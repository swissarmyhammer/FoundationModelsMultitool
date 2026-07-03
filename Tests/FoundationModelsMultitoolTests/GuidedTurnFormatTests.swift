import Foundation
import FoundationModels
import FoundationModelsRouter
import Testing

@testable import FoundationModelsMultitool

/// M4c coverage for `AgentTurn`/`GuidedTurnFormat`: the guided-turn-format
/// sibling to M4b's `TolerantParseTurnFormat` — plan.md Router integration
/// option 1 ("Guided turns"). Driven entirely against the internal
/// `AgentSession` seam via `ScriptedAgentSession`
/// (`Fixtures/MultiToolAgentFixtures.swift`) — zero GPU, no Router
/// dependency, the same pattern `MultiToolAgentTests`/`TurnFormatTests`
/// established for M4b. No model is needed for any of this.
@Suite("GuidedTurnFormat")
struct GuidedTurnFormatTests {
    let format = GuidedTurnFormat()

    // MARK: - AgentTurn.asAgentStep(): the cross-field rule the grammar itself can't express

    @Test("a findAPIs turn with a task converts to AgentStep.findAPIs")
    func findAPIsTurnConvertsToStep() throws {
        let turn = AgentTurn(kind: .findAPIs, task: "find the weather tool")
        #expect(try turn.asAgentStep() == .findAPIs(task: "find the weather tool"))
    }

    @Test("a runCode turn with code converts to AgentStep.runCode")
    func runCodeTurnConvertsToStep() throws {
        let turn = AgentTurn(kind: .runCode, code: "return 1 + 1;")
        #expect(try turn.asAgentStep() == .runCode(code: "return 1 + 1;"))
    }

    @Test("a final turn with text converts to AgentStep.final")
    func finalTurnConvertsToStep() throws {
        let turn = AgentTurn(kind: .final, text: "Austin is warmest.")
        #expect(try turn.asAgentStep() == .final(text: "Austin is warmest."))
    }

    @Test("a findAPIs turn with no task throws TurnParseError")
    func findAPIsWithoutTaskThrows() {
        let turn = AgentTurn(kind: .findAPIs)
        #expect(throws: TurnParseError.self) { try turn.asAgentStep() }
    }

    @Test("a runCode turn with no code throws TurnParseError")
    func runCodeWithoutCodeThrows() {
        let turn = AgentTurn(kind: .runCode)
        #expect(throws: TurnParseError.self) { try turn.asAgentStep() }
    }

    @Test("a final turn with no text throws TurnParseError")
    func finalWithoutTextThrows() {
        let turn = AgentTurn(kind: .final)
        #expect(throws: TurnParseError.self) { try turn.asAgentStep() }
    }

    @Test("a runCode turn with only whitespace code throws TurnParseError")
    func runCodeWithBlankCodeThrows() {
        let turn = AgentTurn(kind: .runCode, code: "   \n  ")
        #expect(throws: TurnParseError.self) { try turn.asAgentStep() }
    }

    @Test("a findAPIs turn with only whitespace task throws TurnParseError, matching runCode's blank-check")
    func findAPIsWithWhitespaceOnlyTaskThrows() {
        let turn = AgentTurn(kind: .findAPIs, task: "   \n  ")
        #expect(throws: TurnParseError.self) { try turn.asAgentStep() }
    }

    @Test("a final turn with only whitespace text throws TurnParseError, matching runCode's blank-check")
    func finalWithWhitespaceOnlyTextThrows() {
        let turn = AgentTurn(kind: .final, text: "   \n  ")
        #expect(throws: TurnParseError.self) { try turn.asAgentStep() }
    }

    // MARK: - GuidedTurnFormat.parseTurn(_:): decodes JSON, then applies the same validation

