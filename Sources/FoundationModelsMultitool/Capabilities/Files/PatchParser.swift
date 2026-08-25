// `PatchParser` — pure, IO-free parser for the `patch files` envelope:
// Add/Delete/Update/Move sections with Find/Replace bodies.
//
// A behavioral port of `../FoundationModelsFileTool/Sources/FileTool/
// PatchParser.swift`. The sibling declares the types `public` for its own
// module surface; this package keeps them internal, the same way `Hashline`
// and `EditEngine` beside it do.
//
// The parser keeps the corrective posture: a patch that cannot parse comes
// back as a `ParseFailure` in a `Result`, never thrown, and the
// `CorrectiveFailure` conformance stands in `CorrectiveResult.swift` beside
// `PathViolation`'s. The patch verb's engine (`PatchEngine`, card ^bhgtf8t)
// consumes the hunks; until that card lands, the ported suite
// (`PatchParserTests`) is the one caller.

import Foundation

/// A rejected `patch files` envelope, carrying the corrective message the model reads and the offending line.
///
/// Follows the upstream *return-don't-throw* pattern shared with ``PathViolation``:
/// a malformed patch is returned as a `Result` failure, never raised, so a
/// language model can read the message, fix the envelope, and retry within the
/// same turn. The type conforms to `Error` only so it can be a `Result` failure
/// — it is never thrown. The ``line`` is a 1-based physical line number into the
/// patch text, so a corrective can point the model at the exact offending line.
struct ParseFailure: Error, Equatable, Sendable, CustomStringConvertible {
    /// The corrective message describing why the patch was rejected.
    let message: String

    /// The 1-based physical line number in the patch text the failure refers to.
    let line: Int

    /// Creates a parse failure carrying a corrective message and a 1-based line number.
    ///
    /// - Parameters:
    ///   - message: the human-readable corrective message.
    ///   - line: the 1-based physical line number the failure refers to.
    init(message: String, line: Int) {
        self.message = message
        self.line = line
    }

    /// The failure's textual representation: its corrective ``message`` with the 1-based ``line``.
    var description: String { "\(message) (line \(line))" }
}

/// Pure, IO-free parser for the `patch files` envelope: Add/Delete/Update/Move sections with Find/Replace bodies.
///
/// The format keeps the codex `apply_patch` file-op headers (`*** Add File:`,
/// `*** Update File:`, `*** Delete File:`, `*** Move to:`) but **replaces the
/// `@@` hunks with hashline-style Find/Replace bodies** — an Update section is a
/// way to send many find/replace pairs (the same pairs `edit file` takes) for
/// one file, and the envelope batches many files into one call. The v1 spec:
///
/// ```text
/// *** Begin Patch
/// *** Add File: <path>
/// +<content line>            ← every Add content line is `+`-prefixed (codex semantics)
/// *** Update File: <path>
/// *** Move to: <new path>    ← optional, immediately after the Update header
/// *** Find:
/// <verbatim lines — hashline-tagged (`12:a7|text`) or bare text>
/// *** Replace:
/// <verbatim replacement lines>
/// *** Delete File: <path>
/// *** End Patch
/// ```
///
/// The parser is deliberately dumb about the bodies: `*** Find:` and
/// `*** Replace:` bodies are passed through untouched (terminators normalized to
/// `\n`), so resolving hashline anchors versus bare text is `EditEngine`'s job
/// downstream. It performs no filesystem access and depends on neither
/// `FileContext` nor `PathGuard`.
///
/// **Divergence from grok's `apply_patch`:** there is no heredoc leniency. grok
/// strips `<<EOF` wrappers as a fossil of codex's shell-invocation era; our
/// models never emit heredocs, so an unrecognized first line is a plain envelope
/// error rather than a stripped wrapper.
enum PatchParser {
    /// One normalized find/replace pair carried by an Update section.
    ///
    /// A bare `(find, replace)` tuple mirroring the atomic unit `edit file`
    /// resolves and applies; downstream (`PatchEngine`) maps each into an
    /// `EditEngine.Pair` to run through the anchor → literal → recovery-ladder
    /// cascade. The strings are verbatim: the parser never trims, re-anchors, or
    /// otherwise rewrites them.
    typealias Pair = (find: String, replace: String)

