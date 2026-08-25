// `EditEngine` — pure, IO-free argument normalization and resolution cascade
// for the files capability's edit verb.
//
// A behavioral port of `../FoundationModelsFileTool/Sources/FileTool/
// EditEngine.swift`. The sibling declares the type `public` for its own
// module surface; this package keeps it internal, the same way `EditMatch`,
// `Hashline`, and `AtomicWriter` beside it do.
//
// The engine composes the already-ported layers instead of reimplementing
// them: `Hashline` resolves the anchor rung, `EditMatch` supplies the
// recovery ladder, the literal byte search, and the ladder's trims, and
// `LineDiff` aligns the near-miss diff. The engine itself performs no file
// IO: the edit verb card (^v5xap97) drives it from `tools.files.edit` and
// routes the committed content through `AtomicWriter`. Until that card
// lands, the ported suite (`EditEngineTests`) and `EditOutcomeProjection`
// are the callers.

import Foundation

/// Pure, IO-free core of the `edit file` operation: argument normalization and the resolution cascade.
///
/// The engine holds the two purely in-memory halves of `edit file`, with no file
/// system access of its own:
///
/// 1. ``normalize(_:)`` turns the operation's argument shapes — a scalar
///    `find`/`replace`, parallel `find`/`replace` arrays (`N` finds zipped with
///    `N` replaces, or `N` finds broadcast against a single replace), or an
///    explicit `edits` array — into a flat list of ``Pair`` values, or a
///    corrective message for a count mismatch or a `find == replace` no-op.
/// 2. ``resolve(_:in:)`` locates a single ``Pair`` in a working copy by
///    climbing a fixed cascade — a hashline **anchor** (via ``Hashline``), then a
///    literal **substring**, then the **recovery ladder** (via ``EditMatch``) —
///    returning a ``Resolution`` that either points at a definite edit site or
///    surfaces candidates / near-misses instead of guessing.
/// 3. ``apply(_:to:)`` drives a batch of pairs sequentially against an evolving
///    working copy, reclassifies a bare no-match into ``Resolution/alreadyApplied``
///    or ``Resolution/consumedTarget`` using batch and idempotency context, and
///    short-circuits before mutating on any unresolved pair — leaving the
///    original content unchanged and reporting which pair failed.
///
/// The anchor rung and the recovery ladder are **not** reimplemented here: the
/// engine composes ``Hashline/resolveAnchor(_:in:)`` (with its ±``Hashline/proximityWindow``
/// drift and `|text` verification) and ``EditMatch/findMatch(find:in:)`` (with
/// its ladder rungs and near-miss spans). Byte ranges index the working
/// copy's UTF-8 bytes, consistent with ``EditMatch``.
enum EditEngine {
    // MARK: Argument shapes

    /// One explicit `{find, replace, replaceAll}` entry from an `edits` array.
    ///
    /// The `edits` array form lets a caller pass several independent edits, each
    /// with its own `replaceAll` flag, in a single `edit file` call.
    struct EditSpec: Equatable, Sendable {
        /// The text (or hashline anchor) to locate.
        let find: String

        /// The replacement text.
        let replace: String

        /// Whether every occurrence of ``find`` is rewritten rather than a single one.
        let replaceAll: Bool

        /// Creates an `edits`-array entry.
        ///
        /// - Parameters:
        ///   - find: the text or hashline anchor to locate.
        ///   - replace: the replacement text.
        ///   - replaceAll: whether every occurrence is rewritten; defaults to `false`.
        init(find: String, replace: String, replaceAll: Bool = false) {
            self.find = find
            self.replace = replace
            self.replaceAll = replaceAll
        }
    }

    /// The raw, resolver-normalized arguments of one `edit file` call, before shaping into pairs.
    ///
    /// The three mutually exclusive input shapes are carried in one value: the
    /// scalar form is a single-element ``finds`` and ``replaces``; the parallel
    /// form is multi-element ``finds`` and ``replaces``; the explicit form is a
    /// non-empty ``edits``. ``normalize(_:)`` decides which shape applies. The
    /// ``replaceAll`` and ``occurrence`` disambiguators apply to the scalar and
    /// parallel forms (the ``edits`` form carries its own per-entry `replaceAll`).
    struct EditArguments: Equatable, Sendable {
        /// The `find` values: one for the scalar form, several for the parallel form.
        let finds: [String]

        /// The `replace` values: one for the scalar form, several (or a single broadcast) for the parallel form.
        let replaces: [String]

        /// Whether every occurrence of each `find` is rewritten rather than a single one.
        let replaceAll: Bool

        /// The 1-based occurrence selector that disambiguates among literal candidates, or `nil` for none.
        let occurrence: Int?

        /// The explicit `edits` array; non-empty selects the explicit form.
        let edits: [EditSpec]

        /// Creates a set of `edit file` arguments.
        ///
        /// - Parameters:
        ///   - finds: the `find` values; defaults to empty.
        ///   - replaces: the `replace` values; defaults to empty.
        ///   - replaceAll: whether every occurrence is rewritten; defaults to `false`.
        ///   - occurrence: the 1-based occurrence selector, or `nil`; defaults to `nil`.
        ///   - edits: the explicit `edits` array; defaults to empty.
        init(
            finds: [String] = [],
            replaces: [String] = [],
            replaceAll: Bool = false,
            occurrence: Int? = nil,
            edits: [EditSpec] = []
        ) {
            self.finds = finds
            self.replaces = replaces
            self.replaceAll = replaceAll
            self.occurrence = occurrence
            self.edits = edits
        }
    }

