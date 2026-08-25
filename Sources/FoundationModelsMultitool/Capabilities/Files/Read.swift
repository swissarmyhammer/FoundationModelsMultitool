// `Read` — the `tools.files.read` verb.
//
// A behavioral port of `../FoundationModelsFileTool/Sources/FileTool/
// Operations/ReadFile.swift`. The sibling is an `@Operation` that takes a
// `FileContext` through its `execute(in:)`; this package has no operation
// machinery, thus the verb is a plain `FoundationModels.Tool` that holds
// the context it reads against, in the pattern of `Capabilities/Files/
// Glob.swift`. The sibling's `@OperationParam` aliases (`file_path`,
// `absolute_path`) do not port: plain `@Generable` arguments keep only the
// canonical names. The sibling's `ReadOutput` enum does not port either:
// the flat result carries a `correction` field in its place.
//
// eventplan.md § "Registration of capabilities: noun/verb": the capability
// supplies the noun, thus this verb's `name` is the bare `read` and the
// surface path renders as `tools.files.read`.
//
// A read the verb cannot make stays IN BAND, as a `correction` beside
// empty content. It is never thrown: an out-of-range `offset` or `limit`,
// an unknown `format`, a path outside the root, a missing or unreadable
// file, and a binary file are each a mistake the model corrects inside
// the turn, and a thrown error would end the turn instead.

import Foundation
import FoundationModels

/// The arguments of `tools.files.read`: the file to read, the window to
/// select, and the format to render.
@Generable
struct ReadArguments {

    /// The path of the file to read.
    @Guide(description: "The path of the file to read, absolute or relative to the session root.")
    var path: String

    /// The 1-based line number to start reading from, or `nil` for the
    /// first line.
    @Guide(description: "The 1-based line number to start reading from. Omit it to start at the first line.")
    var offset: Int?

    /// The maximum number of lines to return, or `nil` for the whole tail.
    @Guide(description: "The maximum number of lines to return. Omit it to read to the end of the file.")
    var limit: Int?

    /// The output format name: `hashline` anchors (the default) or `plain`
    /// text, or `nil` for the default.
    @Guide(
        description:
            "The output format. `hashline` (the default) tags each line as `N:HH|text` with its "
            + "absolute line number and content hash; `plain` returns the raw text.")
    var format: String?
}

/// The result of `tools.files.read`: the windowed lines, or the correction
/// that says why there are none.
///
/// `correction` and the content are exclusive. A read that answers content
/// carries no correction, and a correction carries an empty `hash`, no
/// line, and no note.
@Generable(
    description: "the file's lines in the requested format, or the correction that says why there are none.")
struct ReadResult {

    /// The whole-file freshness token: the lowercase-hex MD5 over the full
    /// on-disk bytes. It reflects the full file regardless of the window,
    /// thus it is identical across windows of one file. Empty on a
    /// correction.
    var hash: String

    /// The selected window of lines: `N:HH|text` anchors in the `hashline`
    /// format, or the raw text in the `plain` format.
    var lines: [String]

    /// The description of the window, or `nil` for a whole-file read.
    var note: String?

    /// Why the read answered no content, or `nil` when the content stands.
    var correction: String?
}

extension Read {

    // MARK: Bounds

    /// A bounded integer parameter: its name, the kind of value it expects,
    /// and its inclusive range.
    ///
    /// Bound checking is data, not control flow: ``offsetBound`` and
    /// ``limitBound`` are two instances of this one type, and
    /// ``violation(_:)`` is the single code path that validates a value and
    /// builds its corrective message. There is no per-parameter validation
    /// function or message string to keep in lockstep — a parameter's whole
    /// identity lives in its spec.
    private struct BoundSpec {
        /// The parameter name, as it appears in backticks in a corrective message (`offset`).
        let parameterName: String

        /// The kind of value expected, as it reads in a corrective message (`1-based line number`).
        let typeDescription: String

        /// The smallest acceptable value.
        let minimum: Int

        /// The largest acceptable value.
        let maximum: Int

        /// The corrective message naming this parameter's valid, inclusive range.
        var correctiveMessage: String {
            "The `\(parameterName)` parameter must be a \(typeDescription) between \(minimum) and \(maximum)."
        }

