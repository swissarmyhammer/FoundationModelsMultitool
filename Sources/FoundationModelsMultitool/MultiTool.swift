import Foundation
import FoundationModels
import FoundationModelsExtras
import FoundationModelsMetadataRegistry
import Logging
import Tracing

extension MultiTool {
    /// The built, executable artifact `MultiTool.Builder.buildRegistry()`
    /// produces: the rendered `APISurface` paired with the wrapped `any Tool`
    /// instances a `runCode` snippet's `tools.*` calls dispatch to.
    ///
    /// `APISurface` alone cannot drive execution. It is pure data, and it
    /// carries only each tool's rendered *descriptor*, never the tool object
    /// itself. `Registry` is the pairing that closes that gap: every entry in
    /// `surface.entries` has a fully-qualified `path` (`"getWeather"`,
    /// `"github.createIssue"`, …), and `tools[path]` is that entry's live
    /// `any Tool` to invoke.
    public struct Registry: Sendable {
        /// The rendered, model-agnostic catalog — declarations, doc comments,
        /// and examples only. Backs the registry-backed selection tier's
        /// instruction prefix and `help()`/`docs()`.
        public let surface: APISurface

        /// Every wrapped tool, keyed by its fully-qualified snippet call path
        /// — `surface.entries`'s own `path`, e.g. `"getWeather"` or
        /// `"github.createIssue"`.
        public let tools: [String: any Tool]

        /// Whether this registry surfaces only `runCode`. `false`, the
        /// default, surfaces `searchTools` as well — see ``directMode()``.
        public let isDirectMode: Bool

        /// Creates a registry pairing a rendered surface with its live tool
        /// instances.
        ///
        /// Explicit because a `public` struct's synthesized initializer is
        /// `internal` only, and a caller must be able to construct a
        /// `Registry` directly.
        ///
        /// - Parameters:
        ///   - surface: the rendered, model-agnostic catalog.
        ///   - tools: every wrapped tool, keyed by `surface.entries`'s own
        ///     `path`. `MultiTool.Builder.buildRegistry()` always keeps the
        ///     two in agreement. A path present in `surface` with no matching
        ///     key here has no live dispatch target, and the generated
        ///     `tools.<path>` binding is then never set rather than crashing —
        ///     see `makePreamble(for:bindsSearchTools:)`.
        ///   - isDirectMode: whether this registry is in direct mode
        ///     (`runCode` only). Defaults to `false`.
        public init(surface: APISurface, tools: [String: any Tool], isDirectMode: Bool = false) {
            self.surface = surface
            self.tools = tools
            self.isDirectMode = isDirectMode
        }

        /// Returns a copy of this registry in **direct mode**: `runCode` is
        /// surfaced to the session and `searchTools` is not, and a snippet is
        /// then expected to introspect the surface itself with
        /// `help()`/`docs()` rather than a `searchTools` round trip.
        ///
        /// Direct mode takes discovery away and nothing else. Every mounted
        /// `runCode` call still goes to the background, and a settled run
        /// still comes back to the session as mail. The executable surface
        /// itself (`surface`/`tools`) is unchanged — only the affordance
        /// metadata (`isDirectMode`, `affordances`, `supportsSearchTools`)
        /// flips.
        public func directMode() -> Registry {
            Registry(surface: surface, tools: tools, isDirectMode: true)
        }

        /// The session-facing operations this registry surfaces —
        /// `["runCode"]` in direct mode, `["runCode", "searchTools"]`
        /// otherwise. Plain, checkable metadata for a caller or a test to read
        /// without knowing `isDirectMode`'s exact semantics.
        ///
        /// It names every tool that
        /// `makeSessionTools(selection:embedder:sampleModel:)` mounts, so
        /// the list agrees with the array a host actually receives, in every
        /// mode. No `wait` tool is in either list: a settled background run
        /// comes back to the session as mail.
        ///
        /// The order is not the mount order, and this property is not the
        /// place to learn one — see
        /// `makeSessionTools(selection:embedder:sampleModel:)`, which owns it.
        public var affordances: [String] {
            isDirectMode ? ["runCode"] : ["runCode", "searchTools"]
        }

        /// Whether this registry surfaces `searchTools` discovery — `false` in
        /// direct mode, `true` otherwise.
        public var supportsSearchTools: Bool {
            !isDirectMode
        }

        /// Builds the tools a host mounts on its session, in the order the
        /// model reads them.
        ///
        /// `searchTools` comes first and `runCode` second. A session's tool
        /// list is read as a whole before the model picks its opening move, so
        /// the list is itself the first statement of what a turn looks like
        /// here: discover what exists, then execute against what came back.
        /// Presenting `runCode` first states the opposite — that execution is
        /// the primary affordance and discovery an aside — which is the
        /// reverse of what the tool descriptions ask for.
        ///
        /// That order is vended rather than only documented because a host
        /// assembling the array by hand has to get it right every time and
        /// nothing tells it when it does not. Direct mode is folded in for
        /// the same reason: `runCode` comes back alone, so a caller never
        /// re-derives from `isDirectMode` what `supportsSearchTools` already
        /// knows.
        ///
        /// This is the whole host contract. A host builds a registry, mounts
        /// what this returns on a Router session, and drives that session by
        /// draining `streamEvents(to:)` — nothing else. In particular it
        /// passes **no session instructions**: the mounted tool descriptions
        /// carry the entire behavioral contract — see ``description``.
        ///
        /// The session type is part of the contract, not a detail. A Router
        /// session is what puts each tool through the `ToolMounting` path of
        /// FoundationModelsExtras, where the background mount `MultiTool` declares for
        /// itself takes effect. So every `runCode` call goes to the background
        /// and answers with a pending envelope. The model ends its answer, and
        /// the settled run comes back to the session as mail, which starts the
        /// next submission (Router `generation-queue.md` §5.5 rule 1). Mounted
        /// on a bare `FoundationModels.LanguageModelSession` the same tools
        /// cannot go to the background at all: the snippet simply blocks, no
        /// envelope is ever written, and no mail comes. The integration suite
        /// drives exactly this contract —
        /// `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/
        /// Support/ScenarioRunner.swift` builds every scenario session as
        /// `profile.standard.makeSession(tools:discoveryPriming:)` with no
        /// instructions, then drains `streamEvents`.
        ///
        /// The order here is deliberately not `affordances`'s. That property
        /// is a capability list, not a mount order, and only this method's
        /// result reaches the model.
        ///
        /// - Parameters:
        ///   - selection: makes `searchTools`'s selection tier for the ids of
        ///     this registry, or `nil` to leave its searcher in cheap
        ///     retrieval. Its sessions must run on a model that is not the
        ///     model of the session that mounts these tools: `searchTools` is
        ///     synchronous, and a host that queues work per model refuses a
        ///     wait on the model of the open submission. See
        ///     ``SearchToolsTool/SelectionFactory``. Unused in direct mode,
        ///     which vends no `searchTools` to configure.
        ///   - embedder: the embedder both `searchTools`'s searcher and
        ///     `runCode`'s did-you-mean ranker rank with, or `nil` (the
        ///     default) for keyword-only ranking. Without it the registry
        ///     reports `no embedder configured` on every search. The catalog
        ///     is embedded at the first search, so this call still starts
        ///     nothing and awaits nothing.
        ///   - sampleModel: the model that writes the runnable sample snippet
        ///     of `searchTools`, or `nil` (the default) to leave sample
        ///     generation unconfigured, so `searchTools` answers with
        ///     signatures alone exactly as it always has. It must also be a
        ///     model that is not the model of the session that mounts these
        ///     tools — see ``SampleSnippetConfig/model``. Unused in direct
        ///     mode.
        /// - Returns: `searchTools` and `runCode` — or `runCode` alone in
        ///   direct mode, which takes discovery away but not the background.
        /// - Throws: whatever
        ///   `SearchToolsTool.init(registry:selection:embedder:limit:sampleModel:)`
        ///   throws.
        public func makeSessionTools(
            selection: SearchToolsTool.SelectionFactory?,
            embedder: (any PooledEmbedding)? = nil,
            sampleModel: (any LanguageModel)? = nil
        ) throws -> [any Tool] {
            try makeSessionToolsAndStaging(
                selection: selection, embedder: embedder, sampleModel: sampleModel
            ).tools
        }

