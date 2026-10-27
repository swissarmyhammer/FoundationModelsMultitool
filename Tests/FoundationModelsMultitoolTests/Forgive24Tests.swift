// `Forgive24Tests` — two more plain mistakes of a model that a `tools.*` call
// accepts ("Postel's rule": be liberal in what you accept).
//
// SWE-bench check bench forgive24 (Multitool 3c5a056), django__django-13447:
// 6. seq 431: `r.matches.map(m => `${m.lineNumber}: ${m.line.slice(0,110)}`)`
//    on a `files.grep` result threw `m.line.slice is not a function`: `line`
//    is the number of the line, and the model read it as its text.
// 7. seq 459: `tools.files.exists({ path: ".venv/bin/python" })` is not a
//    function, and the hint named `tools.files.edit`, a verb that writes.

import Foundation
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

@Suite(.ownsTemporaryDirectories) struct Forgive24Tests {

    /// The name of the temporary directory of one test.
    private static let testDirectoryName = "Forgive24Tests"

    /// Runs `code` on a surface with the files and shell capabilities, over a
    /// root with a `tests/runtests.py` that holds two `label` lines.
    private static func run(_ code: String) async throws -> String {
        let root = TestSupport.makeTemporaryDirectory(named: testDirectoryName)
        let url = root.appendingPathComponent("tests/runtests.py")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("import sys\nlabel = 'a'\nprint(label)\n".utf8).write(to: url)
        let store = TestSupport.makeTemporaryDirectory(named: testDirectoryName + "-store")
        let registry = try MultiTool.Builder()
            .withFiles(root: root)
            .withShell(storeDirectory: store.appendingPathComponent(".shell"), defaultWorkingDirectory: root)
            .buildRegistry()
        return try await MultiTool(registry: registry).call(arguments: RunCodeArguments(code: code))
    }

    // MARK: 6. The line of a grep match

    @Test("the snippet of seq 431: a match's line answers string methods over its text")
    func aMatchLineReadsAsItsText() async throws {
        let output = try await Self.run(
            #"""
            const r = await tools.files.grep({ pattern: "label", path: "tests/runtests.py", maxResults: 40 });
            return r.matches.map(m => `${m.lineNumber}: ${m.line.slice(0,110)}`);
            """#)

        let lines = try RunOutput.decoded([String].self, from: output)
        #expect(lines.contains("2: label = 'a'") && lines.contains("3: print(label)"), "output was: \(output)")
    }

    @Test("a match's line still counts and serializes as its number")
    func aMatchLineStaysItsNumber() async throws {
        let output = try await Self.run(
            #"""
            const r = await tools.files.grep({ pattern: "label", path: "tests/runtests.py" });
            const m = r.matches.find((x) => x.isMatch);
            return [m.line + 1, m.line > 1, Number(m.line), JSON.parse(JSON.stringify(m)).line];
            """#)

        #expect(output.contains("[3,true,2,2]"), "output was: \(output)")
    }

    @Test("a match's line stays a plain number: ===, typeof, Object.is, Set and Map keys")
    func aMatchLineIsAPlainNumber() async throws {
        let output = try await Self.run(
            #"""
            const r = await tools.files.grep({ pattern: "label", path: "tests/runtests.py" });
            const m = r.matches.find((x) => x.isMatch);
            const lines = r.matches.map((x) => x.line);
            return [m.line === 2, typeof m.line, Object.is(m.line, 2), new Set([...lines, ...lines]).size,
              new Map([[m.line, "a"]]).get(2), r.matches.find((x) => x.line === 3).text, (m.line - 2) ? "truthy" : "falsy"];
            """#)

        #expect(output.contains(#"[true,"number",true,3,"a","print(label)","falsy"]"#), "output was: \(output)")
    }

    @Test("a string method on a number that is no line reads the number as its digits")
    func aStringMethodOnAPlainNumberReadsItsDigits() async throws {
        let output = try await Self.run(#"return [(82).slice(0, 1), (1234).padStart(6, "0")];"#)

        #expect(output.contains(#"["8","001234"]"#), "output was: \(output)")
    }

    // MARK: 7. files.exists

    @Test("the snippet of seq 459: files.exists answers true or false")
    func filesExistsAnswersABoolean() async throws {
        let output = try await Self.run(
            #"""
            return [await tools.files.exists({ path: ".venv/bin/python" }), await tools.files.exists({ path: "tests/runtests.py" }),
              await tools.files.exists("tests"), await tools.files.isFile({ path: "tests" }), await tools.files.isDir({ path: "tests" }),
              await tools.files.isFile({ file: "tests/runtests.py" }), await tools.fileExists({ path: "nope.txt" })];
            """#)

        #expect(output.contains("[false,true,true,false,true,true,false]"), "output was: \(output)")
    }

    @Test("files.stat answers whether the path is there, and what it is")
    func filesStatAnswersAnObject() async throws {
        let output = try await Self.run(
            #"""
            const s = await tools.files.stat({ path: "tests/runtests.py" });
            const n = await tools.files.stat({ path: "missing/deep/file.py" });
            return [s.exists, s.isFile, s.isDirectory, n.exists];
            """#)

        #expect(output.contains("[true,true,false,false]"), "output was: \(output)")
    }

    @Test("a made-up verb that asks a question is never pointed at a verb that writes")
    func aQuestionIsNotHintedAtAWrite() async throws {
        // `existsAt` resembles `edit` by its trigrams, as `exists` did.
        let output = try await Self.run(#"return await tools.files.existsAt({ path: "a.py" });"#)

        #expect(output.contains("files.existsAt"), "output was: \(output)")
        for writer in ["files.edit", "files.write", "files.delete", "files.patch", "files.makeDirectory", "files.removeDirectory"] {
            #expect(!output.contains("tools.\(writer)"), "output was: \(output)")
        }
    }
}
