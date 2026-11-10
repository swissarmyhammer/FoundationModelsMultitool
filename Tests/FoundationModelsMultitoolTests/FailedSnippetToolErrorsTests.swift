// `FailedSnippetToolErrorsTests` — a snippet that fails shows the errors its
// `tools.*` calls returned.
//
// planner24 django__django-14411 seq 21873: `tools.kanban.runKanban` returned
// `{"errors":[...]}` with no `data`, and the snippet read `r.data.addTask`.
// The model saw only "undefined is not an object (evaluating
// 'r.data.addTask')", and never the GraphQL error that was the real cause.

import Foundation
import FoundationModels
import Testing

@testable import FoundationModelsMultitool

/// A tool that answers with fixed JSON text, as a GraphQL endpoint does.
private struct CannedJSONTool: Tool {
    let name: String
    let description = "Answers with fixed JSON text."
    let json: String

    func call(arguments: NoArguments) async throws -> String { json }
}

@Suite("A failed snippet shows the errors its tool calls returned")
struct FailedSnippetToolErrorsTests {

    private static let graphQLError = #"""
        {"errors":[{"message":"Variable \"$col\" of type \"String!\" used in position expecting type \"ID\".","extensions":{"code":"GRAPHQL_VALIDATION_FAILED"}}]}
        """#

    private static func run(_ code: String, json: String) async throws -> String {
        let registry = try MultiTool.Builder(mode: .open)
            .addTool(CannedJSONTool(name: "runKanban", json: json))
            .buildRegistry()
        return try await MultiTool(registry: registry).call(arguments: RunCodeArguments(code: code))
    }

    @Test("planner24 14411: reading .data of a GraphQL error result names the error")
    func aGraphQLErrorIsShown() async throws {
        let output = try await Self.run(
            #"let r = await tools.runKanban({}); if (typeof r === "string") r = JSON.parse(r); return r.data.addTask;"#,
            json: Self.graphQLError)

        #expect(output.contains(InterpreterError.Kind.exception.repairableErrorSummary), "output was: \(output)")
        #expect(output.contains("A tool call in this snippet returned errors"), "output was: \(output)")
        #expect(output.contains("tools.runKanban"), "output was: \(output)")
        #expect(output.contains("[GRAPHQL_VALIDATION_FAILED]"), "output was: \(output)")
        #expect(output.contains(#"Variable "$col" of type "String!""#), "output was: \(output)")
        #expect(output.hasSuffix(RepairDirective.repairSnippet.closingLine), "output was: \(output)")
    }

    @Test("an error field and a correction field are shown too")
    func anErrorFieldIsShown() async throws {
        let output = try await Self.run(
            #"await tools.runKanban({}); throw new Error("boom");"#,
            json: #"{"error":{"message":"no such board","code":"NOT_FOUND"}}"#)

        #expect(output.contains("tools.runKanban: [NOT_FOUND] no such board"), "output was: \(output)")
    }

    @Test("a failed snippet whose calls returned no errors is unchanged")
    func noErrorsNoSection() async throws {
        let output = try await Self.run(
            #"await tools.runKanban({}); throw new Error("boom");"#,
            json: #"{"data":{"board":{}}}"#)

        #expect(!output.contains("returned errors"), "output was: \(output)")
    }

    @Test("a snippet that succeeds after a call returned errors is unchanged")
    func successIsUnchanged() async throws {
        let output = try await Self.run(
            #"const r = await tools.runKanban({}); return r;"#,
            json: Self.graphQLError)

        #expect(!output.contains("returned errors"), "output was: \(output)")
    }
}
