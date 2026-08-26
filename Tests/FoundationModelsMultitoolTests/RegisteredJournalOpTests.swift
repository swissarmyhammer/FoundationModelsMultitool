import Foundation
import FoundationModels
import FoundationModelsRouter
import Synchronization
import Testing

@testable import FoundationModelsMultitool

/// Phase-2 coverage for the `"verb noun"` journal op — eventplan.md §
/// "Registration of capabilities: noun/verb": "`OperationEvent.op` stays the
/// canonical `"verb noun"` string. Registration derives it as
/// `"\(verb) \(noun)"`."
///
/// A verb cannot derive that string for itself, because it does not know its own
/// noun: `register(noun:tool:)` holds the noun and `Tool.name` holds the verb.
/// So the derivation stands at the registration site, and these tests read it
/// back at the two places a registered run makes it observable.
///
/// ## The plane the pair appears on
///
/// The run plane, and not the event journal of the enclosing snippet. An inner
/// `tools.*` call inside a `runCode` snippet reaches the session's outbox
/// re-stamped with the OUTER run's op, because `ToolContext.post(_:)` re-stamps
/// every event it forwards. So `"execute shell"` surfaces on `BackgroundRun.op`
/// — which `SessionMailbox.track(tool:op:)` fills from `ToolContext.op` — and
/// on the `ToolInvocationRecord` built from that same field, and nowhere in the
/// snippet's own journal.
///
/// `ToolInvocationRecord` is not readable from this package: `RunBinding` hands
/// the engine an `AmbientUpstreamSink`, which implements `post(event:)` alone,
/// so an inner run's record takes `OperationEventSink`'s no-op default. The two
/// readings below are therefore `BackgroundRun.op` and the `op` a called verb
/// reads out of its own `ToolContext.current` — the one stamp both records are
/// made from.
@Suite("RegisteredJournalOp")
struct RegisteredJournalOpTests {

    /// Owns the temporary directories this test makes, so they go away when the
    /// test ends rather than collecting in `$TMPDIR`.
    private let scratch = TestScratch()

    /// The name prefix of the temporary directory of one test, so a leaked
    /// directory is traceable to this suite.
    private static let testDirectoryNamePrefix = "registered-journal-op-tests"

    /// The name of the store folder inside the directory of one test.
    private static let shellStoreDirectoryName = ".shell"

    /// The noun the fixture verb registers under.
    private static let demoNoun = "demo"

    /// The `Tool.name` of the fixture verb, which is the verb half of the pair.
    private static let demoVerb = "probe"

    /// The noun the shell capability owns.
    private static let shellNoun = "shell"

    /// The `Tool.name` of the run-plane verb of the shell capability.
    private static let executeVerb = "execute"

    /// How long the command of the run-plane test sleeps. Long enough that it
    /// certainly still stands on the run plane while the test reads it, and the
    /// test ends it before it returns.
    private static let backgroundRunSleepSeconds = 30

    /// The command of the short run. A shell builtin that ends at once, thus
    /// that run settles as soon as the test waits for it.
    ///
    /// It reaches no system outside the shell the capability spawns itself,
    /// exactly as the `sleep` of the run-plane test above does, thus this stays
    /// a unit test of the wiring rather than an integration test of a service.
    private static let shortCommand = "true"

    // MARK: - The one pair, read off the rendered surface

    @Test("the snippet path and the journal op are derived from the one noun/verb pair")
    func theSnippetPathAndTheJournalOpComeFromOnePair() throws {
        let surface = try MultiTool.Builder()
            .register(noun: Self.demoNoun, tool: AmbientRecordingTool(name: Self.demoVerb))
            .build()

        let entry = try #require(surface.entries.first)
        #expect(entry.path == "\(Self.demoNoun).\(Self.demoVerb)")
        #expect(entry.journalOp == "\(Self.demoVerb) \(Self.demoNoun)")
    }

