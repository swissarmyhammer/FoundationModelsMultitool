import Foundation
import Testing

import FoundationModels
import FoundationModelsMetadataRegistry
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
    /// `BuilderSurfaceTests`/`ToolAPIRendererTests` use for their own golden
    /// files.
    ///
    /// - Parameter name: the fixture file's name, e.g.
    ///   `"SearchThenCallTranscript.jsonl"`. Must consist solely of letters,
    ///   digits, `-`, `_`, and `.`, and must not be all dots — this is
    ///   interpolated into a filesystem path, so anything else (path
    ///   separators, or an all-dots name like `".."` that `.` alone would
    ///   otherwise let through) is rejected rather than resolved.
    /// - Returns: the fixture file's raw contents.
    /// - Throws: ``InvalidFixtureNameError`` if `name` contains characters
    ///   outside that whitelist, or is entirely `.` characters.
    private static func loadFixture(_ name: String) throws -> String {
        let isWhitelisted = name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }
        let isAllDots = name.allSatisfy { $0 == "." }
        guard isWhitelisted, !isAllDots else {
            throw InvalidFixtureNameError(name: name)
        }
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Goldens/\(name)")
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - loadFixture(_:)

    @Test("loadFixture throws on a path-traversal name instead of escaping Goldens/")
    func loadFixtureThrowsOnPathTraversal() {
        #expect(throws: InvalidFixtureNameError.self) {
            try Self.loadFixture("../Package.swift")
        }
    }

    @Test("loadFixture throws on a name containing a path separator")
    func loadFixtureThrowsOnPathSeparator() {
        #expect(throws: InvalidFixtureNameError.self) {
            try Self.loadFixture("subdir/SearchThenCallTranscript.jsonl")
        }
    }

    @Test(
        "loadFixture throws on a bare \"..\" name, which the letters/digits/-/_/. whitelist alone would let through"
    )
    func loadFixtureThrowsOnBareParentDotDot() {
        #expect(throws: InvalidFixtureNameError.self) {
            try Self.loadFixture("..")
        }
    }

    // MARK: - decodeJsonl(_:)

    @Test("decodeJsonl decodes every line of the search-then-call fixture, in file order")
    func decodeJsonlDecodesEveryLine() throws {
        let events = try TranscriptAnalyzer.decodeJsonl(try Self.loadFixture("SearchThenCallTranscript.jsonl"))

        #expect(events.count == 10)
        #expect(events.map(\.seq) == Array(0...9))
        #expect(events.first?.kind == .session)
        #expect(events.first?.routerId == ULID("01ARZ3NDEKTSV4RRFFQ69G5FAV"))
        #expect(events.last?.kind == .response)
    }

    @Test("decodeJsonl throws on a malformed line")
    func decodeJsonlThrowsOnMalformedLine() {
        #expect(throws: (any Error).self) {
            try TranscriptAnalyzer.decodeJsonl("not JSON at all")
        }
    }

    @Test("decodeJsonl ignores blank lines")
    func decodeJsonlIgnoresBlankLines() throws {
        let jsonl = """
            {"routerId":"01ARZ3NDEKTSV4RRFFQ69G5FAV","sessionId":"01ARZ3NDEKTSV4RRFFQ69G5FAA","slot":"standard","seq":0,"ts":1,"kind":"session"}

            {"routerId":"01ARZ3NDEKTSV4RRFFQ69G5FAV","sessionId":"01ARZ3NDEKTSV4RRFFQ69G5FAA","slot":"standard","seq":1,"ts":2,"kind":"prompt","text":"hi"}
            """
        let events = try TranscriptAnalyzer.decodeJsonl(jsonl)
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
        let events = try TranscriptAnalyzer.decodeJsonl(try Self.loadFixture("SearchThenCallTranscript.jsonl"))
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

    // MARK: - findApisPrecedesRunCode(in:)

    @Test("findApisPrecedesRunCode is true for the search-then-call fixture")
    func findApisPrecedesRunCodeTrueForSearchThenCall() throws {
        let events = try TranscriptAnalyzer.decodeJsonl(try Self.loadFixture("SearchThenCallTranscript.jsonl"))
        let steps = TranscriptAnalyzer.steps(in: events, slot: .standard)
        #expect(TranscriptAnalyzer.findApisPrecedesRunCode(in: steps))
    }

    @Test("findApisPrecedesRunCode is false for the repair fixture (no findAPIs step at all)")
    func findApisPrecedesRunCodeFalseForRepair() throws {
        let events = try TranscriptAnalyzer.decodeJsonl(try Self.loadFixture("RepairTranscript.jsonl"))
        let steps = TranscriptAnalyzer.steps(in: events, slot: .standard)
        #expect(!TranscriptAnalyzer.findApisPrecedesRunCode(in: steps))
    }

    @Test("findApisPrecedesRunCode is false when there is no runCode step at all")
    func findApisPrecedesRunCodeFalseWithNoRunCode() {
        let steps: [AgentStep] = [.findAPIs(task: "look around"), .final(text: "done")]
        #expect(!TranscriptAnalyzer.findApisPrecedesRunCode(in: steps))
    }

    @Test("findApisPrecedesRunCode is true across multiple findAPIs calls, using the last findAPIs before runCode")
    func findApisPrecedesRunCodeTrueWithMultipleFindApisCalls() {
        let steps: [AgentStep] = [
            .findAPIs(task: "look around"),
            .findAPIs(task: "narrow it down"),
            .runCode(code: "return 1;"),
            .final(text: "done"),
        ]
        #expect(TranscriptAnalyzer.findApisPrecedesRunCode(in: steps))
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
        let events = try TranscriptAnalyzer.decodeJsonl(try Self.loadFixture("RepairTranscript.jsonl"))
        let steps = TranscriptAnalyzer.steps(in: events, slot: .standard)
        #expect(TranscriptAnalyzer.runCodeStepsBeforeFinal(in: steps) == 2)
    }

    @Test("runCodeStepsBeforeFinal counts one attempt for the search-then-call fixture")
    func runCodeStepsBeforeFinalCountsOneForSearchThenCall() throws {
        let events = try TranscriptAnalyzer.decodeJsonl(try Self.loadFixture("SearchThenCallTranscript.jsonl"))
        let steps = TranscriptAnalyzer.steps(in: events, slot: .standard)
        #expect(TranscriptAnalyzer.runCodeStepsBeforeFinal(in: steps) == 1)
    }

    @Test("runCodeStepsBeforeFinal counts every runCode step when there is no final step")
    func runCodeStepsBeforeFinalCountsAllWithNoFinal() {
        let steps: [AgentStep] = [.runCode(code: "1"), .runCode(code: "2")]
        #expect(TranscriptAnalyzer.runCodeStepsBeforeFinal(in: steps) == 2)
    }

    // MARK: - selections(in:slot:)

    @Test("selections decodes the selection tier's flash-slot response from the search-then-call fixture")
    func selectionsDecodesSelectionTierResponse() throws {
        let events = try TranscriptAnalyzer.decodeJsonl(try Self.loadFixture("SearchThenCallTranscript.jsonl"))
        let found = try TranscriptAnalyzer.selections(in: events, slot: .flash)

        #expect(found.count == 1)
        #expect(found[0].ids == ["tripCities", "weather"])
    }

    @Test("selections decodes multiple flash-slot responses, one per findAPIs call, in recorded order")
    func selectionsDecodesMultipleResponsesInOrder() throws {
        let events = [
            TranscriptEvent(
                routerId: .generate(),
                sessionId: .generate(),
                slot: .flash,
                seq: 0,
                ts: Date(),
                kind: .response,
                text: cannedTripCitiesSelectionJson
            ),
            TranscriptEvent(
                routerId: .generate(),
                sessionId: .generate(),
                slot: .flash,
                seq: 1,
                ts: Date(),
                kind: .response,
                text: cannedWeatherSelectionJson
            ),
        ]
        let found = try TranscriptAnalyzer.selections(in: events, slot: .flash)
        #expect(found.map(\.ids) == [["tripCities"], ["weather"]])
    }

    @Test("selections throws when a flash-slot response isn't valid Selection JSON")
    func selectionsThrowsOnInvalidJson() {
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
            try TranscriptAnalyzer.selections(in: events, slot: .flash)
        }
    }
}

/// One canned, schema-valid `Selection` JSON payload naming `tripCities`
/// only — the ids-only shape a real `.selection`-mode `MetadataSearcher`'s
/// root session decodes.
private let cannedTripCitiesSelectionJson = #"{"ids":["tripCities"]}"#

/// A second canned payload naming `weather` — used where a test needs a
/// distinct selection result, one per recorded `findAPIs` call.
private let cannedWeatherSelectionJson = #"{"ids":["weather"]}"#

/// A fixture `name` passed to `loadFixture(_:)` that failed the
/// letters/digits/`-`/`_`/`.` whitelist check — guards against the name
/// being used to construct a path outside `Goldens/` (e.g. via `..`
/// traversal segments or path separators).
private struct InvalidFixtureNameError: Error, CustomStringConvertible {
    let name: String
    var description: String { "invalid fixture name: \(name)" }
}
