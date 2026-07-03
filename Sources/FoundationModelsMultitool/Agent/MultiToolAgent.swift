import Foundation
import FoundationModels
import FoundationModelsRouter
import os

/// A failure from `MultiToolAgent.respond(to:)`'s own loop — never a failure
/// from a wrapped tool or the interpreter (those render as ordinary text via
/// `ResultRenderer` and are fed back into the loop, per plan.md's repair
/// mechanics) — only a failure of the loop's own bounds.
public enum MultiToolAgentError: Error, Sendable, Equatable, CustomStringConvertible {
    /// The loop reached its configured `maxTurns` without the model
    /// producing a `final` step. Plan.md M4b: "The loop terminates at
    /// max-turns with a typed error, never spins."
    case maxTurnsExceeded(turns: Int)

    /// The turn format's parse-failure budget (`TurnFormat.maxRepairTurns`)
    /// was exhausted: `turn` consecutive raw responses could not be parsed
    /// into a well-formed `AgentStep`, and `reason` is the last parse
    /// failure's description.
    case unparseableTurn(turn: Int, reason: String)

    /// A human-readable description of the error, satisfying
    /// `CustomStringConvertible`. Synthesized per case — unlike this
    /// package's other `Error` types, there is no single underlying
    /// `message` to echo verbatim.
    public var description: String {
        switch self {
        case .maxTurnsExceeded(let turns):
            return "MultiToolAgent exceeded its maximum of \(turns) turn(s) without producing a final answer."
        case .unparseableTurn(let turn, let reason):
            return
                "MultiToolAgent could not parse the model's turn \(turn) response after exhausting its "
                + "repair-turn budget: \(reason)"
        }
    }
}

/// plan.md Component 2b ⭐ — "the tool loop the Router does not provide":
/// binds a built `MultiTool.Registry` to a resolved Router profile's
/// generation slots and runs the search-then-code loop.
///
/// The loop plan.md's Router integration section specifies:
///
/// ```
/// loop:
///   raw = session.respond(to: turnPrompt)          // Router RoutedSession, plain text
///   parse a tool call out of `raw`  ── runCode / findAPIs / final answer
///     · findAPIs(task)  → ask the librarian (guided), splice the returned blocks in
///     · runCode(code)   → JSCInterpreter runs it; tools.X() → native Swift tool.call
///     · final           → return to the caller
///   feed the tool result back as the next turn; repeat
/// ```
///
/// Because `RoutedSession.respond(to:)` carries no memory of earlier calls
/// on its own (each call is bracketed independently against the session's
/// fixed instructions — confirmed against the Router package source, see
/// `AgentSession`'s documentation), `respond(to:)` below drives the loop by
/// accumulating a running transcript text and resending the whole thing as
/// each turn's prompt — the standard shape for a stateless-`respond`
/// generation surface.
///
/// `MultiToolAgent` depends only on the minimal `AgentSession` seam (never
/// `RoutedSession`/`RoutedLLM` directly) for actually talking to a model, so
/// its loop logic is fully unit-testable against a scripted fake with zero
/// GPU; the public initializer below is the only place a real `RoutedLLM`
/// enters the picture, adapting it to that seam via `RoutedAgentSession`.
public struct MultiToolAgent: Sendable {
    /// Where this agent logs its M10 diagnostics — repair turns.
    private static let logger = Logger(subsystem: "FoundationModelsMultitool", category: "MultiToolAgent")

    /// The blank-line separator joining transcript entries — each turn's raw
    /// response, repair instruction, and step result — into the running
    /// transcript `respond(to:)` resends as the next turn's prompt, and
    /// joining `sessionInstructions`'s sections. A single named constant so
    /// every call site agrees on the separator's format.
    private static let transcriptSeparator = "\n\n"

    /// The catalog + live tool instances this agent's `runCode` dispatches
    /// into, and whose `isDirectMode`/`supportsFindAPIs` govern which
    /// actions this agent's instructions offer the model.
    private let registry: MultiTool.Registry

    /// The `runCode` execution core (M4a) this agent dispatches `.runCode`
    /// steps to.
    private let multiTool: MultiTool

