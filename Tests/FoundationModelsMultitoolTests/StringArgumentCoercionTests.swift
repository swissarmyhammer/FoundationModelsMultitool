// `StringArgumentCoercionTests` — a string argument that gets an object or an
// array takes its JSON text ("Postel's rule": be liberal in what you accept).
//
// kanban24 django__django-14997 seq 23396 and seq 24180:
// `tools.kanban.runKanban({ query, variables: { body } })` was refused with
// `argument "variables" must be string, got an object instead.`, though the
// kanban operation reads `variables` as JSON text or as an object.

import Foundation
import FoundationModels
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

@Suite("String argument coercion", .ownsTemporaryDirectories)
struct StringArgumentCoercionTests {

    // MARK: D. A command as an array

    @Test("dotask24 14672 seq 12313: execute with command as an array runs it as argv")
    func aCommandArrayRunsAsArgv() async throws {
        let root = TestSupport.makeTemporaryDirectory(named: "StringArgumentCoercionTests")
        let registry = try MultiTool.Builder(mode: .open)
            .withShell(storeDirectory: root.appendingPathComponent(".shell"), defaultWorkingDirectory: root)
            .buildRegistry()
        let output = try await MultiTool(registry: registry).call(
            arguments: RunCodeArguments(
                code: #"const r = await tools.shell.execute({ command: ["printf", "%s|", "a b", "it's"] }); return r;"#))

        #expect(output.contains("a b|it's|"), "output was: \(output)")
    }

    @Test("an object for a string argument reaches the tool as its JSON text")
    func anObjectReadsAsJSONText() async throws {
        let tool = RecordingTool()
        let content = try ArgumentMarshaler.marshalArguments(
            .object(["city": .object(["body": .string("a \"b\"")])]))

        _ = try await ToolInvoker.invoke(tool, content: content)

        let city = try #require(tool.recorded?.city)
        let parsed = try JSONSerialization.jsonObject(with: Data(city.utf8)) as? [String: String]
        #expect(parsed == ["body": "a \"b\""], "city was: \(city)")
    }

    @Test("an array for a string argument reaches the tool as its JSON text")
    func anArrayReadsAsJSONText() async throws {
        let tool = RecordingTool()
        let content = try ArgumentMarshaler.marshalArguments(
            .object(["city": .array([.number(1), .string("x")])]))

        _ = try await ToolInvoker.invoke(tool, content: content)

        let city = try #require(tool.recorded?.city)
        let parsed = try #require(JSONSerialization.jsonObject(with: Data(city.utf8)) as? [Any])
        #expect(parsed.count == 2 && parsed.last as? String == "x", "city was: \(city)")
    }

    @Test("a number for a string argument is still refused")
    func aNumberIsStillRefused() async throws {
        let tool = RecordingTool()
        let content = try ArgumentMarshaler.marshalArguments(.object(["city": .number(42)]))

        await #expect(throws: ToolInvokerError.self) {
            try await ToolInvoker.invoke(tool, content: content)
        }
    }
}
