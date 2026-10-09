// `UncoveredLines` — the changes of the lines that no entity of a file holds.
//
// The entity diff (`SemanticDiffer`, `EntityMatcher`) compares entities
// only: a function, a class, a key, a section. A line that no entity holds —
// a comment at the end of a file, an import, a statement at the top level —
// is in no content hash, thus a change to that line gives no change at all
// (task `^8fd3kgk`: a comment line at the end of a Python file gave 0
// changes against `@HEAD`). The Rust source (`parser/differ.rs`) has the same
// gap. This type is not a port: it closes the gap for each plugin, because it
// reads only the lines and the line span of each entity, and each plugin
// gives both.
//
// The steps:
//
// 1. Each side becomes a list of pieces: each line that no entity span
//    holds, with its 1-based number in the file, and one marker for each
//    block of lines that entities hold. The marker keeps two runs apart when
//    an entity stands between them, thus a comment removed above a function
//    and a comment added below it are two changes, not one.
// 2. `LineDiff` aligns the two lists. Two markers are equal, and two lines
//    are equal when their texts are equal.
// 3. Each run of removed and added lines between two unchanged pieces, or
//    between a line and a marker, is one change of the entity type
//    ``UncoveredLines/entityType``: `added` when the run only adds lines,
//    `deleted` when it only removes lines, else `modified`. The change names
//    the line numbers of the new side, or of the old side for a `deleted`
//    run.
//
// A run whose lines are all blank is no change. A blank line between two
// entities moves when an entity is added or removed, and the entity change
// already reports that edit.

import Foundation

/// The changes of the lines that no entity of a file holds.
enum UncoveredLines {

    /// The entity type of each change that this type gives.
    static let entityType = "lines"

    /// The first part of each change id, as ``EntityMatcher`` writes it:
    /// `change::<entity id>` for `modified`, and `change::<type>::<entity id>`
    /// for `added` and `deleted`.
    private static let changeIDPrefix = "change"

    /// The changes of the lines that no entity holds, on the two sides of one
    /// file.
    ///
    /// - Parameters:
    ///   - file: The changed file, with the text of each side.
    ///   - before: The entities of the old side.
    ///   - after: The entities of the new side.
    ///   - commitSHA: The commit sha to write on each change, or `nil`.
    ///   - author: The author to write on each change, or `nil`.
    /// - Returns: One change for each run of changed lines that is not blank,
    ///   in line order.
    static func changes(
        of file: SemanticFileChange, before: [SemanticEntity], after: [SemanticEntity],
        commitSHA: String?, author: String?
    ) -> [SemanticChange] {
        let oldPieces = pieces(of: file.beforeContent, entities: before)
        let newPieces = pieces(of: file.afterContent, entities: after)
        return changedRuns(from: oldPieces, to: newPieces).compactMap { run in
            change(of: run, in: file, commitSHA: commitSHA, author: author)
        }
    }

    // MARK: Steps

    /// The pieces of one side: each line that no entity span holds, and one
    /// marker for each block of lines that entities hold.
    ///
    /// - Parameters:
    ///   - content: The text of the side, or `nil` for no side.
    ///   - entities: The entities of the side.
    /// - Returns: The pieces in line order. No side gives no piece.
    private static func pieces(of content: String?, entities: [SemanticEntity]) -> [LinePiece] {
        guard let content else { return [] }
        let covered = entities.reduce(into: IndexSet()) { covered, entity in
            guard entity.startLine <= entity.endLine else { return }
            covered.insert(integersIn: entity.startLine...entity.endLine)
        }
        let all = RustText.lines(of: content).enumerated().map { offset, text in
            let number = offset + 1
            return covered.contains(number) ? LinePiece.entities : .line(NumberedLine(number: number, text: text))
        }
        return all.enumerated().filter { index, piece in
            piece != .entities || index == all.startIndex || all[index - 1] != .entities
        }.map(\.element)
    }

    /// The runs of changed lines between the two sides, with the blank runs
    /// left out.
    ///
    /// The alignment anchors the common last pieces too
    /// (`trimmingCommonSuffix`), as `GitPatch` does, thus a late edit in a
    /// long file does not align the whole tail again.
    ///
    /// - Parameters:
    ///   - oldPieces: The pieces of the old side.
    ///   - newPieces: The pieces of the new side.
    /// - Returns: The runs that are not blank, in line order.
    private static func changedRuns(from oldPieces: [LinePiece], to newPieces: [LinePiece]) -> [ChangedRun] {
        var walk = RunWalk(oldPieces: oldPieces, newPieces: newPieces)
        for step in LineDiff.changes(
            from: oldPieces.map(\.alignmentKey), to: newPieces.map(\.alignmentKey), trimmingCommonSuffix: true)
        {
            walk.take(step)
        }
        return walk.finishedRuns().filter { !$0.isBlank }
    }

