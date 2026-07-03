import Foundation
import Testing

import FoundationModels
import FoundationModelsRouter
@testable import FoundationModelsMultitool

/// M6.5a coverage for `TranscriptAnalyzer`: the ungated unit suite over
/// checked-in fixture JSONL that plan.md's "Transcript-parsing helpers are
/// themselves unit-tested against checked-in fixture JSONL (runs in normal
/// CI)" acceptance criterion calls for.
///
/// The gated `SearchThenCallTests`/`PrefixReuseTests`
/// (`Tests/FoundationModelsMultitoolIntegrationTests`) read a *real* Router
/// JSONL transcript through the exact same `TranscriptAnalyzer` entry
/// points exercised here — this suite is what proves those helpers are
/// correct without needing a model at all.
@Suite("TranscriptAnalyzer")
struct TranscriptAssertionTests {
    /// Loads a checked-in fixture transcript from `Goldens/<name>` next to
    /// this file — the same `#filePath`-relative pattern
    /// `BuilderSurfaceTests`/`LibrarianTests`/`ToolAPIRendererTests` use for
    /// their own golden files.
    ///
    /// - Parameter name: the fixture file's name, e.g.
    ///   `"SearchThenCallTranscript.jsonl"`.
    /// - Returns: the fixture file's raw contents.
    private static func loadFixture(_ name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Goldens/\(name)")
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - decodeJSONL(_:)

    @Test("decodeJSONL decodes every line of the search-then-call fixture, in file order")
    func decodeJSONLDecodesEveryLine() throws {
        let events = try TranscriptAnalyzer.decodeJSONL(try Self.loadFixture("SearchThenCallTranscript.jsonl"))

        #expect(events.count == 10)
        #expect(events.map(\.seq) == Array(0...9))
        #expect(events.first?.kind == .session)
        #expect(events.first?.routerId == ULID("01ARZ3NDEKTSV4RRFFQ69G5FAV"))
        #expect(events.last?.kind == .response)
    }

    @Test("decodeJSONL throws on a malformed line")
    func decodeJSONLThrowsOnMalformedLine() {
        #expect(throws: (any Error).self) {
            try TranscriptAnalyzer.decodeJSONL("not JSON at all")
        }
    }

    @Test("decodeJSONL ignores blank lines")
    func decodeJSONLIgnoresBlankLines() throws {
        let jsonl = """
            {"routerId":"01ARZ3NDEKTSV4RRFFQ69G5FAV","sessionId":"01ARZ3NDEKTSV4RRFFQ69G5FAA","slot":"standard","seq":0,"ts":1,"kind":"session"}

            {"routerId":"01ARZ3NDEKTSV4RRFFQ69G5FAV","sessionId":"01ARZ3NDEKTSV4RRFFQ69G5FAA","slot":"standard","seq":1,"ts":2,"kind":"prompt","text":"hi"}
            """
        let events = try TranscriptAnalyzer.decodeJSONL(jsonl)
        #expect(events.count == 2)
    }

    // MARK: - step(from:)

    @Test("step(from:) parses a tolerant-format response when grammar is nil")
    func stepFromTolerantResponseParses() throws {
        let event = TranscriptEvent(
            routerId: .generate(),
            sessionId: .generate(),
            seq: 0,
            ts: Date(),
            kind: .response,
            text: "ACTION: runCode\nCODE:\n```js\nreturn 1;\n```"
        )
        #expect(try TranscriptAnalyzer.step(from: event) == .runCode(code: "return 1;"))
    }

    @Test("step(from:) parses a guided-format response when grammar is set")
    func stepFromGuidedResponseParses() throws {
        let event = TranscriptEvent(
            routerId: .generate(),
            sessionId: .generate(),
            seq: 0,
            ts: Date(),
            kind: .response,
            grammar: "{\"type\":\"object\"}",
            text: #"{"kind":"final","text":"done"}"#
        )
        #expect(try TranscriptAnalyzer.step(from: event) == .final(text: "done"))
    }

