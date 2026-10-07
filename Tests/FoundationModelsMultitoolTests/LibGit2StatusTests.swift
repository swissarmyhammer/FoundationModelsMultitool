import Foundation
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Coverage for the status part of the `LibGit2` layer: the uncommitted
/// files of the work folder and of the index, in four groups, with their
/// paths relative to the work folder.
///
/// Each test makes its own repository, thus the tests are independent and
/// they run in parallel safely.
@Suite("LibGit2StatusTests")
struct LibGit2StatusTests {

    /// A repository with no change after its last commit has no file in any
    /// group.
    @Test("a clean work folder has no file in any group")
    func aCleanWorkFolderHasNoFileInAnyGroup() throws {
        let repository = try TemporaryGitRepository()
        try repository.write("a\n", to: "a.txt")
        try repository.commit(message: "first")

        let status = try Self.status(of: repository)

        #expect(LibGit2StatusGroup.allCases.allSatisfy { status.paths(in: $0).isEmpty })
    }

    /// A new staged file, a changed staged file, and a staged removal are
    /// each staged.
    @Test("a staged new file, change, and removal are staged")
    func aStagedNewFileChangeAndRemovalAreStaged() throws {
        let repository = try TemporaryGitRepository()
        try repository.write("a\n", to: "a.txt")
        try repository.write("b\n", to: "b.txt")
        try repository.commit(message: "first")
        try repository.write("n\n", to: "n.txt")
        try repository.stage("n.txt")
        try repository.write("a2\n", to: "a.txt")
        try repository.stage("a.txt")
        try FileManager.default.removeItem(at: repository.workDirectory.appendingPathComponent("b.txt"))
        try repository.stage("b.txt")

        let status = try Self.status(of: repository)

        #expect(Set(status.paths(in: .staged)) == ["a.txt", "b.txt", "n.txt"])
        #expect(status.paths(in: .unstaged).isEmpty)
        #expect(status.paths(in: .untracked).isEmpty)
        #expect(status.paths(in: .renamed).isEmpty)
    }

    /// A changed file and a removed file that are not staged are unstaged.
    @Test("a change and a removal that are not staged are unstaged")
    func aChangeAndARemovalThatAreNotStagedAreUnstaged() throws {
        let repository = try TemporaryGitRepository()
        try repository.write("a\n", to: "a.txt")
        try repository.write("b\n", to: "b.txt")
        try repository.commit(message: "first")
        try repository.write("a2\n", to: "a.txt")
        try FileManager.default.removeItem(at: repository.workDirectory.appendingPathComponent("b.txt"))

        let status = try Self.status(of: repository)

        #expect(Set(status.paths(in: .unstaged)) == ["a.txt", "b.txt"])
        #expect(status.paths(in: .staged).isEmpty)
    }

    /// A file in a new folder is untracked under its own path, not under the
    /// path of the folder.
    @Test("an untracked file in a new folder has its own path")
    func anUntrackedFileInANewFolderHasItsOwnPath() throws {
        let repository = try TemporaryGitRepository()
        try repository.write("a\n", to: "a.txt")
        try repository.commit(message: "first")
        try repository.write("x\n", to: "new/dir/x.txt")

        let status = try Self.status(of: repository)

        #expect(status.paths(in: .untracked) == ["new/dir/x.txt"])
    }

    /// A staged rename is in the renamed group under its new path, and the
    /// old path is in no group.
    @Test("a staged rename is renamed under its new path")
    func aStagedRenameIsRenamedUnderItsNewPath() throws {
        let repository = try TemporaryGitRepository()
        try repository.write("the text of the file\n", to: "old.txt")
        try repository.commit(message: "first")
        try FileManager.default.moveItem(
            at: repository.workDirectory.appendingPathComponent("old.txt"),
            to: repository.workDirectory.appendingPathComponent("new.txt"))
        try repository.stage("old.txt")
        try repository.stage("new.txt")

        let status = try Self.status(of: repository)

        #expect(status.paths(in: .renamed) == ["new.txt"])
        #expect(status.paths(in: .staged).isEmpty)
        #expect(status.paths(in: .unstaged).isEmpty)
        #expect(status.paths(in: .untracked).isEmpty)
    }

    /// A staged rename keeps its old path beside its new path, and a file
    /// with no rename has no old path.
    @Test("a staged rename keeps its old path")
    func aStagedRenameKeepsItsOldPath() throws {
        let repository = try TemporaryGitRepository()
        try repository.write("the text of the file\n", to: "old.txt")
        try repository.write("a\n", to: "a.txt")
        try repository.commit(message: "first")
        try repository.stageRename(from: "old.txt", to: "new.txt")
        try repository.write("a2\n", to: "a.txt")
        try repository.stage("a.txt")

        let status = try Self.status(of: repository)

        #expect(status.oldPathsOfRenamedFiles == ["new.txt": "old.txt"])
        let changed = try #require(status.entries.first { $0.path == "a.txt" })
        #expect(changed.oldPath == nil)
    }

    /// A file with a merge conflict is unstaged: the work folder must change
    /// before the file can be staged.
    @Test("a conflicted file is unstaged")
    func aConflictedFileIsUnstaged() throws {
        let repository = try TemporaryGitRepository()
        try repository.write("a\n", to: "a.txt")
        try repository.commit(message: "first")
        try repository.markConflicted("a.txt")

        let status = try Self.status(of: repository)

        #expect(status.paths(in: .unstaged) == ["a.txt"])
    }

    /// A repository with no commit gives each staged file as staged.
    @Test("a repository with no commit gives a staged file as staged")
    func aRepositoryWithNoCommitGivesAStagedFileAsStaged() throws {
        let repository = try TemporaryGitRepository()
        try repository.write("a\n", to: "a.txt")
        try repository.stage("a.txt")
        try repository.write("u\n", to: "u.txt")

        let status = try Self.status(of: repository)

        #expect(status.paths(in: .staged) == ["a.txt"])
        #expect(status.paths(in: .untracked) == ["u.txt"])
    }

    // MARK: - Helpers

    /// Reads the status of a repository through the `LibGit2` layer.
    ///
    /// - Parameter repository: The repository.
    /// - Returns: The status.
    /// - Throws: ``LibGit2Error`` when the repository or its status cannot be
    ///   read.
    private static func status(of repository: TemporaryGitRepository) throws -> LibGit2Status {
        try LibGit2Repository(discoveringFrom: repository.workDirectory).status()
    }
}
