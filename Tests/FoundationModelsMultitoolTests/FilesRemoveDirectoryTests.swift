// `FilesRemoveDirectoryTests` — the behavioral suite of the
// `tools.files.removeDirectory` verb.
//
// The suite uses the same setup as `FilesWriteTests`: each test makes a
// temporary root, constructs `RemoveDirectoryArguments` with the memberwise
// initializer, and calls the `RemoveDirectory` verb directly. There is one test
// for each acceptance criterion of the card ^y4fbfyy, and one test for each
// root and symlink rule that the card names.

import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Behavioral tests for the `tools.files.removeDirectory` verb.
///
/// The cases are: an empty directory is removed; a directory that holds files
/// gives a correction without `recursive`, and is removed whole with
/// `recursive: true`; a missing path, a regular file, the session root, a
/// workspace root, a path outside the root, and a read-only session each give
/// a correction and change nothing on the disk; a symlink to a directory is
/// removed and its target stays; and a recording session records one delete
/// change for each removed file.
@Suite struct FilesRemoveDirectoryTests {
    // MARK: Test scaffolding

    /// The name of the temporary directory of one test, thus a leaked
    /// directory is traceable to this suite.
    private static let testDirectoryName = "FilesRemoveDirectoryTests"

    /// The relative path of the directory that the tests remove.
    private static let directoryName = "tree"

    /// The relative path of a folder inside ``directoryName``.
    private static let nestedFolder = "tree/inner"

    /// Each file the tests put in the tree, relative to the root, with its content.
    private static let treeFiles = [
        "tree/top.txt": "top\n",
        "tree/inner/middle.txt": "middle\n",
        "tree/inner/bottom.txt": "bottom\n",
    ]

    /// The name of a regular file, which the verb must not remove.
    private static let fileName = "plain.txt"

    /// The content of the regular file.
    private static let fileContent = "keep\n"

    /// The name of the symlink that points at the tree.
    private static let linkName = "link"

    /// Call the `tools.files.removeDirectory` verb over a session context.
    ///
    /// - Parameters:
    ///   - path: the directory path to remove.
    ///   - recursive: whether to remove a directory that holds entries; `nil` uses the verb's default.
    ///   - context: the session context the verb works against.
    /// - Returns: the verb's flat result.
    private static func removeDirectory(
        path: String,
        recursive: Bool? = nil,
        in context: FileContext
    ) async throws -> RemoveDirectoryResult {
        try await RemoveDirectory(context: context)
            .call(arguments: RemoveDirectoryArguments(path: path, recursive: recursive))
    }

