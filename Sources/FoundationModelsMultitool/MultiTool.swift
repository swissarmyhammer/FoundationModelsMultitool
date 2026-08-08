import Foundation
import FoundationModels
import FoundationModelsMetadataRegistry
import FoundationModelsRouter
import os

extension MultiTool {
    /// The built, executable artifact `MultiTool.Builder.buildRegistry()`
    /// produces — plan.md's "registry" (the value the "Adding tools is the
    /// easy path" usage sample assigns `Builder.build()`'s result to, and
    /// that `MultiTool.init(registry:)` and `FindAPIsTool
    /// .init(registry:librarian:limit:)` both take): the rendered
    /// `APISurface` (M2.5) paired with the actual
    /// wrapped `any Tool` instances a `runCode` snippet's `tools.*` calls
    /// dispatch to.
    ///
    /// `APISurface` alone can't drive execution — by its own design (see
    /// `APISurface`'s documentation) it is "pure data: no model wiring, no
    /// rendering logic of its own beyond composing already-rendered pieces,"
    /// carrying only each tool's rendered *descriptor*, never the tool object
    /// itself. `Registry` is the pairing that closes that gap for M4a: every
    /// entry in `surface.entries` has a fully-qualified `path` (`"getWeather"`,
    /// `"github.createIssue"`, …), and `tools[path]` is that entry's live
    /// `any Tool` to invoke.
    public struct Registry: Sendable {
        /// The rendered, model-agnostic catalog — declarations, doc comments,
        /// and examples only (M2.5). Backs the registry-backed selection
        /// tier's instruction prefix (`FoundationModelsMetadataRegistry`) and
        /// `help()`/`docs()` (M6/M7); carries no tool instances of its own.
        public let surface: APISurface

        /// Every wrapped tool, keyed by its fully-qualified snippet call path
        /// (`surface.entries`'s own `path`, e.g. `"getWeather"` or
        /// `"github.createIssue"`) — the pairing `MultiTool` uses to bind
        /// each `tools.*` entry point to a live `any Tool` to invoke via
        /// `ToolInvoker`.
        public let tools: [String: any Tool]

        /// Whether this registry surfaces only `runCode` — plan.md's "direct
        /// mode": discovery (`findAPIs`) is skipped, and a snippet is
        /// expected to introspect the surface itself via `help()`/`docs()`
        /// (M7) instead. `false` (the default) surfaces both `runCode` and
        /// `findAPIs` to the session's tool-calling loop (M4b/M6).
        public let isDirectMode: Bool

        /// Creates a registry pairing a rendered surface with its live tool
        /// instances.
        ///
        /// Explicit for the same reason as `APISurface.init`/
        /// `ToolDescriptor.init`: a `public` struct's synthesized initializer
        /// is only `internal`-accessible, and `Registry` is a public type of
        /// the `FoundationModelsMultitool` library product a caller must be
        /// able to construct directly.
        ///
        /// - Parameters:
        ///   - surface: the rendered, model-agnostic catalog.
        ///   - tools: every wrapped tool, keyed by `surface.entries`'s own
        ///     `path`. `MultiTool.Builder.buildRegistry()` always keeps the
        ///     two in agreement; a path present in `surface` with no
        ///     matching key here simply has no live dispatch target — the
        ///     generated `tools.<path>` binding resolves to `undefined` in
        ///     the sandbox rather than crash (plan.md's "throw/degrade,
        ///     never trap" posture, mirrored throughout this package).
        ///   - isDirectMode: whether this registry is in direct mode
        ///     (`runCode` only). Defaults to `false`.
        public init(surface: APISurface, tools: [String: any Tool], isDirectMode: Bool = false) {
            self.surface = surface
            self.tools = tools
            self.isDirectMode = isDirectMode
        }

        /// Returns a copy of this registry in **direct mode** — plan.md
        /// "Direct mode (skip discovery)": only `runCode` is surfaced to
        /// the session; a snippet is expected to introspect the surface
        /// itself via `help()`/`docs()` (M7) rather than a `findAPIs` round
        /// trip. The executable surface itself (`surface`/`tools`) is
        /// unchanged — only the affordance metadata (`isDirectMode`,
        /// `affordances`, `supportsFindAPIs`) flips.
        ///
        /// - Returns: a copy of this registry with `isDirectMode` set to
        ///   `true`.
        public func directMode() -> Registry {
            Registry(surface: surface, tools: tools, isDirectMode: true)
        }

        /// The session-facing operations this registry surfaces —
        /// `["runCode"]` in direct mode, `["runCode", "findAPIs"]`
        /// otherwise. Plain, checkable metadata for a caller (or a test) to
        /// read without having to separately know `isDirectMode`'s exact
        /// semantics.
        public var affordances: [String] {
            isDirectMode ? ["runCode"] : ["runCode", "findAPIs"]
        }

        /// Whether this registry surfaces `findAPIs` discovery — `false` in
        /// direct mode, `true` otherwise.
        public var supportsFindAPIs: Bool {
            !isDirectMode
        }
    }
}

/// The arguments `MultiTool`'s `runCode` call accepts: the JavaScript
/// snippet to run against `tools.*`, and the two clocks that bound it.
///
/// The clocks are the envelope half of eventplan.md § "Consolidation of the
/// siblings" — `waitSeconds` bounds how long the *caller* waits,
/// ``timeout`` bounds how long the *work* runs — and reach the elevation
/// engine through `MultiTool`'s `ElevationParameterProviding` conformance
/// (see `MultiTool+Elevation.swift`). Both are optional: a call that supplies
/// only `code` runs on the host's own defaults, exactly as every `runCode`
/// call did before the clocks existed.
@Generable
public struct RunCodeArguments {
    /// The JavaScript snippet to run against `tools.*`.
    @Guide(
        description: "JavaScript snippet to run against the available tools, exposed as functions "
            + "under `tools.*`. Compose calls with normal code — variables, loops, map/filter — and "
            + "`return` the final value; only that value (and any console output) comes back."
    )
    public var code: String

