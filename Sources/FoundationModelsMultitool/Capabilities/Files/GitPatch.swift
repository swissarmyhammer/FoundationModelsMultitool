// `GitPatch` — renders a `FileChangeSet` as a patch in git's format, the
// way `git diff` writes one.
//
// A behavioral port of `../FoundationModelsFileTool/Sources/FileTool/
// GitPatch.swift`. The type is internal, the same way `PathGuard` and
// `Hashline` beside it are.
//
// eventplan.md § "Consolidation of the siblings": the Agent Client
// Protocol's diff content carries an optional patch "in git format"
// alongside its structured changes, thus a client can show a real,
// reviewable diff. Nothing else in this package speaks that format — the
// codex `*** Begin Patch` dialect of the later patch verb has find/replace
// bodies, not unified diff — thus this renders it.
//
// One section per change, in change order:
//
//   diff --git a/old/path b/new/path
//   <new file mode … | deleted file mode … | rename from … / rename to … | copy from … / copy to …>
//   --- a/old/path        (or /dev/null for a creation)
//   +++ b/new/path        (or /dev/null for a deletion)
//   @@ -oldStart,oldCount +newStart,newCount @@
//   <context, -removed, and +added lines>
//
// Paths render relative to the session root, as a git patch's are relative
// to the repository it applies in, thus the patch applies with
// `git apply -p1` from that root. Lines follow *git's* line model — split
// on `\n`, with any `\r` kept as line content — thus a CRLF file's
// terminators survive the round trip. Hunks carry `contextLineCount` lines
// of context and merge when their context overlaps, and a final line with
// no terminator is followed by git's `\ No newline at end of file` marker.

import Foundation

/// Renders a ``FileChangeSet`` as a patch in git's format.
///
/// See the file header for the format contract and the port provenance.
///
/// - Important: A change whose text could not be captured (an unreadable or
///   binary file) renders as git's `Binary files … differ` placeholder, above
///   it a zeroed ``indexHeader(for:)``. The patch is then *not* appliable,
///   and deliberately so: `git apply` refuses it whole — every section, not
///   just that one — rather than the far worse alternative the index line
///   prevents, which is a silent skip of the placeholder and a false report
///   of success. The placeholder is for a person or a client to read; a
///   caller that needs an appliable patch checks first for changes whose
///   ``FileChange/oldContent`` or ``FileChange/newContent`` is `nil`.
enum GitPatch {
    // MARK: Rendering

    /// Render a change set as a git-format patch.
    ///
    /// - Parameters:
    ///   - changes: the changes to render, in order.
    ///   - root: the session root the rendered paths are relative to.
    /// - Returns: the patch text, empty when no change has anything to report.
    static func render(_ changes: [FileChange], relativeTo root: URL) -> String {
        changes.map { section(for: $0, relativeTo: root) }.joined()
    }

    /// Render one change's patch section, or the empty string when it has nothing to report.
    ///
    /// A modification whose text is identical on both sides reports nothing —
    /// no headers, no hunks — thus a no-op write does not litter the patch
    /// with an empty section.
    ///
    /// - Parameters:
    ///   - change: the change to render.
    ///   - root: the session root the rendered paths are relative to.
    /// - Returns: the section text, newline-terminated, or empty.
    private static func section(for change: FileChange, relativeTo root: URL) -> String {
        let oldPath = relativePath(of: change.path, in: root)
        let newPath = change.destinationPath.map { relativePath(of: $0, in: root) } ?? oldPath
        var headers = self.headers(for: change.kind, oldPath: oldPath, newPath: newPath)
        let body: [String]
        if let text = capturedText(of: change) {
            body = self.body(text, of: change, oldPath: oldPath, newPath: newPath)
        } else {
            headers.append(indexHeader(for: change.kind))
            body = [binaryPlaceholder(for: change.kind, oldPath: oldPath, newPath: newPath)]
        }
        guard !headers.isEmpty || !body.isEmpty else { return "" }
        let lines = ["diff --git a/\(oldPath) b/\(newPath)"] + headers + body
        return lines.map { $0 + "\n" }.joined()
    }

    // MARK: Headers

    /// The file mode reported for a created or deleted file.
    ///
    /// The operations do not track the executable bit through a change set,
    /// and a freshly created file gets the default mode, thus every created
    /// or deleted file reports the regular-file mode.
    private static let regularFileMode = "100644"

