import Foundation
import FoundationModelsRouter

// MARK: - The ambient sandbox globals (eventplan.md § "The sandbox globals")
//
// Six globals beyond `tools.*`/`help()`/`docs()`, installed unconditionally
// into every `runCode` sandbox by the same `HostFunction`/`AsyncHostFunction`
// mechanism `help()`/`docs()` use, and built by the same
// `makeHelpDocsHostFunctions`-style factories:
//
// - `status()`, `wait()`, `cancel()` — the run plane. Envelopes and outcomes
//   only, read from the session's own `SessionMailbox`; never a capability's
//   bulk output.
// - `elicit()` — a question for the user in the middle of a snippet, parked
//   through `ToolContext.elicit` exactly as a wrapped tool's own elicitation
//   is.
// - `notify()`, `progress()` — enqueue-and-continue notices (see
//   `SandboxNoticeOutbox`).
//
// The one-rule contract (eventplan.md § "Async JavaScript") decides which
// mechanism each uses: "each call that goes into Swift effects returns a
// promise… these calls are synchronous: `help()` and `docs()`… and
// `notify()` / `progress()`." So the first four are `AsyncHostFunction`s and
// the last two are `HostFunction`s — and nothing else about them differs.
//
// None of the six is a `searchTools` entry. A search result implies an item that
// can be found or be absent; these are always present. `MultiTool
// .description` is therefore where the model learns they exist — but it
// carries only that pointer. The contract itself is read on demand, through
// `docs("globals")` or `docs(<one global's name>)`, which is `help()`/`docs()`
// — the discovery path a snippet already has for the wrapped tools — rather
// than a second mechanism built alongside it (see "MARK: - The docs() page").
//
// **No ambient context is a supported mode, not an error.** A `MultiTool`
// constructed and called directly — outside any session, which is how every
// unit suite in this package runs — has no run plane at all. The four
// promise-returning globals then reject with ``SandboxGlobalError/noRunPlane``,
// a named, model-repairable rejection, and `notify()`/`progress()` are silent
// no-ops (consistent with a nil-context `ToolContext.post`). None of the six
// traps.

/// The `state` discriminator every run-plane global stamps on the object it
/// hands back, so a snippet branches on one field rather than on which keys
/// happen to be present.
/// Internal rather than file-private since task `h773bed`: the `wait` **tool**
/// reports a settled run with the same state names the sandbox globals do, and
/// restating the strings there would let two spellings of "settled" drift.
enum RunPlaneState {
    /// The run is registered with the mailbox and has not settled.
    static let parked = "parked"

    /// The run finished; the object carries its terminal event.
    static let settled = "settled"

    /// A `wait()` deadline expired with the run still parked.
    static let deadlineElapsed = "deadlineElapsed"

    /// The mailbox knows no run — parked or settled — under this token.
    static let unknownToken = "unknownToken"

    /// A `cancel()` reached the run's canceler, which reported an outcome.
    static let reported = "reported"

    /// A `cancel()` arrived after the run had already finished.
    static let alreadySettled = "alreadySettled"
}

/// The deadline a lifecycle lookup gives the mailbox: none at all.
///
/// `SessionMailbox.wait(completionToken:seconds:)` resolves immediately for a
/// settled or unknown token and reports `deadlineElapsed` for a parked one, so
/// a zero-second wait is the mailbox's own lifecycle probe — it never suspends
/// the calling snippet.
private let lifecycleProbeSeconds: Double = 0

/// The usage sentence every malformed `elicit()` call is repaired with —
/// shared by both of ``SandboxGlobalError``'s elicitation cases so a snippet
/// is told the same shape either way.
private let elicitUsage = """
    elicit("question") takes a question string, or a request object — \
    elicit({ message, requestedSchema }) for a form, \
    elicit({ message, url }) for a URL flow.
    """

/// One ambient global's `docs(name)` entry.
///
/// Rendered in the same shape ``APISurface/Entry/block`` gives a wrapped tool
/// — a banner naming the call, a JSDoc comment, and a `declare function`
/// signature — so a snippet that reads `docs("elicit")` and
/// `docs("getWeather")` reads one format for both.
private struct SandboxGlobalDoc: Sendable {
    /// The name a snippet calls this global under, which is also the
    /// `docs(name)` key that resolves this entry.
    let name: String