    /// How long this call may block before it elevates, in seconds, or `nil`
    /// to leave the wait clock to the host's mount. `0` detaches immediately;
    /// nothing resets this clock.
    @Guide(
        description: "Optional. How many seconds to wait for this snippet before it hands back a "
            + "pending completion token and keeps running in the background; follow it up with "
            + "status(), wait(), or cancel(). Nothing resets this clock, and 0 detaches at once. "
            + "Omit it to use the host's own default."
    )
    public var waitSeconds: Double?

    /// How long this snippet's own work may run, in seconds, or `nil` to
    /// leave the work clock to the host's configuration. Progress resets this
    /// per-call clock, and the host clamps it to its own ceiling.
    ///
    /// The ceiling itself is absolute. `MultiTool.init` arms the watchdog of
    /// whatever sandbox it runs — the one it builds for itself and one a
    /// caller injects as its `interpreter:`, alike — from
    /// `configuration.executionTimeLimit`, and that watchdog measures from
    /// sandbox creation and nothing resets it: not progress, and not parking
    /// on `elicit()`. Progress therefore buys time only up to that ceiling,
    /// never past it. The same ceiling clamps this per-call clock (see
    /// `MultiToolConfiguration.executionTimeLimit`).
    @Guide(
        description: "Optional. How many seconds the snippet's own work may run before it is "
            + "cancelled. Progress resets this clock, so a snippet that keeps reporting keeps "
            + "running — but only up to the host's ceiling, which is absolute: it is measured "
            + "from the moment the snippet starts, and nothing extends it. "
            + "Omit it to use the host's own default; the host caps it at its configured ceiling."
    )
    public var timeout: Double?

    /// Creates `runCode`'s arguments with the given snippet and clocks.
    ///
    /// Explicit for the same reason as every other public `@Generable`
    /// type's initializer in this package (e.g. `ToolDescriptor.init`): a
    /// `public` struct's synthesized memberwise initializer is only
    /// `internal`-accessible.
    ///
    /// - Parameters:
    ///   - code: the JavaScript snippet to run.
    ///   - waitSeconds: how long the call may block before it elevates, or
    ///     `nil` to leave that to the host's mount.
    ///   - timeout: how long the snippet's own work may run, or `nil` to
    ///     leave that to the host's configuration.
    public init(code: String, waitSeconds: Double? = nil, timeout: Double? = nil) {
        self.code = code
        self.waitSeconds = waitSeconds
        self.timeout = timeout
    }
}

/// plan.md Component 1 ⭐ — the `runCode` `Tool`: the execution half of the
/// MultiTool idea, "a single `Tool`... that wraps other, in-process `Tool`s
/// and exposes them to the model as a callable code API." Conforms to
/// `FoundationModels.Tool`, so it registers directly on a native
/// `LanguageModelSession(tools: [multiTool, findAPIsTool])` and Apple's own
/// tool-calling loop decides when to call it (the hand-rolled
/// `MultiToolAgent` ReAct loop that used to drive it is retired).
///
/// Per call, `call(arguments:)`:
/// 1. builds `tools.*` glue that assigns every registry entry's real,
///    wrapped tool to its fully-qualified snippet path (flat `tools.<name>`
///    for a standalone tool, nested `tools.<group>.<name>` for a grouped
///    one — plan.md Resolved #5) — see "tools.* glue" below;
/// 2. runs the glue followed by the snippet in a fresh `Interpreter` sandbox
///    (M1) off the calling thread (see "Off-cooperative-thread dispatch"),
///    with `help()`/`docs()` and the six ambient globals of eventplan.md §
///    "The sandbox globals" — `status()`, `wait()`, `cancel()`, `elicit()`,
///    `notify()`, `progress()`, see `MultiTool+SandboxGlobals.swift` — also
///    installed;
/// 3. renders the result — or a thrown `InterpreterError` — via
///    `ResultRenderer` (M5).
///
/// Each `tools.X(...)` call is an `AsyncHostFunction`: the interpreter's own
/// promise pump (eventplan.md "Async JavaScript") installs it as a JS
/// function returning a `Promise`, starts the wrapped tool's real, async
/// `call(arguments:)` in its own Swift `Task`, and settles that promise when
/// the `Task` completes — see `invokeAsync`'s documentation for the full
/// dispatch.
public struct MultiTool: Tool {
    /// This tool's `Tool`-protocol name, always `"runCode"`.
    public let name = "runCode"
    /// This tool's `Tool`-protocol description, presented to the model as
    /// usage instructions for `runCode`.
    ///
    /// Together with `FindAPIsTool.description`, deliberately carries the
    /// whole behavioral contract a session needs — the package must be
    /// drop-in usable with no bespoke system prompt. `findAPIs` owns the
    /// access framing and the search-then-snippet workflow; this side owns
    /// the error-recovery contract: fix and immediately re-call on error,
    /// never stop at an error to narrate, never claim an outcome no
    /// snippet actually returned.
    ///
    /// The ambient globals are the one part deliberately *not* carried here.
    /// This text is read on every turn, alongside every tool schema, so
    /// everything in it competes with the findAPIs-first instruction for the
    /// model's attention — and the globals are the part a snippet needs only
    /// once it is already writing a snippet. So this names them and where to
    /// read them, and `docs("globals")` hands back the contract on demand
    /// (see `MultiTool+SandboxGlobals.swift`, "MARK: - The docs() page").
    public let description = """
        Run a JavaScript snippet against the user's real tools, exposed as functions \
        under `tools.*`. Always call findAPIs first to discover the exact functions and \
        their signatures for the task (or help()/docs(name) in a snippet); never guess \
        function names. Every `tools.*` call returns a promise: await each `tools.*` \
        call; use `Promise.all` to run calls in parallel. Then compose calls with normal \
        code — variables, loops, map/filter — and `return` the final value (only that \
        comes back; intermediates stay private). Read each discovered function's \
        declared return type and destructure it accordingly. These tools genuinely \
        execute and return real data: \
        answer only from what they return — never answer data questions from your own \
        knowledge, and never simulate or invent data in a snippet. If a snippet fails, \
        the error comes back for you to repair: fix the snippet and call runCode again \
        immediately — never stop at an error to describe or apologize for what you were \
        going to do, and never claim success for a call a snippet did not actually \
        return. Beyond `tools.*` a few ambient globals are always there and never appear \
        in findAPIs — for asking the user something mid-snippet, reporting what is \
        happening, and following up on a long-running call. Run `docs("globals")` in a \
        snippet to read them.
        """