    /// The mode header a creation or a deletion carries, keyed by kind.
    private static let modeHeaders: [FileChangeKind: String] = [
        .add: "new file mode \(regularFileMode)",
        .delete: "deleted file mode \(regularFileMode)",
    ]

    /// The `from`/`to` header verb a relocating change carries, keyed by kind.
    ///
    /// Git spells the two relocations identically apart from this verb, thus
    /// the difference between them is data rather than a second code path.
    private static let relocationVerbs: [FileChangeKind: String] = [
        .move: "rename",
        .copy: "copy",
    ]

    /// The extra header lines between the `diff --git` line and the body.
    ///
    /// - Parameters:
    ///   - kind: the change kind.
    ///   - oldPath: the root-relative source path.
    ///   - newPath: the root-relative destination path.
    /// - Returns: the header lines, empty for a plain modification.
    private static func headers(for kind: FileChangeKind, oldPath: String, newPath: String)
        -> [String]
    {
        var headers: [String] = []
        if let mode = modeHeaders[kind] { headers.append(mode) }
        if let verb = relocationVerbs[kind] {
            headers.append("\(verb) from \(oldPath)")
            headers.append("\(verb) to \(newPath)")
        }
        return headers
    }

    /// The blob hashes an `index` header names when neither side's content is known.
    ///
    /// A change set records text, not git objects, thus there is no real hash
    /// to name. All-zero abbreviated hashes are git's own "no such object",
    /// and an abbreviated pair is by definition not the *full* index
    /// `git apply` demands before it will touch a binary file — which is
    /// exactly the refusal wanted here.
    private static let unknownBlobHashes = "0000000..0000000"

    /// The `index` header that precedes a binary placeholder.
    ///
    /// Emitted **only** on a placeholder section, and it is load-bearing
    /// rather than cosmetic: without it `git apply` does not recognize the
    /// section as a binary patch at all and silently skips it — it applies
    /// every other section and reports success while that file's change
    /// vanishes. With it, git refuses the whole patch — the honest outcome
    /// for a patch that cannot reproduce one of its changes.
    ///
    /// Git appends the file mode here only when no `new file mode` or
    /// `deleted file mode` header already carries it, thus the mode header's
    /// presence decides the form.
    ///
    /// - Parameter kind: the change kind.
    /// - Returns: the `index` header line.
    private static func indexHeader(for kind: FileChangeKind) -> String {
        guard modeHeaders[kind] == nil else { return "index \(unknownBlobHashes)" }
        return "index \(unknownBlobHashes) \(regularFileMode)"
    }

    // MARK: Body

    /// The side of a diff that does not exist: a creation's old side, a deletion's new side.
    private static let absentSide = "/dev/null"

    /// The placeholder git writes for a file whose content it will not diff.
    ///
    /// Names `/dev/null` on the side that does not exist, exactly as git
    /// does, thus a binary creation and a binary deletion read as such rather
    /// than as a modification of a file against itself.
    ///
    /// - Parameters:
    ///   - kind: the change kind, which decides whether a side is absent.
    ///   - oldPath: the root-relative source path.
    ///   - newPath: the root-relative destination path.
    /// - Returns: the placeholder line.
    private static func binaryPlaceholder(for kind: FileChangeKind, oldPath: String, newPath: String)
        -> String
    {
        let oldSide = kind == .add ? absentSide : "a/\(oldPath)"
        let newSide = kind == .delete ? absentSide : "b/\(newPath)"
        return "Binary files \(oldSide) and \(newSide) differ"
    }

    /// The text on both sides of a change, or `nil` when a side could not be captured.
    ///
    /// The text is taken from the kind, not merely from the optionals: a
    /// creation has no old text and a deletion no new text by definition, and
    /// each is diffed as empty. Any *other* missing side is text the
    /// operation could not capture (an unreadable or binary file) — the case
    /// that renders as binary rather than as a diff against nothing.
    ///
    /// - Parameter change: the change to take the text of.
    /// - Returns: both sides' text, or `nil` when either is uncapturable.
    private static func capturedText(of change: FileChange) -> (old: String, new: String)? {
        let oldContent = change.kind == .add ? "" : change.oldContent
        let newContent = change.kind == .delete ? "" : change.newContent
        guard let oldContent, let newContent else { return nil }
        return (oldContent, newContent)
    }

