// `SnippetWholeOutputTests` — inside a snippet, the result of
// `tools.shell.execute` holds the whole output, not the 32-line tail
// ("Postel's rule": be liberal in what you accept).
//
// checked24 django__django-13710, session 01M77V76GMQNDW5HVXDF4RCQ5K, seq
// 4675…5168: the snippet filtered `r.output` for `^(FAIL|ERROR):`, but
// `r.output` held only the last 32 lines, each "N: text". The FAIL headers
// sat at lines 560–606 of 624, the filter found nothing, and the model ran
// the full suite again, about 9 times. `maxOutputChars: 200000` was ignored
// without a word.

import Foundation
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

@Suite("A snippet reads the whole output of a command", .ownsTemporaryDirectories)
struct SnippetWholeOutputTests {

    /// A command that prints 100 lines, with `FAIL: test_x` at line 10.
    private static let hundredLines =
        #"i=1; while [ $i -le 100 ]; do if [ $i = 10 ]; then echo "FAIL: test_x"; else echo "line $i"; fi; i=$((i+1)); done"#

    private static func run(_ code: String) async throws -> String {
        let root = TestSupport.makeTemporaryDirectory(named: "SnippetWholeOutputTests")
        let registry = try MultiTool.Builder(mode: .open)
            .withShell(storeDirectory: root.appendingPathComponent(".shell"), defaultWorkingDirectory: root)
            .buildRegistry()
        return try await MultiTool(registry: registry).call(arguments: RunCodeArguments(code: code))
    }

    @Test("checked24 13710: filtering r.output for a header finds a line before the tail")
    func filteringOutputFindsAnEarlyLine() async throws {
        let output = try await Self.run(
            #"const r = await tools.shell.execute({ command: \#(Self.jsString(Self.hundredLines)) }); "#
                + #"return r.output.filter(l => /^FAIL:/.test(l));"#)

        #expect(output.hasPrefix(#"["FAIL: test_x"]"#), "output was: \(output)")
    }

    @Test("r.lines holds every line, numbered")
    func linesHoldsEveryLineNumbered() async throws {
        let output = try await Self.run(
            #"const r = await tools.shell.execute({ command: \#(Self.jsString(Self.hundredLines)) }); "#
                + #"return [r.lines.length, r.lines[9], r.output.length, r.text.split("\n").length];"#)

        #expect(output.hasPrefix(#"[100,"10: FAIL: test_x",100,100]"#), "output was: \(output)")
    }

    @Test("a snippet that returns r still gets the 32-line tail")
    func returningTheReportKeepsTheTail() async throws {
        let output = try await Self.run(
            #"const r = await tools.shell.execute({ command: \#(Self.jsString(Self.hundredLines)) }); return r;"#)

        #expect(output.contains(#""lineCount":100"#), "output was: \(output)")
        #expect(output.contains(#""100: line 100""#), "output was: \(output)")
        #expect(!output.contains(#""line 5""#) && !output.contains("FAIL: test_x"), "output was: \(output)")
        #expect(output.contains("outputNote"), "output was: \(output)")
    }

    @Test("checked24 13710: maxOutputChars is not an argument, and the result says so")
    func aMaxOutputArgumentGetsANote() async throws {
        let output = try await Self.run(
            #"const r = await tools.shell.execute({ command: "echo hi", maxOutputChars: 200000 }); return r;"#)

        #expect(output.contains("maxOutputChars"), "output was: \(output)")
        #expect(output.contains("whole output"), "output was: \(output)")
    }

    /// `text` as a JavaScript string literal.
    private static func jsString(_ text: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [text])
        return String(String(data: data, encoding: .utf8)!.dropFirst().dropLast())
    }
}