        /// Builds the tools a host mounts on its session, exactly as
        /// ``makeSessionTools(selection:embedder:sampleModel:)`` does, and
        /// vends beside them the `RegistryStaging` a refresher stages a rebuilt
        /// registry on.
        ///
        /// The mounted `runCode` and `searchTools` share one `RegistryHolder`.
        /// A registry staged on the returned `staging` is applied when the
        /// session calls `runCode`'s `submissionWillBegin()`, and from that tick
        /// both tools read the new surface: `tools.*`, `help()`, `docs()` and
        /// discovery swap together.
        ///
        /// A method of its own name, and not an overload: two overloads that
        /// differ in the return type alone make
        /// `let mounted = try registry.makeSessionTools(selection: nil)`
        /// ambiguous, and every caller of the old method writes exactly that.
        ///
        /// - Parameters:
        ///   - selection: see ``makeSessionTools(selection:embedder:sampleModel:)``.
        ///   - embedder: see ``makeSessionTools(selection:embedder:sampleModel:)``.
        ///   - sampleModel: see
        ///     ``makeSessionTools(selection:embedder:sampleModel:)``.
        /// - Returns: the tools in mount order, and the staging half of the
        ///   holder they share.
        /// - Throws: what ``makeSessionTools(selection:embedder:sampleModel:)``
        ///   throws.
        public func makeSessionToolsAndStaging(
            selection: SearchToolsTool.SelectionFactory?,
            embedder: (any PooledEmbedding)? = nil,
            sampleModel: (any LanguageModel)? = nil
        ) throws -> (tools: [any Tool], staging: any RegistryStaging) {
            // No `wait` tool in either mode. A wait inside a submission holds
            // the model for every session on it, and a settled background run
            // comes back to the session as mail (Router `generation-queue.md`
            // §5.5).
            guard supportsSearchTools else {
                let holder = RegistryHolder(
                    current: RegistryBundle(
                        registry: self,
                        shape: RegistryBundleShape(bindsSearchTools: false, discovery: .none, embedder: embedder)))
                return ([MultiTool(holder: holder)], holder)
            }
            let holder = RegistryHolder(
                current: RegistryBundle(
                    registry: self,
                    shape: RegistryBundleShape(
                        bindsSearchTools: true,
                        discovery: .configured(
                            selection: try SearchToolsTool.makeSelection(
                                selection, ids: surface.entries.map(\.path))),
                        embedder: embedder)))
            let searchTools = SearchToolsTool(
                holder: holder,
                sample: SearchToolsTool.makeSample(model: sampleModel)
            )
            // The same instance both ways in: mounted for the model to call
            // directly, and bound as `tools.searchTools` for a snippet that
            // reaches for it mid-run. One instance means one selection tier and
            // one sample generator, so the two doors cannot answer differently.
            let runCode = MultiTool(holder: holder, searchTools: searchTools)
            return ([searchTools, runCode], holder)
        }
    }
}

/// The arguments `MultiTool`'s `runCode` call accepts: the JavaScript snippet
/// to run against `tools.*`, and nothing else.
///
/// **Every mounted `runCode` call goes to the background, and it answers with
/// one envelope.** The call first waits for its own snippet for
/// `MultiToolConfiguration.inlineSettleGrace` (see
/// `MultiTool.inlineSettleGrace`). The `pending` field of the envelope tells
/// the model what to do:
///
/// - A snippet that settles inside that wait answers with `pending: false`,
///   the outcome of the run, and its result in `detail`. The model answers
///   from that result, and no mail comes for that run.
/// - A snippet that is still running answers with `pending: true` and a
///   completion token. A model that needs the result ends its answer, and the
///   settled run comes back to the session as mail; a model that does not need
///   it lets the snippet run (task `^cv98vff`).
///
/// The envelope shape is the same in the two cases, and its `next` sentence
/// states the action (`MultiTool.resultInstruction(forCompletionToken:)`
/// and `MultiTool.collectInstruction(forCompletionToken:)`). So the model
/// reads one field and one sentence, and not a race it cannot observe. The
/// wait is set by the host, never by the model.
///
/// This schema carries no clock, and must not grow one back. A `waitSeconds`
/// would give the model the wait that the host sets, and a `timeout` would let
/// a model bound work it does not block on. The host's own
/// `MultiToolConfiguration.executionTimeLimit` is the ceiling, and
/// `MultiTool`'s `BackgroundTool` conformance answers it to the engine as the
/// work bound of every call (see `MultiTool+Background.swift`).
@Generable
public struct RunCodeArguments {
    /// The JavaScript snippet to run against `tools.*`.
    ///
    /// The guide names no `searchTools`. The macro makes this schema one time,
    /// for the two modes, and a registry in direct mode mounts no
    /// `searchTools` (task `^bwa2p6c`). The description of `runCode` tells the
    /// model where the paths come from in each mode.
    @Guide(
        description: "JavaScript snippet to run against the available tools, exposed as functions "
            + "under `tools.*`. Call only the exact `tools.*` paths this session gave you. "
            + "Compose calls with normal code — variables, loops, map/filter — and `return` the final value; only that value "
            + "(and any console output) comes back."
    )
    public var code: String

