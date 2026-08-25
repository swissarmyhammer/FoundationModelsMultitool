import Foundation
import FoundationModels
import FoundationModelsRouter
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
/// every event it forwards. So `"execute shell"` surfaces on `ParkedRun.op` —
/// which `SessionMailbox.park(tool:op:)` fills from `ToolContext.op` — and on
/// the `ToolInvocationRecord` built from that same field, and nowhere in the
/// snippet's own journal.
///
/// `ToolInvocationRecord` is not readable from this package: `RunBinding` hands
/// the engine an `AmbientUpstreamSink`, which implements `post(event:)` alone,
/// so an inner run's record takes `OperationEventSink`'s no-op default. The two
/// readings below are therefore `ParkedRun.op` and the `op` a called verb reads
/// out of its own `ToolContext.current` — the one stamp both records are made
/// from.
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
    private static let detachedRunSleepSeconds = 30

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

    @Test("a detached tools.shell.execute run stands on the run plane under the op \"execute shell\"")
    func aDetachedShellRunStandsOnTheRunPlaneUnderThePair() async throws {
        let registry = try Self.makeShellRegistry(in: scratch)
        let context = makeOuterRunContext(mailbox: SessionMailbox(), sink: RecordingEventSink())

        try await Self.run(
            """
            return await tools.\(Self.shellNoun).\(Self.executeVerb)({ \
            command: "sleep \(Self.detachedRunSleepSeconds)", wait: false });
            """,
            over: registry,
            under: context)

        // `DetachingTool.detach` awaits `SessionMailbox.park` before it hands
        // the pending envelope back, so the run stands on the plane by the time
        // the snippet that called it has settled. No poll is needed.
        let going = try #require(await context.parkedRuns().first)
        #expect(going.op == "\(Self.executeVerb) \(Self.shellNoun)")
        #expect(going.tool == Self.executeVerb)

        // Awaited rather than deferred into a task of its own: an unstructured
        // task started at the end of a test need never run, and the command this
        // one stops sleeps far longer than the whole suite.
        _ = await context.cancel(completionToken: going.completionToken)
    }

    // MARK: - The ground of one test

    /// Builds a registry holding the whole shell capability over a store in a
    /// temporary directory the caller owns.
    ///
    /// - Parameter scratch: The owner of the temporary directory the store
    ///   prepares in.
    /// - Returns: The rendered catalog paired with the live verbs of the shell.
    /// - Throws: What `makeDirectory(prefix:)`, `withShell(storeDirectory:)` or
    ///   `buildRegistry()` throws.
    private static func makeShellRegistry(in scratch: TestScratch) throws -> MultiTool.Registry {
        let directory = try scratch.makeDirectory(prefix: testDirectoryNamePrefix)
        return try MultiTool.Builder()
            .withShell(storeDirectory: directory.appendingPathComponent(shellStoreDirectoryName))
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
