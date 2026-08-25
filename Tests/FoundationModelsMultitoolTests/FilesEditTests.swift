// `FilesEditTests` — the behavioral suite of the `tools.files.edit` verb.
//
// A port of `../FoundationModelsFileTool/Tests/FileToolTests/
// EditFileTests.swift`, adapted to the `Tool` call shape: the sibling
// decoded an `EditFile` operation out of `GeneratedContent`; here the suite
// constructs `EditArguments` with the memberwise initializer and calls the
// `Edit` verb directly, the way `FilesWriteTests` calls its verb. The
// sibling's `EditOutput` accessors do not port: the flat result carries a
// `correction` field, and the suite reads it directly. The sibling's
// structured `outcomes` were typed values; here each outcome is one JSON
// string (sorted keys), thus the assertions read the JSON text. The
// anchor-chain and envelope tests call the `Write` and `Read` verbs where
// the sibling called `WriteFile` and `ReadFile`. The sibling folded
// compiler diagnostics into its result; decision 2026-08-11 in eventplan.md
// removes that fold, thus no diagnostics case ports.
//
// Five tests are not in the sibling: the outside-the-root correction and
// the read-only-context correction, which the card's acceptance criteria
// name, and three journal tests — a recorded modify, a disabled journal,
// and an unresolved batch that records nothing — which the card's shape
// section names.

import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Behavioral tests for the `tools.files.edit` verb.
///
/// Every case of the sibling `edit file` suite is here: single /
/// `replacesAll` / `occurrence` edits; a multi-pair parallel-array batch;
/// CRLF and UTF-8-BOM round-trips asserting the bytes outside the edited
/// range stay identical; mixed line endings reported; the executable bit
/// preserved across a commit; a read-only file left byte-identical with a
/// correction; a commit failure that leaves no temporary file and the file
/// byte-identical; the structured retryable outcomes (ambiguous, near-miss,
/// already-applied, consumed-target) that commit nothing; the corrective
/// hard errors (`find == replace` no-op, count mismatch, empty find, blank
/// path, non-existent file, binary file); the applied-result envelope
/// fields; and the write→edit anchor chain with no intervening read. From
/// this card's own criteria: the outside-the-root correction, the
/// read-only-context correction, and the journal recording.
@Suite struct FilesEditTests {
    // MARK: Test scaffolding

    /// The permissions of a file the owner cannot write.
    private static let readOnlyFileMode = 0o444

    /// The permissions that make a read-only file writable again.
    private static let writableFileMode = 0o644

    /// The permissions of an executable file, preserved across an edit.
    private static let executableFileMode = 0o755

    /// The permissions of a directory that the owner cannot write.
    private static let readOnlyDirectoryMode = 0o555

    /// The permissions that make a read-only directory writable again.
    private static let writableDirectoryMode = 0o755

    /// The 1-based selector of the second literal occurrence.
    private static let secondOccurrence = 2

    /// The UTF-8 byte-order-mark bytes (`EF BB BF`).
    private static let utf8ByteOrderMark = Data([0xEF, 0xBB, 0xBF])

    /// Call the `tools.files.edit` verb over a session context.
    ///
    /// - Parameters:
    ///   - path: the file path to edit.
    ///   - find: the `find` values, or `nil`.
    ///   - replace: the `replace` values, or `nil`.
    ///   - replacesAll: whether every occurrence is rewritten, or `nil`.
    ///   - occurrence: the 1-based occurrence selector, or `nil`.
    ///   - context: the session context the verb edits against.
    /// - Returns: the verb's flat result.
    private static func edit(
        path: String,
        find: [String]? = nil,
        replace: [String]? = nil,
        replacesAll: Bool? = nil,
        occurrence: Int? = nil,
        in context: FileContext
    ) async throws -> EditResult {
        try await Edit(context: context).call(
            arguments: EditArguments(
                path: path, find: find, replace: replace, replacesAll: replacesAll, occurrence: occurrence))
    }

