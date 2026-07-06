import Foundation
import FoundationModels
import os

extension MultiTool {
    /// The built, executable artifact `MultiTool.Builder.buildRegistry()`
    /// produces — plan.md's "registry" (the value the "Adding tools is the
    /// easy path" usage sample assigns `Builder.build()`'s result to, and
    /// that `MultiToolAgent(registry:...)` and `MultiTool.init(registry:)`
    /// both take): the rendered `ApiSurface` (M2.5) paired with the actual
    /// wrapped `any Tool` instances a `runCode` snippet's `tools.*` calls
    /// dispatch to.
    ///
    /// `ApiSurface` alone can't drive execution — by its own design (see
    /// `ApiSurface`'s documentation) it is "pure data: no model wiring, no
    /// rendering logic of its own beyond composing already-rendered pieces,"
    /// carrying only each tool's rendered *descriptor*, never the tool object
    /// itself. `Registry` is the pairing that closes that gap for M4a: every
    /// entry in `surface.entries` has a fully-qualified `path` (`"weather"`,
    /// `"github.createIssue"`, …), and `tools[path]` is that entry's live
    /// `any Tool` to invoke.
    public struct Registry: Sendable {
        /// The rendered, model-agnostic catalog — declarations, doc comments,
        /// and examples only (M2.5). Backs the registry-backed selection
        /// tier's instruction prefix (`FoundationModelsMetadataRegistry`) and
        /// `help()`/`docs()` (M6/M7); carries no tool instances of its own.
        public let surface: ApiSurface

        /// Every wrapped tool, keyed by its fully-qualified snippet call path
        /// (`surface.entries`'s own `path`, e.g. `"weather"` or
        /// `"github.createIssue"`) — the pairing `MultiTool` uses to bind
        /// each `tools.*` entry point to a live `any Tool` to invoke via
        /// `ToolInvoker`.
        public let tools: [String: any Tool]

        /// Whether this registry surfaces only `runCode` — plan.md's "direct
        /// mode": discovery (`findAPIs`) is skipped, and a snippet is
        /// expected to introspect the surface itself via `help()`/`docs()`
        /// (M7) instead. `false` (the default) surfaces both `runCode` and
        /// `findAPIs` to the agent loop (M4b/M6).
        public let isDirectMode: Bool

        /// Creates a registry pairing a rendered surface with its live tool
        /// instances.
        ///
        /// Explicit for the same reason as `ApiSurface.init`/
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
        public init(surface: ApiSurface, tools: [String: any Tool], isDirectMode: Bool = false) {
            self.surface = surface
            self.tools = tools
            self.isDirectMode = isDirectMode
        }

        /// Returns a copy of this registry in **direct mode** — plan.md
        /// "Direct mode (skip discovery)": only `runCode` is surfaced to the
        /// agent loop; a snippet is expected to introspect the surface
        /// itself via `help()`/`docs()` (M7) rather than a `findAPIs` round
        /// trip. The executable surface itself (`surface`/`tools`) is
        /// unchanged — only the affordance metadata (`isDirectMode`,
        /// `affordances`, `supportsFindApis`) flips.
        ///
        /// - Returns: a copy of this registry with `isDirectMode` set to
        ///   `true`.
        public func directMode() -> Registry {
            Registry(surface: surface, tools: tools, isDirectMode: true)
        }

        /// The agent-loop-facing operations this registry surfaces —
        /// `["runCode"]` in direct mode, `["runCode", "findAPIs"]`
        /// otherwise. Plain, checkable metadata for a caller (or a test) to
        /// read without having to separately know `isDirectMode`'s exact
        /// semantics.
        public var affordances: [String] {
            isDirectMode ? ["runCode"] : ["runCode", "findAPIs"]
        }

        /// Whether this registry surfaces `findAPIs` discovery — `false` in
        /// direct mode, `true` otherwise.
        public var supportsFindApis: Bool {
            !isDirectMode
        }
    }
}

/// The arguments `MultiTool`'s `runCode` call accepts: the JavaScript
/// snippet to run against `tools.*`.
@Generable
public struct RunCodeArguments {
    @Guide(
        description: "JavaScript snippet to run against the available tools, exposed as functions "
            + "under `tools.*`. Compose calls with normal code — variables, loops, map/filter — and "
            + "`return` the final value; only that value (and any console output) comes back."
    )
    public var code: String

