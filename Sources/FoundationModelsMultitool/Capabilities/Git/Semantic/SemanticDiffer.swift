// `SemanticDiffer` — the entity-level diff of a set of changed files.
//
// A port of `parser/differ.rs` in
// `../swissarmyhammer/crates/swissarmyhammer-sem/src/`: the struct
// `DiffResult` and the function `compute_semantic_diff`. For each file,
// the plugin of the file cuts each side into entities, and
// ``EntityMatcher`` pairs them with the similarity of that plugin.
//
// The Rust code runs the files in parallel with `rayon` and collects the
// results in input order. This port runs them one after the other in input
// order, thus the result is the same. The Rust code also catches a panic of
// a plugin and uses no entity; a Swift plugin gives no entity itself
// (``SemanticParserPlugin/extractEntities(content:filePath:)``).
//
// One step is not in Rust, and it is off by default: the changes of the
// lines that no entity holds (`UncoveredLines.swift`, task `^8fd3kgk`).

/// The result of a semantic diff: `DiffResult` in `parser/differ.rs`.
struct DiffResult: Equatable, Sendable {

    /// The changes, file by file in input order.
    let changes: [SemanticChange]

    /// The number of distinct file paths with at least one change.
    let fileCount: Int

    /// The number of `added` changes.
    let addedCount: Int

    /// The number of `modified` changes.
    let modifiedCount: Int

    /// The number of `deleted` changes.
    let deletedCount: Int

    /// The number of `moved` changes.
    let movedCount: Int

    /// The number of `renamed` changes.
    let renamedCount: Int
}

/// The semantic differ of `parser/differ.rs`.
enum SemanticDiffer {

    /// The entity-level diff of `fileChanges`: `compute_semantic_diff` in
    /// `parser/differ.rs`.
    ///
    /// A file that no plugin reads adds no change. A file whose entities
    /// are all the same adds no change and does not count in
    /// ``DiffResult/fileCount``.
    ///
    /// With `reportsUncoveredLines`, each file also gives the changes of the
    /// lines that no entity holds (``UncoveredLines``), after its entity
    /// changes. That is not in Rust, thus it is off by default, and the
    /// golden tests of the port keep the Rust result.
    ///
    /// - Parameters:
    ///   - fileChanges: The changed files.
    ///   - registry: The plugins.
    ///   - commitSHA: The commit sha to write on each change, or `nil`.
    ///   - author: The author to write on each change, or `nil`.
    ///   - reportsUncoveredLines: Whether a changed line that no entity holds
    ///     is a change too.
    /// - Returns: The changes and their counts.
    static func computeSemanticDiff(
        fileChanges: [SemanticFileChange], registry: ParserRegistry, commitSHA: String?, author: String?,
        reportsUncoveredLines: Bool = false
    ) -> DiffResult {
        let options = FileDiffOptions(commitSHA: commitSHA, author: author, reportsUncoveredLines: reportsUncoveredLines)
        let changedFiles = fileChanges.compactMap { file in
            changes(of: file, registry: registry, options: options)
        }
        let changes = changedFiles.flatMap(\.changes)
        let count = { (type: ChangeType) in changes.count { $0.changeType == type } }
        return DiffResult(
            changes: changes,
            fileCount: Set(changedFiles.map(\.filePath)).count,
            addedCount: count(.added),
            modifiedCount: count(.modified),
            deletedCount: count(.deleted),
            movedCount: count(.moved),
            renamedCount: count(.renamed))
    }

    /// The changes of one file, or `nil` when no plugin reads the file or
    /// when the file has no change: the closure of the Rust `filter_map`.
    private static func changes(
        of file: SemanticFileChange, registry: ParserRegistry, options: FileDiffOptions
    ) -> (filePath: String, changes: [SemanticChange])? {
        guard let plugin = registry.plugin(forFilePath: file.filePath) else { return nil }
        let beforeEntities =
            file.beforeContent.map {
                plugin.extractEntities(content: $0, filePath: file.oldFilePath ?? file.filePath)
            } ?? []
        let afterEntities = file.afterContent.map { plugin.extractEntities(content: $0, filePath: file.filePath) } ?? []
        let result = EntityMatcher.matchEntities(
            before: beforeEntities, after: afterEntities,
            similarity: { plugin.similarity(between: $0, and: $1) },
            commitSHA: options.commitSHA, author: options.author)
        let lineChanges =
            options.reportsUncoveredLines
            ? UncoveredLines.changes(
                of: file, before: beforeEntities, after: afterEntities, commitSHA: options.commitSHA,
                author: options.author)
            : []
        let changes = result.changes + lineChanges
        guard !changes.isEmpty else { return nil }
        return (file.filePath, changes)
    }
}

/// The settings that each file of one ``SemanticDiffer`` call shares.
private struct FileDiffOptions {

    /// The commit sha to write on each change, or `nil`.
    let commitSHA: String?

    /// The author to write on each change, or `nil`.
    let author: String?

    /// Whether a changed line that no entity holds is a change too.
    let reportsUncoveredLines: Bool
}
