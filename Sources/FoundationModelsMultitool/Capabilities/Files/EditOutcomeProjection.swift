// `EditOutcomeProjection` — the single `EditEngine.Resolution` →
// wire-vocabulary mapping for the files capability's edit and patch verbs.
//
// A behavioral port of `../FoundationModelsFileTool/Sources/FileTool/
// EditOutcomeProjection.swift`, carried together with the `Encodable` wire
// types the projection produces (`EditOutcome`, `EditCandidate`,
// `EditContextLine`, `EditNearMiss`, `EditDiffLine`), which the sibling
// declares in its `Operations/EditFile.swift`. The sibling's `EditResult`
// envelope is NOT ported: it carries the compiler-diagnostics fold
// (`FileDiagnostics`), and this package's files capability carries no
// diagnostics types (decision 2026-08-11) — the edit verb card (^v5xap97)
// shapes its own result envelope. The sibling declares these types `public`
// for its own module surface; this package keeps them internal, the same
// way `EditEngine` beside them does. Until the verb cards land, the ported
// suite (`EditOutcomeProjectionTests`) is the one caller.

import Foundation

/// One surrounding context line of an edit candidate: its 1-based line number and text.
///
/// The `Encodable` projection of ``EditEngine/ContextLine``, carried inside an
/// ``EditCandidate`` so the model can tell competing edit sites apart.
struct EditContextLine: Encodable, Sendable {
    /// The 1-based physical line number in the file.
    let line: Int

    /// The line's text, excluding its terminator.
    let text: String

    /// Creates a context line.
    ///
    /// - Parameters:
    ///   - line: the 1-based physical line number.
    ///   - text: the line's text, excluding its terminator.
    init(line: Int, text: String) {
        self.line = line
        self.text = text
    }
}

/// One competing edit site the engine will not choose between: where it is, and its surroundings.
///
/// The `Encodable` projection of ``EditEngine/Candidate``. The ``occurrence`` is
/// the value the caller passes back as `occurrence` to select this site on a
/// retry; ``line`` and ``text`` locate it and ``context`` carries the
/// surrounding lines so the model can disambiguate.
struct EditCandidate: Encodable, Sendable {
    /// The candidate's 1-based position in the candidate list, for `occurrence` selection.
    let occurrence: Int

    /// The 1-based physical line number of the candidate.
    let line: Int

    /// The current text of the candidate's line, excluding its terminator.
    let text: String

    /// The surrounding context lines, excluding the focal ``line``, nearest first.
    let context: [EditContextLine]

    /// Creates a candidate.
    ///
    /// - Parameters:
    ///   - occurrence: the candidate's 1-based position in the candidate list.
    ///   - line: the 1-based physical line number of the candidate.
    ///   - text: the current text of the candidate's line, excluding its terminator.
    ///   - context: the surrounding context lines, excluding the focal line.
    init(occurrence: Int, line: Int, text: String, context: [EditContextLine]) {
        self.occurrence = occurrence
        self.line = line
        self.text = text
        self.context = context
    }
}

/// One line of a near-miss diff: which side of the `find`-versus-current comparison it came from, and its text.
///
/// The `Encodable` projection of ``EditEngine/DiffLine``. The ``change`` reads as
/// `unchanged` (present identically in both), `expected` (present in the `find`
/// but absent from the current text), or `actual` (present in the current text
/// but absent from the `find`).
struct EditDiffLine: Encodable, Sendable {
    /// Which side of the comparison this line came from: `unchanged`, `expected`, or `actual`.
    let change: String

    /// The line's text, excluding its terminator.
    let text: String

    /// Creates a diff line.
    ///
    /// - Parameters:
    ///   - change: which side of the comparison this line came from.
    ///   - text: the line's text, excluding its terminator.
    init(change: String, text: String) {
        self.change = change
        self.text = text
    }
}