    /// The `---` / `+++` pair and hunks for a change whose text was captured.
    ///
    /// - Parameters:
    ///   - text: both sides' text, from ``capturedText(of:)``.
    ///   - change: the change to render the body of.
    ///   - oldPath: the root-relative source path.
    ///   - newPath: the root-relative destination path.
    /// - Returns: the body lines, empty when the two sides are identical.
    private static func body(
        _ text: (old: String, new: String),
        of change: FileChange,
        oldPath: String,
        newPath: String
    ) -> [String] {
        let hunks = self.hunks(from: lines(of: text.old), to: lines(of: text.new))
        guard !hunks.isEmpty else { return [] }
        let oldSide = change.kind == .add ? absentSide : "a/\(oldPath)"
        let newSide = change.kind == .delete ? absentSide : "b/\(newPath)"
        return ["--- \(oldSide)", "+++ \(newSide)"] + hunks
    }

    // MARK: Line model

    /// One line of a file in git's line model: its text, and whether a newline followed it.
    ///
    /// Termination is part of the identity: a final line that gains or loses
    /// its newline is a *changed* line, exactly as git treats it, thus a
    /// patch that reports the change reproduces the new bytes.
    private struct Line: Equatable {
        /// The line's text, with the newline that ended it excluded.
        let text: String

        /// Whether a newline followed the line; `false` only for an unterminated final line.
        let isTerminated: Bool
    }

    /// The lines of a content string, in git's line model.
    ///
    /// Deliberately **not** ``Hashline/splitLines(_:)``: the hashline line
    /// model treats `\r\n` and a bare `\r` as terminators and strips them,
    /// which is right for anchors but wrong for a patch. Git splits on `\n`
    /// alone and keeps any `\r` as ordinary line content, thus a CRLF file's
    /// terminators survive into the hunk and the applied patch reproduces the
    /// original bytes rather than a silent rewrite of the file to LF.
    ///
    /// - Parameter content: the content to split.
    /// - Returns: the lines, in order.
    private static func lines(of content: String) -> [Line] {
        var lines: [Line] = []
        var text = String.UnicodeScalarView()
        for scalar in content.unicodeScalars {
            guard scalar == "\n" else {
                text.append(scalar)
                continue
            }
            lines.append(Line(text: String(text), isTerminated: true))
            text = String.UnicodeScalarView()
        }
        if !text.isEmpty { lines.append(Line(text: String(text), isTerminated: false)) }
        return lines
    }

    // MARK: Hunks

    /// The number of unchanged lines rendered on each side of a change.
    private static let contextLineCount = 3

    /// The marker git writes after a line that ends without a terminator.
    private static let noNewlineMarker = "\\ No newline at end of file"

    /// The prefix of an unchanged (context) body line.
    private static let contextPrefix = " "

    /// The prefix of a removed body line.
    private static let removedPrefix = "-"

    /// The prefix of an added body line.
    private static let addedPrefix = "+"

    /// The hunks that align `old` to `new`, with context, or none when they are identical.
    ///
    /// Every changed line pulls ``contextLineCount`` neighbours on each side
    /// into the patch; runs of pulled-in lines that touch become one hunk,
    /// thus nearby changes merge and distant ones do not.
    ///
    /// - Parameters:
    ///   - old: the old side's lines.
    ///   - new: the new side's lines.
    /// - Returns: the rendered hunk lines, empty when nothing changed.
    private static func hunks(from old: [Line], to new: [Line]) -> [String] {
        // Suffix trimming anchors the shared tail, thus a late edit in a long
        // file does not re-align everything after it.
        let changes = LineDiff.changes(from: old, to: new, trimmingCommonSuffix: true)
        var included = [Bool](repeating: false, count: changes.count)
        var changed = false
        for (index, change) in changes.enumerated() where !isUnchanged(change) {
            changed = true
            let lower = max(0, index - contextLineCount)
            let upper = min(changes.count - 1, index + contextLineCount)
            for neighbour in lower...upper { included[neighbour] = true }
        }
        guard changed else { return [] }
        return ranges(of: included).flatMap { hunk(changes, range: $0) }
    }

