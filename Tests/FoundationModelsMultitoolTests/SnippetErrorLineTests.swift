// `SnippetErrorLineTests` — the "(line N)" of a snippet error counts the lines
// of the model's own snippet, not those of the preamble before it.
//
// SWE-bench run bench24-1023b: each snippet error carried a line in the
// 113–124 range for snippets of 1–5 lines, e.g. "Expected ')' to end an
// argument list. (line 116)" where the bad line was 2 (django__django-14017,
// seq 7751). The model got a line that does not exist in its code.

import Foundation
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

@Suite("SnippetErrorLineTests")
struct SnippetErrorLineTests {

    /// Runs `code` on a surface with the stand-in `code_context` group.
    private func run(_ code: String) async throws -> String {
        let registry = try MultiTool.Builder()
            .addGroup(named: "code_context", [RepairGrepCodeTool()])
            .buildRegistry()
        return try await MultiTool(registry: registry).call(arguments: RunCodeArguments(code: code))
    }

    @Test("a parse error on line 2 of 3 reports line 2")
    func aParseErrorReportsTheSnippetLine() async throws {
        let output = try await run(
            """
            const a = 1;
            const b = ((((;
            return a;
            """)

        #expect(output.contains("The snippet failed"), "output was: \(output)")
        #expect(output.contains("(line 2)"), "output was: \(output)")
    }

    @Test("a thrown TypeError on line 2 of 3 reports line 2")
    func aTypeErrorReportsTheSnippetLine() async throws {
        let output = try await run(
            """
            const a = null;
            const b = a.missing.deeper;
            return b;
            """)

        #expect(output.contains("null is not an object"), "output was: \(output)")
        #expect(output.contains("(line 2)"), "output was: \(output)")
    }

    @Test("a one-line snippet calling a missing tool reports line 1")
    func aMissingToolReportsLineOne() async throws {
        let output = try await run("return await tools.nope.nothing();")

        #expect(output.contains("(line 1)"), "output was: \(output)")
    }

    @Test("the snippet line maps back, and a line outside the snippet is left out")
    func theLineMapping() {
        let preamble = "a;\nb;\nc;"
        let code = "x;\ny;"
        // The preamble has 3 lines, then the snippet starts on line 4.
        #expect(MultiTool.snippetLine(ofWrappedLine: 4, code: code, preamble: preamble) == 1)
        #expect(MultiTool.snippetLine(ofWrappedLine: 5, code: code, preamble: preamble) == 2)
        #expect(MultiTool.snippetLine(ofWrappedLine: 2, code: code, preamble: preamble) == nil)
        #expect(MultiTool.snippetLine(ofWrappedLine: 6, code: code, preamble: preamble) == nil)
        #expect(MultiTool.snippetLine(ofWrappedLine: nil, code: code, preamble: preamble) == nil)
    }
}