    /// This global's rendered documentation block.
    let block: String
}

extension MultiTool {
    /// The two synchronous, void globals — `notify()` and `progress()`.
    ///
    /// Named here rather than inline because `makePreamble(for:)` re-binds
    /// each one to a JS wrapper that returns nothing, and the two sites must
    /// agree (see ``makeNoticeHostFunctions(outbox:)`` for why the wrapper
    /// exists).
    static let voidGlobalNames = ["notify", "progress"]

    // MARK: - The docs() page: the contract, reached on demand

    /// The `docs(name)` topic the whole ambient-globals page is filed under.
    ///
    /// `MultiTool.description` names this topic instead of restating the
    /// contract. What a model needs upfront is that the globals exist and
    /// where to read them; the detail costs nothing until a snippet asks for
    /// it, which is the same lazy shape `searchTools`/`docs()` already give the
    /// wrapped tools. Naming the topic here keeps the pointer and the lookup
    /// on one constant.
    static let sandboxGlobalsDocsTopic = "globals"

    /// The whole ambient-globals page — what `docs("globals")` hands back.
    ///
    /// The preface followed by every global's block, separated by a blank
    /// line, exactly as ``APISurface/source`` concatenates the wrapped tools'
    /// blocks.
    static var sandboxGlobalsPage: String {
        ([sandboxGlobalsPreface] + sandboxGlobalDocs.map(\.block)).joined(separator: "\n\n")
    }

    /// The documentation `docs(name)` answers `name` with, when `name` is the
    /// globals topic or one global's own name.
    ///
    /// - Parameter name: the name a `docs(name)` call asked for.
    /// - Returns: the whole page for the topic, one global's block for a
    ///   global's name, or `nil` when `name` is neither.
    static func sandboxGlobalsDocumentation(for name: String) -> String? {
        if name == sandboxGlobalsDocsTopic {
            return sandboxGlobalsPage
        }
        return sandboxGlobalDocs.first { $0.name == name }?.block
    }

    /// The page's preface: what the ambient globals are, the one rule saying
    /// which of them a snippet awaits, and the object shapes the run plane
    /// and `elicit()` hand back.
    ///
    /// Every `state` value is spliced from ``RunPlaneState`` rather than
    /// retyped, so the documented discriminator and the one the globals
    /// really stamp cannot drift apart.
    ///
    /// Kept tight on purpose: the whole page has to fit inside `runCode`'s
    /// own return cap (``ResultRendererLimits/returnValueCharacterLimit``),
    /// or the snippet that asked for it reads a truncated contract. Facts a
    /// snippet already learns at the moment it needs them — chiefly the
    /// no-run-plane rejection, which ``SandboxGlobalError/noRunPlane``
    /// states in full — belong there rather than here.
    private static let sandboxGlobalsPreface = """
        // globals
        /**
         * The ambient globals every snippet already has, beyond `tools.*`.
         * They are installed in every runCode sandbox, so they never appear
         * in a searchTools result and nothing has to be discovered before
         * calling them. Await the four that return a promise; `notify()` and
         * `progress()` return nothing, so never await those.
         */
        declare type ParkedRun = { state: "\(RunPlaneState.parked)"; completionToken: string; tool: string; op: string; kind: string; latestProgress: string | null };
        declare type SettledRun = { state: "\(RunPlaneState.settled)" | "\(RunPlaneState.alreadySettled)"; completionToken: string; tool: string; op: string; detail: string; outcome: string | null };
        declare type UnresolvedRun = { state: "\(RunPlaneState.deadlineElapsed)" | "\(RunPlaneState.unknownToken)"; completionToken: string };
        declare type CancelReport = { state: "\(RunPlaneState.reported)"; completionToken: string; outcome: string };
        declare type ElicitationAnswer = { action: string; content: object | null };
        """

