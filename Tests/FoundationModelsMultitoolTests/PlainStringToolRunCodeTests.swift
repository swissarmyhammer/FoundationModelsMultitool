// `PlainStringToolRunCodeTests` — a plain `Tool` whose `Output` is `String`,
// called from a `runCode` snippet.
//
// A host tool such as the kanban tool of FoundationModelsKanban is a plain
// `FoundationModels.Tool` that returns JSON text in a `String` (one GraphQL
// response). The snippet must get the parsed object, so that
// `r.data.board.nextTask` works. Text that is not a JSON object or array
// must reach the snippet as a string, as before. The same tool takes a
// `variables` argument whose schema is an `anyOf` of a string and an object
// with no properties, and no top-level `type`; a snippet must be able to give
// it as a JS object or as a JSON string.

import Foundation
import FoundationModels
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// A plain tool with a `String` output. Each case gives the text the tool
/// returns as a function of the arguments it got.
private struct TextAnswerTool: Tool {
    typealias Arguments = GeneratedContent
    typealias Output = String

    let name = PlainStringToolRunCodeTests.toolName
    let description = "Answers one query with text."
    let parameters: GenerationSchema

    /// The text the tool returns for one set of arguments.
    let answer: @Sendable (GeneratedContent) -> String

    /// Creates the tool with the `query` and `variables` schema.
    ///
    /// - Parameter answer: the text the tool returns for one set of arguments.
    /// - Throws: What `GenerationSchema.init(root:dependencies:)` throws.
    init(answer: @escaping @Sendable (GeneratedContent) -> String) throws {
        self.answer = answer
        self.parameters = try PlainStringToolRunCodeTests.querySchema()
    }

    func call(arguments: GeneratedContent) async throws -> String {
        answer(arguments)
    }
}

/// Coverage for a plain `String`-output tool in a `runCode` snippet: JSON text
/// becomes a JS value, other text stays a string, and an `anyOf`
/// string-or-object argument takes both a JS object and a JSON string.
@Suite("PlainStringToolRunCodeTests")
struct PlainStringToolRunCodeTests {
    // MARK: - Shared test constants

    /// The name of the fixture tool, thus its path `tools.graph`.
    static let toolName = "graph"

    /// The name of the string argument.
    static let queryParameter = "query"

    /// The name of the `anyOf` string-or-object argument.
    static let variablesParameter = "variables"

    /// The id the JSON answer and the variables carry.
    private static let taskID = "t1"

    /// The JSON text the JSON case returns: one GraphQL response.
    private static let graphQLAnswer = #"{"data":{"board":{"nextTask":{"id":"t1"}}}}"#

    /// The plain text the text case returns. It starts like JSON, but it is
    /// not JSON, thus it must stay a string.
    private static let plainAnswer = "{not json} done"

    /// The prefix the echo answer puts before a string `variables` value.
    private static let stringPrefix = "string:"

    /// The prefix the echo answer puts before the `id` of an object `variables` value.
    private static let objectPrefix = "object:"

    // MARK: - What a snippet reports back

    /// What the text snippet reports about the value the tool gave it.
    private struct TextReport: Decodable {
        /// The `typeof` of the value.
        let kind: String

        /// The value itself.
        let text: String
    }

    // MARK: - Helpers

    /// The schema of the fixture tool: a required string `query`, and an
    /// optional `variables` that is the `anyOf` of a string and an object
    /// with no properties.
    ///
    /// - Returns: The schema.
    /// - Throws: What `GenerationSchema.init(root:dependencies:)` throws.
    static func querySchema() throws -> GenerationSchema {
        let variables = DynamicGenerationSchema(
            name: "Variables",
            description: "The variables, as a JSON string or as an object.",
            anyOf: [
                DynamicGenerationSchema(type: String.self),
                DynamicGenerationSchema(name: "VariablesObject", properties: []),
            ])
        let root = DynamicGenerationSchema(
            name: "GraphArguments",
            properties: [
                DynamicGenerationSchema.Property(
                    name: queryParameter, schema: DynamicGenerationSchema(type: String.self)),
                DynamicGenerationSchema.Property(name: variablesParameter, schema: variables, isOptional: true),
            ])
        return try GenerationSchema(root: root, dependencies: [])
    }