/// A near-miss: a span the recovery ladder scored highly but could not confidently accept, with a line diff.
///
/// The `Encodable` projection of ``EditEngine/NearMiss``. The ``lines`` are a
/// line-level diff of the pair's `find` against the span's current text, so the
/// model can see exactly how what it asked for differs from what is present.
struct EditNearMiss: Encodable, Sendable {
    /// The 1-based first line of the near-miss span.
    let startLine: Int

    /// The 1-based last line of the near-miss span.
    let endLine: Int

    /// The line-level diff of the pair's `find` against the span's current text.
    let lines: [EditDiffLine]

    /// A diagnostic naming the first confusable-punctuation difference in the diff, or `nil` when there is none.
    ///
    /// Surfaced when a diff line pair differs only by Unicode confusable
    /// punctuation (smart quotes, typographic dashes, exotic spaces), so the
    /// model reading the diff sees the punctuation is the cause. Nil-omitted from
    /// the encoding when absent.
    let note: String?

    /// Creates a near-miss.
    ///
    /// - Parameters:
    ///   - startLine: the 1-based first line of the span.
    ///   - endLine: the 1-based last line of the span.
    ///   - lines: the line-level diff of `find` against the span's current text.
    ///   - note: a confusable-punctuation diagnostic, or `nil`; defaults to `nil`.
    init(startLine: Int, endLine: Int, lines: [EditDiffLine], note: String? = nil) {
        self.startLine = startLine
        self.endLine = endLine
        self.lines = lines
        self.note = note
    }
}

/// The per-pair outcome of an `edit file` batch: how (or whether) one `find` resolved.
///
/// The `Encodable` projection of a single ``EditEngine/Resolution``. Exactly one
/// of the detail fields is populated, selected by ``matchedBy``:
///
/// - `anchor` / `literal` / `recovered` — a definite, applied match; ``line``
///   carries the resolved 1-based line for an `anchor` match.
/// - `ambiguous` — several plausible sites tied; ``candidates`` lists them.
/// - `nearMiss` — nothing matched confidently; ``nearMisses`` carries the line
///   diffs of the best near-misses.
/// - `alreadyApplied` / `consumedTarget` — an idempotency or batch-order
///   reclassification; ``note`` explains it.
struct EditOutcome: Encodable, Sendable {
    /// How this `find` resolved: `anchor`, `literal`, `recovered`, `ambiguous`, `nearMiss`, `alreadyApplied`, or `consumedTarget`.
    let matchedBy: String

    /// The `find` value this outcome resolved (or failed to resolve).
    let find: String

    /// The resolved 1-based line, populated for an `anchor` match; `nil` otherwise.
    let line: Int?

    /// The competing candidates for an `ambiguous` outcome; `nil` otherwise.
    let candidates: [EditCandidate]?

    /// The best near-misses for a `nearMiss` outcome; `nil` otherwise.
    let nearMisses: [EditNearMiss]?

    /// A human-readable note for an `alreadyApplied` or `consumedTarget` outcome; `nil` otherwise.
    let note: String?

    /// Creates a per-pair outcome.
    ///
    /// - Parameters:
    ///   - matchedBy: how this `find` resolved.
    ///   - find: the `find` value this outcome resolved.
    ///   - line: the resolved 1-based line, or `nil`.
    ///   - candidates: the competing candidates, or `nil`.
    ///   - nearMisses: the best near-misses, or `nil`.
    ///   - note: a human-readable note, or `nil`.
    init(
        matchedBy: String,
        find: String,
        line: Int? = nil,
        candidates: [EditCandidate]? = nil,
        nearMisses: [EditNearMiss]? = nil,
        note: String? = nil
    ) {
        self.matchedBy = matchedBy
        self.find = find
        self.line = line
        self.candidates = candidates
        self.nearMisses = nearMisses
        self.note = note
    }
}

