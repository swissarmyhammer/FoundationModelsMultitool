// `FileChangeEventAbsenceTests` — the cases in which no `fileChanges` event
// is posted, and where the change goes instead.
//
// UPSTREAM_ASKS.md, ask 4, part 4: the negative half of the contract of
// `FileChangeJournal.commit(_:through:)`. `FileChangeEventTests` proves that a
// mutating verb which lands under a recording session delivers ONE `.progress`
// event whose `detail` is the `fileChanges` envelope. This suite pins the
// complement: a verb that only reads, a verb under a capability that does not
// record, a mutation that does not land, and a run with no ambient context
// each leave no such event. The run with no ambient context keeps its change
// in the journal for `drain()` instead. The last test tells the two kinds of
// `.progress` event apart by the envelope alone: a `notify()` detail is plain
// text, and `FileChangeSet(operationEventDetail:)` answers `nil` for it.
//
// Each test runs one JavaScript snippet through a `MultiTool` over the files
// registry of a `FilesRun` (see `Fixtures/FilesRunFixtures.swift`), the way a
// model drives the verbs, and it reads the delivered events off the run's stub
// session with `recordedOperationEvents(of:ofKind:correlatedTo:)`. The journal
// is the one the `Write` verb of that registry holds.

import Foundation
import FoundationModels
import FoundationModelsRouter
import Testing

@testable import FoundationModelsMultitool

/// Behavioral tests for the cases in which the journal delivers nothing.
///
/// One test for each acceptance criterion of the card: the read-only snippet,
/// the non-recording capability, the mutation that does not land, the run
/// with no ambient context, and the `notify()` notice beside a write.
@Suite("FileChangeEventAbsenceTests")
struct FileChangeEventAbsenceTests {

    // MARK: - The names and contents of the fixture files

    /// The name of the temporary directory of one test. Thus a leaked
    /// directory is traceable to this suite.
    private static let testDirectoryName = "FileChangeEventAbsenceTests"

    /// The name of the directory that stands outside every session root. The
    /// refused write aims at a file in it.
    private static let outsideDirectoryName = "FileChangeEventAbsenceTests-outside"

    /// The file the read-only snippet and the unresolved edit read.
    private static let seededFileName = "seed.txt"

    /// The content of ``seededFileName``: two lines, thus a read answers a
    /// count the test can compare.
    private static let seededContent = "one\ntwo\n"

    /// The number of lines in ``seededContent``.
    private static let seededLineCount = 2

    /// The number of files the glob of ``textFilePattern`` finds: the one
    /// seeded file.
    private static let globbedFileCount = 1

    /// The number of matching lines the grep of ``grepNeedle`` finds in the
    /// seeded file.
    private static let grepMatchCount = 1

    /// The glob pattern that matches the seeded file.
    private static let textFilePattern = "*.txt"

    /// The text the grep searches for: the first line of the seeded file.
    private static let grepNeedle = "one"

    /// The file the write tests write.
    private static let writtenFileName = "new.txt"

    /// The content the write tests write.
    private static let writtenContent = "hello\n"

    /// The file the refused write aims at, outside the root.
    private static let escapeFileName = "escape.txt"

    /// A `find` text that stands nowhere in ``seededContent``, thus the edit
    /// resolves nothing and commits nothing.
    private static let missingFindText = "no such line"

    /// The text the unresolved edit would have written.
    private static let replacementText = "TWO"

    /// The fragment the path guard's outside-the-root correction carries.
    private static let outsideRootFragment = "outside workspace boundaries"

    /// The detail the `notify()` call posts.
    private static let noticeDetail = "starting the sweep"

    /// How many `.progress` events one `notify()` call posts.
    private static let noticesPerCall = 1

    /// How many `fileChanges` events one landed write posts.
    private static let eventsPerWrite = 1

    // MARK: - The ground of one test

    /// Builds the files run of one test: a canonical root named for this
    /// suite, a files registry over it, its journal, and a stub run.
    ///
    /// - Parameter recordsChanges: whether the capability records changes.
    /// - Returns: the files run.
    /// - Throws: whatever `makeFilesRun(named:recordsChanges:)` throws.
    private static func makeGround(recordsChanges: Bool) async throws -> FilesRun {
        try await makeFilesRun(named: testDirectoryName, recordsChanges: recordsChanges)
    }