    /// Every ambient global's `docs(name)` entry, in the order the preface
    /// introduces them — the run plane, the elicitation, then the two notice
    /// calls.
    ///
    /// No `@param` trailers, unlike ``APISurface/Entry/block``: a wrapped
    /// tool's `args` fields carry meaning only its author's `@Guide` prose
    /// states, whereas each global's own parameter is named and typed in the
    /// declaration right below. Repeating it would spend the page's budget
    /// (see ``sandboxGlobalsPreface``) on text the reader already has.
    private static let sandboxGlobalDocs: [SandboxGlobalDoc] = [
        SandboxGlobalDoc(
            name: "status",
            block: """
                // status
                /**
                 * Reports what this session's long-running calls are doing. With no argument it
                 * lists every run still parked; with a completion token — the token a
                 * long-running call handed back — it reports that one run.
                 * @returns Promise<ParkedRun[] | ParkedRun | SettledRun | UnresolvedRun> — read `state` to tell the shapes apart.
                 * @example const parked = await status();
                 */
                declare function status(completionToken?: string): Promise<ParkedRun[] | ParkedRun | SettledRun | UnresolvedRun>;
                """
        ),
        SandboxGlobalDoc(
            name: "wait",
            block: """
                // wait
                /**
                 * Waits up to `seconds` for one long-running call to finish, then reports its
                 * terminal event — the run's identifier and its bounded output tail, never a
                 * tool's whole output. A deadline that passes with the run still parked reports
                 * `\(RunPlaneState.deadlineElapsed)` rather than failing.
                 * @returns Promise<SettledRun | UnresolvedRun> — read `state` to tell them apart.
                 * @example const settled = await wait(token, 30);
                 */
                declare function wait(completionToken: string, seconds: number): Promise<SettledRun | UnresolvedRun>;
                """
        ),
        SandboxGlobalDoc(
            name: "cancel",
            block: """
                // cancel
                /**
                 * Asks one long-running call to stop, and reports the outcome its own canceler
                 * reported — verbatim, never a guess. A run that already finished reports its
                 * retained terminal event instead.
                 * @returns Promise<CancelReport | SettledRun | UnresolvedRun> — read `state` to tell them apart.
                 * @example const stopped = await cancel(token);
                 */
                declare function cancel(completionToken: string): Promise<CancelReport | SettledRun | UnresolvedRun>;
                """
        ),
        SandboxGlobalDoc(
            name: "elicit",
            block: """
                // elicit
                /**
                 * Asks the user a question in the middle of a snippet, and resolves to their
                 * answer. \(elicitUsage)
                 * @returns Promise<ElicitationAnswer> — `content` is null when the user declined or cancelled, so read `action` first.
                 * @example const answer = await elicit("Which repository should I target?");
                 */
                declare function elicit(request: string | { message: string; requestedSchema?: object; url?: string }): Promise<ElicitationAnswer>;
                """
        ),
        SandboxGlobalDoc(
            name: "notify",
            block: """
                // notify
                /**
                 * Tells the user what is happening. The notice is enqueued and the snippet keeps
                 * running; the run delivers the chain when it ends. A structured `detail` is
                 * reported as JSON.
                 * @returns void — nothing comes back, so never await it.
                 * @example notify("starting the sweep");
                 */
                declare function notify(detail: string | object): void;
                """
        ),
        SandboxGlobalDoc(
            name: "progress",
            block: """
                // progress
                /**
                 * Reports how far along the snippet is, on the run's own progress channel.
                 * Enqueued and delivered exactly as `notify()` is.
                 * @returns void — nothing comes back, so never await it.
                 * @example progress("3 of 8 cities done");
                 */
                declare function progress(detail: string | object): void;
                """
        ),
    ]

    // MARK: - The run plane: status(), wait(), cancel(), and elicit()

