import Testing

@testable import FoundationModelsMultitool

/// One way a discovery answer breaks a rule that the code of this package
/// controls.
enum DiscoveryAnswerFault: Equatable, Sendable {

    /// The answer holds a path that the catalog does not define.
    case pathNotInCatalog(String)

    /// The answer holds this path more than one time.
    case repeatedPath(String)

    /// The answer holds more paths than the limit of the call.
    case overLimit(count: Int, limit: Int)
}

/// The rules every gated discovery suite holds each answer to.
struct DiscoveryAnswerCheck: Sendable {

    /// Every path the catalog defines.
    let catalog: Set<String>

    /// The most paths one answer may hold.
    let limit: Int

    /// Makes the check for one catalog and one limit.
    ///
    /// - Parameters:
    ///   - paths: the paths the catalog defines.
    ///   - limit: the most paths one answer may hold.
    init(catalog paths: [String], limit: Int) {
        catalog = Set(paths)
        self.limit = limit
    }

    /// Every rule that `matchedPaths` breaks.
    ///
    /// - Parameter matchedPaths: the paths of one answer, in answer order.
    /// - Returns: the faults, or an empty list for an answer that holds every
    ///   rule.
    func faults(in matchedPaths: [String]) -> [DiscoveryAnswerFault] {
        let outside = matchedPaths
            .filter { !catalog.contains($0) }
            .map(DiscoveryAnswerFault.pathNotInCatalog)
        let repeated = matchedPaths.indices
            .filter { matchedPaths[..<$0].contains(matchedPaths[$0]) }
            .map { DiscoveryAnswerFault.repeatedPath(matchedPaths[$0]) }
        let overLimit =
            matchedPaths.count > limit
            ? [DiscoveryAnswerFault.overLimit(count: matchedPaths.count, limit: limit)]
            : []
        return outside + repeated + overLimit
    }

    /// Records one issue when one answer breaks a rule.
    ///
    /// - Parameters:
    ///   - matchedPaths: the paths of the answer, in answer order.
    ///   - task: the query the answer came back for, for the message.
    func expectNoFault(in matchedPaths: [String], answering task: String) {
        let found = faults(in: matchedPaths)
        #expect(found.isEmpty, "\"\(task)\" answered \(matchedPaths), which breaks \(found)")
    }

    /// Records one issue for each answer of a graded group that breaks a rule.
    ///
    /// - Parameters:
    ///   - group: the graded group, one grade for each query.
    ///   - queries: the queries the group was driven over, in the same order.
    func expectNoFault(in group: DiscoveryGroupGrade, answering queries: [GradedDiscoveryQuery]) {
        #expect(group.grades.count == queries.count, "the group holds a grade count unlike its query count")
        for (grade, query) in zip(group.grades, queries) {
            expectNoFault(in: grade.matchedPaths, answering: query.task)
        }
    }

    /// The paths `query` declares correct that the catalog does not define.
    ///
    /// The printed correct count reads the declared paths. A declared path
    /// that the mount does not define can never be counted, so the printed
    /// reading would be false. The mount is the code of this package, thus
    /// this is a rule of the code and not of the model.
    ///
    /// - Parameter query: one graded query.
    /// - Returns: the declared paths outside the catalog, sorted.
    func declaredPathsOutsideTheCatalog(of query: GradedDiscoveryQuery) -> [String] {
        query.correctPaths.subtracting(catalog).sorted()
    }

    /// Records one issue for each query that declares a path the catalog does
    /// not define. See ``declaredPathsOutsideTheCatalog(of:)``.
    ///
    /// - Parameter queries: the graded queries of one group.
    func expectEveryDeclaredPathIsInTheCatalog(of queries: [GradedDiscoveryQuery]) {
        for query in queries {
            let missing = declaredPathsOutsideTheCatalog(of: query)
            #expect(missing.isEmpty, "\"\(query.task)\" declares \(missing), which the catalog does not define")
        }
    }
}

extension DiscoveryAnswerCheck {

    /// Makes the check for the surface of `registry`, with the limit
    /// `searchTools` takes when the host gives none: the size of the catalog.
    ///
    /// - Parameter registry: the registry whose surface entries are the
    ///   catalog.
    init(surfaceOf registry: MultiTool.Registry) {
        let paths = registry.surface.entries.map(\.path)
        self.init(catalog: paths, limit: paths.count)
    }
}
