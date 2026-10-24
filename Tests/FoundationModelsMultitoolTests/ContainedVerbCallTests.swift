// `ContainedVerbCallTests` — a made-up verb name that holds one real read
// verb of its group calls that verb ("Postel's rule": be liberal in what you
// accept).
//
// SWE-bench run bench24-1023b, django__django-14382 (root transcript, seq
// 10955): `tools.files.listDir({ path: "tests" })` failed with
// "tools.files.listDir is not a function".

import Foundation
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

@Suite(.ownsTemporaryDirectories) struct ContainedVerbCallTests {

    /// The name of the temporary directory of one test.
    private static let testDirectoryName = "ContainedVerbCallTests"

    /// Runs `code` against a files surface whose root holds `tests/a.py`,
    /// `tests/b.py`, and `keep.txt`.
    private static func run(_ code: String) async throws -> (output: String, root: URL) {
        let root = TestSupport.makeTemporaryDirectory(named: testDirectoryName)
        for path in ["tests/a.py", "tests/b.py", "keep.txt"] {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("x\n".utf8).write(to: url)
        }
        let registry = try MultiTool.Builder().withFiles(root: root).buildRegistry()
        return (try await MultiTool(registry: registry).call(arguments: RunCodeArguments(code: code)), root)
    }

    @Test("the snippet of the run: files.listDir lists the directory")
    func listDirLists() async throws {
        let (output, _) = try await Self.run(#"return (await tools.files.listDir({ path: "tests" })).entries;"#)

        #expect(!output.contains("is not a function"), "output was: \(output)")
        #expect(try RunOutput.decoded([String].self, from: output) == ["a.py", "b.py"], "output was: \(output)")
    }

    @Test(
        "each usual made-up name of a directory listing lists",
        arguments: ["listdir", "readDir", "readdir", "lsDir", "listDirectory", "dir", "listFolder", "listEntries"])
    func eachListNameLists(name: String) async throws {
        let (output, _) = try await Self.run(#"return (await tools.files.\#(name)({ path: "tests" })).entries;"#)

        #expect(try RunOutput.decoded([String].self, from: output) == ["a.py", "b.py"], "output was: \(output)")
    }

    @Test("a made-up name that holds a verb that changes files is not called")
    func aDestructiveContainedVerbIsNotCalled() async throws {
        let (output, root) = try await Self.run(#"return await tools.files.deleteAllFiles({ path: "keep.txt" });"#)

        #expect(output.contains("is not a function"), "output was: \(output)")
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("keep.txt").path))
    }
}