    /// Builds the four promise-returning ambient globals for one `runCode`
    /// invocation.
    ///
    /// Per invocation rather than per registry, for exactly the reason
    /// `makeAsyncHostFunctions(binding:)` is: each closure captures `binding`,
    /// because the `Task` the promise pump starts for it lands outside every
    /// task tree and can inherit no ambient context (see `RunBinding`).
    ///
    /// - Parameter binding: this `runCode` invocation's captured session
    ///   binding, or `nil` when it has none — in which case every one of the
    ///   four rejects with ``SandboxGlobalError/noRunPlane``.
    /// - Returns: four async host functions, named `"status"`, `"wait"`,
    ///   `"cancel"`, and `"elicit"`.
    static func makeRunPlaneHostFunctions(binding: RunBinding?) -> [AsyncHostFunction] {
        [
            AsyncHostFunction(name: "status") { arguments in
                try await reportStatus(of: arguments.first, binding: binding)
            },
            AsyncHostFunction(name: "wait") { arguments in
                try await awaitSettlement(arguments, binding: binding)
            },
            AsyncHostFunction(name: "cancel") { arguments in
                try await requestCancellation(of: arguments.first, binding: binding)
            },
            AsyncHostFunction(name: "elicit") { arguments in
                try await raiseElicitation(arguments.first, binding: binding)
            },
        ]
    }

    /// The captured session context the run plane reads, or a repairable
    /// rejection when this invocation has none.
    ///
    /// - Parameter binding: the invocation's captured binding.
    /// - Returns: the session context.
    /// - Throws: ``SandboxGlobalError/noRunPlane`` when `binding` is `nil`.
    private static func sessionContext(from binding: RunBinding?) throws -> ToolContext {
        guard let binding else { throw SandboxGlobalError.noRunPlane }
        return binding.context
    }

    /// `status()`'s implementation: with no argument, every pending run in the
    /// session's mailbox; with a completion token, that one run's lifecycle.
    ///
    /// - Parameters:
    ///   - argument: the call's first argument — a completion-token string,
    ///     or absent/`null` to list every pending run.
    ///   - binding: the invocation's captured session binding.
    /// - Returns: an array of parked-run rows, or one lifecycle object.
    /// - Throws: ``SandboxGlobalError/noRunPlane`` when the run has no session
    ///   context; ``SandboxGlobalError/malformedCompletionToken(usage:)`` when
    ///   the argument is present but is not a string.
    private static func reportStatus(
        of argument: InterpreterValue?,
        binding: RunBinding?
    ) async throws -> InterpreterValue {
        let context = try sessionContext(from: binding)
        guard let token = try optionalCompletionToken(argument, usage: "status(completionToken)") else {
            return .array(await context.parkedRuns().map { .object(parkedRunFields(of: $0)) })
        }
        return await lifecycle(of: token, in: context)
    }

    /// One run's lifecycle: parked, settled, or unknown.
    ///
    /// - Parameters:
    ///   - token: the run's completion token.
    ///   - context: the session context the run plane is read through.
    /// - Returns: the lifecycle object.
    private static func lifecycle(of token: String, in context: ToolContext) async -> InterpreterValue {
        if let parked = await context.parkedRuns().first(where: { $0.completionToken == token }) {
            return .object(parkedRunFields(of: parked))
        }
        // Not parked in the snapshot above, so the run either already settled
        // — the mailbox retains its terminal event — or the token names
        // nothing at all. A zero-second wait separates exactly those two
        // without suspending.
        switch await context.wait(completionToken: token, seconds: lifecycleProbeSeconds) {
        case .settled(let terminal):
            return .object(terminalEventFields(of: terminal, state: RunPlaneState.settled))
        case .unknownToken:
            return .object(tokenOnlyFields(state: RunPlaneState.unknownToken, token: token))
        case .deadlineElapsed:
            // The run parked between the snapshot and the probe. Re-read it,
            // so the reported row carries the same fields a parked run always
            // does rather than a partial one.
            let parked = await context.parkedRuns().first { $0.completionToken == token }
            guard let parked else {
                return .object(tokenOnlyFields(state: RunPlaneState.unknownToken, token: token))
            }
            return .object(parkedRunFields(of: parked))
        }
    }