    /// The pluggable turn strategy — `.tolerantParse()` (M4b) or `.guided()`
    /// (M4c); selecting either changes only how a turn is encoded/decoded
    /// (and, in the production initializer below, how the main session is
    /// built — see `TurnFormat.grammar`), never this type's loop logic.
    private let turnFormat: any TurnFormat

    /// The bounded turn count `respond(to:)` never exceeds — plan.md M4b:
    /// "under a bounded max-turn count." Clamped to at least `1` at init.
    private let maxTurns: Int

    /// Creates the main agent session for one `respond(to:)` call. A
    /// closure (not a stored session) so the production initializer can
    /// defer creating the real `RoutedSession` until a call actually needs
    /// one, and so a fresh session is used per `respond(to:)` call — each
    /// call is its own conversation, per plan.md's usage example (one
    /// `agent.respond(to:)` per user request).
    private let makeSession: @Sendable () -> any AgentSession

    /// Creates the librarian session `findAPIs` dispatches to, or `nil` when
    /// this agent has no librarian configured (plan.md: `librarian:
    /// RoutedLLM?`). Like `makeSession`, deferred and re-created fresh per
    /// `respond(to:)` call.
    private let makeLibrarianSession: (@Sendable () -> any AgentSession)?

    /// Every *direct* tool this agent's `callTool` step can dispatch to —
    /// plan.md's escape hatch — keyed by `Tool.name`. Empty when this agent
    /// has no direct tools configured (`MultiToolAgent(directTools:)`
    /// defaults to `[]`), in which case `callTool` is never surfaced to the
    /// model (`sessionInstructions` only appends `ToolDescriptions
    /// .callTool` when non-empty) and any `callTool` step the model emits
    /// anyway is rejected the same instructive way an unknown tool name is.
    private let directTools: [String: any Tool]

    /// The seam `DirectToolCall` drives to get schema-valid arguments for
    /// one `callTool` dispatch, or `nil` when no direct tools are configured
    /// (`directTools.isEmpty`) — mirrors `makeLibrarianSession`'s
    /// nil-when-unconfigured shape. Not deferred/per-call like
    /// `makeSession`/`makeLibrarianSession`: `RoutedDirectCallSession` (the
    /// production conformer) is a thin, stateless wrapper over `model`, so
    /// there is no per-call session state to keep fresh.
    private let directCallSession: (any DirectCallSession)?

