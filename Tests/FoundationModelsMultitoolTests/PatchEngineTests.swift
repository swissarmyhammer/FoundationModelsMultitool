import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Behavioral tests for the ``PatchEngine`` two-phase multi-file patch applier.
///
/// This suite is a port of the sibling FileTool suite
/// (`../FoundationModelsFileTool/Tests/FileToolTests/PatchEngineTests.swift`).
/// Each acceptance criterion from the PatchEngine card runs through the real
/// engine against files in a fresh temporary directory: a combined
/// add+update+delete+move patch that lands all four in one call; an unresolved
/// update that aborts the whole patch byte-identical; the phase-1 correctives
/// (add-onto-existing, delete of a missing file, a binary update target);
/// per-file encoding and line-ending preservation; a phase-2 stage failure that
/// leaves every destination untouched with no temporary files behind; a pure
/// rename that moves byte-identical content; and the cross-file conflict rules
/// (move-destination collisions and same-final-path duplicates abort, while
/// legal swaps and rotations pass).
@Suite struct PatchEngineTests {
    // MARK: Constants

    /// The permissions of a directory that the owner cannot write.
    private static let readOnlyDirectoryMode = 0o555

    /// The permissions that make a read-only directory writable again.
    private static let writableDirectoryMode = 0o755

    /// The permissions of a file the owner can write and cannot read.
    private static let writeOnlyFilePermissions = 0o200

    /// The permissions that make a write-only file readable again.
    private static let readWriteFilePermissions = 0o600

    // MARK: Fixture

    /// A fresh temporary directory and a guard rooted at it.
    ///
    /// - Returns: the temporary root URL and a ``PathGuard`` bounded to it.
    private static func makeFixture() -> (root: URL, pathGuard: PathGuard) {
        let root = TestSupport.makeTemporaryDirectory(named: "PatchEngineTests")
        return (root, PathGuard(root: root, workspaceRoot: root))
    }

    /// Seed a file with `data` at `name` inside `root`.
    ///
    /// - Parameters:
    ///   - data: the bytes to write.
    ///   - name: the file name within `root`.
    ///   - root: the directory to seed within.
    /// - Returns: the seeded file's absolute path.
    @discardableResult
    private static func seed(_ data: Data, named name: String, in root: URL) throws -> String {
        let url = root.appendingPathComponent(name, isDirectory: false)
        try data.write(to: url)
        return url.path
    }

    /// The raw on-disk bytes of a file, or `nil` when it does not exist.
    ///
    /// - Parameter path: the absolute path to read.
    /// - Returns: the file's bytes, or `nil`.
    private static func bytes(_ path: String) -> Data? {
        try? Data(contentsOf: URL(fileURLWithPath: path))
    }

    /// Whether a file exists on disk.
    ///
    /// - Parameter path: the absolute path to test.
    /// - Returns: `true` when a file exists at the path.
    private static func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    /// The outcome whose reported path ends with `suffix`.
    ///
    /// - Parameters:
    ///   - outcomes: the outcomes to search.
    ///   - suffix: the path suffix that identifies the wanted outcome.
    /// - Returns: the first matching outcome, or `nil` when none matches.
    private static func outcome(
        in outcomes: [PatchEngine.FileOutcome],
        endingWith suffix: String
    ) -> PatchEngine.FileOutcome? {
        outcomes.first { $0.path.hasSuffix(suffix) }
    }

    // MARK: Combined patch

