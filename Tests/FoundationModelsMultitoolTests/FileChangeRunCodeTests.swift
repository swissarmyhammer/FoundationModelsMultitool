// `FileChangeRunCodeTests` — the `fileChanges` event, end to end through
// `runCode`.
//
// UPSTREAM_ASKS.md, ask 4, part 3. `FileChangeEventTests` proves that a
// mutating verb mounted directly on a session context delivers its change
// set as ONE `.progress` event. This suite proves the same delivery through
// the whole `runCode` route: a snippet calls `tools.files.write`, the inner
// call travels `RunBinding.invoke` and the engine mount, and the event lands
// on the OUTER run's correlation, in the recorder, before
// `MultiTool.call(arguments:)` returns. Two calls that run at the same time
// over one `MultiTool` keep their events apart, and the model reads the same
// text whether the capability records or not.
//
// Each test runs a JavaScript snippet through a `MultiTool` over the files
// registry of a `FilesRun` (see `Fixtures/FilesRunFixtures.swift`), and it
// reads the delivered events off the stub run's transcript with
// `recordedOperationEvents(of:ofKind:correlatedTo:)`.

import Foundation
import FoundationModels
import FoundationModelsRouter
import Testing

@testable import FoundationModelsMultitool

/// Behavioral tests for the delivery of a change set through `runCode`.
///
/// One test for each acceptance criterion of the card: the write, the read
/// with no wait, the three-file patch, the two concurrent calls, and the
/// rendered text a recording and a non-recording capability answer.
@Suite("FileChangeRunCodeTests")
struct FileChangeRunCodeTests {

    // MARK: - The names and contents of the fixture files

    /// The name of the temporary directory of one test. Thus a leaked
    /// directory is traceable to this suite.
    private static let testDirectoryName = "FileChangeRunCodeTests"

    /// The file the write tests write.
    private static let writtenFileName = "new.txt"

    /// The content the write tests write.
    private static let writtenContent = "hello\n"

    /// The file the patch adds.
    private static let addedFileName = "added.txt"

    /// The one line the patch puts in ``addedFileName``.
    private static let addedLine = "added"

    /// The file the patch updates.
    private static let updatedFileName = "update.txt"

    /// The content of ``updatedFileName`` before the patch.
    private static let updatedBefore = "one\ntwo\n"

    /// The line the patch finds in ``updatedFileName``.
    private static let patchFindText = "two"

    /// The line the patch puts in its place.
    private static let patchReplaceText = "TWO"

    /// The file the patch deletes.
    private static let deletedFileName = "delete.txt"

    /// The content of ``deletedFileName`` before the patch.
    private static let deletedContent = "obsolete\n"

    /// How many files the patch envelope touches: one add, one update, and
    /// one delete.
    private static let patchedFileCount = 3

    /// The file the first of the two concurrent snippets writes.
    private static let firstFileName = "first.txt"

    /// The file the second of the two concurrent snippets writes.
    private static let secondFileName = "second.txt"

    /// How many snippets meet at the rendezvous.
    private static let concurrentSnippetCount = 2

    /// How many `fileChanges` events one mutating verb call delivers.
    private static let eventsPerCall = 1

    // MARK: - The ground of one test

    /// The rendered output of a write of ``writtenContent``: the JSON text
    /// of its byte count.
    private static var writtenByteCountText: String {
        String(writtenContent.utf8.count)
    }

    /// The snippet that writes ``writtenFileName`` and answers the byte count.
    private static var writeSnippet: String {
        writeVerbSnippet(writing: writtenFileName, content: writtenContent)
    }

    /// The `.progress` events of `run` on its own outer correlation, read one
    /// time with no wait.
    ///
    /// - Parameter run: the stub run whose transcript to read.
    /// - Returns: the events, in transcript order.
    private static func outerProgressEvents(of run: StubRun) async -> [OperationEvent] {
        await recordedOperationEvents(
            of: run, ofKind: .progress, correlatedTo: [run.context.completionToken])
    }