    /// Creates `runCode`'s arguments with the given snippet.
    ///
    /// Explicit because a `public` struct's synthesized memberwise
    /// initializer is `internal` only.
    ///
    /// - Parameter code: the JavaScript snippet to run.
    public init(code: String) {
        self.code = code
    }
}

/// The `runCode` `Tool`: the execution half of the MultiTool idea — a single
/// `Tool` that wraps other, in-process `Tool`s and exposes them to the model
/// as a callable code API.
///
/// Mount through `Registry.makeSessionTools(selection:embedder:sampleModel:)`
/// rather than assembling the array by hand. That call puts `searchTools`
/// ahead of `runCode`, which is the order this package's whole
/// search-then-call premise depends on, and it drops `searchTools` under
/// `directMode()`.
///
/// Per call, `call(arguments:)`:
/// 1. builds `tools.*` glue that assigns every registry entry's real,
///    wrapped tool to its fully-qualified snippet path — flat `tools.<name>`
///    for a standalone tool, nested `tools.<group>.<name>` for a grouped
///    one — see "tools.* glue" below;
/// 2. runs the glue followed by the snippet in a fresh `Interpreter` sandbox
///    as jobs on an event loop, so a snippet that waits holds no thread
///    (see "Running the snippet"), with
///    `help()`/`docs()` and the five ambient globals — `status()`,
///    `cancel()`, `elicit()`, `notify()`, `progress()`, see
///    `MultiTool+SandboxGlobals.swift` — also installed, together with the
///    `wait` name that only tells a snippet that `wait()` is removed;
/// 3. renders the result, or a thrown `InterpreterError`, through
///    `ResultRenderer`.
///
/// Each `tools.X(...)` call is an `AsyncHostFunction`, which the interpreter's
/// own promise pump installs as a JS function returning a `Promise` — see
/// `invokeAsync` for the full dispatch.
public struct MultiTool: Tool {
    /// This tool's `Tool`-protocol name, always `"runCode"`.
    public let name = "runCode"
    /// The box that holds the catalog + live tool instances this `runCode`
    /// dispatches into, and everything precomputed from them, as one
    /// `RegistryBundle` — see `RegistryHolder`.
    ///
    /// A reference, shared by every copy of this struct and by the
    /// `searchTools` mounted beside it, so a swap at the submission boundary
    /// reaches all of them at one tick. Read one time at the top of
    /// `call(arguments:)`; the run keeps that bundle to its end. Internal,
    /// not `private`, because the submission-boundary extension applies the
    /// staged registry through it (see `MultiTool+SubmissionBoundary.swift`).
    let holder: RegistryHolder

    /// The M10 hardening knobs this tool enforces. Internal, not `private`,
    /// because the background extension reads the work clock's ceiling out of
    /// it (see `MultiTool+Background.swift`).
    let configuration: MultiToolConfiguration

    /// The sandbox this tool runs every snippet in. `any Interpreter` (not
    /// `JSCInterpreter` directly) so a test can substitute a fake — matching
    /// `Interpreter`'s own stated purpose ("the engine is swappable without
    /// touching callers").
    private let interpreter: any Interpreter

    /// The size caps `ResultRenderer` enforces on this tool's rendered
    /// output.
    private let limits: ResultRendererLimits

    /// Creates a `runCode` tool over `registry`, in a holder of its own.
    ///
    /// A tool made here swaps alone: `stage(_:)` and `submissionWillBegin()` reach
    /// its holder, and no `searchTools` shares it. A host that mounts both
    /// uses `Registry.makeSessionToolsAndStaging(selection:embedder:sampleModel:)`,
    /// which gives the two one holder.
    ///
    /// - Parameters:
    ///   - registry: the catalog + live tool instances to expose as
    ///     `tools.*`.
    ///   - configuration: see ``init(holder:configuration:interpreter:limits:searchTools:depth:)``.
    ///   - interpreter: see ``init(holder:configuration:interpreter:limits:searchTools:depth:)``.
    ///   - limits: see ``init(holder:configuration:interpreter:limits:searchTools:depth:)``.
    ///   - searchTools: the mounted discovery tool a snippet reaches as
    ///     `tools.searchTools`. Defaults to `nil`, which binds no such path.
    ///   - depth: see ``init(holder:configuration:interpreter:limits:searchTools:depth:)``.
    public init(
        registry: Registry,
        configuration: MultiToolConfiguration = .default,
        interpreter: (any Interpreter)? = nil,
        limits: ResultRendererLimits? = nil,
        searchTools: (any Tool)? = nil,
        depth: Int = 0
    ) {
        self.init(
            holder: RegistryHolder(
                current: RegistryBundle(
                    registry: registry,
                    shape: RegistryBundleShape(
                        bindsSearchTools: searchTools != nil, discovery: .none, embedder: nil))),
            configuration: configuration,
            interpreter: interpreter,
            limits: limits,
            searchTools: searchTools,
            depth: depth
        )
    }

    /// Creates a `runCode` tool over `holder`, the box it reads its bundle
    /// from at the top of every call.
    ///
    /// - Parameters:
    ///   - holder: the box that holds the catalog + live tool instances to
    ///     expose as `tools.*`, and everything precomputed from them. Shared
    ///     with the `searchTools` mounted beside this tool, when there is one.
    ///   - configuration: the hardening knobs — the work clock's ceiling, the
    ///     inline settle grace, the return and console caps — this tool
    ///     enforces. Defaults to `MultiToolConfiguration.default`. An
    ///     explicitly supplied `limits` wins over the value derived from it.
    ///   - interpreter: the sandbox to run every snippet in. Defaults to a
    ///     fresh `JSCInterpreter`. This tool runs the sandbox as it is. An
    ///     interpreter has no clock: the one outer timeout of a call is the
    ///     tool-level timeout (``timeout(from:)``), and it cancels the run.
    ///   - limits: the size caps `ResultRenderer` enforces on this tool's
    ///     rendered output. Defaults to `configuration.resultLimits`.
    ///   - searchTools: the mounted discovery tool a snippet reaches as
    ///     `tools.searchTools`. Defaults to `nil`, which binds no such path —
    ///     `Registry.makeSessionTools(selection:embedder:sampleModel:)` passes the
    ///     instance it mounts so both doors share one configuration.
    ///   - depth: how many enclosing `tools.runCode` calls this run sits
    ///     inside. Defaults to `0`, the depth of a run the model started;
    ///     ``maxRunCodeDepth`` is where nesting stops.
    init(
        holder: RegistryHolder,
        configuration: MultiToolConfiguration = .default,
        interpreter: (any Interpreter)? = nil,
        limits: ResultRendererLimits? = nil,
        searchTools: (any Tool)? = nil,
        depth: Int = 0
    ) {
        self.holder = holder
        self.configuration = configuration
        self.interpreter = interpreter ?? JSCInterpreter()
        self.limits = limits ?? configuration.resultLimits
        self.searchTools = searchTools
        self.depth = depth
    }

