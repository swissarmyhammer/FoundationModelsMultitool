// `GroupAliasBindingTests` — a group name the model makes up for the file
// verbs, and a verb under a made-up group, still call the verb they mean
// ("Postel's rule": be liberal in what you accept).
//
// dotask24 and kanban24 (2026-11-08):
// - dotask24 13447 seq 43: `tools.fs.list(...)`; kanban24 13447 seq 472:
//   `tools.fs.readFile(...)`.
// - kanban24 13447 seq 687: `const fs = await tools.code_context.fs;
//   fs.listDir(...)` failed with `undefined is not an object`.
// - kanban24 14017 seq 5238: `tools.code_context.readFile(...)`.
// - dotask24 14534 seq 9451: `tools.search.grep(...)`.

import Foundation
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

@Suite(.ownsTemporaryDirectories) struct GroupAliasBindingTests {

    /// Runs `code` on a surface with the files capability and a `web` group
    /// whose one verb is `search`, over a root with `a.txt`.
    private static func run(_ code: String) async throws -> String {
        let root = TestSupport.makeTemporaryDirectory(named: "GroupAliasBindingTests")
        try Data("hello\nlabel = 1\n".utf8).write(to: root.appendingPathComponent("a.txt"))
        let registry = try MultiTool.Builder(mode: .open)
            .withFiles(root: root)
            .addGroup(named: "web", [CatalogEntryTool(name: "search", description: "Searches the web.")])
            .addGroup(named: "code_context", [CatalogEntryTool(name: "grepCode", description: "Greps code.")])
            .buildRegistry()
        return try await MultiTool(registry: registry).call(arguments: RunCodeArguments(code: code))
    }

    @Test("tools.fs is the files group: fs.list, fs.readFile and fs.listDir call files.list and files.read")
    func fsIsTheFilesGroup() async throws {
        let output = try await Self.run(
            #"""
            const a = await tools.fs.list({ path: "." }); const b = await tools.fs.readFile({ path: "a.txt" });
            const c = await tools.fileSystem.listDir({ path: "." });
            return [a.entries.map(String), b.slice(0, 5), c.entries.length];
            """#)

        #expect(output.contains(#"[["a.txt"],"hello",1]"#), "output was: \(output)")
    }

    @Test("a group name under another group is that group: code_context.fs.listDir")
    func aGroupUnderAGroupIsThatGroup() async throws {
        let output = try await Self.run(
            #"const fs = await tools.code_context.fs; return (await fs.listDir({ path: "." })).entries.map(String);"#)

        #expect(output.contains(#"["a.txt"]"#), "output was: \(output)")
    }

    @Test("a file read verb under another group calls the files verb: code_context.readFile")
    func aReadVerbUnderAnotherGroupCallsFiles() async throws {
        let output = try await Self.run(#"return (await tools.code_context.readFile({ path: "a.txt" })).slice(0, 5);"#)

        #expect(output.contains(#""hello""#), "output was: \(output)")
    }

    @Test("a verb under a made-up group calls the verb: search.grep is files.grep")
    func aVerbUnderAMadeUpGroupCallsTheVerb() async throws {
        let output = try await Self.run(
            #"return (await tools.search.grep({ pattern: "label", path: "a.txt" })).matches.filter((m) => m.isMatch).map((m) => m.lineNumber);"#)

        #expect(output.contains("[2]"), "output was: \(output)")
    }
}