    /// Where this tool logs its M10 diagnostics — one `runCode` call's
    /// start/end, and each `tools.*` invocation's start/end/validation
    /// failure — and, at `.notice`, every imagined `tools.*` name a snippet
    /// reached for (see `logImaginedTool(_:)`).
    private static let logger = Logger(subsystem: "FoundationModelsMultitool", category: "MultiTool")

    /// The catalog + live tool instances this `runCode` dispatches into.
    private let registry: Registry

    /// The M10 hardening knobs this tool enforces. Internal, not `private`,
    /// because the elevation extension reads the work clock's ceiling out of
    /// it (see `MultiTool+Elevation.swift`).
    let configuration: MultiToolConfiguration

    /// How many of this tool's `runCode` contexts are live right now, capped
    /// at `configuration.liveContextLimit` — see ``LiveContextCounter``.
    private let liveContexts: LiveContextCounter

    /// The sandbox this tool runs every snippet in. `any Interpreter` (not
    /// `JSCInterpreter` directly) so a test can substitute a fake — matching
    /// `Interpreter`'s own stated purpose ("the engine is swappable without
    /// touching callers").
    private let interpreter: any Interpreter

    /// The size caps `ResultRenderer` enforces on this tool's rendered
    /// output.
    private let limits: ResultRendererLimits

    /// `help()`/`docs()`'s `HostFunction` bridges — the *surface-reading*
    /// synchronous globals this tool installs (see "MARK: - help()/docs()
    /// globals" below; `notify()`/`progress()` are synchronous too, but are
    /// built per invocation because each closes over that invocation's own
    /// notice outbox) — built once at `init` time (stable for the registry's
    /// lifetime — installing them is cheap and the mapping never changes
    /// call to call) and re-installed fresh into every `runCode` call's own
    /// sandbox by `Interpreter.run`.
    private let hostFunctions: [HostFunction]

    /// The catalog ranker `UnknownToolHint` resolves an invented `tools.*`
    /// name against when no real path resembles its spelling.
    ///
    /// The same `MetadataSearcher` machinery `findAPIs` matches an intent to
    /// tools with, over this registry's own entries, in `.retrieval` mode: no
    /// selection tier and no embedder, so repairing a wrong guess costs no
    /// model call and no tokens. Built once at `init` for the same reason as
    /// `hostFunctions`/`liveTools` — it depends only on the registry, which
    /// never changes over this tool's lifetime.
    private let hintSearcher: MetadataSearcher<APISurface.Entry>

    /// Every registry entry that has a live tool to dispatch to, paired with
    /// the flat host-function name its `tools.*` binding installs under —
    /// precomputed once at `init` time for the same reason as
    /// `hostFunctions`: it depends only on `registry`, which never changes.
    ///
    /// The `AsyncHostFunction`s built from it deliberately are *not*
    /// precomputed: each one closes over the invocation's own `RunBinding`
    /// (eventplan.md "Async JavaScript": one binding per `runCode`
    /// invocation, captured at bind time and never inherited), so
    /// `makeAsyncHostFunctions(binding:)` rebuilds them per call from this
    /// stable pairing.
    private let liveTools: [LiveTool]

    /// The `tools.*` assignment glue prepended to every snippet — see
    /// "tools.* glue" below. Precomputed once at `init` time for the same
    /// reason as `hostFunctions`/`liveTools`: it depends only on
    /// `registry.surface`, which never changes.
    private let preamble: String

    /// Creates a `runCode` tool over `registry`.
    ///
    /// - Parameters:
    ///   - registry: the catalog + live tool instances to expose as
    ///     `tools.*`.
    ///   - configuration: the M10 hardening knobs (the work clock's ceiling,
    ///     the live-context cap, return/console caps) this tool enforces.
    ///     Defaults to `MultiToolConfiguration.default`. Ignored for
    ///     whichever of `interpreter`/`limits` is explicitly supplied instead
    ///     of left `nil` — an explicit override always wins over the
    ///     configuration's corresponding derived value.
    ///   - interpreter: the sandbox to run every snippet in. Defaults to a
    ///     fresh `JSCInterpreter`. Whichever sandbox is used, it is armed
    ///     here with `configuration.executionTimeLimit` — the work clock's
    ///     ceiling, and the only clock the interpreter itself owns (see
    ///     `MultiToolConfiguration.executionTimeLimit`) — so an injected
    ///     interpreter runs under the configured ceiling rather than
    ///     whatever its own constructor received.
    ///   - limits: the size caps `ResultRenderer` enforces on this tool's
    ///     rendered output. Defaults to `configuration.resultLimits`.
    public init(
        registry: Registry,
        configuration: MultiToolConfiguration = .default,
        interpreter: (any Interpreter)? = nil,
        limits: ResultRendererLimits? = nil
    ) {
        self.registry = registry
        self.configuration = configuration
        self.liveContexts = LiveContextCounter()
        // One arming path for every sandbox this tool runs, injected or
        // built here: the configured ceiling always wins, so a caller who
        // passes a `JSCInterpreter()` never silently gets that interpreter's
        // own stock limit instead (see `Interpreter.withTimeLimit(_:)`).
        self.interpreter = (interpreter ?? JSCInterpreter()).withTimeLimit(configuration.executionTimeLimit)
        self.limits = limits ?? configuration.resultLimits
        self.hostFunctions = Self.makeHelpDocsHostFunctions(for: registry)
        self.liveTools = Self.makeLiveTools(for: registry)
        self.preamble = Self.makePreamble(for: registry)
        self.hintSearcher = MetadataSearcher(items: registry.surface.entries, mode: .retrieval)
    }