    @Test func combinedPatchAppliesAddUpdateDeleteAndMove() throws {
        let (root, pathGuard) = Self.makeFixture()
        try Self.seed(Data("one\ntwo\nthree\n".utf8), named: "update.txt", in: root)
        try Self.seed(Data("obsolete\n".utf8), named: "delete.txt", in: root)
        try Self.seed(Data("keep me\n".utf8), named: "source.txt", in: root)

        let hunks: [PatchParser.Hunk] = [
            .addFile(path: TestSupport.path("added.txt", in: root), contents: "added\n"),
            .updateFile(
                path: TestSupport.path("update.txt", in: root), movePath: nil, pairs: [(find: "two", replace: "TWO")]),
            .deleteFile(path: TestSupport.path("delete.txt", in: root)),
            .updateFile(
                path: TestSupport.path("source.txt", in: root), movePath: TestSupport.path("dest.txt", in: root),
                pairs: []),
        ]

        let outcomes = try Self.apply(hunks, using: pathGuard)

        // Add
        #expect(Self.bytes(TestSupport.path("added.txt", in: root)) == Data("added\n".utf8))
        let add = try #require(Self.outcome(in: outcomes, endingWith: "added.txt"))
        #expect(add.action == .added)
        #expect(add.appliedPairs == 0)
        #expect(add.bytesWritten == Data("added\n".utf8).count)
        #expect(add.hash == Hashline.wholeFileHash(bytes: Data("added\n".utf8)))

        // Update
        #expect(Self.bytes(TestSupport.path("update.txt", in: root)) == Data("one\nTWO\nthree\n".utf8))
        let update = try #require(Self.outcome(in: outcomes, endingWith: "update.txt"))
        #expect(update.action == .modified)
        #expect(update.appliedPairs == 1)
        #expect(update.hash == Hashline.wholeFileHash(bytes: Data("one\nTWO\nthree\n".utf8)))

        // Delete
        #expect(!Self.exists(TestSupport.path("delete.txt", in: root)))
        let delete = try #require(Self.outcome(in: outcomes, endingWith: "delete.txt"))
        #expect(delete.action == .deleted)
        #expect(delete.bytesWritten == nil)
        #expect(delete.hash == nil)

        // Move
        #expect(!Self.exists(TestSupport.path("source.txt", in: root)))
        #expect(Self.bytes(TestSupport.path("dest.txt", in: root)) == Data("keep me\n".utf8))
        let move = try #require(Self.outcome(in: outcomes, endingWith: "source.txt"))
        #expect(move.action == .moved)
        #expect(move.movedTo?.hasSuffix("dest.txt") == true)
        #expect(move.hash == Hashline.wholeFileHash(bytes: Data("keep me\n".utf8)))

        #expect(TestSupport.temporaryFileLeftovers(in: root).isEmpty)
    }

    // MARK: Abort-all on an unresolved update

    @Test func unresolvedUpdateAbortsEntirePatchLeavingFilesByteIdentical() throws {
        let (root, pathGuard) = Self.makeFixture()
        let updateBytes = Data("alpha\nbeta\n".utf8)
        let editBytes = Data("gamma\ndelta\n".utf8)
        try Self.seed(updateBytes, named: "will-edit.txt", in: root)
        try Self.seed(editBytes, named: "no-match.txt", in: root)

        let hunks: [PatchParser.Hunk] = [
            .addFile(path: TestSupport.path("new.txt", in: root), contents: "new\n"),
            .updateFile(
                path: TestSupport.path("will-edit.txt", in: root), movePath: nil,
                pairs: [(find: "beta", replace: "BETA")]),
            .updateFile(
                path: TestSupport.path("no-match.txt", in: root),
                movePath: nil,
                pairs: [(find: "nowhere-to-be-found", replace: "x")]
            ),
        ]

        let failure = Self.failure(PatchEngine.apply(hunks, using: pathGuard))
        guard case .unresolved(let path, _, let resolution) = failure else {
            Issue.record("expected .unresolved, got \(failure)")
            return
        }
        #expect(path.hasSuffix("no-match.txt"))
        if case .noMatch = resolution {} else { Issue.record("expected .noMatch resolution, got \(resolution)") }

        // Every file byte-identical; nothing added.
        #expect(Self.bytes(TestSupport.path("will-edit.txt", in: root)) == updateBytes)
        #expect(Self.bytes(TestSupport.path("no-match.txt", in: root)) == editBytes)
        #expect(!Self.exists(TestSupport.path("new.txt", in: root)))
        #expect(TestSupport.temporaryFileLeftovers(in: root).isEmpty)
    }

    // MARK: Phase-1 correctives

    @Test func addTargetingExistingFileAborts() throws {
        let (root, pathGuard) = Self.makeFixture()
        let existingBytes = Data("already here\n".utf8)
        try Self.seed(existingBytes, named: "exists.txt", in: root)
        try Self.seed(Data("victim\n".utf8), named: "other.txt", in: root)

        let hunks: [PatchParser.Hunk] = [
            .deleteFile(path: TestSupport.path("other.txt", in: root)),
            .addFile(path: TestSupport.path("exists.txt", in: root), contents: "clobber\n"),
        ]

        let failure = Self.failure(PatchEngine.apply(hunks, using: pathGuard))
        guard case .corrective = failure else {
            Issue.record("expected .corrective, got \(failure)")
            return
        }
        // Nothing was touched: the existing file is intact and the delete did not happen.
        #expect(Self.bytes(TestSupport.path("exists.txt", in: root)) == existingBytes)
        #expect(Self.exists(TestSupport.path("other.txt", in: root)))
    }