    @Test("step(from:) throws when the event carries no text")
    func stepFromTextlessEventThrows() {
        let event = TranscriptEvent(
            routerId: .generate(),
            sessionId: .generate(),
            seq: 0,
            ts: Date(),
            kind: .response
        )
        #expect(throws: (any Error).self) {
            try TranscriptAnalyzer.step(from: event)
        }
    }

    // MARK: - steps(in:slot:)

    @Test("steps(in:slot:) recovers exactly the main agent's three steps from the search-then-call fixture")
    func stepsInStandardSlotRecoversMainAgentSteps() throws {
        let events = try TranscriptAnalyzer.decodeJSONL(try Self.loadFixture("SearchThenCallTranscript.jsonl"))
        let steps = TranscriptAnalyzer.steps(in: events, slot: .standard)

        #expect(steps.count == 3)
        #expect(steps[0] == .findAPIs(task: "list trip cities and get weather for each to find the warmest"))
        if case .runCode(let code) = steps[1] {
            #expect(code.contains("tools.tripCities()"))
        } else {
            Issue.record("expected steps[1] to be .runCode")
        }
        #expect(steps[2] == .final(text: "Austin is the warmest at 31C."))
    }

    // MARK: - findAPIsPrecedesRunCode(in:)

    @Test("findAPIsPrecedesRunCode is true for the search-then-call fixture")
    func findAPIsPrecedesRunCodeTrueForSearchThenCall() throws {
        let events = try TranscriptAnalyzer.decodeJSONL(try Self.loadFixture("SearchThenCallTranscript.jsonl"))
        let steps = TranscriptAnalyzer.steps(in: events, slot: .standard)
        #expect(TranscriptAnalyzer.findAPIsPrecedesRunCode(in: steps))
    }

    @Test("findAPIsPrecedesRunCode is false for the repair fixture (no findAPIs step at all)")
    func findAPIsPrecedesRunCodeFalseForRepair() throws {
        let events = try TranscriptAnalyzer.decodeJSONL(try Self.loadFixture("RepairTranscript.jsonl"))
        let steps = TranscriptAnalyzer.steps(in: events, slot: .standard)
        #expect(!TranscriptAnalyzer.findAPIsPrecedesRunCode(in: steps))
    }

    @Test("findAPIsPrecedesRunCode is false when there is no runCode step at all")
    func findAPIsPrecedesRunCodeFalseWithNoRunCode() {
        let steps: [AgentStep] = [.findAPIs(task: "look around"), .final(text: "done")]
        #expect(!TranscriptAnalyzer.findAPIsPrecedesRunCode(in: steps))
    }

    @Test("findAPIsPrecedesRunCode is true across multiple findAPIs calls, using the last findAPIs before runCode")
    func findAPIsPrecedesRunCodeTrueWithMultipleFindAPIsCalls() {
        let steps: [AgentStep] = [
            .findAPIs(task: "look around"),
            .findAPIs(task: "narrow it down"),
            .runCode(code: "return 1;"),
            .final(text: "done"),
        ]
        #expect(TranscriptAnalyzer.findAPIsPrecedesRunCode(in: steps))
    }

    // MARK: - toolCallPaths(in:)

    @Test("toolCallPaths extracts flat and namespaced tools.* call sites, ignoring look-alikes")
    func toolCallPathsExtractsCallSites() {
        let code = """
            const c = tools.weather({ city: "ATX" }).tempC;
            tools.github.createIssue({ title: "x" });
            const ignored = notTools.other();
            const bare = tools.weather;
            """
        let paths = TranscriptAnalyzer.toolCallPaths(in: code)
        #expect(paths == ["weather", "github.createIssue"])
    }

    @Test("toolCallPaths returns an empty set for code with no tools.* calls")
    func toolCallPathsEmptyForNoCalls() {
        #expect(TranscriptAnalyzer.toolCallPaths(in: "return 1 + 1;").isEmpty)
    }

    @Test("toolCallPaths does not match an identifier that merely ends in \"tools\"")
    func toolCallPathsIgnoresIdentifiersEndingInTools() {
        let code = """
            const x = mytools.other({ a: 1 });
            const y = helpertools.foo();
            const z = tools.weather({ city: "ATX" });
            """
        #expect(TranscriptAnalyzer.toolCallPaths(in: code) == ["weather"])
    }

    // MARK: - invokedToolPaths(in:)

    @Test("invokedToolPaths unions call paths across every runCode step")
    func invokedToolPathsUnionsAcrossSteps() {
        let steps: [AgentStep] = [
            .findAPIs(task: "t"),
            .runCode(code: "tools.weather({ city: \"ATX\" });"),
            .runCode(code: "tools.github.createIssue({ title: \"x\" });"),
            .final(text: "done"),
        ]
        #expect(TranscriptAnalyzer.invokedToolPaths(in: steps) == ["weather", "github.createIssue"])
    }

    // MARK: - runCodeStepsBeforeFinal(in:)

    @Test("runCodeStepsBeforeFinal counts two attempts for the repair fixture")
    func runCodeStepsBeforeFinalCountsRepairAttempts() throws {
        let events = try TranscriptAnalyzer.decodeJSONL(try Self.loadFixture("RepairTranscript.jsonl"))
        let steps = TranscriptAnalyzer.steps(in: events, slot: .standard)
        #expect(TranscriptAnalyzer.runCodeStepsBeforeFinal(in: steps) == 2)
    }

    @Test("runCodeStepsBeforeFinal counts one attempt for the search-then-call fixture")
    func runCodeStepsBeforeFinalCountsOneForSearchThenCall() throws {
        let events = try TranscriptAnalyzer.decodeJSONL(try Self.loadFixture("SearchThenCallTranscript.jsonl"))
        let steps = TranscriptAnalyzer.steps(in: events, slot: .standard)
        #expect(TranscriptAnalyzer.runCodeStepsBeforeFinal(in: steps) == 1)
    }

    @Test("runCodeStepsBeforeFinal counts every runCode step when there is no final step")
    func runCodeStepsBeforeFinalCountsAllWithNoFinal() {
        let steps: [AgentStep] = [.runCode(code: "1"), .runCode(code: "2")]
        #expect(TranscriptAnalyzer.runCodeStepsBeforeFinal(in: steps) == 2)
    }

    // MARK: - foundAPIs(in:slot:)

    @Test("foundAPIs decodes the librarian's flash-slot response from the search-then-call fixture")
    func foundAPIsDecodesLibrarianResponse() throws {
        let events = try TranscriptAnalyzer.decodeJSONL(try Self.loadFixture("SearchThenCallTranscript.jsonl"))
        let found = try TranscriptAnalyzer.foundAPIs(in: events, slot: .flash)

        #expect(found.count == 1)
        #expect(found[0].functions.map(\.name) == ["tripCities", "weather"])
    }

    @Test("foundAPIs decodes multiple flash-slot responses, one per findAPIs call, in recorded order")
    func foundAPIsDecodesMultipleResponsesInOrder() throws {
        let events = [
            TranscriptEvent(
                routerId: .generate(),
                sessionId: .generate(),
                slot: .flash,
                seq: 0,
                ts: Date(),
                kind: .response,
                text: cannedTripCitiesFoundAPIsJSON
            ),
            TranscriptEvent(
                routerId: .generate(),
                sessionId: .generate(),
                slot: .flash,
                seq: 1,
                ts: Date(),
                kind: .response,
                text: cannedWeatherFoundAPIsJSON
            ),
        ]
        let found = try TranscriptAnalyzer.foundAPIs(in: events, slot: .flash)
        #expect(found.map { $0.functions.map(\.name) } == [["tripCities"], ["weather"]])
    }

    @Test("foundAPIs throws when a flash-slot response isn't valid FoundAPIs JSON")
    func foundAPIsThrowsOnInvalidJSON() {
        let events = [
            TranscriptEvent(
                routerId: .generate(),
                sessionId: .generate(),
                slot: .flash,
                seq: 0,
                ts: Date(),
                kind: .response,
                text: "not JSON at all"
            )
        ]
        #expect(throws: (any Error).self) {
            try TranscriptAnalyzer.foundAPIs(in: events, slot: .flash)
        }
    }
}
