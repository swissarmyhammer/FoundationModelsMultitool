import Foundation

@testable import FoundationModelsMultitool
import ScenarioGrading

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

/// What one query scored.
///
/// It carries the whole answer and both halves of it, so the printed line
/// shows which paths earned the correct count and which paths did not. Both
/// halves are readings and never assertions: they measure how well the model
/// selects, and card `^xr5w83f` removed every fixed level on them. The rules
/// an answer is held to are in ``DiscoveryAnswerCheck``.
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

/// What one pass over a graded group scored.
///
/// Each query of the group runs one time. Two CI runs (`36609306669` and
/// `36951032341`) drove each of the four discovery groups three times in one
/// test. In both runs, each query printed the same paths and the same raw
/// selection ids in all three passes. The second and the third pass thus
/// measured nothing new, and they cost approximately 500 s of each run.
struct DiscoveryGroupGrade: Sendable {

    /// The grade of each query of the group, in the order the group lists
    /// them.
    let grades: [DiscoveryGrade]

    /// How many declared-correct paths the group found over all its queries.
    var correctCount: Int { grades.reduce(0) { $0 + $1.correctCount } }

    /// How many undeclared paths the group returned over all its queries.
    var wrongCount: Int { grades.reduce(0) { $0 + $1.wrongCount } }
}

/// Drives each query of `queries` through `searchTools` one time and grades
/// every answer, printing one line for each query and one line for the whole
/// group.
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
/// - Returns: the grade of the group.
/// - Throws: whatever the tool call or the transcript read throws.
func gradeDiscoveryGroup(
    of queries: [GradedDiscoveryQuery],
    through searchTools: SearchToolsTool,
    recordedBy fixture: LiveRouterFixture,
    reportedAs scenario: String
) async throws -> DiscoveryGroupGrade {
    var grades: [DiscoveryGrade] = []
    var readSelections = 0
    for (index, query) in queries.enumerated() {
        let feedback = try await searchTools.call(arguments: SearchToolsArguments(task: query.task))
        let grade = DiscoveryGrade(query: query, matchedPaths: catalogPaths(in: feedback))
        let selections = try NativeTranscript.selections(in: fixture.transcriptEvents(), slot: .flash)
        let rawIDs = selections.dropFirst(readSelections).flatMap(\.ids)
        readSelections = selections.count
        grades.append(grade)
        reportGatedResult(
            scenario: scenario,
            line: gradeLine(number: index + 1, query: query, grade: grade, rawIDs: rawIDs)
        )
    }
    let group = DiscoveryGroupGrade(grades: grades)
    reportGatedResult(scenario: scenario, line: groupLine(of: group, queryCount: queries.count))
    return group
}

/// The printed line of one graded query.
///
/// Built in named pieces because one chained interpolation of this length
/// times the type checker out.
///
/// - Parameters:
///   - number: the one-based position of the query in its group.
///   - query: the query that was driven.
///   - grade: what the answer scored.
///   - rawIDs: the ids the selection model answered for this call.
/// - Returns: the line to print.
private func gradeLine(
    number: Int, query: GradedDiscoveryQuery, grade: DiscoveryGrade, rawIDs: [String]
) -> String {
    let counts =
        "q\(number) matches=\(grade.matchedPaths.count) "
        + "correct=\(grade.correctCount) wrong=\(grade.wrongCount)"
    let paths =
        "paths=\(grade.matchedPaths) correctPaths=\(grade.correctPaths) "
        + "wrongPaths=\(grade.wrongPaths) declared=\(query.correctPaths.sorted())"
    return "\(counts) \(paths) selection=\(rawIDs) query=\"\(query.task)\""
}

/// The printed line that closes one group.
///
/// - Parameters:
///   - group: the graded group to report.
///   - queryCount: how many queries the group holds.
/// - Returns: the line to print.
private func groupLine(of group: DiscoveryGroupGrade, queryCount: Int) -> String {
    "queries=\(queryCount) correctTotal=\(group.correctCount) wrongTotal=\(group.wrongCount)"
}
