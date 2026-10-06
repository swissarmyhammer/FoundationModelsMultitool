import Foundation
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Coverage for the change part of the `LibGit2` layer: the files that a
/// branch changed since the merge-base with its parent, and the files of a
/// range.
///
/// The cases are the ports of `test_get_changed_files_from_parent` and of the
/// three `test_get_changed_files_from_range_*` tests in
/// `../swissarmyhammer/crates/swissarmyhammer-git/src/operations.rs`, and the
/// cases of a bad range. Each test makes its own repository, thus the tests
/// are independent and they run in parallel safely.
@Suite("LibGit2ChangesTests")
struct LibGit2ChangesTests {

    /// The branch that each parent test changes.
    private static let featureBranch = "feature"

    /// The range of the last commit.
    private static let lastCommitRange = "HEAD~1..HEAD"

    /// The files that the branch changed since the merge-base come back in
    /// path order, one time each. A file that the parent changed after the
    /// merge-base is not one of them.
    @Test("the files since the merge-base are the files of the branch")
    func theFilesSinceTheMergeBaseAreTheFilesOfTheBranch() throws {
        let repository = try TemporaryGitRepository()
        try repository.write("Initial content", to: "README.md")
        try repository.commit(message: "Initial commit")
        try repository.createBranch(named: Self.featureBranch)
        try repository.write("main", to: "main-only.txt")
        try repository.commit(message: "Main commit")
        try repository.pointHead(atBranch: Self.featureBranch)
        try FileManager.default.removeItem(at: repository.workDirectory.appendingPathComponent("main-only.txt"))
        try repository.write("fn main() {}", to: "src/main.rs")
        try repository.write("pub fn hello() {}", to: "src/lib.rs")
        try repository.commit(message: "Feature commit 1")
        try repository.write("# Guide", to: "docs/guide.md")
        try repository.commit(message: "Feature commit 2")
        try repository.write("fn main() { println!(\"Hello\"); }", to: "src/main.rs")
        try repository.write("#[test] fn test_main() {}", to: "tests/test.rs")
        try repository.commit(message: "Feature commit 3")
        let opened = try LibGit2Repository(discoveringFrom: repository.workDirectory)

        let paths = try opened.changedPaths(
            onBranch: Self.featureBranch, sinceMergeBaseWith: TemporaryGitRepository.defaultBranch)

        #expect(paths == ["docs/guide.md", "src/lib.rs", "src/main.rs", "tests/test.rs"])
    }

    /// `HEAD~1..HEAD` gives the files of the last commit only.
    @Test("the range of the last commit gives its files")
    func theRangeOfTheLastCommitGivesItsFiles() throws {
        let repository = try Self.makeCommits(["README.md", "file1.txt"])
        let opened = try LibGit2Repository(discoveringFrom: repository.workDirectory)

        #expect(try opened.changedPaths(inRange: Self.lastCommitRange) == ["file1.txt"])
    }

    /// `HEAD~3..HEAD` gives the files of the last three commits.
    @Test("a range of three commits gives the files of each")
    func aRangeOfThreeCommitsGivesTheFilesOfEach() throws {
        let repository = try Self.makeCommits(["README.md", "file1.txt", "file2.txt", "file3.txt"])
        let opened = try LibGit2Repository(discoveringFrom: repository.workDirectory)

        #expect(try opened.changedPaths(inRange: "HEAD~3..HEAD") == ["file1.txt", "file2.txt", "file3.txt"])
    }

    /// One ref alone is the range from that ref to HEAD.
    @Test("one ref alone is the range from that ref to HEAD")
    func oneRefAloneIsTheRangeFromThatRefToHead() throws {
        let repository = try Self.makeCommits(["README.md", "file1.txt", "file2.txt"])
        let opened = try LibGit2Repository(discoveringFrom: repository.workDirectory)

        #expect(try opened.changedPaths(inRange: "HEAD~2") == ["file1.txt", "file2.txt"])
    }

    /// A file that the range removes is in the list under its path.
    @Test("a file that the range removes is in the list")
    func aFileThatTheRangeRemovesIsInTheList() throws {
        let repository = try TemporaryGitRepository()
        try repository.write("a\n", to: "a.txt")
        try repository.write("b\n", to: "b.txt")
        try repository.commit(message: "first")
        try FileManager.default.removeItem(at: repository.workDirectory.appendingPathComponent("a.txt"))
        try repository.commit(message: "second")
        let opened = try LibGit2Repository(discoveringFrom: repository.workDirectory)

        #expect(try opened.changedPaths(inRange: Self.lastCommitRange) == ["a.txt"])
    }

    /// A ref that names no commit gives no list.
    @Test("a ref that names no commit gives no list")
    func aRefThatNamesNoCommitGivesNoList() throws {
        let repository = try Self.makeCommits(["README.md", "file1.txt"])
        let opened = try LibGit2Repository(discoveringFrom: repository.workDirectory)

        #expect(try opened.changedPaths(inRange: "no-such-ref..HEAD") == nil)
    }

    /// In a repository with one commit, `HEAD~1` names no commit, thus the
    /// range of the last commit gives no list.
    @Test("one commit only gives no list for the last-commit range")
    func oneCommitOnlyGivesNoListForTheLastCommitRange() throws {
        let repository = try Self.makeCommits(["README.md"])
        let opened = try LibGit2Repository(discoveringFrom: repository.workDirectory)

        #expect(try opened.changedPaths(inRange: Self.lastCommitRange) == nil)
    }

    // MARK: - Helpers

    /// Makes a repository with one commit for each path, oldest first. Each
    /// commit writes its own new file.
    ///
    /// - Parameter paths: The path of the file of each commit.
    /// - Returns: The repository. The test keeps it while it reads, because
    ///   the release of the repository removes its folder.
    /// - Throws: When a write or a commit fails.
    private static func makeCommits(_ paths: [String]) throws -> TemporaryGitRepository {
        let repository = try TemporaryGitRepository()
        for path in paths {
            try repository.write("\(path)\n", to: path)
            try repository.commit(message: "add \(path)")
        }
        return repository
    }
}
