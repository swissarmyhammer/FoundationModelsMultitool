import Foundation
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Coverage for the blob part of the `LibGit2` layer: the bytes of one file at
/// one ref, and the kind of each lookup that finds no file.
///
/// libgit2 gives the same code (`GIT_ENOTFOUND`) for an unknown ref and for an
/// unknown path. The layer tells the two apart, thus each test here holds one
/// kind of lookup. Each test makes its own temporary repository, thus the tests
/// are independent and they run in parallel safely.
@Suite("LibGit2BlobTests")
struct LibGit2BlobTests {

    /// The file that the tests read.
    private static let filePath = "src/a.txt"

    /// The text of the first commit of ``filePath``.
    private static let firstText = "one\ntwo\n"

    /// The text of the second commit of ``filePath``.
    private static let secondText = "one\nTWO\n"

    /// The ref of the commit before HEAD.
    private static let parentRevision = "HEAD~1"

    /// The ref of the newest commit.
    private static let headRevision = "HEAD"

    /// The bytes of a file that git sees as binary: a NUL byte, and bytes that
    /// are not UTF-8.
    private static let binaryBytes = Data([0x00, 0xFF, 0x00, 0x80])

    /// The bytes of a file at HEAD are the bytes of the newest commit, and the
    /// bytes at the commit before are the bytes of that commit.
    @Test("the blob at a ref holds the bytes of that commit")
    func theBlobAtARefHoldsTheBytesOfThatCommit() throws {
        let repository = try Self.repositoryWithTwoCommits()
        let opened = try LibGit2Repository(discoveringFrom: repository.workDirectory)

        let head = try opened.blob(atPath: Self.filePath, revision: Self.headRevision)
        let parent = try opened.blob(atPath: Self.filePath, revision: Self.parentRevision)

        #expect(head == .found(LibGit2Blob(content: Data(Self.secondText.utf8), isBinary: false)))
        #expect(parent == .found(LibGit2Blob(content: Data(Self.firstText.utf8), isBinary: false)))
    }

    /// A ref that names no object is an unknown revision, not a thrown error.
    @Test("a ref that names no object is an unknown revision")
    func aRefThatNamesNoObjectIsAnUnknownRevision() throws {
        let repository = try Self.repositoryWithTwoCommits()

        let lookup = try LibGit2Repository(discoveringFrom: repository.workDirectory)
            .blob(atPath: Self.filePath, revision: "no-such-ref")

        #expect(lookup == .unknownRevision)
    }

    /// A path that the commit does not hold is an unknown path, not a thrown
    /// error.
    @Test("a path that the commit does not hold is an unknown path")
    func aPathThatTheCommitDoesNotHoldIsAnUnknownPath() throws {
        let repository = try Self.repositoryWithTwoCommits()

        let lookup = try LibGit2Repository(discoveringFrom: repository.workDirectory)
            .blob(atPath: "src/missing.txt", revision: Self.headRevision)

        #expect(lookup == .unknownPath)
    }

    /// A path that names a folder of the commit is not a file.
    @Test("a path that names a folder is not a file")
    func aPathThatNamesAFolderIsNotAFile() throws {
        let repository = try Self.repositoryWithTwoCommits()

        let lookup = try LibGit2Repository(discoveringFrom: repository.workDirectory)
            .blob(atPath: "src", revision: Self.headRevision)

        #expect(lookup == .notAFile)
    }

    /// A file with a NUL byte is binary for git, and the layer says so beside
    /// its bytes.
    @Test("a binary file is found with its binary flag set")
    func aBinaryFileIsFoundWithItsBinaryFlagSet() throws {
        let repository = try TemporaryGitRepository()
        try Self.binaryBytes.write(
            to: repository.workDirectory.appendingPathComponent("blob.bin", isDirectory: false))
        try repository.commit(message: "binary")

        let lookup = try LibGit2Repository(discoveringFrom: repository.workDirectory)
            .blob(atPath: "blob.bin", revision: Self.headRevision)

        #expect(lookup == .found(LibGit2Blob(content: Self.binaryBytes, isBinary: true)))
    }

    // MARK: - Helpers

    /// A repository with ``firstText`` and then ``secondText`` committed to
    /// ``filePath``.
    ///
    /// - Returns: The repository.
    /// - Throws: When a write, a commit, or the branch fails.
    private static func repositoryWithTwoCommits() throws -> TemporaryGitRepository {
        try GitTestHistory.makeTwoVersions(of: filePath, firstText: firstText, secondText: secondText)
    }
}
