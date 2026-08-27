import Foundation
import FoundationModels
import FoundationModelsMetadataRegistry
import FoundationModelsRouter
import os

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

        /// Returns a copy of this registry in **direct mode**: `runCode` and
        /// `wait` are surfaced to the session and `searchTools` is not, and a
        /// snippet is then expected to introspect the surface itself with
        /// `help()`/`docs()` rather than a `searchTools` round trip.
        ///
        /// Direct mode takes discovery away and nothing else. `wait` stays,
        /// because every mounted `runCode` call goes to the background and the
        /// model still needs a deliberate join. The executable surface itself
        /// (`surface`/`tools`) is unchanged — only the affordance metadata
        /// (`isDirectMode`, `affordances`, `supportsSearchTools`) flips.
        public func directMode() -> Registry {
            Registry(surface: surface, tools: tools, isDirectMode: true)
        }

        /// The session-facing operations this registry surfaces —
        /// `["runCode", "wait"]` in direct mode, `["runCode", "searchTools",
        /// "wait"]` otherwise. Plain, checkable metadata for a caller or a
        /// test to read without knowing `isDirectMode`'s exact semantics.
        ///
        /// **`wait` appears in both arms because
        /// `makeSessionTools(librarian:sampleGenerator:)` mounts it in both.**
        /// Direct mode takes discovery away and nothing else, so a list that
        /// named only `runCode` and `searchTools` would disagree with the
        /// array a host actually receives, in every mode.
        ///
        /// The order is not the mount order, and this property is not the
        /// place to learn one — see
        /// `makeSessionTools(librarian:sampleGenerator:)`, which owns it.
        public var affordances: [String] {
            isDirectMode ? ["runCode", "wait"] : ["runCode", "searchTools", "wait"]
        }

        /// Whether this registry surfaces `searchTools` discovery — `false` in
        /// direct mode, `true` otherwise.
        public var supportsSearchTools: Bool {
            !isDirectMode
        }

        /// Builds the tools a host mounts on its session, in the order the
        /// model reads them.
        ///
        /// `searchTools` comes first, `runCode` second, `wait` last. A
        /// session's tool list is read as a whole before the model picks its
        /// opening move, so the list is itself the first statement of what a
        /// turn looks like here: discover what exists, execute against what
        /// came back, and block only when a result has not arrived yet.
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
        /// what this returns on a `RoutedSession`, and drives that session by
        /// draining `streamEvents(to:)` — nothing else. In particular it
        /// passes **no session instructions**: the mounted tool descriptions
        /// carry the entire behavioral contract — see ``description``.
        ///
        /// The session type is part of the contract, not a detail. A
        /// `RoutedSession` is what puts each tool through Router's own
        /// mounting path, where the background mount `MultiTool` declares for
        /// itself takes effect. So every `runCode` call goes to the background
        /// and answers with a pending envelope the model collects with `wait`.
        /// Mounted on a bare
        /// `FoundationModels.LanguageModelSession` the same tools cannot go to
        /// the background at all: the
        /// snippet simply blocks, no envelope is ever written, and `wait` has
        /// nothing to join. The integration suite drives exactly this contract —
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
        ///   - librarian: the model backing `searchTools`'s selection
        ///     tier, or `nil` to leave its searcher in cheap retrieval. Unused
        ///     in direct mode, which vends no `searchTools` to configure.
        ///   - sampleGenerator: the model `searchTools` writes its runnable
        ///     sample snippet on, or `nil` (the default) to leave sample
        ///     generation unconfigured, so `searchTools` answers with signatures
        ///     alone exactly as it always has. Pass the **main** generation
        ///     slot: the sample is code the model is told to run, so its
        ///     quality matters more than its cost. Unused in direct mode.
        /// - Returns: `searchTools`, `runCode`, `wait` — or `runCode` and
        ///   `wait` in direct mode, which takes discovery away but not
        ///   the background.
        /// - Throws: whatever
        ///   `SearchToolsTool.init(registry:librarian:limit:sampleGenerator:)`
        ///   throws.
        public func makeSessionTools(
            librarian: RoutedLLM?,
            sampleGenerator: RoutedLLM? = nil
        ) throws -> [any Tool] {
            try makeSessionToolsAndStaging(librarian: librarian, sampleGenerator: sampleGenerator).tools
        }

        /// Builds the tools a host mounts on its session, exactly as
        /// ``makeSessionTools(librarian:sampleGenerator:)`` does, and vends
        /// beside them the `RegistryStaging` a refresher stages a rebuilt
        /// registry on.
        ///
        /// The mounted `runCode` and `searchTools` share one `RegistryHolder`.
        /// A registry staged on the returned `staging` is applied when the
        /// session calls `runCode`'s `turnWillBegin()`, and from that tick
        /// both tools read the new surface: `tools.*`, `help()`, `docs()` and
        /// discovery swap together.
        ///
        /// A method of its own name, and not an overload: two overloads that
        /// differ in the return type alone make
        /// `let mounted = try registry.makeSessionTools(librarian: nil)`
        /// ambiguous, and every caller of the old method writes exactly that.
        ///
        /// - Parameters:
        ///   - librarian: see ``makeSessionTools(librarian:sampleGenerator:)``.
        ///   - sampleGenerator: see
        ///     ``makeSessionTools(librarian:sampleGenerator:)``.
        /// - Returns: the tools in mount order, and the staging half of the
        ///   holder they share.
        /// - Throws: what ``makeSessionTools(librarian:sampleGenerator:)``
        ///   throws.
        public func makeSessionToolsAndStaging(
            librarian: RoutedLLM?,
            sampleGenerator: RoutedLLM? = nil
        ) throws -> (tools: [any Tool], staging: any RegistryStaging) {
            // `wait` is mounted in both modes: a direct-mode surface declares
            // the background mount for `runCode` too, so every mounted call
            // goes to the background and a model still needs a way to say
            // "I cannot continue without that result" (task `h773bed`).
            guard supportsSearchTools else {
                let holder = RegistryHolder(
                    current: RegistryBundle(
                        registry: self,
                        shape: RegistryBundleShape(bindsSearchTools: false, discovery: .none)))
                return ([MultiTool(holder: holder), WaitTool()], holder)
            }
            let holder = RegistryHolder(
                current: RegistryBundle(
                    registry: self,
                    shape: RegistryBundleShape(
                        bindsSearchTools: true,
                        discovery: .configured(selection: SearchToolsTool.makeSelection(librarian: librarian)))))
            let searchTools = SearchToolsTool(
                holder: holder,
                sample: SearchToolsTool.makeSample(generator: sampleGenerator)
            )
            // The same instance both ways in: mounted for the model to call
            // directly, and bound as `tools.searchTools` for a snippet that
            // reaches for it mid-run. One instance means one librarian and one
            // sample generator, so the two doors cannot answer differently.
            let runCode = MultiTool(holder: holder, searchTools: searchTools)
            // Presented last, deliberately. A model reads "discover what
            // exists", then "execute code", and only then "block until
            // something finishes" — which is the rarest of the three and the
            // one it should reach for only when the other two have left it
            // waiting on a result.
            return ([searchTools, runCode, WaitTool()], holder)
        }
    }
}