    /// Creates an agent bound to a resolved Router profile's generation slots.
    ///
    /// Plan.md's "Usage: attaching to a session":
    ///
    /// ```swift
    /// let agent = MultiToolAgent(
    ///     registry: registry,
    ///     model:     profile.standard,
    ///     librarian: profile.flash,
    ///     instructions: "You are a travel assistant. Use runCode to get things done."
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - registry: the catalog + live tool instances to run the loop
    ///     over. `registry.directMode()` surfaces only `runCode` — a
    ///     `findAPIs` step the model emits anyway is rejected with an
    ///     instructive message rather than dispatched (plan.md "Direct
    ///     mode (skip discovery)").
    ///   - model: the resolved `RoutedLLM` this agent's main loop runs on —
    ///     typically `profile.standard`.
    ///   - librarian: the resolved `RoutedLLM` `findAPIs` dispatches to —
    ///     typically `profile.flash`. `nil` disables `findAPIs` dispatch
    ///     even when `registry` isn't in direct mode: a `findAPIs` step is
    ///     then rejected with an instructive message, the same as direct
    ///     mode, rather than a configuration-error trap.
    ///   - instructions: the agent's persona/purpose text.
    ///   - configuration: the M10 hardening knobs this agent's loop and
    ///     `runCode` execution core enforce (execution time limit,
    ///     return/console caps, max agent turns, max repair turns).
    ///     Defaults to `MultiToolConfiguration.default`. An explicitly
    ///     supplied `turnFormat`/`maxTurns` always wins over the
    ///     configuration's corresponding derived default.
    ///   - turnFormat: the turn strategy. Defaults to `nil`, which resolves
    ///     to `.tolerantParse(maxRepairTurns: configuration.maxRepairTurns)`.
    ///   - maxTurns: the bounded turn count `respond(to:)` never exceeds.
    ///     Defaults to `nil`, which resolves to `configuration.maxAgentTurns`.
    ///   - directTools: plan.md's escape hatch — tools this agent calls
    ///     through `callTool`'s guided-generation path (`DirectToolCall`)
    ///     instead of wrapping as `tools.*` in a `runCode` snippet, keeping
    ///     their arguments xgrammar-constrained end to end. Defaults to `[]`
    ///     (no direct tools: `callTool` isn't surfaced to the model at all).
    ///     Every direct call's guided generation runs on `model` — the same
    ///     `RoutedLLM` the main loop runs on — via `RoutedDirectCallSession`.
    public init(
        registry: MultiTool.Registry,
        model: RoutedLLM,
        librarian: RoutedLLM? = nil,
        instructions: String,
        configuration: MultiToolConfiguration = .default,
        turnFormat: (any TurnFormat)? = nil,
        maxTurns: Int? = nil,
        directTools: [any Tool] = []
    ) {
        let resolvedTurnFormat = turnFormat ?? .tolerantParse(maxRepairTurns: configuration.maxRepairTurns)
        let indexedDirectTools = Self.indexDirectTools(directTools)
        let sessionInstructions = Self.sessionInstructions(
            userInstructions: instructions,
            registry: registry,
            turnFormat: resolvedTurnFormat,
            directTools: indexedDirectTools
        )
        let makeLibrarianSession: (@Sendable () -> any AgentSession)? =
            if let librarian {
                {
                    RoutedAgentSession(
                        session: librarian.makeSession(instructions: Self.librarianInstructions(for: registry))
                    )
                }
            } else {
                nil
            }
        let makeSession: @Sendable () -> any AgentSession =
            if let grammar = resolvedTurnFormat.grammar {
                {
                    RoutedAgentSession(
                        session: model.makeGuidedSession(grammar, instructions: sessionInstructions)
                    )
                }
            } else {
                { RoutedAgentSession(session: model.makeSession(instructions: sessionInstructions)) }
            }
        let directCallSession: (any DirectCallSession)? =
            indexedDirectTools.isEmpty ? nil : RoutedDirectCallSession(model: model)
        self.init(
            registry: registry,
            configuration: configuration,
            turnFormat: resolvedTurnFormat,
            maxTurns: maxTurns ?? configuration.maxAgentTurns,
            makeSession: makeSession,
            makeLibrarianSession: makeLibrarianSession,
            directTools: indexedDirectTools,
            directCallSession: directCallSession
        )
    }

    /// Creates an agent driving a pre-built `AgentSession` (and, optionally,
    /// a pre-built librarian `AgentSession`) directly.
    ///
    /// The test-facing entry point plan.md M4b calls for: "the
    /// `AgentSession` seam... so unit tests use a scripted fake with zero
    /// GPU." Not `public`: this seam exists for this package's own test
    /// target (`@testable import`), never for a library consumer, who
    /// always goes through the `RoutedLLM`-based initializer above.
    ///
    /// - Parameters:
    ///   - registry: the catalog + live tool instances to run the loop
    ///     over.
    ///   - session: the main agent session to drive.
    ///   - librarianSession: the librarian session `findAPIs` dispatches
    ///     to, or `nil` to disable `findAPIs` dispatch.
    ///   - instructions: the agent's persona/purpose text.
    ///   - configuration: the M10 hardening knobs this agent's loop and
    ///     `runCode` execution core enforce. Defaults to
    ///     `MultiToolConfiguration.default`. An explicitly supplied
    ///     `turnFormat`/`maxTurns` always wins over the configuration's
    ///     corresponding derived default.
    ///   - turnFormat: the turn strategy. Defaults to `nil`, which resolves
    ///     to `.tolerantParse(maxRepairTurns: configuration.maxRepairTurns)`.
    ///   - maxTurns: the bounded turn count `respond(to:)` never exceeds.
    ///     Defaults to `nil`, which resolves to `configuration.maxAgentTurns`.
    ///   - directTools: plan.md's escape hatch — tools this agent calls
    ///     through `callTool`'s guided-generation path. Defaults to `[]`.
    ///   - directCallSession: the scripted `DirectCallSession` fake
    ///     `callTool` dispatches through, or `nil` to disable `callTool`
    ///     dispatch even when `directTools` is non-empty (a `callTool` step
    ///     is then rejected with an instructive message, the same
    ///     configuration-gap posture `makeLibrarianSession == nil` takes
    ///     toward `findAPIs`). Defaults to `nil`.
    init(
        registry: MultiTool.Registry,
        session: any AgentSession,
        librarianSession: (any AgentSession)? = nil,
        instructions: String,
        configuration: MultiToolConfiguration = .default,
        turnFormat: (any TurnFormat)? = nil,
        maxTurns: Int? = nil,
        directTools: [any Tool] = [],
        directCallSession: (any DirectCallSession)? = nil
    ) {
        let makeLibrarianSession: (@Sendable () -> any AgentSession)? =
            if let librarianSession {
                { librarianSession }
            } else {
                nil
            }
        self.init(
            registry: registry,
            configuration: configuration,
            turnFormat: turnFormat ?? .tolerantParse(maxRepairTurns: configuration.maxRepairTurns),
            maxTurns: maxTurns ?? configuration.maxAgentTurns,
            makeSession: { session },
            makeLibrarianSession: makeLibrarianSession,
            directTools: Self.indexDirectTools(directTools),
            directCallSession: directCallSession
        )
    }