    /// One file operation parsed from a patch envelope: an Add, a Delete, or an Update (with an optional Move).
    ///
    /// Mirrors the shape of the codex file-op headers, minus the wire/`Encodable`
    /// concerns — the `patch files` operation projects these engine-level values
    /// into its typed output, the way `EditFile` projects `EditEngine` outcomes.
    enum Hunk: Sendable {
        /// Create a new file at `path` with the given `contents`.
        ///
        /// The `contents` are the Add body's `+`-stripped lines joined with `\n`
        /// plus a trailing newline (codex contents semantics); an Add with zero
        /// body lines yields empty `contents`.
        case addFile(path: String, contents: String)

        /// Delete the file at `path`.
        case deleteFile(path: String)

        /// Update the file at `path`: an optional rename to `movePath`, then the ordered Find/Replace `pairs`.
        ///
        /// `movePath` is non-`nil` when the section carried a `*** Move to:` line.
        /// A pure rename is `movePath` set with an empty `pairs`; a pure edit is
        /// `movePath` `nil` with non-empty `pairs`; both together rename *and*
        /// edit.
        case updateFile(path: String, movePath: String?, pairs: [Pair])
    }

    // MARK: Parsing

    /// Parse a `patch files` envelope into an ordered list of ``Hunk`` values.
    ///
    /// Validates the envelope (first non-blank line `*** Begin Patch`, last
    /// non-blank line `*** End Patch`, both whitespace-tolerant), then reads the
    /// file sections between them. Every malformed input — a missing or misplaced
    /// envelope marker, an unknown `*** ` marker, a `*** Replace:` without a
    /// preceding `*** Find:`, a `*** Find:` with an empty body or no following
    /// `*** Replace:`, an Update with neither pairs nor a move, or the same path
    /// in two sections — is returned as a ``ParseFailure`` with a 1-based line
    /// number. Nothing throws.
    ///
    /// - Parameter patch: the raw patch envelope text.
    /// - Returns: `.success` with the parsed hunks (possibly empty for an empty
    ///   envelope), or `.failure` with a corrective ``ParseFailure``.
    static func parse(_ patch: String) -> Result<[Hunk], ParseFailure> {
        let lines = Hashline.splitLines(patch).map(\.text)
        guard let begin = firstNonBlank(lines), classify(lines[begin]) == .marker(.begin) else {
            return .failure(ParseFailure(message: Messages.beginRequired, line: (firstNonBlank(lines) ?? 0) + 1))
        }
        guard let last = lastNonBlank(lines), last != begin, classify(lines[last]) == .marker(.end) else {
            return .failure(ParseFailure(message: Messages.endRequired, line: (lastNonBlank(lines) ?? begin) + 1))
        }
        var parser = Parser(lines: lines, end: last, index: begin + 1)
        return parser.parseSections()
    }

    /// The index of the first line that is non-blank after trimming, or `nil` when every line is blank.
    ///
    /// - Parameter lines: the physical line texts (terminators excluded).
    /// - Returns: the 0-based index of the first non-blank line, or `nil`.
    private static func firstNonBlank(_ lines: [String]) -> Int? {
        lines.firstIndex { !isBlank($0) }
    }

    /// The index of the last line that is non-blank after trimming, or `nil` when every line is blank.
    ///
    /// - Parameter lines: the physical line texts (terminators excluded).
    /// - Returns: the 0-based index of the last non-blank line, or `nil`.
    private static func lastNonBlank(_ lines: [String]) -> Int? {
        lines.lastIndex { !isBlank($0) }
    }

