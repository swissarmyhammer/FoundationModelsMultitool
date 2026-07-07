import Testing

@testable import FoundationModelsMultitool

/// M4b coverage for `TolerantParseTurnFormat`'s lenient extractor, isolated
/// from the loop itself (`MultiToolAgentTests` covers the loop driving this
/// format end to end). No model, no session — pure text-in/`AgentStep`-out.
@Suite("TolerantParseTurnFormat")
struct TolerantParseTurnFormatTests {
    let format = TolerantParseTurnFormat()

    // MARK: - Well-formed turns

    @Test("parses a well-formed findAPIs turn")
    func parsesFindApis() throws {
        let step = try format.parseTurn("ACTION: findAPIs\nTASK: find the weather tool")
        #expect(step == .findAPIs(task: "find the weather tool"))
    }

    @Test("parses a well-formed runCode turn with a fenced code block")
    func parsesRunCodeWithFence() throws {
        let step = try format.parseTurn("ACTION: runCode\nCODE:\n```js\nreturn 1 + 1;\n```")
        #expect(step == .runCode(code: "return 1 + 1;"))
    }

    @Test("parses a multi-line fenced runCode snippet, preserving internal newlines")
    func parsesMultiLineRunCode() throws {
        let raw = "ACTION: runCode\nCODE:\n```js\nconst x = 1;\nreturn x + 1;\n```"
        let step = try format.parseTurn(raw)
        #expect(step == .runCode(code: "const x = 1;\nreturn x + 1;"))
    }

    @Test("parses a well-formed final turn")
    func parsesFinal() throws {
        let step = try format.parseTurn("ACTION: final\nANSWER: Austin is warmest.")
        #expect(step == .final(text: "Austin is warmest."))
    }

    @Test("parses a multi-line final answer")
    func parsesMultiLineFinalAnswer() throws {
        let raw = "ACTION: final\nANSWER: line one\nline two"
        let step = try format.parseTurn(raw)
        #expect(step == .final(text: "line one\nline two"))
    }

    // MARK: - Leniency

    @Test("tolerates a Thought:-style preamble before the ACTION line")
    func tolerantOfPreamble() throws {
        let raw = "Thought: I should look this up.\nACTION: findAPIs\nTASK: weather lookup"
        let step = try format.parseTurn(raw)
        #expect(step == .findAPIs(task: "weather lookup"))
    }

    @Test("matches markers case-insensitively")
    func caseInsensitiveMarkers() throws {
        let step = try format.parseTurn("action: Final\nanswer: done")
        #expect(step == .final(text: "done"))
    }

    @Test("falls back to everything after CODE: when the model forgets the code fence")
    func runCodeFallsBackWithoutFence() throws {
        let step = try format.parseTurn("ACTION: runCode\nCODE:\nreturn 42;")
        #expect(step == .runCode(code: "return 42;"))
    }

    // MARK: - Malformed turns

    @Test("throws TurnParseError when no ACTION line is present")
    func throwsWhenNoActionLine() {
        #expect(throws: TurnParseError.self) {
            try format.parseTurn("just some free-form prose")
        }
    }

    @Test("throws TurnParseError for an unrecognized action verb")
    func throwsForUnrecognizedAction() {
        #expect(throws: TurnParseError.self) {
            try format.parseTurn("ACTION: doSomethingElse\nTASK: whatever")
        }
    }

    @Test("throws TurnParseError when findAPIs has no TASK field")
    func throwsWhenFindApisMissingTask() {
        #expect(throws: TurnParseError.self) {
            try format.parseTurn("ACTION: findAPIs")
        }
    }

    @Test("throws TurnParseError when runCode has no CODE field")
    func throwsWhenRunCodeMissingCode() {
        #expect(throws: TurnParseError.self) {
            try format.parseTurn("ACTION: runCode")
        }
    }

    @Test("throws TurnParseError when final has no ANSWER field")
    func throwsWhenFinalMissingAnswer() {
        #expect(throws: TurnParseError.self) {
            try format.parseTurn("ACTION: final")
        }
    }

    // MARK: - formatInstructions honors supportsFindApis

    @Test("formatInstructions mentions findAPIs when supported")
    func formatInstructionsMentionsFindApisWhenSupported() {
        let text = format.formatInstructions(supportsFindAPIs: true)
        #expect(text.contains("ACTION: findAPIs"))
    }

    @Test("formatInstructions omits findAPIs when not supported")
    func formatInstructionsOmitsFindApisWhenUnsupported() {
        let text = format.formatInstructions(supportsFindAPIs: false)
        #expect(!text.contains("ACTION: findAPIs"))
        #expect(text.contains("ACTION: runCode"))
        #expect(text.contains("ACTION: final"))
    }

    // MARK: - maxRepairTurns clamping

    @Test("a negative maxRepairTurns is clamped to 0")
    func negativeMaxRepairTurnsClampedToZero() {
        #expect(TolerantParseTurnFormat(maxRepairTurns: -5).maxRepairTurns == 0)
    }

    @Test("maxRepairTurns defaults to 1")
    func maxRepairTurnsDefaultsToOne() {
        #expect(TolerantParseTurnFormat().maxRepairTurns == 1)
    }
}