    /// `wait()`'s implementation: awaits one run's settlement with a deadline
    /// and reports the terminal event — the run's identifier plus its bounded
    /// output tail — never a capability's full store.
    ///
    /// - Parameters:
    ///   - arguments: the call's arguments: a completion-token string and a
    ///     number of seconds.
    ///   - binding: the invocation's captured session binding.
    /// - Returns: the settled, deadline-elapsed, or unknown-token object.
    /// - Throws: ``SandboxGlobalError/noRunPlane`` when the run has no session
    ///   context; ``SandboxGlobalError/malformedCompletionToken(usage:)`` or
    ///   ``SandboxGlobalError/missingWaitDeadline`` when an argument is
    ///   missing or of the wrong kind.
    private static func awaitSettlement(
        _ arguments: [InterpreterValue],
        binding: RunBinding?
    ) async throws -> InterpreterValue {
        let context = try sessionContext(from: binding)
        let token = try completionToken(arguments.first, usage: "wait(completionToken, seconds)")
        guard case .number(let seconds)? = arguments.dropFirst().first else {
            throw SandboxGlobalError.missingWaitDeadline
        }
        switch await context.wait(completionToken: token, seconds: seconds) {
        case .settled(let terminal):
            return .object(terminalEventFields(of: terminal, state: RunPlaneState.settled))
        case .deadlineElapsed:
            return .object(tokenOnlyFields(state: RunPlaneState.deadlineElapsed, token: token))
        case .unknownToken:
            return .object(tokenOnlyFields(state: RunPlaneState.unknownToken, token: token))
        }
    }

    /// `cancel()`'s implementation: invokes the run's own canceler and reports
    /// the outcome it reported — verbatim, never a guess.
    ///
    /// - Parameters:
    ///   - argument: the call's first argument: a completion-token string.
    ///   - binding: the invocation's captured session binding.
    /// - Returns: the reported, already-settled, or unknown-token object.
    /// - Throws: ``SandboxGlobalError/noRunPlane`` when the run has no session
    ///   context; ``SandboxGlobalError/malformedCompletionToken(usage:)`` when
    ///   the argument is not a string.
    private static func requestCancellation(
        of argument: InterpreterValue?,
        binding: RunBinding?
    ) async throws -> InterpreterValue {
        let context = try sessionContext(from: binding)
        let token = try completionToken(argument, usage: "cancel(completionToken)")
        switch await context.cancel(completionToken: token) {
        case .reported(let outcome):
            return .object([
                "state": .string(RunPlaneState.reported),
                "completionToken": .string(token),
                "outcome": .string(outcome.rawValue),
            ])
        case .alreadySettled(let terminal):
            return .object(terminalEventFields(of: terminal, state: RunPlaneState.alreadySettled))
        case .unknownToken:
            return .object(tokenOnlyFields(state: RunPlaneState.unknownToken, token: token))
        }
    }

    // MARK: - Run-plane rendering

    /// The JS-visible fields of one parked run — the row `status()` lists and
    /// the object `status(completionToken)` reports for a run still in flight.
    ///
    /// - Parameter run: the mailbox's own snapshot row.
    /// - Returns: the object's fields.
    private static func parkedRunFields(of run: ParkedRun) -> [String: InterpreterValue] {
        [
            "state": .string(RunPlaneState.parked),
            "completionToken": .string(run.completionToken),
            "tool": .string(run.tool),
            "op": .string(run.op),
            "kind": .string(run.kind.rawValue),
            "latestProgress": run.latestProgressDetail.map { .string($0) } ?? .null,
        ]
    }

    /// The JS-visible fields of a run's terminal event — its identifier, the
    /// bounded output tail the mailbox already capped, and its honest outcome.
    ///
    /// - Parameters:
    ///   - terminal: the terminal event.
    ///   - state: the ``RunPlaneState`` this event is being reported under.
    /// - Returns: the object's fields.
    /// Internal rather than file-private since task `h773bed`: the `wait`
    /// **tool** reports a settled run through this same builder, so a run reads
    /// identically however it was collected.
    static func terminalEventFields(
        of terminal: OperationEvent,
        state: String
    ) -> [String: InterpreterValue] {
        [
            "state": .string(state),
            "completionToken": .string(terminal.correlationID),
            "tool": .string(terminal.tool),
            "op": .string(terminal.op),
            "detail": .string(terminal.detail),
            "outcome": terminal.outcome.map { .string($0.rawValue) } ?? .null,
        ]
    }