    /// Puts the seeded file under the root of a ground.
    ///
    /// - Parameter ground: the ground whose root to seed.
    /// - Returns: the absolute path of the seeded file.
    /// - Throws: rethrows a seed-write failure.
    @discardableResult
    private static func seed(_ ground: FilesRun) throws -> String {
        try TestSupport.seed(seededFileName, contents: seededContent, in: ground.root)
    }

    /// Runs one snippet over the ground's registry, under the stub run's
    /// ambient context.
    ///
    /// - Parameters:
    ///   - code: the snippet to run.
    ///   - ground: the ground whose registry and context to use.
    /// - Returns: the rendered output, as the model would read it.
    /// - Throws: whatever `MultiTool.call(arguments:)` throws.
    private static func run(_ code: String, under ground: FilesRun) async throws -> String {
        try await runSnippet(code, over: ground.registry, under: ground.run.context)
    }

    /// Decodes the JSON value one run returned.
    ///
    /// - Parameters:
    ///   - type: the value type to decode.
    ///   - output: the rendered run output.
    /// - Returns: the decoded value.
    /// - Throws: when `output` is not the JSON text of `type`. The raw
    ///   output is recorded first, thus the failure names what came back.
    private static func decoded<Value: Decodable>(
        _ type: Value.Type, from output: String
    ) throws -> Value {
        do {
            return try JSONDecoder().decode(type, from: Data(output.utf8))
        } catch {
            Issue.record("the output did not decode as \(type): \(output)")
            throw error
        }
    }

    /// The recorded `.progress` events of a run whose `detail` is the
    /// `fileChanges` envelope.
    ///
    /// - Parameter run: the stub run whose transcript to read.
    /// - Returns: the events that decode with `FileChangeSet(operationEventDetail:)`.
    private static func fileChangeEvents(of run: StubRun) async -> [OperationEvent] {
        await recordedOperationEvents(of: run, ofKind: .progress)
            .filter { FileChangeSet(operationEventDetail: $0.detail) != nil }
    }

    /// The snippet that writes ``writtenFileName`` and answers the byte count.
    private static var writeSnippet: String {
        """
        const written = await tools.files.write({ path: "\(writtenFileName)", content: `\(writtenContent)` });
        if (written.correction) { return written.correction; }
        return written.bytesWritten;
        """
    }

    // MARK: - A snippet that only reads

    /// The value the read-only snippet returns: what each reading verb found.
    private struct ReadValue: Decodable {
        /// The lines the read answered.
        let lines: Int

        /// The files the glob found.
        let files: Int

        /// The matching lines the grep found.
        let matches: Int
    }

    @Test("a snippet that only reads under a recording capability leaves no fileChanges event")
    func readsLeaveNoFileChangesEvent() async throws {
        let ground = try await Self.makeGround(recordsChanges: true)
        try Self.seed(ground)

        let output = try await Self.run(
            """
            const read = await tools.files.read({ path: "\(Self.seededFileName)" });
            if (read.correction) { return read.correction; }
            const globbed = await tools.files.glob({ pattern: "\(Self.textFilePattern)" });
            if (globbed.correction) { return globbed.correction; }
            const grep = await tools.files.grep({ pattern: "\(Self.grepNeedle)" });
            if (grep.correction) { return grep.correction; }
            return {
                lines: read.lines.length,
                files: globbed.files.length,
                matches: grep.matches.filter((m) => m.isMatch).length,
            };
            """, under: ground)
        let value = try Self.decoded(ReadValue.self, from: output)
        let events = await Self.fileChangeEvents(of: ground.run)

        #expect(value.lines == Self.seededLineCount)
        #expect(value.files == Self.globbedFileCount)
        #expect(value.matches == Self.grepMatchCount)
        #expect(events.isEmpty, "events were: \(events)")
    }

    // MARK: - A capability that does not record

    @Test("a write under a non-recording capability leaves no event and an empty journal")
    func writeUnderNonRecordingCapabilityLeavesNothing() async throws {
        let ground = try await Self.makeGround(recordsChanges: false)

        let output = try await Self.run(Self.writeSnippet, under: ground)
        let bytesWritten = try Self.decoded(Int.self, from: output)
        let events = await Self.fileChangeEvents(of: ground.run)
        let drained = await ground.journal.drain()

        #expect(bytesWritten == Self.writtenContent.utf8.count)
        #expect(TestSupport.text(at: TestSupport.path(Self.writtenFileName, in: ground.root)) == Self.writtenContent)
        #expect(events.isEmpty, "events were: \(events)")
        #expect(drained.changes.isEmpty)
    }

