// `ShellVerbSynonymTests` — the other names a model calls `shell.execute` by
// run it ("Postel's rule": be liberal in what you accept).
//
// SWE-bench run bench24-1023b, django__django-14915 (seq 21437): the model
// called `tools.shell.run(...)` and got "tools.shell.run is not a function".

import Foundation
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

@Suite("ShellVerbSynonymTests", .ownsTemporaryDirectories)
struct ShellVerbSynonymTests {

    /// Runs `code` on a surface with the shell capability over an empty root.
    private static func run(_ code: String) async throws -> String {
        let root = TestSupport.makeTemporaryDirectory(named: "shell-verb-synonyms")
        let store = TestSupport.makeTemporaryDirectory(named: "shell-verb-synonyms-store")
        let registry = try MultiTool.Builder()
            .withShell(storeDirectory: store.appendingPathComponent(".shell"), defaultWorkingDirectory: root)
            .buildRegistry()
        return try await MultiTool(registry: registry).call(arguments: RunCodeArguments(code: code))
    }

    @Test("the call of the run: shell.run runs the command")
    func shellRunRuns() async throws {
        let output = try await Self.run(
            #"return await tools.shell.run({ command: "git log --oneline -S ModelChoiceIteratorValue -- django/forms/models.py" });"#
        )

        #expect(!output.contains("is not a function"), "output was: \(output)")
        #expect(output.contains("exitCode"), "output was: \(output)")
    }

    @Test(
        "each other name of shell.execute runs the command",
        arguments: ["run", "exec", "sh", "bash", "command", "runCommand", "Run"])
    func eachNameRuns(name: String) async throws {
        let output = try await Self.run(#"return (await tools.shell.\#(name)({ command: "echo hi" })).stdout;"#)

        #expect(try RunOutput.decoded(String.self, from: output) == "hi", "output was: \(output)")
    }
}
