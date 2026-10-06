import Foundation
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Coverage for `GitContext` and `GitRepositoryLocation` — git.md §
/// "Decisions", item 8: the context holds its own root and one `PathGuard`
/// with the rules of `files`, and the repository is the one that contains the
/// root. The root can be a subfolder of the repository, and each path in a
/// result is relative to the root.
///
/// Each test makes its own temporary repository or folder, thus the tests are
/// independent and they run in parallel safely.
@Suite("GitContextTests")
struct GitContextTests {

    /// The name of the temporary folder of one test. Thus a leaked folder is
    /// traceable to this suite.
    private static let testDirectoryName = "GitContextTests"

    /// The subfolder of the repository that the subfolder tests use as the
    /// root.
    private static let rootSubfolder = "src"

    /// The correction that each verb answers when the root is in no
    /// repository (task `^q01e3qn`, item 5).
    private static let notInRepositoryCorrection = "the root is not in a git repository"

    // MARK: - The repository of the root

    /// A root in a subfolder finds the repository above it, and the work
    /// folder is the real path of that repository (git.md § "Spike result",
    /// fact 1: libgit2 gives `/private/var/...`).
    @Test("a root in a subfolder finds the repository above it")
    func aRootInASubfolderFindsTheRepositoryAboveIt() throws {
        let repository = try TemporaryGitRepository()
        let root = try Self.makeSubfolderRoot(in: repository)

        let context = GitContext(root: root)

        let location = try context.repository.get()
        #expect(location.workDirectory.path == resolvedPath(repository.workDirectory.path))
    }

    /// The root of the work folder itself is a root in the repository.
    @Test("the work folder itself is a root in the repository")
    func theWorkFolderItselfIsARootInTheRepository() throws {
        let repository = try TemporaryGitRepository()

        let context = GitContext(root: repository.workDirectory)

        let location = try context.repository.get()
        #expect(location.workDirectory.path == resolvedPath(repository.workDirectory.path))
        #expect(location.rootRelativePath(fromRepositoryPath: "a.txt") == "a.txt")
    }

    /// A root in no repository does not throw. The context holds the
    /// correction that each verb answers in band.
    @Test("a root outside any repository holds the not-in-a-repository correction")
    func aRootOutsideAnyRepositoryHoldsTheCorrection() {
        let outside = TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName)

        let context = GitContext(root: outside)

