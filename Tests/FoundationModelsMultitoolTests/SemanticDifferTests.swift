import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Tests for ``SemanticDiffer`` and ``SemanticFileChange`` — the port of
/// `parser/differ.rs` and of the parts of `git_types.rs` that the differ
/// uses, in `../swissarmyhammer/crates/swissarmyhammer-sem/src/`.
///
/// The Rust tests use the JSON and YAML plugins, which are not ported yet.
/// These tests use ``LineEntityPlugin`` (one entity for each `name = body`
/// line) with the same scenarios: an added file, a deleted file, a modified
/// value, a renamed key, counts over several files, and the commit metadata.
/// They add a moved entity (a file rename), the fallback plugin, and the
/// similarity of the plugin.
@Suite("SemanticDifferTests")
struct SemanticDifferTests {

    /// A registry with the line plugin for `.lines` only.
    private static func lineRegistry() -> ParserRegistry {
        var registry = ParserRegistry()
        registry.register(LineEntityPlugin())
        return registry
    }

    /// The diff of `fileChanges` over ``lineRegistry()``.
    private static func diff(
        _ fileChanges: [SemanticFileChange], commitSHA: String? = nil, author: String? = nil
    ) -> DiffResult {
        SemanticDiffer.computeSemanticDiff(
            fileChanges: fileChanges, registry: lineRegistry(), commitSHA: commitSHA, author: author)
    }

    /// The counts of `result` in the order added, modified, deleted, moved,
    /// renamed.
    private static func counts(_ result: DiffResult) -> [Int] {
        [result.addedCount, result.modifiedCount, result.deletedCount, result.movedCount, result.renamedCount]
    }

    // MARK: Scenarios of the Rust suite

    /// No file change gives a result with each count at 0.
    @Test("no file change gives zero counts")
    func noFileChangeGivesZeroCounts() {
        let result = Self.diff([])

        #expect(result.changes.isEmpty)
        #expect(result.fileCount == 0)
        #expect(Self.counts(result) == [0, 0, 0, 0, 0])
    }

    /// A new file gives one added change for each entity.
    @Test("an added file gives added changes")
    func anAddedFileGivesAddedChanges() {
        let result = Self.diff([
            SemanticFileChange(
                filePath: "app.lines", status: .added, oldFilePath: nil, beforeContent: nil,
                afterContent: "name = my-app\nversion = 1.0.0\n")
        ])

        #expect(result.fileCount == 1)
        #expect(Self.counts(result) == [2, 0, 0, 0, 0])
        #expect(result.changes.map(\.entityName) == ["name", "version"])
    }

    /// A removed file gives one deleted change for each entity.
    @Test("a deleted file gives deleted changes")
    func aDeletedFileGivesDeletedChanges() {
        let result = Self.diff([
            SemanticFileChange(
                filePath: "app.lines", status: .deleted, oldFilePath: nil,
                beforeContent: "name = my-app\nversion = 1.0.0\n", afterContent: nil)
        ])

        #expect(result.fileCount == 1)
        #expect(Self.counts(result) == [0, 0, 2, 0, 0])
    }

    /// A new value under the same key is one modified change, not an added
    /// and a deleted one.
    @Test("a new value under the same key is modified")
    func aNewValueUnderTheSameKeyIsModified() throws {
        let result = Self.diff([
            SemanticFileChange(
                filePath: "app.lines", status: .modified, oldFilePath: nil,
                beforeContent: "version = 1.0.0\n", afterContent: "version = 2.0.0\n")
        ])

        #expect(result.fileCount == 1)
        #expect(Self.counts(result) == [0, 1, 0, 0, 0])
        let change = try #require(result.changes.first)
        #expect(change.entityID == "app.lines::line::version")
        #expect(change.beforeContent == "1.0.0")
        #expect(change.afterContent == "2.0.0")
    }

    /// The same value under a new key is one renamed change.
    @Test("the same value under a new key is renamed")
    func theSameValueUnderANewKeyIsRenamed() {
        let result = Self.diff([
            SemanticFileChange(
                filePath: "config.lines", status: .modified, oldFilePath: nil,
                beforeContent: "timeout = 30\n", afterContent: "request_timeout = 30\n")
        ])

        #expect(Self.counts(result) == [0, 0, 0, 0, 1])
        #expect(result.changes.map(\.entityName) == ["request_timeout"])
    }

    /// The counts and the file count add up over several files.
    @Test("the counts add up over several files")
    func theCountsAddUpOverSeveralFiles() {
        let result = Self.diff([
            SemanticFileChange(
                filePath: "one.lines", status: .added, oldFilePath: nil, beforeContent: nil,
                afterContent: "a = 1\nb = 2\n"),
            SemanticFileChange(
                filePath: "two.lines", status: .added, oldFilePath: nil, beforeContent: nil, afterContent: "x = 10\n"),
        ])

        #expect(result.fileCount == 2)
        #expect(result.addedCount == 3)
        #expect(result.changes.map(\.filePath) == ["one.lines", "one.lines", "two.lines"])
    }

    /// The commit sha and the author go on each change.
    @Test("the commit sha and the author go on each change")
    func theCommitAndTheAuthorGoOnEachChange() {
        let result = Self.diff(
            [
                SemanticFileChange(
                    filePath: "meta.lines", status: .added, oldFilePath: nil, beforeContent: nil,
                    afterContent: "key = value\nother = thing\n")
            ],
            commitSHA: "abc1234", author: "Alice")

        #expect(result.changes.count == 2)
        #expect(result.changes.allSatisfy { $0.commitSHA == "abc1234" && $0.author == "Alice" })
    }

