import Foundation
import FoundationModels
import FoundationModelsRouter
import Testing
import os

@testable import FoundationModelsMultitool

// MARK: - `ScriptedDirectCallSession` — a zero-GPU `DirectCallSession` fake

/// Thrown by `ScriptedDirectCallSession.respond(to:matching:)` when it
/// receives more calls than it was scripted with — a test bug, mirroring
/// `ScriptedAgentSessionError`'s identical role for `ScriptedAgentSession`.
struct ScriptedDirectCallSessionError: Error, Equatable, CustomStringConvertible {
    /// How many scripted responses `respond(to:matching:)` had queued.
    let scriptedResponseCount: Int

    var description: String {
        "ScriptedDirectCallSession received more calls than its \(scriptedResponseCount) scripted response(s)."
    }
}

/// A scripted `DirectCallSession` test double: returns its canned
/// `responses` in order, one per call, regardless of the prompt/schema —
/// `DirectToolCallTests`'/`MultiToolAgentTests`'-style zero-GPU stand-in for
/// a real `RoutedLLM.respond(to:matching:)` call, mirroring
/// `ScriptedAgentSession`'s established pattern
/// (`Fixtures/MultiToolAgentFixtures.swift`) for the `DirectCallSession` seam
/// instead of `AgentSession`.
final class ScriptedDirectCallSession: DirectCallSession, Sendable {
    /// The mutable state guarded by `stateBox`.
    private struct State {
        /// How many calls `respond(to:matching:)` has handled so far.
        var callCount = 0
        /// Every prompt this session received, in call order.
        var receivedPrompts: [String] = []
        /// Every JSON Schema string this session was constrained to, in call order.
        var receivedSchemas: [String] = []
    }

    /// The canned responses returned in order, one per call.
    private let responses: [JSONValue]

    /// This session's call state.
    private let stateBox: OSAllocatedUnfairLock<State>

    /// Creates a scripted session that returns `responses` in order, one per
    /// `respond(to:matching:)` call.
    ///
    /// - Parameter responses: the canned schema-valid responses to return,
    ///   in call order.
    init(_ responses: [JSONValue]) {
        self.responses = responses
        self.stateBox = OSAllocatedUnfairLock(initialState: State())
    }

    /// How many calls this session has handled so far.
    var callCount: Int { stateBox.withLock { $0.callCount } }

    /// Every prompt this session received, in call order.
    var receivedPrompts: [String] { stateBox.withLock { $0.receivedPrompts } }

    /// Every JSON Schema string this session was constrained to, in call order.
    var receivedSchemas: [String] { stateBox.withLock { $0.receivedSchemas } }

    /// Returns this session's next scripted response, in order, regardless
    /// of `prompt`/`jsonSchema` — recording both for later assertions.
    ///
    /// - Parameters:
    ///   - prompt: the prompt to record.
    ///   - jsonSchema: the JSON Schema string to record.
    /// - Returns: the next canned response from `responses`.
    /// - Throws: `ScriptedDirectCallSessionError` if every scripted response
    ///   has already been returned.
    func respond(to prompt: String, matching jsonSchema: String) async throws -> JSONValue {
        let index = stateBox.withLock { state -> Int in
            state.receivedPrompts.append(prompt)
            state.receivedSchemas.append(jsonSchema)
            let index = state.callCount
            state.callCount += 1
            return index
        }
        guard index < responses.count else {
            throw ScriptedDirectCallSessionError(scriptedResponseCount: responses.count)
        }
        return responses[index]
    }
}

/// A `DirectCallSession` fake that always throws `error` — exercises
/// `DirectToolCall.call`'s propagate-the-session's-own-error-unchanged
/// posture.
struct ThrowingDirectCallSession: DirectCallSession {
    /// The error every call throws.
    let error: Error

    /// Throws the configured `error` immediately, ignoring `prompt` and
    /// `jsonSchema`.
    ///
    /// - Parameters:
    ///   - prompt: ignored.
    ///   - jsonSchema: ignored.
    /// - Returns: never returns.
    /// - Throws: the configured `error`, unconditionally.
    func respond(to prompt: String, matching jsonSchema: String) async throws -> JSONValue {
        throw error
    }
}