/// The shared projection from an ``EditEngine/Resolution`` to its model-facing wire vocabulary, used by both the edit and patch verbs.
///
/// The edit and patch verbs both resolve find/replace pairs through the
/// same ``EditEngine`` cascade, so they must report an identical wire
/// vocabulary: the per-batch status / ``EditOutcome/matchedBy`` names, and
/// the ``EditOutcome`` candidate and near-miss projections. Housing that mapping
/// here — rather than in one operation the other reaches into — keeps the two
/// verbs' reporting from drifting: there is exactly one ``EditEngine/Resolution``
/// → wire-name table and one ``EditEngine/Resolution`` → ``EditOutcome``
/// translation, shared by both.
enum EditOutcomeProjection {
    // MARK: Status names

    /// The model-facing wire names of the resolution outcomes, as data.
    ///
    /// A `String`-raw-valued mirror of ``EditEngine/Resolution``'s cases, so the
    /// wire names live as raw-value data in a single declaration — exactly as
    /// ``AtomicWriter/LineEnding`` and ``AtomicWriter/TextEncoding`` carry theirs
    /// and are read here as `.rawValue` — rather than as string literals repeated
    /// across parallel `switch` arms.
    ///
    /// ``EditEngine/Resolution`` carries associated values (candidates,
    /// near-misses, byte ranges) and so cannot itself key a lookup dictionary;
    /// ``statusName(for:)`` maps each engine case to a member of this table and
    /// reads the wire name from the non-optional ``rawValue``.
    private enum StatusName: String {
        case anchor
        case literal
        case recovered
        case ambiguous
        case nearMiss
        case alreadyApplied
        case consumedTarget
    }

    /// The whole-batch status of a successfully applied batch or patch.
    static let appliedStatus = "applied"

    /// The wire status and ``EditOutcome/matchedBy`` name of a resolution.
    ///
    /// The single mapping from an ``EditEngine/Resolution`` to its wire name,
    /// shared by the applied per-pair outcomes (definite `anchor` / `literal` /
    /// `recovered` matches) and the whole-batch status of an unresolved batch
    /// (`ambiguous` / `nearMiss` / `alreadyApplied` / `consumedTarget`), so the
    /// two never drift. The wire name is read from ``StatusName`` data; this
    /// switch only routes each engine case to its member.
    ///
    /// - Parameter resolution: the resolution to name.
    /// - Returns: the wire name of the resolution.
    static func statusName(for resolution: EditEngine.Resolution) -> String {
        let name: StatusName
        switch resolution {
        case .anchor: name = .anchor
        case .literal: name = .literal
        case .recovered: name = .recovered
        case .ambiguous: name = .ambiguous
        case .noMatch: name = .nearMiss
        case .alreadyApplied: name = .alreadyApplied
        case .consumedTarget: name = .consumedTarget
        }
        return name.rawValue
    }

    // MARK: Outcome mapping

    /// The corrective note for an already-applied outcome.
    private static let alreadyAppliedNote =
        "The edit appears to have been applied already: the `find` is absent and the `replace` is already present."

    /// The corrective note for a consumed-target outcome.
    private static let consumedTargetNote =
        "An earlier edit in this batch consumed this `find`: it was present before the batch but is now gone."

    /// Map one ``EditEngine/Resolution`` to its `Encodable` ``EditOutcome``.
    ///
    /// The single translation from the engine's resolution cases to the wire
    /// outcome: a definite match carries its ``EditOutcome/matchedBy`` (and the
    /// resolved line for an anchor); an ambiguous or near-miss outcome carries
    /// the mapped candidates or near-misses; a reclassified outcome carries an
    /// explanatory note.
    ///
    /// - Parameters:
    ///   - resolution: the resolution to project.
    ///   - find: the pair's `find` value, carried through onto the outcome.
    /// - Returns: the `Encodable` outcome.
    static func outcome(for resolution: EditEngine.Resolution, find: String) -> EditOutcome {
        let matchedBy = statusName(for: resolution)
        switch resolution {
        case .anchor(let line):
            return EditOutcome(matchedBy: matchedBy, find: find, line: line)
        case .literal, .recovered:
            return EditOutcome(matchedBy: matchedBy, find: find)
        case .ambiguous(let candidates):
            return EditOutcome(matchedBy: matchedBy, find: find, candidates: candidates.map(candidateOutput))
        case .noMatch(let nearMisses):
            return EditOutcome(matchedBy: matchedBy, find: find, nearMisses: nearMisses.map(nearMissOutput))
        case .alreadyApplied:
            return EditOutcome(matchedBy: matchedBy, find: find, note: alreadyAppliedNote)
        case .consumedTarget:
            return EditOutcome(matchedBy: matchedBy, find: find, note: consumedTargetNote)
        }
    }

