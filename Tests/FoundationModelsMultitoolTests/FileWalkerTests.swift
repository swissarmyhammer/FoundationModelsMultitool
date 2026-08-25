import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Behavioral tests for the ``FileWalker`` shared walk helpers.
///
/// The sibling FileTool package proves this type through its glob and grep
/// operation suites, which are not in this package yet — they arrive with the
/// glob and grep verb tasks. Thus this suite drives each helper directly:
/// the relative-path arithmetic, the canonicalization and directory probes,
/// the plain and git-aware enumeration, the shared collect-filter-assemble
/// loop, and the search-root resolution both engines share.
@Suite struct FileWalkerTests {
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
    @Test func collectFilesWalksNestedRegularFilesOnly() throws {
        let (root, rootFile, nestedFile) = try Self.makeTree()
        let collected = FileWalker.collectFiles(walkRoot: root, respectGitIgnore: false).sorted()
        #expect(collected == [root.path + "/" + rootFile, root.path + "/" + nestedFile])
    }

    /// Inside a repository the git-aware listing skips an ignored directory,
    /// thus a file under it never appears among the candidates.
    @Test func collectFilesHonorsGitIgnoreInsideARepository() throws {
        let (root, rootFile, _) = try Self.makeTree()
        try TestSupport.runGit(["init", "--quiet"], in: root)
        try "build/\n".write(to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        let ignored = root.appendingPathComponent("build", isDirectory: true)
        try FileManager.default.createDirectory(at: ignored, withIntermediateDirectories: true)
        try "junk\n".write(to: ignored.appendingPathComponent("out.txt"), atomically: true, encoding: .utf8)

        let collected = FileWalker.collectFiles(walkRoot: root, respectGitIgnore: true)
        #expect(collected.contains(root.path + "/" + rootFile))
        #expect(!collected.contains { $0.hasPrefix(ignored.path + "/") })
    }

    /// Outside a repository the git listing yields nothing, thus the walk
    /// falls back to the plain enumeration and still returns the files.
    @Test func collectFilesFallsBackToAPlainWalkOutsideARepository() throws {
        let (root, rootFile, nestedFile) = try Self.makeTree()
        let collected = FileWalker.collectFiles(walkRoot: root, respectGitIgnore: true).sorted()
        #expect(collected == [root.path + "/" + rootFile, root.path + "/" + nestedFile])
    }

    // MARK: Collect-filter-assemble

    /// The shared loop applies the acceptance predicate against the
    /// walk-relative path, builds each kept result from the session-relative
    /// path, and drops a file whose build returns `nil`.
    @Test func walkAndFilterAppliesTheAcceptancePredicateAndBuildsSessionRelativeResults() throws {
        let (root, rootFile, nestedFile) = try Self.makeTree()
        let walkRoot = root.appendingPathComponent("sub", isDirectory: true)

        let accepted = FileWalker.walkAndFilter(
            walkRoot: walkRoot,
            sessionRoot: root,
            respectGitIgnore: false,
            accept: { _, walkRelativePath in walkRelativePath == "b.txt" },
            build: { _, sessionRelativePath in sessionRelativePath }
        )
        #expect(accepted == [nestedFile])

        let dropped = FileWalker.walkAndFilter(
            walkRoot: root,
            sessionRoot: root,
            respectGitIgnore: false,
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
