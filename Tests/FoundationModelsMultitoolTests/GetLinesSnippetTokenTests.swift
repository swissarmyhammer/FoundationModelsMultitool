// `GetLinesSnippetTokenTests` — `shell.getLines` given the completion token
// of a `runCode` snippet reads the commands that snippet started ("Postel's
// rule": be liberal in what you accept).
//
// dotask24 django__django-13447 seq 661 and 689, and kanban24
// django__django-13925 seq 2749 and 2753: the model passed the token of a
// pending runCode snippet to getLines, got "No command of this session ran
// under the completion token …", and ran the command again.

import Foundation
import FoundationModelsExtras
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

@Suite(.ownsTemporaryDirectories) struct GetLinesSnippetTokenTests {

    /// Runs `code` in runCode under the context of a session, and answers the
    /// getLines verb and the completion token of that runCode run.
    private static func runSnippet(_ code: String) async throws -> (getLines: GetLines, token: String) {
        let root = TestSupport.makeTemporaryDirectory(named: "GetLinesSnippetTokenTests")
        let registry = try MultiTool.Builder()
            .withShell(storeDirectory: root.appendingPathComponent(".shell"), defaultWorkingDirectory: root)
            .buildRegistry()
        let getLines = try #require(registry.tools["shell.getLines"] as? GetLines)
        let session = LeasedSession()
        _ = try await ToolContext.$current.withValue(session.context) {
            try await MultiTool(registry: registry).call(arguments: RunCodeArguments(code: code))
        }
        return (getLines, session.context.completionToken)
    }

    @Test("the token of a snippet that ran one command reads that command")
    func aSnippetTokenReadsItsCommand() async throws {
        let (getLines, token) = try await Self.runSnippet(
            #"const r = await tools.shell.execute({ command: "echo one" }); return r.exitCode;"#)

        let read = try await getLines.call(arguments: GetLinesArguments(commandID: token))

        #expect(read.correction == nil, "correction was: \(read.correction ?? "")")
        #expect(read.lines == ["1: one"])
        #expect(read.commandID != token)
    }

    @Test("the token of a snippet that ran two commands reads the last, and names both")
    func aSnippetTokenOfTwoCommandsReadsTheLast() async throws {
        let (getLines, token) = try await Self.runSnippet(
            #"""
            await tools.shell.execute({ command: "echo one" });
            const r = await tools.shell.execute({ command: "echo two" }); return r.exitCode;
            """#)

        let read = try await getLines.call(arguments: GetLinesArguments(commandID: token))

        #expect(read.lines == ["1: two"])
        let note = try #require(read.note)
        #expect(note.contains("echo one") && note.contains("echo two"), "note was: \(note)")
    }

    @Test("a token no command and no snippet ran under still gets the correction")
    func anUnknownTokenStillGetsTheCorrection() async throws {
        let (getLines, _) = try await Self.runSnippet(#"return 1;"#)

        let read = try await getLines.call(arguments: GetLinesArguments(commandID: "nope"))

        #expect(read.correction != nil)
        #expect(read.note == nil)
    }
}