    /// Make the tree of ``treeFiles`` under a root.
    ///
    /// - Parameter root: the directory to make the tree in.
    /// - Throws: an error when a folder or a file cannot be made.
    private static func makeTree(in root: URL) throws {
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(nestedFolder, isDirectory: true),
            withIntermediateDirectories: true
        )
        for (name, contents) in treeFiles {
            try TestSupport.seed(name, contents: contents, in: root)
        }
    }

    /// Whether a symlink stands at a path, without following it.
    ///
    /// - Parameter path: the absolute path to inspect.
    /// - Returns: `true` when the path itself is a symlink.
    private static func isSymlink(_ path: String) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) != nil
    }

    // MARK: Removal

    /// An empty directory is removed, and the result has `removed: true`,
    /// `filesRemoved: 0`, and no correction.
    @Test func emptyDirectoryIsRemoved() async throws {
        let root = TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName)
        let directory = TestSupport.path(Self.directoryName, in: root)
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: false)
        let context = FileContext(root: root)

        let result = try await Self.removeDirectory(path: Self.directoryName, in: context)

        #expect(result.correction == nil)
        #expect(result.removed)
        #expect(result.filesRemoved == 0)
        #expect(result.path.hasSuffix(Self.directoryName))
        #expect(!FileManager.default.fileExists(atPath: directory))
    }

    /// A directory that holds files gives a correction when the call omits
    /// `recursive`, and nothing is removed.
    @Test func directoryWithFilesWithoutRecursiveIsCorrective() async throws {
        let root = TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName)
        try Self.makeTree(in: root)
        let context = FileContext(root: root)

        let result = try await Self.removeDirectory(path: Self.directoryName, in: context)

        #expect(result.correction != nil)
        #expect(!result.removed)
        #expect(result.path.isEmpty)
        for (name, contents) in Self.treeFiles {
            #expect(TestSupport.text(at: TestSupport.path(name, in: root)) == contents)
        }
    }

    /// With `recursive: true` the whole tree is removed, and `filesRemoved` is
    /// the number of files the tree held.
    @Test func recursiveRemovalRemovesTheTree() async throws {
        let root = TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName)
        try Self.makeTree(in: root)
        let context = FileContext(root: root)

        let result = try await Self.removeDirectory(path: Self.directoryName, recursive: true, in: context)

        #expect(result.correction == nil)
        #expect(result.removed)
        #expect(result.filesRemoved == Self.treeFiles.count)
        #expect(!FileManager.default.fileExists(atPath: TestSupport.path(Self.directoryName, in: root)))
    }

    /// A symlink to a directory is removed, and the target directory and its
    /// files stay.
    @Test func symlinkToADirectoryRemovesOnlyTheLink() async throws {
        let root = TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName)
        try Self.makeTree(in: root)
        let linkPath = TestSupport.path(Self.linkName, in: root)
        try FileManager.default.createSymbolicLink(
            atPath: linkPath,
            withDestinationPath: TestSupport.path(Self.directoryName, in: root)
        )
        let context = FileContext(root: root, allowSymlinks: true)

        let result = try await Self.removeDirectory(path: Self.linkName, recursive: true, in: context)

        #expect(result.correction == nil)
        #expect(result.removed)
        #expect(result.filesRemoved == 0)
        #expect(!Self.isSymlink(linkPath))
        for (name, contents) in Self.treeFiles {
            #expect(TestSupport.text(at: TestSupport.path(name, in: root)) == contents)
        }
    }

    // MARK: Corrections

    /// A path with nothing at it gives a correction.
    @Test func missingPathIsCorrective() async throws {
        let root = TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName)
        let context = FileContext(root: root)

        let result = try await Self.removeDirectory(path: Self.directoryName, in: context)

        #expect(result.correction != nil)
        #expect(!result.removed)
        #expect(result.filesRemoved == 0)
    }

    /// A regular file gives a correction, and the file stays as it was.
    @Test func regularFileIsCorrective() async throws {
        let root = TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName)
        let filePath = try TestSupport.seed(Self.fileName, contents: Self.fileContent, in: root)
        let context = FileContext(root: root)

        let result = try await Self.removeDirectory(path: Self.fileName, recursive: true, in: context)

        #expect(result.correction != nil)
        #expect(!result.removed)
        #expect(TestSupport.text(at: filePath) == Self.fileContent)
    }

    /// The session root gives a correction, and the root and its files stay.
    @Test func sessionRootIsCorrective() async throws {
        let root = TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName)
        try Self.makeTree(in: root)
        let context = FileContext(root: root)

        let result = try await Self.removeDirectory(path: root.path, recursive: true, in: context)

        #expect(result.correction != nil)
        #expect(!result.removed)
        #expect(FileWalker.isDirectory(root.path))
        for (name, contents) in Self.treeFiles {
            #expect(TestSupport.text(at: TestSupport.path(name, in: root)) == contents)
        }
    }

    /// An additional workspace root gives a correction, and it stays.
    @Test func additionalWorkspaceRootIsCorrective() async throws {
        let root = TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName)
        let additional = TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName)
        let context = FileContext(root: root, additionalRoots: [additional])

        let result = try await Self.removeDirectory(path: additional.path, recursive: true, in: context)

        #expect(result.correction != nil)
        #expect(!result.removed)
        #expect(FileWalker.isDirectory(additional.path))
    }

    /// A path outside the root gives a correction, and the outside tree stays.
    @Test func pathOutsideTheRootIsCorrective() async throws {
        let root = TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName)
        let outside = TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName)
        try Self.makeTree(in: outside)
        let context = FileContext(root: root)

        let result = try await Self.removeDirectory(
            path: TestSupport.path(Self.directoryName, in: outside),
            recursive: true,
            in: context
        )

        #expect(result.correction != nil)
        #expect(!result.removed)
        for (name, contents) in Self.treeFiles {
            #expect(TestSupport.text(at: TestSupport.path(name, in: outside)) == contents)
        }
    }

    /// A link inside the root whose folder is a symlink to a folder outside
    /// the root gives a correction, and the outside link stays: the link
    /// itself is outside the root, although its target is inside.
    @Test func linkInAFolderOutsideTheRootIsCorrective() async throws {
        let root = TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName)
        let outside = TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName)
        try Self.makeTree(in: root)
        let outsideLink = TestSupport.path(Self.linkName, in: outside)
        try FileManager.default.createSymbolicLink(
            atPath: outsideLink,
            withDestinationPath: TestSupport.path(Self.directoryName, in: root)
        )
        let folderLinkName = "outside"
        try FileManager.default.createSymbolicLink(
            atPath: TestSupport.path(folderLinkName, in: root),
            withDestinationPath: outside.path
        )
        let context = FileContext(root: root, allowSymlinks: true)

        let result = try await Self.removeDirectory(path: "\(folderLinkName)/\(Self.linkName)", in: context)

        #expect(result.correction != nil)
        #expect(!result.removed)
        #expect(Self.isSymlink(outsideLink))
    }

    /// A call on a read-only session gives a correction, and the directory stays.
    @Test func readOnlySessionIsCorrective() async throws {
        let root = TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName)
        try Self.makeTree(in: root)
        let context = FileContext(root: root, readOnly: true)

        let result = try await Self.removeDirectory(path: Self.directoryName, recursive: true, in: context)

        #expect(result.correction != nil)
        #expect(!result.removed)
        #expect(FileWalker.isDirectory(TestSupport.path(Self.directoryName, in: root)))
    }

    // MARK: Change recording

    /// A recursive removal on a recording session records one delete change
    /// for each removed file, with the old content of that file.
    @Test func recordingSessionRecordsADeleteForEachFile() async throws {
        let root = TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName)
        try Self.makeTree(in: root)
        let context = FileContext(root: root, recordsChanges: true)

        let result = try await Self.removeDirectory(path: Self.directoryName, recursive: true, in: context)
        #expect(result.correction == nil)

        let changes = await context.changes.drain().changes
        #expect(changes.count == Self.treeFiles.count)
        #expect(changes.allSatisfy { $0.kind == .delete })
        for (name, contents) in Self.treeFiles {
            let change = try #require(changes.first { $0.path.hasSuffix("/\(name)") })
            #expect(change.oldContent == contents)
            #expect(change.newContent == nil)
        }
    }
}