    /// One normalized find/replace pair: the atomic unit the cascade resolves and applies.
    struct Pair: Equatable, Sendable {
        /// The text (or hashline anchor) to locate.
        let find: String

        /// The replacement text.
        let replace: String

        /// Whether every occurrence of ``find`` is rewritten rather than a single one.
        let replaceAll: Bool

        /// The 1-based occurrence selector among literal candidates, or `nil` for none.
        let occurrence: Int?

        /// Creates a find/replace pair.
        ///
        /// - Parameters:
        ///   - find: the text or hashline anchor to locate.
        ///   - replace: the replacement text.
        ///   - replaceAll: whether every occurrence is rewritten; defaults to `false`.
        ///   - occurrence: the 1-based occurrence selector, or `nil`; defaults to `nil`.
        init(find: String, replace: String, replaceAll: Bool = false, occurrence: Int? = nil) {
            self.find = find
            self.replace = replace
            self.replaceAll = replaceAll
            self.occurrence = occurrence
        }
    }

    /// The outcome of ``normalize(_:)``: the shaped pairs, or a corrective message.
    ///
    /// A count mismatch (unequal `find`/`replace` counts with no single-replace
    /// broadcast), an empty `find` set, or a `find == replace` no-op is surfaced
    /// as a ``corrective(_:)`` message the model reads and acts on within the
    /// turn, following the upstream *return-don't-throw* convention.
    enum Normalization: Equatable, Sendable {
        /// The successfully shaped find/replace pairs, in order.
        case pairs([Pair])

        /// A recoverable failure carrying a corrective message for the model.
        case corrective(String)
    }

    // MARK: Resolution outcomes

    /// One line of surrounding context around a candidate: its 1-based line number and text.
    struct ContextLine: Equatable, Sendable {
        /// The 1-based physical line number in the working copy.
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
    /// A ``Candidate`` is emitted when a pair resolves to more than one plausible
    /// site — several literal occurrences, a competing anchor and literal, or a
    /// tie from the recovery ladder. The ``occurrence`` is the candidate's 1-based
    /// position in the list (the value the caller passes back as `occurrence` to
    /// select it), ``line`` and ``text`` locate it, and ``context`` carries the
    /// surrounding lines (up to ``contextRadius`` on each side, excluding the
    /// focal line) so the model can tell the sites apart.
    struct Candidate: Equatable, Sendable {
        /// The candidate's 1-based position in the candidate list.
        let occurrence: Int

        /// The 1-based physical line number of the candidate in the working copy.
        let line: Int

        /// The current text of the candidate's line, excluding its terminator.
        let text: String

        /// The surrounding context lines, excluding the focal ``line``, nearest first.
        let context: [ContextLine]

        /// Creates a candidate.
        ///
        /// - Parameters:
        ///   - occurrence: the candidate's 1-based position in the candidate list.
        ///   - line: the 1-based physical line number of the candidate.
        ///   - text: the current text of the candidate's line, excluding its terminator.
        ///   - context: the surrounding context lines, excluding the focal line.
        init(occurrence: Int, line: Int, text: String, context: [ContextLine]) {
            self.occurrence = occurrence
            self.line = line
            self.text = text
            self.context = context
        }
    }

    /// One line of a near-miss diff: whether it appears in the `find`, the current text, or both.
    struct DiffLine: Equatable, Sendable {
        /// Which side of the `find`-versus-current comparison a diff line came from.
        enum Change: Equatable, Sendable {
            /// The line is present, identical, in both the `find` and the current text.
            case unchanged

            /// The line is present in the `find` but absent from the current text (what the edit expected).
            case expected

            /// The line is present in the current text but absent from the `find` (what is actually there).
            case actual
        }

        /// Which side of the comparison this line came from.
        let change: Change

        /// The line's text, excluding its terminator.
        let text: String

        /// Creates a diff line.
        ///
        /// - Parameters:
        ///   - change: which side of the comparison this line came from.
        ///   - text: the line's text, excluding its terminator.
        init(change: Change, text: String) {
            self.change = change
            self.text = text
        }
    }

    /// A near-miss: a span the recovery ladder scored highly but could not confidently accept, with a line diff.
    ///
    /// Built from an ``EditMatch/Span`` in ``EditMatch/MatchResult/noMatch(near:)``.
    /// The ``lines`` are a line-level diff of the pair's `find` against the span's
    /// current text, so the model can see exactly how what it asked for differs
    /// from what is present.
    struct NearMiss: Equatable, Sendable {
        /// The 1-based first line of the near-miss span in the working copy.
        let startLine: Int

        /// The 1-based last line of the near-miss span in the working copy.
        let endLine: Int

        /// The line-level diff of the pair's `find` against the span's current text.
        let lines: [DiffLine]

        /// A diagnostic naming the first confusable-punctuation difference in the diff, or `nil` when there is none.
        ///
        /// Populated when an expected line and an actual line differ only by
        /// Unicode confusable punctuation (equal after ``EditMatch/foldConfusables(_:)``
        /// and a whitespace trim): the note points at the first differing scalar
        /// with its code point, so a model reading an opaque smart-quote-versus-ASCII
        /// diff can see the punctuation is the cause. `nil` for a near-miss with no
        /// confusable-equal line pair.
        let note: String?

        /// Creates a near-miss.
        ///
        /// - Parameters:
        ///   - startLine: the 1-based first line of the span.
        ///   - endLine: the 1-based last line of the span.
        ///   - lines: the line-level diff of `find` against the span's current text.
        ///   - note: a confusable-punctuation diagnostic, or `nil`; defaults to `nil`.
        init(startLine: Int, endLine: Int, lines: [DiffLine], note: String? = nil) {
            self.startLine = startLine
            self.endLine = endLine
            self.lines = lines
            self.note = note
        }
    }