    /// The mounted discovery tool a snippet reaches as `tools.searchTools`, or
    /// `nil` when this registry mounts none.
    ///
    /// The same instance the session mounts as its own tool, so a snippet and
    /// the model's direct call share one selection tier and one sample generator.
    private let searchTools: (any Tool)?

    /// How many enclosing `tools.runCode` calls this run sits inside.
    ///
    /// `0` for a run the model started. Each nested call runs at one deeper,
    /// and ``maxRunCodeDepth`` is where nesting stops. Internal, because
    /// `timeout(from:)` in `MultiTool+Background.swift` reads it: a nested run
    /// states no clock of its own.
    let depth: Int

    /// How deeply `tools.runCode` may nest before a call is refused.
    ///
    /// A snippet composing a nested run needs one level; a nested run that
    /// itself composes needs two. Three leaves room for that and still bounds
    /// a snippet that recurses without a base case, which would otherwise
    /// spend the whole turn's time limit before returning anything.
    static let maxRunCodeDepth = 3

    /// Runs `arguments.code` against `tools.*` and renders the outcome.
    ///
    /// Never throws for an ordinary snippet failure. A thrown
    /// `InterpreterError` — a JS exception or a syntax error — is caught
    /// here and rendered as `ResultRenderer`'s
    /// repairable-error text instead, because errors are returned to the
    /// model to fix and retry. A cancelled enclosing `Task`, however, is
    /// never rendered as text: cancelling the task running this call
    /// terminates the in-flight snippet, so `CancellationError` always
    /// propagates unchanged. Nor is a lost inner call: a `tools.*` call whose
    /// transport dropped under it throws a `LostRunError`, and once the
    /// snippet has finished this call throws that error, whatever the snippet
    /// went on to do, so the engine settles this run as `.lost` — see
    /// ``LostRunRecord``.
    ///
    /// No number limits how many calls run at the same time. A snippet that
    /// waits for a `tools.*` call holds no thread, only its context in memory
    /// (see the event-loop documentation of `JSCInterpreter`).
    ///
    /// - Parameter arguments: the snippet to run.
    /// - Returns: the rendered `runCode` result — the snippet's return
    ///   value (plus any captured console output) on success, or a
    ///   repairable error description on failure.
    /// - Throws: `CancellationError` if the calling `Task` is cancelled
    ///   before or during the run; the `LostRunError` an inner `tools.*` call
    ///   threw, once the snippet has finished; otherwise only a failure this
    ///   tool cannot itself render as text — e.g. `interpreter.run` failing
    ///   for a reason other than `InterpreterError`/`CancellationError` (not
    ///   reachable through `JSCInterpreter`, kept as a defensive passthrough
    ///   for any other `Interpreter` conformer).
    public func call(arguments: RunCodeArguments) async throws -> String {
        // A `MultiTool` that is called directly, outside each session, has no
        // ambient `ToolContext`, thus no completion token.
        let completionToken = ToolContext.current?.completionToken
        return try await MultitoolTelemetry.traced(
            .runCode, attributes: [.toolName: name, .depth: depth, .completionToken: completionToken]
        ) { span in
            let rendered = try await runSnippet(arguments: arguments)
            span.attributes[MultitoolTelemetry.AttributeKey.outputCharacters.rawValue] = rendered.count
            return rendered
        }
    }

    /// Runs one `runCode` call, inside the span ``call(arguments:)`` opened.
    ///
    /// Split out so the span wraps the *whole* call: a call cancelled before
    /// it ever reaches the sandbox has to be as visible as one that reaches
    /// the interpreter.
    ///
    /// Returns and throws what ``call(arguments:)`` does.
    private func runSnippet(arguments: RunCodeArguments) async throws -> String {
        try Task.checkCancellation()
        // Read one time, here, and kept to the end of this run: a registry
        // staged on the holder is applied at the next submission boundary, and
        // "an in-flight run keeps the registry that it started with" — see
        // `RegistryHolder`.
        let bundle = holder.current
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
        // One ledger per invocation, for the same reason as the notice chain
        // above: it records what *this* run's `tools.*` calls returned, and
        // `call(arguments:)` reads it back once the snippet has finished (see
        // ``ToolReturnLedger``).
        let ledger = ToolReturnLedger()
        // One record per invocation, for the same reason again: it notes the
        // `LostRunError` an inner call of *this* run threw, and the check
        // below reads it back once the snippet has finished (see
        // ``LostRunRecord``).
        let lostRuns = LostRunRecord()
        // One record per invocation, once more: it holds the inner `tools.*`
        // calls of *this* run that are in flight, so the cancellation of this
        // run reaches each of them at once (see ``InFlightInnerCalls``).
        let inFlight = InFlightInnerCalls()
        let code = "\(bundle.preamble)\n\(arguments.code)"
        let outcome = await Self.runCapturingOutcome(
            code: code,
            installing: bundle.hostFunctions + Self.makeNoticeHostFunctions(outbox: notices)
                + Self.makeRemovedGlobalHostFunctions(),
            installingAsync: makeAsyncHostFunctions(
                over: bundle, binding: binding, recordingInto: ledger, noting: lostRuns,
                holding: inFlight)
                + Self.makeBackgroundRunHostFunctions(binding: binding),
            using: interpreter,
            cancelling: inFlight
        )
        // "They enqueue and continue; the bridge flushes them" — the flush,
        // before this call hands anything back, so a run's last notice never
        // reaches the session after the run's own result does. On the failure
        // path too: a notice a snippet already made happened, whatever the
        // snippet went on to do.
        await notices?.flush()
        // A lost inner call makes the outcome of this whole run unknowable,
        // whatever the snippet returned or threw, so it is thrown ahead of
        // the rendering — the engine settles this run as `.lost`.
        if let lost = lostRuns.lostError {
            throw lost
        }
        switch outcome {
        case .success(let result):
            return ResultRenderer.render(
                result,
                limits: limits,
                notice: uncarriedReturnNotice(from: ledger, for: result.returnValue)
            )
        case .failure(let interpreterError as InterpreterError):
            let resolution = await UnknownToolHint.hint(
                message: interpreterError.message,
                // `arguments.code`, never `code`: the preamble prepended above
                // spells out every real `tools.*` path, so handing the glue to
                // a rule that asks what the *model* reached for would find a
                // real path every time.
                snippet: arguments.code,
                surface: bundle.registry.surface,
                searcher: bundle.hintSearcher
            )
            if let resolution {
                Self.logImaginedTool(resolution)
            }
            // The `tools.*` hint comes first. A message that names an
            // unknown path is about that path, and a message about a missing
            // Node.js global (see ``UnavailableGlobalHint``) names no path.
            return ResultRenderer.render(
                interpreterError,
                hint: resolution?.text ?? UnavailableGlobalHint.hint(message: interpreterError.message),
                directive: resolution?.directive ?? .repairSnippet
            )
        case .failure(let error):
            throw error
        }
    }