    /// The change set one delivered event carries.
    ///
    /// - Parameter event: the delivered event.
    /// - Returns: the decoded change set.
    /// - Throws: when the detail of `event` is not the `fileChanges` envelope.
    private static func changeSet(of event: OperationEvent) throws -> FileChangeSet {
        try #require(FileChangeSet(operationEventDetail: event.detail))
    }

    /// The one `fileChanges` event `run` delivered on its outer correlation,
    /// read with no wait, and the change set it carries.
    ///
    /// `SessionOutbox.post(event:)` awaits the journal write, thus the event
    /// is in the recorder when the `runCode` call that caused it returns. A
    /// read that comes back with no event is a fault in the route, and no
    /// race.
    ///
    /// - Parameter run: the stub run whose transcript to read.
    /// - Returns: the event and its decoded change set.
    /// - Throws: when no event is there, or its detail is not the envelope.
    private static func deliveredChange(
        of run: StubRun
    ) async throws -> (event: OperationEvent, set: FileChangeSet) {
        let events = await outerProgressEvents(of: run)
        #expect(events.count == eventsPerCall, "events were: \(events)")
        let event = try #require(events.first)
        return (event, try changeSet(of: event))
    }

    // MARK: - A write through runCode

    @Test("a write through runCode delivers one add change on the outer run's correlation")
    func writeThroughRunCodeDeliversOneAddChange() async throws {
        let ground = try await makeFilesRun(named: Self.testDirectoryName, recordsChanges: true)
        let path = TestSupport.path(Self.writtenFileName, in: ground.root)

        let output = try await runSnippet(Self.writeSnippet, over: ground.registry, under: ground.run.context)
        let events = await recordedOperationEvents(
            of: ground.run,
            ofKind: .progress,
            correlatedTo: [ground.run.context.completionToken],
            awaiting: Self.eventsPerCall
        )
        let event = try #require(events.first)
        let set = try Self.changeSet(of: event)

        #expect(output == Self.writtenByteCountText, "output was: \(output)")
        #expect(events.count == Self.eventsPerCall, "events were: \(events)")
        #expect(event.correlationID == ground.run.context.completionToken)
        #expect(set.root == ground.journal.root)
        #expect(set.changes == [FileChange(kind: .add, path: path, newContent: Self.writtenContent)])
    }

    // MARK: - The event is there when the call returns

    @Test("the event is in the recorder when the runCode call returns, with no wait, and alone")
    func eventIsRecordedWhenTheCallReturns() async throws {
        let ground = try await makeFilesRun(named: Self.testDirectoryName, recordsChanges: true)

        let output = try await runSnippet(Self.writeSnippet, over: ground.registry, under: ground.run.context)
        let outerEvents = await Self.outerProgressEvents(of: ground.run)
        let everyProgressEvent = await recordedOperationEvents(of: ground.run, ofKind: .progress)

        #expect(output == Self.writtenByteCountText, "output was: \(output)")
        #expect(outerEvents.count == Self.eventsPerCall, "events were: \(outerEvents)")
        #expect(everyProgressEvent.count == Self.eventsPerCall, "events were: \(everyProgressEvent)")
        #expect(outerEvents.allSatisfy { FileChangeSet(operationEventDetail: $0.detail) != nil })
    }

    // MARK: - A patch through runCode

    /// The three-file envelope: one add, one update, and one delete. The
    /// paths are relative, as a model writes them, and the path guard
    /// resolves them against the root.
    private static var patchSnippet: String {
        """
        const patched = await tools.files.patch({ patch: `*** Begin Patch
        *** Add File: \(addedFileName)
        +\(addedLine)
        *** Update File: \(updatedFileName)
        *** Find:
        \(patchFindText)
        *** Replace:
        \(patchReplaceText)
        *** Delete File: \(deletedFileName)
        *** End Patch
        ` });
        if (patched.correction) { return patched.correction; }
        return patched.files.length;
        """
    }