/// M18 coverage for `DirectToolCall` (`Sources/FoundationModelsMultitool/Agent/DirectToolCall.swift`)
/// — plan.md § "Escape hatch — keep the schema-valid-args guarantee": the
/// escape hatch that calls one *direct* tool through Router guided
/// generation instead of wrapping it as `tools.*`, so its arguments stay
/// xgrammar-constrained end to end.
///
/// Driven entirely against the internal `DirectCallSession` seam via
/// `ScriptedDirectCallSession`/`ThrowingDirectCallSession` (zero GPU, no
/// Router dependency), and reuses `RecordingTool`/`RecordingToolArguments`/
/// `ThrowingTool` from `Fixtures/ToolInvokerFixtures.swift` — the same
/// mock-tool set M3b's `ToolInvokerTests` already established.
@Suite("DirectToolCall")
struct DirectToolCallTests {
    // MARK: - Acceptance 1: the derived grammar stays within the xgrammar subset

    @Test(
        "a direct tool's derived JSON Schema uses no $ref/allOf/format anywhere in its tree — the xgrammar-unsupported keywords Grammar.jsonSchema rejects"
    )
    func derivedSchemaStaysWithinXGrammarSubset() throws {
        let schemaText = try ToolAPIRenderer.jsonSchemaString(for: RecordingToolArguments.generationSchema)
        let data = Data(schemaText.utf8)
        let root = try JSONSerialization.jsonObject(with: data)
        var found: Set<String> = []
        Self.collectKeys(["$ref", "allOf", "format"], in: root, into: &found)
        #expect(found.isEmpty, "found xgrammar-unsupported keyword(s): \(found.sorted())")
    }

    @Test("a direct tool's derived JSON Schema is a well-formed object schema naming its required/optional properties")
    func derivedSchemaDescribesTheArgumentsShape() throws {
        let schemaText = try ToolAPIRenderer.jsonSchemaString(for: RecordingToolArguments.generationSchema)
        let data = Data(schemaText.utf8)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(root["type"] as? String == "object")
        let properties = try #require(root["properties"] as? [String: Any])
        #expect(properties["city"] != nil)
        #expect(properties["units"] != nil)
        let required = try #require(root["required"] as? [String])
        #expect(required == ["city"])
    }

    /// Recursively collects any of `keywords` found as a key anywhere in a
    /// parsed JSON tree — the same local mirror of `Grammar`'s own
    /// (module-internal to `FoundationModelsRouter`) xgrammar-subset
    /// validation that `GuidedTurnFormatTests` uses for `AgentTurn`'s
    /// derived schema.
    ///
    /// - Parameters:
    ///   - keywords: the set of keywords to find.
    ///   - node: the JSON node to search.
    ///   - found: the set accumulating found keywords.
    private static func collectKeys(_ keywords: Set<String>, in node: Any, into found: inout Set<String>) {
        if let array = node as? [Any] {
            for element in array { collectKeys(keywords, in: element, into: &found) }
            return
        }
        guard let object = node as? [String: Any] else { return }
        for (key, value) in object {
            if keywords.contains(key) { found.insert(key) }
            collectKeys(keywords, in: value, into: &found)
        }
    }

    // MARK: - Acceptance 2: schema-valid guided output invokes the tool with correctly-typed Arguments

    @Test("a scripted schema-valid guided response invokes the tool with correctly-typed, decoded Arguments")
    func schemaValidGuidedOutputInvokesToolWithTypedArguments() async throws {
        let tool = RecordingTool()
        let session = ScriptedDirectCallSession([
            .object(["city": .string("PAR"), "units": .string("c")])
        ])

        let output = try await DirectToolCall.call(tool, task: "look up Paris in Celsius", using: session)

        #expect(output.echoedCity == "PAR")
        #expect(tool.recorded?.city == "PAR")
        #expect(tool.recorded?.units == "c")
        // The session was constrained to a schema derived from the tool's
        // own parameters, and prompted with the caller's task description.
        #expect(session.callCount == 1)
        #expect(session.receivedSchemas[0].contains("\"city\""))
        #expect(session.receivedPrompts[0].contains("look up Paris in Celsius"))
        #expect(session.receivedPrompts[0].contains(tool.name))
    }

    @Test("a schema-valid guided response omitting the optional field still invokes the tool, leaving it nil")
    func schemaValidGuidedOutputOmittingOptionalFieldDecodesAsNil() async throws {
        let tool = RecordingTool()
        let session = ScriptedDirectCallSession([
            .object(["city": .string("TOK")])
        ])

        _ = try await DirectToolCall.call(tool, task: "look up Tokyo", using: session)

        #expect(tool.recorded?.city == "TOK")
        #expect(tool.recorded?.units == nil)
    }