    /// The change of one run.
    ///
    /// - Parameters:
    ///   - run: The run, with at least one line.
    ///   - file: The changed file.
    ///   - commitSHA: The commit sha to write on the change, or `nil`.
    ///   - author: The author to write on the change, or `nil`.
    /// - Returns: The change, or `nil` for a run with no line.
    private static func change(
        of run: ChangedRun, in file: SemanticFileChange, commitSHA: String?, author: String?
    ) -> SemanticChange? {
        let isDeletion = run.added.isEmpty
        let named = isDeletion ? run.removed : run.added
        guard let first = named.first, let last = named.last else { return nil }
        let type: ChangeType = isDeletion ? .deleted : (run.removed.isEmpty ? .added : .modified)
        let filePath = isDeletion ? (file.oldFilePath ?? file.filePath) : file.filePath
        let name = SemanticEntity.lineSpanName(firstLine: first.number, lastLine: last.number)
        let entityID = SemanticEntity.makeID(filePath: filePath, entityType: entityType, name: name, parentID: nil)
        let idPrefix = type == .modified ? changeIDPrefix : "\(changeIDPrefix)::\(type.rawValue)"
        return SemanticChange(
            id: "\(idPrefix)::\(entityID)", entityID: entityID, changeType: type, entityType: entityType,
            entityName: name, filePath: filePath, oldFilePath: nil, beforeContent: run.removed.joinedText,
            afterContent: run.added.joinedText, commitSHA: commitSHA, author: author, isStructuralChange: nil)
    }
}

/// One line that no entity holds: its 1-based number in the file, and its
/// text.
private struct NumberedLine: Equatable {

    /// The 1-based number of the line in its file.
    let number: Int

    /// The text of the line, with no line end.
    let text: String
}

extension [NumberedLine] {

    /// The texts of the lines, joined by a newline, or `nil` for no line.
    fileprivate var joinedText: String? {
        isEmpty ? nil : map(\.text).joined(separator: "\n")
    }
}

/// One piece of a side: a line that no entity holds, or the marker of a
/// block of lines that entities hold.
private enum LinePiece: Equatable {

    /// A line that no entity holds.
    case line(NumberedLine)

    /// A block of one or more lines that entities hold.
    case entities

    /// What the alignment compares: the text of a line, with no number, or
    /// the marker. Thus a line that moved to another number is unchanged.
    var alignmentKey: AlignmentKey {
        switch self {
        case .line(let line):
            .text(line.text)
        case .entities:
            .entities
        }
    }

    /// The line of the piece, or `nil` for the marker.
    var line: NumberedLine? {
        guard case .line(let line) = self else { return nil }
        return line
    }
}

/// The part of a ``LinePiece`` that the alignment compares.
private enum AlignmentKey: Equatable {

    /// The text of a line that no entity holds.
    case text(String)

    /// The marker of a block of lines that entities hold.
    case entities
}

/// One run of changed lines between two unchanged pieces: the old lines it
/// removed and the new lines it added.
private struct ChangedRun {

    /// The lines of the old side that the run removed.
    var removed: [NumberedLine] = []

    /// The lines of the new side that the run added.
    var added: [NumberedLine] = []

    /// Whether the run holds no line.
    var isEmpty: Bool { removed.isEmpty && added.isEmpty }

    /// Whether each line of the run is blank: empty, or whitespace only.
    var isBlank: Bool {
        (removed + added).allSatisfy { RustText.trimmed($0.text).isEmpty }
    }
}

/// The walk over the steps of one `LineDiff` alignment, which cuts the steps
/// into runs of changed lines.
///
/// The alignment gives keys with no line number. Each removed or added step
/// takes the next piece of its side, thus the walk keeps one index into
/// each side and gets the line number back.
private struct RunWalk {

    /// The pieces of the old side.
    private let oldPieces: [LinePiece]

    /// The pieces of the new side.
    private let newPieces: [LinePiece]

    /// The index in ``oldPieces`` of the next old piece.
    private var oldIndex = 0

    /// The index in ``newPieces`` of the next new piece.
    private var newIndex = 0

    /// The run that the walk fills now.
    private var current = ChangedRun()

    /// The runs that the walk closed.
    private var closed: [ChangedRun] = []

    /// Makes a walk over the two sides.
    ///
    /// - Parameters:
    ///   - oldPieces: The pieces of the old side.
    ///   - newPieces: The pieces of the new side.
    init(oldPieces: [LinePiece], newPieces: [LinePiece]) {
        self.oldPieces = oldPieces
        self.newPieces = newPieces
    }

    /// Takes one step of the alignment. An unchanged piece closes the
    /// current run. A removed or added line joins it, and a removed or added
    /// marker closes it, because an entity stands there.
    ///
    /// - Parameter step: The step.
    mutating func take(_ step: LineDiff.Change<AlignmentKey>) {
        switch step {
        case .unchanged:
            closeCurrentRun()
            oldIndex += 1
            newIndex += 1
        case .removed:
            add(oldPieces[oldIndex].line, to: \.removed)
            oldIndex += 1
        case .added:
            add(newPieces[newIndex].line, to: \.added)
            newIndex += 1
        }
    }

    /// The closed runs and the last run, in line order.
    ///
    /// - Returns: Each run that holds at least one line.
    mutating func finishedRuns() -> [ChangedRun] {
        closeCurrentRun()
        return closed
    }

    /// Adds a line to one side of the current run, or closes the run for a
    /// marker.
    ///
    /// - Parameters:
    ///   - line: The line, or `nil` for a marker.
    ///   - side: The side of the run that takes the line.
    private mutating func add(_ line: NumberedLine?, to side: WritableKeyPath<ChangedRun, [NumberedLine]>) {
        guard let line else {
            closeCurrentRun()
            return
        }
        current[keyPath: side].append(line)
    }

    /// Closes the current run when it holds a line, and starts a new one.
    private mutating func closeCurrentRun() {
        guard !current.isEmpty else { return }
        closed.append(current)
        current = ChangedRun()
    }
}