        #expect(
            context.repository == .failure(CorrectiveRejection(correctiveMessage: Self.notInRepositoryCorrection)))
    }

    /// A repository whose work folder is in another place (`core.worktree`)
    /// does not contain a root beside its `.git` folder. Thus that root holds
    /// the not-in-a-repository correction, and no verb reads a work folder
    /// that is not below the root.
    @Test("a root outside the work folder of its repository holds the not-in-a-repository correction")
    func aRootOutsideTheWorkFolderOfItsRepositoryHoldsTheCorrection() throws {
        let repository = try TemporaryGitRepository()
        let elsewhere = TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName)
        let config = repository.workDirectory.appendingPathComponent(".git/config", isDirectory: false)
        let text = try String(contentsOf: config, encoding: .utf8)
        try (text + "[core]\n\tworktree = \(elsewhere.path)\n").write(to: config, atomically: true, encoding: .utf8)

        let context = GitContext(root: repository.workDirectory)

        #expect(
            context.repository == .failure(CorrectiveRejection(correctiveMessage: Self.notInRepositoryCorrection)))
    }

    /// A bare repository has no work folder, thus a root in it holds the
    /// bare-repository correction. The test writes the three parts that make
    /// a folder a bare repository for libgit2: `HEAD`, `objects/`, `refs/`,
    /// and a `config` that says `bare = true`.
    @Test("a root in a bare repository holds the bare-repository correction")
    func aRootInABareRepositoryHoldsTheBareCorrection() throws {
        let bare = TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName)
        try "ref: refs/heads/main\n".write(
            to: bare.appendingPathComponent("HEAD", isDirectory: false), atomically: true, encoding: .utf8)
        try "[core]\n\tbare = true\n".write(
            to: bare.appendingPathComponent("config", isDirectory: false), atomically: true, encoding: .utf8)
        for folder in ["objects", "refs"] {
            try FileManager.default.createDirectory(
                at: bare.appendingPathComponent(folder, isDirectory: true), withIntermediateDirectories: true)
        }

        let context = GitContext(root: bare)

        #expect(
            context.repository
                == .failure(CorrectiveRejection(correctiveMessage: "the git repository of the root has no work folder")))
    }

    /// A repository that libgit2 cannot open gives a correction with the
    /// libgit2 text after it. A `.git` file that is not a `gitdir:` link is
    /// such a repository.
    @Test("a repository that libgit2 cannot open holds the libgit2 text")
    func aRepositoryThatCannotOpenHoldsTheLibGit2Text() throws {
        let root = TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName)
        try "not a git link\n".write(
            to: root.appendingPathComponent(".git", isDirectory: false), atomically: true, encoding: .utf8)

        let context = GitContext(root: root)

        let correction = try #require(Self.correction(of: context))
        #expect(correction.hasPrefix("the git repository of the root cannot be opened: "), "was: \(correction)")
        #expect(correction.contains("libgit2 code"), "was: \(correction)")
    }

    /// The path guard holds the rules of `files`: the root is the boundary,
    /// and a path that goes out of it is refused.
    @Test("the path guard keeps each path inside the root")
    func thePathGuardKeepsEachPathInsideTheRoot() throws {
        let repository = try TemporaryGitRepository()
        let root = try Self.makeSubfolderRoot(in: repository)

        let context = GitContext(root: root)

        #expect(context.root == root)
        #expect(context.pathGuard.workspaceRoot == root)
        #expect(!context.pathGuard.allowSymlinks)
        #expect(throws: PathViolation.self) { try context.pathGuard.validatePath("../a.txt").get() }
    }

    // MARK: - Repository path to root path

    /// A repository path below the root becomes a path relative to the root.
    @Test("a repository path below the root becomes a root path")
    func aRepositoryPathBelowTheRootBecomesARootPath() throws {
        let location = try Self.subfolderLocation()

        #expect(location.rootRelativePath(fromRepositoryPath: "src/a.txt") == "a.txt")
        #expect(location.rootRelativePath(fromRepositoryPath: "src/deep/b.txt") == "deep/b.txt")
    }

    /// The root folder itself is `.` relative to the root.
    @Test("the root folder itself is . as a root path")
    func theRootFolderItselfIsDotAsARootPath() throws {
        let location = try Self.subfolderLocation()

        #expect(location.rootRelativePath(fromRepositoryPath: "src") == ".")
    }

    /// A repository path outside the root has no root path. A path that only
    /// starts with the same letters as the root is outside it.
    @Test("a repository path outside the root has no root path")
    func aRepositoryPathOutsideTheRootHasNoRootPath() throws {
        let location = try Self.subfolderLocation()

        #expect(location.rootRelativePath(fromRepositoryPath: "b.txt") == nil)
        #expect(location.rootRelativePath(fromRepositoryPath: "srcx/a.txt") == nil)
    }

    // MARK: - Root path to repository path

    /// A path relative to the root becomes a repository path.
    @Test("a root path becomes a repository path")
    func aRootPathBecomesARepositoryPath() throws {
        let location = try Self.subfolderLocation()

        #expect(location.repositoryPath(fromRootRelativePath: "a.txt") == "src/a.txt")
        #expect(location.repositoryPath(fromRootRelativePath: "./deep/b.txt") == "src/deep/b.txt")
        #expect(location.repositoryPath(fromRootRelativePath: ".") == "src")
    }

    /// A `..` part goes up one folder, and the work folder itself is `.`.
    @Test("a .. part goes up one folder")
    func aDotDotPartGoesUpOneFolder() throws {
        let location = try Self.subfolderLocation()

        #expect(location.repositoryPath(fromRootRelativePath: "../b.txt") == "b.txt")
        #expect(location.repositoryPath(fromRootRelativePath: "..") == ".")
    }

    /// A path that goes above the work folder, or an absolute path, has no
    /// repository path.
    @Test("a path above the work folder or an absolute path has no repository path")
    func aPathAboveTheWorkFolderHasNoRepositoryPath() throws {
        let location = try Self.subfolderLocation()

        #expect(location.repositoryPath(fromRootRelativePath: "../../x.txt") == nil)
        #expect(location.repositoryPath(fromRootRelativePath: "/etc/hosts") == nil)
    }

    /// The two helpers go in opposite directions: a repository path below
    /// the root goes to a root path and back to the same repository path.
    @Test("a repository path goes to a root path and back unchanged")
    func aRepositoryPathGoesToARootPathAndBack() throws {
        let location = try Self.subfolderLocation()
        let repositoryPath = "src/deep/b.txt"

        let rootPath = try #require(location.rootRelativePath(fromRepositoryPath: repositoryPath))

        #expect(location.repositoryPath(fromRootRelativePath: rootPath) == repositoryPath)
    }

    // MARK: - File URL to repository path

    /// A file URL in the work folder becomes a repository path. The URL keeps
    /// the `/var/...` spelling of the temporary folder, and the work folder
    /// is a real path (`/private/var/...`), thus the helper must compare real
    /// paths.
    @Test("a file URL in the work folder becomes a repository path")
    func aFileURLInTheWorkFolderBecomesARepositoryPath() throws {
        let repository = try TemporaryGitRepository()
        try repository.write("one\n", to: "src/deep/b.txt")
        let root = try Self.makeSubfolderRoot(in: repository)
        let location = try GitContext(root: root).repository.get()
        let file = repository.workDirectory.appendingPathComponent("src/deep/b.txt", isDirectory: false)

        #expect(location.repositoryPath(ofFile: file) == "src/deep/b.txt")
    }

    /// A file URL outside the work folder has no repository path.
    @Test("a file URL outside the work folder has no repository path")
    func aFileURLOutsideTheWorkFolderHasNoRepositoryPath() throws {
        let repository = try TemporaryGitRepository()
        let location = try GitContext(root: repository.workDirectory).repository.get()
        let outside = TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName)
        let file = outside.appendingPathComponent("a.txt", isDirectory: false)
        try "one\n".write(to: file, atomically: true, encoding: .utf8)

        #expect(location.repositoryPath(ofFile: file) == nil)
    }

    // MARK: - Helpers

    /// Makes the ``rootSubfolder`` folder in `repository`, and gives its URL.
    ///
    /// - Parameter repository: The repository.
    /// - Returns: The URL of the subfolder, in the spelling of the work
    ///   folder of `repository` (`/var/...`, not `/private/var/...`).
    /// - Throws: The error of `FileManager`.
    private static func makeSubfolderRoot(in repository: TemporaryGitRepository) throws -> URL {
        let root = repository.workDirectory.appendingPathComponent(rootSubfolder, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// The correction that `context` holds in place of a repository.
    ///
    /// - Parameter context: The context.
    /// - Returns: The correction, or `nil` when the context found a
    ///   repository.
    private static func correction(of context: GitContext) -> String? {
        switch context.repository {
        case .success:
            nil
        case .failure(let rejection):
            rejection.correctiveMessage
        }
    }

    /// The location of a root at ``rootSubfolder`` of a new repository.
    ///
    /// The location is a value: it keeps the paths after the repository is
    /// released, thus the path tests need no repository after this call.
    ///
    /// - Returns: The location.
    /// - Throws: When the repository cannot be made, or the root is in no
    ///   repository.
    private static func subfolderLocation() throws -> GitRepositoryLocation {
        let repository = try TemporaryGitRepository()
        let root = try makeSubfolderRoot(in: repository)
        return try GitContext(root: root).repository.get()
    }
}
