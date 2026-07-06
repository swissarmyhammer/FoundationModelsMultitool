import Foundation
import FoundationModels
import FoundationModelsMetadataRegistry
import FoundationModelsRouter
import os

/// A failure from `MultiToolAgent.respond(to:)`'s own loop — never a failure
/// from a wrapped tool or the interpreter (those render as ordinary text via
/// `ResultRenderer` and are fed back into the loop, per plan.md's repair
/// mechanics) — only a failure of the loop's own bounds.
public enum MultiToolAgentError: Error, Sendable, Equatable, CustomStringConvertible {
    /// The loop reached its configured `maxTurns` without the model
    /// producing a `final` step.
    ///
    /// Plan.md M4b: "The loop terminates at max-turns with a typed error,
    /// never spins."
    case maxTurnsExceeded(turns: Int)

    /// The turn format's parse-failure budget (`TurnFormat.maxRepairTurns`)
    /// was exhausted: `turn` consecutive raw responses could not be parsed
    /// into a well-formed `AgentStep`, and `reason` is the last parse
    /// failure's description.
    case unparseableTurn(turn: Int, reason: String)

    /// A human-readable description of the error, satisfying
    /// `CustomStringConvertible`.
    ///
    /// Synthesized per case — unlike this package's other `Error` types,
    /// there is no single underlying `message` to echo verbatim.
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
    /// joining `sessionInstructions`'s sections.
    ///
    /// A single named constant so every call site agrees on the separator's
    /// format.
    private static let transcriptSeparator = "\n\n"

    /// The catalog + live tool instances this agent's `runCode` dispatches
    /// into, and whose `isDirectMode`/`supportsFindAPIs` govern which
    /// actions this agent's instructions offer the model.
    private let registry: MultiTool.Registry

    /// The `runCode` execution core (M4a) this agent dispatches `.runCode`
    /// steps to.
    private let multiTool: MultiTool

    /// The pluggable turn strategy — `.tolerantParse()` (M4b) or `.guided()`
    /// (M4c).
    ///
    /// Selecting either changes only how a turn is encoded/decoded (and, in
    /// the production initializer below, how the main session is built —
    /// see `TurnFormat.grammar`), never this type's loop logic.
    private let turnFormat: any TurnFormat

    /// The bounded turn count `respond(to:)` never exceeds — plan.md M4b:
    /// "under a bounded max-turn count."
    ///
    /// Clamped to at least `1` at init.
    private let maxTurns: Int

    /// Creates the main agent session for one `respond(to:)` call.
    ///
    /// A closure (not a stored session) so the production initializer can
    /// defer creating the real `RoutedSession` until a call actually needs
    /// one, and so a fresh session is used per `respond(to:)` call — each
    /// call is its own conversation, per plan.md's usage example (one
    /// `agent.respond(to:)` per user request).
    private let makeSession: @Sendable () -> any AgentSession

