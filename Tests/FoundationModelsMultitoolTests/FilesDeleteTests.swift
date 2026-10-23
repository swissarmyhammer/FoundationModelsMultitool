// `FilesDeleteTests` — the behavioral suite of the `tools.files.delete` verb.
//
// SWE-bench run bench24-1023b, django__django-13933 seq 4183: the model
// called `tools.files.delete({ path })` to remove a scratch test file it had
// made. There was no such verb, and the failure took the rest of the snippet
// (a test run) down with it, so seq 4186 ran the same tests again. Each test
// here runs a snippet through `MultiTool.call(arguments:)`, the path that
// snippet took.

import Foundation
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

@Suite(.ownsTemporaryDirectories) struct FilesDeleteTests {

    /// The name of the temporary directory of one test, thus a leaked
    /// directory is traceable to this suite.
    private static let testDirectoryName = "FilesDeleteTests"

    /// The scratch test file the model made and then deleted.
    private static let scratchPath = "tests/admin_widgets/test_debug_response.py"

    /// The part of a delete result these tests read.
    private struct DeleteValue: Decodable {
        let deleted: Bool
        let correction: String?
    }

    /// A session root that holds the scratch test file.
    private static func makeRoot() throws -> URL {
        let root = TestSupport.makeTemporaryDirectory(named: testDirectoryName)
        try write("import unittest\n", to: scratchPath, in: root)
        return root
    }