    // MARK: - A throwing tool's own error propagates unchanged

    @Test("a throwing tool's error propagates through DirectToolCall.call unchanged, not wrapped")
    func throwingToolErrorPropagatesUnchanged() async throws {
        let tool = ThrowingTool()
        let session = ScriptedDirectCallSession([
            .object(["city": .string("AAA")])
        ])

        await #expect(throws: ThrowingToolError(message: "boom: AAA")) {
            _ = try await DirectToolCall.call(tool, task: "look up AAA", using: session)
        }
    }

    // MARK: - The guided session's own error propagates unchanged

    @Test("a guided session's own thrown error propagates through DirectToolCall.call unchanged")
    func guidedSessionErrorPropagatesUnchanged() async throws {
        struct FixtureSessionError: Error, Equatable {}
        let tool = RecordingTool()
        let session = ThrowingDirectCallSession(error: FixtureSessionError())

        await #expect(throws: FixtureSessionError.self) {
            _ = try await DirectToolCall.call(tool, task: "look up anything", using: session)
        }
    }

    // MARK: - Pre-call validation still runs on the guided output

    @Test("a schema-valid-shaped but guide-violating guided response still fails ToolInvoker's pre-call validation")
    func guideViolationInGuidedOutputStillFailsValidation() async throws {
        let tool = RangedTool()
        // RangedIntegerArgument's `score` is `.range(1...10)`; 999 violates it
        // even though the JSON shape (an object with an integer `score`) is
        // schema-valid.
        let session = ScriptedDirectCallSession([
            .object(["score": .number(999)])
        ])

        await #expect(throws: ToolInvokerError.self) {
            _ = try await DirectToolCall.call(tool, task: "score something", using: session)
        }
    }

    // MARK: - Acceptance 3: a wrapped tool and a direct tool coexist in one agent

    @Test("a wrapped tool (runCode) and a direct tool (callTool) both dispatch correctly in one agent")
    func wrappedAndDirectToolsCoexistInOneAgent() async throws {
        let registry = try MultiTool.Builder().addTool(CitiesTool()).buildRegistry()
        let recordingTool = RecordingTool()
        let mainSession = ScriptedAgentSession([
            "ACTION: runCode\nCODE:\n```js\nreturn tools.cities().cities.length;\n```",
            "ACTION: callTool\nNAME: recordingTool\nTASK: look up Paris",
            "ACTION: final\nANSWER: done",
        ])
        let directCallSession = ScriptedDirectCallSession([
            .object(["city": .string("PAR")])
        ])
        let agent = MultiToolAgent(
            registry: registry,
            session: mainSession,
            instructions: "You are a travel assistant.",
            directTools: [recordingTool],
            directCallSession: directCallSession
        )

        let reply = try await agent.respond(to: "Plan my trip.")

        #expect(reply == "done")
        // The runCode path dispatched correctly: the cities count (3) was
        // fed back before the callTool turn.
        #expect(mainSession.receivedPrompts[1].contains("3"))
        // The callTool path dispatched correctly: the recording tool
        // actually received schema-valid, correctly-typed arguments.
        #expect(recordingTool.recorded?.city == "PAR")
        // And its rendered result was fed back into the transcript before
        // the final turn.
        #expect(mainSession.receivedPrompts[2].contains("PAR"))
    }

    // MARK: - Acceptance 4: an unknown direct-tool name is a repairable error, not a crash

    @Test("an unknown direct-tool name from the model is fed back as a repairable error, not a crash")
    func unknownDirectToolNameIsRepairable() async throws {
        let registry = try MultiTool.Builder().addTool(CitiesTool()).buildRegistry()
        let recordingTool = RecordingTool()
        let mainSession = ScriptedAgentSession([
            "ACTION: callTool\nNAME: doesNotExist\nTASK: whatever",
            "ACTION: final\nANSWER: recovered without crashing",
        ])
        let directCallSession = ScriptedDirectCallSession([])
        let agent = MultiToolAgent(
            registry: registry,
            session: mainSession,
            instructions: "You are a travel assistant.",
            directTools: [recordingTool],
            directCallSession: directCallSession
        )

        let reply = try await agent.respond(to: "hello")

        #expect(reply == "recovered without crashing")
        #expect(mainSession.receivedPrompts[1].contains("unknown direct tool"))
        #expect(mainSession.receivedPrompts[1].contains("recordingTool"))
        // The unknown-name dispatch never touched the guided-call session at all.
        #expect(directCallSession.callCount == 0)
    }

    @Test("callTool with no direct tools configured at all is rejected instructively, not a crash")
    func noDirectToolsConfiguredIsRejectedInstructively() async throws {
        let registry = try MultiTool.Builder().addTool(CitiesTool()).buildRegistry()
        let mainSession = ScriptedAgentSession([
            "ACTION: callTool\nNAME: anything\nTASK: whatever",
            "ACTION: final\nANSWER: recovered",
        ])
        let agent = MultiToolAgent(
            registry: registry,
            session: mainSession,
            instructions: "You are a travel assistant."
        )

        let reply = try await agent.respond(to: "hello")

        #expect(reply == "recovered")
        #expect(mainSession.receivedPrompts[1].contains("no direct tools are registered"))
    }

    @Test("callTool with direct tools configured but no guided-call session is rejected instructively, not a crash")
    func directToolsWithNoSessionIsRejectedInstructively() async throws {
        let registry = try MultiTool.Builder().addTool(CitiesTool()).buildRegistry()
        let recordingTool = RecordingTool()
        let mainSession = ScriptedAgentSession([
            "ACTION: callTool\nNAME: recordingTool\nTASK: whatever",
            "ACTION: final\nANSWER: recovered",
        ])
        let agent = MultiToolAgent(
            registry: registry,
            session: mainSession,
            instructions: "You are a travel assistant.",
            directTools: [recordingTool]
        )

        let reply = try await agent.respond(to: "hello")

        #expect(reply == "recovered")
        #expect(mainSession.receivedPrompts[1].contains("no guided-call session is configured"))
    }

    @Test("a direct tool's own thrown error, dispatched through the agent loop, is a repairable error, not a crash")
    func directToolFailureThroughAgentLoopIsRepairable() async throws {
        let registry = try MultiTool.Builder().addTool(CitiesTool()).buildRegistry()
        let throwingTool = ThrowingTool()
        let mainSession = ScriptedAgentSession([
            "ACTION: callTool\nNAME: throwingTool\nTASK: whatever",
            "ACTION: final\nANSWER: recovered from the failure",
        ])
        let directCallSession = ScriptedDirectCallSession([
            .object(["city": .string("AAA")])
        ])
        let agent = MultiToolAgent(
            registry: registry,
            session: mainSession,
            instructions: "You are a travel assistant.",
            directTools: [throwingTool],
            directCallSession: directCallSession
        )

        let reply = try await agent.respond(to: "hello")

        #expect(reply == "recovered from the failure")
        #expect(mainSession.receivedPrompts[1].contains("boom: AAA"))
        // A single newline, matching the sibling in-message feedback
        // functions' separator (e.g. `FindAPITool.format`'s "found:\n" and
        // `discoveryUnavailableMessage`'s prose) — not
        // `MultiToolAgent.transcriptSeparator`'s blank-line `"\n\n"`, which
        // joins transcript entries, not text within a single message.
        #expect(mainSession.receivedPrompts[1].contains("boom: AAA\nFix the request and call callTool again."))
        #expect(!mainSession.receivedPrompts[1].contains("boom: AAA\n\nFix the request and call callTool again."))
    }

    // MARK: - The guided turn format also round-trips callTool correctly

    @Test("under .guided, a scripted callTool JSON turn dispatches correctly alongside runCode and final")
    func guidedFormatDispatchesCallToolCorrectly() async throws {
        let registry = try MultiTool.Builder().addTool(CitiesTool()).buildRegistry()
        let recordingTool = RecordingTool()
        let mainSession = ScriptedAgentSession([
            #"{"kind":"callTool","toolName":"recordingTool","task":"look up Berlin"}"#,
            #"{"kind":"final","text":"done via guided callTool"}"#,
        ])
        let directCallSession = ScriptedDirectCallSession([
            .object(["city": .string("BER")])
        ])
        let agent = MultiToolAgent(
            registry: registry,
            session: mainSession,
            instructions: "You are a travel assistant.",
            turnFormat: .guided(),
            directTools: [recordingTool],
            directCallSession: directCallSession
        )

        let reply = try await agent.respond(to: "hello")

        #expect(reply == "done via guided callTool")
        #expect(recordingTool.recorded?.city == "BER")
    }
}
