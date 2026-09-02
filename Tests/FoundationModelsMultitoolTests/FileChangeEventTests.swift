// `FileChangeEventTests` — the mutating file verbs deliver their change set
// to the session as a `.progress` `OperationEvent`.
//
// UPSTREAM_ASKS.md, ask 4, part 2: a host reads what a verb changed off an
// `OperationEvent.detail` that carries the `fileChanges` envelope, and it
// reads that envelope back with `FileChangeSet.init(operationEventDetail:)`.
// Each verb posts through the ambient `ToolContext` the engine bound around
// its call, and `ToolContext.post(_:)` re-stamps the event with the OUTER
// run's correlation, thus the host puts the change set on the tool call the
// session issued. A verb called with no ambient context keeps its changes in
// the journal for `drain()`, as `FileChangeSetTests` reads them.
//
// The ground of each test is the one `FilesCapabilityTests` mounts a verb on:
// a stub run from `makeStubRun()`, and `context.mount(verb, as: .synchronous)`.

import Foundation
import FoundationModels
import FoundationModelsRouter
import Testing

@testable import FoundationModelsMultitool

/// Behavioral tests for the delivery of a change set through the session.
///
/// One test for each acceptance criterion of the card: the write verb, the
/// patch verb, the edit verb, the emptied journal, and the bare-session path.
@Suite("FileChangeEventTests")
struct FileChangeEventTests {

    /// The name of the temporary directory of one test. Thus a leaked
    /// directory is traceable to this suite.
    private static let testDirectoryName = "FileChangeEventTests"

    /// The number of files the multi-file envelope touches: one add, one
    /// update, one delete, and one move.
    private static let touchedFileCount = 4

    /// How many `fileChanges` events one mutating verb call delivers.
    private static let eventsPerCall = 1

    /// The content the write test writes.
    private static let writtenContent = "hello\n"

    /// The content the edit test seeds and rewrites.
    private static let editedBefore = "one\ntwo\n"

    /// The content the edit test expects after the rewrite.
    private static let editedAfter = "one\nTWO\n"

    // MARK: - The ground of one test

    /// A stub run beside a recording files capability rooted in a directory
    /// this test owns.
    private struct Ground {
        /// The stub session and its context.
        let run: StubRun

        /// The recording capability the verbs come from.
        let capability: FilesCapability

        /// The canonical session root.
        let root: URL
    }

    /// Builds the ground: a canonical root seeded with files, a recording
    /// capability over it, and a stub run.
    ///
    /// - Parameter files: the file names and UTF-8 contents to seed under the
    ///   root.
    /// - Returns: the ground.
    /// - Throws: rethrows a seed-write failure, or whatever standing up the
    ///   stub run throws.
    private static func makeGround(
        seeding files: [(name: String, contents: String)] = []
    ) async throws -> Ground {
        let root = TestSupport.canonicalDirectory(
            TestSupport.makeTemporaryDirectory(named: testDirectoryName))
        for file in files {
            try Data(file.contents.utf8).write(
                to: root.appendingPathComponent(file.name, isDirectory: false))
        }
        let capability = FilesCapability(root: root, recordsChanges: true)
        let run = try await makeStubRun()
        return Ground(run: run, capability: capability, root: root)
    }