    @Test("parses a well-formed findAPIs JSON turn")
    func parsesFindAPIsJSON() throws {
        let step = try format.parseTurn(#"{"kind":"findAPIs","task":"find the weather tool"}"#)
        #expect(step == .findAPIs(task: "find the weather tool"))
    }

    @Test("parses a well-formed runCode JSON turn")
    func parsesRunCodeJSON() throws {
        let step = try format.parseTurn(#"{"kind":"runCode","code":"return 1 + 1;"}"#)
        #expect(step == .runCode(code: "return 1 + 1;"))
    }

    @Test("parses a well-formed final JSON turn")
    func parsesFinalJSON() throws {
        let step = try format.parseTurn(#"{"kind":"final","text":"Austin is warmest."}"#)
        #expect(step == .final(text: "Austin is warmest."))
    }

    @Test("throws TurnParseError for JSON that isn't a well-formed AgentTurn")
    func throwsForMalformedJSON() {
        #expect(throws: TurnParseError.self) {
            try format.parseTurn("not JSON at all")
        }
    }

    @Test("throws TurnParseError for schema-valid JSON that fails cross-field validation")
    func throwsForSchemaValidButEmptyTurn() {
        #expect(throws: TurnParseError.self) {
            try format.parseTurn(#"{"kind":"runCode"}"#)
        }
    }

    // MARK: - formatInstructions honors supportsFindAPIs

    @Test("formatInstructions mentions findAPIs when supported")
    func formatInstructionsMentionsFindAPIsWhenSupported() {
        let text = format.formatInstructions(supportsFindAPIs: true)
        #expect(text.contains("findAPIs"))
    }

    @Test("formatInstructions notes findAPIs is unavailable when not supported")
    func formatInstructionsNotesFindAPIsUnavailable() {
        let text = format.formatInstructions(supportsFindAPIs: false)
        #expect(text.contains("not available"))
    }

    // MARK: - maxRepairTurns clamping

    @Test("a negative maxRepairTurns is clamped to 0")
    func negativeMaxRepairTurnsClampedToZero() {
        #expect(GuidedTurnFormat(maxRepairTurns: -5).maxRepairTurns == 0)
    }

    @Test("maxRepairTurns defaults to 1")
    func maxRepairTurnsDefaultsToOne() {
        #expect(GuidedTurnFormat().maxRepairTurns == 1)
    }

    // MARK: - grammar: non-nil for guided, nil (the protocol default) for tolerant parse

    @Test("GuidedTurnFormat.grammar is a non-nil jsonSchema grammar")
    func guidedFormatHasAGrammar() {
        guard case .jsonSchema(let source)? = format.grammar else {
            Issue.record("expected GuidedTurnFormat.grammar to be a non-nil .jsonSchema")
            return
        }
        #expect(source.contains("\"kind\""))
    }

    @Test("TolerantParseTurnFormat.grammar is nil (the protocol's default)")
    func tolerantParseFormatHasNoGrammar() {
        #expect(TolerantParseTurnFormat().grammar == nil)
    }

    // MARK: - Schema-subset assertion: AgentTurn's derived schema stays in the xgrammar subset

    @Test(
        "AgentTurn's derived JSON schema uses no $ref/allOf/format anywhere in its tree — the xgrammar-unsupported keywords Grammar.jsonSchema rejects"
    )
    func derivedSchemaStaysWithinXGrammarSubset() throws {
        let data = Data(AgentTurn.jsonSchemaSource.utf8)
        let root = try JSONSerialization.jsonObject(with: data)
        var found: Set<String> = []
        Self.collectKeys(["$ref", "allOf", "format"], in: root, into: &found)
        #expect(found.isEmpty, "found xgrammar-unsupported keyword(s): \(found.sorted())")
    }

    /// Recursively collects any of `keywords` found as a key anywhere in a
    /// parsed JSON tree — a local mirror of `Grammar`'s own (module-internal
    /// to `FoundationModelsRouter`, so uncallable directly from this
    /// package's tests) xgrammar-subset validation, run over `AgentTurn`'s
    /// actual encoded schema rather than assumed safe.
    ///
    /// - Parameters:
    ///   - keywords: the keys to search for.
    ///   - node: a parsed JSON value (object, array, or scalar).
    ///   - found: the accumulating set of matches encountered.
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

    // MARK: - End-to-end: findAPIs → runCode → final under .guided, zero repair turns

    @Test("a scripted findAPIs → runCode → final JSON turn sequence dispatches each step under .guided with zero repair turns")
    func guidedDispatchesFindAPIsThenRunCodeThenFinal() async throws {
        let registry = try MultiTool.Builder().addTool(CitiesTool()).buildRegistry()
        let mainSession = ScriptedAgentSession([
            #"{"kind":"findAPIs","task":"list the trip cities"}"#,
            #"{"kind":"runCode","code":"return tools.cities().cities.length;"}"#,
            #"{"kind":"final","text":"There are 3 cities."}"#,
        ])
        let librarianSession = ScriptedAgentSession([
            "declare function cities(): { cities: string[] };"
        ])
        let agent = MultiToolAgent(
            registry: registry,
            session: mainSession,
            librarianSession: librarianSession,
            instructions: "You are a travel assistant.",
            turnFormat: .guided()
        )

        let reply = try await agent.respond(to: "How many cities are on my trip?")

        #expect(reply == "There are 3 cities.")
        // Exactly 3 main-session calls — zero repair turns.
        #expect(mainSession.callCount == 3)
        #expect(librarianSession.receivedPrompts == ["list the trip cities"])
        #expect(mainSession.receivedPrompts[1].contains("declare function cities()"))
        #expect(mainSession.receivedPrompts[2].contains("3"))
        // No repair instruction was ever fed back.
        #expect(!mainSession.receivedPrompts.joined().contains("could not be used"))
    }

    // MARK: - Malformed guided turn still triggers the shared repair-turn loop

    @Test("a malformed guided turn triggers one repair turn (shared loop semantics with tolerant parse) and then succeeds")
    func malformedGuidedTurnRecoversViaSharedRepairLoop() async throws {
        let registry = try MultiTool.Builder().addTool(CitiesTool()).buildRegistry()
        let mainSession = ScriptedAgentSession([
            "not JSON at all",
            #"{"kind":"final","text":"Recovered."}"#,
        ])
        let agent = MultiToolAgent(
            registry: registry,
            session: mainSession,
            instructions: "You are a travel assistant.",
            turnFormat: .guided()
        )

        let reply = try await agent.respond(to: "hello")

        #expect(reply == "Recovered.")
        #expect(mainSession.receivedPrompts[1].contains("could not be used"))
    }

    // MARK: - max-turns termination is shared loop behavior, unaffected by turn format

    @Test("the loop terminates at max-turns under .guided too, never spinning past it")
    func guidedLoopTerminatesAtMaxTurns() async throws {
        let registry = try MultiTool.Builder().addTool(CitiesTool()).buildRegistry()
        let neverEndingResponse = #"{"kind":"runCode","code":"return 1;"}"#
        let mainSession = ScriptedAgentSession(Array(repeating: neverEndingResponse, count: 10))
        let agent = MultiToolAgent(
            registry: registry,
            session: mainSession,
            instructions: "You are a travel assistant.",
            turnFormat: .guided(),
            maxTurns: 3
        )

        await #expect(
            throws: MultiToolAgentError.maxTurnsExceeded(turns: 3)
        ) {
            try await agent.respond(to: "hello")
        }
        #expect(mainSession.callCount == 3)
    }

    // MARK: - Strategy-switch equivalence: same scenario, different formats, same loop outcome

    @Test(
        "switching turnFormat between .tolerantParse and .guided changes only the encoding, not the loop's dispatch/turn-count behavior"
    )
    func strategySwitchEquivalence() async throws {
        let registry = try MultiTool.Builder().addTool(CitiesTool()).buildRegistry()

        let tolerantSession = ScriptedAgentSession([
            "ACTION: findAPIs\nTASK: list the trip cities",
            "ACTION: runCode\nCODE:\n```js\nreturn tools.cities().cities.length;\n```",
            "ACTION: final\nANSWER: There are 3 cities.",
        ])
        let tolerantLibrarian = ScriptedAgentSession(["declare function cities(): { cities: string[] };"])
        let tolerantAgent = MultiToolAgent(
            registry: registry,
            session: tolerantSession,
            librarianSession: tolerantLibrarian,
            instructions: "You are a travel assistant.",
            turnFormat: .tolerantParse()
        )

        let guidedSession = ScriptedAgentSession([
            #"{"kind":"findAPIs","task":"list the trip cities"}"#,
            #"{"kind":"runCode","code":"return tools.cities().cities.length;"}"#,
            #"{"kind":"final","text":"There are 3 cities."}"#,
        ])
        let guidedLibrarian = ScriptedAgentSession(["declare function cities(): { cities: string[] };"])
        let guidedAgent = MultiToolAgent(
            registry: registry,
            session: guidedSession,
            librarianSession: guidedLibrarian,
            instructions: "You are a travel assistant.",
            turnFormat: .guided()
        )

        let tolerantReply = try await tolerantAgent.respond(to: "How many cities are on my trip?")
        let guidedReply = try await guidedAgent.respond(to: "How many cities are on my trip?")

        #expect(tolerantReply == guidedReply)
        #expect(tolerantSession.callCount == guidedSession.callCount)
        #expect(tolerantLibrarian.receivedPrompts == guidedLibrarian.receivedPrompts)
    }
}
