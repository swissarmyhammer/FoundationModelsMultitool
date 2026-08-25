import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Unit tests for the ``AtomicWriter`` primitive.
///
/// This suite is a port of the sibling FileTool suite. It covers the reusable
/// capabilities of the writer: parent-directory creation for a deep target,
/// the staged multi-file commit, permission preservation, cleanup on a failed
/// stage, and the encoding and line-ending hooks the `edit file` operation
/// consumes. The operation-level behaviors arrive with the write verb of task
/// ^p238zzp and the edit verb of task ^v5xap97, which commits
/// ``EditEngine``'s content through this writer.
@Suite struct AtomicWriterTests {
    // MARK: Mode and byte constants

    /// The permission bits of an executable script (`rwxr-xr-x`).
    private static let executableFileMode = 0o755

    /// The permissions of a directory that the owner cannot write.
    private static let readOnlyDirectoryMode = 0o555

    /// The permissions that make a read-only directory removable again.
    private static let writableDirectoryMode = 0o755

    /// The UTF-8 byte-order mark bytes (`EF BB BF`).
    private static let utf8ByteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]

    /// Bytes that are not valid UTF-8, thus a decode must reject them.
    private static let invalidUTF8Bytes = Data([0xFF, 0xFE, 0x00, 0x01, 0xFF, 0x80])

    // MARK: Parent-directory creation

    @Test func writeCreatesMissingParentDirectories() throws {
        let root = TestSupport.makeTemporaryDirectory(named: "AtomicWriterTests")
        let target =
            root
            .appendingPathComponent("deep", isDirectory: true)
            .appendingPathComponent("nested", isDirectory: true)
            .appendingPathComponent("file.txt", isDirectory: false)

        try AtomicWriter.write(Data("content\n".utf8), to: target)

        #expect(try Data(contentsOf: target) == Data("content\n".utf8))
    }

    // MARK: Staged multi-file commit

    @Test func stageCreatesTempInDestinationDirectoryWithoutTouchingDestination() throws {
        let root = TestSupport.makeTemporaryDirectory(named: "AtomicWriterTests")
        let target = root.appendingPathComponent("file.txt")
        try Data("original\n".utf8).write(to: target)

        let staged = try AtomicWriter.stage(Data("staged\n".utf8), to: target)

        // The temp sits in the destination's own directory, not the destination.
        #expect(staged.temporaryURL.deletingLastPathComponent().path == root.path)
        #expect(FileManager.default.fileExists(atPath: staged.temporaryURL.path))
        #expect(staged.temporaryURL.path != target.path)
        // The destination is untouched until commit.
        #expect(try Data(contentsOf: target) == Data("original\n".utf8))

        staged.discard()
    }

    @Test func commitMakesDestinationEqualStagedData() throws {
        let root = TestSupport.makeTemporaryDirectory(named: "AtomicWriterTests")
        let target = root.appendingPathComponent("file.txt")

        let staged = try AtomicWriter.stage(Data("staged\n".utf8), to: target)
        // A fresh target has no permission bits to preserve.
        #expect(staged.permissionBits == nil)
        try staged.commit()

        #expect(try Data(contentsOf: target) == Data("staged\n".utf8))
        // The temp was renamed onto the destination, thus it no longer exists.
        #expect(!FileManager.default.fileExists(atPath: staged.temporaryURL.path))
    }

    @Test func discardRemovesTempAndLeavesDestinationUntouched() throws {
        let root = TestSupport.makeTemporaryDirectory(named: "AtomicWriterTests")
        let target = root.appendingPathComponent("file.txt")
        try Data("original\n".utf8).write(to: target)

        let staged = try AtomicWriter.stage(Data("staged\n".utf8), to: target)
        staged.discard()

        #expect(!FileManager.default.fileExists(atPath: staged.temporaryURL.path))
        #expect(try Data(contentsOf: target) == Data("original\n".utf8))
    }

    @Test func twoStagedWritesCommitIndependentlyLeavingUncommittedDestinationsUntouched() throws {
        let root = TestSupport.makeTemporaryDirectory(named: "AtomicWriterTests")
        let first = root.appendingPathComponent("first.txt")
        let second = root.appendingPathComponent("second.txt")
        try Data("first-original\n".utf8).write(to: first)
        try Data("second-original\n".utf8).write(to: second)

        let stagedFirst = try AtomicWriter.stage(Data("first-new\n".utf8), to: first)
        let stagedSecond = try AtomicWriter.stage(Data("second-new\n".utf8), to: second)

        // Neither destination changes while both are only staged.
        #expect(try Data(contentsOf: first) == Data("first-original\n".utf8))
        #expect(try Data(contentsOf: second) == Data("second-original\n".utf8))

        try stagedFirst.commit()
        // Committing the first leaves the second's destination untouched.
        #expect(try Data(contentsOf: first) == Data("first-new\n".utf8))
        #expect(try Data(contentsOf: second) == Data("second-original\n".utf8))

        try stagedSecond.commit()
        #expect(try Data(contentsOf: second) == Data("second-new\n".utf8))
    }

    @Test func discardAfterCommitIsANoOpThatDoesNotThrow() throws {
        let root = TestSupport.makeTemporaryDirectory(named: "AtomicWriterTests")
        let target = root.appendingPathComponent("file.txt")

        let staged = try AtomicWriter.stage(Data("staged\n".utf8), to: target)
        try staged.commit()
        // Idempotent: a discard after a commit, and a second discard, neither
        // throws nor disturbs the committed destination.
        staged.discard()
        staged.discard()

        #expect(try Data(contentsOf: target) == Data("staged\n".utf8))
    }

    @Test func stagePreservesPermissionBitsThroughCommit() throws {
        let root = TestSupport.makeTemporaryDirectory(named: "AtomicWriterTests")
        let target = root.appendingPathComponent("script.sh")
        try Data("#!/bin/sh\n".utf8).write(to: target)
        try FileManager.default.setAttributes(
            [.posixPermissions: Self.executableFileMode], ofItemAtPath: target.path)

        let staged = try AtomicWriter.stage(Data("#!/bin/sh\necho hi\n".utf8), to: target)
        // The staged value records the destination's bits, thus the staging
        // contract is visible before the commit.
        #expect(staged.permissionBits == mode_t(Self.executableFileMode))
        try staged.commit()

        #expect(
            TestSupport.permissionBits(target.path) == Self.executableFileMode,
            "staging over an executable file must keep its mode")
    }

    @Test func stageCleansUpTempWhenWriteFails() throws {
        let root = TestSupport.makeTemporaryDirectory(named: "AtomicWriterTests")
        let readOnlyDirectory = root.appendingPathComponent("readonly", isDirectory: true)
        try FileManager.default.createDirectory(at: readOnlyDirectory, withIntermediateDirectories: true)
        // A directory without write bits cannot receive a new temp file, thus
        // the staged write fails. The teardown restores the write bits, thus
        // the operating system can reclaim the tree.
        try FileManager.default.setAttributes(
            [.posixPermissions: Self.readOnlyDirectoryMode], ofItemAtPath: readOnlyDirectory.path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: Self.writableDirectoryMode], ofItemAtPath: readOnlyDirectory.path)
        }

        let target = readOnlyDirectory.appendingPathComponent("file.txt")
        #expect(throws: (any Error).self) {
            try AtomicWriter.stage(Data("data\n".utf8), to: target)
        }

        // No temporary file stays behind in the read-only directory.
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: readOnlyDirectory.path)
        #expect(leftovers.isEmpty, "a failed stage must leave no temp file behind, found: \(leftovers)")
    }

    // MARK: Line-ending detection

    @Test func detectsLineFeedEndings() {
        #expect(AtomicWriter.detectLineEnding(in: "a\nb\nc\n") == .lineFeed)
    }

    @Test func detectsCarriageReturnLineFeedEndings() {
        #expect(AtomicWriter.detectLineEnding(in: "a\r\nb\r\n") == .carriageReturnLineFeed)
    }

    @Test func detectsCarriageReturnEndings() {
        #expect(AtomicWriter.detectLineEnding(in: "a\rb\r") == .carriageReturn)
    }

    @Test func detectsMixedEndings() {
        #expect(AtomicWriter.detectLineEnding(in: "a\r\nb\nc\r") == .mixed)
    }

    @Test func detectsNoEndingsWhenUnterminated() {
        #expect(AtomicWriter.detectLineEnding(in: "no terminator") == nil)
    }

    // MARK: Encoding detection and re-encode

    @Test func decodesPlainUTF8() throws {
        let decoded = try #require(AtomicWriter.decode(Data("hello\n".utf8)))
        #expect(decoded.encoding == .utf8)
        #expect(decoded.text == "hello\n")
    }

    @Test func decodesUTF8WithByteOrderMarkStrippingTheMark() throws {
        var bytes = Data(Self.utf8ByteOrderMark)
        bytes.append(Data("hello\n".utf8))
        let decoded = try #require(AtomicWriter.decode(bytes))

        #expect(decoded.encoding == .utf8WithByteOrderMark)
        #expect(decoded.text == "hello\n", "the byte-order mark must be stripped from the decoded text")
    }

    @Test func rejectsUndecodableBytes() {
        #expect(AtomicWriter.decode(Self.invalidUTF8Bytes) == nil)
    }

    @Test func plainUTF8RoundTripsThroughEncode() throws {
        let original = Data("re-encoded\n".utf8)
        let decoded = try #require(AtomicWriter.decode(original))
        #expect(AtomicWriter.encode(decoded.text, as: decoded.encoding) == original)
    }

    @Test func byteOrderMarkedUTF8RoundTripsThroughEncode() throws {
        var original = Data(Self.utf8ByteOrderMark)
        original.append(Data("re-encoded\n".utf8))
        let decoded = try #require(AtomicWriter.decode(original))
        #expect(AtomicWriter.encode(decoded.text, as: decoded.encoding) == original)
    }

    // MARK: Best-effort decoded read

    @Test func decodedTextReturnsTheTextOfAUTF8File() throws {
        let root = TestSupport.makeTemporaryDirectory(named: "AtomicWriterTests")
        let target = root.appendingPathComponent("file.txt")
        try Data("captured\n".utf8).write(to: target)

        #expect(AtomicWriter.decodedText(at: target) == "captured\n")
    }

    @Test func decodedTextReturnsNilForAMissingFile() {
        let root = TestSupport.makeTemporaryDirectory(named: "AtomicWriterTests")
        let target = root.appendingPathComponent("absent.txt")

        #expect(AtomicWriter.decodedText(at: target) == nil)
    }

    @Test func decodedTextReturnsNilForUndecodableBytes() throws {
        let root = TestSupport.makeTemporaryDirectory(named: "AtomicWriterTests")
        let target = root.appendingPathComponent("binary.bin")
        try Self.invalidUTF8Bytes.write(to: target)

        #expect(AtomicWriter.decodedText(at: target) == nil)
    }
}