    /// Project an ``EditEngine/Candidate`` to its `Encodable` ``EditCandidate``.
    ///
    /// - Parameter candidate: the engine candidate to project.
    /// - Returns: the `Encodable` candidate.
    private static func candidateOutput(_ candidate: EditEngine.Candidate) -> EditCandidate {
        EditCandidate(
            occurrence: candidate.occurrence,
            line: candidate.line,
            text: candidate.text,
            context: candidate.context.map { EditContextLine(line: $0.line, text: $0.text) }
        )
    }

    /// Project an ``EditEngine/NearMiss`` to its `Encodable` ``EditNearMiss``.
    ///
    /// - Parameter nearMiss: the engine near-miss to project.
    /// - Returns: the `Encodable` near-miss.
    private static func nearMissOutput(_ nearMiss: EditEngine.NearMiss) -> EditNearMiss {
        EditNearMiss(
            startLine: nearMiss.startLine,
            endLine: nearMiss.endLine,
            lines: nearMiss.lines.map { EditDiffLine(change: changeName(for: $0.change), text: $0.text) },
            note: nearMiss.note
        )
    }

    /// The model-facing wire names of a diff line's change, as data.
    ///
    /// A `String`-raw-valued mirror of ``EditEngine/DiffLine/Change``'s cases, so
    /// the wire names are data declared once and read via the non-optional
    /// ``rawValue`` — matching the ``StatusName`` treatment above and the
    /// codebase's ``AtomicWriter/LineEnding`` idiom — rather than string literals
    /// across parallel `switch` arms.
    private enum ChangeName: String {
        case unchanged
        case expected
        case actual
    }

    /// The wire name of a diff line's ``EditEngine/DiffLine/Change``.
    ///
    /// The wire name is read from ``ChangeName`` data; this switch only routes
    /// each engine case to its member.
    ///
    /// - Parameter change: the diff-line change to name.
    /// - Returns: `unchanged`, `expected`, or `actual`.
    private static func changeName(for change: EditEngine.DiffLine.Change) -> String {
        let name: ChangeName
        switch change {
        case .unchanged: name = .unchanged
        case .expected: name = .expected
        case .actual: name = .actual
        }
        return name.rawValue
    }

    // MARK: Wire text

    /// Encodes one wire value to its JSON text with sorted keys.
    ///
    /// The one place a wire value becomes result text, shared by the `edit`
    /// verb (its per-pair ``EditOutcome``s) and the `patch` verb (its
    /// per-file results and its unresolved ``EditOutcome``), so the two
    /// verbs' JSON never drifts. The keys are sorted for deterministic
    /// output, the same convention ``ResultRenderer/serialize(_:)`` uses for
    /// its own `Encodable` input.
    ///
    /// - Parameter value: the wire value to encode.
    /// - Returns: the JSON text, or the literal `"null"` in the
    ///   unreachable-in-practice case that encoding fails — the wire types
    ///   hold only strings and integers, which are always JSON-safe, so this
    ///   fallback is defensive, never a trap.
    static func encodedText(_ value: some Encodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return "null" }
        return String(decoding: data, as: UTF8.self)
    }
}
