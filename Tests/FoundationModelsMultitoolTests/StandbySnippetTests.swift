// `StandbySnippetTests` — a `runCode` snippet that only stands by while
// background work runs is taken as "end my answer".
//
// SWE-bench run bench24-1023b, django__django-13925 (a child session, seq
// 2837–3247): while a background command ran, the model sent the snippet
// below 28 times in two minutes. Each result ("standby") gave it a new turn,
// so it called again. The model knew it should wait; it waited by calling a
// tool ("Postel's rule": accept the intent).

import Foundation
import FoundationModelsExtras
import FoundationModelsRouter
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

@Suite("StandbySnippetTests", .ownsTemporaryDirectories)
struct StandbySnippetTests {

    /// The snippet the model sent, byte for byte.
    private static let standbySnippet =
        "// Stand by. No further action until the background full-suite result is injected.\nreturn \"standby\";"

    /// Runs `code` on a `MultiTool` with no tools, under `context`.
    ///
    /// - Parameters:
    ///   - code: the snippet.
    ///   - context: the session context the call runs under.
    /// - Returns: the rendered output, as the model reads it.
    private func run(_ code: String, under context: ToolContext) async throws -> String {
        let multiTool = MultiTool(registry: MultiTool.Registry(surface: APISurface(entries: []), tools: [:]))
        return try await ToolContext.$current.withValue(context) {
            try await multiTool.call(arguments: RunCodeArguments(code: code))
        }
    }

    @Test("the standby snippet, while a background run is pending, ends the answer and invites no new call")
    func standbyWhileBackgroundWorkRunsEndsTheAnswer() async throws {
        let clock = ManualRunClock()
        try await withStubRun(runClock: clock) { stub in
            try await withScriptedRun(on: stub.context, clock: clock) { _ in
                let output = try await run(Self.standbySnippet, under: stub.context)

                #expect(output == MultiTool.standbyAnswer, "output was: \(output)")
                #expect(!output.contains("call runCode again"))
                #expect(!output.contains("\"standby\""))
            }
        }
    }

    @Test(
        "each constant-only form is a standby",
        arguments: ["return null;", "return;", "", "// waiting", "return 'end 11'", "return `waiting`;", "return 0", "/* hold */ return true;"])
    func eachConstantFormIsAStandby(code: String) async throws {
        let clock = ManualRunClock()
        try await withStubRun(runClock: clock) { stub in
            try await withScriptedRun(on: stub.context, clock: clock) { _ in
                let output = try await run(code, under: stub.context)

                #expect(output == MultiTool.standbyAnswer, "output was: \(output)")
            }
        }
    }

    @Test("with no background run pending, the standby snippet returns its value as before")
    func standbyWithNoBackgroundRunReturnsItsValue() async throws {
        try await withStubRun { stub in
            let output = try await run(Self.standbySnippet, under: stub.context)

            #expect(try RunOutput.decoded(String.self, from: output) == "standby")
        }
    }

    @Test("a snippet that computes a value runs as before, even while a background run is pending")
    func aComputingSnippetRunsAsBefore() async throws {
        let clock = ManualRunClock()
        try await withStubRun(runClock: clock) { stub in
            try await withScriptedRun(on: stub.context, clock: clock) { _ in
                let output = try await run("return 1 + 1;", under: stub.context)

                #expect(try RunOutput.decoded(Int.self, from: output) == 2)
            }
        }
    }

    @Test("the static check reads only a constant return, or nothing, as a standby")
    func theStaticCheckReadsOnlyConstants() {
        #expect(MultiTool.isStandbySnippet(Self.standbySnippet))
        #expect(MultiTool.isStandbySnippet("  return \"a // b\";  "))
        #expect(!MultiTool.isStandbySnippet("return 1 + 1;"))
        #expect(!MultiTool.isStandbySnippet("return `${x}`;"))
        #expect(!MultiTool.isStandbySnippet("return await tools.files.read({ path: \"a\" });"))
        #expect(!MultiTool.isStandbySnippet("const a = 1; return a;"))
    }
}