    /// Twenty files in one call give twenty changes in the order of the
    /// input, as the Rust `par_iter` and `collect` give them.
    @Test("many files keep the order of the input")
    func manyFilesKeepTheOrderOfTheInput() {
        let paths = (0..<20).map { "file\($0).lines" }
        let result = Self.diff(
            paths.map {
                SemanticFileChange(filePath: $0, status: .added, oldFilePath: nil, beforeContent: nil, afterContent: "key = value\n")
            })

        #expect(result.fileCount == 20)
        #expect(result.addedCount == 20)
        #expect(result.changes.map(\.filePath) == paths)
    }

    // MARK: More scenarios

    /// A renamed file reads its old side at the old path, thus each entity
    /// that is the same is moved, with the old path.
    @Test("a renamed file gives moved entities")
    func aRenamedFileGivesMovedEntities() throws {
        let result = Self.diff([
            SemanticFileChange(
                filePath: "new.lines", status: .renamed, oldFilePath: "old.lines",
                beforeContent: "keep = same\n", afterContent: "keep = same\n")
        ])

        #expect(Self.counts(result) == [0, 0, 0, 1, 0])
        let change = try #require(result.changes.first)
        #expect(change.oldFilePath == "old.lines")
        #expect(change.filePath == "new.lines")
        #expect(change.entityID == "new.lines::line::keep")
    }

    /// A file with no change in any entity adds no change and does not
    /// count as a file.
    @Test("a file with no entity change does not count")
    func aFileWithNoEntityChangeDoesNotCount() {
        let result = Self.diff([
            SemanticFileChange(
                filePath: "same.lines", status: .modified, oldFilePath: nil,
                beforeContent: "a = 1\n", afterContent: "a = 1\n\n")
        ])

        #expect(result.changes.isEmpty)
        #expect(result.fileCount == 0)
    }

    /// Two changes of the same path count as one file, as the Rust
    /// `HashSet` of paths does.
    @Test("two changes of one path count as one file")
    func twoChangesOfOnePathCountAsOneFile() {
        let change = SemanticFileChange(
            filePath: "app.lines", status: .added, oldFilePath: nil, beforeContent: nil, afterContent: "a = 1\n")

        let result = Self.diff([change, change])

        #expect(result.fileCount == 1)
        #expect(result.addedCount == 2)
    }

    /// A file that no plugin reads, with no fallback plugin, adds nothing.
    @Test("a file that no plugin reads adds nothing")
    func aFileThatNoPluginReadsAddsNothing() {
        let result = Self.diff([
            SemanticFileChange(
                filePath: "data.xyz", status: .added, oldFilePath: nil, beforeContent: nil, afterContent: "a = 1\n")
        ])

        #expect(result.changes.isEmpty)
        #expect(result.fileCount == 0)
    }

    /// A file with an unknown extension goes to the fallback plugin.
    @Test("a file with an unknown extension goes to the fallback plugin")
    func aFileWithAnUnknownExtensionGoesToTheFallback() {
        var registry = Self.lineRegistry()
        registry.register(LineEntityPlugin(id: ParserRegistry.fallbackPluginID, extensions: []))

        let result = SemanticDiffer.computeSemanticDiff(
            fileChanges: [
                SemanticFileChange(
                    filePath: "data.xyz", status: .added, oldFilePath: nil, beforeContent: nil,
                    afterContent: "a = 1\n")
            ],
            registry: registry, commitSHA: nil, author: nil)

        #expect(result.addedCount == 1)
        #expect(result.changes.map(\.entityID) == ["data.xyz::line::a"])
    }

    /// The differ asks the plugin for the similarity of each pair. A plugin
    /// that gives 1 for each pair makes two unrelated entities one rename.
    @Test("the differ uses the similarity of the plugin")
    func theDifferUsesTheSimilarityOfThePlugin() {
        var registry = ParserRegistry()
        registry.register(FixedSimilarityPlugin(score: 1))
        let change = SemanticFileChange(
            filePath: "a.fixed", status: .modified, oldFilePath: nil,
            beforeContent: "old = alpha\n", afterContent: "new = omega\n")

        let result = SemanticDiffer.computeSemanticDiff(
            fileChanges: [change], registry: registry, commitSHA: nil, author: nil)

        #expect(result.changes.map(\.changeType) == [.renamed])
    }

    /// The line plugin gives each entity the line where it stands.
    @Test("the line plugin gives each entity its line")
    func theLinePluginGivesEachEntityItsLine() {
        let entities = LineEntityPlugin().extractEntities(content: "a = 1\nnot an entity\nb = 2", filePath: "x.lines")

        #expect(entities.map(\.name) == ["a", "b"])
        #expect(entities.map(\.startLine) == [1, 3])
        #expect(entities.map(\.endLine) == [1, 3])
    }

    // MARK: File status

    /// Each file status has the lowercase name of the Rust `Display`.
    @Test("each file status has its lowercase name")
    func eachFileStatusHasItsLowercaseName() {
        #expect(
            [FileStatus.added, .modified, .deleted, .renamed].map(\.rawValue)
                == ["added", "modified", "deleted", "renamed"])
    }
}