    /// Whether a line is blank once leading and trailing whitespace is trimmed.
    ///
    /// - Parameter line: the line text.
    /// - Returns: `true` when the line has no non-whitespace content.
    private static func isBlank(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: Marker model

    /// A recognized `*** ` marker line, with the path argument for the file-op headers.
    private enum Marker: Equatable {
        /// `*** Begin Patch`.
        case begin
        /// `*** End Patch`.
        case end
        /// `*** Add File: <path>`.
        case add(String)
        /// `*** Update File: <path>`.
        case update(String)
        /// `*** Delete File: <path>`.
        case delete(String)
        /// `*** Move to: <path>`.
        case move(String)
        /// `*** Find:`.
        case find
        /// `*** Replace:`.
        case replace
    }

    /// The classification of one physical line: a recognized marker, an unknown `*** ` marker, or plain content.
    private enum Classified: Equatable {
        /// A recognized ``Marker``.
        case marker(Marker)
        /// A line beginning with the `*** ` marker prefix that matches no known marker.
        case unknownMarker
        /// A body / content line (does not begin with the marker prefix after trimming).
        case content
    }

    /// The prefix every `*** ` marker line begins with after trimming.
    private static let markerPrefix = "*** "

    /// The exact-match markers that carry no argument, paired with their ``Marker`` case.
    ///
    /// Data-driven so the marker dialect for the argument-free headers lives in
    /// one table rather than a parallel `switch`.
    private static let exactMarkers: [(text: String, marker: Marker)] = [
        ("*** Begin Patch", .begin),
        ("*** End Patch", .end),
        ("*** Find:", .find),
        ("*** Replace:", .replace),
    ]

    /// The path-carrying header markers, each a prefix paired with the ``Marker`` constructor for its argument.
    ///
    /// Data-driven so the marker dialect for the file-op headers lives in one
    /// table; the path is the text after the prefix, trimmed.
    private static let pathMarkers: [(prefix: String, make: @Sendable (String) -> Marker)] = [
        ("*** Add File:", Marker.add),
        ("*** Update File:", Marker.update),
        ("*** Delete File:", Marker.delete),
        ("*** Move to:", Marker.move),
    ]

    /// Classify a physical line as a marker, an unknown marker, or content.
    ///
    /// The line is trimmed before comparison, so whitespace around a marker is
    /// tolerated. A line that does not begin with ``markerPrefix`` is
    /// ``Classified/content``; one that does but matches no known marker is
    /// ``Classified/unknownMarker``; otherwise the recognized ``Marker`` (with
    /// its trimmed path argument for the file-op headers).
    ///
    /// - Parameter line: the physical line text (terminator excluded).
    /// - Returns: the line's classification.
    private static func classify(_ line: String) -> Classified {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(markerPrefix) else { return .content }
        for entry in exactMarkers where trimmed == entry.text {
            return .marker(entry.marker)
        }
        for entry in pathMarkers where trimmed.hasPrefix(entry.prefix) {
            let path = String(trimmed.dropFirst(entry.prefix.count)).trimmingCharacters(in: .whitespaces)
            return .marker(entry.make(path))
        }
        return .unknownMarker
    }

    // MARK: Body shaping

    /// The Add contents for a `+`-prefixed body: each line's leading `+` stripped, joined with `\n`, trailing newline.
    ///
    /// An empty body yields empty contents (no trailing newline); a non-empty
    /// body is `\n`-joined with a single trailing newline appended, matching
    /// codex contents semantics.
    ///
    /// - Parameter body: the Add section's verbatim body lines.
    /// - Returns: the file contents to create.
    private static func addContents(_ body: [String]) -> String {
        guard !body.isEmpty else { return "" }
        let stripped = body.map { $0.hasPrefix("+") ? String($0.dropFirst()) : $0 }
        return stripped.joined(separator: "\n") + "\n"
    }

    /// A Find/Replace body joined into one verbatim string, terminators normalized to `\n`.
    ///
    /// The lines are passed through untouched and joined with `\n` (no trailing
    /// newline), so a single hashline-tagged line round-trips byte-identical and
    /// a multi-line body preserves interior content for `EditEngine` to resolve.
    ///
    /// - Parameter body: the section's verbatim body lines.
    /// - Returns: the joined body string.
    private static func joinBody(_ body: [String]) -> String {
        body.joined(separator: "\n")
    }

    // MARK: Corrective messages

    /// The corrective messages for every envelope and section error, defined in one place.
    private enum Messages {
        /// Missing or misplaced `*** Begin Patch`.
        static let beginRequired = "A `patch files` envelope must begin with `*** Begin Patch`."
        /// Missing or misplaced `*** End Patch`.
        static let endRequired = "A `patch files` envelope must end with `*** End Patch`."
        /// A `*** Replace:` with no preceding `*** Find:`.
        static let replaceWithoutFind = "A `*** Replace:` section must be preceded by a `*** Find:` section."
        /// A `*** Find:` with no following `*** Replace:`.
        static let findWithoutReplace = "A `*** Find:` section must be followed by a `*** Replace:` section."
        /// A `*** Find:` whose body is empty.
        static let findEmptyBody = "A `*** Find:` section requires a non-empty body."
        /// An `*** Update File:` with neither a Find/Replace pair nor a `*** Move to:` rename.
        static let updateEmpty =
            "An `*** Update File:` section requires at least one Find/Replace pair or a `*** Move to:` rename."
        /// A `*** Find:` outside any `*** Update File:` section.
        static let findOutsideUpdate = "A `*** Find:` section may only appear inside an `*** Update File:` section."
        /// A `*** Move to:` not immediately after an `*** Update File:` header.
        static let moveMisplaced =
            "A `*** Move to:` line may only appear immediately after an `*** Update File:` header."
        /// A nested `*** Begin Patch`.
        static let nestedBegin = "Unexpected `*** Begin Patch`: the patch has already begun."
        /// A `*** End Patch` that is not the final marker.
        static let contentAfterEnd = "Unexpected `*** End Patch`: it must be the final marker."
        /// A non-blank content line where a file section header was expected.
        static let expectedSection =
            "Expected a file section (`*** Add File:`, `*** Update File:`, or `*** Delete File:`)."
        /// A non-blank content line where a `*** Find:`, `*** Move to:`, or new section was expected.
        static let expectedFindOrSection =
            "Expected `*** Find:`, `*** Move to:`, or a new file section inside an `*** Update File:` section."

        /// The corrective message for an unknown `*** ` marker.
        ///
        /// - Parameter line: the offending line text.
        /// - Returns: a message naming the trimmed marker.
        static func unknownMarker(_ line: String) -> String {
            "Unknown patch marker: `\(line.trimmingCharacters(in: .whitespaces))`."
        }

        /// The corrective message for the same path appearing in two sections.
        ///
        /// - Parameter path: the duplicated path.
        /// - Returns: a message naming the path.
        static func duplicatePath(_ path: String) -> String {
            "The path `\(path)` appears in more than one patch section."
        }
    }

    // MARK: Section parser

    /// The mutable cursor that reads file sections from the lines between the envelope markers.
    ///
    /// Holds the physical `lines`, the exclusive `end` bound (the `*** End Patch`
    /// index), the set of `seenPaths` for duplicate detection, and the current
    /// `index`. Each parse method advances `index` past the construct it consumed
    /// and returns a `Result`, so a failure short-circuits without throwing.
    private struct Parser {
        /// The physical line texts of the whole patch (terminators excluded).
        let lines: [String]

        /// The exclusive upper bound for section content: the index of `*** End Patch`.
        let end: Int

        /// The paths already claimed by an earlier section, for duplicate detection.
        var seenPaths: Set<String> = []

        /// The current 0-based line index.
        var index: Int

        /// Read every file section between the envelope markers into an ordered hunk list.
        ///
        /// Skips blank lines between sections; a non-blank content line, an
        /// unknown marker, or a misplaced marker is a failure. Each recognized
        /// file-op header is delegated to ``parseSection(_:)``.
        ///
        /// - Returns: `.success` with the parsed hunks, or `.failure` with a
        ///   corrective ``ParseFailure``.
        mutating func parseSections() -> Result<[Hunk], ParseFailure> {
            var hunks: [Hunk] = []
            while index < end {
                switch classify(lines[index]) {
                case .content:
                    guard isBlank(lines[index]) else {
                        return .failure(ParseFailure(message: Messages.expectedSection, line: index + 1))
                    }
                    index += 1
                case .unknownMarker:
                    return .failure(ParseFailure(message: Messages.unknownMarker(lines[index]), line: index + 1))
                case .marker(let marker):
                    switch parseSection(marker) {
                    case .success(let hunk): hunks.append(hunk)
                    case .failure(let failure): return .failure(failure)
                    }
                }
            }
            return .success(hunks)
        }

        /// Parse one file section starting at the current marker, advancing past its body.
        ///
        /// Add and Delete are read directly; Update is delegated to
        /// ``parseUpdate(path:headerLine:)``. A marker that cannot begin a file
        /// section here (`*** Find:`, `*** Replace:`, `*** Move to:`,
        /// `*** Begin Patch`, or a premature `*** End Patch`) is a failure. The
        /// section's declared path is recorded for duplicate detection before its
        /// body is read, so a duplicate is reported against the header line.
        ///
        /// - Parameter marker: the section header marker at ``index``.
        /// - Returns: `.success` with the parsed hunk, or `.failure`.
        private mutating func parseSection(_ marker: Marker) -> Result<Hunk, ParseFailure> {
            let headerLine = index + 1
            switch marker {
            case .add(let path):
                index += 1
                let body = consumeBody()
                return recordPath(path, line: headerLine).map { .addFile(path: path, contents: addContents(body)) }
            case .delete(let path):
                index += 1
                return recordPath(path, line: headerLine).map { .deleteFile(path: path) }
            case .update(let path):
                index += 1
                return recordPath(path, line: headerLine).flatMap { parseUpdate(path: path, headerLine: headerLine) }
            case .replace:
                return .failure(ParseFailure(message: Messages.replaceWithoutFind, line: headerLine))
            case .find:
                return .failure(ParseFailure(message: Messages.findOutsideUpdate, line: headerLine))
            case .move:
                return .failure(ParseFailure(message: Messages.moveMisplaced, line: headerLine))
            case .begin:
                return .failure(ParseFailure(message: Messages.nestedBegin, line: headerLine))
            case .end:
                return .failure(ParseFailure(message: Messages.contentAfterEnd, line: headerLine))
            }
        }

        /// Parse the body of an Update section: an optional Move, then the ordered Find/Replace pairs.
        ///
        /// A `*** Move to:` immediately after the header sets the rename
        /// destination. Then Find/Replace pairs are read until the next file-op
        /// header or the envelope end. A `*** Replace:` here (no preceding Find),
        /// a misplaced `*** Move to:`, an unknown marker, or a non-blank content
        /// line is a failure. An Update with neither pairs nor a move is a
        /// failure reported against the header line.
        ///
        /// - Parameters:
        ///   - path: the file's path from the Update header.
        ///   - headerLine: the header's 1-based line, for the empty-update failure.
        /// - Returns: `.success` with the update hunk, or `.failure`.
        private mutating func parseUpdate(path: String, headerLine: Int) -> Result<Hunk, ParseFailure> {
            var movePath: String?
            if index < end, case .marker(.move(let destination)) = classify(lines[index]) {
                movePath = destination
                index += 1
            }
            return parsePairs().flatMap { pairs -> Result<Hunk, ParseFailure> in
                guard !pairs.isEmpty || movePath != nil else {
                    return .failure(ParseFailure(message: Messages.updateEmpty, line: headerLine))
                }
                return .success(.updateFile(path: path, movePath: movePath, pairs: pairs))
            }
        }

        /// Read an Update body's ordered Find/Replace pairs, stopping at the next file-op header or the envelope end.
        ///
        /// Blank content lines between pairs are skipped. A `*** Replace:` here
        /// (no preceding Find), a misplaced `*** Move to:`, a nested
        /// `*** Begin Patch`, an unknown marker, or a non-blank content line is a
        /// failure. The terminating header is left unconsumed for the caller.
        ///
        /// - Returns: `.success` with the pairs in source order, or `.failure`.
        private mutating func parsePairs() -> Result<[Pair], ParseFailure> {
            var pairs: [Pair] = []
            while index < end {
                switch classify(lines[index]) {
                case .content:
                    guard isBlank(lines[index]) else {
                        return .failure(ParseFailure(message: Messages.expectedFindOrSection, line: index + 1))
                    }
                    index += 1
                case .unknownMarker:
                    return .failure(ParseFailure(message: Messages.unknownMarker(lines[index]), line: index + 1))
                case .marker(.find):
                    if let failure = appendPair(to: &pairs) { return .failure(failure) }
                case .marker(.replace):
                    return .failure(ParseFailure(message: Messages.replaceWithoutFind, line: index + 1))
                case .marker(.move):
                    return .failure(ParseFailure(message: Messages.moveMisplaced, line: index + 1))
                case .marker(.begin):
                    return .failure(ParseFailure(message: Messages.nestedBegin, line: index + 1))
                case .marker(.add), .marker(.update), .marker(.delete), .marker(.end):
                    return .success(pairs)
                }
            }
            return .success(pairs)
        }

        /// Parse one Find/Replace pair at the current `*** Find:` marker and append it to `pairs`.
        ///
        /// Adapts ``parsePair()``'s `Result` to the marker loop in
        /// ``parsePairs()``, which needs only to know whether the pair parsed —
        /// keeping the pair-result handling out of that loop's `switch`.
        ///
        /// - Parameter pairs: the accumulator the parsed pair is appended to.
        /// - Returns: the failure that stopped the parse, or `nil` on success.
        private mutating func appendPair(to pairs: inout [Pair]) -> ParseFailure? {
            switch parsePair() {
            case .success(let pair):
                pairs.append(pair)
                return nil
            case .failure(let failure):
                return failure
            }
        }

        /// Parse one Find/Replace pair starting at a `*** Find:` marker, advancing past the Replace body.
        ///
        /// The Find body (verbatim lines to the next marker) must be non-empty;
        /// the next marker must be `*** Replace:`, whose body (possibly empty, for
        /// a deletion) follows. Both bodies are joined via ``joinBody(_:)``.
        ///
        /// - Returns: `.success` with the pair, or `.failure` for an empty Find
        ///   body or a missing following `*** Replace:`.
        private mutating func parsePair() -> Result<Pair, ParseFailure> {
            let findLine = index + 1
            index += 1
            let find = joinBody(consumeBody())
            guard !find.isEmpty else {
                return .failure(ParseFailure(message: Messages.findEmptyBody, line: findLine))
            }
            guard index < end, case .marker(.replace) = classify(lines[index]) else {
                return .failure(ParseFailure(message: Messages.findWithoutReplace, line: findLine))
            }
            index += 1
            let replace = joinBody(consumeBody())
            return .success((find: find, replace: replace))
        }

        /// Consume the run of content lines from ``index`` up to the next marker or the envelope end.
        ///
        /// Advances ``index`` past every consumed line; the returned lines are
        /// verbatim (untrimmed). Stops at the first line classified as a marker
        /// or unknown marker, or at the envelope ``end``.
        ///
        /// - Returns: the consumed body lines, in order.
        private mutating func consumeBody() -> [String] {
            var body: [String] = []
            while index < end, case .content = classify(lines[index]) {
                body.append(lines[index])
                index += 1
            }
            return body
        }

        /// Claim a section's path, failing when it was already claimed by an earlier section.
        ///
        /// - Parameters:
        ///   - path: the section's declared path.
        ///   - line: the header's 1-based line, for the duplicate failure.
        /// - Returns: `.success` when the path is new, or `.failure` with a
        ///   duplicate-path ``ParseFailure``.
        private mutating func recordPath(_ path: String, line: Int) -> Result<Void, ParseFailure> {
            guard seenPaths.insert(path).inserted else {
                return .failure(ParseFailure(message: Messages.duplicatePath(path), line: line))
            }
            return .success(())
        }
    }
}

/// Equality over ``PatchParser/Hunk`` values, comparing the tuple-typed Update pairs element-wise.
///
/// Synthesis is unavailable because ``PatchParser/Pair`` is a tuple (tuples do
/// not conform to `Equatable`), so equality is written by hand: the `pairs`
/// arrays are equal when they have the same length and every positional
/// `(find, replace)` tuple compares equal.
extension PatchParser.Hunk: Equatable {
    /// Whether two hunks are equal, comparing paths, move destinations, and Update pairs positionally.
    ///
    /// - Parameters:
    ///   - lhs: the left hunk.
    ///   - rhs: the right hunk.
    /// - Returns: `true` when the two hunks are the same case with equal payloads.
    static func == (lhs: PatchParser.Hunk, rhs: PatchParser.Hunk) -> Bool {
        switch (lhs, rhs) {
        case (.addFile(let lPath, let lContents), .addFile(let rPath, let rContents)):
            return lPath == rPath && lContents == rContents
        case (.deleteFile(let lPath), .deleteFile(let rPath)):
            return lPath == rPath
        case (.updateFile(let lPath, let lMove, let lPairs), .updateFile(let rPath, let rMove, let rPairs)):
            return lPath == rPath && lMove == rMove && pairsEqual(lPairs, rPairs)
        default:
            return false
        }
    }

    /// Whether two Update pair lists are equal, comparing each `(find, replace)` tuple positionally.
    ///
    /// - Parameters:
    ///   - lhs: the left pair list.
    ///   - rhs: the right pair list.
    /// - Returns: `true` when the lists have equal length and every positional tuple is equal.
    private static func pairsEqual(_ lhs: [PatchParser.Pair], _ rhs: [PatchParser.Pair]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { $0 == $1 }
    }
}