    /// Runs one snippet over a registry that holds `tool` as a standalone tool.
    ///
    /// - Parameters:
    ///   - code: The snippet to run.
    ///   - tool: The fixture tool.
    /// - Returns: The rendered output of `runCode`.
    /// - Throws: What `buildRegistry()` or `MultiTool.call(arguments:)` throws.
    private static func run(_ code: String, over tool: TextAnswerTool) async throws -> String {
        let multiTool = MultiTool(registry: try MultiTool.Builder().addTool(tool).buildRegistry())
        return try await multiTool.call(arguments: RunCodeArguments(code: code))
    }

    /// The echo answer: names the kind of the `variables` the tool got, with
    /// the string itself or the `id` field of the object.
    ///
    /// - Parameter arguments: The arguments the tool got.
    /// - Returns: The echo text.
    private static func echoVariables(_ arguments: GeneratedContent) -> String {
        guard let variables = try? arguments.value(GeneratedContent.self, forProperty: variablesParameter) else {
            return "missing"
        }
        switch variables.kind {
        case .string(let text):
            return stringPrefix + text
        case .structure:
            return objectPrefix + ((try? variables.value(String.self, forProperty: "id")) ?? "no id")
        default:
            return "other"
        }
    }

    // MARK: - Output

    @Test("a String output that holds a JSON object reaches the snippet as a JS object")
    func jsonTextOutputIsAnObject() async throws {
        let tool = try TextAnswerTool { _ in Self.graphQLAnswer }

        let output = try await Self.run(
            """
            const r = await tools.\(Self.toolName)({ \(Self.queryParameter): "{ board { nextTask { id } } }" });
            return r.data.board.nextTask.id;
            """,
            over: tool)

        #expect(try RunOutput.decoded(String.self, from: output) == Self.taskID)
    }

    @Test("a String output that is not JSON reaches the snippet as a JS string")
    func plainTextOutputIsAString() async throws {
        let tool = try TextAnswerTool { _ in Self.plainAnswer }

        let output = try await Self.run(
            """
            const r = await tools.\(Self.toolName)({ \(Self.queryParameter): "q" });
            return { kind: typeof r, text: r };
            """,
            over: tool)

        let report = try RunOutput.decoded(TextReport.self, from: output)
        #expect(report.kind == "string")
        #expect(report.text == Self.plainAnswer)
    }

    @Test("ArgumentMarshaler renders a JSON array String as an array, and a JSON scalar String as a string")
    func renderOutputParsesOnlyContainers() throws {
        #expect(try ArgumentMarshaler.renderOutput(#"[1,"a"]"#) == .array([.number(1), .string("a")]))
        #expect(try ArgumentMarshaler.renderOutput("42") == .string("42"))
        #expect(try ArgumentMarshaler.renderOutput(#""hi""#) == .string(#""hi""#))
    }

    // MARK: - Input

    @Test("the variables schema is an anyOf with no top-level type, the shape the kanban tool declares")
    func variablesSchemaIsAnUntypedAnyOf() throws {
        let data = try JSONEncoder().encode(try Self.querySchema())
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let properties = try #require(root["properties"] as? [String: Any])
        var variables = try #require(properties[Self.variablesParameter] as? [String: Any])
        // A named `anyOf` encodes as a `$ref` into `$defs`; follow it.
        if let reference = variables["$ref"] as? String {
            let definitions = try #require(root["$defs"] as? [String: Any])
            let definitionName = try #require(reference.split(separator: "/").last.map(String.init))
            variables = try #require(definitions[definitionName] as? [String: Any])
        }
        #expect(variables["anyOf"] != nil)
        #expect(variables["type"] == nil)
    }

    @Test("an anyOf string-or-object argument takes a JS object and a JSON string")
    func anyOfArgumentTakesObjectAndString() async throws {
        let tool = try TextAnswerTool(answer: Self.echoVariables)

        let output = try await Self.run(
            """
            const asObject = await tools.\(Self.toolName)({
              \(Self.queryParameter): "q", \(Self.variablesParameter): { id: "\(Self.taskID)" } });
            const asString = await tools.\(Self.toolName)({
              \(Self.queryParameter): "q", \(Self.variablesParameter): JSON.stringify({ id: "\(Self.taskID)" }) });
            return [asObject, asString];
            """,
            over: tool)

        let answers = try RunOutput.decoded([String].self, from: output)
        #expect(answers == [Self.objectPrefix + Self.taskID, Self.stringPrefix + #"{"id":"t1"}"#])
    }
}