    /// Where and how a single ``Pair`` resolves against a working copy.
    ///
    /// ``resolve(_:in:)`` returns one of the first five cases; the last two are
    /// **reclassifications** of a bare ``noMatch(_:)`` that only ``apply(_:to:)``
    /// produces, using batch and idempotency context. The three *definite* cases
    /// — ``anchor(line:)``, ``literal(range:)``, ``recovered(range:)`` — point at
    /// an edit site; the rest leave the working copy untouched.
    enum Resolution: Equatable, Sendable {
        /// A hashline anchor resolved to this 1-based line.
        case anchor(line: Int)

        /// A literal substring match at this UTF-8 byte range of the working copy.
        ///
        /// For a `replaceAll` pair this is the first occurrence; ``apply(_:to:)``
        /// rewrites every occurrence.
        case literal(range: Range<Int>)

        /// The recovery ladder matched this UTF-8 byte range of the working copy.
        case recovered(range: Range<Int>)

        /// Several plausible sites tied; the caller must disambiguate rather than the engine guess.
        case ambiguous([Candidate])

        /// Nothing matched; the best-effort near-misses carry a line diff for diagnostics.
        case noMatch([NearMiss])

        /// The edit appears to have been applied already: the `find` is absent and the `replace` is present.
        case alreadyApplied

        /// An earlier pair in the batch consumed this pair's target: the `find` was in the pre-batch original but is gone.
        case consumedTarget
    }

    // MARK: Batch outcomes

    /// One successfully applied pair and the resolution that placed it.
    struct AppliedEdit: Equatable, Sendable {
        /// The pair that was applied.
        let pair: Pair

        /// The definite resolution that located the edit site.
        let resolution: Resolution

        /// Creates an applied-edit record.
        ///
        /// - Parameters:
        ///   - pair: the pair that was applied.
        ///   - resolution: the definite resolution that located the edit site.
        init(pair: Pair, resolution: Resolution) {
            self.pair = pair
            self.resolution = resolution
        }
    }

    /// The outcome of ``apply(_:to:)``: the committed content, or the first pair that failed to resolve.
    ///
    /// The batch is all-or-nothing: ``applied(content:edits:)`` carries the fully
    /// rewritten content only when *every* pair resolved definitely; otherwise
    /// ``failed(index:pair:resolution:)`` names the offending pair and its
    /// non-definite resolution, and no content is produced — the caller leaves
    /// the original byte-identical.
    enum BatchOutcome: Equatable, Sendable {
        /// Every pair resolved and applied; the rewritten content and per-pair records.
        case applied(content: String, edits: [AppliedEdit])

        /// A pair failed to resolve definitely, short-circuiting the batch before mutation.
        case failed(index: Int, pair: Pair, resolution: Resolution)
    }

    // MARK: Normalization

    /// Shape `edit file` arguments into an ordered list of find/replace pairs.
    ///
    /// The explicit ``EditArguments/edits`` array, when non-empty, wins and maps
    /// one pair per entry. Otherwise the ``EditArguments/finds`` and
    /// ``EditArguments/replaces`` arrays are paired: equal counts zip pairwise; a
    /// single replace broadcasts across every find; any other count is a
    /// corrective listing the unpaired remainder. An empty find set and any
    /// `find == replace` no-op are likewise corrective.
    ///
    /// - Parameter arguments: the resolver-normalized `edit file` arguments.
    /// - Returns: ``Normalization/pairs(_:)`` with the shaped pairs, or
    ///   ``Normalization/corrective(_:)`` with a message the model can act on.
    static func normalize(_ arguments: EditArguments) -> Normalization {
        let pairs: [Pair]
        if !arguments.edits.isEmpty {
            pairs = arguments.edits.map {
                Pair(find: $0.find, replace: $0.replace, replaceAll: $0.replaceAll, occurrence: nil)
            }
        } else {
            switch pairsFromArrays(arguments) {
            case .pairs(let shaped): pairs = shaped
            case .corrective(let message): return .corrective(message)
            }
        }
        if let noOp = pairs.first(where: { $0.find == $0.replace }) {
            return .corrective(noOpMessage(find: noOp.find))
        }
        return .pairs(pairs)
    }

    /// Pair the scalar/parallel `finds` and `replaces` arrays, or return a count-mismatch corrective.
    ///
    /// - Parameter arguments: the resolver-normalized `edit file` arguments.
    /// - Returns: ``Normalization/pairs(_:)`` when the arrays pair up, or
    ///   ``Normalization/corrective(_:)`` for an empty find set or a count mismatch.
    private static func pairsFromArrays(_ arguments: EditArguments) -> Normalization {
        let finds = arguments.finds
        let replaces = arguments.replaces
        guard !finds.isEmpty else { return .corrective(missingFindMessage) }
        if finds.count == replaces.count {
            let pairs = zip(finds, replaces).map { find, replace in
                Pair(find: find, replace: replace, replaceAll: arguments.replaceAll, occurrence: arguments.occurrence)
            }
            return .pairs(pairs)
        }
        if replaces.count == 1 {
            let pairs = finds.map {
                Pair(find: $0, replace: replaces[0], replaceAll: arguments.replaceAll, occurrence: arguments.occurrence)
            }
            return .pairs(pairs)
        }
        return .corrective(mismatchMessage(finds: finds, replaces: replaces))
    }

    // MARK: Resolution cascade