        /// A corrective message when `value` is present and out of range, or `nil` when acceptable.
        ///
        /// An absent value is acceptable (the parameter was omitted); an
        /// in-range value is acceptable; an out-of-range value yields
        /// ``correctiveMessage``.
        ///
        /// - Parameter value: the requested value, or `nil` when the parameter was omitted.
        /// - Returns: ``correctiveMessage`` when `value` is present and out
        ///   of range, else `nil`.
        func violation(_ value: Int?) -> String? {
            guard let value else { return nil }
            return (minimum...maximum).contains(value) ? nil : correctiveMessage
        }
    }

    /// The largest accepted `offset`: the millionth line, matching the Rust `files` tool.
    private static let maximumOffset = 1_000_000

    /// The largest accepted `limit`: a hundred thousand lines, matching the Rust `files` tool.
    private static let maximumLimit = 100_000

    /// The bound on `offset`: a 1-based line number up to ``maximumOffset``.
    private static let offsetBound = BoundSpec(
        parameterName: "offset",
        typeDescription: "1-based line number",
        minimum: 1,
        maximum: maximumOffset
    )

    /// The bound on `limit`: a line count up to ``maximumLimit``.
    private static let limitBound = BoundSpec(
        parameterName: "limit",
        typeDescription: "line count",
        minimum: 1,
        maximum: maximumLimit
    )

    // MARK: Format names

    /// The format name selecting hashline-anchored output.
    private static let hashlineFormatName = "hashline"

    /// The format name selecting plain, untagged output.
    private static let plainFormatName = "plain"

    /// The format used when the `format` parameter is absent.
    private static let defaultFormatName = hashlineFormatName

    // MARK: Window-note text

    /// The leading text of a window note (before the start line number).
    private static let windowNotePrefix = "showing lines "

    /// The separator between the window's start and end line numbers (an en dash).
    private static let windowNoteRangeSeparator = "\u{2013}"

    /// The text between the window's end line number and the file's total.
    private static let windowNoteTotalPrefix = " of "

    // MARK: Output format

    /// The resolved output format of a read.
    private enum ReadFormat {
        /// Each line carries an absolute `N:HH|text` hashline anchor.
        case hashline

        /// Each line is the raw text, with no anchor or per-line tag.
        case plain
    }

    /// The mapping from an accepted `format` name to its resolved ``ReadFormat``.
    ///
    /// Format resolution is data, not control flow: this table is the
    /// single place that enumerates the accepted names, thus
    /// ``resolveFormat(_:)`` is one lookup and the valid names in
    /// ``unknownFormatMessage`` cannot drift out of step with what the verb
    /// actually accepts. The canonical names (`hashline`, `plain`) are
    /// exactly what ``unknownFormatMessage`` shows the model;
    /// ``formatMapByFoldedName`` is the case-folded lookup derived from
    /// this table.
    private static let formatMap: [String: ReadFormat] = [
        hashlineFormatName: .hashline,
        plainFormatName: .plain,
    ]

    /// ``formatMap`` re-keyed by lowercased name, for the case-folded lookup.
    ///
    /// Derived from the canonical table rather than written out again, thus
    /// the two cannot diverge. The canonical spellings stay the ones
    /// ``unknownFormatMessage`` shows the model; only the *lookup* folds
    /// case. ``formatMap``'s keys happen to be all-lowercase today, but
    /// deriving the folded table keeps a future camelCase format name from
    /// silently breaking the lookup. The grep verb's `outputMode` and
    /// `type` parameters (card ^2j06zb7) resolve the same way when they
    /// arrive, thus the string-enum parameters of the file verbs do not
    /// disagree about whether `Plain` is spelled acceptably.
    private static let formatMapByFoldedName: [String: ReadFormat] =
        Dictionary(uniqueKeysWithValues: formatMap.map { ($0.key.lowercased(), $0.value) })

    // MARK: Execution

