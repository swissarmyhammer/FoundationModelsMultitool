import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Tests for ``UncoveredLines``: the changes of the lines that no entity of a
/// file holds (task `^8fd3kgk`), through ``SemanticDiffer``.
///
/// The tests use ``LineEntityPlugin``: each `name = body` line is one entity,
/// and each other line is a line that no entity holds. Thus each test checks
/// the line changes and not a language plugin.
@Suite("UncoveredLinesTests")
struct UncoveredLinesTests {

    /// The path of the file of each test, which ``LineEntityPlugin`` reads.
    private static let filePath = "app.lines"

    /// The 1-based line of the note between the two entities of
    /// ``aChangedLineBetweenTwoEntitiesIsOneModifiedChange()``.
    private static let noteLine = 2

    /// The diff of one changed file over ``LineEntityPlugin``.
    ///
    /// - Parameters:
    ///   - before: The old text, or `nil` for a new file.
    ///   - after: The new text, or `nil` for a removed file.
    ///   - reportsUncoveredLines: Whether the line changes are in the result.
    /// - Returns: The diff.
    private static func diff(before: String?, after: String?, reportsUncoveredLines: Bool = true) -> DiffResult {
        var registry = ParserRegistry()
        registry.register(LineEntityPlugin())
        let file = SemanticFileChange(
            filePath: filePath, status: .modified, oldFilePath: nil, beforeContent: before, afterContent: after)
        return SemanticDiffer.computeSemanticDiff(
            fileChanges: [file], registry: registry, commitSHA: nil, author: nil,
            reportsUncoveredLines: reportsUncoveredLines)
    }

    /// The changes of `result` that are line changes.
    private static func lineChanges(of result: DiffResult) -> [SemanticChange] {
        result.changes.filter { $0.entityType == UncoveredLines.entityType }
    }

    /// A changed line between two entities is one `modified` change that
    /// names its line, holds the old and the new text, and adds no entity
    /// change.
    @Test("a changed line between two entities is one modified change")
    func aChangedLineBetweenTwoEntitiesIsOneModifiedChange() throws {
        let result = Self.diff(
            before: "name = app\n# old note\nversion = 1\n", after: "name = app\n# new note\nversion = 1\n")

        let change = try #require(result.changes.first)
        #expect(result.changes.count == 1)
        #expect(result.modifiedCount == 1)
        #expect(result.fileCount == 1)
        #expect(change.changeType == .modified)
        #expect(change.entityType == UncoveredLines.entityType)
        #expect(change.entityName == SemanticEntity.lineSpanName(firstLine: Self.noteLine, lastLine: Self.noteLine))
        #expect(change.beforeContent == "# old note")
        #expect(change.afterContent == "# new note")
        #expect(change.filePath == Self.filePath)
    }

    /// Two runs of changed lines, apart from each other, are two changes in
    /// line order: one `added` and one `deleted`.
    @Test("two runs of changed lines are two changes in line order")
    func twoRunsOfChangedLinesAreTwoChangesInLineOrder() {
        let result = Self.diff(
            before: "# header\nname = app\nversion = 1\n# footer\n",
            after: "# header\n# added\nname = app\nversion = 1\n")

        let changes = Self.lineChanges(of: result)
        #expect(changes.map(\.changeType) == [.added, .deleted])
        #expect(changes.first?.afterContent == "# added")
        #expect(changes.last?.beforeContent == "# footer")
        #expect(changes.last?.afterContent == nil)
    }

    /// An entity change and a line change in one file are both reported,
    /// the entity change first.
    @Test("an entity change and a line change are both reported")
    func anEntityChangeAndALineChangeAreBothReported() {
        let result = Self.diff(before: "name = app\n", after: "name = other\n# note\n")

        #expect(result.changes.map(\.entityType) == [LineEntityPlugin.entityType, UncoveredLines.entityType])
        #expect(result.changes.map(\.changeType) == [.modified, .added])
    }

    /// A run of blank lines only is no change.
    @Test("a run of blank lines is no change")
    func aRunOfBlankLinesIsNoChange() {
        let result = Self.diff(before: "name = app\nversion = 1\n", after: "name = app\n\n   \nversion = 1\n")

        #expect(result.changes.isEmpty)
        #expect(result.fileCount == 0)
    }

    /// The default keeps the Rust result: a changed line that no entity
    /// holds is no change.
    @Test("by default a changed line that no entity holds is no change")
    func byDefaultAChangedLineThatNoEntityHoldsIsNoChange() {
        let result = Self.diff(
            before: "name = app\n", after: "name = app\n# note\n", reportsUncoveredLines: false)

        #expect(result.changes.isEmpty)
        #expect(result.fileCount == 0)
    }
}