    /// Resolve a single pair against a working copy by climbing the anchor → literal → ladder cascade.
    ///
    /// The rungs are tried in order, and a resolving anchor takes precedence over
    /// a literal, which takes precedence over the recovery ladder:
    ///
    /// 1. **Anchor** — when `find` parses as a hashline anchor, it is resolved via
    ///    ``Hashline/resolveAnchor(_:in:)`` (±``Hashline/proximityWindow`` drift,
    ///    optional `|text` verification). If it resolves *and* the anchor's
    ///    `|text` payload also matches literally on a **different** line, the two
    ///    compete and ``Resolution/ambiguous(_:)`` is returned rather than a guess;
    ///    otherwise ``Resolution/anchor(line:)``.
    /// 2. **Literal** — the first literal substring occurrence, or the
    ///    `occurrence`-selected one; a `replaceAll` pair resolves to the first
    ///    occurrence (``apply(_:to:)`` rewrites all); multiple un-disambiguated
    ///    occurrences (or an out-of-range `occurrence`) are
    ///    ``Resolution/ambiguous(_:)``.
    /// 3. **Ladder** — ``EditMatch/findMatch(find:in:)`` yields
    ///    ``Resolution/recovered(range:)``, ``Resolution/ambiguous(_:)``, or
    ///    ``Resolution/noMatch(_:)`` with a line diff.
    ///
    /// This never returns ``Resolution/alreadyApplied`` or
    /// ``Resolution/consumedTarget`` — those are batch reclassifications produced
    /// only by ``apply(_:to:)``.
    ///
    /// - Parameters:
    ///   - pair: the find/replace pair to resolve.
    ///   - working: the current working copy to resolve against.
    /// - Returns: the ``Resolution`` locating the edit site, or surfacing candidates or near-misses.
    static func resolve(_ pair: Pair, in working: String) -> Resolution {
        let literalRanges = literalSearchString(for: pair.find).map { literalByteRanges(of: $0, in: working) } ?? []
        if let anchorLine = anchorLine(for: pair.find, in: working) {
            let competing = literalRanges.filter { lineNumber(ofByteOffset: $0.lowerBound, in: working) != anchorLine }
            if competing.isEmpty {
                return .anchor(line: anchorLine)
            }
            return .ambiguous(competingCandidates(anchorLine: anchorLine, literalRanges: competing, in: working))
        }
        if !literalRanges.isEmpty {
            return literalResolution(pair, ranges: literalRanges, in: working)
        }
        return ladderResolution(pair, in: working)
    }

    /// The 1-based line a `find` resolves to as a hashline anchor, or `nil` when it is not a resolving anchor.
    ///
    /// - Parameters:
    ///   - find: the pair's find text.
    ///   - working: the working copy to resolve against.
    /// - Returns: the resolved 1-based line, or `nil` when `find` is not a
    ///   well-formed anchor or does not resolve.
    private static func anchorLine(for find: String, in working: String) -> Int? {
        guard Hashline.parseAnchor(find) != nil else { return nil }
        return Hashline.resolveAnchor(find, in: working)
    }

    /// Resolve the literal rung from a pair's literal occurrence ranges.
    ///
    /// - Parameters:
    ///   - pair: the pair being resolved.
    ///   - ranges: the ascending literal occurrence ranges (guaranteed non-empty).
    ///   - working: the working copy.
    /// - Returns: ``Resolution/literal(range:)`` for a single or selected
    ///   occurrence, or ``Resolution/ambiguous(_:)`` when the selection is missing
    ///   or out of range.
    private static func literalResolution(_ pair: Pair, ranges: [Range<Int>], in working: String) -> Resolution {
        if pair.replaceAll {
            return .literal(range: ranges[0])
        }
        if let occurrence = pair.occurrence {
            let index = occurrence - firstOccurrence
            if ranges.indices.contains(index) {
                return .literal(range: ranges[index])
            }
            return .ambiguous(literalCandidates(ranges, in: working))
        }
        if ranges.count == 1 {
            return .literal(range: ranges[0])
        }
        return .ambiguous(literalCandidates(ranges, in: working))
    }

    /// Resolve the recovery-ladder rung via ``EditMatch/findMatch(find:in:)``.
    ///
    /// - Parameters:
    ///   - pair: the pair being resolved.
    ///   - working: the working copy.
    /// - Returns: ``Resolution/recovered(range:)`` for a unique ladder match,
    ///   ``Resolution/ambiguous(_:)`` for a ladder tie, or
    ///   ``Resolution/noMatch(_:)`` with per-span line diffs.
    private static func ladderResolution(_ pair: Pair, in working: String) -> Resolution {
        let workingLines = lineTexts(of: working)
        switch EditMatch.findMatch(find: pair.find, in: working) {
        case .unique(let range, _, _):
            return .recovered(range: range)
        case .ambiguous(let spans):
            return .ambiguous(
                spans.enumerated().map { offset, span in
                    candidate(occurrence: offset + firstOccurrence, span: span, in: workingLines)
                }
            )
        case .noMatch(let spans):
            return .noMatch(spans.map { nearMiss(for: pair.find, span: $0) })
        }
    }

    // MARK: Batch application