    /// The JS-visible fields of an outcome that carries nothing but the token
    /// it was asked about — an unknown token, or an elapsed deadline.
    ///
    /// - Parameters:
    ///   - state: the ``RunPlaneState`` being reported.
    ///   - token: the completion token the call named.
    /// - Returns: the object's fields.
    /// Internal rather than file-private since task `h773bed`: the `wait` **tool**
    /// reports an unknown token and an elapsed bound through this same builder.
    static func tokenOnlyFields(state: String, token: String) -> [String: InterpreterValue] {
        ["state": .string(state), "completionToken": .string(token)]
    }

    /// Reads a required completion-token argument.
    ///
    /// - Parameters:
    ///   - argument: the call's argument.
    ///   - usage: the call shape named in the repair message.
    /// - Returns: the token.
    /// - Throws: ``SandboxGlobalError/malformedCompletionToken(usage:)`` when
    ///   `argument` is missing or is not a string.
    private static func completionToken(_ argument: InterpreterValue?, usage: String) throws -> String {
        guard case .string(let token)? = argument else {
            throw SandboxGlobalError.malformedCompletionToken(usage: usage)
        }
        return token
    }

    /// Reads an optional completion-token argument, treating an absent or
    /// `null` argument as "no token given".
    ///
    /// - Parameters:
    ///   - argument: the call's argument.
    ///   - usage: the call shape named in the repair message.
    /// - Returns: the token, or `nil` when none was given.
    /// - Throws: ``SandboxGlobalError/malformedCompletionToken(usage:)`` when
    ///   `argument` is present but is not a string.
    private static func optionalCompletionToken(_ argument: InterpreterValue?, usage: String) throws -> String? {
        guard let argument, argument != .null else { return nil }
        return try completionToken(argument, usage: usage)
    }

    // MARK: - elicit()

    /// `elicit()`'s implementation: parks the snippet on the session's mailbox
    /// through `ToolContext.elicit` — the same elevation path every other
    /// elicitor takes — and resumes with the user's answer.
    ///
    /// - Parameters:
    ///   - argument: the call's first argument: a question string, or a
    ///     request object.
    ///   - binding: the invocation's captured session binding.
    /// - Returns: the answer, as `{ action, content }` — `content` is `null`
    ///   for a decline or a cancel, so a snippet can read `action` and
    ///   `content` without either being absent.
    /// - Throws: ``SandboxGlobalError/noRunPlane`` when the run has no session
    ///   context; ``SandboxGlobalError/malformedElicitationRequest`` or
    ///   ``SandboxGlobalError/undecodableElicitationRequest(reason:)`` when the
    ///   argument is not a request this boundary accepts.
    private static func raiseElicitation(
        _ argument: InterpreterValue?,
        binding: RunBinding?
    ) async throws -> InterpreterValue {
        let context = try sessionContext(from: binding)
        let request = try makeElicitationRequest(from: argument)
        return renderElicitationResponse(try await context.elicit(request))
    }

