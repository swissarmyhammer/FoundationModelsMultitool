// `PythonSnippetTests` — a `runCode` snippet that is plainly Python, and does
// not parse as JavaScript, runs with python3 through `tools.shell.execute`
// ("Postel's rule": be liberal in what you accept).
//
// SWE-bench run bench24-1023b, django__django-14382 (child session, seq
// 11129): the model sent a Python snippet, and it failed with "Unexpected
// identifier 'os'. import call expects one or two arguments."

import Foundation
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

@Suite(.ownsTemporaryDirectories) struct PythonSnippetTests {

    /// The name of the temporary directory of one test.
    private static let testDirectoryName = "PythonSnippetTests"

    /// The snippet of the run, byte for byte.
    private static let basenameSnippet = """
        // Confirm the stdlib behavior that is the crux of the bug (read-only check)
        import os
        results = {}
        for t in ['directory', 'directory/', '/abs/directory/', './directory/']:
            results[t] = {
                'basename': os.path.basename(t),
                'abspath+basename': os.path.basename(os.path.abspath(t)),
            }
        return results
        """

    /// Runs `code` on a surface with the files and shell capabilities.
    private static func run(_ code: String, shell: Bool = true) async throws -> String {
        let root = TestSupport.makeTemporaryDirectory(named: testDirectoryName)
        let store = TestSupport.makeTemporaryDirectory(named: testDirectoryName + "-store")
        var builder = MultiTool.Builder().withFiles(root: root)
        if shell {
            builder = try builder.withShell(storeDirectory: store.appendingPathComponent(".shell"), defaultWorkingDirectory: root)
        }
        return try await MultiTool(registry: try builder.buildRegistry()).call(arguments: RunCodeArguments(code: code))
    }

    /// The rendered value before the note, and the note.
    private static func split(_ output: String) -> (value: String, note: String?) {
        guard let range = output.range(of: "\n\n" + PythonSnippet.note) else { return (output, nil) }
        return (String(output[..<range.lowerBound]), PythonSnippet.note)
    }

    @Test("the snippet of the run returns its basename table, with the note")
    func thePythonSnippetRuns() async throws {
        let output = try await Self.run(Self.basenameSnippet)
        let (value, note) = Self.split(output)

        #expect(note == "This snippet was Python; it ran with python3.", "output was: \(output)")
        let table = try RunOutput.decoded([String: [String: String]].self, from: value)
        #expect(table["directory"]?["basename"] == "directory", "output was: \(output)")
        #expect(table["directory/"]?["basename"] == "", "output was: \(output)")
        #expect(table["/abs/directory/"]?["abspath+basename"] == "directory", "output was: \(output)")
        #expect(table["./directory/"]?["abspath+basename"] == "directory", "output was: \(output)")
    }

    @Test("a Python snippet that raises gives its traceback, with the note")
    func aFailingPythonSnippetGivesItsTraceback() async throws {
        let output = try await Self.run("import os\nraise ValueError('boom')\n")

        #expect(output.contains("ValueError: boom"), "output was: \(output)")
        #expect(output.hasSuffix(PythonSnippet.note), "output was: \(output)")
    }

    @Test("a snippet that parses as JavaScript is never run as Python")
    func aJavaScriptSnippetIsNotPython() async throws {
        let output = try await Self.run("const os = 1;\nreturn os + 1;")

        #expect(try RunOutput.decoded(Int.self, from: output) == 2, "output was: \(output)")
        #expect(!output.contains(PythonSnippet.note))
    }

    @Test("with no shell, a Python snippet gives the parse error as before")
    func withNoShellTheParseErrorStands() async throws {
        let output = try await Self.run(Self.basenameSnippet, shell: false)

        #expect(output.contains("The snippet failed"), "output was: \(output)")
        #expect(!output.contains(PythonSnippet.note))
    }

    @Test("the heuristic: Python lines and no JavaScript declarations")
    func theHeuristic() {
        #expect(PythonSnippet.looksLikePython(Self.basenameSnippet))
        #expect(PythonSnippet.looksLikePython("from os import path\nreturn path.sep"))
        #expect(PythonSnippet.looksLikePython("def f(x):\n    return x\nreturn f(1)"))
        #expect(!PythonSnippet.looksLikePython("import os\nconst x = await tools.files.read('a');"))
        #expect(!PythonSnippet.looksLikePython("return {{{ ]]] ;;; ((("))
        #expect(!PythonSnippet.looksLikePython("for (const x of xs) { y(x) }"))
    }
}