    /// Creates `runCode`'s arguments with the given snippet.
    ///
    /// Explicit for the same reason as every other public `@Generable`
    /// type's initializer in this package (e.g. `ToolDescriptor.init`): a
    /// `public` struct's synthesized memberwise initializer is only
    /// `internal`-accessible.
    ///
    /// - Parameter code: the JavaScript snippet to run.
    public init(code: String) {
        self.code = code
    }
}

/// plan.md Component 1 ⭐ — the `runCode` `Tool`: the execution half of the
/// MultiTool idea, "a single `Tool`... that wraps other, in-process `Tool`s
/// and exposes them to the model as a callable code API." Conforms to
/// `FoundationModels.Tool` (so it can also drop into an Apple built-in
/// session, per plan.md's "Usage: attaching to a session" escape hatch), but
/// on a Router model is driven by `MultiToolAgent` (M4b) instead of an Apple
/// tool-calling loop.
///
/// Per call, `call(arguments:)`:
/// 1. builds `tools.*` glue that assigns every registry entry's real,
///    wrapped tool to its fully-qualified snippet path (flat `tools.<name>`
///    for a standalone tool, nested `tools.<group>.<name>` for a grouped
///    one — plan.md Resolved #5) — see "tools.* glue" below;
/// 2. runs the glue followed by the snippet in a fresh `Interpreter` sandbox
///    (M1) off the calling thread (see "Off-cooperative-thread dispatch");
/// 3. renders the result — or a thrown `InterpreterError` — via
///    `ResultRenderer` (M5).
///
/// Each `tools.X(...)` call bridges into the wrapped tool's real, async
/// `call(arguments:)` through `invokeBlocking`'s v1 blocking bridge (plan.md
/// Resolved #1) — see that function's documentation for the full
/// tradeoff.
public struct MultiTool: Tool {
    /// This tool's `Tool`-protocol name, always `"runCode"`.
    public let name = "runCode"
    /// This tool's `Tool`-protocol description, presented to the model as usage instructions for `runCode`.
    public let description = """
        Run a JavaScript snippet against the available tools, exposed as functions under
        `tools.*`. Compose calls with normal code — variables, loops, map/filter — and
        `return` the final value (only that comes back; intermediates stay private).
        Call findAPIs first to learn exact signatures, or help()/docs(name) in-snippet.
        Errors are returned to you to fix and retry.
        """

    /// Where this tool logs its M10 diagnostics — one `runCode` call's
    /// start/end, and each `tools.*` invocation's start/end/validation
    /// failure.
    private static let logger = Logger(subsystem: "FoundationModelsMultitool", category: "MultiTool")

    /// The catalog + live tool instances this `runCode` dispatches into.
    private let registry: Registry

    /// The sandbox this tool runs every snippet in. `any Interpreter` (not
    /// `JSCInterpreter` directly) so a test can substitute a fake — matching
    /// `Interpreter`'s own stated purpose ("the engine is swappable without
    /// touching callers").
    private let interpreter: any Interpreter

    /// The size caps `ResultRenderer` enforces on this tool's rendered
    /// output.
    private let limits: ResultRendererLimits

    /// Every wrapped tool's `HostFunction` bridge, built once at `init` time
    /// (stable for the registry's lifetime — installing them is cheap and
    /// the mapping never changes call to call) and re-installed fresh into
    /// every `runCode` call's own sandbox by `Interpreter.run`.
    private let hostFunctions: [HostFunction]

    /// The `tools.*` assignment glue prepended to every snippet — see
    /// "tools.* glue" below. Precomputed once at `init` time for the same
    /// reason as `hostFunctions`: it depends only on `registry.surface`,
    /// which never changes.
    private let preamble: String

    /// Creates a `runCode` tool over `registry`.
    ///
    /// - Parameters:
    ///   - registry: the catalog + live tool instances to expose as
    ///     `tools.*`.
    ///   - configuration: the M10 hardening knobs (execution time limit,
    ///     return/console caps) this tool enforces. Defaults to
    ///     `MultiToolConfiguration.default`. Ignored for whichever of
    ///     `interpreter`/`limits` is explicitly supplied instead of left
    ///     `nil` — an explicit override always wins over the configuration's
    ///     corresponding derived value.
    ///   - interpreter: the sandbox to run every snippet in. Defaults to a
    ///     fresh `JSCInterpreter` honoring `configuration.executionTimeLimit`.
    ///   - limits: the size caps `ResultRenderer` enforces on this tool's
    ///     rendered output. Defaults to `configuration.resultLimits`.
    public init(
        registry: Registry,
        configuration: MultiToolConfiguration = .default,
        interpreter: (any Interpreter)? = nil,
        limits: ResultRendererLimits? = nil
    ) {
        self.registry = registry
        self.interpreter = interpreter ?? JSCInterpreter(timeLimit: configuration.executionTimeLimit)
        self.limits = limits ?? configuration.resultLimits
        self.hostFunctions = Self.makeHostFunctions(for: registry) + Self.makeHelpDocsHostFunctions(for: registry)
        self.preamble = Self.makePreamble(for: registry)
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
    /// - Parameter arguments: the snippet to run.
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
        let code = "\(preamble)\n\(arguments.code)"
        do {
            let result = try await Self.run(code: code, installing: hostFunctions, using: interpreter)
            return ResultRenderer.render(result, limits: limits)
        } catch let interpreterError as InterpreterError {
            return ResultRenderer.render(interpreterError)
        }
    }