    /// The one verb of the capability that is a `Verb`, mounted on the stub
    /// session context as a synchronous tool.
    ///
    /// - Parameters:
    ///   - kind: the verb type to mount.
    ///   - ground: the ground whose capability and context to use.
    /// - Returns: the mounted verb, typed as the verb's own arguments and output.
    /// - Throws: when the capability holds no such verb, or the mount changes
    ///   the output type.
    private static func mounted<Verb: Tool>(
        _ kind: Verb.Type, in ground: Ground
    ) throws -> any Tool<Verb.Arguments, Verb.Output> {
        let verb = try #require(ground.capability.tools.compactMap { $0 as? Verb }.first)
        return try #require(
            ground.run.context.mount(verb, as: .synchronous)
                as? any Tool<Verb.Arguments, Verb.Output>)
    }

    /// The change journal the capability's verbs share.
    ///
    /// - Parameter ground: the ground whose capability to read.
    /// - Returns: the journal.
    /// - Throws: when the capability holds no write verb.
    private static func journal(of ground: Ground) throws -> FileChangeJournal {
        try #require(ground.capability.tools.compactMap { $0 as? Write }.first).context.changes
    }

    /// The one `fileChanges` event the run delivered, and the change set it carries.
    ///
    /// Waits for the event to be journaled, then asserts the run delivered
    /// exactly one, and that it decodes.
    ///
    /// - Parameter ground: the ground whose run to read.
    /// - Returns: the event and its decoded change set.
    /// - Throws: when no event arrived, or its detail is not the envelope.
    private static func deliveredChangeSet(
        in ground: Ground
    ) async throws -> (event: OperationEvent, set: FileChangeSet) {
        let events = await recordedOperationEvents(
            of: ground.run,
            ofKind: .progress,
            correlatedTo: [ground.run.context.completionToken],
            awaiting: eventsPerCall
        )
        #expect(events.count == eventsPerCall, "events were: \(events)")
        let event = try #require(events.first)
        let set = try #require(FileChangeSet(operationEventDetail: event.detail))
        return (event, set)
    }

    // MARK: - The write verb

    @Test("a mounted write delivers one add change through the session")
    func aMountedWriteDeliversOneAddChange() async throws {
        let ground = try await Self.makeGround()
        let write = try Self.mounted(Write.self, in: ground)
        let path = TestSupport.path("new.txt", in: ground.root)

        let result = try await write.call(
            arguments: WriteArguments(path: path, content: Self.writtenContent))
        let (event, set) = try await Self.deliveredChangeSet(in: ground)

        #expect(result.correction == nil)
        #expect(event.correlationID == ground.run.context.completionToken)
        #expect(set.root == (try Self.journal(of: ground)).root)
        #expect(set.changes == [FileChange(kind: .add, path: path, newContent: Self.writtenContent)])
    }

    // MARK: - The patch verb

    @Test("a mounted patch of four files delivers one event with four changes")
    func aMountedPatchDeliversOneEventWithFourChanges() async throws {
        let ground = try await Self.makeGround(seeding: [
            ("update.txt", "one\ntwo\nthree\n"),
            ("delete.txt", "obsolete\n"),
            ("source.txt", "keep me\n"),
        ])
        let patch = try Self.mounted(Patch.self, in: ground)
        let envelope = """
            *** Begin Patch
            *** Add File: \(TestSupport.path("added.txt", in: ground.root))
            +added
            *** Update File: \(TestSupport.path("update.txt", in: ground.root))
            *** Find:
            two
            *** Replace:
            TWO
            *** Delete File: \(TestSupport.path("delete.txt", in: ground.root))
            *** Update File: \(TestSupport.path("source.txt", in: ground.root))
            *** Move to: \(TestSupport.path("dest.txt", in: ground.root))
            *** End Patch

            """

        let result = try await patch.call(arguments: PatchArguments(patch: envelope))
        let (event, set) = try await Self.deliveredChangeSet(in: ground)

        #expect(result.correction == nil)
        #expect(event.correlationID == ground.run.context.completionToken)
        #expect(set.changes.count == Self.touchedFileCount)
        #expect(Set(set.changes.map(\.kind)) == [.add, .modify, .delete, .move])
    }

    // MARK: - The edit verb

    @Test("a mounted edit delivers one modify change with both sides")
    func aMountedEditDeliversOneModifyWithBothSides() async throws {
        let ground = try await Self.makeGround(seeding: [("code.txt", Self.editedBefore)])
        let edit = try Self.mounted(Edit.self, in: ground)
        let path = TestSupport.path("code.txt", in: ground.root)

        let result = try await edit.call(
            arguments: EditArguments(
                path: path, find: ["two"], replace: ["TWO"], replacesAll: nil, occurrence: nil))
        let (event, set) = try await Self.deliveredChangeSet(in: ground)

        #expect(result.correction == nil)
        #expect(event.correlationID == ground.run.context.completionToken)
        #expect(
            set.changes == [
                FileChange(
                    kind: .modify, path: path, oldContent: Self.editedBefore,
                    newContent: Self.editedAfter)
            ])
    }

    // MARK: - The journal after a delivery

    @Test("a delivered change is not kept in the journal")
    func aDeliveredChangeIsNotKeptInTheJournal() async throws {
        let ground = try await Self.makeGround()
        let write = try Self.mounted(Write.self, in: ground)

        _ = try await write.call(
            arguments: WriteArguments(
                path: TestSupport.path("new.txt", in: ground.root), content: Self.writtenContent))
        _ = try await Self.deliveredChangeSet(in: ground)
        let drained = await (try Self.journal(of: ground)).drain()

        #expect(drained.changes.isEmpty)
    }

    // MARK: - A verb with no ambient context

    @Test("a verb called with no ambient context keeps its change for drain")
    func aVerbCalledWithNoAmbientContextKeepsItsChangeForDrain() async throws {
        let ground = try await Self.makeGround()
        let write = try #require(ground.capability.tools.compactMap { $0 as? Write }.first)
        let path = TestSupport.path("new.txt", in: ground.root)

        _ = try await write.call(arguments: WriteArguments(path: path, content: Self.writtenContent))
        let drained = await write.context.changes.drain()
        let events = await recordedOperationEvents(of: ground.run, ofKind: .progress)

        #expect(drained.changes == [FileChange(kind: .add, path: path, newContent: Self.writtenContent)])
        #expect(events.isEmpty)
    }
}