    /// Runs `arguments.code` against `tools.*` and renders the outcome.
    ///
    /// Never throws for an ordinary snippet failure — a thrown
    /// `InterpreterError` (a JS exception, syntax error, or watchdog
    /// timeout) is caught here and rendered as `ResultRenderer`'s
    /// repairable-error text instead, per plan.md: "Errors are returned to
    /// you to fix and retry." A cancelled enclosing `Task`, however, is never
    /// rendered as text — plan.md M10: cancelling the task running this call
    /// "terminates the in-flight snippet... and propagates
    /// `CancellationError`" — so `CancellationError` always propagates
    /// unchanged.
    ///
    /// A call that would push this tool past `configuration
    /// .liveContextLimit` never reaches the sandbox at all: it renders the
    /// same repairable error text instead, naming the cap and the run-plane
    /// globals that collect a parked snippet (see ``LiveContextCounter``).
    ///
    /// - Parameter arguments: the snippet to run, and the clocks bounding it.
    /// - Returns: the rendered `runCode` result — the snippet's return
    ///   value (plus any captured console output) on success, or a
    ///   repairable error description on failure.
    /// - Throws: `CancellationError` if the calling `Task` is cancelled
    ///   before or during the run; otherwise only a failure this tool cannot
    ///   itself render as text — e.g. `interpreter.run` failing for a reason
    ///   other than `InterpreterError`/`CancellationError` (not reachable
    ///   through `JSCInterpreter`, kept as a defensive passthrough for any
    ///   other `Interpreter` conformer).
    public func call(arguments: RunCodeArguments) async throws -> String {
        try Task.checkCancellation()
        guard liveContexts.claim(upTo: configuration.liveContextLimit) else {
            return ResultRenderer.render(Self.liveContextCapError(limit: configuration.liveContextLimit))
        }
        defer { liveContexts.release() }
        // Captured here, and only here: this is the last point on the route
        // where the session's ambient `ToolContext` is still reachable. Every
        // `tools.*` call below runs in a `Task` the interpreter's promise pump
        // starts from a JSC callback, outside every task tree, where
        // `ToolContext.current` is `nil` — see `RunBinding`.
        let binding = RunBinding.ambient
        // One notice chain per invocation, for the same reason: `notify()`
        // and `progress()` post through the captured context, never an
        // inherited one. `nil` when this run has no session — both globals
        // are then silent no-ops.
        let notices = binding.map { SandboxNoticeOutbox(context: $0.context) }
        let code = "\(preamble)\n\(arguments.code)"
        let outcome = await Self.runCapturingOutcome(
            code: code,
            installing: hostFunctions + Self.makeNoticeHostFunctions(outbox: notices),
            installingAsync: makeAsyncHostFunctions(binding: binding)
                + Self.makeRunPlaneHostFunctions(binding: binding),
            using: interpreter
        )
        // "They enqueue and continue; the bridge flushes them" — the flush,
        // before this call hands anything back, so a run's last notice never
        // reaches the session after the run's own result does. On the failure
        // path too: a notice a snippet already made happened, whatever the
        // snippet went on to do.
        await notices?.flush()
        switch outcome {
        case .success(let result):
            return ResultRenderer.render(result, limits: limits)
        case .failure(let interpreterError as InterpreterError):
            let resolution = await UnknownToolHint.hint(
                message: interpreterError.message,
                // `arguments.code`, never `code`: the preamble prepended above
                // spells out every real `tools.*` path, so handing the glue to
                // a rule that asks what the *model* reached for would find a
                // real path every time.
                snippet: arguments.code,
                surface: registry.surface,
                searcher: hintSearcher
            )
            if let resolution {
                Self.logImaginedTool(resolution)
            }
            return ResultRenderer.render(
                interpreterError,
                hint: resolution?.text,
                directive: resolution?.directive ?? .repairSnippet
            )
        case .failure(let error):
            throw error
        }
    }

    // MARK: - Off-cooperative-thread dispatch

    /// Runs one snippet and captures its outcome instead of throwing it, so
    /// `call(arguments:)` can flush the invocation's notice chain on both the
    /// success and the failure path before deciding what to hand back.
    ///
    /// - Parameters:
    ///   - code: the JavaScript source to run.
    ///   - installing: the synchronous host functions to expose as globals.
    ///   - installingAsync: the asynchronous host functions to expose as
    ///     globals.
    ///   - interpreter: the sandbox to run `code` in.
    /// - Returns: the run's result, or the error
    ///   `run(code:installing:installingAsync:using:)` threw.
    private static func runCapturingOutcome(
        code: String,
        installing: [HostFunction],
        installingAsync: [AsyncHostFunction],
        using interpreter: any Interpreter
    ) async -> Result<InterpreterResult, Error> {
        do {
            return .success(
                try await run(
                    code: code,
                    installing: installing,
                    installingAsync: installingAsync,
                    using: interpreter
                )
            )
        } catch {
            return .failure(error)
        }
    }