    /// Dispatches every `findAPIs` step to a `MetadataSearcher<APISurface
    /// .Entry>` running in `.selection` mode, or `nil` when this agent has
    /// no librarian configured (plan.md: `librarian: RoutedLLM?`).
    ///
    /// Unlike `makeSession`, not per-call: `MetadataSearcher` is an actor
    /// whose selection tier caches its own root session across calls (the
    /// same prefix-reuse contract Multitool's former `Librarian`
    /// established, generalized by the registry's `SelectionTier`), so the
    /// same `FindAPITool` — wrapping the same searcher — is reused for every
    /// `findAPIs` step across every `respond(to:)` call this agent makes.
    private let findApiTool: FindAPITool?

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
    /// - Throws: whatever `idEnumGrammar(ids:)` throws while deriving the
    ///   selection tier's id-enum grammar — not expected in practice (see
    ///   that function's documentation), and only reachable when
    ///   `librarian` is non-`nil`.
    public init(
        registry: MultiTool.Registry,
        model: RoutedLLM,
        librarian: RoutedLLM? = nil,
        instructions: String,
        configuration: MultiToolConfiguration = .default,
        turnFormat: (any TurnFormat)? = nil,
        maxTurns: Int? = nil
    ) throws {
        let resolvedTurnFormat = turnFormat ?? .tolerantParse(maxRepairTurns: configuration.maxRepairTurns)
        let sessionInstructions = Self.sessionInstructions(
            userInstructions: instructions,
            registry: registry,
            turnFormat: resolvedTurnFormat
        )
        let findApiTool: FindAPITool? =
            if let librarian {
                FindAPITool(
                    searcher: try Self.makeFindApiSearcher(registry: registry, librarian: librarian),
                    limit: registry.surface.entries.count
                )
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
        self.init(
            registry: registry,
            configuration: configuration,
            turnFormat: resolvedTurnFormat,
            maxTurns: maxTurns ?? configuration.maxAgentTurns,
            makeSession: makeSession,
            findApiTool: findApiTool
        )
    }

    /// Builds the `.selection`-mode `MetadataSearcher` backing production
    /// `findAPIs` dispatch: derives an id-enum grammar constraining every
    /// selection session to exactly `registry.surface`'s entry paths (so the
    /// model is structurally incapable of inventing one), and wires
    /// `librarian`'s guided sessions through it.
    ///
    /// Extracted as its own factory — rather than inlined at the production
    /// initializer above — so the gated integration test target can drive
    /// this exact production wiring against a real `RoutedLLM`, not a
    /// reimplementation of it.
    ///
    /// - Parameters:
    ///   - registry: the catalog whose entries become the searcher's
    ///     catalog and whose paths constrain the selection grammar.
    ///   - librarian: the resolved `RoutedLLM` every selection session runs
    ///     on — typically `profile.flash`.
    /// - Returns: a `.selection`-mode `MetadataSearcher` over
    ///   `registry.surface.entries`.
    /// - Throws: whatever `idEnumGrammar(ids:)` throws deriving the
    ///   selection grammar — not expected in practice.
    static func makeFindApiSearcher(
        registry: MultiTool.Registry,
        librarian: RoutedLLM
    ) throws -> MetadataSearcher<APISurface.Entry> {
        let grammar = try idEnumGrammar(ids: registry.surface.entries.map(\.path))
        let selection = SelectionConfig(model: { instructions in
            RoutedAgentSession(session: librarian.makeGuidedSession(grammar, instructions: instructions))
        })
        return MetadataSearcher(items: registry.surface.entries, mode: .selection, selection: selection)
    }

    /// Creates an agent driving a pre-built `AgentSession` (and, optionally,
    /// a pre-built `findAPIs` searcher) directly.
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
    ///   - findApiSearcher: the `.selection`-mode `MetadataSearcher`
    ///     `findAPIs` dispatches to (wrapped in a `FindAPITool`), or `nil` to
    ///     disable `findAPIs` dispatch. A test builds one with a scripted
    ///     `SelectionConfig.model` factory over the internal `AgentSession`
    ///     seam, so `findAPIs` dispatch exercises the searcher's real
    ///     prefix-caching/`fork()`-per-call contract, not a reimplementation
    ///     of it.
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
    init(
        registry: MultiTool.Registry,
        session: any AgentSession,
        findApiSearcher: MetadataSearcher<APISurface.Entry>? = nil,
        instructions: String,
        configuration: MultiToolConfiguration = .default,
        turnFormat: (any TurnFormat)? = nil,
        maxTurns: Int? = nil
    ) {
        let findApiTool = findApiSearcher.map { FindAPITool(searcher: $0, limit: registry.surface.entries.count) }
        self.init(
            registry: registry,
            configuration: configuration,
            turnFormat: turnFormat ?? .tolerantParse(maxRepairTurns: configuration.maxRepairTurns),
            maxTurns: maxTurns ?? configuration.maxAgentTurns,
            makeSession: { session },
            findApiTool: findApiTool
        )
    }

    /// The designated initializer both public-facing initializers above
    /// delegate to, differing only in how `makeSession`/`findApiTool` are
    /// produced (a real `RoutedLLM` vs. a fixed test double).
    private init(
        registry: MultiTool.Registry,
        configuration: MultiToolConfiguration,
        turnFormat: any TurnFormat,
        maxTurns: Int,
        makeSession: @escaping @Sendable () -> any AgentSession,
        findApiTool: FindAPITool?
    ) {
        self.registry = registry
        self.multiTool = MultiTool(registry: registry, configuration: configuration)
        self.turnFormat = turnFormat
        self.maxTurns = max(1, maxTurns)
        self.makeSession = makeSession
        self.findApiTool = findApiTool
    }

    /// Runs the search-then-code loop to answer `prompt`, per this type's
    /// documentation.
    ///
    /// Starts a fresh main session for this call alone; nothing persists
    /// across separate `respond(to:)` calls except `findApiTool`'s own
    /// searcher, whose selection tier's cached root session (plan.md Finding
    /// #6) outlives any single `respond(to:)` call by design. Each turn's
    /// raw response is appended to a running transcript that becomes the
    /// next turn's prompt, since a Router session's `respond(to:)` carries
    /// no memory of its own between calls.
    ///
    /// - Parameter prompt: the user's request.
    /// - Returns: the model's final answer text.
    /// - Throws: `MultiToolAgentError.unparseableTurn` if the turn format's
    ///   repair-turn budget (`TurnFormat.maxRepairTurns`) is exhausted
    ///   before a well-formed turn arrives; `MultiToolAgentError
    ///   .maxTurnsExceeded` if `maxTurns` is reached with no `final` step;
    ///   otherwise whatever the underlying session or `findApiTool` throws.
    public func respond(to prompt: String) async throws -> String {
        let session = makeSession()
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
                let feedback = try await dispatchFindApis(task: task)
                transcript += "\(Self.transcriptSeparator)\(feedback)"
            }
        }