    /// The designated initializer both public-facing initializers above
    /// delegate to, differing only in how `makeSession`/`makeLibrarianSession`
    /// are produced (a real `RoutedLLM` vs. a fixed test double).
    private init(
        registry: MultiTool.Registry,
        configuration: MultiToolConfiguration,
        turnFormat: any TurnFormat,
        maxTurns: Int,
        makeSession: @escaping @Sendable () -> any AgentSession,
        makeLibrarianSession: (@Sendable () -> any AgentSession)?,
        directTools: [String: any Tool],
        directCallSession: (any DirectCallSession)?
    ) {
        self.registry = registry
        self.multiTool = MultiTool(registry: registry, configuration: configuration)
        self.turnFormat = turnFormat
        self.maxTurns = max(1, maxTurns)
        self.makeSession = makeSession
        self.makeLibrarianSession = makeLibrarianSession
        self.directTools = directTools
        self.directCallSession = directCallSession
    }

    /// Indexes `tools` by `Tool.name` for `directTools`'s dispatch lookup —
    /// shared by both public-facing initializers.
    ///
    /// Duplicate names keep the *first* occurrence, the same
    /// `uniquingKeysWith` posture `ArgumentMarshaler.marshalArguments` takes
    /// toward its own dictionary construction: `MultiToolAgent` is not a
    /// validating catalog builder like `MultiTool.Builder` (which throws on
    /// a genuine name collision), so a caller-supplied duplicate degrades
    /// gracefully rather than failing `init`.
    ///
    /// - Parameter tools: the direct tools to index.
    /// - Returns: `tools` keyed by `Tool.name`.
    private static func indexDirectTools(_ tools: [any Tool]) -> [String: any Tool] {
        Dictionary(tools.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Runs the search-then-code loop to answer `prompt`, per this type's
    /// documentation.
    ///
    /// Starts a fresh main session (and, lazily, a fresh librarian session
    /// on first `findAPIs` dispatch) for this call alone; nothing persists
    /// across separate `respond(to:)` calls. Each turn's raw response is
    /// appended to a running transcript that becomes the next turn's
    /// prompt, since a Router session's `respond(to:)` carries no memory of
    /// its own between calls.
    ///
    /// - Parameter prompt: the user's request.
    /// - Returns: the model's final answer text.
    /// - Throws: `MultiToolAgentError.unparseableTurn` if the turn format's
    ///   repair-turn budget (`TurnFormat.maxRepairTurns`) is exhausted
    ///   before a well-formed turn arrives; `MultiToolAgentError
    ///   .maxTurnsExceeded` if `maxTurns` is reached with no `final` step;
    ///   otherwise whatever the underlying session or librarian session
    ///   throws.
    public func respond(to prompt: String) async throws -> String {
        let session = makeSession()
        var librarianSession: (any AgentSession)?
        var transcript = "User request:\n\(prompt)"
        var repairsUsed = 0

        for turnNumber in 1...maxTurns {
            try Task.checkCancellation()
            let raw = try await session.respond(to: transcript)
            transcript += "\(Self.transcriptSeparator)\(raw)"

            let step: AgentStep
            do {
                step = try turnFormat.parseTurn(raw)
            } catch {
                repairsUsed += 1
                Self.logger.notice(
                    "Turn \(turnNumber, privacy: .public) unparseable (repair \(repairsUsed, privacy: .public) of \(turnFormat.maxRepairTurns, privacy: .public)): \(String(describing: error), privacy: .public)"
                )
                guard repairsUsed <= turnFormat.maxRepairTurns else {
                    throw MultiToolAgentError.unparseableTurn(turn: turnNumber, reason: String(describing: error))
                }
                transcript += "\(Self.transcriptSeparator)\(turnFormat.repairInstruction(for: error))"
                continue
            }

            // A well-formed turn resets the budget: `TurnFormat.maxRepairTurns`
            // is documented as *consecutive* parse failures, so a later,
            // unrelated parse hiccup gets its own fresh budget rather than
            // being charged against an earlier, already-recovered-from one.
            repairsUsed = 0

            switch step {
            case .final(let text):
                return text

            case .runCode(let code):
                let result = try await multiTool.call(arguments: RunCodeArguments(code: code))
                transcript += "\(Self.transcriptSeparator)runCode result:\n\(result)"

            case .findAPIs(let task):
                let feedback = try await dispatchFindAPIs(task: task, librarianSession: &librarianSession)
                transcript += "\(Self.transcriptSeparator)\(feedback)"

            case .callTool(let name, let task):
                let feedback = try await dispatchCallTool(name: name, task: task)
                transcript += "\(Self.transcriptSeparator)\(feedback)"
            }
        }

        throw MultiToolAgentError.maxTurnsExceeded(turns: maxTurns)
    }

    // MARK: - findAPIs dispatch

    /// Dispatches one `findAPIs(task)` step: rejects it with an instructive
    /// message when discovery isn't available (direct mode, or no librarian
    /// configured), otherwise forwards `task` to the (lazily created,
    /// reused-for-this-call) librarian session and returns its response as
    /// the text to feed back into the transcript.
    ///
    /// The librarian's instructions (set once, at session creation — see
    /// `librarianInstructions(for:)`) already carry the full rendered
    /// surface as plan.md's "prefix-cached" librarian prompt, so only
    /// `task` itself is sent as the per-call prompt.
    ///
    /// - Parameters:
    ///   - task: the plain-language goal the model passed to `findAPIs`.
    ///   - librarianSession: the call's librarian session, created on first
    ///     use and reused for any further `findAPIs` steps in the same
    ///     `respond(to:)` call.
    /// - Returns: the text to feed back to the model as this step's result.
    /// - Throws: whatever the librarian session's `respond(to:)` throws.
    private func dispatchFindAPIs(
        task: String,
        librarianSession: inout (any AgentSession)?
    ) async throws -> String {
        guard registry.supportsFindAPIs else {
            return Self.discoveryUnavailableMessage(
                task: task,
                reason: "this agent runs in direct mode (runCode only)"
            )
        }
        guard let makeLibrarianSession else {
            return Self.discoveryUnavailableMessage(
                task: task,
                reason: "no librarian is configured for this agent"
            )
        }

        let session = librarianSession ?? makeLibrarianSession()
        librarianSession = session
        let raw = try await session.respond(to: task)
        return "findAPIs(\"\(task)\") found:\n\(raw)"
    }

    /// The instructive rejection fed back to the model when it emits a
    /// `findAPIs` step this agent can't dispatch (plan.md M4b acceptance:
    /// "directMode: findAPIs from the model is rejected with an instructive
    /// message").
    ///
    /// - Parameters:
    ///   - task: the plain-language goal the model passed to `findAPIs`.
    ///   - reason: why discovery isn't available.
    /// - Returns: the rejection text to feed back into the transcript.
    private static func discoveryUnavailableMessage(task: String, reason: String) -> String {
        """
        findAPIs is not available: \(reason). Use help()/docs(name) inside a runCode \
        snippet to discover functions instead. (You asked to find APIs for: "\(task)")
        """
    }

    // MARK: - callTool dispatch (plan.md's escape hatch)

    /// Dispatches one `callTool(name, task)` step: rejects an unknown
    /// direct-tool name, or a `callTool` step this agent can't dispatch at
    /// all (no direct tools configured, or none supplied a guided-call
    /// session), with an instructive message — never a crash — otherwise
    /// runs `DirectToolCall.call` and renders its outcome.
    ///
    /// Mirrors `MultiTool.call`'s own posture toward a `runCode` failure:
    /// every failure this function's own pipeline can produce (an unknown
    /// tool name, a schema-derivation failure, a guided-session failure, a
    /// malformed guided output, a pre-call validation failure, or the direct
    /// tool's own thrown error) is rendered as **repairable text** fed back
    /// into the transcript rather than propagated out of `respond(to:)` —
    /// only `CancellationError` propagates unchanged, so cancelling the
    /// `Task` running `respond(to:)` still reaches a `callTool` dispatch in
    /// flight.
    ///
    /// - Parameters:
    ///   - name: the direct tool's name the model passed to `callTool`.
    ///   - task: the plain-language description of the arguments to use the
    ///     model passed to `callTool`.
    /// - Returns: the text to feed back to the model as this step's result.
    /// - Throws: `CancellationError` if the calling `Task` is cancelled.
    private func dispatchCallTool(name: String, task: String) async throws -> String {
        try Task.checkCancellation()
        guard let tool = directTools[name] else {
            return Self.unknownDirectToolMessage(name: name, known: directTools.keys.sorted())
        }
        guard let directCallSession else {
            return Self.directCallUnavailableMessage(name: name)
        }
        do {
            let output = try await DirectToolCall.call(tool, task: task, using: directCallSession)
            let rendered = try ArgumentMarshaler.renderOutput(output)
            return "callTool(\"\(name)\") result:\n\(ResultRenderer.serialize(rendered))"
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch {
            return "callTool(\"\(name)\") failed: \(error)\(Self.transcriptSeparator)Fix the request and call callTool again."
        }
    }

    /// The instructive rejection fed back to the model when it emits
    /// `callTool` naming a tool this agent doesn't recognize — plan.md
    /// acceptance criterion: "Unknown direct-tool name from the model → a
    /// repairable error, not a crash."
    ///
    /// - Parameters:
    ///   - name: the unrecognized direct-tool name the model passed to
    ///     `callTool`.
    ///   - known: every direct tool name this agent does recognize, for a
    ///     helpful listing.
    /// - Returns: the rejection text to feed back into the transcript.
    private static func unknownDirectToolMessage(name: String, known: [String]) -> String {
        guard !known.isEmpty else {
            return "callTool(\"\(name)\") failed: no direct tools are registered."
        }
        return "callTool(\"\(name)\") failed: unknown direct tool. Known direct tools: \(known.joined(separator: ", "))."
    }

    /// The instructive rejection fed back to the model when `callTool`
    /// can't be dispatched at all because no guided-call session is
    /// configured — the `callTool` analogue of `discoveryUnavailableMessage`'s
    /// "no librarian is configured" case.
    ///
    /// - Parameter name: the direct tool name the model passed to `callTool`.
    /// - Returns: the rejection text to feed back into the transcript.
    private static func directCallUnavailableMessage(name: String) -> String {
        "callTool(\"\(name)\") failed: no guided-call session is configured for this agent's direct tools."
    }

    // MARK: - Instructions assembly

    /// The fixed `runCode`/`findAPIs` description strings the loop teaches
    /// the model — plan.md § "The two tools, as the main model sees them":
    /// "These two `description`s *are* the prompt that makes the model
    /// search-then-code — fixed strings, not per-tool."
    private enum ToolDescriptions {
        /// `runCode`'s description — plan.md's fixed instruction block, with
        /// one line that varies by whether `findAPIs` is also surfaced:
        /// direct mode (plan.md "Direct mode (skip discovery)") points the
        /// model at in-snippet `help()`/`docs()` instead of a `findAPIs`
        /// step that doesn't exist.
        ///
        /// - Parameter supportsFindAPIs: whether `findAPIs` is also
        ///   surfaced to the model.
        /// - Returns: `runCode`'s full description text.
        static func runCode(supportsFindAPIs: Bool) -> String {
            let discoveryLine =
                supportsFindAPIs
                ? "Call findAPIs first to learn exact signatures, or help()/docs(name) in-snippet."
                : "Use help()/docs(name) in-snippet to discover available functions and their signatures."
            return """
                runCode(code: string)
                  Run a JavaScript snippet against the available tools, exposed as functions under
                  `tools.*`. Compose calls with normal code — variables, loops, map/filter — and
                  `return` the final value (only that comes back; intermediates stay private).
                  \(discoveryLine)
                  Errors are returned to you to fix and retry.
                """
        }

        /// `findAPIs`'s description, included only when `registry
        /// .supportsFindAPIs`.
        static let findAPIs = """
            findAPIs(task: string)
              Describe, in plain language, what you are trying to accomplish. Returns the few
              tool-functions relevant to that task — each with its typed signature, purpose,
              and a runnable example — so you can write a runCode snippet. Prefer this over
              guessing function names.
            """

        /// `callTool`'s description — plan.md's escape hatch — included only
        /// when this agent has at least one direct tool configured
        /// (`directTools` non-empty). Lists each direct tool's name and
        /// description so the model knows they exist and roughly what they
        /// do; unlike `runCode`'s `tools.*` surface, no typed signature is
        /// rendered here — the arguments themselves are produced separately,
        /// under a grammar derived from the called tool's own schema, so the
        /// main model only ever needs to describe its *intent* via `args`,
        /// never the literal argument shape.
        ///
        /// - Parameter directTools: this agent's direct tools, keyed by name.
        /// - Returns: `callTool`'s full description text.
        static func callTool(directTools: [String: any Tool]) -> String {
            let listing =
                directTools
                .values
                .sorted { $0.name < $1.name }
                .map { "  - \($0.name): \($0.description)" }
                .joined(separator: "\n")
            return """
                callTool(name: string, args: string)
                  Call one of the direct tools listed below with a schema-valid argument
                  guarantee: unlike runCode's tools.*, its arguments are generated separately
                  under a grammar derived from that tool's own schema, so they can never be
                  malformed. Give the tool's exact name and, in args, describe in plain
                  language what you want the call to accomplish — never the literal argument
                  values themselves.
                Available direct tools:
                \(listing)
                """
        }
    }

    /// Assembles the full session instructions for the main agent loop: the
    /// caller's persona/purpose text, the fixed tool-description block
    /// (honoring `registry.isDirectMode` and whether any direct tools are
    /// configured), and the turn format's own response-shape instructions.
    ///
    /// - Parameters:
    ///   - userInstructions: the caller-supplied persona/purpose text.
    ///   - registry: the catalog this agent's loop dispatches into.
    ///   - turnFormat: the turn strategy in use.
    ///   - directTools: this agent's direct tools, keyed by name — plan.md's
    ///     escape hatch.
    /// - Returns: the full session instructions.
    private static func sessionInstructions(
        userInstructions: String,
        registry: MultiTool.Registry,
        turnFormat: any TurnFormat,
        directTools: [String: any Tool]
    ) -> String {
        var sections = [
            userInstructions,
            ToolDescriptions.runCode(supportsFindAPIs: registry.supportsFindAPIs),
        ]
        if registry.supportsFindAPIs {
            sections.append(ToolDescriptions.findAPIs)
        }
        if !directTools.isEmpty {
            sections.append(ToolDescriptions.callTool(directTools: directTools))
        }
        sections.append(
            turnFormat.formatInstructions(
                supportsFindAPIs: registry.supportsFindAPIs,
                supportsDirectCall: !directTools.isEmpty
            )
        )
        return sections.joined(separator: Self.transcriptSeparator)
    }

    /// Assembles the librarian's instructions — plan.md § "The librarian's
    /// assembled prompt (concrete)": curated selection guidance followed by
    /// every tool's rendered block, set once as the session's instructions
    /// so only the per-call `task` needs to be sent as the prompt.
    ///
    /// - Parameter registry: the catalog whose rendered surface
    ///   (`registry.surface.source`) becomes the librarian's prefix.
    /// - Returns: the librarian's full session instructions.
    private static func librarianInstructions(for registry: MultiTool.Registry) -> String {
        """
        You are an API librarian. Given a task, return ONLY the functions needed — fewest
        that suffice, in call order when order matters. Do not invent functions; return an
        empty list if nothing fits.

        # Available functions
        \(registry.surface.source)
        """
    }
}