    /// Reads the file and answers the windowed content, or the correction
    /// that says why there is none.
    ///
    /// Validates the `offset` / `limit` / `format` bounds, then the path
    /// via the context's ``PathGuard``, then reads and UTF-8-decodes the
    /// full bytes (rejecting a binary file), and finally windows and tags
    /// the text. Each recoverable failure comes back as the `correction`
    /// field of the result; nothing here throws for a bad parameter, path,
    /// or file.
    ///
    /// - Parameter arguments: What to read, the window, and the format.
    /// - Returns: The windowed content, or the correction.
    func call(arguments: ReadArguments) async throws -> ReadResult {
        if let message = Self.offsetBound.violation(arguments.offset) { return Self.corrective(message) }
        if let message = Self.limitBound.violation(arguments.limit) { return Self.corrective(message) }
        guard let resolvedFormat = Self.resolveFormat(arguments.format) else {
            return Self.corrective(Self.unknownFormatMessage)
        }

        return context.pathGuard.validate(arguments.path, for: .read)
            .resolve(corrective: Self.corrective) { url in
                PathCorrective.readData(at: url, path: arguments.path)
                    .resolve(corrective: Self.corrective) { data in
                        guard let content = String(data: data, encoding: .utf8) else {
                            return Self.corrective(
                                PathCorrective.pathErrorMessage(
                                    description: Self.binaryDescription, path: arguments.path))
                        }

                        let hash = Hashline.wholeFileHash(bytes: data)
                        return Self.window(
                            content: content, hash: hash, offset: arguments.offset, limit: arguments.limit,
                            format: resolvedFormat)
                    }
            }
    }

    // MARK: Format resolution

    /// Resolves the requested format name to a ``ReadFormat``, or `nil` when unknown.
    ///
    /// An absent name resolves to the default (`hashline`); each other name
    /// is looked up in ``formatMapByFoldedName``, thus the accepted set
    /// lives in one place. The lookup ignores case.
    ///
    /// - Parameter name: the requested format name, or `nil`.
    /// - Returns: the resolved format, or `nil` when the name is unrecognized.
    private static func resolveFormat(_ name: String?) -> ReadFormat? {
        formatMapByFoldedName[(name ?? defaultFormatName).lowercased()]
    }

    // MARK: Windowing

    /// Windows the decoded content by line and tags it in the requested format.
    ///
    /// Splits the content into physical lines, selects the `offset` /
    /// `limit` window (clamped to the file's bounds), and renders each
    /// windowed line — as an absolute hashline anchor via
    /// ``Hashline/tag(lines:startingAtLine:)`` for the `hashline` format,
    /// or verbatim for `plain`. The result's `hash` is carried through
    /// unchanged, thus it reflects the full file, not the window.
    ///
    /// - Parameters:
    ///   - content: the full UTF-8 file content.
    ///   - hash: the whole-file freshness token over the full on-disk bytes.
    ///   - offset: the requested 1-based start line, or `nil` for the first line.
    ///   - limit: the requested maximum line count, or `nil` for the whole tail.
    ///   - format: the resolved output format.
    /// - Returns: the windowed ``ReadResult``, with no correction.
    private static func window(
        content: String,
        hash: String,
        offset: Int?,
        limit: Int?,
        format: ReadFormat
    ) -> ReadResult {
        let physicalLines = Hashline.splitLines(content)
        let total = physicalLines.count
        let startIndex = min(max((offset ?? 1) - 1, 0), total)
        let requestedCount = limit ?? (total - startIndex)
        let endIndex = min(startIndex + max(requestedCount, 0), total)
        let windowSlice = physicalLines[startIndex..<endIndex]

        let lines: [String]
        switch format {
        case .plain:
            lines = windowSlice.map(\.text)
        case .hashline:
            let windowContent = windowSlice.map { $0.text + $0.terminator }.joined()
            let tagged = Hashline.tag(lines: windowContent, startingAtLine: startIndex + 1)
            lines = Hashline.splitLines(tagged).map(\.text)
        }

        let note = windowNote(startIndex: startIndex, endIndex: endIndex, total: total)
        return ReadResult(hash: hash, lines: lines, note: note, correction: nil)
    }