    @Test func deleteOfNonexistentFileAborts() throws {
        let (root, pathGuard) = Self.makeFixture()
        let hunks: [PatchParser.Hunk] = [.deleteFile(path: TestSupport.path("ghost.txt", in: root))]
        guard case .corrective = Self.failure(PatchEngine.apply(hunks, using: pathGuard)) else {
            Issue.record("expected .corrective for a missing delete target")
            return
        }
    }

    @Test func binaryUpdateTargetAborts() throws {
        // Canonicalized so the corrective's reported (resolved) path, which
        // `PathGuard` derives via `realpath`, matches the path this test builds
        // from `root` byte-for-byte — see `TestSupport.canonicalDirectory`.
        let root = TestSupport.canonicalDirectory(TestSupport.makeTemporaryDirectory(named: "PatchEngineTests"))
        let pathGuard = PathGuard(root: root, workspaceRoot: root)
        let binary = Data([0xFF, 0xFE, 0x00, 0x01, 0x80])
        let path = try Self.seed(binary, named: "image.bin", in: root)
        let hunks: [PatchParser.Hunk] = [
            .updateFile(path: path, movePath: nil, pairs: [(find: "a", replace: "b")])
        ]
        guard case .corrective(let message, _) = Self.failure(PatchEngine.apply(hunks, using: pathGuard)) else {
            Issue.record("expected .corrective for a binary update target")
            return
        }
        // Pinned byte-identical: patch-specific wording composed through the
        // shared `PathCorrective.pathErrorMessage(description:path:)` builder.
        #expect(
            message
                == "The file is not valid UTF-8 text and appears to be binary, so it cannot be patched as text: \(path)"
        )
        #expect(Self.bytes(path) == binary)
    }

    @Test func unreadableUpdateSourceAborts() throws {
        // Canonicalized for the same reason as `binaryUpdateTargetAborts`: the
        // corrective reports `PathGuard`'s resolved path.
        let root = TestSupport.canonicalDirectory(TestSupport.makeTemporaryDirectory(named: "PatchEngineTests"))
        let pathGuard = PathGuard(root: root, workspaceRoot: root)
        let path = try Self.seed(Data("content\n".utf8), named: "noread.txt", in: root)
        // `.edit` permission only requires the file to exist and not be
        // read-only, so a write-only file passes path validation but fails the
        // actual `Data(contentsOf:)` read inside `decodeSource`, exercising the
        // same unreadable-file corrective `read file`/`edit file` share via
        // `PathCorrective`.
        try FileManager.default.setAttributes(
            [.posixPermissions: Self.writeOnlyFilePermissions], ofItemAtPath: path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: Self.readWriteFilePermissions], ofItemAtPath: path)
        }

        let hunks: [PatchParser.Hunk] = [
            .updateFile(path: path, movePath: nil, pairs: [(find: "content", replace: "CONTENT")])
        ]
        guard case .corrective(let message, _) = Self.failure(PatchEngine.apply(hunks, using: pathGuard)) else {
            Issue.record("expected .corrective for an unreadable update source")
            return
        }
        // Pinned byte-identical to `PathCorrective.unreadableDescription`'s
        // rendered message, since `PatchEngine` composes it rather than
        // defining its own copy.
        #expect(message == "The file could not be read: \(path)")
    }

    // MARK: Encoding / line-ending preservation

    @Test func updatePreservesEncodingAndLineEndingsPerFile() throws {
        let (root, pathGuard) = Self.makeFixture()
        let byteOrderMark = Data([0xEF, 0xBB, 0xBF])
        let crlfOriginal = byteOrderMark + Data("alpha\r\nbeta\r\ngamma\r\n".utf8)
        let lfOriginal = Data("one\ntwo\nthree\n".utf8)
        try Self.seed(crlfOriginal, named: "crlf.txt", in: root)
        try Self.seed(lfOriginal, named: "lf.txt", in: root)

        let hunks: [PatchParser.Hunk] = [
            .updateFile(
                path: TestSupport.path("crlf.txt", in: root), movePath: nil, pairs: [(find: "beta", replace: "BETA")]),
            .updateFile(
                path: TestSupport.path("lf.txt", in: root), movePath: nil, pairs: [(find: "two", replace: "TWO")]),
        ]

        _ = try Self.apply(hunks, using: pathGuard)

        #expect(
            Self.bytes(TestSupport.path("crlf.txt", in: root)) == byteOrderMark
                + Data("alpha\r\nBETA\r\ngamma\r\n".utf8))
        #expect(Self.bytes(TestSupport.path("lf.txt", in: root)) == Data("one\nTWO\nthree\n".utf8))
    }

    // MARK: Phase-2 stage failure

    @Test func stageFailureLeavesDestinationsUntouchedAndNoTempFiles() throws {
        let (root, pathGuard) = Self.makeFixture()
        let lockedDirectory = root.appendingPathComponent("locked", isDirectory: true)
        try FileManager.default.createDirectory(at: lockedDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: Self.writableDirectoryMode], ofItemAtPath: lockedDirectory.path)
        }

        let hunks: [PatchParser.Hunk] = [
            .addFile(path: TestSupport.path("a.txt", in: root), contents: "a\n"),
            .addFile(path: TestSupport.path("b.txt", in: root), contents: "b\n"),
            .addFile(path: lockedDirectory.appendingPathComponent("c.txt").path, contents: "c\n"),
        ]

        // The parent directory exists (so the path validates) but is not writable,
        // so staging the third write fails after the first two have staged.
        try FileManager.default.setAttributes(
            [.posixPermissions: Self.readOnlyDirectoryMode], ofItemAtPath: lockedDirectory.path)

        let failure = Self.failure(PatchEngine.apply(hunks, using: pathGuard))
        guard case .corrective = failure else {
            Issue.record("expected .corrective for an unwritable stage target")
            return
        }

        #expect(!Self.exists(TestSupport.path("a.txt", in: root)))
        #expect(!Self.exists(TestSupport.path("b.txt", in: root)))
        #expect(!Self.exists(lockedDirectory.appendingPathComponent("c.txt").path))
        #expect(TestSupport.temporaryFileLeftovers(in: root).isEmpty)
        #expect(TestSupport.temporaryFileLeftovers(in: lockedDirectory).isEmpty)
        // Staging aborts before any commit, so there is nothing landed to report.
        #expect(failure.committedOutcomes.isEmpty)
    }

    // MARK: Phase-2 removal failure

    @Test func deleteWhoseUnlinkFailsAbortsRatherThanReportingAFalseDeletion() throws {
        let (root, pathGuard) = Self.makeFixture()
        let stillHere = Data("still here\n".utf8)
        let doomed = try Self.seed(stillHere, named: "immutable.txt", in: root)

        // Lock the file so `.delete` validation passes in phase 1 (the parent
        // stays writable) but the phase-2 unlink is denied.
        #expect(TestSupport.setImmutable(doomed, to: true))
        defer { TestSupport.setImmutable(doomed, to: false) }

        let hunks: [PatchParser.Hunk] = [.deleteFile(path: doomed)]
        let failure = Self.failure(PatchEngine.apply(hunks, using: pathGuard))
        guard case .corrective = failure else {
            Issue.record("expected .corrective when a delete target cannot be unlinked")
            return
        }
        // The unlink failure was surfaced, not swallowed behind a `.deleted`
        // outcome: the file is still on disk and no false success was reported.
        #expect(Self.bytes(doomed) == stillHere)
        // This patch has no writes, so nothing at all landed.
        #expect(failure.committedOutcomes.isEmpty)
    }

    @Test func moveWhoseSourceUnlinkFailsAbortsRatherThanReportingAFalseMove() throws {
        let (root, pathGuard) = Self.makeFixture()
        let payload = Data("payload\n".utf8)
        let source = try Self.seed(payload, named: "locked-source.txt", in: root)
        let destination = TestSupport.path("moved-dest.txt", in: root)

        // Lock the source so `.edit` validation and the decode both pass, but
        // the post-commit unlink of the move source is denied.
        #expect(TestSupport.setImmutable(source, to: true))
        defer { TestSupport.setImmutable(source, to: false) }

        let hunks: [PatchParser.Hunk] = [
            .updateFile(path: source, movePath: destination, pairs: [])
        ]
        guard case .failure(.corrective) = PatchEngine.apply(hunks, using: pathGuard) else {
            Issue.record("expected .corrective when a move source cannot be unlinked")
            return
        }
        // Removals run after commits, so the destination was written — but the
        // source still exists, so the engine must not have claimed a completed
        // move; it reports the failure instead.
        #expect(Self.bytes(source) == payload)
        #expect(Self.bytes(destination) == payload)
    }

    // MARK: Post-commit failure reporting

    @Test func commitFailurePartwayCarriesTheOutcomesThatCommitted() throws {
        let (root, pathGuard) = Self.makeFixture()
        let first = try Self.seed(Data("first\n".utf8), named: "first.txt", in: root)
        let locked = try Self.seed(Data("locked\n".utf8), named: "locked.txt", in: root)

        // A staged write commits by renaming onto its destination, and a rename
        // onto an immutable file is denied — so the second section's commit
        // fails once the first section's has already landed.
        #expect(TestSupport.setImmutable(locked, to: true))
        defer { TestSupport.setImmutable(locked, to: false) }

        let hunks: [PatchParser.Hunk] = [
            .updateFile(path: first, movePath: nil, pairs: [(find: "first", replace: "FIRST")]),
            .updateFile(path: locked, movePath: nil, pairs: [(find: "locked", replace: "LOCKED")]),
        ]
        let failure = Self.failure(
            PatchEngine.apply(hunks, using: pathGuard, capturingContent: true))

        #expect(Self.bytes(first) == Data("FIRST\n".utf8))
        #expect(Self.bytes(locked) == Data("locked\n".utf8))
        #expect(failure.committedOutcomes.count == 1)
        let landed = try #require(failure.committedOutcomes.first)
        #expect(landed.path.hasSuffix("first.txt"))
        #expect(landed.action == .modified)
        #expect(landed.oldContent == "first\n")
        #expect(landed.newContent == "FIRST\n")
    }

    @Test func strandedMoveIsReportedAtItsDestinationRatherThanAsACompletedMove() throws {
        let (root, pathGuard) = Self.makeFixture()
        let payload = Data("payload\n".utf8)
        let source = try Self.seed(payload, named: "locked-source.txt", in: root)
        let destination = TestSupport.path("moved-dest.txt", in: root)

        #expect(TestSupport.setImmutable(source, to: true))
        defer { TestSupport.setImmutable(source, to: false) }

        let hunks: [PatchParser.Hunk] = [
            .updateFile(path: source, movePath: destination, pairs: [])
        ]
        let failure = Self.failure(
            PatchEngine.apply(hunks, using: pathGuard, capturingContent: true))

        // The rename never completed — the source is still on disk — so what
        // landed is a new file at the destination, and that is what is reported.
        #expect(Self.bytes(source) == payload)
        #expect(Self.bytes(destination) == payload)
        let landed = try #require(failure.committedOutcomes.first)
        #expect(failure.committedOutcomes.count == 1)
        #expect(landed.path.hasSuffix("moved-dest.txt"))
        #expect(landed.action == .added)
        #expect(landed.movedTo == nil)
        #expect(landed.oldContent == nil)
        #expect(landed.newContent == "payload\n")
        // The bytes the write produced are reported the same way a completed
        // change reports them — only where the change is named differs.
        #expect(landed.bytesWritten == payload.count)
        #expect(landed.hash == Hashline.wholeFileHash(bytes: payload))
    }

    @Test func strandedMoveOntoAnExistingFileIsReportedAsAModification() throws {
        let (root, pathGuard) = Self.makeFixture()
        let source = try Self.seed(Data("payload\n".utf8), named: "locked-source.txt", in: root)
        let destination = try Self.seed(Data("previous\n".utf8), named: "occupied.txt", in: root)

        #expect(TestSupport.setImmutable(source, to: true))
        defer { TestSupport.setImmutable(source, to: false) }

        // The move carries an edit, so the pair count is a value the outcome
        // has to report rather than the `0` a pure rename would report anyway.
        let hunks: [PatchParser.Hunk] = [
            .updateFile(path: source, movePath: destination, pairs: [(find: "payload", replace: "PAYLOAD")])
        ]
        let failure = Self.failure(
            PatchEngine.apply(hunks, using: pathGuard, capturingContent: true))

        // The move overwrote a file that was already there, so the stranded
        // rename is that file's modification, not a creation.
        #expect(Self.bytes(source) == Data("payload\n".utf8))
        #expect(Self.bytes(destination) == Data("PAYLOAD\n".utf8))
        let landed = try #require(failure.committedOutcomes.first)
        #expect(landed.path.hasSuffix("occupied.txt"))
        #expect(landed.action == .modified)
        #expect(landed.appliedPairs == 1)
        #expect(landed.oldContent == "previous\n")
        #expect(landed.newContent == "PAYLOAD\n")
    }

    @Test func aCompletedMoveOntoAnExistingFileReportsTheOverwrittenDestination() throws {
        let (root, pathGuard) = Self.makeFixture()
        let source = try Self.seed(Data("keep me\n".utf8), named: "source.txt", in: root)
        let destination = try Self.seed(Data("clobbered\n".utf8), named: "dest.txt", in: root)

        let hunks: [PatchParser.Hunk] = [
            .updateFile(path: source, movePath: destination, pairs: [])
        ]
        let outcomes = try Self.apply(hunks, using: pathGuard, capturingContent: true)

        // The move completed — the source is gone — so the outcome describes a
        // real rename, but the destination it landed on held a different file a
        // moment ago; that file's prior text has to survive somewhere on the
        // outcome, not be discarded once the rename succeeds.
        #expect(!Self.exists(source))
        #expect(Self.bytes(destination) == Data("keep me\n".utf8))
        let landed = try #require(outcomes.first)
        #expect(landed.action == .moved)
        #expect(landed.movedTo?.hasSuffix("dest.txt") == true)
        #expect(landed.oldContent == "keep me\n")
        #expect(landed.overwrittenDestination?.content == "clobbered\n")
    }

    @Test func aCompletedMoveOntoANewDestinationReportsNoOverwrittenDestination() throws {
        let (root, pathGuard) = Self.makeFixture()
        let source = try Self.seed(Data("keep me\n".utf8), named: "source.txt", in: root)
        let destination = TestSupport.path("dest.txt", in: root)

        let hunks: [PatchParser.Hunk] = [
            .updateFile(path: source, movePath: destination, pairs: [])
        ]
        let outcomes = try Self.apply(hunks, using: pathGuard, capturingContent: true)

        let landed = try #require(outcomes.first)
        #expect(landed.action == .moved)
        #expect(landed.overwrittenDestination == nil)
    }

    @Test func aSwapReportsNoOverwrittenDestinationForEitherFile() throws {
        // Each hunk's destination necessarily pre-exists — that is what makes
        // it a swap — but neither file's prior content is actually destroyed:
        // it is relocated by the peer hunk within this same atomic patch.
        let (root, pathGuard) = Self.makeFixture()
        let alphaBytes = Data("alpha\n".utf8)
        let betaBytes = Data("beta\n".utf8)
        try Self.seed(alphaBytes, named: "alpha.txt", in: root)
        try Self.seed(betaBytes, named: "beta.txt", in: root)

        let hunks: [PatchParser.Hunk] = [
            .updateFile(
                path: TestSupport.path("alpha.txt", in: root), movePath: TestSupport.path("beta.txt", in: root),
                pairs: []),
            .updateFile(
                path: TestSupport.path("beta.txt", in: root), movePath: TestSupport.path("alpha.txt", in: root),
                pairs: []),
        ]
        let outcomes = try Self.apply(hunks, using: pathGuard, capturingContent: true)

        #expect(outcomes.count == 2)
        #expect(outcomes.allSatisfy { $0.overwrittenDestination == nil })
    }

    @Test func removalFailureStillReportsAMoveWhoseSourceWasAlreadyUnlinked() throws {
        let (root, pathGuard) = Self.makeFixture()
        let moverBytes = Data("mover\n".utf8)
        let mover = try Self.seed(moverBytes, named: "mover.txt", in: root)
        let renamed = TestSupport.path("renamed.txt", in: root)
        let doomed = try Self.seed(Data("obsolete\n".utf8), named: "doomed.txt", in: root)

        // Move sources are unlinked before delete targets, so the rename
        // completes and only the delete fails.
        #expect(TestSupport.setImmutable(doomed, to: true))
        defer { TestSupport.setImmutable(doomed, to: false) }

        let hunks: [PatchParser.Hunk] = [
            .updateFile(path: mover, movePath: renamed, pairs: []),
            .deleteFile(path: doomed),
        ]
        let failure = Self.failure(
            PatchEngine.apply(hunks, using: pathGuard, capturingContent: true))

        #expect(!Self.exists(mover))
        #expect(Self.bytes(renamed) == moverBytes)
        #expect(failure.committedOutcomes.count == 1)
        let landed = try #require(failure.committedOutcomes.first)
        #expect(landed.path.hasSuffix("mover.txt"))
        #expect(landed.action == .moved)
        #expect(landed.movedTo?.hasSuffix("renamed.txt") == true)
    }

    @Test func aFailedRemovalIsNotCreditedByAPeerSectionRemovingTheSamePath() throws {
        let (root, pathGuard) = Self.makeFixture()
        let payload = Data("payload\n".utf8)
        let source = try Self.seed(payload, named: "aliased.txt", in: root)
        let destination = TestSupport.path("renamed.txt", in: root)
        // The same file spelled two ways. `PatchParser` dedups sections on the
        // raw path string while ``PathGuard`` canonicalizes, so both sections
        // reach the engine as distinct changes removing one file: the move
        // unlinks it, and the delete's own unlink then fails with ENOENT.
        let alias = "\(root.path)/./aliased.txt"

        let hunks: [PatchParser.Hunk] = [
            .updateFile(path: source, movePath: destination, pairs: []),
            .deleteFile(path: alias),
        ]
        let failure = Self.failure(
            PatchEngine.apply(hunks, using: pathGuard, capturingContent: true))

        // Only the move landed. Crediting the delete with the move's removal
        // would report the same file as both renamed and deleted.
        #expect(failure.committedOutcomes.count == 1)
        #expect(failure.committedOutcomes.allSatisfy { $0.action == .moved })
        #expect(Self.bytes(destination) == payload)
        #expect(!Self.exists(source))
    }

    // MARK: Pure rename

    @Test func pureRenameMovesFileWithByteIdenticalContent() throws {
        let (root, pathGuard) = Self.makeFixture()
        let original = Data([0xEF, 0xBB, 0xBF]) + Data("keep\r\nthese\r\nbytes\r\n".utf8)
        try Self.seed(original, named: "before.txt", in: root)

        let hunks: [PatchParser.Hunk] = [
            .updateFile(
                path: TestSupport.path("before.txt", in: root), movePath: TestSupport.path("after.txt", in: root),
                pairs: [])
        ]
        let outcomes = try Self.apply(hunks, using: pathGuard)

        #expect(!Self.exists(TestSupport.path("before.txt", in: root)))
        #expect(Self.bytes(TestSupport.path("after.txt", in: root)) == original)
        let move = try #require(outcomes.first)
        #expect(move.action == .moved)
        #expect(move.appliedPairs == 0)
    }

    // MARK: Cross-file conflicts

    @Test func moveDestinationCollidingWithAddAborts() throws {
        let (root, pathGuard) = Self.makeFixture()
        try Self.seed(Data("payload\n".utf8), named: "src.txt", in: root)

        let hunks: [PatchParser.Hunk] = [
            .updateFile(
                path: TestSupport.path("src.txt", in: root), movePath: TestSupport.path("collide.txt", in: root),
                pairs: []),
            .addFile(path: TestSupport.path("collide.txt", in: root), contents: "new\n"),
        ]
        guard case .corrective = Self.failure(PatchEngine.apply(hunks, using: pathGuard)) else {
            Issue.record("expected .corrective for a move-destination/add collision")
            return
        }
        // No write happened: the source is intact and the collision target absent.
        #expect(Self.exists(TestSupport.path("src.txt", in: root)))
        #expect(!Self.exists(TestSupport.path("collide.txt", in: root)))
    }

    @Test func twoMovesToSameDestinationAbort() throws {
        let (root, pathGuard) = Self.makeFixture()
        try Self.seed(Data("first\n".utf8), named: "one.txt", in: root)
        try Self.seed(Data("second\n".utf8), named: "two.txt", in: root)

        let hunks: [PatchParser.Hunk] = [
            .updateFile(
                path: TestSupport.path("one.txt", in: root), movePath: TestSupport.path("merged.txt", in: root),
                pairs: []),
            .updateFile(
                path: TestSupport.path("two.txt", in: root), movePath: TestSupport.path("merged.txt", in: root),
                pairs: []),
        ]
        guard case .corrective = Self.failure(PatchEngine.apply(hunks, using: pathGuard)) else {
            Issue.record("expected .corrective for two moves to the same destination")
            return
        }
        #expect(Self.exists(TestSupport.path("one.txt", in: root)))
        #expect(Self.exists(TestSupport.path("two.txt", in: root)))
    }

    @Test func deleteAndMoveToSamePathAborts() throws {
        let (root, pathGuard) = Self.makeFixture()
        try Self.seed(Data("mover\n".utf8), named: "a.txt", in: root)
        try Self.seed(Data("doomed\n".utf8), named: "b.txt", in: root)

        let hunks: [PatchParser.Hunk] = [
            .updateFile(
                path: TestSupport.path("a.txt", in: root), movePath: TestSupport.path("b.txt", in: root), pairs: []),
            .deleteFile(path: TestSupport.path("b.txt", in: root)),
        ]
        guard case .corrective = Self.failure(PatchEngine.apply(hunks, using: pathGuard)) else {
            Issue.record("expected .corrective when a move destination is also deleted")
            return
        }
    }

    @Test func swapOfTwoFilesIsAllowed() throws {
        let (root, pathGuard) = Self.makeFixture()
        let alphaBytes = Data("alpha\n".utf8)
        let betaBytes = Data("beta\n".utf8)
        try Self.seed(alphaBytes, named: "alpha.txt", in: root)
        try Self.seed(betaBytes, named: "beta.txt", in: root)

        // A filename swap: each section renames onto the other's path. Distinct
        // final paths, so the patch is legal and content is swapped.
        let hunks: [PatchParser.Hunk] = [
            .updateFile(
                path: TestSupport.path("alpha.txt", in: root), movePath: TestSupport.path("beta.txt", in: root),
                pairs: []),
            .updateFile(
                path: TestSupport.path("beta.txt", in: root), movePath: TestSupport.path("alpha.txt", in: root),
                pairs: []),
        ]
        let outcomes = try Self.apply(hunks, using: pathGuard, capturingContent: true)

        #expect(Self.bytes(TestSupport.path("alpha.txt", in: root)) == betaBytes)
        #expect(Self.bytes(TestSupport.path("beta.txt", in: root)) == alphaBytes)
        #expect(TestSupport.temporaryFileLeftovers(in: root).isEmpty)
        // Neither source is unlinked — each is a peer's write destination — yet
        // both renames completed, so both are reported as moves with their text.
        #expect(outcomes.count == 2)
        #expect(outcomes.allSatisfy { $0.action == .moved })
        let alpha = try #require(Self.outcome(in: outcomes, endingWith: "alpha.txt"))
        #expect(alpha.movedTo?.hasSuffix("beta.txt") == true)
        #expect(alpha.oldContent == "alpha\n")
        #expect(alpha.newContent == "alpha\n")
    }

    @Test func rotationOfThreeFilesIsAllowed() throws {
        let (root, pathGuard) = Self.makeFixture()
        let aBytes = Data("A\n".utf8)
        let bBytes = Data("B\n".utf8)
        let cBytes = Data("C\n".utf8)
        try Self.seed(aBytes, named: "a.txt", in: root)
        try Self.seed(bBytes, named: "b.txt", in: root)
        try Self.seed(cBytes, named: "c.txt", in: root)

        // a→b, b→c, c→a: distinct final paths, a legal rotation.
        let hunks: [PatchParser.Hunk] = [
            .updateFile(
                path: TestSupport.path("a.txt", in: root), movePath: TestSupport.path("b.txt", in: root), pairs: []),
            .updateFile(
                path: TestSupport.path("b.txt", in: root), movePath: TestSupport.path("c.txt", in: root), pairs: []),
            .updateFile(
                path: TestSupport.path("c.txt", in: root), movePath: TestSupport.path("a.txt", in: root), pairs: []),
        ]
        _ = try Self.apply(hunks, using: pathGuard)

        #expect(Self.bytes(TestSupport.path("b.txt", in: root)) == aBytes)
        #expect(Self.bytes(TestSupport.path("c.txt", in: root)) == bBytes)
        #expect(Self.bytes(TestSupport.path("a.txt", in: root)) == cBytes)
        #expect(TestSupport.temporaryFileLeftovers(in: root).isEmpty)
    }

    // MARK: Result helpers

    /// The `[FileOutcome]` of a successful apply, or a recorded failure.
    ///
    /// - Parameters:
    ///   - hunks: the parsed hunks to apply, in order.
    ///   - pathGuard: the guard that validates and resolves every path.
    ///   - capturingContent: whether each outcome carries the file's text on
    ///     both sides; defaults to `false`.
    /// - Returns: the per-file outcomes of a successful apply.
    /// - Throws: the failure, after an issue is recorded, so the test stops.
    private static func apply(
        _ hunks: [PatchParser.Hunk],
        using pathGuard: PathGuard,
        capturingContent: Bool = false
    ) throws -> [PatchEngine.FileOutcome] {
        switch PatchEngine.apply(hunks, using: pathGuard, capturingContent: capturingContent) {
        case .success(let outcomes):
            return outcomes
        case .failure(let failure):
            Issue.record("expected success, got failure: \(failure)")
            throw failure
        }
    }

    /// The failure of an apply that is expected to fail.
    ///
    /// - Parameter result: the apply result to unwrap.
    /// - Returns: the failure, or a sentinel after a recorded issue.
    private static func failure(
        _ result: Result<[PatchEngine.FileOutcome], PatchEngine.Failure>
    ) -> PatchEngine.Failure {
        switch result {
        case .success:
            Issue.record("expected failure, got success")
            return .corrective("unexpected success")
        case .failure(let failure):
            return failure
        }
    }
}