    /// The maximal ranges of consecutive `true` flags.
    ///
    /// - Parameter included: the per-line inclusion flags.
    /// - Returns: one range per hunk, in order.
    private static func ranges(of included: [Bool]) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var start: Int?
        for index in included.indices {
            switch (included[index], start) {
            case (true, nil): start = index
            case (false, .some(let begun)):
                ranges.append(begun..<index)
                start = nil
            default: break
            }
        }
        if let start { ranges.append(start..<included.count) }
        return ranges
    }

    /// Render one hunk: its `@@` header and body lines.
    ///
    /// - Parameters:
    ///   - changes: every aligned change in the file.
    ///   - range: the slice of `changes` this hunk covers.
    /// - Returns: the hunk's lines.
    private static func hunk(_ changes: [LineDiff.Change<Line>], range: Range<Int>) -> [String] {
        let header =
            "@@ -\(span(changes, range: range, on: hasOldSide))"
            + " +\(span(changes, range: range, on: hasNewSide)) @@"
        return [header] + changes[range].flatMap(bodyLines)
    }

    /// The `start,count` span one side of a hunk covers.
    ///
    /// Counted from the changes that precede the hunk, thus the numbering
    /// needs no per-line bookkeeping. Git omits the count for a one-line span
    /// and, for an empty one, names the line *before* the hunk (hence `-0,0`
    /// for a creation), thus both forms are produced here.
    ///
    /// - Parameters:
    ///   - changes: every aligned change in the file.
    ///   - range: the slice of `changes` this hunk covers.
    ///   - present: whether a change occupies a line on the side being counted.
    /// - Returns: the rendered `start` or `start,count`.
    private static func span(
        _ changes: [LineDiff.Change<Line>],
        range: Range<Int>,
        on present: (LineDiff.Change<Line>) -> Bool
    ) -> String {
        let before = changes[..<range.lowerBound].count(where: present)
        let count = changes[range].count(where: present)
        let start = count == 0 ? before : before + 1
        return count == 1 ? "\(start)" : "\(start),\(count)"
    }

    /// The body line (or line plus no-newline marker) one aligned change renders as.
    ///
    /// - Parameter change: the aligned change to render.
    /// - Returns: the rendered lines.
    private static func bodyLines(for change: LineDiff.Change<Line>) -> [String] {
        let (prefix, line) = prefixedLine(of: change)
        guard !line.isTerminated else { return [prefix + line.text] }
        return [prefix + line.text, noNewlineMarker]
    }

    /// The body prefix and line of an aligned change.
    ///
    /// - Parameter change: the aligned change.
    /// - Returns: the prefix and the line it applies to.
    private static func prefixedLine(of change: LineDiff.Change<Line>) -> (String, Line) {
        switch change {
        case .unchanged(let line): return (contextPrefix, line)
        case .removed(let line): return (removedPrefix, line)
        case .added(let line): return (addedPrefix, line)
        }
    }

    /// Whether an aligned change is common to both sides.
    ///
    /// - Parameter change: the aligned change.
    /// - Returns: `true` for an unchanged line.
    private static func isUnchanged(_ change: LineDiff.Change<Line>) -> Bool {
        if case .unchanged = change { return true }
        return false
    }

    /// Whether an aligned change occupies a line on the old side.
    ///
    /// - Parameter change: the aligned change.
    /// - Returns: `true` for an unchanged or removed line.
    private static func hasOldSide(_ change: LineDiff.Change<Line>) -> Bool {
        if case .added = change { return false }
        return true
    }

    /// Whether an aligned change occupies a line on the new side.
    ///
    /// - Parameter change: the aligned change.
    /// - Returns: `true` for an unchanged or added line.
    private static func hasNewSide(_ change: LineDiff.Change<Line>) -> Bool {
        if case .removed = change { return false }
        return true
    }

    // MARK: Paths

    /// A path rendered relative to the session root, as a git patch's paths are.
    ///
    /// A path outside the root — which ``PathGuard`` does not let an
    /// operation produce, but which a host-assembled change could carry —
    /// falls back to its absolute path with the leading separator dropped,
    /// thus the `a/` and `b/` prefixes still yield a well-formed, unambiguous
    /// patch path.
    ///
    /// The comparison is a plain prefix match against the root as given. A
    /// standardized comparison would be actively wrong on macOS, where
    /// standardization rewrites a canonical `/private/var/…` root back to
    /// `/var/…` and thus stops matching the canonical paths the operations
    /// report; the file-change journal (task ^zcr6qz8) canonicalizes the
    /// session root once instead.
    ///
    /// - Parameters:
    ///   - path: the absolute path to render.
    ///   - root: the session root to render it against.
    /// - Returns: the root-relative path.
    private static func relativePath(of path: String, in root: URL) -> String {
        let rootPath = root.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard path.hasPrefix(prefix) else { return String(path.drop(while: { $0 == "/" })) }
        return String(path.dropFirst(prefix.count))
    }
}