    /// Runs `interpreter.run(code:installing:)` — a synchronous, blocking
    /// call — without blocking the calling `async` context's own
    /// cooperative-pool thread for its duration.
    ///
    /// `Interpreter.run` already guarantees it never runs on the caller's
    /// thread (`JSCInterpreter`'s own documentation: "groundwork for the M4
    /// blocking async bridge... that blocking must not happen on the
    /// caller's (potentially main) thread") by dispatching internally onto
    /// the run's own dedicated worker queue via `DispatchQueue.sync` — but
    /// calling that *synchronously* from here would still tie up whichever
    /// cooperative-pool thread is running this `async` `call(arguments:)`
    /// for the run's entire duration. Wrapping it in
    /// `withCheckedThrowingContinuation` and dispatching onto a plain,
    /// elastic GCD global queue instead means this `async` function
    /// *suspends* (freeing its cooperative-pool thread for other work)
    /// rather than *blocks* while the snippet runs — a second, independent
    /// half of the same "never block the caller" principle
    /// `JSCInterpreter` established for the interpreter's own worker thread,
    /// applied here to the tool-call boundary above it.
    ///
    /// M10: also threads this `async` context's own `Task` cancellation
    /// into the interpreter's `isCancelled` hook
    /// (`Interpreter.run(code:installing:installingAsync:isCancelled:)`), so
    /// cancelling the `Task` running `call(arguments:)` reaches all the way
    /// into the running snippet rather than only being observed after it
    /// finishes.
    ///
    /// - Parameters:
    ///   - code: the JavaScript source to run.
    ///   - installing: the synchronous host functions to expose as globals.
    ///   - installingAsync: the asynchronous host functions to expose as
    ///     globals — every live `tools.*` binding.
    ///   - interpreter: the sandbox to run `code` in.
    /// - Returns: the run's result.
    /// - Throws: `CancellationError` if the calling `Task` is cancelled
    ///   before or during the run; otherwise whatever
    ///   `interpreter.run(code:installing:installingAsync:isCancelled:)`
    ///   itself throws.
    private static func run(
        code: String,
        installing: [HostFunction],
        installingAsync: [AsyncHostFunction],
        using interpreter: any Interpreter
    ) async throws -> InterpreterResult {
        // Lock-protected (not a plain `Bool`) for the same reason
        // `JSCInterpreter`'s own `WatchdogState` is: `onCancel` below can run
        // concurrently with the polling read `isCancelled` performs from the
        // interpreter's worker thread.
        let cancelledBox = OSAllocatedUnfairLock(initialState: false)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                dispatchRun(
                    code: code,
                    installing: installing,
                    installingAsync: installingAsync,
                    using: interpreter,
                    cancelledBox: cancelledBox,
                    continuation: continuation
                )
            }
        } onCancel: {
            cancelledBox.withLock { $0 = true }
        }
    }

    /// The GCD-queue half of `run(code:installing:installingAsync:using:)`'s
    /// bridge: performs the actual blocking `interpreter.run` off the
    /// cooperative pool and settles `continuation` with its outcome. Pulled
    /// out of `run` itself so that function's cancellation-handler/
    /// continuation nesting doesn't also have to carry the
    /// dispatch-queue/do-catch levels below it.
    ///
    /// - Parameters:
    ///   - code: the JavaScript source to run.
    ///   - installing: the synchronous host functions to expose as globals.
    ///   - installingAsync: the asynchronous host functions to expose as
    ///     globals.
    ///   - interpreter: the sandbox to run `code` in.
    ///   - cancelledBox: polled as `interpreter.run`'s `isCancelled` hook;
    ///     flipped to `true` by
    ///     `run(code:installing:installingAsync:using:)`'s `onCancel`.
    ///   - continuation: resumed with `interpreter.run`'s result or thrown
    ///     error.
    private static func dispatchRun(
        code: String,
        installing: [HostFunction],
        installingAsync: [AsyncHostFunction],
        using interpreter: any Interpreter,
        cancelledBox: OSAllocatedUnfairLock<Bool>,
        continuation: CheckedContinuation<InterpreterResult, Error>
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try interpreter.run(
                    code: code,
                    installing: installing,
                    installingAsync: installingAsync,
                    isCancelled: { cancelledBox.withLock { $0 } }
                )
                continuation.resume(returning: result)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - tools.* glue
    //
    // `HostFunction`s (M1) are always flat globals — `Interpreter.run`
    // installs each one under a single bare `name`, with no notion of a
    // nested object (and no way to install one: `InterpreterValue`, the type
    // every `HostFunction` argument/result crosses through, has no case for
    // a JS function value, so a "namespace object full of callables" can't
    // be built by handing the interpreter a pre-built value — it can only be
    // built the same way a snippet itself would build one: with JS). So
    // every wrapped tool installs as an anonymous, positionally-named flat
    // global (`__tool0`, `__tool1`, …, never seen by the model), and a small
    // JS preamble — prepended ahead of the user's own snippet inside the one
    // `code` string handed to `interpreter.run` — assigns each into its real
    // `tools.<name>` / `tools.<group>.<name>` position. Position (not a
    // name mangled from the path) is what keeps the two functions below in
    // lockstep and collision-free by construction, with no escaping
    // subtleties to get wrong.

    /// One registry entry that has a live tool to dispatch to, paired with
    /// the flat global its `tools.*` binding installs under.
    private struct LiveTool: Sendable {
        /// The entry's flat host-function name — see `hostFunctionName(at:)`.
        let hostFunctionName: String

        /// The live tool a `tools.<path>(…)` call dispatches into.
        let tool: any Tool
    }

    /// The positional host-function name for `registry.surface.entries[index]`
    /// — shared by `makeLiveTools` (which names it) and `makePreamble` (which
    /// assigns it into `tools.*`), so the two always agree on naming without
    /// either duplicating the scheme.
    ///
    /// - Parameter index: the entry's position in `registry.surface.entries`.
    /// - Returns: that entry's flat host-function name.
    private static func hostFunctionName(at index: Int) -> String {
        "__tool\(index)"
    }

    /// Pairs every registry entry that has a live tool with the flat
    /// host-function name it installs under.
    ///
    /// - Parameter registry: the catalog + live tool instances to bridge.
    /// - Returns: one pairing per entry with a matching
    ///   `registry.tools[path]`, named per `hostFunctionName(at:)` and in
    ///   the same order as `registry.surface.entries`.
    private static func makeLiveTools(for registry: Registry) -> [LiveTool] {
        var liveTools: [LiveTool] = []
        for (index, entry) in registry.surface.entries.enumerated() {
            guard let tool = registry.tools[entry.path] else { continue }
            liveTools.append(LiveTool(hostFunctionName: hostFunctionName(at: index), tool: tool))
        }
        return liveTools
    }

    /// Builds this invocation's `AsyncHostFunction`s — one per `liveTools`
    /// pairing, bridging its call into the tool's real `async`
    /// `call(arguments:)` via `invokeAsync` — no blocking bridge: the
    /// interpreter's own promise pump runs each closure in its own Swift
    /// `Task` (see `AsyncHostFunction`'s documentation).
    ///
    /// Per invocation rather than per registry, because each closure captures
    /// `binding`: that `Task` runs outside every task tree, so the session it
    /// belongs to has to be a captured value rather than an inherited one
    /// (see `RunBinding`).
    ///
    /// - Parameter binding: this `runCode` invocation's captured session
    ///   binding, or `nil` when it has none.
    /// - Returns: one `AsyncHostFunction` per live tool, in `liveTools`'
    ///   order.
    private func makeAsyncHostFunctions(binding: RunBinding?) -> [AsyncHostFunction] {
        liveTools.map { liveTool in
            AsyncHostFunction(name: liveTool.hostFunctionName) { arguments in
                try await Self.invokeAsync(tool: liveTool.tool, arguments: arguments, binding: binding)
            }
        }
    }

    /// Builds the JS preamble that assigns every registry entry's
    /// positionally-named host function into its real `tools.<name>` /
    /// `tools.<group>.<name>` position, prepended ahead of the user's
    /// snippet.
    ///
    /// Splices `entry.path`/`entry.group`/`entry.descriptor.name` bare into
    /// generated JS — safe because every one of them is already validated
    /// as a legal TypeScript (and so legal JS) identifier before an `Entry`
    /// is ever constructed: a group name by `MultiTool.Builder.build()`
    /// (`isLegalTSIdentifier`), a tool's own `name` by `ToolAPIRenderer
    /// .render` (which throws otherwise) — the same invariant
    /// `APISurface.Entry.block`'s own documentation relies on for its `//
    /// tools.<path>` banner comment.
    ///
    /// An entry with no matching `registry.tools[path]` is skipped
    /// entirely, exactly like `makeLiveTools`'s own `guard` — the
    /// two must agree, since a skipped entry here has no host function for
    /// `makeLiveTools` to name: unconditionally emitting
    /// `tools.<path> = __toolN;` regardless would reference an
    /// *undeclared* JS identifier (a `ReferenceError`, since that global was
    /// never installed) rather than degrade gracefully — skipping the
    /// assignment instead leaves `tools.<path>` simply never set, so
    /// reading it evaluates to `undefined` like any other absent property.
    ///
    /// - Parameter registry: the catalog + live tool instances to build
    ///   glue for.
    /// - Returns: the JS preamble, one `tools.*` assignment per entry with a
    ///   live tool, preceded by `globalThis.tools = {};` and by the void
    ///   re-binding of every name in `voidGlobalNames`.
    private static func makePreamble(for registry: Registry) -> String {
        // `globalThis.tools = {}` (not `var tools = {}`) so `tools` is a
        // genuine `globalThis` property — like `console`/`help`/`docs`,
        // installed directly via `context.setObject` — rather than a
        // variable merely local to the wrapping IIFE `evaluate` runs every
        // snippet inside (see `JSCInterpreter.evaluate`'s `wrapped` string).
        // A plain `var tools` would still be lexically reachable from the
        // snippet itself (same function scope), but wouldn't actually be
        // one of the sandbox's *global* bindings the README's "Injected
        // globals" list and `HardeningTests`'s runtime enumeration
        // (`Object.getOwnPropertyNames(globalThis)`) document it as.
        // `notify()`/`progress()` are void (eventplan.md's one-rule
        // contract), so their call expression must evaluate to `undefined` —
        // and `InterpreterValue`, the seam their `HostFunction` results cross,
        // has no `undefined` case to return. Each installed native global is
        // therefore captured and replaced, in place, by a JS wrapper that
        // calls it and returns nothing: the same "the seam cannot carry this
        // shape, so build it in JS" move `tools.*` itself makes. Emitted on
        // one line so the preamble costs the snippet's reported line numbers
        // as little as possible.
        var lines = [
            "globalThis.tools = {};",
            voidGlobalNames
                .map { "globalThis.\($0) = (function (send) { return function (detail) { send(detail); }; })(globalThis.\($0));" }
                .joined(separator: " "),
        ]
        for (index, entry) in registry.surface.entries.enumerated() {
            guard registry.tools[entry.path] != nil else { continue }
            let hostName = hostFunctionName(at: index)
            if let group = entry.group {
                lines.append("tools.\(group) = tools.\(group) || {};")
                lines.append("tools.\(group).\(entry.descriptor.name) = \(hostName);")
            } else {
                lines.append("tools.\(entry.path) = \(hostName);")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - The async host-function bridge (eventplan.md "Async JavaScript")

    /// Bridges one `tools.<name>(...)` call into the wrapped tool's real
    /// `async` `call(arguments:)`.
    ///
    /// No blocking bridge, no semaphore: this is an `AsyncHostFunction`
    /// body, which `JSCInterpreter.install(asyncHostFunction:into:registry:)`
    /// already runs in its own Swift `Task` — installed as a JS function
    /// that returns a `Promise`, resolved or rejected once that `Task`
    /// completes (see `AsyncHostFunction`'s documentation for the full
    /// promise-pump mechanics). `Promise.all` over several `tools.*` calls
    /// therefore starts their backing `Task`s concurrently, and
    /// `Interpreter.run`'s settle-before-return guarantee still applies at
    /// the snippet boundary regardless of whether the snippet itself awaits
    /// this call.
    ///
    /// That `Task` lands outside every task tree, so the session behind the
    /// call arrives as `binding` — a value captured back in
    /// `call(arguments:)` — never as an inherited ambient context. `binding`
    /// also selects the mount: through the elevation engine with elevation
    /// off when a session bound one, natively when none did (see
    /// `ToolInvoker`'s "The two mounts").
    ///
    /// - Parameters:
    ///   - tool: the wrapped tool this call dispatches to.
    ///   - arguments: the JS call's arguments, already converted to
    ///     `InterpreterValue` by `JSCInterpreter`. A well-formed call always
    ///     supplies exactly one JS object (`tools.name({ … })`, plan.md:
    ///     "object (named) parameters, always"); a missing or non-object
    ///     first argument is treated as `{}` and surfaces as an ordinary
    ///     `ArgumentMarshalerError`/`ToolInvokerError` below, never a crash.
    ///   - binding: the enclosing `runCode` invocation's captured session
    ///     binding, or `nil` when it has none.
    /// - Returns: the tool's rendered `Output`, JS-ready.
    /// - Throws: `ArgumentMarshalerError` if `arguments` can't be marshaled
    ///   into the tool's `Arguments` shape (or its `Output` can't be
    ///   rendered back out); `ToolInvokerError` if pre-call validation
    ///   fails; otherwise whatever `tool.call(arguments:)` itself throws,
    ///   unchanged. Every case becomes the returned promise's rejection
    ///   reason, carrying the message unchanged, by
    ///   `JSCInterpreter.install(asyncHostFunction:into:registry:)`, which
    ///   `ResultRenderer` in turn renders as a repairable error.
    private static func invokeAsync(
        tool: any Tool,
        arguments: [InterpreterValue],
        binding: RunBinding?
    ) async throws -> InterpreterValue {
        let start = ContinuousClock.now
        logger.debug("tools.\(tool.name, privacy: .public) invocation started.")
        do {
            let value = try await performInvocation(tool: tool, arguments: arguments, binding: binding)
            logger.debug(
                "tools.\(tool.name, privacy: .public) invocation finished in \(start.duration(to: .now), privacy: .public)."
            )
            return value
        } catch {
            logInvocationFailure(tool: tool, error: error)
            throw error
        }
    }

    /// Records one imagined `tools.*` path a snippet reached for, so a host
    /// can mine its own log for the names its model expects.
    ///
    /// **Why this is logged at all.** An imagined name is free evidence
    /// about the catalog: it is the model saying what it thought the tool
    /// should be called. Accumulated across real sessions, those guesses
    /// rank the synonyms a host's naming (or an alias table) should cover.
    /// Nothing else on this route records them — the hint is rendered into
    /// the model's error text and discarded.
    ///
    /// **Why `.notice`.** The corpus has to survive an ordinary host run to
    /// be worth mining. `.debug` is disabled by default and never reaches
    /// the store at all; `.info` reaches the in-memory buffer but is not
    /// persisted to disk unless the subsystem's info level is turned on, so
    /// it survives a live `log stream` and not a later `log show`.
    /// `.notice` is the lowest level that persists by default. Against this
    /// file's own gradient it also fits: the `.debug` lines here are
    /// per-invocation and high-volume, and the `.warning`/`.error` lines
    /// report a failure a host should act on — an imagined name is neither.
    ///
    /// **Why `.public`.** Every field is model- or catalog-authored and
    /// carries no user data: `imaginedPath` is a name the model made up,
    /// `suggestedPaths` are the host's own tool names (already `.public`
    /// wherever `tool.name` is logged above), and the tier is one of three
    /// fixed words. Nothing derived from a snippet's arguments, a tool's
    /// output, or the user's prompt is in the line, and none is added: the
    /// message is composed by `UnknownToolHint.Resolution.logMessage` from
    /// exactly those three fields.
    ///
    /// - Parameter resolution: the unknown-path detection to record.
    private static func logImaginedTool(_ resolution: UnknownToolHint.Resolution) {
        logger.notice("\(resolution.logMessage, privacy: .public)")
    }

    /// Logs one `tools.*` invocation's failure — plan.md M10: "each
    /// tools.* invocation, validation failures" — distinguishing a
    /// pre-call **validation failure** (`ToolInvokerError`/
    /// `ArgumentMarshalerError`, logged at `.warning`: the snippet's call
    /// was malformed, not the tool itself) from any other failure (the
    /// tool's own thrown error, logged at `.error`).
    ///
    /// - Parameters:
    ///   - tool: the tool `invokeAsync` was invoking.
    ///   - error: the failure `performInvocation` threw.
    private static func logInvocationFailure(tool: any Tool, error: Error) {
        switch error {
        case let validationError as ToolInvokerError:
            logger.warning(
                "tools.\(tool.name, privacy: .public) argument validation failed: \(validationError.message, privacy: .public)"
            )
        case let marshalingError as ArgumentMarshalerError:
            logger.warning(
                "tools.\(tool.name, privacy: .public) argument marshaling failed: \(marshalingError.message, privacy: .public)"
            )
        default:
            logger.error(
                "tools.\(tool.name, privacy: .public) invocation failed: \(String(describing: error), privacy: .public)"
            )
        }
    }

    /// The actual marshal → validate → call → render pipeline `invokeAsync`
    /// wraps with start/end logging — see that function's documentation for
    /// the full async host-function bridge.
    ///
    /// - Parameters:
    ///   - tool: the wrapped tool this call dispatches to.
    ///   - arguments: the JS call's arguments, already converted to
    ///     `InterpreterValue`.
    ///   - binding: the enclosing `runCode` invocation's captured session
    ///     binding, or `nil` when it has none — selects `ToolInvoker`'s
    ///     mount.
    /// - Returns: the tool's rendered `Output`, JS-ready.
    /// - Throws: `ArgumentMarshalerError`, `ToolInvokerError`, or whatever
    ///   `tool.call(arguments:)` itself throws — see `invokeAsync`'s
    ///   documentation.
    private static func performInvocation(
        tool: any Tool,
        arguments: [InterpreterValue],
        binding: RunBinding?
    ) async throws -> InterpreterValue {
        let argumentObject = arguments.first ?? .object([:])
        let content = try ArgumentMarshaler.marshalArguments(argumentObject)
        let output = try await ToolInvoker.invoke(tool, content: content, binding: binding)
        return try ArgumentMarshaler.renderOutput(output)
    }

    // MARK: - help()/docs() globals (plan.md M7)
    //
    // Two more `HostFunction`s, installed as flat globals alongside
    // `tools.*` — the surface-reading half of the fixed, enumerable global
    // set a snippet can reach (plan.md: "These are the only extra globals;
    // the deny-by-default sandbox is otherwise unchanged."). The other half
    // is the six ambient globals of eventplan.md § "The sandbox globals" —
    // see `MultiTool+SandboxGlobals.swift`; `HardeningTests` pins the whole
    // set against the README's own list. Both read from the very same
    // `registry.surface`/`Entry` data the registry-backed selection tier's
    // instruction prefix and `findAPIs` are built from (M2.5/M6) — plan.md's
    // "one generator, one source of truth, never drifting" — so
    // `help()`/`docs()` can never describe a tool differently than
    // discovery does.
    //
    // Neither return value is ever spliced into generated JS *source* the
    // way `makePreamble`'s `tools.<path> = __toolN;` assignments are — a
    // plain Swift `String`/`[String]` crosses back into the sandbox as an
    // ordinary `InterpreterValue`, which `JSCInterpreter` round-trips
    // through `JSON.parse`/`JSON.stringify` (see `Interpreter.swift`) as JS
    // *data*, not source text. So unlike `ToolAPIRenderer`'s splice sites
    // (which build literal `declare function …` source and must guard
    // schema-derived text against breaking out of a comment or string
    // literal), nothing here needs escaping: a schema-derived tool name
    // containing a quote or newline just becomes a JS string value like any
    // other, safe by construction.

    /// Builds the `help()` and `docs(name)` host functions — the two
    /// surface-reading globals `MultiTool` installs beyond `tools.*` itself.
    ///
    /// - Parameter registry: the catalog whose `surface` backs both
    ///   functions.
    /// - Returns: two host functions, named `"help"` and `"docs"`.
    private static func makeHelpDocsHostFunctions(for registry: Registry) -> [HostFunction] {
        [
            HostFunction(name: "help") { _ in
                .array(registry.surface.entries.map { .string($0.path) })
            },
            HostFunction(name: "docs") { arguments in
                .string(renderDocs(for: arguments.first, in: registry.surface))
            },
        ]
    }

    /// Renders `docs(name)`'s result: the exact `APISurface.Entry.block`
    /// for the entry whose `path` matches `name` — plan.md: "reuse
    /// `APISurface.Entry.block`... rather than re-rendering anything" — or,
    /// when `name` doesn't match any entry (including when it isn't a
    /// string at all), a helpful error naming the closest known names
    /// instead of crashing.
    ///
    /// - Parameters:
    ///   - argument: the JS call's first argument, already converted to
    ///     `InterpreterValue` by `JSCInterpreter` — expected to be
    ///     `.string(name)` for a well-formed `docs("name")` call.
    ///   - surface: the catalog to look `name` up against.
    /// - Returns: the matching entry's full rendered block, or an error
    ///   message listing near-match suggestions.
    private static func renderDocs(for argument: InterpreterValue?, in surface: APISurface) -> String {
        guard case .string(let name) = argument else {
            return "docs(name) requires a string tool name, e.g. docs(\"getWeather\")."
        }
        if let entry = surface.entries.first(where: { $0.path == name }) {
            return entry.block
        }
        // After the catalog, never before it: a wrapped tool actually named
        // `globals` keeps its own block, and the ambient page is what `name`
        // resolves to only when no entry claimed it.
        if let globals = sandboxGlobalsDocumentation(for: name) {
            return globals
        }

        let knownPaths = surface.entries.map(\.path)
        let suggestions = nearestMatches(to: name, among: knownPaths)
        guard !suggestions.isEmpty else {
            return "Unknown tool \"\(name)\". No tools are registered."
        }
        return "Unknown tool \"\(name)\". Did you mean: \(suggestions.joined(separator: ", "))?"
    }

    /// The closest known tool paths to `name`, ranked by Levenshtein edit
    /// distance — a deliberately simple fuzzy match (plan.md M7: "a simple
    /// approach... is fine — don't over-engineer a fuzzy-matching
    /// library"), good enough to point a model at the right function after
    /// a typo'd `docs()` call.
    ///
    /// - Parameters:
    ///   - name: the (unknown) name `docs()` was called with.
    ///   - candidates: every known tool path to compare against.
    ///   - limitingTo: the maximum number of suggestions to return. Defaults
    ///     to `3`.
    /// - Returns: up to `limitingTo` candidates, nearest first; `sorted`'s
    ///   guaranteed stability keeps ties in `candidates`' original
    ///   (catalog) order.
    private static func nearestMatches(to name: String, among candidates: [String], limitingTo: Int = 3) -> [String] {
        candidates
            .map { ($0, levenshteinDistance($0, name)) }
            .sorted { $0.1 < $1.1 }
            .prefix(limitingTo)
            .map(\.0)
    }

    /// The Levenshtein (edit) distance between `lhs` and `rhs`: the minimum
    /// number of single-character insertions, deletions, or substitutions
    /// to turn one into the other. Used only to rank `docs(name)`'s
    /// near-match suggestions — not exposed beyond
    /// `nearestMatches(to:among:limitingTo:)`.
    ///
    /// A standard two-row dynamic-programming implementation, operating
    /// over `Character`s (extended grapheme clusters) rather than raw
    /// UTF-8/UTF-16 units, matching this package's established posture
    /// toward user/schema-derived text (`ResultRendererLimits`'s own
    /// documentation gives the same reasoning for its truncation caps).
    ///
    /// The textbook algorithm fills an `(a.count + 1) x (b.count + 1)`
    /// matrix, where cell `[i][j]` holds the edit distance between `a`'s
    /// first `i` characters and `b`'s first `j` characters. Row `0` and
    /// column `0` are the base cases (turning a prefix into the empty
    /// string costs one deletion/insertion per character), and every other
    /// cell is the cheapest of three moves in from its already-computed
    /// neighbors: deleting `a[i-1]` (from the cell above), inserting `b[j-1]`
    /// (from the cell to the left), or substituting (from the cell
    /// diagonally above-left, plus `0`/`1` depending on whether `a[i-1] ==
    /// b[j-1]`). Since row `i` only ever reads from row `i-1` and itself,
    /// the full matrix is never needed — this implementation keeps just two
    /// rows, `previousRow` (row `i-1`, seeded with the base case
    /// `0...b.count`) and `currentRow` (row `i`, being filled left to
    /// right), and slides `currentRow` into `previousRow` at the end of
    /// each outer iteration before starting the next row. That trades the
    /// textbook's `O(a.count * b.count)` space for `O(b.count)`, at no cost
    /// to the `O(a.count * b.count)` time — the only ingredient
    /// `nearestMatches` actually needs is the final `previousRow[b.count]`.
    ///
    /// - Parameters:
    ///   - lhs: the first string.
    ///   - rhs: the second string.
    /// - Returns: the edit distance between `lhs` and `rhs`.
    private static func levenshteinDistance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        var previousRow = Array(0...b.count)
        var currentRow = [Int](repeating: 0, count: b.count + 1)

        for i in 1...a.count {
            currentRow[0] = i
            for j in 1...b.count {
                let substitutionCost = a[i - 1] == b[j - 1] ? 0 : 1
                currentRow[j] = Swift.min(
                    previousRow[j] + 1, // deletion
                    currentRow[j - 1] + 1, // insertion
                    previousRow[j - 1] + substitutionCost // substitution
                )
            }
            previousRow = currentRow
        }
        return previousRow[b.count]
    }
}
