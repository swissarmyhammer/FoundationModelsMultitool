import Foundation
import FoundationModels
import os

extension MultiTool {
    /// The built, executable artifact `MultiTool.Builder.buildRegistry()`
    /// produces — plan.md's "registry" (the value the "Adding tools is the
    /// easy path" usage sample assigns `Builder.build()`'s result to, and
    /// that `MultiToolAgent(registry:...)` and `MultiTool.init(registry:)`
    /// both take): the rendered `APISurface` (M2.5) paired with the actual
    /// wrapped `any Tool` instances a `runCode` snippet's `tools.*` calls
    /// dispatch to.
    ///
    /// `APISurface` alone can't drive execution — by its own design (see
    /// `APISurface`'s documentation) it is "pure data: no model wiring, no
    /// rendering logic of its own beyond composing already-rendered pieces,"
    /// carrying only each tool's rendered *descriptor*, never the tool object
    /// itself. `Registry` is the pairing that closes that gap for M4a: every
    /// entry in `surface.entries` has a fully-qualified `path` (`"weather"`,
    /// `"github.createIssue"`, …), and `tools[path]` is that entry's live
    /// `any Tool` to invoke.
    public struct Registry: Sendable {
        /// The rendered, model-agnostic catalog — declarations, doc comments,
        /// and examples only (M2.5). Backs the librarian prefix and
        /// `help()`/`docs()` (M6/M7); carries no tool instances of its own.
        public let surface: APISurface

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
        /// "Direct mode (skip discovery)": only `runCode` is surfaced to the
        /// agent loop; a snippet is expected to introspect the surface
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
        public var supportsFindAPIs: Bool {
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
    public let name = "runCode"
    public let description = """
        Run a JavaScript snippet against the available tools, exposed as functions under
        `tools.*`. Compose calls with normal code — variables, loops, map/filter — and
        `return` the final value (only that comes back; intermediates stay private).
        Call findAPIs first to learn exact signatures, or help()/docs(name) in-snippet.
        Errors are returned to you to fix and retry.
        """

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
    ///   - interpreter: the sandbox to run every snippet in. Defaults to a
    ///     fresh `JSCInterpreter`.
    ///   - limits: the size caps `ResultRenderer` enforces on this tool's
    ///     rendered output. Defaults to `ResultRendererLimits.default`.
    public init(
        registry: Registry,
        interpreter: any Interpreter = JSCInterpreter(),
        limits: ResultRendererLimits = .default
    ) {
        self.registry = registry
        self.interpreter = interpreter
        self.limits = limits
        self.hostFunctions = Self.makeHostFunctions(for: registry)
        self.preamble = Self.makePreamble(for: registry)
    }

    /// Runs `arguments.code` against `tools.*` and renders the outcome.
    ///
    /// Never throws for an ordinary snippet failure — a thrown
    /// `InterpreterError` (a JS exception, syntax error, or watchdog
    /// timeout) is caught here and rendered as `ResultRenderer`'s
    /// repairable-error text instead, per plan.md: "Errors are returned to
    /// you to fix and retry."
    ///
    /// - Parameter arguments: the snippet to run.
    /// - Returns: the rendered `runCode` result — the snippet's return
    ///   value (plus any captured console output) on success, or a
    ///   repairable error description on failure.
    /// - Throws: only a failure this tool cannot itself render as text —
    ///   e.g. `interpreter.run` failing for a reason other than
    ///   `InterpreterError` (not reachable through `JSCInterpreter`, kept as
    ///   a defensive passthrough for any other `Interpreter` conformer).
    public func call(arguments: RunCodeArguments) async throws -> String {
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
    /// - Parameters:
    ///   - code: the JavaScript source to run.
    ///   - installing: the host functions to expose as globals.
    ///   - interpreter: the sandbox to run `code` in.
    /// - Returns: the run's result.
    /// - Throws: whatever `interpreter.run(code:installing:)` itself throws.
    private static func run(
        code: String,
        installing: [HostFunction],
        using interpreter: any Interpreter
    ) async throws -> InterpreterResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try interpreter.run(code: code, installing: installing))
                } catch {
                    continuation.resume(throwing: error)
                }
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
    /// `APISurface.Entry.block`'s own documentation relies on for its `//
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
    ///   live tool, preceded by `var tools = {};`.
    private static func makePreamble(for registry: Registry) -> String {
        var lines = ["var tools = {};"]
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
            // Unreachable: the `Task` above always sets the box before
            // signaling the semaphore this function just woke from. Kept as
            // a defensive, reportable failure rather than a force-unwrap.
            throw InterpreterError(kind: .exception, message: "Tool bridge produced no result.")
        }
    }
}
