// `CodeContextSynonymTests` — the other names a model uses for a read verb of
// the `code_context` group call that verb ("Postel's rule": be liberal in
// what you accept).
//
// SWE-bench run bench24-1023b, django__django-14411 (root transcript, seq
// 12018): `tools.code_context.search({query: "ReadOnlyPasswordHashWidget"})`
// failed with "tools.code_context.search is not a function".

import Foundation
import FoundationModels
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// The arguments of each stand-in `code_context` verb.
@Generable
struct StandInCodeContextArguments {
    @Guide(description: "The query.")
    var query: String?
    @Guide(description: "The pattern.")
    var pattern: String?
}

/// A stand-in `code_context` verb that answers its own name and argument.
struct StandInCodeContextTool: Tool {
    let name: String
    let description = "A code_context verb."
    func call(arguments: StandInCodeContextArguments) async throws -> String {
        "\(name) \(arguments.query ?? arguments.pattern ?? "")"
    }
}

@Suite(.ownsTemporaryDirectories) struct CodeContextSynonymTests {

    /// The real verbs of the `code_context` group of FoundationModelsCodeContext.
    private static let verbs = [
        "searchSymbol", "getSymbol", "listSymbol", "grepCode", "searchCode", "getDefinition", "getReferences",
        "getInboundCalls", "getCallgraph", "getBlastradius", "rebuildIndex",
    ]

    /// Runs `code` on a surface with the stand-in `code_context` group and,
    /// when `files` is set, the files capability.
    private static func run(_ code: String, files: Bool = false) async throws -> String {
        var builder = MultiTool.Builder().addGroup(named: "code_context", verbs.map { StandInCodeContextTool(name: $0) })
        if files {
            builder = builder.withFiles(root: TestSupport.makeTemporaryDirectory(named: "CodeContextSynonymTests"))
        }
        return try await MultiTool(registry: try builder.buildRegistry()).call(arguments: RunCodeArguments(code: code))
    }

    @Test("the snippet of the run: code_context.search runs searchSymbol")
    func searchRunsSearchSymbol() async throws {
        let output = try await Self.run(
            #"return await tools.code_context.search({query: "ReadOnlyPasswordHashWidget"});"#)

        #expect(!output.contains("is not a function"), "output was: \(output)")
        #expect(
            try RunOutput.decoded(String.self, from: output) == "searchSymbol ReadOnlyPasswordHashWidget",
            "output was: \(output)")
    }

    @Test(
        "each other name of a code_context read verb runs it",
        arguments: [
            ("find", "searchSymbol"), ("lookup", "searchSymbol"), ("symbol", "searchSymbol"),
            ("findSymbol", "searchSymbol"), ("searchSymbols", "searchSymbol"),
            ("definition", "getDefinition"), ("goto", "getDefinition"), ("gotoDefinition", "getDefinition"),
            ("findDefinition", "getDefinition"), ("def", "getDefinition"),
            ("references", "getReferences"), ("refs", "getReferences"), ("usages", "getReferences"),
            ("findReferences", "getReferences"), ("findUsages", "getReferences"),
            ("callers", "getInboundCalls"), ("whoCalls", "getInboundCalls"), ("incomingCalls", "getInboundCalls"),
            ("inboundCalls", "getInboundCalls"),
            ("symbols", "listSymbol"), ("outline", "listSymbol"), ("listSymbols", "listSymbol"),
            ("fileSymbols", "listSymbol"),
            ("grep", "grepCode"), ("callgraph", "getCallgraph"), ("callGraph", "getCallgraph"),
            ("blastRadius", "getBlastradius"), ("impact", "getBlastradius"),
            ("searchSymbolByName", "searchSymbol"),
        ])
    func eachOtherNameRuns(name: String, verb: String) async throws {
        let output = try await Self.run(#"return await tools.code_context.\#(name)({ query: "x" });"#)

        #expect(try RunOutput.decoded(String.self, from: output) == "\(verb) x", "output was: \(output)")
    }

    @Test("files.search still runs files.grep beside the code_context group")
    func filesSearchStaysGrep() async throws {
        let output = try await Self.run(
            #"const r = await tools.files.search({ pattern: "x" }); return r.matchCount;"#, files: true)

        #expect(try RunOutput.decoded(Int.self, from: output) == 0, "output was: \(output)")
    }

    @Test("a made-up name that holds a verb that changes the index is not called")
    func aChangingVerbIsNotContained() async throws {
        let output = try await Self.run(#"return await tools.code_context.rebuildIndexNow({});"#)

        #expect(output.contains("is not a function"), "output was: \(output)")
    }
}