    /// The in-band notice this run's rendered result closes with, or `nil`
    /// when it closes with the value alone.
    ///
    /// Only a run the model started carries one. A nested `tools.runCode`
    /// result is read by a *snippet* — `makeNestedRunCodeHostFunction` decodes
    /// the rendered text back into a value — so a sentence appended there
    /// would reach JavaScript rather than the model, where the teaching has no
    /// reader and the decode has one more thing to fail on.
    private func uncarriedReturnNotice(
        from ledger: ToolReturnLedger, for returnValue: InterpreterValue
    ) -> String? {
        guard depth == 0 else { return nil }
        return ledger.notice(forReturnValue: returnValue)
    }

    // MARK: - Running the snippet

    /// Runs one snippet and captures its outcome instead of throwing it, so
    /// `call(arguments:)` can flush the invocation's notice chain on both the
    /// success and the failure path before deciding what to hand back.
    ///
    /// The call awaits the run directly. `Interpreter.run` is `async`, and a
    /// run that waits for a `tools.*` call holds no thread (see the
    /// event-loop documentation of `JSCInterpreter`), so no bridge to a
    /// dispatch queue stands between this call and the run.
    ///
    /// Cancelling the `Task` running `call(arguments:)` reaches the run
    /// through the cancellation of this task, and reaches every inner
    /// `tools.*` call of the run that is in flight at once, through
    /// `inFlight` (see ``InFlightInnerCalls`` for why).
    ///
    /// A cancelled call answers `CancellationError` whatever the snippet did
    /// once the cancellation reached it. The cancellation reaches the inner
    /// `tools.*` calls first, and a snippet that catches the rejection of
    /// one — or that fails on it — can finish with a value or a repairable
    /// error before the run reads the cancellation. Neither is the answer of
    /// a cancelled call: `call(arguments:)` promises that a cancellation
    /// "always propagates unchanged".
    ///
    /// - Parameters:
    ///   - code: the JavaScript source to run.
    ///   - installing: host functions to expose as globals for this run only.
    ///   - installingAsync: asynchronous host functions to expose as globals
    ///     for this run only.
    ///   - interpreter: the sandbox to run the snippet in.
    ///   - inFlight: the inner `tools.*` calls of this run, cancelled with it.
    /// - Returns: the outcome of the run, or `CancellationError` when the
    ///   calling `Task` was cancelled.
    private static func runCapturingOutcome(
        code: String,
        installing: [HostFunction],
        installingAsync: [AsyncHostFunction],
        using interpreter: any Interpreter,
        cancelling inFlight: InFlightInnerCalls
    ) async -> Result<InterpreterResult, Error> {
        let outcome: Result<InterpreterResult, Error>
        do {
            outcome = .success(
                try await withTaskCancellationHandler {
                    try await interpreter.run(code: code, installing: installing, installingAsync: installingAsync)
                } onCancel: {
                    inFlight.cancelAll()
                }
            )
        } catch {
            outcome = .failure(error)
        }
        guard !Task.isCancelled else { return .failure(CancellationError()) }
        return outcome
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
    ///
    /// Internal, not `private`: `RegistryBundle` holds the list.
    struct LiveTool: Sendable {
        /// The entry's flat host-function name — see `hostFunctionName(at:)`.
        let hostFunctionName: String

        /// The live tool a `tools.<path>(…)` call dispatches into.
        let tool: any Tool

        /// The `"verb noun"` string this entry's runs journal as their `op`, or
        /// `nil` for a standalone entry that was registered under no noun — see
        /// `APISurface.Entry.journalOp`, which derives it from the same pair the
        /// entry's `path` comes from.
        let journalOp: String?
    }

    /// The positional host-function name for `registry.surface.entries[index]`
    /// — shared by `makeLiveTools`, which names it, and `makePreamble`, which
    /// assigns it into `tools.*`, so the two always agree on naming without
    /// either duplicating the scheme.
    private static func hostFunctionName(at index: Int) -> String {
        "__tool\(index)"
    }

    /// Pairs every registry entry that has a live tool with the flat
    /// host-function name it installs under.
    ///
    /// One pairing per entry with a matching `registry.tools[path]`, in the
    /// same order as `registry.surface.entries`.
    ///
    /// Internal, not `private`: `RegistryBundle.init` builds the list.
    static func makeLiveTools(for registry: Registry) -> [LiveTool] {
        var liveTools: [LiveTool] = []
        for (index, entry) in registry.surface.entries.enumerated() {
            guard let tool = registry.tools[entry.path] else { continue }
            liveTools.append(
                LiveTool(
                    hostFunctionName: hostFunctionName(at: index),
                    tool: tool,
                    journalOp: entry.journalOp
                )
            )
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
    /// Every binding is wrapped so `ledger` sees what it returned, which is
    /// what lets `call(arguments:)` tell a snippet that reported a value from
    /// one that promised it (see ``ToolReturnLedger``), so `lostRuns`
    /// sees the `LostRunError` it threw, which is what lets `call(arguments:)`
    /// throw it once the snippet has finished (see ``LostRunRecord``), and so
    /// `inFlight` holds it while it runs, which is what lets the cancellation
    /// of this run reach it at once (see ``InFlightInnerCalls``). The wraps
    /// are applied to the whole list at once rather than at each construction
    /// site, so no binding added later can be left out of any record by
    /// omission.
    ///
    /// Each live tool's binding carries that tool's own `journalOp`, so a verb
    /// registered under a noun journals the `"verb noun"` pair. `searchTools`
    /// and the nested `runCode` are session-level operations that no noun was
    /// registered under, so each keeps the engine's own default of stamping
    /// `op` with the tool's name.
    ///
    /// - Parameters:
    ///   - bundle: the bundle this run read at its start, whose `liveTools`
    ///     the bindings dispatch into.
    ///   - binding: the captured session binding of this run, or `nil`.
    ///   - ledger: the record of what each binding returned.
    ///   - lostRuns: the record of the `LostRunError` a binding threw.
    ///   - inFlight: the record of the bindings in flight.
    /// - Returns: one `AsyncHostFunction` per live tool, in `liveTools`'
    ///   order.
    private func makeAsyncHostFunctions(
        over bundle: RegistryBundle,
        binding: RunBinding?, recordingInto ledger: ToolReturnLedger, noting lostRuns: LostRunRecord,
        holding inFlight: InFlightInnerCalls
    ) -> [AsyncHostFunction] {
        // Captured here, in the task of the `runCode` call and in its span,
        // and not in the host functions: the interpreter calls them from its
        // own thread, which has no task-local value of the call (see
        // `MultitoolTelemetry.Scope`).
        let scope = MultitoolTelemetry.Scope.current
        let logger = scope.logger
        var functions = bundle.liveTools.map { liveTool in
            AsyncHostFunction(name: liveTool.hostFunctionName) { arguments in
                try await Self.invokeAsync(
                    tool: liveTool.tool,
                    arguments: arguments,
                    binding: binding,
                    journalOp: liveTool.journalOp,
                    logger: logger
                )
            }
        }
        if let searchTools {
            functions.append(
                AsyncHostFunction(name: Self.searchToolsHostName) { arguments in
                    try await Self.invokeAsync(
                        tool: searchTools,
                        arguments: Self.widenedToObject(arguments, field: Self.searchToolsTaskField),
                        binding: binding,
                        logger: logger
                    )
                }
            )
        }
        functions.append(makeNestedRunCodeHostFunction(over: bundle))
        return functions.map {
            scope.bind(Self.recording($0, into: ledger, noting: lostRuns, holding: inFlight))
        }
    }

    /// Wraps one `tools.*` binding so this run's ledger sees the value it
    /// handed back, this run's record sees the `LostRunError` it threw, and
    /// this run's in-flight record holds it while it runs. The wrapper keeps
    /// the same name.
    ///
    /// - Parameters:
    ///   - function: the binding to wrap.
    ///   - ledger: the record of what the binding returned.
    ///   - lostRuns: the record of the `LostRunError` the binding threw.
    ///   - inFlight: the record that holds the binding while it runs.
    /// - Returns: the wrapped binding.
    private static func recording(
        _ function: AsyncHostFunction, into ledger: ToolReturnLedger, noting lostRuns: LostRunRecord,
        holding inFlight: InFlightInnerCalls
    ) -> AsyncHostFunction {
        AsyncHostFunction(name: function.name) { arguments in
            try await inFlight.running {
                try await lostRuns.noting {
                    try await ledger.recording { try await function.call(arguments) }
                }
            }
        }
    }

    /// The error `tools.runCode` throws when a snippet nests past
    /// ``maxRunCodeDepth``.
    ///
    /// `JSCInterpreter.install` turns a thrown Swift error into a JS exception
    /// the renderer then hands back as a repairable error, so its text is
    /// written as the repair instruction the model reads.
    struct NestedRunCodeDepthExceeded: Error, CustomStringConvertible {
        /// The nesting depth that was exceeded.
        let limit: Int

        /// The repair instruction handed back to the model.
        var description: String {
            "tools.runCode nests at most \(limit) deep, and this call is deeper. Write the "
                + "remaining work inline in this snippet instead of nesting another runCode."
        }
    }

    /// The field ``searchToolsPath`` reads its query from.
    static let searchToolsTaskField = "task"

    /// The field ``runCodePath`` reads its snippet from.
    static let runCodeSnippetField = "code"

    /// Wraps a bare scalar argument into the single-field object a `Tool`'s
    /// `@Generable` arguments decode from.
    ///
    /// The generated signatures take an object, so `tools.name({ … })` is the
    /// documented call. A model that reads `searchTools(task)` in prose writes
    /// `tools.searchTools("…")` instead, which is the same intent — task
    /// `bwk7knm` chose to accept it rather than correct it. An argument list
    /// that is already an object, or is empty, is handed through unchanged;
    /// `field` names the single field a bare scalar stands for.
    private static func widenedToObject(
        _ arguments: [InterpreterValue], field: String
    ) -> [InterpreterValue] {
        guard let first = arguments.first else { return arguments }
        switch first {
        case .object:
            return arguments
        default:
            return [.object([field: first])] + arguments.dropFirst()
        }
    }

    /// Reads the snippet out of a `tools.runCode` argument list.
    ///
    /// Accepts the bare string a model writes first, and the object form the
    /// generated signatures otherwise teach, under either `code` or `snippet`.
    /// Answers `nil` when no argument carries one.
    private static func snippetArgument(_ arguments: [InterpreterValue]) -> String? {
        switch arguments.first {
        case .string(let snippet):
            return snippet
        case .object(let fields):
            for key in [runCodeSnippetField, "snippet"] {
                if case .string(let snippet)? = fields[key] { return snippet }
            }
            return nil
        default:
            return nil
        }
    }

    /// The error `tools.runCode` throws when a nested run did not settle on a
    /// plain value.
    ///
    /// Carries the nested run's own rendered text, so whatever it says — a
    /// repairable error, a truncation note — reaches the snippet that asked
    /// for it rather than being flattened into "something went wrong".
    struct NestedRunCodeFailed: Error, CustomStringConvertible {
        /// The nested run's rendered output.
        let rendered: String

        /// The nested output, handed to the snippet unchanged.
        var description: String { rendered }
    }

    /// Builds the host function behind `tools.runCode` — one nested snippet
    /// run, one level deeper than this one.
    ///
    /// Refuses past ``maxRunCodeDepth`` rather than recursing further, so a
    /// snippet with no base case ends with a repairable error naming the
    /// limit instead of spending the run's whole time budget.
    ///
    /// The nested run gets a holder of its own over `bundle`, the bundle
    /// this run read at its start, so a nested snippet resolves the same
    /// surface as the snippet that started it: a swap at the submission boundary
    /// reaches neither of them.
    ///
    /// - Parameter bundle: the bundle this run read at its start.
    private func makeNestedRunCodeHostFunction(over bundle: RegistryBundle) -> AsyncHostFunction {
        let depth = depth
        let nested = MultiTool(
            holder: RegistryHolder(current: bundle),
            configuration: configuration,
            limits: limits,
            searchTools: searchTools,
            depth: depth + 1
        )
        return AsyncHostFunction(name: Self.runCodeHostName) { arguments in
            guard depth + 1 < Self.maxRunCodeDepth else {
                throw NestedRunCodeDepthExceeded(limit: Self.maxRunCodeDepth)
            }
            guard let snippet = Self.snippetArgument(arguments) else {
                throw ToolInvokerError(
                    kind: .missingRequiredField,
                    field: Self.runCodeSnippetField,
                    message: "tools.runCode takes the JavaScript snippet to run — either as a string, "
                        + "`tools.runCode(\"return 1;\")`, or as `tools.runCode({ code: \"return 1;\" })`."
                )
            }
            let rendered = try await nested.call(arguments: RunCodeArguments(code: snippet))
            // A nested run hands back a *value*, not the text an outer caller
            // would read: `await tools.runCode("return 1 + 1;")` is 2, not
            // "2". `call` renders, so decode the render back. Anything that is
            // not a bare JSON value — a repairable error, or a render carrying
            // a console section — cannot decode, and is thrown instead so the
            // snippet sees a catchable exception carrying the nested run's own
            // diagnostics rather than a string it has to parse.
            guard let value = try? JSONDecoder().decode(InterpreterValue.self, from: Data(rendered.utf8)) else {
                throw NestedRunCodeFailed(rendered: rendered)
            }
            return value
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
    /// An entry with no matching `registry.tools[path]` is skipped entirely,
    /// exactly like `makeLiveTools`'s own `guard`. The two must agree: a
    /// skipped entry here has no host function for `makeLiveTools` to name,
    /// so emitting `tools.<path> = __toolN;` regardless would reference an
    /// *undeclared* JS identifier — a `ReferenceError`, since that global was
    /// never installed. Skipping the assignment instead leaves `tools.<path>`
    /// never set, so reading it evaluates to `undefined` like any other
    /// absent property.
    ///
    /// - Parameters:
    ///   - registry: the catalog + live tool instances to build glue for.
    ///   - bindsSearchTools: whether to bind ``searchToolsPath``. `false` when
    ///     this registry mounts no discovery tool, so the path is absent
    ///     rather than bound to a host function that was never installed.
    /// - Returns: the JS preamble, one `tools.*` assignment per entry with a
    ///   live tool, preceded by `globalThis.tools = {};`, by the void
    ///   re-binding of every name in `voidGlobalNames`, and by the sibling
    ///   paths this tool binds itself.
    ///
    /// Internal, not `private`: `RegistryBundle.init` builds the preamble.
    static func makePreamble(for registry: Registry, bindsSearchTools: Bool) -> String {
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
        // Emitted before the registry's own entries, so a host that mounts a
        // tool of the same name binds over ours rather than being shadowed.
        if bindsSearchTools {
            lines += siblingBindingLines(path: searchToolsPath, hostName: searchToolsHostName)
        }
        lines += siblingBindingLines(path: runCodePath, hostName: runCodeHostName)
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

    /// The `tools.*` path — and the host-function name behind it — a snippet
    /// reaches the mounted discovery tool by.
    ///
    /// The model reached for this path unprompted and got an invented-path
    /// error, burning a whole turn (task `bwk7knm`). It is a real binding now.
    /// Named the same on both sides so the preamble reads as the identity it
    /// is. Nothing reserves the name: a registry that mounts its own tool
    /// called `searchTools` binds over this one, because the preamble emits
    /// the siblings before the registry's own entries and a host's tools
    /// should never be shadowed by ours.
    static let searchToolsPath = "searchTools"

    /// The flat global ``searchToolsPath``'s binding installs under.
    ///
    /// `__`-prefixed like every registry tool's `__tool<N>`, for the same
    /// reason: the preamble moves it into `tools.*` and the flat name is not
    /// part of the sandbox's documented global surface (`HardeningTests`
    /// enumerates that set and pins it against README).
    static let searchToolsHostName = "__searchTools"

    /// The `tools.*` path — and the host-function name behind it — a snippet
    /// reaches a nested `runCode` by.
    ///
    /// Recursion, bounded by ``maxRunCodeDepth``.
    static let runCodePath = "runCode"

    /// The flat global ``runCodePath``'s binding installs under.
    ///
    /// `__`-prefixed for the same reason as ``searchToolsHostName``.
    static let runCodeHostName = "__runCode"

    /// The preamble lines that move one sibling host function into its
    /// `tools.*` path.
    ///
    /// The flat `__`-prefixed name is how the interpreter installs a host
    /// function, not part of the sandbox's surface, so it is unbound once the
    /// path holds it: leaving it would add a global the README's "Injected
    /// globals" list does not name, which `HardeningTests` enumerates and pins.
    ///
    /// - Returns: the assignment and the delete, in that order.
    private static func siblingBindingLines(path: String, hostName: String) -> [String] {
        [
            "tools.\(path) = \(hostName);",
            "delete globalThis.\(hostName);",
        ]
    }

    /// The `tools.*` paths this tool binds itself, beyond the registry's own
    /// entries.
    ///
    /// `UnknownToolHint` unions these with the catalog before deciding a path
    /// is invented: they are real bindings, so a snippet that calls one must
    /// not be told it does not exist.
    static let siblingToolPaths: Set<String> = [searchToolsPath, runCodePath]

    // MARK: - The async host-function bridge (eventplan.md "Async JavaScript")

    /// Bridges one `tools.<name>(...)` call into the wrapped tool's real
    /// `async` `call(arguments:)`.
    ///
    /// The call runs in a `tools.dispatch` span, with its enter record (see
    /// ``MultitoolTelemetry/SpanName/toolsDispatch``). This is the one path
    /// of each `tools.*` call of a snippet, for both mounts. The span is a
    /// child of the `runCode` span because `makeAsyncHostFunctions` binds the
    /// telemetry scope of the `runCode` call around this call.
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
    /// also selects the mount: through the background engine in
    /// run-to-completion mode when a session bound one, natively when none did
    /// (see `ToolInvoker`'s "The two mounts").
    ///
    /// - Parameters:
    ///   - tool: the wrapped tool this call dispatches to.
    ///   - arguments: the JS call's arguments, already converted to
    ///     `InterpreterValue` by `JSCInterpreter`. A well-formed call always
    ///     supplies exactly one JS object — `tools.name({ … })`, object and
    ///     named parameters, always. A missing or non-object first argument
    ///     is treated as `{}` and surfaces as an ordinary
    ///     `ArgumentMarshalerError`/`ToolInvokerError` below, never a crash.
    ///   - binding: the enclosing `runCode` invocation's captured session
    ///     binding, or `nil` when it has none.
    ///   - journalOp: the `"verb noun"` string this call's run journals as its
    ///     `op`, or `nil` for a tool registered under no noun.
    ///   - logger: the logger of the run, made in the task of the `runCode`
    ///     call. This call runs in a task that the interpreter starts on its
    ///     own thread, which has no task-local value of that call.
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
        binding: RunBinding?,
        journalOp: String? = nil,
        logger: Logging.Logger
    ) async throws -> InterpreterValue {
        // The completion token is the one of the outer `runCode` run, when a
        // session bound one.
        let attributes = MultitoolTelemetry.journalAttributes(of: journalOp)
            .merging([.toolName: tool.name, .completionToken: binding?.context.completionToken]) { $1 }
        return try await MultitoolTelemetry.traced(.toolsDispatch, attributes: attributes) { _ in
            let start = ContinuousClock.now
            let toolName = MultitoolTelemetry.toolNameMetadata(tool.name)
            logger.log(.toolInvocationStarted, level: .debug, metadata: toolName)
            do {
                let value = try await performInvocation(
                    tool: tool, arguments: arguments, binding: binding, journalOp: journalOp)
                logger.log(
                    .toolInvocationFinished, level: .debug,
                    metadata: toolName.merging(MultitoolTelemetry.durationMetadata(since: start)) { $1 })
                return value
            } catch {
                logInvocationFailure(tool: tool, error: error, to: logger)
                throw error
            }
        }
    }

    /// Records one imagined `tools.*` path a snippet reached for, so a host
    /// can mine its own log for the names its model expects.
    ///
    /// **Why this is logged at all.** An imagined name is free evidence about
    /// the catalog: it is the model saying what it thought the tool should be
    /// called. Accumulated across real sessions, those guesses rank the
    /// synonyms a host's naming, or an alias table, should cover. Nothing
    /// else on this route records them — the hint is rendered into the
    /// model's error text and discarded.
    ///
    /// **Why `.notice`.** The corpus has to survive an ordinary host run to
    /// be worth mining. A host usually drops `.debug` and `.info` records.
    /// `.notice` is the lowest level that a host usually keeps. Not
    /// `.warning` or `.error`: the records at those levels in this file report
    /// a failure that a host must act on, and an imagined name is not one.
    ///
    /// **No content.** Each value is a name or a fixed word, and carries no
    /// user data: `imaginedPath` is a name the model made up,
    /// `suggestedPaths` are the host's own tool names, and the tier is one of
    /// four fixed words. The message is constant, and
    /// `UnknownToolHint.Resolution.logMetadata` holds exactly those three
    /// values. Nothing from the arguments of a snippet, the output of a tool,
    /// or the prompt of the user is in the record.
    private static func logImaginedTool(_ resolution: UnknownToolHint.Resolution) {
        MultitoolTelemetry.logger.log(.imaginedTool, level: .notice, metadata: resolution.logMetadata)
    }

    /// Logs one `tools.*` invocation's failure, distinguishing a pre-call
    /// **validation failure** — `ToolInvokerError`/`ArgumentMarshalerError`,
    /// logged at `.warning`, because the snippet's call was malformed and not
    /// the tool itself — from any other failure, which is the tool's own
    /// thrown error and is logged at `.error`.
    ///
    /// The record carries the name of the tool and the type and code of the
    /// error, and never the text of the error: a validation message can hold
    /// an argument value, and the error of a tool can hold its input or its
    /// output.
    ///
    /// - Parameters:
    ///   - tool: the tool whose call failed.
    ///   - error: what the call threw.
    ///   - logger: the logger of the run — see `invokeAsync`.
    private static func logInvocationFailure(tool: any Tool, error: Error, to logger: Logging.Logger) {
        let metadata = MultitoolTelemetry.toolNameMetadata(tool.name)
            .merging(MultitoolTelemetry.errorMetadata(of: error)) { $1 }
        switch error {
        case is ToolInvokerError:
            logger.log(.toolArgumentValidationFailed, level: .warning, metadata: metadata)
        case is ArgumentMarshalerError:
            logger.log(.toolArgumentMarshalingFailed, level: .warning, metadata: metadata)
        default:
            logger.log(.toolInvocationFailed, level: .error, metadata: metadata)
        }
    }

    /// The actual marshal → validate → call → render pipeline `invokeAsync`
    /// wraps with start and end logging. `binding` selects `ToolInvoker`'s
    /// mount. See `invokeAsync` for every parameter, the return value, and
    /// the failures this can throw.
    private static func performInvocation(
        tool: any Tool,
        arguments: [InterpreterValue],
        binding: RunBinding?,
        journalOp: String? = nil
    ) async throws -> InterpreterValue {
        let argumentObject = arguments.first ?? .object([:])
        let content = try ArgumentMarshaler.marshalArguments(argumentObject)
        let output = try await ToolInvoker.invoke(
            tool, content: content, binding: binding, journalOp: journalOp)
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
    // instruction prefix and `searchTools` are built from (M2.5/M6) — plan.md's
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
    /// Synchronous, and installed *inside* the sandbox, so a snippet can
    /// confirm the surface and keep going in the same call. Every recorded
    /// plan-and-stop happens at the `searchTools` → `runCode` turn boundary,
    /// and this path removes the boundary.
    ///
    /// Internal, not `private`: `RegistryBundle.init` builds the pair.
    static func makeHelpDocsHostFunctions(for registry: Registry) -> [HostFunction] {
        [
            HostFunction(name: "help") { _ in
                .array(registry.surface.entries.map { .string($0.path) })
            },
            HostFunction(name: "docs") { arguments in
                .string(renderDocs(for: arguments.first, in: registry.surface))
            },
        ]
    }

    /// Renders `docs(name)`'s result: the exact `APISurface.Entry.block` for
    /// the entry whose `path` matches `name`, reused rather than re-rendered.
    ///
    /// When `name` matches no entry — which includes `argument` not being a
    /// string at all — the result is an error naming the closest known names,
    /// never a crash.
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
    /// distance — a deliberately simple fuzzy match, good enough to point a
    /// model at the right function after a typo'd `docs()` call.
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
    /// A standard two-row dynamic-programming implementation. It operates
    /// over `Character`s — extended grapheme clusters — rather than raw
    /// UTF-8/UTF-16 units, matching this package's established posture toward
    /// user- and schema-derived text; `ResultRendererLimits` gives the same
    /// reasoning for its truncation caps.
    ///
    /// Two rows rather than the textbook's full
    /// `(a.count + 1) x (b.count + 1)` matrix, because row `i` only ever
    /// reads from row `i-1` and itself. That trades `O(a.count * b.count)`
    /// space for `O(b.count)`, at no cost to the `O(a.count * b.count)` time,
    /// and the only ingredient `nearestMatches` needs is the final
    /// `previousRow[b.count]`.
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
