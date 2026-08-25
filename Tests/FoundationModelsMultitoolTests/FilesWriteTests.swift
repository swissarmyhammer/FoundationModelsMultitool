// `FilesWriteTests` — the behavioral suite of the `tools.files.write` verb.
//
// A port of `../FoundationModelsFileTool/Tests/FileToolTests/
// WriteFileTests.swift`, adapted to the `Tool` call shape: the sibling
// decoded a `WriteFile` operation out of `GeneratedContent`; here the suite
// constructs `WriteArguments` with the memberwise initializer and calls the
// `Write` verb directly, the way `FilesReadTests` calls its verb. The
// sibling's `WriteOutput` accessors do not port: the flat result carries a
// `correction` field, and the suite reads it directly. The sibling folded
// compiler diagnostics into its result; decision 2026-08-11 in eventplan.md
// removes that fold, thus no diagnostics case ports.
//
// The envelope tests call the `Read` verb where the sibling called
// `ReadFile`. Four tests are not in the sibling: the outside-the-root
// correction and the read-only-context correction, which the card's
// acceptance criteria name, and the two journal-recording tests, which the
// card's shape section names.

import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Behavioral tests for the `tools.files.write` verb.
///
/// Every case of the sibling `write file` suite is here: writing a new file
/// and overwriting an existing one; the blank-path correction; the
/// content-size cap (rejected one byte over, accepted exactly at the cap);
/// the read-only-target correction; temp-file cleanup on both a write
/// failure and a rename failure, with a directory scan proving no `.tmp.*`
/// files remain; unicode and empty content; permission preservation on
/// overwrite; and the envelope fields — `bytesWritten`, the freshness `hash`
/// matching a subsequent read, and `taggedContent` matching that read's
/// hashline tagging. From this card's own criteria: the outside-the-root
/// correction, the read-only-context correction, and the journal recording
/// an add and a modify.
@Suite struct FilesWriteTests {
    // MARK: Test scaffolding

    /// The content-size cap in bytes, matching the verb's cap (10 MiB).
    private static let contentByteCap = 10 * 1024 * 1024

    /// The permissions of a file the owner cannot write.
    private static let readOnlyFileMode = 0o444

    /// The permissions of an executable file, preserved across an overwrite.
    private static let executableFileMode = 0o755

    /// The permissions of a directory that the owner cannot write.
    private static let readOnlyDirectoryMode = 0o555

    /// The permissions that make a read-only directory writable again.
    private static let writableDirectoryMode = 0o755

    /// Call the `tools.files.write` verb over a session context.
    ///
    /// - Parameters:
    ///   - path: the file path to write.
    ///   - content: the content to write.
    ///   - context: the session context the verb writes against.
    /// - Returns: the verb's flat result.
    private static func write(
        path: String,
        content: String,
        in context: FileContext
    ) async throws -> WriteResult {
        try await Write(context: context).call(arguments: WriteArguments(path: path, content: content))
    }