    /// Writes `content` to `path` under `root`, with its folders.
    private static func write(_ content: String, to path: String, in root: URL) throws {
        let url = root.appendingPathComponent(path, isDirectory: false)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: url)
    }

    /// Whether anything is at `path` under `root`.
    private static func exists(_ path: String, in root: URL) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path)
    }

    /// Runs one snippet against a surface with the files and shell
    /// capabilities, both rooted at `root`.
    private static func run(
        _ code: String, root: URL, readOnly: Bool = false, excludePatterns: [String] = []
    ) async throws -> String {
        let store = TestSupport.makeTemporaryDirectory(named: testDirectoryName + "-store")
        let registry = try MultiTool.Builder()
            .withFiles(root: root, readOnly: readOnly, excludePatterns: excludePatterns)
            .withShell(storeDirectory: store.appendingPathComponent(".shell"), defaultWorkingDirectory: root)
            .buildRegistry()
        return try await MultiTool(registry: registry).call(arguments: RunCodeArguments(code: code))
    }

    /// Runs one `tools.files.delete` call and decodes its result.
    private static func delete(
        _ call: String, root: URL, readOnly: Bool = false, excludePatterns: [String] = []
    ) async throws -> DeleteValue {
        let output = try await run(
            "const d = await tools.files.delete(\(call)); return { deleted: d.deleted, correction: d.correction ?? null };",
            root: root, readOnly: readOnly, excludePatterns: excludePatterns)
        return try RunOutput.decoded(DeleteValue.self, from: output)
    }

    // MARK: - The snippet of the run

    /// The value of the delete-then-run snippet.
    private struct SnippetValue: Decodable {
        let deleted: Bool
        let ran: [String]
    }

    @Test("the snippet of the run deletes the scratch file and goes on to its test run")
    func theSnippetOfTheRunDeletesAndGoesOn() async throws {
        let root = try Self.makeRoot()

        let output = try await Self.run(
            #"""
            const d = await tools.files.delete({ path: "tests/admin_widgets/test_debug_response.py" });
            const run = await tools.shell.execute({ command: "test ! -e tests/admin_widgets/test_debug_response.py && echo gone" });
            return { deleted: d.deleted, ran: run.output };
            """#, root: root)

        #expect(!output.contains("is not a function"), "output was: \(output)")
        let value = try RunOutput.decoded(SnippetValue.self, from: output)
        #expect(value.deleted)
        #expect(value.ran.contains { $0.hasSuffix("gone") }, "output was: \(output)")
        #expect(!Self.exists(Self.scratchPath, in: root))
    }

    // MARK: - Corrections

    @Test("a missing path answers a correction, and the snippet goes on")
    func aMissingPathIsCorrective() async throws {
        let root = try Self.makeRoot()

        let value = try await Self.delete(#"{ path: "no/such/file.py" }"#, root: root)

        #expect(!value.deleted)
        #expect(value.correction != nil)
    }

    @Test("a path outside the root answers a correction and deletes nothing")
    func aPathOutsideTheRootIsCorrective() async throws {
        let root = try Self.makeRoot()
        let outside = TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName + "-outside")
        try Self.write("keep\n", to: "keep.txt", in: outside)

        let value = try await Self.delete(
            "{ path: \"\(outside.appendingPathComponent("keep.txt").path)\" }", root: root)

        #expect(!value.deleted)
        #expect(value.correction != nil)
        #expect(Self.exists("keep.txt", in: outside))
    }

    @Test("a file inside .git answers a correction and stays")
    func aGitInternalIsCorrective() async throws {
        let root = try Self.makeRoot()
        try Self.write("[core]\n", to: ".git/config", in: root)

        let value = try await Self.delete(#"{ path: ".git/config" }"#, root: root)

        #expect(!value.deleted)
        #expect(value.correction != nil)
        #expect(Self.exists(".git/config", in: root))
    }

    @Test("a file the host exclude patterns name answers a correction and stays")
    func anExcludedFileIsCorrective() async throws {
        let root = try Self.makeRoot()
        try Self.write("{}\n", to: ".acp-agent/state.json", in: root)

        let value = try await Self.delete(
            #"{ path: ".acp-agent/state.json" }"#, root: root, excludePatterns: [".acp-agent/"])

        #expect(!value.deleted)
        #expect(value.correction != nil)
        #expect(Self.exists(".acp-agent/state.json", in: root))
    }

    @Test("a read-only session answers a correction and deletes nothing")
    func aReadOnlySessionIsCorrective() async throws {
        let root = try Self.makeRoot()

        let value = try await Self.delete("{ path: \"\(Self.scratchPath)\" }", root: root, readOnly: true)

        #expect(!value.deleted)
        #expect(value.correction != nil)
        #expect(Self.exists(Self.scratchPath, in: root))
    }

    // MARK: - Directories

    @Test("a directory needs directory: true, and then only an empty one is deleted")
    func aDirectoryNeedsTheFlag() async throws {
        let root = try Self.makeRoot()
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("empty"), withIntermediateDirectories: false)

        let withoutFlag = try await Self.delete(#"{ path: "empty" }"#, root: root)
        let notEmpty = try await Self.delete(#"{ path: "tests", directory: true }"#, root: root)
        let empty = try await Self.delete(#"{ path: "empty", directory: true }"#, root: root)

        #expect(!withoutFlag.deleted && withoutFlag.correction != nil)
        #expect(!notEmpty.deleted && notEmpty.correction != nil)
        #expect(Self.exists(Self.scratchPath, in: root))
        #expect(empty.deleted && empty.correction == nil)
        #expect(!Self.exists("empty", in: root))
    }

    // MARK: - Synonyms

    @Test(
        "each usual other name of a delete deletes the file",
        arguments: ["files.remove", "files.rm", "files.unlink", "files.del", "files.deleteFile", "rm", "delete"])
    func eachSynonymDeletes(name: String) async throws {
        let root = try Self.makeRoot()

        let output = try await Self.run(
            "const d = await tools.\(name)({ path: \"\(Self.scratchPath)\" }); return d.deleted;", root: root)

        #expect(output == "true", "output was: \(output)")
        #expect(!Self.exists(Self.scratchPath, in: root))
    }

    @Test("files.rmdir removes an empty directory")
    func rmdirRemovesAnEmptyDirectory() async throws {
        let root = try Self.makeRoot()
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("empty"), withIntermediateDirectories: false)

        let output = try await Self.run(#"return (await tools.files.rmdir({ path: "empty" })).removed;"#, root: root)

        #expect(output == "true", "output was: \(output)")
        #expect(!Self.exists("empty", in: root))
    }
}