        throw MultiToolAgentError.maxTurnsExceeded(turns: maxTurns)
    }

    // MARK: - findAPIs dispatch

    /// Dispatches one `findAPIs(task)` step: rejects it with an instructive
    /// message when discovery isn't available (direct mode, or no librarian
    /// configured), otherwise forwards `task` to `findApiTool` — which asks
    /// the underlying `MetadataSearcher`'s `.selection` tier (`fork()`-ing
    /// its cached, prefix-rooted session per call under budget, per plan.md
    /// Finding #6, now generalized by the registry's `SelectionTier`) and
    /// formats the selected functions into the text fed back into the
    /// transcript.
    ///
    /// - Parameter task: the plain-language goal the model passed to
    ///   `findAPIs`.
    /// - Returns: the text to feed back to the model as this step's result.
    /// - Throws: whatever `findApiTool.dispatch(task:)` throws.
    private func dispatchFindApis(task: String) async throws -> String {
        guard registry.supportsFindAPIs else {
            return Self.discoveryUnavailableMessage(
                task: task,
                reason: "this agent runs in direct mode (runCode only)"
            )
        }
        guard let findApiTool else {
            return Self.discoveryUnavailableMessage(
                task: task,
                reason: "no librarian is configured for this agent"
            )
        }

        return try await findApiTool.dispatch(task: task)
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
        /// - Parameter supportsFindApis: whether `findAPIs` is also
        ///   surfaced to the model.
        /// - Returns: `runCode`'s full description text.
        static func runCode(supportsFindApis: Bool) -> String {
            let discoveryLine =
                supportsFindApis
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
    }

    /// Assembles the full session instructions for the main agent loop: the
    /// caller's persona/purpose text, the fixed tool-description block
    /// (honoring `registry.isDirectMode`), and the turn format's own
    /// response-shape instructions.
    ///
    /// - Parameters:
    ///   - userInstructions: the caller-supplied persona/purpose text.
    ///   - registry: the catalog this agent's loop dispatches into.
    ///   - turnFormat: the turn strategy in use.
    /// - Returns: the full session instructions.
    private static func sessionInstructions(
        userInstructions: String,
        registry: MultiTool.Registry,
        turnFormat: any TurnFormat
    ) -> String {
        var sections = [
            userInstructions,
            ToolDescriptions.runCode(supportsFindApis: registry.supportsFindAPIs),
        ]
        if registry.supportsFindAPIs {
            sections.append(ToolDescriptions.findAPIs)
        }
        sections.append(
            turnFormat.formatInstructions(supportsFindApis: registry.supportsFindAPIs)
        )
        return sections.joined(separator: Self.transcriptSeparator)
    }
}