    /// Builds the window note, or `nil` when the window is the whole file.
    ///
    /// Returns `nil` for a whole-file read (the window covers every line).
    /// For a non-empty subset it reports the inclusive 1-based line range
    /// and total; a window that begins past the end of the file reports
    /// that instead.
    ///
    /// - Parameters:
    ///   - startIndex: the 0-based index of the window's first line.
    ///   - endIndex: the 0-based index one past the window's last line.
    ///   - total: the total number of lines in the file.
    /// - Returns: the window note, or `nil` for a whole-file read.
    private static func windowNote(startIndex: Int, endIndex: Int, total: Int) -> String? {
        if startIndex == 0 && endIndex == total { return nil }
        if endIndex == startIndex { return pastEndMessage(total: total) }
        return
            "\(windowNotePrefix)\(startIndex + 1)\(windowNoteRangeSeparator)\(endIndex)\(windowNoteTotalPrefix)\(total)"
    }

    // MARK: Corrective messages

    /// A result carrying only a correction: empty hash, no line, no note.
    ///
    /// - Parameter message: the correction the model reads and acts on.
    /// - Returns: the corrective ``ReadResult``.
    private static func corrective(_ message: String) -> ReadResult {
        ReadResult(hash: "", lines: [], note: nil, correction: message)
    }

    /// The corrective message naming the valid `format` values.
    ///
    /// The valid names are derived from the authoritative ``formatMap``
    /// keys, thus the message cannot drift out of step with the set of
    /// formats the verb actually accepts; adding a format requires editing
    /// only the map.
    private static var unknownFormatMessage: String {
        EnumParameter.unknownValueMessage(validNames: formatMap.keys, parameterName: "format")
    }

    /// The description of a non-UTF-8 (binary) file, which is never decoded, before the `: path` suffix.
    ///
    /// Composed with ``PathCorrective/pathErrorMessage(description:path:)``
    /// at the call site; the unreadable-path description lives there too
    /// (``PathCorrective/unreadableDescription``), since it is
    /// byte-identical to the edit verb's, while this wording is
    /// read-specific.
    private static let binaryDescription =
        "The file is not valid UTF-8 text and appears to be binary, so it cannot be read as text"

    /// The window note for a window that begins past the end of the file.
    ///
    /// - Parameter total: the total number of lines in the file.
    /// - Returns: the window note.
    private static func pastEndMessage(total: Int) -> String {
        "\(windowNotePrefix)none; the window begins past the end of the file\(windowNoteTotalPrefix)\(total)"
    }
}

/// Reads a file's contents, windowed by line and tagged with hashline anchors.
///
/// ```swift
/// // In a snippet the model writes:
/// //   const page = await tools.files.read({ path: "Sources/App/main.swift", offset: 40, limit: 20 });
/// ```
///
/// The contract: the default `hashline` format tags each windowed line
/// with an absolute `N:HH|text` anchor — the line number and content hash
/// the edit verb resolves against — and the `plain` format returns the raw
/// text instead. `offset` (a 1-based line number) and `limit` (a line
/// count) select a window, and the `note` reports the window when the
/// lines are a strict subset of the file. The `hash` is the whole-file
/// freshness token over the full on-disk bytes, thus it never changes with
/// the window, and a later write or edit re-derives it to detect
/// staleness. The path is bounded through the session's ``PathGuard``. An
/// out-of-range `offset` or `limit`, an unknown `format`, a path outside
/// the root, a missing or unreadable file, and a binary (non-UTF-8) file
/// each come back as a `correction` rather than as an error.
///
/// The context it reads against is the context the files capability owns,
/// thus each verb of one capability answers for the same session.
struct Read: Tool {

    /// The verb this tool renders as, which the files noun stands in front
    /// of: `tools.files.read`.
    let name = "read"

    /// The usage instructions, as the model reads them.
    let description = """
        read reads a file's contents, windowed by line. offset is the 1-based line to start \
        from and limit is the maximum number of lines, thus a large file is read one window \
        at a time. The default hashline format tags each line as N:HH|text with its absolute \
        line number and content hash; format plain returns the raw text instead. The hash in \
        the result is the whole-file freshness token over the full bytes, identical across \
        windows. An out-of-range offset or limit, an unknown format, a path outside the \
        session root, a missing or unreadable file, and a binary file each come back as a \
        correction rather than as an error — read it, correct the call, and ask again.
        """

    /// The session context this verb reads against, which the files capability owns.
    ///
    /// The compiler-synthesized memberwise initializer takes this one
    /// property, thus the capability makes the verb as `Read(context:)`.
    let context: FileContext
}