    /// Apply an ordered batch of pairs to an original, committing only when every pair resolves.
    ///
    /// Each pair is resolved against the working copy as mutated by the pairs
    /// before it, so a later pair sees earlier edits. A bare
    /// ``Resolution/noMatch(_:)`` is reclassified into
    /// ``Resolution/consumedTarget`` or ``Resolution/alreadyApplied`` using the
    /// pre-batch original as context. The first pair whose resolution is not a
    /// definite anchor/literal/recovered short-circuits the batch: no content is
    /// committed and the caller leaves the original byte-identical.
    ///
    /// - Parameters:
    ///   - pairs: the pairs to apply, in order.
    ///   - original: the content the batch starts from.
    /// - Returns: ``BatchOutcome/applied(content:edits:)`` when all pairs
    ///   resolved, or ``BatchOutcome/failed(index:pair:resolution:)`` for the
    ///   first pair that did not.
    static func apply(_ pairs: [Pair], to original: String) -> BatchOutcome {
        var working = original
        var applied: [AppliedEdit] = []
        for (index, pair) in pairs.enumerated() {
            let resolution = batchResolution(for: pair, working: working, original: original)
            switch resolution {
            case .anchor(let line):
                working = replacingLine(line, with: pair.replace, in: working)
            case .literal(let range):
                working =
                    pair.replaceAll
                    ? replacingAllLiteral(for: pair.find, with: pair.replace, in: working)
                    : replacingBytes(range, with: pair.replace, in: working)
            case .recovered(let range):
                working = replacingBytes(range, with: pair.replace, in: working)
            case .ambiguous, .noMatch, .alreadyApplied, .consumedTarget:
                return .failed(index: index, pair: pair, resolution: resolution)
            }
            applied.append(AppliedEdit(pair: pair, resolution: resolution))
        }
        return .applied(content: working, edits: applied)
    }

    /// Resolve a pair within a batch, reclassifying a bare no-match with batch context.
    ///
    /// - Parameters:
    ///   - pair: the pair being resolved.
    ///   - working: the working copy as mutated by earlier pairs.
    ///   - original: the pre-batch content.
    /// - Returns: the resolution, with ``Resolution/noMatch(_:)`` possibly
    ///   reclassified to ``Resolution/consumedTarget`` or ``Resolution/alreadyApplied``.
    private static func batchResolution(for pair: Pair, working: String, original: String) -> Resolution {
        let resolution = resolve(pair, in: working)
        guard case .noMatch = resolution else { return resolution }
        return reclassifiedNoMatch(for: pair, working: working, original: original) ?? resolution
    }

    /// Reclassify a bare no-match into a consumed-target or already-applied outcome, or `nil` to keep it.
    ///
    /// A literal `find` that was present in the pre-batch `original` but is now
    /// absent from `working` was consumed by an earlier pair
    /// (``Resolution/consumedTarget``). A `find` that was never in the original
    /// while the non-empty `replace` is already present looks like a prior-turn
    /// idempotent re-run (``Resolution/alreadyApplied``).
    ///
    /// - Parameters:
    ///   - pair: the pair whose no-match to reclassify.
    ///   - working: the working copy as mutated by earlier pairs.
    ///   - original: the pre-batch content.
    /// - Returns: the reclassified resolution, or `nil` to keep the bare no-match.
    private static func reclassifiedNoMatch(for pair: Pair, working: String, original: String) -> Resolution? {
        guard let literal = literalSearchString(for: pair.find), !literal.isEmpty else { return nil }
        if original.contains(literal) {
            return .consumedTarget
        }
        if !pair.replace.isEmpty, working.contains(pair.replace) {
            return .alreadyApplied
        }
        return nil
    }

    // MARK: Literal search

    /// The string to search literally for a `find`, or `nil` when there is no literal interpretation.
    ///
    /// A `find` that does not parse as a hashline anchor is itself the literal. A
    /// `find` that *is* an anchor contributes its `|text` payload (the human-readable
    /// line text) as the literal — so an anchor whose text also occurs elsewhere can
    /// compete — while a pure `N:HH` anchor with no `|text` has no literal
    /// interpretation and returns `nil`.
    ///
    /// - Parameter find: the pair's find text.
    /// - Returns: the literal search string, or `nil` for a pure anchor.
    private static func literalSearchString(for find: String) -> String? {
        guard Hashline.parseAnchor(find) != nil else { return find }
        return anchorTextSuffix(of: find)
    }

    /// The `|text` payload of an anchor string, or `nil` when it carries none.
    ///
    /// - Parameter find: the anchor string.
    /// - Returns: the text after the first ``anchorTextDelimiter``, or `nil`.
    private static func anchorTextSuffix(of find: String) -> String? {
        guard let delimiter = find.firstIndex(of: anchorTextDelimiter) else { return nil }
        return String(find[find.index(after: delimiter)...])
    }

    /// The ascending, non-overlapping UTF-8 byte ranges where `needle` occurs in `haystack`.
    ///
    /// - Parameters:
    ///   - needle: the literal string to search for.
    ///   - haystack: the string to search within.
    /// - Returns: the occurrence ranges in order; empty when `needle` is empty or longer than `haystack`.
    private static func literalByteRanges(of needle: String, in haystack: String) -> [Range<Int>] {
        let needleBytes = Array(needle.utf8)
        return EditMatch.byteOffsets(of: needleBytes, in: Array(haystack.utf8))
            .map { $0..<($0 + needleBytes.count) }
    }

    // MARK: Mutation

    /// Replace the text of a 1-based line, preserving its terminator.
    ///
    /// - Parameters:
    ///   - line: the 1-based line to replace.
    ///   - replacement: the new line text.
    ///   - working: the working copy.
    /// - Returns: the working copy with the line's text replaced.
    private static func replacingLine(_ line: Int, with replacement: String, in working: String) -> String {
        var lines = Hashline.splitLines(working)
        guard lines.indices.contains(line - 1) else { return working }
        let existing = lines[line - 1]
        lines[line - 1] = Hashline.Line(text: replacement, terminator: existing.terminator)
        return lines.map { $0.text + $0.terminator }.joined()
    }