    @Test("a three-file patch through runCode delivers ONE event with three changes")
    func patchThroughRunCodeDeliversOneEventWithThreeChanges() async throws {
        let ground = try await makeFilesRun(named: Self.testDirectoryName, recordsChanges: true)
        try TestSupport.seed(Self.updatedFileName, contents: Self.updatedBefore, in: ground.root)
        try TestSupport.seed(Self.deletedFileName, contents: Self.deletedContent, in: ground.root)

        let output = try await runSnippet(Self.patchSnippet, over: ground.registry, under: ground.run.context)
        let (event, set) = try await Self.deliveredChange(of: ground.run)

        #expect(output == String(Self.patchedFileCount), "output was: \(output)")
        #expect(event.correlationID == ground.run.context.completionToken)
        #expect(set.changes.count == Self.patchedFileCount)
        #expect(Set(set.changes.map(\.kind)) == [.add, .modify, .delete])
    }

    // MARK: - Two calls at the same time

    /// The snippet of one concurrent writer: it meets the other at the
    /// rendezvous, then it writes `fileName`.
    ///
    /// - Parameter fileName: the file this writer writes.
    /// - Returns: the snippet.
    private static func gatedWriteSnippet(writing fileName: String) -> String {
        """
        await tools.\(RendezvousTool.toolName)();
        \(writeVerbSnippet(writing: fileName, content: writtenContent))
        """
    }

    @Test("two concurrent runCode calls over one MultiTool each deliver their own path on their own correlation")
    func concurrentCallsKeepTheirEventsApart() async throws {
        let rendezvous = Rendezvous(partySize: Self.concurrentSnippetCount)
        let first = try await makeFilesRun(
            named: Self.testDirectoryName, recordsChanges: true,
            alongside: [RendezvousTool(rendezvous: rendezvous)])
        let second = try await makeStubRun()
        let multiTool = MultiTool(registry: first.registry)

        async let firstOutput = runSnippet(
            Self.gatedWriteSnippet(writing: Self.firstFileName), through: multiTool, under: first.run.context)
        async let secondOutput = runSnippet(
            Self.gatedWriteSnippet(writing: Self.secondFileName), through: multiTool, under: second.context)
        let outputs = try await [firstOutput, secondOutput]
        let (firstEvent, firstSet) = try await Self.deliveredChange(of: first.run)
        let (secondEvent, secondSet) = try await Self.deliveredChange(of: second)

        #expect(outputs == [Self.writtenByteCountText, Self.writtenByteCountText], "outputs were: \(outputs)")
        #expect(firstEvent.correlationID == first.run.context.completionToken)
        #expect(secondEvent.correlationID == second.context.completionToken)
        #expect(firstSet.changes.map(\.path) == [TestSupport.path(Self.firstFileName, in: first.root)])
        #expect(secondSet.changes.map(\.path) == [TestSupport.path(Self.secondFileName, in: first.root)])
    }

    // MARK: - What the model reads

    /// The snippet that writes ``writtenFileName`` and answers the whole
    /// envelope but its `path`, which differs between two roots.
    private static var envelopeSnippet: String {
        """
        \(writeVerbCall(writing: writtenFileName, content: writtenContent))
        delete written.path;
        return written;
        """
    }

    @Test("a recording capability renders the same runCode text as a non-recording one")
    func recordingAndNonRecordingCapabilitiesRenderTheSameText() async throws {
        let recording = try await makeFilesRun(named: Self.testDirectoryName, recordsChanges: true)
        let plain = try await makeFilesRun(named: Self.testDirectoryName, recordsChanges: false)

        let recordingOutput = try await runSnippet(
            Self.envelopeSnippet, over: recording.registry, under: recording.run.context)
        let plainOutput = try await runSnippet(Self.envelopeSnippet, over: plain.registry, under: plain.run.context)
        let recordingEvents = await Self.outerProgressEvents(of: recording.run)
        let plainEvents = await Self.outerProgressEvents(of: plain.run)

        #expect(recordingOutput == plainOutput, "outputs were: \(recordingOutput) and \(plainOutput)")
        #expect(TestSupport.text(at: TestSupport.path(Self.writtenFileName, in: recording.root)) == Self.writtenContent)
        #expect(TestSupport.text(at: TestSupport.path(Self.writtenFileName, in: plain.root)) == Self.writtenContent)
        #expect(recordingEvents.count == Self.eventsPerCall, "events were: \(recordingEvents)")
        #expect(plainEvents.isEmpty, "events were: \(plainEvents)")
    }
}
