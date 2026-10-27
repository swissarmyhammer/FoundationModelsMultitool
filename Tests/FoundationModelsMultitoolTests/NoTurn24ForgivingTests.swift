// `NoTurn24ForgivingTests` — five more plain mistakes of a model that a
// `tools.*` call accepts ("Postel's rule": be liberal in what you accept).
//
// SWE-bench run noturn24 (Multitool bf89e39):
// 1. django__django-13964 seq 3488: `tools.code.run({ command: "git log …" })`,
//    a made-up group with a shell verb.
// 2. django__django-14608 seq 8613, django__django-14730 seq 10369:
//    `tools.docs("globals")`, `tools.docs("files")`; the hint sent the model
//    to `tools.web.search`.
// 3. django__django-14730 seq 10364: `tools.files.write(path, content)`.
// 4. django__django-14855 seq 11528: `tools.listFiles({ path: "." })` was
//    refused for its missing `pattern`.
// 5. django__django-15061 seq 15061: `grepCode({ pattern: "MultiWidget)" })`
//    answered a corrective text, thus `g1.map is not a function`.

import Foundation
import FoundationModels
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// The arguments of the stand-in `grepCode`.
@Generable
struct NoTurnGrepArguments {
    @Guide(description: "The regular expression.")
    var pattern: String
    @Guide(description: "The most matches to give.")
    var maxResults: Int?
}

/// A stand-in for `code_context.grepCode`: like the real verb, it answers its
/// matches as a JSON object, and a corrective text for a pattern that is not
/// a valid regular expression or for an index that is not ready.
struct NoTurnGrepCodeTool: Tool {
    let name = "grepCode"
    let description = "Searches the indexed code with a regular expression."

    /// The lines of the stand-in index.
    static let lines = ["class SplitDateTimeWidget(MultiWidget):", "x = 1"]