    /// Replace a single UTF-8 byte range with a replacement string.
    ///
    /// - Parameters:
    ///   - range: the byte range to replace.
    ///   - replacement: the replacement text.
    ///   - working: the working copy.
    /// - Returns: the working copy with the range replaced.
    private static func replacingBytes(_ range: Range<Int>, with replacement: String, in working: String) -> String {
        var bytes = Array(working.utf8)
        bytes.replaceSubrange(range, with: Array(replacement.utf8))
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Replace every literal occurrence of a `find`'s literal search string.
    ///
    /// Occurrences are rewritten from last to first so earlier byte offsets stay
    /// valid through the mutation.
    ///
    /// - Parameters:
    ///   - find: the pair's find text.
    ///   - replacement: the replacement text.
    ///   - working: the working copy.
    /// - Returns: the working copy with every occurrence replaced.
    private static func replacingAllLiteral(for find: String, with replacement: String, in working: String) -> String {
        guard let literal = literalSearchString(for: find) else { return working }
        var bytes = Array(working.utf8)
        let replacementBytes = Array(replacement.utf8)
        for range in literalByteRanges(of: literal, in: working).reversed() {
            bytes.replaceSubrange(range, with: replacementBytes)
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    // MARK: Candidate construction

    /// Build the candidate list for a competing anchor and one or more literal occurrences.
    ///
    /// The anchor is candidate ``firstOccurrence``; the literal occurrences follow
    /// in order.
    ///
    /// - Parameters:
    ///   - anchorLine: the 1-based line the anchor resolved to.
    ///   - literalRanges: the competing literal occurrence ranges.
    ///   - working: the working copy.
    /// - Returns: the ordered candidates, anchor first.
    private static func competingCandidates(
        anchorLine: Int,
        literalRanges: [Range<Int>],
        in working: String
    ) -> [Candidate] {
        let workingLines = lineTexts(of: working)
        var candidates = [candidate(occurrence: firstOccurrence, line: anchorLine, in: workingLines)]
        for range in literalRanges {
            // The next occurrence number follows the candidates already collected
            // (the anchor, then any earlier literals), so no literal offset is hardcoded.
            let occurrence = candidates.count + firstOccurrence
            candidates.append(candidate(occurrence: occurrence, forByteRange: range, in: workingLines, of: working))
        }
        return candidates
    }

    /// Build the candidate list for several literal occurrences.
    ///
    /// - Parameters:
    ///   - ranges: the literal occurrence ranges, in order.
    ///   - working: the working copy.
    /// - Returns: the ordered candidates, numbered from ``firstOccurrence``.
    private static func literalCandidates(_ ranges: [Range<Int>], in working: String) -> [Candidate] {
        let workingLines = lineTexts(of: working)
        return ranges.enumerated().map { offset, range in
            candidate(occurrence: offset + firstOccurrence, forByteRange: range, in: workingLines, of: working)
        }
    }

    /// Build a candidate for a literal occurrence at a byte range.
    ///
    /// - Parameters:
    ///   - occurrence: the candidate's 1-based position in the list.
    ///   - range: the occurrence's byte range.
    ///   - workingLines: the working copy's per-line texts.
    ///   - working: the working copy.
    /// - Returns: the candidate located at the range's line.
    private static func candidate(
        occurrence: Int,
        forByteRange range: Range<Int>,
        in workingLines: [String],
        of working: String
    ) -> Candidate {
        candidate(
            occurrence: occurrence, line: lineNumber(ofByteOffset: range.lowerBound, in: working), in: workingLines)
    }

    /// Build a candidate at a 1-based line, carrying an explicit focal text.
    ///
    /// This is the single point where a ``Candidate`` is constructed: every other
    /// candidate builder narrows down to this core by supplying the focal `line`
    /// and its `text`, and the ±``contextRadius`` context is always taken around
    /// that same line.
    ///
    /// - Parameters:
    ///   - occurrence: the candidate's 1-based position in the list.
    ///   - line: the 1-based focal line.
    ///   - text: the focal line's text.
    ///   - workingLines: the working copy's per-line texts.
    /// - Returns: the candidate with the given focal text and surrounding context.
    private static func candidate(
        occurrence: Int,
        line: Int,
        text: String,
        in workingLines: [String]
    ) -> Candidate {
        Candidate(
            occurrence: occurrence,
            line: line,
            text: text,
            context: contextLines(around: line, in: workingLines)
        )
    }

    /// Build a candidate for an ``EditMatch/Span`` from a ladder tie.
    ///
    /// - Parameters:
    ///   - occurrence: the candidate's 1-based position in the list.
    ///   - span: the ladder candidate span.
    ///   - workingLines: the working copy's per-line texts.
    /// - Returns: the candidate located at the span's start line, carrying the span's text.
    private static func candidate(occurrence: Int, span: EditMatch.Span, in workingLines: [String]) -> Candidate {
        candidate(occurrence: occurrence, line: span.startLine, text: span.text, in: workingLines)
    }

    /// Build a candidate at a 1-based line, taking its focal text from the working lines.
    ///
    /// - Parameters:
    ///   - occurrence: the candidate's 1-based position in the list.
    ///   - line: the 1-based focal line.
    ///   - workingLines: the working copy's per-line texts.
    /// - Returns: the candidate with focal text and surrounding context.
    private static func candidate(occurrence: Int, line: Int, in workingLines: [String]) -> Candidate {
        candidate(occurrence: occurrence, line: line, text: lineText(at: line, in: workingLines), in: workingLines)
    }

    /// The context lines within ``contextRadius`` of a focal line, excluding the focal line itself.
    ///
    /// - Parameters:
    ///   - line: the 1-based focal line.
    ///   - workingLines: the working copy's per-line texts.
    /// - Returns: the surrounding lines, nearest bounds clamped to the content, focal line omitted.
    private static func contextLines(around line: Int, in workingLines: [String]) -> [ContextLine] {
        let lowerBound = max(1, line - contextRadius)
        let upperBound = min(workingLines.count, line + contextRadius)
        guard lowerBound <= upperBound else { return [] }
        return (lowerBound...upperBound)
            .filter { $0 != line }
            .map { ContextLine(line: $0, text: workingLines[$0 - 1]) }
    }

    // MARK: Near-miss diff

    /// Build a near-miss from an ``EditMatch/Span``, diffing the `find` against the span's current text.
    ///
    /// - Parameters:
    ///   - find: the pair's find text.
    ///   - span: the near-miss span the ladder retained.
    /// - Returns: the near-miss with the span's line range and the line diff.
    private static func nearMiss(for find: String, span: EditMatch.Span) -> NearMiss {
        let expected = lineTexts(of: find)
        let actual = lineTexts(of: span.text)
        return NearMiss(
            startLine: span.startLine,
            endLine: span.endLine,
            lines: diff(expected: expected, actual: actual),
            note: confusableNote(expected: expected, actual: actual)
        )
    }

    /// The confusable-punctuation note for a near-miss, or `nil` when no line pair differs only by confusables.
    ///
    /// Scans the `expected` (the `find`'s) lines against the `actual` (the span's)
    /// lines for the first pair that is unequal verbatim yet equal after
    /// ``EditMatch/foldConfusables(_:)`` plus the ladder's whitespace trim, then
    /// names the first Unicode scalar at which that pair diverges. This is the
    /// diagnostic facet of the confusable rung: when the ladder still fails
    /// because *other* lines differ, it explains that a surviving line pair
    /// differs only by typographic punctuation.
    ///
    /// - Parameters:
    ///   - expected: the `find`'s lines (what the edit expected to be present).
    ///   - actual: the current text's lines (what is actually present).
    /// - Returns: the diagnostic note, or `nil` when no confusable-equal pair is found.
    private static func confusableNote(expected: [String], actual: [String]) -> String? {
        for expectedLine in expected {
            for actualLine in actual where isConfusableDifference(find: expectedLine, file: actualLine) {
                if let difference = firstConfusableScalar(
                    find: EditMatch.normalize(expectedLine),
                    file: EditMatch.normalize(actualLine)
                ) {
                    return confusableNoteMessage(fileScalar: difference.file, findScalar: difference.find)
                }
            }
        }
        return nil
    }

    /// Whether a line pair differs *only* by confusable punctuation.
    ///
    /// True exactly when the two lines are unequal after the ladder's plain
    /// whitespace trim yet equal once confusables are also folded — so folding is
    /// what closed the gap. A pair already equal under the whitespace trim alone
    /// (a pure indentation difference, say) is *not* a confusable difference and
    /// yields no note, and neither does a pair that stays unequal after folding.
    ///
    /// - Parameters:
    ///   - find: the `find`'s line.
    ///   - file: the current text's line.
    /// - Returns: `true` when only confusable folding closes the gap between the lines.
    private static func isConfusableDifference(find: String, file: String) -> Bool {
        EditMatch.normalize(find) != EditMatch.normalize(file)
            && EditMatch.unicodeNormalize(find) == EditMatch.unicodeNormalize(file)
    }

    /// The first aligned scalar position where two trimmed lines diverge by a genuine confusable pair, or `nil`.
    ///
    /// Scans the two already-trimmed lines scalar by scalar; at the first
    /// divergence it reports the pair only when the two scalars fold to the same
    /// ASCII form — a real confusable relationship. A divergence that is *not* a
    /// confusable pair (an alignment shift from leading confusable whitespace, for
    /// instance) yields `nil` rather than a misattributed note.
    ///
    /// - Parameters:
    ///   - find: the `find`'s trimmed line.
    ///   - file: the current text's trimmed line.
    /// - Returns: the diverging `(find, file)` confusable scalars, or `nil`.
    private static func firstConfusableScalar(
        find: String,
        file: String
    ) -> (find: Unicode.Scalar, file: Unicode.Scalar)? {
        let findScalars = Array(find.unicodeScalars)
        let fileScalars = Array(file.unicodeScalars)
        for index in 0..<min(findScalars.count, fileScalars.count) where findScalars[index] != fileScalars[index] {
            let findScalar = findScalars[index]
            let fileScalar = fileScalars[index]
            guard EditMatch.foldConfusables(String(findScalar)) == EditMatch.foldConfusables(String(fileScalar)) else {
                return nil
            }
            return (findScalar, fileScalar)
        }
        return nil
    }

    /// Compose the confusable-punctuation diagnostic naming the file and find scalars with their code points.
    ///
    /// - Parameters:
    ///   - fileScalar: the scalar present in the file (the current text).
    ///   - findScalar: the scalar present in the `find`.
    /// - Returns: a message of the form
    ///   `differs only by Unicode punctuation: the file has 'X' (U+XXXX) where the find has 'Y' (U+YYYY)`.
    private static func confusableNoteMessage(fileScalar: Unicode.Scalar, findScalar: Unicode.Scalar) -> String {
        "differs only by Unicode punctuation: the file has \(quoted(fileScalar)) (\(codePoint(fileScalar)))"
            + " where the find has \(quoted(findScalar)) (\(codePoint(findScalar)))"
    }

    /// A single scalar wrapped in quotes, using double quotes when the scalar is itself an apostrophe.
    ///
    /// - Parameter scalar: the scalar to quote.
    /// - Returns: the scalar in single quotes, or double quotes when it is `'`.
    private static func quoted(_ scalar: Unicode.Scalar) -> String {
        scalar == "'" ? "\"\(scalar)\"" : "'\(scalar)'"
    }

    /// The `U+XXXX` code-point label of a scalar, zero-padded to at least four hex digits.
    ///
    /// - Parameter scalar: the scalar to label.
    /// - Returns: the uppercase `U+XXXX` code point.
    private static func codePoint(_ scalar: Unicode.Scalar) -> String {
        String(format: "U+%04X", scalar.value)
    }

    /// A longest-common-subsequence line diff of `expected` against `actual`.
    ///
    /// Lines common to both are ``DiffLine/Change/unchanged``; lines only in
    /// `expected` are ``DiffLine/Change/expected``; lines only in `actual` are
    /// ``DiffLine/Change/actual``.
    ///
    /// The alignment itself is ``LineDiff/changes(from:to:trimmingCommonSuffix:)``,
    /// shared with the git-patch renderer so the package has exactly one line
    /// diff; this only names each aligned line in the near-miss vocabulary. The
    /// suffix trim stays off here, so the near-miss alignment matches the
    /// sibling's exactly.
    ///
    /// - Parameters:
    ///   - expected: the `find`'s lines (what the edit expected to be present).
    ///   - actual: the current text's lines (what is actually present).
    /// - Returns: the ordered diff lines.
    private static func diff(expected: [String], actual: [String]) -> [DiffLine] {
        LineDiff.changes(from: expected, to: actual).map { change in
            switch change {
            case .unchanged(let text): return DiffLine(change: .unchanged, text: text)
            case .removed(let text): return DiffLine(change: .expected, text: text)
            case .added(let text): return DiffLine(change: .actual, text: text)
            }
        }
    }

    // MARK: Line model

    /// The per-line texts of a string, terminators excluded, via ``Hashline/splitLines(_:)``.
    ///
    /// - Parameter content: the content to split.
    /// - Returns: the physical line texts, in order.
    private static func lineTexts(of content: String) -> [String] {
        Hashline.splitLines(content).map(\.text)
    }

    /// The text of a 1-based line, or the empty string when out of range.
    ///
    /// - Parameters:
    ///   - line: the 1-based line number.
    ///   - workingLines: the per-line texts.
    /// - Returns: the line's text, or `""` when the line is out of range.
    private static func lineText(at line: Int, in workingLines: [String]) -> String {
        workingLines.indices.contains(line - 1) ? workingLines[line - 1] : ""
    }

    /// The 1-based line number of a UTF-8 byte offset in `content`.
    ///
    /// - Parameters:
    ///   - offset: the byte offset.
    ///   - content: the content the offset indexes.
    /// - Returns: the count of newlines before the offset, plus one.
    private static func lineNumber(ofByteOffset offset: Int, in content: String) -> Int {
        let bytes = Array(content.utf8)
        return EditMatch.lineNumber(in: bytes, at: min(offset, bytes.count))
    }

    // MARK: Corrective messages

    /// The corrective message for an empty `find` set.
    private static let missingFindMessage =
        "The `edit file` operation requires at least one `find` value."

    /// The corrective message for a count mismatch between `find` and `replace` arrays.
    ///
    /// - Parameters:
    ///   - finds: the `find` values.
    ///   - replaces: the `replace` values.
    /// - Returns: a message naming the counts and listing the unpaired remainder.
    private static func mismatchMessage(finds: [String], replaces: [String]) -> String {
        let paired = min(finds.count, replaces.count)
        var remainders: [String] = []
        if finds.count > paired {
            remainders.append("unpaired find values: \(quotedList(Array(finds[paired...])))")
        }
        if replaces.count > paired {
            remainders.append("unpaired replace values: \(quotedList(Array(replaces[paired...])))")
        }
        return "The number of `find` values (\(finds.count)) and `replace` values (\(replaces.count)) do not match."
            + " Provide one `replace` per `find`, or a single `replace` to apply to every `find`."
            + " \(remainders.joined(separator: "; "))."
    }

    /// The corrective message for an identical `find` and `replace`.
    ///
    /// - Parameter find: the identical find/replace text.
    /// - Returns: a message naming the no-op.
    private static func noOpMessage(find: String) -> String {
        "The `find` and `replace` values are identical (\"\(find)\"), so the edit would make no change."
    }

    /// A comma-separated list of double-quoted values.
    ///
    /// - Parameter values: the values to quote.
    /// - Returns: the quoted, comma-separated list.
    private static func quotedList(_ values: [String]) -> String {
        values.map { "\"\($0)\"" }.joined(separator: ", ")
    }

    // MARK: Constants

    /// The number of context lines retained on each side of a candidate's focal line.
    private static let contextRadius = 2

    /// The 1-based number of the first occurrence, used as the base for occurrence numbering and selection.
    private static let firstOccurrence = 1

    /// The delimiter separating a hashline anchor's `N:HH` head from its optional `|text` suffix.
    ///
    /// Mirrors the anchor dialect defined in ``Hashline``; declared here because
    /// the engine splits an anchor's literal `|text` payload for the
    /// competing-literal check.
    private static let anchorTextDelimiter: Character = "|"
}