/// The arguments `MultiTool`'s `runCode` call accepts: the JavaScript snippet
/// to run against `tools.*`, and nothing else.
///
/// **`runCode` always backgrounds.** It hands back a completion token every
/// time, so waiting is not one of its options — the concept is out of this
/// schema rather than set to zero. A model that needs the result calls `wait`;
/// a model that does not lets the snippet run (task `^cv98vff`).
///
/// A tool with two return shapes is unlearnable. Under "inline if it is fast,
/// a token if it is slow" the same call sometimes yields a value and sometimes
/// an envelope, decided by a race the model cannot observe, so it can never
/// form a stable habit. One shape, every time, is a correctness property
/// before it is a simplification — and it happens to be deterministic too: the
/// same call behaves identically on a fast machine and a loaded one.
///
/// This schema carries no clock, and must not grow one back. A `waitSeconds`
/// would bound a wait that no longer exists, and a `timeout` would let a model
/// bound work it no longer blocks on. The host's own
/// `MultiToolConfiguration.executionTimeLimit` is the ceiling, and
/// `MultiTool`'s `BackgroundTool` conformance answers it to the engine as the
/// work bound of every call (see `MultiTool+Background.swift`).
@Generable
public struct RunCodeArguments {
    /// The JavaScript snippet to run against `tools.*`.
    @Guide(
        description: "JavaScript snippet to run against the available tools, exposed as functions "
            + "under `tools.*`. Call the exact paths searchTools returned. Compose calls with normal "
            + "code — variables, loops, map/filter — and `return` the final value; only that value "
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
/// Mount through `Registry.makeSessionTools(librarian:sampleGenerator:)`
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
///    off the calling thread (see "Off-cooperative-thread dispatch"), with
///    `help()`/`docs()` and the six ambient globals — `status()`, `wait()`,
///    `cancel()`, `elicit()`, `notify()`, `progress()`, see
///    `MultiTool+SandboxGlobals.swift` — also installed;
/// 3. renders the result, or a thrown `InterpreterError`, through
///    `ResultRenderer`.
///
/// Each `tools.X(...)` call is an `AsyncHostFunction`, which the interpreter's
/// own promise pump installs as a JS function returning a `Promise` — see
/// `invokeAsync` for the full dispatch.
public struct MultiTool: Tool {
    /// This tool's `Tool`-protocol name, always `"runCode"`.
    public let name = "runCode"
    /// This tool's `Tool`-protocol description, presented to the model as
    /// usage instructions for `runCode`.
    ///
    /// Together with `SearchToolsTool.description` this carries the **whole**
    /// behavioral contract a session needs. Mounting the two tools is the
    /// entire integration: a `Tool` conformance's description goes into the
    /// prompt on every turn, but a session instruction is optional and a host
    /// can supply none. So nothing load-bearing can live outside these two
    /// strings. `searchTools` owns the discovery mandate; this side owns the
    /// snippet, the provenance rule, and the error-recovery contract.
    ///
    /// The provenance rule — answer only from what the snippet returns — is
    /// in this text because runs reported a booking as confirmed with nothing
    /// invoked.
    ///
    /// The ambient globals' *contract* is the one part deliberately not
    /// carried here. This text is read on every turn, alongside every tool
    /// schema, so everything in it competes with the discovery mandate for
    /// the model's attention — and the globals are the part a snippet needs
    /// only once it is already writing a snippet. So this names them, closes
    /// the global world around them, and points at `docs("globals")`, which
    /// hands back the contract on demand (see
    /// `MultiTool+SandboxGlobals.swift`, "MARK: - The docs() page").
    public let description = """
        runCode is an isolated JavaScript runtime that runs one snippet and returns what
        that snippet returns — use it for any computation (arithmetic, string work,
        dates, sorting, reshaping JSON) and for this session's functions, which it
        exposes under `tools.*`. The runtime is JavaScriptCore, core JavaScript only:
        `import` and `require` do not exist, there are no modules and no node, deno or
        bun APIs, and every function you can call is under `tools.*`. Write one snippet
        calling the exact `tools.*` paths searchTools returned, await every call, and
        `return` the final value; only that value comes back. Awaiting a call is the
        whole of how a snippet coordinates its work: do not wait() inside a snippet, and
        never time a call or poll for one. When runCode returns a pending envelope with a
        completionToken, call the wait tool with that completionToken to collect the
        result. Answer only from what the snippet returns: never
        state a fact about the user's data that did not come from a `tools.*` return
        value, and never claim success for a call the snippet did not actually return.
        When a snippet fails, fix it and call runCode again immediately. Ambient globals
        never appear in searchTools — run `docs("globals")` in a snippet to read them.
        """

    /// Where this tool logs its diagnostics — one `runCode` call's start and
    /// end, and each `tools.*` invocation's start, end and validation
    /// failure — and, at `.notice`, every imagined `tools.*` name a snippet
    /// reached for (see `logImaginedTool(_:)`).
    private static let logger = Logger(subsystem: "FoundationModelsMultitool", category: "MultiTool")

    /// Where this tool's call boundaries are recorded — see ``CallTrace``.
    ///
    /// Separate from ``logger`` above, and deliberately so: that one records
    /// what a run *decided* — which snippet ran, which `tools.*` name was
    /// imagined — on this package's diagnostic subsystem, and this one records
    /// only where control is, on its own. A hang is read by looking for an
    /// entry with no exit, and interleaving decisions into that stream is what
    /// makes the missing line hard to see.
    private static let trace = CallTrace(category: "MultiTool")

    /// What ``trace`` prints for a `runCode` call made outside any session.
    ///
    /// A `MultiTool` constructed and called directly has no ambient
    /// `ToolContext`, so it has no completion token to correlate against. That
    /// is a legitimate mode — every unit suite in this package runs in it —
    /// and it reads as an explicit absence rather than a blank.
    private static let noAmbientToken = CallTrace.absent

    /// The box that holds the catalog + live tool instances this `runCode`
    /// dispatches into, and everything precomputed from them, as one
    /// `RegistryBundle` — see `RegistryHolder`.
    ///
    /// A reference, shared by every copy of this struct and by the
    /// `searchTools` mounted beside it, so a swap at the turn boundary
    /// reaches all of them at one tick. Read one time at the top of
    /// `call(arguments:)`; the run keeps that bundle to its end. Internal,
    /// not `private`, because the turn-boundary extension applies the staged
    /// registry through it (see `MultiTool+TurnBoundary.swift`).
    let holder: RegistryHolder

    /// The M10 hardening knobs this tool enforces. Internal, not `private`,
    /// because the background extension reads the work clock's ceiling out of
    /// it (see `MultiTool+Background.swift`).
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

    /// Creates a `runCode` tool over `registry`, in a holder of its own.
    ///
    /// A tool made here swaps alone: `stage(_:)` and `turnWillBegin()` reach
    /// its holder, and no `searchTools` shares it. A host that mounts both
    /// uses `Registry.makeSessionToolsAndStaging(librarian:sampleGenerator:)`,
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
                    shape: RegistryBundleShape(bindsSearchTools: searchTools != nil, discovery: .none))),
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
    ///     live-context cap, the return and console caps — this tool
    ///     enforces. Defaults to `MultiToolConfiguration.default`. An
    ///     explicitly supplied `limits` wins over the value derived from it;
    ///     an explicitly supplied `interpreter` does NOT, and is still armed
    ///     with `configuration.executionTimeLimit` as below.
    ///   - interpreter: the sandbox to run every snippet in. Defaults to a
    ///     fresh `JSCInterpreter`. Whichever sandbox is used, it is armed
    ///     here with `configuration.executionTimeLimit` — the work clock's
    ///     ceiling, and the only clock the interpreter itself owns (see
    ///     `MultiToolConfiguration.executionTimeLimit`) — so an injected
    ///     interpreter runs under the configured ceiling rather than
    ///     whatever its own constructor received.
    ///   - limits: the size caps `ResultRenderer` enforces on this tool's
    ///     rendered output. Defaults to `configuration.resultLimits`.
    ///   - searchTools: the mounted discovery tool a snippet reaches as
    ///     `tools.searchTools`. Defaults to `nil`, which binds no such path —
    ///     `Registry.makeSessionTools(librarian:sampleGenerator:)` passes the
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
        self.liveContexts = LiveContextCounter()
        // One arming path for every sandbox this tool runs, injected or
        // built here: the configured ceiling always wins, so a caller who
        // passes a `JSCInterpreter()` never silently gets that interpreter's
        // own stock limit instead (see `Interpreter.withTimeLimit(_:)`).
        self.interpreter = (interpreter ?? JSCInterpreter()).withTimeLimit(configuration.executionTimeLimit)
        self.limits = limits ?? configuration.resultLimits
        self.searchTools = searchTools
        self.depth = depth
    }

    /// The mounted discovery tool a snippet reaches as `tools.searchTools`, or
    /// `nil` when this registry mounts none.
    ///
    /// The same instance the session mounts as its own tool, so a snippet and
    /// the model's direct call share one librarian and one sample generator.
    private let searchTools: (any Tool)?

    /// How many enclosing `tools.runCode` calls this run sits inside.
    ///
    /// `0` for a run the model started. Each nested call runs at one deeper,
    /// and ``maxRunCodeDepth`` is where nesting stops.
    private let depth: Int

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
    /// `InterpreterError` — a JS exception, a syntax error, or a watchdog
    /// timeout — is caught here and rendered as `ResultRenderer`'s
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
    /// A call that would push this tool past `configuration
    /// .liveContextLimit` never reaches the sandbox at all: it renders the
    /// same repairable error text instead, naming the cap and the three
    /// globals that collect a background run (see ``LiveContextCounter``).
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
        try await Self.trace.span(
            "MultiTool.call",
            detail: "depth=\(depth) completionToken=\(ToolContext.current?.completionToken ?? Self.noAmbientToken)"
        ) {
            try await runSnippet(arguments: arguments)
        }
    }

    /// Runs one `runCode` call, inside the span ``call(arguments:)`` opened.
    ///
    /// Split out so the span wraps the *whole* call, `liveContexts` claim
    /// included: a call refused at the cap, or one blocked before it ever
    /// reaches the sandbox, has to be as visible as one that reaches the
    /// interpreter.
    ///
    /// Returns and throws what ``call(arguments:)`` does.
    private func runSnippet(arguments: RunCodeArguments) async throws -> String {
        try Task.checkCancellation()
        guard liveContexts.claim(upTo: configuration.liveContextLimit) else {
            return ResultRenderer.render(Self.liveContextCapError(limit: configuration.liveContextLimit))
        }
        defer { liveContexts.release() }
        // Read one time, here, and kept to the end of this run: a registry
        // staged on the holder is applied at the next turn boundary, and
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
        let code = "\(bundle.preamble)\n\(arguments.code)"
        let outcome = await Self.runCapturingOutcome(
            code: code,
            installing: bundle.hostFunctions + Self.makeNoticeHostFunctions(outbox: notices),
            installingAsync: makeAsyncHostFunctions(
                over: bundle, binding: binding, recordingInto: ledger, noting: lostRuns)
                + Self.makeBackgroundRunHostFunctions(binding: binding),
            using: interpreter
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
            return ResultRenderer.render(
                interpreterError,
                hint: resolution?.text,
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

    // MARK: - Off-cooperative-thread dispatch

    /// Runs one snippet and captures its outcome instead of throwing it, so
    /// `call(arguments:)` can flush the invocation's notice chain on both the
    /// success and the failure path before deciding what to hand back.
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
    /// thread, by dispatching internally onto the run's own dedicated worker
    /// queue with `DispatchQueue.sync`. But calling that *synchronously* from
    /// here would still tie up whichever cooperative-pool thread is running
    /// this `async` `call(arguments:)` for the run's entire duration.
    /// Wrapping it in `withCheckedThrowingContinuation` and dispatching onto
    /// a plain, elastic GCD global queue instead means this `async` function
    /// *suspends* — freeing its cooperative-pool thread for other work —
    /// rather than *blocks* while the snippet runs. It is the second,
    /// independent half of the same "never block the caller" principle
    /// `JSCInterpreter` established for the interpreter's own worker thread,
    /// applied here to the tool-call boundary above it.
    ///
    /// It also threads this `async` context's own `Task` cancellation into
    /// the interpreter's `isCancelled` hook, so cancelling the `Task` running
    /// `call(arguments:)` reaches all the way into the running snippet rather
    /// than only being observed after it finishes.
    ///
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
    /// out of `run` itself so that function's cancellation-handler and
    /// continuation nesting does not also have to carry the dispatch-queue
    /// and do-catch levels below it.
    ///
    /// `cancelledBox` is polled as `interpreter.run`'s `isCancelled` hook,
    /// and `run(code:installing:installingAsync:using:)`'s `onCancel` is what
    /// flips it to `true`.
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
    /// one that promised it (see ``ToolReturnLedger``), and so `lostRuns`
    /// sees the `LostRunError` it threw, which is what lets `call(arguments:)`
    /// throw it once the snippet has finished (see ``LostRunRecord``). The
    /// wrap is applied to the whole list at once rather than at each
    /// construction site, so no binding added later can be left out of either
    /// record by omission.
    ///
    /// Each live tool's binding carries that tool's own `journalOp`, so a verb
    /// registered under a noun journals the `"verb noun"` pair. `searchTools`
    /// and the nested `runCode` are session-level operations that no noun was
    /// registered under, so each keeps the engine's own default of stamping
    /// `op` with the tool's name.
    ///
    /// - Parameter bundle: the bundle this run read at its start, whose
    ///   `liveTools` the bindings dispatch into.
    /// - Returns: one `AsyncHostFunction` per live tool, in `liveTools`'
    ///   order.
    private func makeAsyncHostFunctions(
        over bundle: RegistryBundle,
        binding: RunBinding?, recordingInto ledger: ToolReturnLedger, noting lostRuns: LostRunRecord
    ) -> [AsyncHostFunction] {
        var functions = bundle.liveTools.map { liveTool in
            AsyncHostFunction(name: liveTool.hostFunctionName) { arguments in
                try await Self.invokeAsync(
                    tool: liveTool.tool,
                    arguments: arguments,
                    binding: binding,
                    journalOp: liveTool.journalOp
                )
            }
        }
        if let searchTools {
            functions.append(
                AsyncHostFunction(name: Self.searchToolsHostName) { arguments in
                    try await Self.invokeAsync(
                        tool: searchTools,
                        arguments: Self.widenedToObject(arguments, field: Self.searchToolsTaskField),
                        binding: binding
                    )
                }
            )
        }
        functions.append(makeNestedRunCodeHostFunction(over: bundle))
        return functions.map { Self.recording($0, into: ledger, noting: lostRuns) }
    }

    /// Wraps one `tools.*` binding so this run's ledger sees the value it
    /// handed back, and this run's record sees the `LostRunError` it threw.
    /// The wrapper keeps the same name.
    private static func recording(
        _ function: AsyncHostFunction, into ledger: ToolReturnLedger, noting lostRuns: LostRunRecord
    ) -> AsyncHostFunction {
        AsyncHostFunction(name: function.name) { arguments in
            try await lostRuns.noting {
                try await ledger.recording { try await function.call(arguments) }
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
    /// surface as the snippet that started it: a swap at the turn boundary
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
        journalOp: String? = nil
    ) async throws -> InterpreterValue {
        let start = ContinuousClock.now
        logger.debug("tools.\(tool.name, privacy: .public) invocation started.")
        do {
            let value = try await performInvocation(
                tool: tool, arguments: arguments, binding: binding, journalOp: journalOp)
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
    /// **Why this is logged at all.** An imagined name is free evidence about
    /// the catalog: it is the model saying what it thought the tool should be
    /// called. Accumulated across real sessions, those guesses rank the
    /// synonyms a host's naming, or an alias table, should cover. Nothing
    /// else on this route records them — the hint is rendered into the
    /// model's error text and discarded.
    ///
    /// **Why `.notice`.** The corpus has to survive an ordinary host run to
    /// be worth mining. `.debug` is disabled by default and never reaches the
    /// store at all. `.info` reaches the in-memory buffer, but is not
    /// persisted to disk unless the subsystem's info level is turned on, so
    /// it survives a live `log stream` and not a later `log show`. `.notice`
    /// is the lowest level that persists by default. Nor `.warning`/`.error`:
    /// the lines at those levels in this file report a failure a host should
    /// act on, and an imagined name is not one.
    ///
    /// **Why `.public`.** Every field is model- or catalog-authored and
    /// carries no user data: `imaginedPath` is a name the model made up,
    /// `suggestedPaths` are the host's own tool names, and the tier is one of
    /// three fixed words. Nothing derived from a snippet's arguments, a
    /// tool's output, or the user's prompt is in the line, and none can be
    /// added: `UnknownToolHint.Resolution.logMessage` composes the message
    /// from exactly those three fields.
    private static func logImaginedTool(_ resolution: UnknownToolHint.Resolution) {
        logger.notice("\(resolution.logMessage, privacy: .public)")
    }

    /// Logs one `tools.*` invocation's failure, distinguishing a pre-call
    /// **validation failure** — `ToolInvokerError`/`ArgumentMarshalerError`,
    /// logged at `.warning`, because the snippet's call was malformed and not
    /// the tool itself — from any other failure, which is the tool's own
    /// thrown error and is logged at `.error`.
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