    /// Builds the typed request one `elicit()` call raises.
    ///
    /// A bare string is the shorthand eventplan.md § "The sandbox globals"
    /// shows (`await elicit("Which repository should I target?")`): a
    /// form-mode request with a message and no fields to fill in. An object
    /// carries the full restricted MCP shape, decoded by Router's own
    /// `ElicitationRequestedSchema` so this boundary enforces exactly the
    /// subset every other elicitor does — a snippet cannot widen it.
    ///
    /// The `elicitationId` is minted here, never taken from the snippet: it is
    /// the key the mailbox parks the continuation under, and a snippet-chosen
    /// id could collide with a pending one.
    ///
    /// - Parameter argument: the call's first argument.
    /// - Returns: the typed request.
    /// - Throws: ``SandboxGlobalError/malformedElicitationRequest`` when the
    ///   argument is neither a question string nor an object with a `message`;
    ///   ``SandboxGlobalError/undecodableElicitationRequest(reason:)`` when its
    ///   `url` is not a URL or its `requestedSchema` is outside the subset.
    private static func makeElicitationRequest(from argument: InterpreterValue?) throws -> ElicitationRequest {
        let elicitationId = ULID()
        if case .string(let question)? = argument {
            return ElicitationRequest(
                message: question,
                elicitationId: elicitationId,
                requestedSchema: ElicitationRequestedSchema(properties: [:])
            )
        }
        guard case .object(let fields)? = argument, case .string(let message)? = fields["message"] else {
            throw SandboxGlobalError.malformedElicitationRequest
        }
        if case .string(let urlText)? = fields["url"] {
            guard let url = URL(string: urlText) else {
                throw SandboxGlobalError.undecodableElicitationRequest(reason: "\"\(urlText)\" is not a URL")
            }
            return ElicitationRequest(message: message, elicitationId: elicitationId, url: url)
        }
        return ElicitationRequest(
            message: message,
            elicitationId: elicitationId,
            requestedSchema: try decodeRequestedSchema(fields["requestedSchema"])
        )
    }

    /// Decodes a form request's `requestedSchema` through Router's own
    /// `Codable` conformance, so the restricted MCP subset is enforced by the
    /// one implementation that defines it.
    ///
    /// - Parameter value: the `requestedSchema` field, or `nil`/`null` for a
    ///   message-only form — the same request the string shorthand produces.
    /// - Returns: the decoded schema.
    /// - Throws: ``SandboxGlobalError/undecodableElicitationRequest(reason:)``
    ///   when the value is outside the subset.
    private static func decodeRequestedSchema(_ value: InterpreterValue?) throws -> ElicitationRequestedSchema {
        guard let value, value != .null else {
            return ElicitationRequestedSchema(properties: [:])
        }
        do {
            return try JSONDecoder().decode(
                ElicitationRequestedSchema.self,
                from: try JSONEncoder().encode(value)
            )
        } catch {
            throw SandboxGlobalError.undecodableElicitationRequest(reason: "\(error)")
        }
    }

    /// Renders the user's answer for the snippet.
    ///
    /// `content` is always present — `null` rather than absent for a decline
    /// or a cancel — so the three actions are told apart by `action` alone and
    /// reading `content` never trips over an undefined property.
    ///
    /// - Parameter response: the user's answer.
    /// - Returns: the JS-visible answer object.
    private static func renderElicitationResponse(_ response: ElicitationResponse) -> InterpreterValue {
        .object([
            "action": .string(response.action.rawValue),
            "content": response.content.map { .object($0.mapValues(renderElicitationValue)) } ?? .null,
        ])
    }

    /// Converts one elicitation content value to its JS-visible equivalent.
    ///
    /// - Parameter value: the answered value.
    /// - Returns: the equivalent interpreter value.
    private static func renderElicitationValue(_ value: ElicitationValue) -> InterpreterValue {
        switch value {
        case .string(let text): .string(text)
        case .number(let number): .number(number)
        case .boolean(let flag): .bool(flag)
        case .stringArray(let items): .array(items.map { .string($0) })
        }
    }

    // MARK: - notify() / progress()

    /// Builds the two synchronous, void ambient globals for one `runCode`
    /// invocation.
    ///
    /// Both enqueue onto `outbox` and return at once — the snippet keeps
    /// running, and `MultiTool.call(arguments:)` flushes the chain once the
    /// run ends (see `SandboxNoticeOutbox`). A `nil` outbox is the
    /// no-ambient-context mode: both are silent no-ops, the same thing a
    /// `nil`-context `ToolContext.post` already is.
    ///
    /// The snippet-visible call expression evaluates to `undefined`, not to
    /// these functions' returned value: `makePreamble(for:)` re-binds each
    /// name to a JS wrapper that discards it. `InterpreterValue` — the seam
    /// every `HostFunction` result crosses — is JSON-shaped and has no
    /// `undefined` case, so `.null` here would cross back as JS `null`, an
    /// observably different value from the `undefined` a void call must
    /// produce. Building that shape in JS is the same move `tools.*` itself
    /// makes for the same reason (see "tools.* glue").
    ///
    /// - Parameter outbox: the invocation's notice outbox, or `nil` when it
    ///   has no session context.
    /// - Returns: two host functions, named `"notify"` and `"progress"`.
    static func makeNoticeHostFunctions(outbox: SandboxNoticeOutbox?) -> [HostFunction] {
        [
            HostFunction(name: "notify") { arguments in
                enqueue(.notify(noticeDetail(of: arguments.first)), on: outbox)
            },
            HostFunction(name: "progress") { arguments in
                enqueue(.progress(noticeDetail(of: arguments.first)), on: outbox)
            },
        ]
    }

