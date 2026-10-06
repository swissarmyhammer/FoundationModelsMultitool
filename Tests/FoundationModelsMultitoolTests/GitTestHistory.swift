// `GitTestHistory` — the repository histories that the git test suites share.
//
// The suites of the `LibGit2` layer and the suites of the verbs read the same
// histories. One builder for each history keeps the two kinds of suite on the
// same facts, thus a change to a history changes both kinds at one time.

import Foundation

@testable import MultitoolTestSupport

/// The repository histories that the git test suites share.
///
/// A namespace, not a value: each builder makes a new temporary repository,
/// thus each test holds its own repository and the tests run in parallel
/// safely.
enum GitTestHistory {

    /// The branch that each history makes at an older commit. HEAD does not
    /// move to it.
    static let featureBranch = "feature"

    /// The folder that the last commit of
    /// ``makeRemovedFolder(firstText:secondText:)`` removes from the work
    /// folder, relative to the work folder.
    static let removedFolder = "old"

    /// The file of ``makeRemovedFolder(firstText:secondText:)``, relative to
    /// the work folder. It is two folders below ``removedFolder``.
    static let removedFolderFile = "\(removedFolder)/dir/a.txt"

    /// The folder that ``makeRemovedFolder(firstText:secondText:)`` keeps in
    /// the work folder. A test can use it as a root in a subfolder.
    static let keptFolder = "src"

    /// Makes a repository with three commits on the branch of HEAD:
    ///
    /// 1. `first` writes `a.txt`.
    /// 2. `second` writes `src/b.txt`. ``featureBranch`` stops here.
    /// 3. `third` changes `a.txt`.
    ///
    /// - Returns: The repository, and the sha of each commit, oldest first.
    /// - Throws: When a write, a commit, or the branch fails.
    static func makeThreeCommits() throws -> (repository: TemporaryGitRepository, shas: [String]) {
        let repository = try TemporaryGitRepository()
        try repository.write("1\n", to: "a.txt")
        let first = try repository.commit(message: "first")
        try repository.write("b\n", to: "src/b.txt")
        let second = try repository.commit(message: "second")
        try repository.createBranch(named: featureBranch)
        try repository.write("3\n", to: "a.txt")
        let third = try repository.commit(message: "third")
        return (repository, [first, second, third])
    }

    /// Makes a repository with two versions of one file: the commit `first`
    /// writes `firstText`, ``featureBranch`` stops there, and the commit
    /// `second` writes `secondText`.
    ///
    /// - Parameters:
    ///   - path: The path of the file, relative to the work folder.
    ///   - firstText: The text of the first commit.
    ///   - secondText: The text of the second commit.
    /// - Returns: The repository.
    /// - Throws: When a write, a commit, or the branch fails.
    static func makeTwoVersions(
        of path: String,
        firstText: String,
        secondText: String
    ) throws -> TemporaryGitRepository {
        let repository = try TemporaryGitRepository()
        try repository.write(firstText, to: path)
        try repository.commit(message: "first")
        try repository.createBranch(named: featureBranch)
        try repository.write(secondText, to: path)
        try repository.commit(message: "second")
        return repository
    }

    /// Makes a repository with three commits on the branch of HEAD:
    ///
    /// 1. `first` writes ``removedFolderFile`` with `firstText`, and
    ///    `keep.txt` in ``keptFolder``.
    /// 2. `second` writes ``removedFolderFile`` with `secondText`.
    /// 3. `third` removes ``removedFolder`` from the work folder.
    ///
    /// - Parameters:
    ///   - firstText: The text of the first commit.
    ///   - secondText: The text of the second commit.
    /// - Returns: The repository, and the sha of each commit, oldest first.
    /// - Throws: When a write, a removal, or a commit fails.
    static func makeRemovedFolder(
        firstText: String,
        secondText: String
    ) throws -> (repository: TemporaryGitRepository, shas: [String]) {
        let repository = try TemporaryGitRepository()
        try repository.write(firstText, to: removedFolderFile)
        try repository.write("keep\n", to: "\(keptFolder)/keep.txt")
        let first = try repository.commit(message: "first")
        try repository.write(secondText, to: removedFolderFile)
        let second = try repository.commit(message: "second")
        try FileManager.default.removeItem(
            at: repository.workDirectory.appendingPathComponent(removedFolder, isDirectory: true))
        let third = try repository.commit(message: "third")
        return (repository, [first, second, third])
    }
}