    @Test("the shell capability renders tools.shell.execute and the journal op \"execute shell\"")
    func theShellCapabilityRendersBothHalvesOfItsPair() throws {
        let registry = try Self.makeShellRegistry(in: scratch)

        let entry = try #require(
            registry.surface.entries.first { $0.path == "\(Self.shellNoun).\(Self.executeVerb)" })
        #expect(entry.journalOp == "\(Self.executeVerb) \(Self.shellNoun)")
    }

    @Test("a standalone tool has no noun, so it declares no journal op of its own")
    func aStandaloneEntryDeclaresNoJournalOp() throws {
        let surface = try MultiTool.Builder()
            .addTool(AmbientRecordingTool(name: Self.demoVerb))
            .build()

        let entry = try #require(surface.entries.first)
        #expect(entry.path == Self.demoVerb)
        #expect(entry.journalOp == nil)
    }

    // MARK: - The stamp a registered run actually carries

    @Test("a verb registered under a noun runs stamped with the pair, and its tool stays the verb")
    func aVerbRegisteredUnderANounRunsStampedWithThePair() async throws {
        let probe = AmbientRecordingTool(name: Self.demoVerb)
        let registry = try MultiTool.Builder()
            .register(noun: Self.demoNoun, tool: probe)
            .buildRegistry()
        let context = makeOuterRunContext(mailbox: SessionMailbox(), sink: RecordingEventSink())

        try await Self.run(
            "return await tools.\(Self.demoNoun).\(Self.demoVerb)();",
            over: registry,
            under: context)

        let observation = try #require(probe.observations.first)
        #expect(observation.stampedOp == "\(Self.demoVerb) \(Self.demoNoun)")
        #expect(observation.stampedTool == Self.demoVerb)
    }

    @Test("a tool registered with no noun keeps its own name as its op, so nothing that renders today changes")
    func aToolRegisteredWithNoNounKeepsItsOwnNameAsItsOp() async throws {
        let probe = AmbientRecordingTool(name: Self.demoVerb)
        let registry = try MultiTool.Builder()
            .addTool(probe)
            .buildRegistry()
        let context = makeOuterRunContext(mailbox: SessionMailbox(), sink: RecordingEventSink())

        try await Self.run("return await tools.\(Self.demoVerb)();", over: registry, under: context)

        let observation = try #require(probe.observations.first)
        #expect(observation.stampedOp == Self.demoVerb)
        #expect(observation.stampedTool == Self.demoVerb)
    }

    // MARK: - The run plane

    @Test("a background tools.shell.execute run stands on the run plane under the op \"execute shell\"")
    func aBackgroundShellRunStandsOnTheRunPlaneUnderThePair() async throws {
        let registry = try Self.makeShellRegistry(in: scratch)
        let context = makeOuterRunContext(mailbox: SessionMailbox(), sink: RecordingEventSink())

        try await Self.run(
            """
            return await tools.\(Self.shellNoun).\(Self.executeVerb)({ \
            command: "sleep \(Self.backgroundRunSleepSeconds)" });
            """,
            over: registry,
            under: context)

        // `BackgroundToolRunner.call` awaits `SessionMailbox.track` before it hands
        // the pending envelope back, so the run stands on the plane by the time
        // the snippet that called it has settled. No poll is needed.
        let going = try #require(await context.backgroundRuns().first)
        #expect(going.op == "\(Self.executeVerb) \(Self.shellNoun)")
        #expect(going.tool == Self.executeVerb)

        // Awaited rather than deferred into a task of its own: an unstructured
        // task started at the end of a test need never run, and the command this
        // one stops sleeps far longer than the whole suite.
        _ = await context.cancel(completionToken: going.completionToken)
    }

    // MARK: - The stamp the shell verb itself reads

    /// The second reading of the pair, made from INSIDE the run: `Execute`
    /// reads its own `ToolContext` and asks its sandbox to preflight from
    /// inside that call — so a probe sandbox reports the stamp the
    /// registration site put on the run, which is the one field
    /// `BackgroundRun.op` and `ToolInvocationRecord.op` are both built from.
    ///
    /// The verb declares the background mount, so the snippet settles with the
    /// pending envelope while the command still spawns. A short command can
    /// be off the plane again before the snippet returns, so the test polls
    /// the sandbox itself for the stamp instead of reading the plane.
    @Test("a tools.shell.execute run carries the journal op \"execute shell\" into its own call")
    func aShellRunCarriesThePairIntoItsOwnCall() async throws {
        let sandbox = JournalOpProbeSandbox()
        let registry = try Self.makeShellRegistry(in: scratch, sandbox: sandbox)
        let context = makeOuterRunContext(mailbox: SessionMailbox(), sink: RecordingEventSink())

        try await Self.run(
            """
            return await tools.\(Self.shellNoun).\(Self.executeVerb)({ \
            command: "\(Self.shortCommand)" });
            """,
            over: registry,
            under: context)

        try await TestPoll.waitUntil("the run consulted its sandbox") {
            !sandbox.observedOps.isEmpty
        }

        let stampedOp = try #require(
            sandbox.observedOps.first, "the run never consulted its sandbox")
        #expect(stampedOp == "\(Self.executeVerb) \(Self.shellNoun)")
    }

    // MARK: - The ground of one test

    /// Builds a registry holding the whole shell capability over a store in a
    /// temporary directory the caller owns.
    ///
    /// - Parameters:
    ///   - scratch: The owner of the temporary directory the store prepares in.
    ///   - sandbox: The confinement each command of the capability spawns
    ///     under. The default, `nil`, confines nothing.
    /// - Returns: The rendered catalog paired with the live verbs of the shell.
    /// - Throws: What `makeDirectory(prefix:)`,
    ///   `withShell(storeDirectory:sandbox:)` or `buildRegistry()` throws.
    private static func makeShellRegistry(
        in scratch: TestScratch, sandbox: (any CommandSandbox)? = nil
    ) throws -> MultiTool.Registry {
        let directory = try scratch.makeDirectory(prefix: testDirectoryNamePrefix)
        return try MultiTool.Builder()
            .withShell(
                storeDirectory: directory.appendingPathComponent(shellStoreDirectoryName),
                sandbox: sandbox)
            .buildRegistry()
    }

    /// Runs one `runCode` snippet over `registry`, under the ambient context a
    /// Router session binds around the outer run.
    ///
    /// - Parameters:
    ///   - code: The snippet to run.
    ///   - registry: The catalog the snippet's `tools.*` calls dispatch into.
    ///   - context: The outer run's ambient context.
    /// - Throws: What `MultiTool.call(arguments:)` throws.
    private static func run(
        _ code: String, over registry: MultiTool.Registry, under context: ToolContext
    ) async throws {
        let multiTool = MultiTool(registry: registry)
        _ = try await ToolContext.$current.withValue(context) {
            try await multiTool.call(arguments: RunCodeArguments(code: code))
        }
    }
}

