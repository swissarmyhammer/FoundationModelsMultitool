import Foundation
import Testing

@testable import FoundationModelsMultitool
import ScenarioGrading

/// How many times each graded group drives its whole query list.
///
/// One round says nothing about a stochastic model. Between two recorded runs
/// of the ten queries of card `^zqz1zan`, one query answered five matches and
/// then six, and a single pass observed neither. Three rounds put that
/// variation in the printed record, and hold every round to the same level
/// rather than to the luck of one pass.
let discoveryRoundCount = 3

/// One query of a graded discovery group: the phrase a host gives
/// `searchTools`, and the catalog paths a reader of the tool descriptions says
/// answer it.
///
/// The correct paths are a declaration, never a measurement. They are written
/// by a person who read the nine tool descriptions of the surface, and they
/// are what turns a match count into a grade: a run that answers many paths
/// scores well only when those paths are the declared ones.
struct GradedDiscoveryQuery: Sendable {

    /// The phrase the host gives `searchTools`, verbatim.
    let task: String

    /// The catalog paths a reader says answer ``task``.
    let correctPaths: Set<String>
}

/// What one query scored in one round.
///
/// It carries the whole answer and both halves of it, so the printed line
/// shows which paths earned the correct count and which paths did not. The
/// wrong half is a reading and never an assertion — card `^kn9ay20` asks for
/// it to be printed until a level for it is known.
struct DiscoveryGrade: Sendable {

    /// Every path the answer spliced, in the order the answer listed them.
    let matchedPaths: [String]

    /// The matched paths the query declares correct, in matched order.
    let correctPaths: [String]

    /// The matched paths the query does not declare correct, in matched order.
    let wrongPaths: [String]

    /// How many declared-correct paths the answer found.
    var correctCount: Int { correctPaths.count }

    /// How many paths the answer returned that the query does not declare
    /// correct.
    var wrongCount: Int { wrongPaths.count }

    /// Grades one answer against one query.
    ///
    /// - Parameters:
    ///   - query: the query the answer came back for.
    ///   - matchedPaths: the paths the answer spliced, in answer order.
    init(query: GradedDiscoveryQuery, matchedPaths: [String]) {
        self.matchedPaths = matchedPaths
        correctPaths = matchedPaths.filter { query.correctPaths.contains($0) }
        wrongPaths = matchedPaths.filter { !query.correctPaths.contains($0) }
    }
}

/// What one whole pass of a graded group scored.
struct DiscoveryRound: Sendable {

    /// The one-based number of this round.
    let number: Int

    /// The grade of each query of the group, in the order the group lists
    /// them.
    let grades: [DiscoveryGrade]

    /// How many declared-correct paths this round found over the whole group.
    var correctCount: Int { grades.reduce(0) { $0 + $1.correctCount } }

    /// How many undeclared paths this round returned over the whole group.
    var wrongCount: Int { grades.reduce(0) { $0 + $1.wrongCount } }
}

/// Drives `queries` through `searchTools` ``discoveryRoundCount`` times and
/// grades every answer, printing one line for each query of each round and one
/// line for each round.
///
/// The raw ids of each call are read off the Router recording the same way
/// `SelectionForkPerCallTests` reads its fork trace. Each call adds its own
/// selections to the end of that recording, so the ids of one call are the
/// selections that stand past the ones already read.
///
/// - Parameters:
///   - queries: the group to drive, in the order it is listed.
///   - searchTools: the mounted production tool the queries go through.
///   - fixture: the resolved fixture whose recording the raw ids are read off.
///   - scenario: the label the printed lines carry.
/// - Returns: one ``DiscoveryRound`` for each round, in round order.
/// - Throws: whatever the tool call or the transcript read throws.
func gradeDiscoveryRounds(
    of queries: [GradedDiscoveryQuery],
    through searchTools: SearchToolsTool,
    recordedBy fixture: LiveRouterFixture,
    reportedAs scenario: String
) async throws -> [DiscoveryRound] {
    var rounds: [DiscoveryRound] = []
    var readSelections = 0
    for number in 1...discoveryRoundCount {
        var grades: [DiscoveryGrade] = []
        for (index, query) in queries.enumerated() {
            let feedback = try await searchTools.call(arguments: SearchToolsArguments(task: query.task))
            let grade = DiscoveryGrade(query: query, matchedPaths: catalogPaths(in: feedback))
            let selections = try NativeTranscript.selections(in: fixture.transcriptEvents(), slot: .flash)
            let rawIDs = selections.dropFirst(readSelections).flatMap(\.ids)
            readSelections = selections.count
            grades.append(grade)
            reportGatedResult(
                scenario: scenario,
                line: gradeLine(round: number, number: index + 1, query: query, grade: grade, rawIDs: rawIDs)
            )
        }
        let round = DiscoveryRound(number: number, grades: grades)
        reportGatedResult(scenario: scenario, line: roundLine(of: round, queryCount: queries.count))
        rounds.append(round)
    }
    return rounds
}

/// Holds every query of one round to finding at least one of the catalog
/// paths it declares correct.
///
/// This is the floor under the round level: a query that answered nothing, or
/// answered only paths no reader declared, fails here whatever the round total
/// is.
///
/// - Parameters:
///   - round: the round to hold.
///   - queries: the group the round was driven over, in the same order.
func expectEveryQueryFindsACorrectPath(in round: DiscoveryRound, of queries: [GradedDiscoveryQuery]) {
    for (index, grade) in round.grades.enumerated() {
        let query = queries[index]
        #expect(
            grade.correctCount >= 1,
            """
            round \(round.number) query \(index + 1) "\(query.task)" found no correct path; \
            it matched \(grade.matchedPaths) and declares \(query.correctPaths.sorted())
            """
        )
    }
}

/// The printed line of one graded query of one round.
///
/// Built in named pieces because one chained interpolation of this length
/// times the type checker out.
///
/// - Parameters:
///   - round: the one-based number of the round.
///   - number: the one-based position of the query in its group.
///   - query: the query that was driven.
///   - grade: what the answer scored.
///   - rawIDs: the ids the selection model answered for this call.
/// - Returns: the line to print.
private func gradeLine(
    round: Int, number: Int, query: GradedDiscoveryQuery, grade: DiscoveryGrade, rawIDs: [String]
) -> String {
    let counts =
        "round=\(round) q\(number) matches=\(grade.matchedPaths.count) "
        + "correct=\(grade.correctCount) wrong=\(grade.wrongCount)"
    let paths =
        "paths=\(grade.matchedPaths) correctPaths=\(grade.correctPaths) "
        + "wrongPaths=\(grade.wrongPaths) declared=\(query.correctPaths.sorted())"
    return "\(counts) \(paths) selection=\(rawIDs) query=\"\(query.task)\""
}

/// The printed line that closes one round.
///
/// - Parameters:
///   - round: the round to report.
///   - queryCount: how many queries the group holds.
/// - Returns: the line to print.
private func roundLine(of round: DiscoveryRound, queryCount: Int) -> String {
    "round=\(round.number) queries=\(queryCount) "
        + "correctTotal=\(round.correctCount) wrongTotal=\(round.wrongCount)"
}