    func call(arguments: NoTurnGrepArguments) async throws -> String {
        if arguments.pattern == "NOTREADY" { return "The index is not ready. Try again later." }
        guard let regex = try? NSRegularExpression(pattern: arguments.pattern) else {
            return "The pattern is not a valid regular expression: invalid grep pattern '\(arguments.pattern)'. "
                + "Correct the pattern, then try again."
        }
        let matches = Self.lines.enumerated().filter { _, line in
            regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
        }.map { index, line in ["filePath": "django/forms/widgets.py", "startLine": index + 1, "text": line] as [String: Any] }
        let data = try JSONSerialization.data(withJSONObject: ["matches": matches], options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}

@Suite(.ownsTemporaryDirectories) struct NoTurn24ForgivingTests {

    /// The name of the temporary directory of one test.
    private static let testDirectoryName = "NoTurn24ForgivingTests"

    /// Runs `code` on a surface with the files and shell capabilities and the
    /// stand-in `code_context` group, over a root with `tests/runtests.py`.
    private static func run(_ code: String) async throws -> String {
        let root = TestSupport.makeTemporaryDirectory(named: testDirectoryName)
        let url = root.appendingPathComponent("tests/runtests.py")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("print('ok')\n".utf8).write(to: url)
        let store = TestSupport.makeTemporaryDirectory(named: testDirectoryName + "-store")
        let registry = try MultiTool.Builder()
            .withFiles(root: root)
            .withShell(storeDirectory: store.appendingPathComponent(".shell"), defaultWorkingDirectory: root)
            .addGroup(named: "code_context", [NoTurnGrepCodeTool()] as [any Tool])
            .buildRegistry()
        return try await MultiTool(registry: registry).call(arguments: RunCodeArguments(code: code))
    }

    // MARK: 1. A shell verb on a made-up group

    @Test("the snippet of seq 3488: tools.code.run with a command runs it in the shell")
    func aMadeUpGroupRunsTheShell() async throws {
        let output = try await Self.run(
            #"const r = await tools.code.run({ command: "echo hi && echo there" }); return r.stdout;"#)

        #expect(try RunOutput.decoded(String.self, from: output) == "hi\nthere", "output was: \(output)")
    }

    @Test("a shell verb on a made-up group or a real group runs in the shell", arguments: [
        "tools.bash.exec", "tools.terminal.execute", "tools.code_context.run", "tools.files.runCommand",
    ])
    func aShellVerbAnywhereRunsTheShell(path: String) async throws {
        let output = try await Self.run(#"const r = await \#(path)({ command: "echo hi" }); return r.stdout;"#)

        #expect(try RunOutput.decoded(String.self, from: output) == "hi", "output was: \(output)")
    }

    @Test("a made-up group's other verb still fails and is hinted")
    func aMadeUpGroupsOtherVerbStillFails() async throws {
        let output = try await Self.run(#"return await tools.git.frobnicate({ x: 1 });"#)

        #expect(output.contains("git.frobnicate"), "output was: \(output)")
    }

    // MARK: 2. tools.docs

    // A page is long, thus each snippet checks it and answers the checks.

    @Test("tools.docs(\"globals\") answers the globals page, as docs(\"globals\") does")
    func toolsDocsGlobals() async throws {
        let output = try await Self.run(
            #"const p = tools.docs("globals"); return [p === docs("globals"), p.includes("Unknown tool")];"#)

        #expect(output.contains("[true,false]"), "output was: \(output)")
    }

    @Test("docs of a group answers the docs of each of its verbs", arguments: [
        #"tools.docs("files")"#, #"docs("files")"#, #"tools.help("files")"#, #"docs("tools.files")"#,
        #"tools.files.docs()"#,
    ])
    func docsOfAGroup(call: String) async throws {
        let output = try await Self.run(
            #"const p = \#(call); return [p.includes("tools.files.read"), p.includes("tools.files.write"), "#
                + #"p.includes("Unknown tool")];"#)

        #expect(output.contains("[true,true,false]"), "output was: \(output)")
    }

    @Test("docs() with no name lists the globals page and every path")
    func docsWithNoName() async throws {
        let output = try await Self.run(
            #"const p = tools.docs(); return [p.includes(docs("globals")), p.includes("tools.files.read"), "#
                + #"p.includes("tools.shell.execute")];"#)

        #expect(output.contains("[true,true,true]"), "output was: \(output)")
    }

    // MARK: 3. Positional arguments

    @Test("the snippet of seq 10364: files.write(path, content) writes the file")
    func writeTakesPositionalArguments() async throws {
        let output = try await Self.run(
            #"""
            await tools.files.write("tests/test_scratch_probe.py", "x = 1\n");
            return (await tools.files.read({ path: "tests/test_scratch_probe.py" })).text;
            """#)

        #expect(!output.contains("must be a JS object"), "output was: \(output)")
        #expect(try RunOutput.decoded(String.self, from: output).contains("x = 1"), "output was: \(output)")
    }

    @Test("positional strings then an options object fill the required arguments in order")
    func positionalStringsThenOptions() async throws {
        let output = try await Self.run(
            #"""
            await tools.files.write("a.txt", "one\n");
            await tools.files.edit("a.txt", "one", "two");
            return (await tools.files.read("a.txt")).text;
            """#)

        #expect(try RunOutput.decoded(String.self, from: output).contains("two"), "output was: \(output)")
    }

    // MARK: 4. glob with only a path

    @Test("the snippet of seq 11528: listFiles with only a path lists the folder")
    func listFilesWithOnlyAPath() async throws {
        let output = try await Self.run(#"const r = await tools.listFiles({ path: "." }); return r.map((f) => String(f));"#)

        #expect(!output.contains("missing its required argument"), "output was: \(output)")
        #expect(try RunOutput.decoded([String].self, from: output).contains { $0.hasSuffix("runtests.py") },
                "output was: \(output)")
    }

    // MARK: 5. A grepCode corrective

    @Test("the snippet of seq 15061: a pattern that is not a valid regex is searched as literal text")
    func anInvalidRegexIsSearchedLiterally() async throws {
        let output = try await Self.run(
            #"""
            const g1 = await tools.code_context.grepCode({ pattern: "MultiWidget)", maxResults: 30 });
            return { g1: g1.map((x) => x.text), notes: g1.notes };
            """#)

        struct Value: Decodable {
            let g1: [String]
            let notes: [String]?
        }
        let value = try RunOutput.decoded(Value.self, from: output)
        #expect(value.g1 == ["class SplitDateTimeWidget(MultiWidget):"], "output was: \(output)")
        #expect(value.notes?.contains { $0.contains("literal") } == true, "output was: \(output)")
    }

    @Test("a list verb that answers a corrective text acts as an empty list that keeps the text")
    func aCorrectiveActsAsAnEmptyList() async throws {
        let output = try await Self.run(
            #"""
            const g = await tools.code_context.grepCode({ pattern: "NOTREADY" });
            return [g.map((x) => x).length, g.length, g.correction];
            """#)

        #expect(output.contains(#"[0,0,"The index is not ready. Try again later."]"#), "output was: \(output)")
    }
}