/// A `CommandSandbox` that records the journal `op` of each run that consults
/// it, and that confines nothing.
///
/// The seam is the one place inside a real `execute` run that a test can stand:
/// `Execute` asks its sandbox to `preflight` before it spawns, from inside its
/// own call, thus `ToolContext.current` there is the context the registration
/// site stamped for THAT run. No other probe is needed, and the verb keeps its
/// production shape.
///
/// `wrap` gives the shell invocation back exactly as it came in, thus the
/// command of the run starts as it starts with no sandbox at all and the probe
/// changes only what is observed.
///
/// A reference type, thus the test reads what the copy of the runner the verb
/// holds observed. A runner is a value, and it is copied. It is a locked class
/// rather than an actor because `wrap` is a SYNCHRONOUS requirement of
/// `CommandSandbox`, which an actor answers only from outside its own
/// isolation — the same shape `RecordingSandbox` takes, for the same reason.
private final class JournalOpProbeSandbox: CommandSandbox {

    /// The stamp of each run that consulted this sandbox, in call order — `nil`
    /// for a call that ran under no ambient context at all.
    private let observed = Mutex<[String?]>([])

    /// The stamp of each run that consulted this sandbox, in call order.
    var observedOps: [String?] {
        observed.withLock { $0 }
    }

    /// Records the journal op of the run, and proves nothing about the
    /// confinement.
    ///
    /// - Parameters:
    ///   - workingDirectory: Not read — nothing is proved.
    ///   - temporaryDirectory: Not read — nothing is proved.
    func preflight(workingDirectory: String, temporaryDirectory: String) async {
        let stampedOp = ToolContext.current?.op
        observed.withLock { $0.append(stampedOp) }
    }

    /// Gives back `shellPath` and `shellArguments` unchanged.
    ///
    /// - Parameters:
    ///   - shellPath: The absolute path of the shell to run.
    ///   - shellArguments: The arguments of that shell.
    ///   - workingDirectory: Not read — no confinement is applied.
    ///   - temporaryDirectory: Not read — no confinement is applied.
    /// - Returns: The shell invocation as it came in.
    func wrap(
        shellPath: String,
        shellArguments: [String],
        workingDirectory: String,
        temporaryDirectory: String
    ) -> SandboxedInvocation {
        SandboxedInvocation(executable: shellPath, arguments: shellArguments)
    }
}
