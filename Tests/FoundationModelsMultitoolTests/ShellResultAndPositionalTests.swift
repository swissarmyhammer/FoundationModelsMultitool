// `ShellResultAndPositionalTests` — three more plain mistakes of a model that
// a `tools.*` call accepts ("Postel's rule": be liberal in what you accept).
//
// SWE-bench run bench24-1023b, django__django-14534:
// 1. seq 13568: `r.stdout.slice(-3000)` on a `shell.execute` result, and
//    `cwd` for `workingDirectory`. The tests ran, the snippet threw, and the
//    model ran the same tests again.
// 2. seq 13418: `tools.files.read("…", { offset: 670, limit: 70 })`, a path
//    and then an options object.
// 3. The error of (2) named `tools.name`, the placeholder of the message, and
//    the hint then sent the model to an unrelated verb.

import Foundation
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

@Suite(.ownsTemporaryDirectories) struct ShellResultAndPositionalTests {

    /// The name of the temporary directory of one test.
    private static let testDirectoryName = "ShellResultAndPositionalTests"

    /// A root with a `tests/runtests.py` that prints a test summary, and a
    /// 100-line `tests/forms_tests/tests/test_forms.py`.
    private static func makeRoot() throws -> URL {
        let root = TestSupport.makeTemporaryDirectory(named: testDirectoryName)
        let files = [
            "tests/runtests.py": "import sys\nprint('Ran 3 tests')\nprint('OK')\nsys.stderr.write('warn\\n')\n",
            "tests/forms_tests/tests/test_forms.py": (1...100).map { "line \($0)" }.joined(separator: "\n") + "\n",
        ]
        for (path, content) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(content.utf8).write(to: url)
        }
        return root
    }

    /// Runs `code` on a surface with the files and shell capabilities.
    private static func run(_ code: String) async throws -> String {
        try await run { _ in code }
    }

    /// Runs the code `code` makes from the root on a surface with the files
    /// and shell capabilities.
    private static func run(_ code: (URL) -> String) async throws -> String {
        let root = try makeRoot()
        let store = TestSupport.makeTemporaryDirectory(named: testDirectoryName + "-store")
        let registry = try MultiTool.Builder()
            .withFiles(root: root)
            .withShell(storeDirectory: store.appendingPathComponent(".shell"), defaultWorkingDirectory: root)
            .buildRegistry()
        return try await MultiTool(registry: registry).call(arguments: RunCodeArguments(code: code(root)))
    }

    /// The value of the snippet of seq 13568.
    private struct TestRunValue: Decodable {
        let status: String
        let out: String
        let err: String
    }

    @Test("the snippet of seq 13568 reads stdout and stderr, with cwd for workingDirectory")
    func aShellResultHasStdout() async throws {
        // `python3` for the model's `python`, which this host does not have.
        let output = try await Self.run(
            """
            const r = await tools.shell.execute({ command: "python3 tests/runtests.py forms_tests", cwd: "." });
            return { status: r.status, out: r.stdout.slice(-3000), err: r.stderr.slice(-1500) };
            """)

        #expect(!output.contains("undefined is not an object"), "output was: \(output)")
        let value = try RunOutput.decoded(TestRunValue.self, from: output)
        #expect(value.out.contains("Ran 3 tests") && value.out.contains("OK"), "output was: \(output)")
        #expect(!value.out.contains("1: "), "output was: \(output)")
        // The shell merges the two streams, thus stdout holds what went to
        // stderr too, and stderr is empty.
        #expect(value.out.contains("warn"), "output was: \(output)")
        #expect(value.err.isEmpty, "output was: \(output)")
    }

    @Test("an execute result answers code, returncode, exit, ok, success, out, and text")
    func aShellResultAnswersItsOtherNames() async throws {
        let output = try await Self.run(
            #"""
            const r = await tools.shell.execute({ cmd: "echo hi; exit 3", workdir: "." });
            return [r.code, r.returncode, r.returnCode, r.exit, r.ok, r.success, r.out, r.text];
            """#)

        #expect(output.contains(#"[3,3,3,3,false,false,"hi","hi"]"#), "output was: \(output)")
    }

    @Test("an execute result's output answers the string methods over its text, and stays its list of lines")
    func aShellOutputActsAsAString() async throws {
        // noqueue24 django__django-14672 seq 16829: `out(ps).trim is not a
        // function`; django__django-14752 seq 18454: `r1.output.split is not
        // a function`.
        let output = try await Self.run(
            #"""
            const r = await tools.shell.execute({ command: "printf 'Ran 3 tests\\nOK\\n'" });
            const o = r.output;
            return [o.trim().split("\n"), o.match(/Ran (\d+)/)[1], o.toLowerCase().startsWith("ran"),
              `${o}`.endsWith("OK"), o.length, String(o[0]), o.map((l) => l.length > 0).length];
            """#)

        #expect(!output.contains("is not a function"), "output was: \(output)")
        #expect(
            output.contains(#"[["Ran 3 tests","OK"],"3",true,true,2,"1: Ran 3 tests",2]"#),
            "output was: \(output)")
    }

    @Test("the methods an array has stay array methods on an execute result's output")
    func aShellOutputKeepsItsArrayMethods() async throws {
        // The kept bench transcripts use `output.slice(-15)` for the last 15
        // lines, and `output.slice(-6).join(...)`.
        let output = try await Self.run(
            #"""
            const r = await tools.shell.execute({ command: "seq 1 20" });
            return [r.output.slice(-6).join("\n").split("\n").length, r.output.slice(-15).length === 15,
              r.output.includes("20: 20"), r.output.indexOf("1: 1"), r.output.concat(["x"]).length];
            """#)

        #expect(output.contains(#"[6,true,true,0,21]"#), "output was: \(output)")
    }

    @Test("an execute result still serializes its output as the list of lines")
    func aShellOutputStillSerializesAsItsLines() async throws {
        let output = try await Self.run(
            #"const r = await tools.shell.execute({ command: "echo hi" }); return JSON.stringify(r.output);"#)

        #expect(try RunOutput.decoded(String.self, from: output) == #"["1: hi"]"#, "output was: \(output)")
    }

    @Test("a workingDirectory that names the root's own folder, and is not in it, runs in the root with a note")
    func aWorkingDirectoryNamedAsTheRootRunsInTheRoot() async throws {
        // noqueue24 django__django-14534 seq 11936: `workingDirectory: "repo"`
        // with the root named `repo` resolved to `…/repo/repo`.
        var name = ""
        let output = try await Self.run { root in
            name = root.lastPathComponent
            return #"const r = await tools.shell.execute({ command: "pwd", workingDirectory: "\#(name)" }); "#
                + #"return { status: r.status, out: r.stdout, note: r.note };"#
        }

        struct Value: Decodable {
            let status: String
            let out: String
            let note: String?
        }
        let value = try RunOutput.decoded(Value.self, from: output)
        #expect(!output.contains("Failed to set working directory"), "output was: \(output)")
        #expect(value.status == "completed", "output was: \(output)")
        #expect(value.out.hasSuffix("/\(name)") && !value.out.hasSuffix("/\(name)/\(name)"), "output was: \(output)")
        #expect(value.note?.contains("the root") == true, "output was: \(output)")
    }

    @Test("each other name of workingDirectory is accepted", arguments: ["cwd", "dir", "directory", "workdir", "cd"])
    func eachOtherNameOfWorkingDirectory(name: String) async throws {
        let output = try await Self.run(
            #"const r = await tools.shell.execute({ command: "pwd", \#(name): "tests" }); return r.stdout;"#)

        #expect(try RunOutput.decoded(String.self, from: output).hasSuffix("/tests"), "output was: \(output)")
    }

    /// The part of a read result the positional test reads.
    private struct ReadValue: Decodable {
        let lines: [String]
    }

    @Test("the snippet of seq 13418: a path and then an options object read the range")
    func aPathAndOptionsAreMerged() async throws {
        let output = try await Self.run(
            #"""
            const r = await tools.files.read("tests/forms_tests/tests/test_forms.py", { offset: 70, limit: 5 });
            return r;
            """#)

        #expect(!output.contains("must be a JS object"), "output was: \(output)")
        let lines = try RunOutput.decoded(ReadValue.self, from: output).lines
        #expect(lines.count == 5, "output was: \(output)")
        #expect(lines.first?.hasSuffix("line 70") == true, "output was: \(output)")
    }

    @Test("a call that is not an object names the real verb and its object form, and no tools.name hint")
    func aNonObjectCallNamesTheRealVerb() async throws {
        let output = try await Self.run(#"return await tools.files.read(42);"#)

        #expect(output.contains("tools.files.read({ path: "), "output was: \(output)")
        #expect(!output.contains("tools.name"), "output was: \(output)")
        #expect(!output.contains("getRenameEdits"), "output was: \(output)")
    }
}