    // MARK: - A mutation that does not land

    /// The value the refused-mutation snippet returns: the correction of the
    /// refused write and the status of the unresolved edit.
    private struct RefusedValue: Decodable {
        /// The correction the path guard answered for the write.
        let refusedCorrection: String

        /// The whole-batch status the edit answered.
        let editStatus: String
    }

    @Test("a write the path guard refuses and an edit that does not resolve leave no fileChanges event")
    func mutationsThatDoNotLandLeaveNoFileChangesEvent() async throws {
        let ground = try await Self.makeGround(recordsChanges: true)
        let seededPath = try Self.seed(ground)
        let outside = TestSupport.makeTemporaryDirectory(named: Self.outsideDirectoryName)
        let escapePath = TestSupport.path(Self.escapeFileName, in: outside)

        let output = try await Self.run(
            """
            const refused = await tools.files.write({ path: "\(escapePath)", content: `\(Self.writtenContent)` });
            const edited = await tools.files.edit({
                path: "\(Self.seededFileName)",
                find: ["\(Self.missingFindText)"],
                replace: ["\(Self.replacementText)"],
            });
            if (edited.correction) { return edited.correction; }
            return { refusedCorrection: refused.correction, editStatus: edited.status };
            """, under: ground)
        let value = try Self.decoded(RefusedValue.self, from: output)
        let events = await Self.fileChangeEvents(of: ground.run)
        let drained = await ground.journal.drain()

        #expect(value.refusedCorrection.contains(Self.outsideRootFragment), "correction was: \(value.refusedCorrection)")
        #expect(value.editStatus != EditOutcomeProjection.appliedStatus)
        #expect(!FileManager.default.fileExists(atPath: escapePath), "a refused write must not create the file")
        #expect(TestSupport.text(at: seededPath) == Self.seededContent)
        #expect(events.isEmpty, "events were: \(events)")
        #expect(drained.changes.isEmpty)
    }

    // MARK: - A run with no ambient context

    @Test("a run with no ambient context delivers nothing and keeps the change for drain")
    func runWithNoAmbientContextKeepsTheChangeForDrain() async throws {
        let ground = try await Self.makeGround(recordsChanges: true)
        let path = TestSupport.path(Self.writtenFileName, in: ground.root)

        let output = try await runSnippet(Self.writeSnippet, over: ground.registry)
        let bytesWritten = try Self.decoded(Int.self, from: output)
        let events = await recordedOperationEvents(of: ground.run, ofKind: .progress)
        let drained = await ground.journal.drain()

        #expect(bytesWritten == Self.writtenContent.utf8.count)
        #expect(TestSupport.text(at: path) == Self.writtenContent)
        #expect(events.isEmpty, "events were: \(events)")
        #expect(drained.changes == [FileChange(kind: .add, path: path, newContent: Self.writtenContent)])
    }

    // MARK: - A notice beside a write

    @Test("a notify() beside a write posts a plain-text progress event the envelope tells apart")
    func noticeBesideAWriteIsToldApartByTheEnvelope() async throws {
        let ground = try await Self.makeGround(recordsChanges: true)
        let path = TestSupport.path(Self.writtenFileName, in: ground.root)

        let output = try await Self.run(
            """
            notify("\(Self.noticeDetail)");
            \(Self.writeSnippet)
            """, under: ground)
        let bytesWritten = try Self.decoded(Int.self, from: output)
        let events = await recordedOperationEvents(
            of: ground.run,
            ofKind: .progress,
            correlatedTo: [ground.run.context.completionToken],
            awaiting: Self.noticesPerCall + Self.eventsPerWrite
        )
        let notices = events.filter { $0.detail == Self.noticeDetail }
        let changeSets = events.compactMap { FileChangeSet(operationEventDetail: $0.detail) }

        #expect(bytesWritten == Self.writtenContent.utf8.count)
        #expect(events.count == Self.noticesPerCall + Self.eventsPerWrite, "events were: \(events)")
        #expect(notices.count == Self.noticesPerCall)
        #expect(notices.allSatisfy { FileChangeSet(operationEventDetail: $0.detail) == nil })
        #expect(changeSets.count == Self.eventsPerWrite)
        #expect(changeSets.first?.changes == [FileChange(kind: .add, path: path, newContent: Self.writtenContent)])
    }
}