    /// Read the raw on-disk bytes of a file.
    ///
    /// - Parameter path: the absolute path to read.
    /// - Returns: the file's bytes.
    private static func readBytes(_ path: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: path))
    }

    // MARK: New and overwrite

    /// A write to a fresh path creates the file with the exact bytes.
    @Test func writesANewFile() async throws {
        let root = TestSupport.makeTemporaryDirectory(named: "FilesWriteTests")
        let path = root.appendingPathComponent("new.txt", isDirectory: false).path
        let context = FileContext(root: root)

        let result = try await Self.write(path: path, content: "hello\nworld\n", in: context)

        #expect(result.correction == nil)
        #expect(try Self.readBytes(path) == Data("hello\nworld\n".utf8))
        #expect(result.bytesWritten == Data("hello\nworld\n".utf8).count)
    }

    /// A write to an existing path replaces the file's bytes.
    @Test func overwritesAnExistingFile() async throws {
        let root = TestSupport.makeTemporaryDirectory(named: "FilesWriteTests")
        let url = root.appendingPathComponent("existing.txt", isDirectory: false)
        try Data("stale contents that are longer\n".utf8).write(to: url)
        let context = FileContext(root: root)

        let result = try await Self.write(path: url.path, content: "fresh\n", in: context)

        #expect(result.correction == nil)
        #expect(try Self.readBytes(url.path) == Data("fresh\n".utf8))
        #expect(result.bytesWritten == Data("fresh\n".utf8).count)
    }

    // MARK: Blank path

    /// A blank path comes back as a correction, not as a thrown error.
    @Test func blankPathIsCorrective() async throws {
        let context = FileContext(root: TestSupport.makeTemporaryDirectory(named: "FilesWriteTests"))

        let result = try await Self.write(path: "   ", content: "x", in: context)
        let message = try #require(result.correction)

        #expect(!message.isEmpty)
    }

    // MARK: Content-size cap

    /// Content one byte over the cap comes back as a correction and creates
    /// no file.
    @Test func contentOneByteOverCapIsCorrective() async throws {
        let root = TestSupport.makeTemporaryDirectory(named: "FilesWriteTests")
        let path = root.appendingPathComponent("big.txt", isDirectory: false).path
        let context = FileContext(root: root)
        let oversized = String(repeating: "a", count: Self.contentByteCap + 1)

        let result = try await Self.write(path: path, content: oversized, in: context)
        let message = try #require(result.correction)

        #expect(message.contains("content"))
        #expect(!FileManager.default.fileExists(atPath: path), "an over-cap write must not create the file")
    }

    /// Content exactly at the cap is accepted and written whole.
    @Test func contentExactlyAtCapIsAccepted() async throws {
        let root = TestSupport.makeTemporaryDirectory(named: "FilesWriteTests")
        let path = root.appendingPathComponent("atcap.txt", isDirectory: false).path
        let context = FileContext(root: root)
        let atCap = String(repeating: "a", count: Self.contentByteCap)

        let result = try await Self.write(path: path, content: atCap, in: context)

        #expect(result.correction == nil)
        #expect(result.bytesWritten == Self.contentByteCap)
    }

    // MARK: Read-only target

    /// A write onto a read-only file comes back as a correction and leaves
    /// the file untouched.
    @Test func readOnlyTargetIsCorrectiveAndLeavesItUntouched() async throws {
        let root = TestSupport.makeTemporaryDirectory(named: "FilesWriteTests")
        let url = root.appendingPathComponent("locked.txt", isDirectory: false)
        try Data("original\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: Self.readOnlyFileMode], ofItemAtPath: url.path)
        let context = FileContext(root: root)

        let result = try await Self.write(path: url.path, content: "overwrite\n", in: context)
        let message = try #require(result.correction)

        #expect(!message.isEmpty)
        #expect(try Self.readBytes(url.path) == Data("original\n".utf8), "a read-only target must be untouched")
    }

    // MARK: Cleanup on failure

    /// A rename onto a directory target fails, comes back as a correction,
    /// and leaves neither a temp file nor a changed directory behind.
    @Test func renameFailureWhenTargetIsADirectoryIsCorrectiveAndLeavesNoTempFiles() async throws {
        let root = TestSupport.makeTemporaryDirectory(named: "FilesWriteTests")
        let directoryTarget = root.appendingPathComponent("target-dir", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryTarget, withIntermediateDirectories: true)
        let context = FileContext(root: root)

        let result = try await Self.write(path: directoryTarget.path, content: "data\n", in: context)
        let message = try #require(result.correction)

        #expect(!message.isEmpty)
        #expect(TestSupport.temporaryFileLeftovers(in: root).isEmpty, "rename failure must remove the temporary file")
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: directoryTarget.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue, "the directory target must be untouched")
    }

    /// A staged write into a read-only directory fails, comes back as a
    /// correction, and leaves neither a temp file nor a target behind.
    @Test func writeFailureIntoAReadOnlyDirectoryIsCorrectiveAndLeavesNoTempFiles() async throws {
        let root = TestSupport.makeTemporaryDirectory(named: "FilesWriteTests")
        let readOnlyDirectory = root.appendingPathComponent("read-only", isDirectory: true)
        try FileManager.default.createDirectory(at: readOnlyDirectory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.posixPermissions: Self.readOnlyDirectoryMode], ofItemAtPath: readOnlyDirectory.path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: Self.writableDirectoryMode], ofItemAtPath: readOnlyDirectory.path)
        }
        let target = readOnlyDirectory.appendingPathComponent("blocked.txt", isDirectory: false)
        let context = FileContext(root: root)

        let result = try await Self.write(path: target.path, content: "data\n", in: context)
        let message = try #require(result.correction)

        #expect(!message.isEmpty)
        #expect(
            TestSupport.temporaryFileLeftovers(in: readOnlyDirectory).isEmpty,
            "write failure must remove the temporary file")
        #expect(!FileManager.default.fileExists(atPath: target.path), "a failed write must not create the target")
    }

    // MARK: Unicode and empty content

    /// Unicode content survives the write byte for byte.
    @Test func unicodeContentRoundTripsOnDisk() async throws {
        let root = TestSupport.makeTemporaryDirectory(named: "FilesWriteTests")
        let url = root.appendingPathComponent("unicode.txt", isDirectory: false)
        let text = "h\u{00E9}llo \u{1F30D}\n\u{0441}\u{0432}\u{0456}\u{0442}\n"
        let context = FileContext(root: root)

        let result = try await Self.write(path: url.path, content: text, in: context)

        #expect(result.correction == nil)
        #expect(try Self.readBytes(url.path) == Data(text.utf8))
        #expect(result.bytesWritten == Data(text.utf8).count)
    }

    /// Empty content writes an empty file with the empty-bytes token.
    @Test func emptyContentWritesAnEmptyFile() async throws {
        let root = TestSupport.makeTemporaryDirectory(named: "FilesWriteTests")
        let url = root.appendingPathComponent("empty.txt", isDirectory: false)
        let context = FileContext(root: root)

        let result = try await Self.write(path: url.path, content: "", in: context)

        #expect(result.correction == nil)
        #expect(try Self.readBytes(url.path).isEmpty)
        #expect(result.bytesWritten == 0)
        #expect(result.taggedContent.isEmpty)
        #expect(result.hash == Hashline.wholeFileHash(bytes: Data()))
    }

    // MARK: Permission preservation

    /// Overwriting an executable file keeps its permission bits.
    @Test func overwritingPreservesExecutablePermissionBits() async throws {
        let root = TestSupport.makeTemporaryDirectory(named: "FilesWriteTests")
        let url = root.appendingPathComponent("script.sh", isDirectory: false)
        try Data("#!/bin/sh\necho old\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: Self.executableFileMode], ofItemAtPath: url.path)
        let context = FileContext(root: root)

        let result = try await Self.write(path: url.path, content: "#!/bin/sh\necho new\n", in: context)

        #expect(result.correction == nil)
        #expect(
            TestSupport.permissionBits(url.path) == Self.executableFileMode,
            "overwriting a 0755 file must keep it 0755")
    }

    // MARK: Envelope fields

    /// `bytesWritten` counts UTF-8 bytes, not characters.
    @Test func envelopeBytesWrittenCountsUTF8Bytes() async throws {
        let root = TestSupport.makeTemporaryDirectory(named: "FilesWriteTests")
        let url = root.appendingPathComponent("bytes.txt", isDirectory: false)
        // A multi-byte scalar makes byte count differ from character count.
        let text = "a\u{1F30D}b"
        let context = FileContext(root: root)

        let result = try await Self.write(path: url.path, content: text, in: context)

        #expect(result.correction == nil)
        #expect(result.bytesWritten == Data(text.utf8).count)
        #expect(result.bytesWritten != text.count, "byte count must not be conflated with character count")
    }

    /// The write's `hash` equals a subsequent read's freshness token.
    @Test func envelopeHashEqualsASubsequentReadToken() async throws {
        let root = TestSupport.makeTemporaryDirectory(named: "FilesWriteTests")
        let url = root.appendingPathComponent("hash.txt", isDirectory: false)
        let text = "alpha\nbeta\ngamma\n"
        let context = FileContext(root: root)

        let writeResult = try await Self.write(path: url.path, content: text, in: context)
        #expect(writeResult.correction == nil)

        let readResult = try await Read(context: context)
            .call(arguments: ReadArguments(path: url.path, offset: nil, limit: nil, format: nil))

        #expect(writeResult.hash == readResult.hash)
        #expect(writeResult.hash == Hashline.wholeFileHash(bytes: Data(text.utf8)))
    }

    /// The write's `taggedContent` equals a subsequent read's hashline lines.
    @Test func envelopeTaggedContentEqualsSubsequentReadBackTagging() async throws {
        let root = TestSupport.makeTemporaryDirectory(named: "FilesWriteTests")
        let url = root.appendingPathComponent("tagged.txt", isDirectory: false)
        let text = "first line\nsecond line\nthird line\n"
        let context = FileContext(root: root)

        let writeResult = try await Self.write(path: url.path, content: text, in: context)
        #expect(writeResult.correction == nil)

        let readResult = try await Read(context: context)
            .call(arguments: ReadArguments(path: url.path, offset: nil, limit: nil, format: nil))

        #expect(writeResult.taggedContent == readResult.lines)
        #expect(writeResult.taggedContent.first?.hasPrefix("1:") == true)
    }

    // MARK: Corrective paths of this card

    /// A path outside the session root comes back as a correction and
    /// creates no file: the write stays bounded through the session's path
    /// guard.
    @Test func pathOutsideTheRootIsCorrective() async throws {
        let root = TestSupport.makeTemporaryDirectory(named: "FilesWriteTests")
        let outside = TestSupport.makeTemporaryDirectory(named: "FilesWriteTestsOutside")
        let outsidePath = outside.appendingPathComponent("escape.txt", isDirectory: false).path
        let context = FileContext(root: root)

        let result = try await Self.write(path: outsidePath, content: "data\n", in: context)
        let message = try #require(result.correction)

        #expect(!message.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: outsidePath), "a rejected write must not create the file")
    }

    /// A write on a read-only context comes back as a correction and creates
    /// no file: the context flag forbids the mutating verbs up front.
    @Test func readOnlyContextIsCorrective() async throws {
        let root = TestSupport.makeTemporaryDirectory(named: "FilesWriteTests")
        let path = root.appendingPathComponent("forbidden.txt", isDirectory: false).path
        let context = FileContext(root: root, readOnly: true)

        let result = try await Self.write(path: path, content: "data\n", in: context)
        let message = try #require(result.correction)

        #expect(!message.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: path), "a read-only context must not create the file")
    }

    // MARK: Change recording

    /// A write of a fresh file on a recording context records one add change
    /// carrying the new content.
    @Test func aRecordingContextRecordsAnAddChange() async throws {
        let root = TestSupport.makeTemporaryDirectory(named: "FilesWriteTests")
        let url = root.appendingPathComponent("added.txt", isDirectory: false)
        let context = FileContext(root: root, recordsChanges: true)

        let result = try await Self.write(path: url.path, content: "fresh\n", in: context)
        #expect(result.correction == nil)

        let changes = await context.changes.drain().changes
        let change = try #require(changes.first)
        #expect(changes.count == 1)
        #expect(change.kind == .add)
        #expect(change.path.hasSuffix("/added.txt"))
        #expect(change.oldContent == nil)
        #expect(change.newContent == "fresh\n")
    }

    /// An overwrite on a recording context records one modify change
    /// carrying the text on both sides.
    @Test func aRecordingContextRecordsAModifyChangeWithTheOldText() async throws {
        let root = TestSupport.makeTemporaryDirectory(named: "FilesWriteTests")
        let url = root.appendingPathComponent("modified.txt", isDirectory: false)
        try Data("old\n".utf8).write(to: url)
        let context = FileContext(root: root, recordsChanges: true)

        let result = try await Self.write(path: url.path, content: "new\n", in: context)
        #expect(result.correction == nil)

        let changes = await context.changes.drain().changes
        let change = try #require(changes.first)
        #expect(changes.count == 1)
        #expect(change.kind == .modify)
        #expect(change.oldContent == "old\n")
        #expect(change.newContent == "new\n")
    }

    /// A write on a non-recording context records nothing: the journal is
    /// disabled and the verb skips the capture work.
    @Test func aDisabledJournalRecordsNothing() async throws {
        let root = TestSupport.makeTemporaryDirectory(named: "FilesWriteTests")
        let url = root.appendingPathComponent("unrecorded.txt", isDirectory: false)
        let context = FileContext(root: root)

        let result = try await Self.write(path: url.path, content: "data\n", in: context)
        #expect(result.correction == nil)

        let changes = await context.changes.drain().changes
        #expect(changes.isEmpty)
    }
}
