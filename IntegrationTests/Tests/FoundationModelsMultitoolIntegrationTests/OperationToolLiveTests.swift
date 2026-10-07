import Foundation
import FoundationModels
import ScenarioGrading
import Testing

@testable import FoundationModelsMultitool

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
/// These are the three queries the card names, one for each verb they
/// declare. Card `^3vtvrzg` removed two more, because each declared the same
/// verb as a query that stays and so proved nothing more (approximately 7 s
/// of selection each on the CI runner `mini`): "attach a label to a note"
/// (`tagNote`, the same as "put the tag urgent on note-2") and "show every
/// note" (`listNote`, the same as "how many notes are there").
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
///    entries, so a query has distractors to miss it among. The group
///    ``operationToolQueries`` runs through
///    `FilesAndShellSurface.driveGradedGroup`, exactly as
///    `AgentSurfaceDiscoveryTests` runs its group. It holds that each verb
///    path a query declares is a path of the catalog, so the `@Operation`
///    macro expanded the notes tool into those verbs, and that each answer
///    holds only catalog paths, each one time, inside the limit. It prints
///    how many declared verbs the model found, and asserts nothing on that
///    count: card `^xr5w83f` removed the floor of one declared verb for each
///    query, because that count measures the model.
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
    .timeLimit(IntegrationHangGuard.timeLimit)
)
struct OperationToolLiveTests {
    @Test("the notes verbs stand in the catalog beside the distractors, and each answer holds only catalog paths")
    func notesVerbsStandInTheCatalogBesideTheDistractors() async throws {
        try await withLiveRouterFixture(name: operationDiscoveryScenarioName) { fixture in
            let notes = try IntegrationNotesTool.make(store: IntegrationNotesStore())
            try await makeFilesAndShellSurface(over: fixture, adding: [notes])
                .driveGradedGroup(
                    of: operationToolQueries, recordedBy: fixture, reportedAs: operationDiscoveryScenarioName)
        }
    }

    @Test("the model searches, runs one snippet that adds and tags the note, and names the id of the stored note")
    func searchThenCallStoresTheNoteAndNamesItsID() async throws {
        let store = IntegrationNotesStore()
        let notes = try IntegrationNotesTool.make(store: store)
        try await runGatedTurnScenario(
            named: operationSearchThenCallScenarioName,
            prompt: operationSearchThenCallPrompt,
            tools: { try makeScenarioSurface(over: [notes], on: $0).tools },
            reading: { turn, elapsed in
                let stored = await store.list()
                return GatedTurnReading(
                    checks: Self.searchThenCallChecks(turn: turn, stored: stored),
                    resultLine: gatedResultLine(
                        of: turn,
                        elapsed: elapsed,
                        readings: ["stored=\(Self.descriptions(of: stored))", failedCallsReading(of: turn)],
                        replyPreviewCharacters: operationToolReplyPreviewCharacters))
            })
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
                held: Self.expectedNoteIsTheOnlyOne(in: stored),
                failureMessage:
                    "expected the store to hold one note titled \(groceriesTitle) with the tag \(shoppingTag), "
                    + "but it holds \(Self.descriptions(of: stored))"
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
    private static func expectedNoteIsTheOnlyOne(in stored: [IntegrationNote]) -> Bool {
        stored.count == 1 && stored.allSatisfy { $0.title == groceriesTitle && $0.tags.contains(shoppingTag) }
    }

    /// One line for each stored note: its id, its title and its tags.
    ///
    /// - Parameter stored: the notes the fixture store holds.
    /// - Returns: the notes, readable on one printed line.
    private static func descriptions(of stored: [IntegrationNote]) -> [String] {
        stored.map { "\($0.id) \"\($0.title)\" \($0.tags)" }
    }
}
