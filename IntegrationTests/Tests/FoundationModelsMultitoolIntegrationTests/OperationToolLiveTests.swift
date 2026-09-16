import Foundation
import FoundationModels
import ScenarioGrading
import Testing

@testable import FoundationModelsMultitool

/// The time limit of each test of this suite, in minutes.
///
/// The discovery test makes five `searchTools` calls in each of
/// ``discoveryRoundCount`` rounds. The search-then-call test drives one turn
/// of the shipped profile, and `SearchThenCallTests` gives one such turn the
/// same twelve minutes. A run that reaches the limit is parked, not slow.
private let operationToolTimeLimitMinutes = 12

/// The label the discovery test prints its result lines under.
private let operationDiscoveryScenarioName = "operationToolDiscovery"

/// The label the search-then-call test prints its result lines under.
private let operationSearchThenCallScenarioName = "operationToolSearchThenCall"

/// How many characters of the reply the `RESULT` line shows.
private let operationToolReplyPreviewCharacters = 120

/// The prompt of the search-then-call test, verbatim from the card.
private let operationSearchThenCallPrompt =
    "Add a note titled Groceries with the body milk and eggs, then tag it shopping, and tell me its id."

/// The title the prompt gives the note.
private let groceriesTitle = "Groceries"

/// The tag the prompt asks for.
private let shoppingTag = "shopping"

/// The label of the check that a `searchTools` call came before the first
/// `runCode` call.
private let searchedFirstCheckName = "searchedFirst"

/// The label of the check that the model made exactly one `runCode` call.
private let oneRunCodeCheckName = "oneRunCode"

/// The label of the check that the store holds the one expected note.
private let storeHoldsTheNoteCheckName = "storeHoldsTheNote"

/// The graded queries of the discovery test, each beside the verb path of
/// the notes tool a reader of the five operation descriptions says answers
/// it.
///
/// The first three are the queries the card names. The last two are
/// semantic: neither names a verb, a noun of the surface or a note id, so a
/// match rests on the description of the verb and on nothing else.
let operationToolQueries = [
    GradedDiscoveryQuery(
        task: "add a note titled Groceries",
        correctPaths: [IntegrationNotesTool.addNotePath]),
    GradedDiscoveryQuery(
        task: "put the tag urgent on note-2",
        correctPaths: [IntegrationNotesTool.tagNotePath]),
    GradedDiscoveryQuery(
        task: "how many notes are there",
        correctPaths: [IntegrationNotesTool.listNotePath]),
    GradedDiscoveryQuery(
        task: "attach a label to a note",
        correctPaths: [IntegrationNotesTool.tagNotePath]),
    GradedDiscoveryQuery(
        task: "show every note",
        correctPaths: [IntegrationNotesTool.listNotePath]),
]

/// The gated suite that proves the operation-tool feature with the real
/// stack: the `@Operation` macro, `OperationTool` and a real model.
///
/// **What the unit tests cannot say.** `OperationMountTests`,
/// `OperationSearchTests` and `OperationRunCodeTests` in the root package
/// drive a hand-conformed `OperationDescribing` fixture with no model. They
/// show that the registry expands a parent into verbs, that the search index
/// holds the verbs and that a snippet reaches one. They do not show that a
/// tool the macros build expands the same way, nor that a model finds a verb
/// by its description and then writes a snippet that calls it. This suite
/// shows both, on `Fixtures/IntegrationNotesOperationTool.swift`.
///
/// **Two tests, two questions.**
///
/// 1. Discovery. The notes tool stands beside the nine files-and-shell
///    entries, so a query has distractors to miss it among. Every query of
///    ``operationToolQueries`` must find a declared verb path in every one of
///    ``discoveryRoundCount`` rounds, graded by `gradeDiscoveryRounds` and
///    held by `expectEveryQueryFindsACorrectPath`, exactly as
///    `HeldOutSurfaceDiscoveryTests` grades its group. No round level: the
///    group is five queries with one declared path each, so the per-query
///    floor is the whole level.
/// 2. Search then call. One prompt asks the model to add a note, tag it and
///    report its id. The route is read off `StreamedTurn.calls`, which is the
///    record `streamTurn` keeps of every session tool call: a `searchTools`
///    call precedes the first `runCode` call, and there is one `runCode` call.
///    The outcome is read off the fixture store and off the reply: the store
///    holds one note with the title and the tag the prompt gave, and the
///    reply names the id of that note. `ScenarioCallLog` is not the record
///    here, because it holds fixture tool calls only; `searchTools` and
///    `runCode` are session tools, and the turn stream is where they are
///    recorded.
///
/// **Why the shipped profile.** Both tests grade a capability claim about the
/// configuration a host really gets, so both resolve `multitoolTinyProfile`,
/// the profile every suite that grades an answer must resolve.
///
/// Packaged like every gated suite: in the nested `IntegrationTests` package,
/// out of reach of the root `swift test`, run under
/// `swift test --package-path IntegrationTests --no-parallel`, and skipping
/// cleanly when the live Router path throws
/// `GenerationError.notWiredForLiveInference`.
@Suite(
    "Gated operation tool: a real @Operation tool is found and called through runCode",
    .serialized,
    .timeLimit(.minutes(operationToolTimeLimitMinutes))
)
struct OperationToolLiveTests {
    @Test("every query finds a declared verb of the notes tool beside the files-and-shell distractors, in every round")
    func notesVerbsAreFoundBesideTheDistractors() async throws {
        try await withLiveRouterFixture(name: operationDiscoveryScenarioName) { fixture in
            let notes = try IntegrationNotesTool.make(store: IntegrationNotesStore())
            let surface = try makeFilesAndShellSurface(over: fixture, adding: [notes])
            reportCatalogSize(of: surface.registry, reportedAs: operationDiscoveryScenarioName)

            let rounds = try await gradeDiscoveryRounds(
                of: operationToolQueries,
                through: surface.searchTools,
                recordedBy: fixture,
                reportedAs: operationDiscoveryScenarioName)

            for round in rounds {
                expectEveryQueryFindsACorrectPath(in: round, of: operationToolQueries)
            }
        }
    }