    // MARK: - Off-cooperative-thread dispatch

    /// Runs `interpreter.run(code:installing:)` — a synchronous, blocking
    /// call — without blocking the calling `async` context's own
    /// cooperative-pool thread for its duration.
    ///
    /// `Interpreter.run` already guarantees it never runs on the caller's
    /// thread (`JSCInterpreter`'s own documentation: "groundwork for the M4
    /// blocking async bridge... that blocking must not happen on the
    /// caller's (potentially main) thread") by dispatching internally onto
    /// its own dedicated worker queue via `DispatchQueue.sync` — but calling
    /// that *synchronously* from here would still tie up whichever
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
    /// (`Interpreter.run(code:installing:isCancelled:)`), so cancelling the
    /// `Task` running `call(arguments:)` reaches all the way into the
    /// running snippet rather than only being observed after it finishes.
    ///
    /// - Parameters:
    ///   - code: the JavaScript source to run.
    ///   - installing: the host functions to expose as globals.
    ///   - interpreter: the sandbox to run `code` in.
    /// - Returns: the run's result.
    /// - Throws: `CancellationError` if the calling `Task` is cancelled
    ///   before or during the run; otherwise whatever
    ///   `interpreter.run(code:installing:isCancelled:)` itself throws.
    private static func run(
        code: String,
        installing: [HostFunction],
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
                    using: interpreter,
                    cancelledBox: cancelledBox,
                    continuation: continuation
                )
            }
        } onCancel: {
            cancelledBox.withLock { $0 = true }
        }
    }

    /// The GCD-queue half of `run(code:installing:using:)`'s bridge: performs
    /// the actual blocking `interpreter.run` off the cooperative pool and
    /// settles `continuation` with its outcome. Pulled out of `run` itself so
    /// that function's cancellation-handler/continuation nesting doesn't also
    /// have to carry the dispatch-queue/do-catch levels below it.
    ///
    /// - Parameters:
    ///   - code: the JavaScript source to run.
    ///   - installing: the host functions to expose as globals.
    ///   - interpreter: the sandbox to run `code` in.
    ///   - cancelledBox: polled as `interpreter.run`'s `isCancelled` hook;
    ///     flipped to `true` by `run(code:installing:using:)`'s `onCancel`.
    ///   - continuation: resumed with `interpreter.run`'s result or thrown
    ///     error.
    private static func dispatchRun(
        code: String,
        installing: [HostFunction],
        using interpreter: any Interpreter,
        cancelledBox: OSAllocatedUnfairLock<Bool>,
        continuation: CheckedContinuation<InterpreterResult, Error>
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try interpreter.run(
                    code: code,
                    installing: installing,
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

    /// The positional host-function name for `registry.surface.entries[index]`
    /// — shared by `makeHostFunctions` (which installs it) and
    /// `makePreamble` (which assigns it into `tools.*`), so the two always
    /// agree on naming without either duplicating the scheme.
    ///
    /// - Parameter index: the entry's position in `registry.surface.entries`.
    /// - Returns: that entry's flat host-function name.
    private static func hostFunctionName(at index: Int) -> String {
        "__tool\(index)"
    }

    /// Builds one `HostFunction` per registry entry that has a live tool to
    /// dispatch to, bridging its synchronous JS call into the tool's real
    /// `async` `call(arguments:)` via `invokeBlocking`.
    ///
    /// - Parameter registry: the catalog + live tool instances to bridge.
    /// - Returns: one `HostFunction` per entry with a matching `registry
    ///   .tools[path]`, named per `hostFunctionName(at:)` and in the same
    ///   order as `registry.surface.entries`.
    private static func makeHostFunctions(for registry: Registry) -> [HostFunction] {
        var hostFunctions: [HostFunction] = []
        for (index, entry) in registry.surface.entries.enumerated() {
            guard let tool = registry.tools[entry.path] else { continue }
            hostFunctions.append(
                HostFunction(name: hostFunctionName(at: index)) { arguments in
                    try invokeBlocking(tool: tool, arguments: arguments)
                }
            )
        }
        return hostFunctions
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
    /// `ApiSurface.Entry.block`'s own documentation relies on for its `//
    /// tools.<path>` banner comment.
    ///
    /// An entry with no matching `registry.tools[path]` is skipped
    /// entirely, exactly like `makeHostFunctions`'s own `guard` — the two
    /// must agree, since a skipped entry here has no host function for
    /// `makeHostFunctions` to assign it to: unconditionally emitting
    /// `tools.<path> = __toolN;` regardless would reference an
    /// *undeclared* JS identifier (a `ReferenceError`, since that global was
    /// never installed) rather than degrade gracefully — skipping the
    /// assignment instead leaves `tools.<path>` simply never set, so
    /// reading it evaluates to `undefined` like any other absent property.
    ///
    /// - Parameter registry: the catalog + live tool instances to build
    ///   glue for.
    /// - Returns: the JS preamble, one `tools.*` assignment per entry with a
    ///   live tool, preceded by `globalThis.tools = {};`.
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
        var lines = ["globalThis.tools = {};"]
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

    // MARK: - The v1 async bridge (plan.md Resolved #1)

    /// Bridges one `tools.<name>(...)` call — synchronous from JSC's
    /// perspective, since `HostFunction.call` is a plain, non-`async`
    /// closure (M1) — into the wrapped tool's real `async`
    /// `call(arguments:)`.
    ///
    /// ## Why blocking is safe here
    /// This closure runs as a `HostFunction` body, which `JSCInterpreter`
    /// only ever invokes from its own dedicated worker `DispatchQueue` —
    /// never the caller's thread, and never the main thread (see that
    /// type's documentation). Blocking *that* thread on a semaphore is
    /// exactly the "standard JSContext bridging pattern" plan.md commits to
    /// for v1: the snippet's actual work — `await tool.call(arguments:)` —
    /// is dispatched onto Swift's cooperative thread pool via an
    /// unstructured `Task`, and this function's `semaphore.wait()` simply
    /// parks the dedicated JSC worker thread until that `Task` reports
    /// back, exactly mirroring `MultiTool.run`'s own "never block the
    /// caller" treatment of the layer above it.
    ///
    /// ## The documented tradeoff
    /// The dedicated JSC worker thread is *not* one of Swift's (bounded,
    /// roughly core-count-sized) cooperative-pool threads, so parking it
    /// here never directly *removes* a cooperative-pool thread from
    /// circulation — but the `Task` spawned below still needs a free
    /// cooperative-pool thread to make progress. If every thread in that
    /// pool is *also* blocked on work like this (many concurrent `runCode`
    /// calls each waiting on their own tool bridge, or unrelated blocking
    /// work sharing the same pool), the spawned `Task` can be starved
    /// indefinitely waiting for a thread to run on — under sustained
    /// saturation this is a real deadlock risk, not merely reduced
    /// throughput, even though this bridge itself never *holds* a
    /// cooperative thread while waiting. v1 accepts this (plan.md: "the
    /// standard JSContext bridging pattern, safe under stateless
    /// snippets") because each `runCode` call is short-lived and
    /// stateless, so the exposure window is small; a JSC microtask/promise
    /// pump giving real `async`/`await` (and parallel `Promise.all`
    /// fan-out) is the documented later upgrade that removes this bridge —
    /// and the pool-exhaustion risk with it — entirely.
    ///
    /// - Parameters:
    ///   - tool: the wrapped tool this call dispatches to.
    ///   - arguments: the JS call's arguments, already converted to
    ///     `InterpreterValue` by `JSCInterpreter`. A well-formed call always
    ///     supplies exactly one JS object (`tools.name({ … })`, plan.md:
    ///     "object (named) parameters, always"); a missing or non-object
    ///     first argument is treated as `{}` and surfaces as an ordinary
    ///     `ArgumentMarshalerError`/`ToolInvokerError` below, never a crash.
    /// - Returns: the tool's rendered `Output`, JS-ready.
    /// - Throws: `ArgumentMarshalerError` if `arguments` can't be marshaled
    ///   into the tool's `Arguments` shape (or its `Output` can't be
    ///   rendered back out); `ToolInvokerError` if pre-call validation
    ///   fails; otherwise whatever `tool.call(arguments:)` itself throws,
    ///   unchanged. Every case is turned into a JS exception carrying the
    ///   message by `JSCInterpreter.install(hostFunction:into:)`, which
    ///   `ResultRenderer` in turn renders as a repairable error.
    private static func invokeBlocking(
        tool: any Tool,
        arguments: [InterpreterValue]
    ) throws -> InterpreterValue {
        let start = ContinuousClock.now
        logger.debug("tools.\(tool.name, privacy: .public) invocation started.")
        do {
            let value = try performInvocation(tool: tool, arguments: arguments)
            logger.debug(
                "tools.\(tool.name, privacy: .public) invocation finished in \(start.duration(to: .now), privacy: .public)."
            )
            return value
        } catch {
            logInvocationFailure(tool: tool, error: error)
            throw error
        }
    }

    /// Logs one `tools.*` invocation's failure — plan.md M10: "each
    /// tools.* invocation, validation failures" — distinguishing a
    /// pre-call **validation failure** (`ToolInvokerError`/
    /// `ArgumentMarshalerError`, logged at `.warning`: the snippet's call
    /// was malformed, not the tool itself) from any other failure (the
    /// tool's own thrown error, logged at `.error`).
    ///
    /// - Parameters:
    ///   - tool: the tool `invokeBlocking` was invoking.
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

    /// The actual marshal → validate → call → render pipeline
    /// `invokeBlocking` wraps with start/end logging — see that function's
    /// documentation for the full async-bridge tradeoff.
    ///
    /// - Parameters:
    ///   - tool: the wrapped tool this call dispatches to.
    ///   - arguments: the JS call's arguments, already converted to
    ///     `InterpreterValue`.
    /// - Returns: the tool's rendered `Output`, JS-ready.
    /// - Throws: `ArgumentMarshalerError`, `ToolInvokerError`, or whatever
    ///   `tool.call(arguments:)` itself throws — see `invokeBlocking`'s
    ///   documentation.
    private static func performInvocation(
        tool: any Tool,
        arguments: [InterpreterValue]
    ) throws -> InterpreterValue {
        let argumentObject = arguments.first ?? .object([:])
        let content = try ArgumentMarshaler.marshalArguments(argumentObject)

        let semaphore = DispatchSemaphore(value: 0)
        let outcomeBox = OSAllocatedUnfairLock<Result<InterpreterValue, Error>?>(initialState: nil)
        Task {
            do {
                let output = try await ToolInvoker.invoke(tool, content: content)
                let rendered = try ArgumentMarshaler.renderOutput(output)
                outcomeBox.withLock { $0 = .success(rendered) }
            } catch {
                outcomeBox.withLock { $0 = .failure(error) }
            }
            semaphore.signal()
        }
        semaphore.wait()

        switch outcomeBox.withLock({ $0 }) {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        case nil:
            // Unreachable in practice, but not force-unwrapped: `semaphore.wait()`
            // above only returns after the `Task` has written `.success`/`.failure`
            // into `outcomeBox` and called `semaphore.signal()`, so a nil box here
            // means that invariant is broken — a programmer error in the bridge
            // itself, not a recoverable runtime condition a caller could hit by
            // passing bad arguments or a failing tool. Treat it as such.
            preconditionFailure(
                "MultiTool.invokeBlocking: outcomeBox was nil after semaphore.wait() "
                    + "returned. The Task must write a Result into outcomeBox before "
                    + "signaling the semaphore, so this indicates the bridge's "
                    + "signal/write ordering invariant has been violated."
            )
        }
    }

    // MARK: - help()/docs() globals (plan.md M7)
    //
    // Two more `HostFunction`s, installed as flat globals alongside
    // `tools.*` — the *only* other globals a snippet can reach (plan.md:
    // "These are the only extra globals; the deny-by-default sandbox is
    // otherwise unchanged."). Both read from the very same
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

    /// Builds the `help()` and `docs(name)` host functions — the only
    /// globals `MultiTool` installs beyond `tools.*` itself.
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

    /// Renders `docs(name)`'s result: the exact `ApiSurface.Entry.block`
    /// for the entry whose `path` matches `name` — plan.md: "reuse
    /// `ApiSurface.Entry.block`... rather than re-rendering anything" — or,
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
    private static func renderDocs(for argument: InterpreterValue?, in surface: ApiSurface) -> String {
        guard case .string(let name) = argument else {
            return "docs(name) requires a string tool name, e.g. docs(\"weather\")."
        }
        if let entry = surface.entries.first(where: { $0.path == name }) {
            return entry.block
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
