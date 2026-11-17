// `FolderFilesTests` — the behavioral suite of the public folder listing:
// the files of a folder that the ignore rules of git do not exclude, read
// through libgit2, and the plain walk outside a repository.

import Foundation
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Behavioral tests for ``FolderFiles``.
@Suite(.ownsTemporaryDirectories) struct FolderFilesTests {

    /// Writes a short text to the file at `path` below `root`, and makes each
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

    /// Makes a new temporary folder with the files at `paths`.
    ///
    /// - Parameter paths: The files to write, relative to the folder.
    /// - Returns: The folder.
    private static func makeFolder(_ paths: [String]) throws -> URL {
        let root = TestSupport.canonicalDirectory(TestSupport.makeTemporaryDirectory(named: "FolderFilesTests"))
        for path in paths {
            try writeFile(path, in: root)
        }
        return root
    }

    /// Makes a repository that ignores `node_modules/` and `.build/`, with a
    /// tracked file, an untracked file, ignored files and hidden files.
    ///
    /// - Returns: The work folder.
    private static func makeRepository() throws -> URL {
        let root = try makeFolder(["Sources/App.swift", "README.md"])
        try GitFixture.initRepository(at: root)
        try "node_modules/\n.build/\n".write(
            to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        try GitFixture.stageAll(in: root)
        for path in ["Sources/New.swift", "node_modules/pkg/index.js", ".build/debug/app", ".github/ci.yml"] {
            try writeFile(path, in: root)
        }
        return root
    }

    @Test("in a repository, the ignored folders are not in the list, and the paths are sorted and relative")
    func aRepositorySkipsTheIgnoredFolders() async throws {
        let root = try Self.makeRepository()

        let files = await FolderFiles.list(in: root)

        #expect(files == ["README.md", "Sources/App.swift", "Sources/New.swift"])
    }

    @Test("with includeHidden, the hidden files that git does not ignore are in the list, and no .git file")
    func includeHiddenGivesTheHiddenFiles() async throws {
        let root = try Self.makeRepository()

        let files = await FolderFiles.list(in: root, includeHidden: true)

        #expect(files == [".github/ci.yml", ".gitignore", "README.md", "Sources/App.swift", "Sources/New.swift"])
    }

    @Test("a sub folder of a repository gives its files relative to the sub folder")
    func aSubFolderOfARepository() async throws {
        let root = try Self.makeRepository()

        let files = await FolderFiles.list(in: root.appendingPathComponent("Sources", isDirectory: true))

        #expect(files == ["App.swift", "New.swift"])
    }

    @Test("outside a repository, the list holds each file, and hidden files only with includeHidden")
    func outsideARepository() async throws {
        let root = try Self.makeFolder(["a.txt", "sub/b.txt", ".env", ".hidden/c.txt"])

        let visible = await FolderFiles.list(in: root)
        let all = await FolderFiles.list(in: root, includeHidden: true)

        #expect(visible == ["a.txt", "sub/b.txt"])
        #expect(all == [".env", ".hidden/c.txt", "a.txt", "sub/b.txt"])
    }

    @Test("a folder that does not exist gives an empty list")
    func aMissingFolder() async {
        let missing = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)", isDirectory: true)

        #expect(await FolderFiles.list(in: missing).isEmpty)
    }
}
