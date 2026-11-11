import Foundation
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Behavioral tests for the ``FileWalker`` shared walk helpers.
///
/// The sibling FileTool package proves this type through its glob and grep
/// operation suites, which are not in this package yet — they arrive with the
/// glob and grep verb tasks. Thus this suite drives each helper directly:
/// the relative-path arithmetic, the canonicalization and directory probes,
/// the plain and git-aware enumeration, the shared collect-filter-assemble
/// loop, and the search-root resolution both engines share.
@Suite(.ownsTemporaryDirectories) struct FileWalkerTests {
    // MARK: Fixtures

    /// Creates a directory tree with one root file and one nested file.
    ///
    /// - Returns: the tree root and the two file names, root-relative.
    private static func makeTree() throws -> (root: URL, rootFile: String, nestedFile: String) {
        let root = TestSupport.canonicalDirectory(TestSupport.makeTemporaryDirectory(named: "FileWalkerTests"))
        let nested = root.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try "alpha\n".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "beta\n".write(to: nested.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        return (root, "a.txt", "sub/b.txt")
    }

    // MARK: Relative paths

    /// The relative path is the remainder under the root, joined with `/`.
    @Test func relativePathJoinsTheComponentsUnderTheRoot() {
        #expect(FileWalker.relativePath(ofAbsolute: "/a/b/c.txt", under: "/a") == "b/c.txt")
    }

    /// A sibling that shares the root's string prefix is not under the root:
    /// the comparison is component-wise, thus `/foobar` is outside `/foo`.
    @Test func relativePathRejectsASiblingThatSharesThePrefix() {
        #expect(FileWalker.relativePath(ofAbsolute: "/foobar/x.txt", under: "/foo") == nil)
    }

    /// The root relative to itself is the empty remainder.
    @Test func relativePathOfTheRootItselfIsEmpty() {
        #expect(FileWalker.relativePath(ofAbsolute: "/a/b", under: "/a/b") == "")
    }

    // MARK: Filesystem probes

    /// `canonicalDirectory` resolves the firmlinks `realpath` resolves, thus
    /// its result agrees with the canonical form the test support computes.
    @Test func canonicalDirectoryResolvesTheTemporaryFirmlink() {
        let root = TestSupport.makeTemporaryDirectory(named: "FileWalkerTests")
        #expect(FileWalker.canonicalDirectory(root) == TestSupport.canonicalDirectory(root))
    }

    /// A path that does not exist cannot be resolved, thus the input URL
    /// comes back unchanged and the caller rejects it separately.
    @Test func canonicalDirectoryFallsBackToTheInputWhenThePathDoesNotExist() {
        let missing = URL(fileURLWithPath: "/nonexistent/FileWalkerTests", isDirectory: true)
        #expect(FileWalker.canonicalDirectory(missing) == missing)
    }

    /// `isDirectory` holds for a directory and fails for a regular file and
    /// for a path with no entry.
    @Test func isDirectoryDistinguishesDirectoriesFromFilesAndMissingPaths() throws {
        let (root, rootFile, _) = try Self.makeTree()
        #expect(FileWalker.isDirectory(root.path))
        #expect(!FileWalker.isDirectory(root.appendingPathComponent(rootFile).path))
        #expect(!FileWalker.isDirectory(root.appendingPathComponent("missing").path))
    }

    // MARK: Enumeration

    /// A plain walk returns each nested regular file as an absolute path and
    /// never returns a directory.
    @Test func collectFilesWalksNestedRegularFilesOnly() async throws {
        let (root, rootFile, nestedFile) = try Self.makeTree()
        let collected = await FileWalker.collectFiles(walkRoot: root, respectGitIgnore: false).sorted()
        #expect(collected == [root.path + "/" + rootFile, root.path + "/" + nestedFile])
    }

    /// Inside a repository the git-aware listing skips an ignored directory,
    /// thus a file under it never appears among the candidates.
    @Test func collectFilesHonorsGitIgnoreInsideARepository() async throws {
        let (root, rootFile, _) = try Self.makeTree()
        try GitFixture.initRepository(at: root)
        try "build/\n".write(to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        let ignored = root.appendingPathComponent("build", isDirectory: true)
        try FileManager.default.createDirectory(at: ignored, withIntermediateDirectories: true)
        try "junk\n".write(to: ignored.appendingPathComponent("out.txt"), atomically: true, encoding: .utf8)

        let collected = await FileWalker.collectFiles(walkRoot: root, respectGitIgnore: true)
        #expect(collected.contains(root.path + "/" + rootFile))
        #expect(!collected.contains { $0.hasPrefix(ignored.path + "/") })
    }

    /// The walk root of the repository listing tests, relative to the work folder.
    private static let listingWalkRoot = "pkg"

    /// The tracked file below the walk root, relative to the work folder.
    private static let trackedBelowWalkRoot = "pkg/tracked.txt"

    /// The tracked file above the walk root, relative to the work folder.
    private static let trackedAboveWalkRoot = "top.txt"

    /// The untracked file in a nested untracked folder below the walk root,
    /// relative to the work folder.
    private static let untrackedInNestedFolder = "pkg/new/deep/untracked.txt"

    /// The file in the ignored `build/` folder below the walk root, relative
    /// to the work folder.
    private static let ignoredBuildOutput = "pkg/build/out.txt"

    /// Writes `contents` to the file at `path` below `root`, and makes each
    /// parent folder that is missing.
    ///
    /// - Parameters:
    ///   - path: The path of the file, relative to `root`.
    ///   - root: The folder that holds the file.
    private static func writeFile(_ path: String, in root: URL) throws {
        let url = root.appendingPathComponent(path, isDirectory: false)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "text\n".write(to: url, atomically: true, encoding: .utf8)
    }

    /// Makes a repository with two tracked files (one above the walk root),
    /// an ignored `build/` folder, and an untracked file in a nested
    /// untracked folder. Only the tracked files are staged.
    ///
    /// - Returns: The canonical work folder.
    private static func makeListingRepository() throws -> URL {
        let root = TestSupport.canonicalDirectory(TestSupport.makeTemporaryDirectory(named: "FileWalkerTests"))
        try GitFixture.initRepository(at: root)
        try "build/\n".write(to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        try writeFile(trackedBelowWalkRoot, in: root)
        try writeFile(trackedAboveWalkRoot, in: root)
        try GitFixture.stageAll(in: root)
        try writeFile(untrackedInNestedFolder, in: root)
        try writeFile(ignoredBuildOutput, in: root)
        return root
    }

    /// A walk root that is a subfolder of a repository gives the tracked file
    /// and the untracked file of a nested untracked folder below it, and no
    /// file above it or in its ignored `build/` folder.
    ///
    /// The plain walk would also give the ignored file, thus this set comes
    /// from the repository listing.
    @Test func collectFilesInASubfolderOfARepositoryGivesTheTrackedAndUntrackedFilesBelowIt() async throws {
        let root = try Self.makeListingRepository()
        let walkRoot = root.appendingPathComponent(Self.listingWalkRoot, isDirectory: true)

        let collected = await FileWalker.collectFiles(walkRoot: walkRoot, respectGitIgnore: true)

        #expect(
            Set(collected)
                == Set([Self.trackedBelowWalkRoot, Self.untrackedInNestedFolder].map { root.path + "/" + $0 }))
    }

    /// A tracked file that the work folder no longer holds stays in the
    /// listing, because the listing reads each entry of the index.
    @Test func collectFilesInARepositoryKeepsATrackedFileThatTheWorkFolderLost() async throws {
        let root = try Self.makeListingRepository()
        try FileManager.default.removeItem(at: root.appendingPathComponent(Self.trackedAboveWalkRoot))

        let collected = await FileWalker.collectFiles(walkRoot: root, respectGitIgnore: true)

        #expect(collected.contains(root.path + "/" + Self.trackedAboveWalkRoot))
    }

    /// A walk root in the `.git` folder is not in the work folder, thus the
    /// walk falls back to the plain enumeration of that folder.
    @Test func collectFilesInTheGitFolderFallsBackToAPlainWalk() async throws {
        let root = try Self.makeListingRepository()
        let gitFolder = root.appendingPathComponent(".git", isDirectory: true)

        let collected = await FileWalker.collectFiles(walkRoot: gitFolder, respectGitIgnore: true)

        #expect(collected.contains(gitFolder.path + "/HEAD"))
    }

    /// Outside a repository the git listing yields nothing, thus the walk
    /// falls back to the plain enumeration and still returns the files.
    @Test func collectFilesFallsBackToAPlainWalkOutsideARepository() async throws {
        let (root, rootFile, nestedFile) = try Self.makeTree()
        let collected = await FileWalker.collectFiles(walkRoot: root, respectGitIgnore: true).sorted()
        #expect(collected == [root.path + "/" + rootFile, root.path + "/" + nestedFile])
    }

    // MARK: Collect-filter-assemble

    /// The shared loop applies the acceptance predicate against the
    /// walk-relative path, builds each kept result from the session-relative
    /// path, and drops a file whose build returns `nil`.
    @Test func walkAndFilterAppliesTheAcceptancePredicateAndBuildsSessionRelativeResults() async throws {
        let (root, rootFile, nestedFile) = try Self.makeTree()
        let walkRoot = root.appendingPathComponent("sub", isDirectory: true)

        let accepted = await FileWalker.walkAndFilter(
            walkRoot: walkRoot,
            sessionRoot: root,
            respectGitIgnore: false,
            excludePatterns: ExcludePatterns([]),
            accept: { _, walkRelativePath in walkRelativePath == "b.txt" },
            build: { _, sessionRelativePath in sessionRelativePath }
        )
        #expect(accepted == [nestedFile])

        let dropped = await FileWalker.walkAndFilter(
            walkRoot: root,
            sessionRoot: root,
            respectGitIgnore: false,
            excludePatterns: ExcludePatterns([]),
            accept: { _, _ in true },
            build: { _, sessionRelativePath in sessionRelativePath == rootFile ? nil : sessionRelativePath }
        )
        #expect(dropped == [nestedFile])
    }

    // MARK: Search-root resolution

    /// An absent requested path resolves to the session root without
    /// consulting the validation closure at all.
    @Test func resolveRequestedPathFallsBackToTheSessionRoot() {
        let root = TestSupport.makeTemporaryDirectory(named: "FileWalkerTests")
        let context = FileContext(root: root)
        let resolved = FileWalker.resolveRequestedPath(nil, in: context) { _ in
            .failure(PathViolation("the fallback must not validate"))
        }
        #expect(resolved == .success(root))
    }

    /// A given requested path resolves to whatever the validation returns.
    @Test func resolveRequestedPathValidatesAGivenPath() {
        let root = TestSupport.makeTemporaryDirectory(named: "FileWalkerTests")
        let context = FileContext(root: root)
        let resolved = FileWalker.resolveRequestedPath("sub", in: context) { path in
            .success(context.root.appendingPathComponent(path, isDirectory: true))
        }
        #expect(resolved == .success(root.appendingPathComponent("sub", isDirectory: true)))
    }

    /// The filesystem root is refused: a whole-filesystem walk is never
    /// allowed, and the violation carries the guard's corrective message.
    @Test func boundDirectoryRefusesTheFilesystemRoot() {
        let root = TestSupport.makeTemporaryDirectory(named: "FileWalkerTests")
        let context = FileContext(root: root)
        let result = FileWalker.boundDirectory(URL(fileURLWithPath: "/"), in: context)
        #expect(throws: PathViolation.self) { try result.get() }
    }

    /// A surviving directory comes back canonicalized, thus the walk and the
    /// session-relative paths share one prefix model.
    @Test func boundDirectoryCanonicalizesTheSurvivingDirectory() {
        let root = TestSupport.makeTemporaryDirectory(named: "FileWalkerTests")
        let context = FileContext(root: root)
        let result = FileWalker.boundDirectory(root, in: context)
        #expect(result == .success(TestSupport.canonicalDirectory(root)))
    }
}
