// `EmptyListResultTests` — a list-shaped result with no match reads as an
// empty list, and each match answers the field names of the other search
// verb ("Postel's rule": be liberal in what you accept).
//
// SWE-bench run bench24-1023b, django__django-14608 (seq 15808): `files.grep`
// on a file with no match answered `matches: null`, thus `r2.matches.map(...)`
// threw "null is not an object" and the good `grepCode` call was lost too.

import Foundation
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

@Suite("EmptyListResultTests")
struct EmptyListResultTests {

    /// The snippet of the run; the run elided the first mapper, which here
    /// reads the same names as the second.
    private static func snippet(path: String) -> String {
        """
        const r1 = await tools.code_context.grepCode({ pattern: "self\\\\._non_form_errors = ", filePattern: "django/forms/formsets.py", maxResults: 10 });
        const r2 = await tools.files.grep({ pattern: "ErrorList|non_form_errors", path: "\(path)", maxResults: 30 });
        return { r1: r1.matches.map(m=>({f:m.file, l:m.line, t:m.text})), r2: r2.matches.map(m=>({f:m.file, l:m.line, t:m.text})) };
        """
    }

    private struct Row: Decodable, Equatable {
        let f: String
        let l: Int
        let t: String
    }

    private struct Answer: Decodable {
        let r1: [Row]
        let r2: [Row]
    }

    /// Runs `code` with the files group over a root that holds a
    /// `docs/ref/forms.txt` with no match, beside the stand-in `grepCode`.
    private static func run(_ code: String) async throws -> String {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = root.appendingPathComponent("docs/ref/forms.txt")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("Forms\n=====\n".utf8).write(to: url)
        let registry = try MultiTool.Builder()
            .withFiles(root: root)
            .addGroup(named: "code_context", [RepairMatchesTool()])
            .buildRegistry()
        return try await MultiTool(registry: registry).call(arguments: RunCodeArguments(code: code))
    }

    @Test("the snippet of the run, on a file with no match, gives r2: []")
    func noMatchGivesAnEmptyList() async throws {
        let output = try await Self.run(Self.snippet(path: "docs/ref/forms.txt"))
        let answer = try RunOutput.decoded(Answer.self, from: output)

        #expect(answer.r1 == [Row(f: "tests/x.py", l: 1, t: #"self\._non_form_errors = "#)], "output was: \(output)")
        #expect(answer.r2 == [], "output was: \(output)")
    }

    @Test("the snippet of the run, on a path that is not there, gives r2: []")
    func aMissingPathGivesAnEmptyList() async throws {
        let output = try await Self.run(Self.snippet(path: "docs/ref/nothere.txt"))
        let answer = try RunOutput.decoded(Answer.self, from: output)

        #expect(answer.r2 == [], "output was: \(output)")
    }

    @Test("a missing path still says why, beside the empty list")
    func aMissingPathKeepsItsCorrection() async throws {
        let output = try await Self.run(
            #"const r = await tools.files.grep({ pattern: "x", path: "nothere.txt" }); return { n: r.matches.length, c: r.correction };"#)

        #expect(output.contains(#""n":0"#) || output.contains(#""n" : 0"#), "output was: \(output)")
        #expect(output.contains("nothere"), "output was: \(output)")
    }

    @Test("a files.grep match answers the names of a grepCode match")
    func aGrepMatchAnswersOtherNames() async throws {
        let output = try await Self.run(
            #"const r = await tools.files.grep({ pattern: "Forms", path: "docs" }); const m = r.matches[0]; return [m.filePath, m.path, String(m.startLine), String(m.lineNumber)];"#)

        #expect(
            try RunOutput.decoded([String].self, from: output) == ["docs/ref/forms.txt", "docs/ref/forms.txt", "1", "1"],
            "output was: \(output)")
    }
}
