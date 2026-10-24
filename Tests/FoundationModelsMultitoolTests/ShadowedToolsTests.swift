// `ShadowedToolsTests` — a snippet that declares its own `tools` still
// reaches the tool namespace ("Postel's rule": be liberal in what you
// accept).
//
// SWE-bench run bench24-1023b, django__django-14787 (seq 19546): `const tools
// = await tools.files.list(...)` put the global in the temporal dead zone for
// the whole snippet: "Cannot access 'tools' before initialization."

import Foundation
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

@Suite("ShadowedToolsTests")
struct ShadowedToolsTests {

    /// The snippet of the run, byte for byte.
    private static let shadowingSnippet = """
        const root = await tools.files.list({});
        const lib = await tools.files.list({ path: "Lib" });
        const tools = await tools.files.list({ path: "Tools" });
        return { root: root.entries, lib: lib.entries.slice(0, 40), tools: tools.entries.slice(0, 40), libCorr: lib.correction, toolsCorr: tools.correction };
        """

    private struct Answer: Decodable {
        let root: [String]
        let lib: [String]
        let tools: [String]
        let libCorr: String?
        let toolsCorr: String?
    }

    private static let paths = ["files.list", "files.read", "shell.execute"]

    /// Runs `code` with the files group over a root with `Lib/` and `Tools/`.
    private static func run(_ code: String) async throws -> String {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for file in ["Lib/a.py", "Tools/b.py"] {
            let url = root.appendingPathComponent(file)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("x\n".utf8).write(to: url)
        }
        let registry = try MultiTool.Builder().withFiles(root: root).buildRegistry()
        return try await MultiTool(registry: registry).call(arguments: RunCodeArguments(code: code))
    }

    /// The rendered value before the note, and the note.
    private static func split(_ output: String) -> (value: String, note: String?) {
        guard let range = output.range(of: "\n\n" + ShadowedTools.note) else { return (output, nil) }
        return (String(output[..<range.lowerBound]), ShadowedTools.note)
    }

    @Test("the snippet of the run lists all three directories")
    func theSnippetOfTheRunRuns() async throws {
        let output = try await Self.run(Self.shadowingSnippet)
        let (value, note) = Self.split(output)
        let answer = try RunOutput.decoded(Answer.self, from: value)

        #expect(answer.lib == ["a.py"], "output was: \(output)")
        #expect(answer.tools == ["b.py"], "output was: \(output)")
        #expect(answer.root.contains("Lib/") && answer.root.contains("Tools/"), "output was: \(output)")
        #expect(answer.libCorr == nil && answer.toolsCorr == nil, "output was: \(output)")
        #expect(note == ShadowedTools.note, "output was: \(output)")
    }

    @Test("only the namespace calls are rewritten; the model's own uses and keys stay")
    func onlyNamespaceCallsAreRewritten() {
        let rewritten = ShadowedTools.rewrite(Self.shadowingSnippet, paths: Self.paths)

        #expect(
            rewritten == """
                const root = await globalThis.tools.files.list({});
                const lib = await globalThis.tools.files.list({ path: "Lib" });
                const tools = await globalThis.tools.files.list({ path: "Tools" });
                return { root: root.entries, lib: lib.entries.slice(0, 40), tools: tools.entries.slice(0, 40), libCorr: lib.correction, toolsCorr: tools.correction };
                """)
    }

    @Test(
        "each way to bind tools is seen",
        arguments: [
            "let tools = 1;", "var tools = 1;", "function tools() {}", "class tools {}",
            "const { tools } = x;", "const { a, b: tools } = x;", "const [a, tools] = x;", "const { ...tools } = x;",
        ])
    func eachBindingIsSeen(declaration: String) {
        let code = "const r = await tools.files.list({});\n" + declaration
        #expect(ShadowedTools.rewrite(code, paths: Self.paths)?.hasPrefix("const r = await globalThis.tools.files.list") == true)
    }

    @Test(
        "a snippet that binds no tools is not touched",
        arguments: [
            "return await tools.files.list({});",
            "const { tools: t } = x; return await tools.files.list({});",
            #"const s = "const tools = 1"; return await tools.files.list({});"#,
            "// const tools = 1\nreturn await tools.files.list({});",
            "return { tools: await tools.files.list({}) };",
        ])
    func aSnippetThatBindsNoToolsIsNotTouched(code: String) {
        #expect(ShadowedTools.rewrite(code, paths: Self.paths) == nil)
    }

    @Test("after the declaration, a field of the model's own tools is not taken for a group")
    func aFieldOfTheModelsToolsStays() {
        // `files` is a group, but `map` is no verb of it, thus this is the
        // model's own value.
        let code = """
            const tools = await tools.files.list({});
            return [tools.files.map((f) => f), await tools.files.read({ path: "a" })];
            """
        #expect(
            ShadowedTools.rewrite(code, paths: Self.paths) == """
                const tools = await globalThis.tools.files.list({});
                return [tools.files.map((f) => f), await globalThis.tools.files.read({ path: "a" })];
                """)
    }

    @Test("a tools inside a string, a template, a comment, or a regex is never rewritten")
    func literalsAreSkipped() {
        let code = """
            const tools = 1;
            const a = "tools.files.list(";
            const b = `tools.files.list( ${await tools.files.list({})}`;
            /* tools.files.list( */
            const c = /tools.files.list\\(/;
            """
        #expect(
            ShadowedTools.rewrite(code, paths: Self.paths) == """
                const tools = 1;
                const a = "tools.files.list(";
                const b = `tools.files.list( ${await globalThis.tools.files.list({})}`;
                /* tools.files.list( */
                const c = /tools.files.list\\(/;
                """)
    }
}