    /// Write `data` to a file named `name` inside a fresh temporary directory.
    ///
    /// - Parameters:
    ///   - data: the raw bytes to seed the file with.
    ///   - name: the file name to create in the temporary directory.
    ///   - recordsChanges: whether the context records changes.
    /// - Returns: the session context rooted at the temporary directory, the
    ///   file's URL, and its absolute path.
    private static func makeContext(
        seeding data: Data,
        named name: String = "sample.txt",
        recordsChanges: Bool = false
    ) throws -> (context: FileContext, url: URL, path: String) {
        let root = TestSupport.makeTemporaryDirectory(named: "FilesEditTests")
        let fileURL = root.appendingPathComponent(name, isDirectory: false)
        try data.write(to: fileURL)
        return (FileContext(root: root, recordsChanges: recordsChanges), fileURL, fileURL.path)
    }

    /// Read the raw on-disk bytes of a file.
    ///
    /// - Parameter path: the absolute path to read.
    /// - Returns: the file's bytes.
    private static func readBytes(_ path: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: path))
    }

    // MARK: Single / replacesAll / occurrence

    /// A scalar edit rewrites the one matched text and reports a literal match.
    @Test func singleEditReplacesTheMatchedText() async throws {
        let (context, _, path) = try Self.makeContext(seeding: Data("alpha\nbeta\ngamma\n".utf8))

        let result = try await Self.edit(path: path, find: ["beta"], replace: ["BETA"], in: context)

        #expect(result.correction == nil)
        #expect(result.status == "applied")
        #expect(result.applied == 1)
        #expect(try #require(result.outcomes.first).contains("\"matchedBy\":\"literal\""))
        #expect(try Self.readBytes(path) == Data("alpha\nBETA\ngamma\n".utf8))
    }

    /// `replacesAll` rewrites every occurrence in one applied pair.
    @Test func replacesAllRewritesEveryOccurrence() async throws {
        let (context, _, path) = try Self.makeContext(seeding: Data("x\nx\nx\n".utf8))

        let result = try await Self.edit(path: path, find: ["x"], replace: ["y"], replacesAll: true, in: context)

        #expect(result.status == "applied")
        #expect(result.applied == 1)
        #expect(try Self.readBytes(path) == Data("y\ny\ny\n".utf8))
    }

    /// `occurrence` selects one site among several literal matches.
    @Test func occurrenceSelectsAmongLiteralMatches() async throws {
        let (context, _, path) = try Self.makeContext(seeding: Data("x\nx\nx\n".utf8))

        let result = try await Self.edit(
            path: path, find: ["x"], replace: ["y"], occurrence: Self.secondOccurrence, in: context)

        #expect(result.status == "applied")
        #expect(try Self.readBytes(path) == Data("x\ny\nx\n".utf8))
    }

    // MARK: Multi-pair batch

    /// Parallel `find`/`replace` arrays apply in order as one batch.
    @Test func multiPairParallelArraysApplyInOrder() async throws {
        let (context, _, path) = try Self.makeContext(seeding: Data("foo\nbar\n".utf8))
        let finds = ["foo", "bar"]

        let result = try await Self.edit(path: path, find: finds, replace: ["FOO", "BAR"], in: context)

        #expect(result.status == "applied")
        #expect(result.applied == finds.count)
        #expect(result.outcomes.count == finds.count)
        #expect(try Self.readBytes(path) == Data("FOO\nBAR\n".utf8))
    }

    // MARK: CRLF round-trip

    /// A CRLF file keeps every terminator outside the edited line.
    @Test func crlfEditPreservesBytesOutsideTheEditedLine() async throws {
        let original = Data("line one\r\nline two\r\nline three\r\n".utf8)
        let (context, _, path) = try Self.makeContext(seeding: original)

        let result = try await Self.edit(path: path, find: ["line two"], replace: ["LINE TWO"], in: context)

        #expect(result.status == "applied")
        #expect(result.lineEndings == "crlf")
        #expect(result.encoding == "utf-8")
        let committed = try Self.readBytes(path)
        #expect(committed == Data("line one\r\nLINE TWO\r\nline three\r\n".utf8))
        // Every terminator survives: the edit rewrites only the line's text.
        #expect(String(decoding: committed, as: UTF8.self).contains("\r\n"))
        #expect(!String(decoding: committed, as: UTF8.self).contains("\n\n"))
    }

    // MARK: UTF-8-BOM round-trip

    /// A UTF-8-BOM file keeps its byte-order mark across the edit.
    @Test func bomEditKeepsTheByteOrderMarkIntact() async throws {
        let original = Self.utf8ByteOrderMark + Data("alpha\nbeta\n".utf8)
        let (context, _, path) = try Self.makeContext(seeding: original)

        let result = try await Self.edit(path: path, find: ["beta"], replace: ["BETA"], in: context)

        #expect(result.status == "applied")
        #expect(result.encoding == "utf-8 bom")
        let committed = try Self.readBytes(path)
        #expect(committed.prefix(Self.utf8ByteOrderMark.count) == Self.utf8ByteOrderMark)
        #expect(committed == Self.utf8ByteOrderMark + Data("alpha\nBETA\n".utf8))
    }

    // MARK: Mixed line endings

    /// A file with more than one terminator convention reports `mixed`.
    @Test func mixedLineEndingsAreReported() async throws {
        let (context, _, path) = try Self.makeContext(seeding: Data("a\r\nb\rc\n".utf8))

        let result = try await Self.edit(path: path, find: ["b"], replace: ["B"], in: context)

        #expect(result.status == "applied")
        #expect(result.lineEndings == "mixed")
    }

    // MARK: Permission preservation

    /// Editing an executable file keeps its permission bits.
    @Test func executableBitIsPreservedAcrossAnEdit() async throws {
        let (context, url, path) = try Self.makeContext(
            seeding: Data("#!/bin/sh\necho old\n".utf8), named: "script.sh")
        try FileManager.default.setAttributes(
            [.posixPermissions: Self.executableFileMode], ofItemAtPath: url.path)

        let result = try await Self.edit(path: path, find: ["echo old"], replace: ["echo new"], in: context)

        #expect(result.correction == nil)
        #expect(
            TestSupport.permissionBits(path) == Self.executableFileMode,
            "editing a 0755 file must keep it 0755")
    }

    // MARK: Read-only file

    /// An edit on a read-only file comes back as a correction and leaves the
    /// file byte-identical.
    @Test func readOnlyFileIsCorrectiveAndLeavesItByteIdentical() async throws {
        let original = Data("original\n".utf8)
        let (context, url, path) = try Self.makeContext(seeding: original, named: "locked.txt")
        try FileManager.default.setAttributes(
            [.posixPermissions: Self.readOnlyFileMode], ofItemAtPath: url.path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: Self.writableFileMode], ofItemAtPath: url.path)
        }

        let result = try await Self.edit(path: path, find: ["original"], replace: ["changed"], in: context)
        let message = try #require(result.correction)

        #expect(!message.isEmpty)
        #expect(try Self.readBytes(path) == original, "a read-only target must be byte-identical")
    }

    // MARK: Commit-failure cleanup

    /// A commit that fails after the batch resolved comes back as a
    /// correction, removes its temporary file, and leaves the file
    /// byte-identical.
    @Test func commitFailureLeavesNoTempFilesAndTheFileByteIdentical() async throws {
        let root = TestSupport.makeTemporaryDirectory(named: "FilesEditTests")
        let lockedDirectory = root.appendingPathComponent("locked-dir", isDirectory: true)
        try FileManager.default.createDirectory(at: lockedDirectory, withIntermediateDirectories: true)
        let fileURL = lockedDirectory.appendingPathComponent("target.txt", isDirectory: false)
        let original = Data("alpha\nbeta\n".utf8)
        try original.write(to: fileURL)
        // The file itself stays writable (the edit permission passes) but its
        // directory is read-only, thus the atomic writer's temp-file creation
        // fails at commit time — after the batch has already resolved.
        try FileManager.default.setAttributes(
            [.posixPermissions: Self.readOnlyDirectoryMode], ofItemAtPath: lockedDirectory.path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: Self.writableDirectoryMode], ofItemAtPath: lockedDirectory.path)
        }
        let context = FileContext(root: root)

        let result = try await Self.edit(path: fileURL.path, find: ["beta"], replace: ["BETA"], in: context)
        let message = try #require(result.correction)

        #expect(message == "The edit resolved but could not be committed: \(fileURL.path)")
        #expect(
            TestSupport.temporaryFileLeftovers(in: lockedDirectory).isEmpty,
            "a failed commit must remove the temp file")
        #expect(try Self.readBytes(fileURL.path) == original, "a failed commit must leave the file byte-identical")
    }

    // MARK: Structured retryable outcomes

    /// An ambiguous edit reports its candidate sites and commits nothing.
    @Test func ambiguousEditReportsCandidatesAndCommitsNothing() async throws {
        let original = Data("x\nx\n".utf8)
        let (context, _, path) = try Self.makeContext(seeding: original)

        let result = try await Self.edit(path: path, find: ["x"], replace: ["y"], in: context)

        #expect(result.status == "ambiguous")
        #expect(result.applied == 0)
        #expect(result.bytesWritten == nil)
        #expect(result.hash == nil)
        let outcome = try #require(result.outcomes.first)
        #expect(outcome.contains("\"matchedBy\":\"ambiguous\""))
        #expect(outcome.contains("\"occurrence\":1"))
        #expect(outcome.contains("\"occurrence\":\(Self.secondOccurrence)"))
        #expect(try Self.readBytes(path) == original, "an ambiguous edit must leave the file byte-identical")
    }

    /// A near-miss edit reports a line diff and commits nothing.
    @Test func nearMissEditReportsALineDiffAndCommitsNothing() async throws {
        let original = Data("the quick brown fox\n".utf8)
        let (context, _, path) = try Self.makeContext(seeding: original)

        let result = try await Self.edit(path: path, find: ["the quick red fox"], replace: ["X"], in: context)

        #expect(result.status == "nearMiss")
        #expect(result.applied == 0)
        let outcome = try #require(result.outcomes.first)
        #expect(outcome.contains("\"startLine\":1"))
        #expect(outcome.contains("{\"change\":\"expected\",\"text\":\"the quick red fox\"}"))
        #expect(outcome.contains("{\"change\":\"actual\",\"text\":\"the quick brown fox\"}"))
        #expect(try Self.readBytes(path) == original, "a near-miss must leave the file byte-identical")
    }

    /// A near-miss that differs only by confusable punctuation carries the
    /// punctuation note in its wire outcome.
    @Test func nearMissEditSurfacesAConfusablePunctuationNote() async throws {
        let original = Data("don\u{2019}t stop\n".utf8)
        let (context, _, path) = try Self.makeContext(seeding: original)

        let result = try await Self.edit(
            path: path,
            find: ["don't stop\nEXTRA_LINE_NOT_PRESENT"],
            replace: ["X"],
            in: context)

        #expect(result.status == "nearMiss")
        let outcome = try #require(result.outcomes.first)
        #expect(outcome.contains("\"note\":\"differs only by Unicode punctuation"))
        #expect(outcome.contains("U+2019"))
        #expect(outcome.contains("U+0027"))
        #expect(try Self.readBytes(path) == original, "a near-miss must leave the file byte-identical")
    }

    /// A near-miss that differs by a real word carries no punctuation note.
    @Test func genuinelyDifferentNearMissHasNoConfusableNote() async throws {
        // The mirror of `nearMissEditSurfacesAConfusablePunctuationNote`: this
        // near-miss differs by a real word rather than by confusable
        // punctuation, thus the note must be absent rather than attached to
        // every near-miss diff.
        let original = Data("the quick brown fox\n".utf8)
        let (context, _, path) = try Self.makeContext(seeding: original)

        let result = try await Self.edit(path: path, find: ["the quick red fox"], replace: ["X"], in: context)

        #expect(result.status == "nearMiss")
        let outcome = try #require(result.outcomes.first)
        #expect(!outcome.contains("\"note\""), "an absent note is omitted from the wire outcome")
    }

    /// An already-applied edit is reported with a note and commits nothing.
    @Test func alreadyAppliedEditIsReportedAndCommitsNothing() async throws {
        let original = Data("world\n".utf8)
        let (context, _, path) = try Self.makeContext(seeding: original)

        let result = try await Self.edit(path: path, find: ["hello"], replace: ["world"], in: context)

        #expect(result.status == "alreadyApplied")
        #expect(result.applied == 0)
        #expect(try #require(result.outcomes.first).contains("\"note\":"))
        #expect(try Self.readBytes(path) == original)
    }

    /// A consumed-target edit is reported and commits nothing.
    @Test func consumedTargetEditIsReportedAndCommitsNothing() async throws {
        let original = Data("foo\nbar\n".utf8)
        let (context, _, path) = try Self.makeContext(seeding: original)

        let result = try await Self.edit(path: path, find: ["foo", "foo"], replace: ["XXX", "YYY"], in: context)

        #expect(result.status == "consumedTarget")
        #expect(result.applied == 0)
        #expect(try Self.readBytes(path) == original)
    }

    // MARK: Corrective hard errors

    /// A `find == replace` no-op comes back as a correction.
    @Test func identicalFindAndReplaceIsCorrective() async throws {
        let (context, _, path) = try Self.makeContext(seeding: Data("same\n".utf8))

        let result = try await Self.edit(path: path, find: ["same"], replace: ["same"], in: context)
        let message = try #require(result.correction)

        #expect(!message.isEmpty)
    }

    /// A `find`/`replace` count mismatch comes back as a correction naming
    /// the unpaired value.
    @Test func countMismatchIsCorrective() async throws {
        let (context, _, path) = try Self.makeContext(seeding: Data("a\nb\nc\n".utf8))

        let result = try await Self.edit(path: path, find: ["a", "b", "c"], replace: ["X", "Y"], in: context)
        let message = try #require(result.correction)

        #expect(message.contains("\"c\""))
    }

    /// An absent `find` comes back as a correction.
    @Test func missingFindIsCorrective() async throws {
        let (context, _, path) = try Self.makeContext(seeding: Data("content\n".utf8))

        let result = try await Self.edit(path: path, replace: ["X"], in: context)
        let message = try #require(result.correction)

        #expect(!message.isEmpty)
    }

    /// A blank path comes back as a correction.
    @Test func blankPathIsCorrective() async throws {
        let context = FileContext(root: TestSupport.makeTemporaryDirectory(named: "FilesEditTests"))

        let result = try await Self.edit(path: "   ", find: ["a"], replace: ["b"], in: context)
        let message = try #require(result.correction)

        #expect(!message.isEmpty)
    }

    /// A non-existent file comes back as a correction: an edit requires the
    /// file to exist.
    @Test func nonExistentFileIsCorrective() async throws {
        let root = TestSupport.makeTemporaryDirectory(named: "FilesEditTests")
        let missing = root.appendingPathComponent("does-not-exist.txt", isDirectory: false)
        let context = FileContext(root: root)

        let result = try await Self.edit(path: missing.path, find: ["a"], replace: ["b"], in: context)
        let message = try #require(result.correction)

        #expect(!message.isEmpty)
    }

    /// A binary file comes back as a correction and is never rewritten.
    @Test func binaryFileIsCorrectiveAndLeftByteIdentical() async throws {
        let original = Data([0xFF, 0xFE, 0x00, 0x01, 0xFF, 0x80])
        let (context, _, path) = try Self.makeContext(seeding: original, named: "blob.bin")

        let result = try await Self.edit(path: path, find: ["a"], replace: ["b"], in: context)
        let message = try #require(result.correction)

        #expect(
            message
                == "The file is not valid UTF-8 text and appears to be binary, so it cannot be edited as text: \(path)")
        #expect(try Self.readBytes(path) == original, "a binary file must never be decoded or rewritten")
    }

    // MARK: Corrective paths of this card

    /// A path outside the session root comes back as a correction and the
    /// outside file is untouched: the edit stays bounded through the
    /// session's path guard.
    @Test func pathOutsideTheRootIsCorrective() async throws {
        let root = TestSupport.makeTemporaryDirectory(named: "FilesEditTests")
        let outside = TestSupport.makeTemporaryDirectory(named: "FilesEditTestsOutside")
        let outsideURL = outside.appendingPathComponent("escape.txt", isDirectory: false)
        let original = Data("outside\n".utf8)
        try original.write(to: outsideURL)
        let context = FileContext(root: root)

        let result = try await Self.edit(path: outsideURL.path, find: ["outside"], replace: ["inside"], in: context)
        let message = try #require(result.correction)

        #expect(!message.isEmpty)
        #expect(try Self.readBytes(outsideURL.path) == original, "a rejected edit must not change the file")
    }

    /// An edit on a read-only context comes back as a correction and the
    /// file is untouched: the context flag forbids the mutating verbs up
    /// front.
    @Test func readOnlyContextIsCorrectiveAndLeavesItByteIdentical() async throws {
        let root = TestSupport.makeTemporaryDirectory(named: "FilesEditTests")
        let url = root.appendingPathComponent("forbidden.txt", isDirectory: false)
        let original = Data("original\n".utf8)
        try original.write(to: url)
        let context = FileContext(root: root, readOnly: true)

        let result = try await Self.edit(path: url.path, find: ["original"], replace: ["changed"], in: context)
        let message = try #require(result.correction)

        #expect(!message.isEmpty)
        #expect(try Self.readBytes(url.path) == original, "a read-only context must not change the file")
    }

    // MARK: Applied-result envelope fields

    /// The applied envelope's `bytesWritten`, `encoding`, `hash`, and
    /// `taggedContent` equal what a subsequent read of the path computes.
    @Test func appliedResultEnvelopeMatchesASubsequentRead() async throws {
        let (context, url, path) = try Self.makeContext(seeding: Data("alpha\nbeta\ngamma\n".utf8))

        let result = try await Self.edit(path: path, find: ["beta"], replace: ["BETA"], in: context)

        let committed = try Self.readBytes(path)
        #expect(result.bytesWritten == committed.count)
        #expect(result.encoding == "utf-8")
        #expect(result.hash == Hashline.wholeFileHash(bytes: committed))

        let readResult = try await Read(context: context)
            .call(arguments: ReadArguments(path: url.path, offset: nil, limit: nil, format: nil))
        #expect(result.hash == readResult.hash)
        #expect(try #require(result.taggedContent) == readResult.lines)
    }

    // MARK: Write → edit anchor chain (no intervening read)

    /// A `write` envelope's hashline anchor resolves in an edit with no read
    /// in between.
    @Test func writeEnvelopeAnchorResolvesInAnEditWithNoInterveningRead() async throws {
        let root = TestSupport.makeTemporaryDirectory(named: "FilesEditTests")
        let url = root.appendingPathComponent("chained.txt", isDirectory: false)
        let context = FileContext(root: root)

        // 1. write — capture the write envelope's hashline-tagged content.
        let writeResult = try await Write(context: context)
            .call(arguments: WriteArguments(path: url.path, content: "alpha\nbeta\ngamma\n"))
        #expect(writeResult.correction == nil)
        // The second tagged line ("2:HH|beta") is the anchor a chained edit lifts.
        let anchor = writeResult.taggedContent[1]

        // 2. edit using that anchor directly — no read in between.
        let result = try await Self.edit(path: url.path, find: [anchor], replace: ["BETA"], in: context)

        #expect(result.status == "applied")
        let outcome = try #require(result.outcomes.first)
        #expect(outcome.contains("\"matchedBy\":\"anchor\""))
        #expect(outcome.contains("\"line\":\(Self.secondOccurrence)"))
        #expect(try Self.readBytes(url.path) == Data("alpha\nBETA\ngamma\n".utf8))
    }

    // MARK: Change recording

    /// An applied edit on a recording context records one modify change
    /// carrying the text on both sides.
    @Test func aRecordingContextRecordsAModifyChangeWithTheOldText() async throws {
        let (context, _, path) = try Self.makeContext(
            seeding: Data("old\n".utf8), recordsChanges: true)

        let result = try await Self.edit(path: path, find: ["old"], replace: ["new"], in: context)
        #expect(result.correction == nil)

        let changes = await context.changes.drain().changes
        let change = try #require(changes.first)
        #expect(changes.count == 1)
        #expect(change.kind == .modify)
        #expect(change.oldContent == "old\n")
        #expect(change.newContent == "new\n")
    }

    /// An edit on a non-recording context records nothing: the journal is
    /// disabled.
    @Test func aDisabledJournalRecordsNothing() async throws {
        let (context, _, path) = try Self.makeContext(seeding: Data("old\n".utf8))

        let result = try await Self.edit(path: path, find: ["old"], replace: ["new"], in: context)
        #expect(result.correction == nil)

        let changes = await context.changes.drain().changes
        #expect(changes.isEmpty)
    }

    /// An unresolved batch commits nothing and records nothing, on a
    /// recording context.
    @Test func anUnresolvedBatchRecordsNothing() async throws {
        let (context, _, path) = try Self.makeContext(
            seeding: Data("x\nx\n".utf8), recordsChanges: true)

        let result = try await Self.edit(path: path, find: ["x"], replace: ["y"], in: context)
        #expect(result.status == "ambiguous")

        let changes = await context.changes.drain().changes
        #expect(changes.isEmpty, "an unresolved batch must record no change")
    }
}