    /// Enqueues one notice, if this invocation has an outbox to enqueue it on.
    ///
    /// - Parameters:
    ///   - notice: the notice to enqueue.
    ///   - outbox: the invocation's notice outbox, or `nil`.
    /// - Returns: `.null`, which the JS wrapper described in
    ///   ``makeNoticeHostFunctions(outbox:)`` discards.
    private static func enqueue(_ notice: SandboxNotice, on outbox: SandboxNoticeOutbox?) -> InterpreterValue {
        outbox?.enqueue(notice)
        return .null
    }

    /// Reads a notice's detail text from the call's argument.
    ///
    /// A string is used as-is; a structured value is rendered as JSON so
    /// `progress({ done: 3 })` reports something a user can read rather than
    /// being silently dropped; nothing at all reports an empty detail.
    ///
    /// - Parameter argument: the call's first argument.
    /// - Returns: the detail text.
    private static func noticeDetail(of argument: InterpreterValue?) -> String {
        guard let argument else { return "" }
        switch argument {
        case .null:
            return ""
        case .string(let detail):
            return detail
        case .bool, .number, .array, .object:
            let json = (try? JSONEncoder().encode(argument)) ?? Data()
            return String(decoding: json, as: UTF8.self)
        }
    }
}

/// A failure one of the four promise-returning ambient globals reports back to
/// the snippet as its promise's rejection reason.
///
/// Every case's ``description`` is written for the model to repair from: it
/// says what was wrong and what shape to call instead. `JSCInterpreter` already
/// prefixes a rejection with the global's own name (`"<name>: <reason>"`), so
/// no case repeats it.
enum SandboxGlobalError: Error, Equatable, CustomStringConvertible {
    /// The enclosing `runCode` invocation captured no ambient `ToolContext`,
    /// so there is no session mailbox to read and no user to ask — a
    /// `MultiTool` constructed and called directly, outside any session.
    case noRunPlane

    /// A completion-token argument was missing or was not a string.
    case malformedCompletionToken(usage: String)

    /// `wait()` was called without a number of seconds to wait.
    case missingWaitDeadline

    /// `elicit()`'s argument was neither a question string nor an object
    /// carrying a `message`.
    case malformedElicitationRequest

    /// `elicit()`'s request object could not be read into the restricted MCP
    /// elicitation subset.
    case undecodableElicitationRequest(reason: String)

    /// A human-readable description of the failure, satisfying
    /// `CustomStringConvertible`.
    ///
    /// This is the text that reaches the snippet as its promise's rejection
    /// reason, so every case is phrased as repair instructions for the model
    /// rather than as a diagnosis for a human reader.
    var description: String {
        switch self {
        case .noRunPlane:
            return "no session context — this run has no run plane. status(), wait(), cancel(), and "
                + "elicit() reach the session that issued this run, and this one has none. Drop them "
                + "and return the value from the tool calls you already made."
        case .malformedCompletionToken(let usage):
            return "\(usage) needs a completion-token string — the token a long-running call handed "
                + "back. Call status() with no argument to list every pending run's token."
        case .missingWaitDeadline:
            return "wait(completionToken, seconds) needs a number of seconds to wait, "
                + "e.g. await wait(token, 30)."
        case .malformedElicitationRequest:
            return elicitUsage
        case .undecodableElicitationRequest(let reason):
            return "\(reason). \(elicitUsage)"
        }
    }
}