    @Test("the model searches, runs one snippet that adds and tags the note, and names the id of the stored note")
    func searchThenCallStoresTheNoteAndNamesItsID() async throws {
        try await withLiveRouterFixture(name: operationSearchThenCallScenarioName) { fixture in
            let store = IntegrationNotesStore()
            let notes = try IntegrationNotesTool.make(store: store)
            let surface = try makeScenarioSurface(over: [notes], on: fixture)
            // No instructions, for the reason `runNativeIntegrationScenario`
            // gives: mounting the tools is the whole product surface.
            let session = fixture.profile.standard.makeSession(
                tools: surface.tools,
                discoveryPriming: scenarioDiscoveryPriming
            )

            let start = Date()
            let turn = try await streamTurn(of: session, prompt: operationSearchThenCallPrompt)
            let elapsed = Date().timeIntervalSince(start)
            let stored = await store.list()

            grade(
                scenario: operationSearchThenCallScenarioName,
                checks: Self.searchThenCallChecks(turn: turn, stored: stored))
            reportGatedResult(
                scenario: operationSearchThenCallScenarioName,
                line: Self.resultLine(turn: turn, stored: stored, elapsed: elapsed))
        }
    }

    /// The conditions the search-then-call run is graded on, in reporting
    /// order: the route, the store, and the reply.
    ///
    /// - Parameters:
    ///   - turn: the streamed turn, with every session tool call it made.
    ///   - stored: the notes the fixture store holds after the turn.
    /// - Returns: every condition, for `grade(scenario:checks:)`.
    private static func searchThenCallChecks(turn: StreamedTurn, stored: [IntegrationNote]) -> [ScenarioCheck] {
        let callNames = turn.calls.map(\.name)
        let runCodeCalls = callNames.count { $0 == MultiTool.runCodePath }
        var checks = [
            ScenarioCheck(
                name: searchedFirstCheckName,
                held: NativeTranscript.searchToolsPrecedesRunCode(in: turn.calls),
                failureMessage:
                    "expected a \(MultiTool.searchToolsPath) call before the first \(MultiTool.runCodePath) call, "
                    + "but the calls were \(callNames)"
            ),
            ScenarioCheck(
                name: oneRunCodeCheckName,
                held: runCodeCalls == 1,
                failureMessage: "expected one \(MultiTool.runCodePath) call, but the calls were \(callNames)"
            ),
            ScenarioCheck(
                name: storeHoldsTheNoteCheckName,
                held: Self.holdsTheExpectedNote(stored),
                failureMessage:
                    "expected the store to hold one note titled \(groceriesTitle) with the tag \(shoppingTag), "
                    + "but it holds \(Self.describe(stored))"
            ),
        ]
        // The id of a stored note, and never a literal: the reply is graded
        // on the id the store really gave, so an empty store fails this check
        // with the empty candidate list in its message.
        checks += answerChecks(turn.answer, containsOneOf: stored.map(\.id), mustNotContain: [])
        return checks
    }

    /// Whether `stored` is exactly one note with the title and the tag the
    /// prompt gave.
    ///
    /// - Parameter stored: the notes the fixture store holds.
    /// - Returns: `true` for the one expected note.
    private static func holdsTheExpectedNote(_ stored: [IntegrationNote]) -> Bool {
        stored.count == 1 && stored.allSatisfy { $0.title == groceriesTitle && $0.tags.contains(shoppingTag) }
    }

    /// One line for each stored note: its id, its title and its tags.
    ///
    /// - Parameter stored: the notes the fixture store holds.
    /// - Returns: the notes, readable on one printed line.
    private static func describe(_ stored: [IntegrationNote]) -> [String] {
        stored.map { "\($0.id) \"\($0.title)\" \($0.tags)" }
    }

    /// The `RESULT` line of the search-then-call run.
    ///
    /// Built in named pieces because one chained interpolation of this length
    /// times the type checker out.
    ///
    /// - Parameters:
    ///   - turn: the streamed turn.
    ///   - stored: the notes the fixture store holds after the turn.
    ///   - elapsed: how long the turn took, in seconds.
    /// - Returns: the reading to print after the scenario label.
    private static func resultLine(turn: StreamedTurn, stored: [IntegrationNote], elapsed: TimeInterval) -> String {
        let route = "elapsed=\(elapsed)s toolCalls=\(turn.toolCallCount) calls=\(turn.calls.map(\.name)) "
        let outcome = "stored=\(Self.describe(stored)) failedCalls=\(turn.failedCalls) "
        return route + outcome + "reply=\"\(turn.answer.prefix(operationToolReplyPreviewCharacters))\""
    }
}
