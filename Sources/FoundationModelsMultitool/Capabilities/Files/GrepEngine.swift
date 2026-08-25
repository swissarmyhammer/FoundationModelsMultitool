// `GrepEngine` — the pattern and filter validation, the bounded git-aware
// walk, the binary skip, the line matching, and the context assembly
// behind the `tools.files.grep` verb.
//
// A behavioral port of `../FoundationModelsFileTool/Sources/FileTool/
// GrepEngine.swift`, unchanged in behavior. One name changes: the sibling
// calls the success payload `GrepResult`, and this package gives that name
// to the verb's flat result (the Shell verbs name their flat results
// `<Verb>Result`), thus the engine's success payload is `GrepMatches`
// here. The sibling declares the types `public`; this package keeps them
// internal, the same way `GlobEngine` beside it does. Two other pieces do
// not port: the deprecated `caseInsensitive:` compatibility overload,
// which no caller of this package ever compiled against, and the
// `elapsedMs` `CodingKeys` spelling, which now lives on the verb's flat
// result where the wire is rendered.
//
// eventplan.md § "Consolidation of the siblings": the glob and grep verbs
// resolve, bound, and enumerate a search root through the shared
// `FileWalker`, and a corrective result stays in band, never thrown.

import Foundation

/// One line of a grep result: the file it came from, its line number, its
/// text, and whether it matched.
///
/// A ``GrepMatch`` is emitted for every line rendered in the `content` output
/// mode — both the lines that the pattern actually matched (``isMatch``
/// `true`) and the surrounding context lines carried along for readability
/// (``isMatch`` `false`). The ``line`` is the 1-based physical line number,
/// numbered against the same line model the read verb uses, so a match's
/// address can be fed straight back to `tools.files.read` and
/// `tools.files.edit`.
struct GrepMatch: Encodable, Sendable {
    /// The matching file's path relative to the session root.
    let file: String

    /// The 1-based physical line number of this line within its file.
    let line: Int

    /// The line's text, with its terminator excluded.
    let text: String

    /// Whether this line matched the pattern (`true`) or is surrounding context (`false`).
    let isMatch: Bool
}

/// The successful matches of one grep, shaped by the requested output mode.
///
/// The three output modes carry different fields, expressed here as optionals
/// that are absent when the mode leaves them out: the `content` mode carries
/// ``matches`` (with ``files`` absent); the `filesWithMatches` mode carries
/// ``files`` (with ``matches`` absent); and the `count` mode carries neither.
/// All three always carry the ``matchCount`` (the number of matched lines —
/// only match lines count, never context lines), the ``fileCount`` (the
/// number of files with at least one match), and the ``elapsedMilliseconds``
/// wall-clock timing.
struct GrepMatches: Encodable, Sendable {
    /// The matched and context lines, present only in the `content` mode.
    let matches: [GrepMatch]?

    /// The relative paths of the files with at least one match, present only in the `filesWithMatches` mode.
    let files: [String]?

    /// The total number of matched lines across all files; context lines never count.
    let matchCount: Int

    /// The number of files with at least one matched line.
    let fileCount: Int

    /// The wall-clock duration of the search, in milliseconds.
    let elapsedMilliseconds: Double
}

/// The outcome of one grep: either the mode-shaped matches or a corrective message.
///
/// The engine follows the upstream *return-don't-throw* convention (the same
/// convention ``GlobOutput`` and ``PathViolation`` embody): an invalid
/// regular expression, an unknown file type, an unknown output mode, an
/// invalid `glob` filter, a rejected search root, or a missing path is
/// surfaced as a ``corrective(_:)`` message the model reads and acts on
/// within the turn, never thrown. A thrown error is fatal to the turn, so
/// every recoverable condition returns a value instead.
enum GrepOutput: CorrectiveEncodable, Sendable {
    /// A successful grep carrying the ``GrepMatches``.
    case content(GrepMatches)

    /// A recoverable failure carrying a corrective message for the model.
    case corrective(String)

    /// The successful ``GrepMatches`` (encoded inline), or `nil` for a corrective outcome.
    var successResult: GrepMatches? {
        if case .content(let matches) = self { return matches }
        return nil
    }

    /// The corrective message, or `nil` for a successful outcome.
    var correctiveMessage: String? {
        if case .corrective(let message) = self { return message }
        return nil
    }
}

/// Searches file contents for a regular expression, git-aware and binary-skipping, shaped by output mode.
///
/// The engine resolves the output mode, the optional file-type filter, the
/// optional `glob` filename filter, and the regular expression (all invalid
/// inputs returned as correctives); resolves the search target through the
/// context's ``PathGuard`` (a single file short-circuits the walk, a
/// directory is enumerated); enumerates candidate files through the shared,
/// git-aware ``FileWalker`` so a gitignored directory such as `build/` is
/// never descended into — the fix for the "unscoped grep hung forever"
/// pathology; skips a file whose first bytes contain a NUL (a binary file);
/// matches each line with Swift `Regex`; assembles the matched lines with
/// their surrounding context into hunks; and returns the mode-shaped
/// ``GrepMatches``. Every recoverable failure is returned as
/// ``GrepOutput/corrective(_:)``; nothing here throws.
struct GrepEngine: Sendable {
    // MARK: Configuration

    /// The number of context lines rendered on each side of a match when `contextLines` is absent.
    private static let defaultContextLines = 2

    /// The smallest permitted context-line count: a floor that degrades any requested negative value to match-lines-only.
    private static let minimumContextLines = 0

    /// The number of leading bytes inspected for a NUL byte when classifying a file as binary.
    ///
    /// A file whose first 8 kibibytes contain a NUL byte is treated as binary
    /// and skipped, matching the Rust `files` tool's binary-detection window.
    private static let binarySniffWindowByteCount = 8 * 1024

    /// The byte value whose presence in the sniff window marks a file as binary.
    private static let nullByte: UInt8 = 0

    /// The inline flag prepended to the pattern to make matching case-insensitive.
    private static let caseInsensitivePrefix = "(?i)"

    /// The number of milliseconds in one second, used to report the elapsed duration.
    private static let millisecondsPerSecond = 1000.0

    // MARK: Output modes

    /// The `content` output-mode name: matched lines with their surrounding context.
    private static let contentModeName = "content"

    /// The `filesWithMatches` output-mode name: only the list of matching files.
    private static let filesWithMatchesModeName = "filesWithMatches"

    /// The `count` output-mode name: only the match and file totals.
    private static let countModeName = "count"

    /// The output mode used when the `outputMode` parameter is absent.
    private static let defaultOutputModeName = contentModeName

    /// A resolved output mode selecting which fields the result carries.
    private enum OutputMode {
        /// Matched lines and their surrounding context.
        case content
        /// Only the relative paths of the matching files.
        case filesWithMatches
        /// Only the match and file totals.
        case count
    }

    /// The mapping from an accepted `outputMode` name to its resolved ``OutputMode``.
    ///
    /// Output-mode resolution is data, not control flow: this table is the
    /// single place that enumerates the accepted names, so ``resolveOutputMode(name:)``
    /// is one lookup and the valid names in ``unknownOutputModeMessage`` cannot
    /// drift out of step with what the engine actually accepts.
    private static let outputModeMap: [String: OutputMode] = [
        contentModeName: .content,
        filesWithMatchesModeName: .filesWithMatches,
        countModeName: .count,
    ]

    /// ``outputModeMap`` re-keyed by lowercased name, for the case-folded lookup.
    ///
    /// Derived from the canonical table rather than written out again, so the
    /// two cannot diverge. The canonical spellings stay the ones
    /// ``unknownOutputModeMessage`` shows the model; only the *lookup* folds
    /// case. Folding cannot be done by lowercasing the requested name against
    /// ``outputModeMap`` directly — `filesWithMatches` is camelCase, so
    /// `outputModeMap["fileswithmatches"]` misses.
    private static let outputModeMapByFoldedName: [String: OutputMode] =
        Dictionary(uniqueKeysWithValues: outputModeMap.map { ($0.key.lowercased(), $0.value) })

    /// Which optional fields a ``GrepMatches`` carries, per output mode.
    private struct ResultFields {
        /// Whether the result carries the matched and context lines.
        let includesMatches: Bool

        /// Whether the result carries the matched-file list.
        let includesFiles: Bool
    }

    /// The field selection carrying neither optional field, used by the `count`
    /// mode and as the default for any mode absent from ``resultFieldsByMode``.
    private static let noResultFields = ResultFields(includesMatches: false, includesFiles: false)

    /// The field selection for each output mode.
    ///
    /// The three modes differ only in which optional fields they populate:
    /// `content` carries ``GrepMatches/matches``, `filesWithMatches` carries
    /// ``GrepMatches/files``, and `count` carries neither. Both the match-list
    /// collection in ``search(candidates:regex:contextLines:mode:)`` and the
    /// result shaping in ``makeResult(mode:matches:files:matchCount:elapsedMilliseconds:)``
    /// interpret this one table via ``resultFields(for:)``, keeping the
    /// selection data-driven and single-sourced rather than parallel branches a
    /// human must keep in lockstep.
    private static let resultFieldsByMode: [OutputMode: ResultFields] = [
        .content: ResultFields(includesMatches: true, includesFiles: false),
        .filesWithMatches: ResultFields(includesMatches: false, includesFiles: true),
        .count: noResultFields,
    ]

    /// The field selection for an output mode, defaulting to carrying no
    /// optional fields for any mode absent from ``resultFieldsByMode``.
    ///
    /// - Parameter mode: the resolved output mode.
    /// - Returns: the ``ResultFields`` selection for the mode.
    private static func resultFields(for mode: OutputMode) -> ResultFields {
        resultFieldsByMode[mode, default: noResultFields]
    }

    // MARK: File-type filter

    /// The mapping from a `type` filter name to the file extensions it selects.
    ///
    /// The file-type filter is data, not control flow: this table is the single
    /// place that enumerates the known types, so the filter is one lookup and
    /// the known-type list in ``unknownTypeMessage(type:)`` cannot drift out of
    /// step with what the engine actually accepts. Extensions are compared
    /// lowercased, so the values here are lowercase.
    private static let typeExtensionMap: [String: Set<String>] = [
        "rust": ["rs"],
        "py": ["py", "pyi"],
        "js": ["js", "jsx", "mjs", "cjs"],
        "ts": ["ts", "tsx"],
        "swift": ["swift"],
        "json": ["json"],
        "yaml": ["yaml", "yml"],
        "toml": ["toml"],
        "md": ["md", "markdown"],
        "c": ["c", "h"],
        "cpp": ["cpp", "cc", "cxx", "hpp", "hh"],
        "go": ["go"],
        "java": ["java"],
        "sh": ["sh", "bash"],
        "html": ["html", "htm"],
        "css": ["css"],
        "xml": ["xml"],
        "txt": ["txt"],
    ]

    // MARK: Execution

    /// Searches file contents for `pattern` and returns the mode-shaped matches, or a corrective message.
    ///
    /// Resolves the output mode, the file-type filter, the `glob` filter, and
    /// the regular expression (returning a corrective for any invalid input);
    /// resolves the search target through `context`'s ``PathGuard`` (a single
    /// file short-circuits the walk, a directory is enumerated git-aware);
    /// skips binary files; matches each line; assembles context into hunks; and
    /// returns the mode-shaped ``GrepMatches``. Every recoverable failure is
    /// returned as ``GrepOutput/corrective(_:)``; nothing here throws.
    ///
    /// - Parameters:
    ///   - pattern: the regular-expression pattern to search for.
    ///   - path: the file or directory to search, or `nil` to search the session root.
    ///   - glob: an optional filename filter applied to a directory walk.
    ///   - type: an optional file-type filter naming a known type (for example `swift`).
    ///   - caseSensitive: whether matching is case-sensitive; defaults to `true`.
    ///     Named and polarized to match ``GlobEngine/run(pattern:path:caseSensitive:respectGitIgnore:in:)``,
    ///     so the two engines spell the same concept the same way. The
    ///     *defaults* still differ on purpose, and identical spellings now hide
    ///     that: `tools.files.grep` defaults to case-**sensitive** (matching
    ///     the upstream Rust tool's `caseInsensitive: false`), while
    ///     `tools.files.glob` defaults to case-**insensitive** (matching the
    ///     filesystem). Only the name and polarity are shared. The grep verb's
    ///     *wire* parameter also stays `caseInsensitive` (the upstream
    ///     spelling); the verb's `call(arguments:)` is the single place that
    ///     inverts it.
    ///   - contextLines: the number of context lines on each side of a match, or
    ///     `nil` for the default of two; `0` returns match lines only.
    ///   - outputMode: the output mode name, or `nil` for the default `content` mode.
    ///   - context: the shared session context supplying the path guard and root.
    /// - Returns: the ``GrepOutput/content(_:)`` matches on success, or a
    ///   ``GrepOutput/corrective(_:)`` message the model can act on.
    func run(
        pattern: String,
        path: String? = nil,
        glob: String? = nil,
        type: String? = nil,
        caseSensitive: Bool = true,
        contextLines: Int? = nil,
        outputMode: String? = nil,
        in context: FileContext
    ) -> GrepOutput {
        guard let mode = Self.resolveOutputMode(name: outputMode) else {
            return .corrective(Self.unknownOutputModeMessage)
        }

        let typeExtensions: Set<String>?
        if let type {
            guard let extensions = Self.typeExtensionMap[type.lowercased()] else {
                return .corrective(Self.unknownTypeMessage(type: type))
            }
            typeExtensions = extensions
        } else {
            typeExtensions = nil
        }

        let compiledGlob: GlobPattern?
        if let glob {
            guard let compiled = try? GlobPattern(glob) else {
                return .corrective(Self.invalidGlobMessage(glob: glob))
            }
            compiledGlob = compiled
        } else {
            compiledGlob = nil
        }

        guard let regex = try? Regex(caseSensitive ? pattern : Self.caseInsensitivePrefix + pattern)
        else {
            return .corrective(Self.invalidPatternMessage(pattern: pattern))
        }

        return Self.resolveTarget(path: path, in: context)
            .resolve(corrective: GrepOutput.corrective) { target in
                let sessionRoot = FileWalker.canonicalDirectory(context.root)
                let candidates = Self.candidateFiles(
                    target: target,
                    sessionRoot: sessionRoot,
                    glob: compiledGlob,
                    typeExtensions: typeExtensions
                )
                // Clamp to the match-lines-only floor so a negative `contextLines` cannot
                // silently drop matched lines from the content while `matchCount` still
                // counts them.
                let effectiveContextLines = max(Self.minimumContextLines, contextLines ?? Self.defaultContextLines)
                return .content(
                    Self.search(candidates: candidates, regex: regex, contextLines: effectiveContextLines, mode: mode))
            }
    }

    // MARK: Search

    /// Scans the candidate files and assembles the mode-shaped result.
    ///
    /// Reads and matches each candidate (skipping binary and unreadable files),
    /// records the matched lines and files, assembles the context hunks for the
    /// `content` mode, and stamps the wall-clock duration. Only matched lines
    /// count toward ``GrepMatches/matchCount``; context lines never do.
    ///
    /// - Parameters:
    ///   - candidates: the files to scan, each with its session-relative path.
    ///   - regex: the compiled pattern.
    ///   - contextLines: the number of context lines on each side of a match.
    ///   - mode: the resolved output mode selecting the result shape.
    /// - Returns: the mode-shaped ``GrepMatches``.
    private static func search(
        candidates: [Candidate],
        regex: Regex<AnyRegexOutput>,
        contextLines: Int,
        mode: OutputMode
    ) -> GrepMatches {
        let start = Date()
        var allMatches: [GrepMatch] = []
        var matchedFiles: [String] = []
        var matchCount = 0

        for candidate in candidates {
            guard let scan = scanFile(path: candidate.absolutePath, regex: regex), !scan.matchLines.isEmpty else {
                continue
            }
            matchedFiles.append(candidate.relativePath)
            matchCount += scan.matchLines.count
            if resultFields(for: mode).includesMatches {
                allMatches.append(
                    contentsOf: buildMatches(
                        file: candidate.relativePath,
                        lines: scan.lines,
                        matchLines: scan.matchLines,
                        contextLines: contextLines
                    )
                )
            }
        }

        let elapsed = Date().timeIntervalSince(start) * millisecondsPerSecond
        return makeResult(
            mode: mode, matches: allMatches, files: matchedFiles, matchCount: matchCount, elapsedMilliseconds: elapsed)
    }

    /// Assembles the mode-shaped result from the gathered data.
    ///
    /// Selects which fields the result carries per the output mode: `content`
    /// carries the matches, `filesWithMatches` carries the files, and `count`
    /// carries neither. All modes carry the counts and elapsed duration.
    ///
    /// - Parameters:
    ///   - mode: the resolved output mode.
    ///   - matches: the assembled matched and context lines.
    ///   - files: the relative paths of the matching files.
    ///   - matchCount: the total number of matched lines.
    ///   - elapsedMilliseconds: the wall-clock duration of the search.
    /// - Returns: the mode-shaped ``GrepMatches``.
    private static func makeResult(
        mode: OutputMode,
        matches: [GrepMatch],
        files: [String],
        matchCount: Int,
        elapsedMilliseconds: Double
    ) -> GrepMatches {
        let fields = resultFields(for: mode)
        return GrepMatches(
            matches: fields.includesMatches ? matches : nil,
            files: fields.includesFiles ? files : nil,
            matchCount: matchCount,
            fileCount: files.count,
            elapsedMilliseconds: elapsedMilliseconds
        )
    }

    // MARK: File scanning

    /// The per-file scan result: the matched line numbers and the file's line texts.
    private struct FileScan {
        /// The 1-based line numbers that matched the pattern, ascending.
        let matchLines: [Int]

        /// The file's line texts, terminators excluded, 1-based by array index plus one.
        let lines: [String]
    }

    /// Scans one file for matching lines, or `nil` when it is unreadable or binary.
    ///
    /// Reads the file's bytes, skips it when it is unreadable, binary (a NUL
    /// byte in the sniff window), or not valid UTF-8, then splits it into
    /// physical lines and records the 1-based numbers of the lines the pattern
    /// matches.
    ///
    /// - Parameters:
    ///   - path: the absolute path of the file to scan.
    ///   - regex: the compiled pattern.
    /// - Returns: the ``FileScan`` on success, or `nil` when the file is
    ///   unreadable or binary.
    private static func scanFile(path: String, regex: Regex<AnyRegexOutput>) -> FileScan? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        guard !isBinary(data: data) else { return nil }
        guard let content = String(data: data, encoding: .utf8) else { return nil }
        let lines = Hashline.splitLines(content).map(\.text)
        var matchLines: [Int] = []
        for (index, line) in lines.enumerated() where line.contains(regex) {
            matchLines.append(index + 1)
        }
        return FileScan(matchLines: matchLines, lines: lines)
    }

    /// Whether a file's leading bytes contain a NUL byte, marking it as binary.
    ///
    /// - Parameter data: the file's bytes.
    /// - Returns: `true` when the first ``binarySniffWindowByteCount`` bytes
    ///   contain a NUL byte.
    private static func isBinary(data: Data) -> Bool {
        data.prefix(binarySniffWindowByteCount).contains(nullByte)
    }

    // MARK: Context assembly

    /// Builds the matched and context lines for one file, grouped into hunks.
    ///
    /// Each match contributes a window of `contextLines` lines on each side;
    /// overlapping or contiguous windows merge into one hunk, and a gap between
    /// windows becomes a hunk boundary (the intervening lines are omitted). Each
    /// emitted line is flagged ``GrepMatch/isMatch`` according to whether it is
    /// one of the matched lines.
    ///
    /// - Parameters:
    ///   - file: the file's session-relative path.
    ///   - lines: the file's line texts.
    ///   - matchLines: the 1-based numbers of the matched lines, ascending.
    ///   - contextLines: the number of context lines on each side of a match.
    /// - Returns: the matched and context lines in ascending line order.
    private static func buildMatches(
        file: String,
        lines: [String],
        matchLines: [Int],
        contextLines: Int
    ) -> [GrepMatch] {
        let matchSet = Set(matchLines)
        var result: [GrepMatch] = []
        for hunk in hunkRanges(matchLines: matchLines, totalLines: lines.count, contextLines: contextLines) {
            for lineNumber in hunk {
                result.append(
                    GrepMatch(
                        file: file, line: lineNumber, text: lines[lineNumber - 1],
                        isMatch: matchSet.contains(lineNumber))
                )
            }
        }
        return result
    }

    /// Merges the per-match context windows into hunk ranges.
    ///
    /// A match at line `m` contributes the window `[m - contextLines, m + contextLines]`
    /// clamped to the file's bounds. A window that overlaps or directly abuts
    /// the previous hunk (its start is at most one past the hunk's end) extends
    /// that hunk; otherwise it opens a new hunk, and the gap between the two is
    /// the hunk boundary.
    ///
    /// - Parameters:
    ///   - matchLines: the 1-based matched line numbers, ascending.
    ///   - totalLines: the number of lines in the file.
    ///   - contextLines: the number of context lines on each side of a match.
    /// - Returns: the merged hunk ranges, ascending and non-overlapping.
    private static func hunkRanges(matchLines: [Int], totalLines: Int, contextLines: Int) -> [ClosedRange<Int>] {
        var ranges: [ClosedRange<Int>] = []
        for match in matchLines {
            let start = max(1, match - contextLines)
            let end = min(totalLines, match + contextLines)
            guard start <= end else { continue }
            if let last = ranges.last, start <= last.upperBound + 1 {
                ranges[ranges.count - 1] = last.lowerBound...max(last.upperBound, end)
            } else {
                ranges.append(start...end)
            }
        }
        return ranges
    }

    // MARK: Target resolution

    /// A resolved search target: a single file to grep directly, or a directory to walk.
    private enum SearchTarget {
        /// A single file, short-circuiting the directory walk.
        case singleFile(URL)

        /// A directory to enumerate git-aware.
        case directory(URL)
    }

    /// Resolves the search target from the requested path, or a corrective violation.
    ///
    /// A given `path` is validated through the context's ``PathGuard`` (which
    /// enforces the workspace boundary); an absent `path` targets the session
    /// root. A path that does not exist is refused; an existing directory is
    /// refused when it is the filesystem root and otherwise walked; an existing
    /// file short-circuits the walk. All paths are canonicalized so the walk and
    /// the session-relative paths share one prefix model.
    ///
    /// - Parameters:
    ///   - path: the requested file or directory, or `nil` for the session root.
    ///   - context: the shared session context supplying the path guard and root.
    /// - Returns: `.success` with the resolved ``SearchTarget``, or `.failure`
    ///   with a corrective ``PathViolation``.
    private static func resolveTarget(path: String?, in context: FileContext) -> Result<SearchTarget, PathViolation> {
        FileWalker.resolveRequestedPath(path, in: context) { context.pathGuard.validatePath($0) }
            .flatMap { resolved in
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory) else {
                    return .failure(PathViolation(pathMissingMessage(path: path ?? resolved.path)))
                }
                guard isDirectory.boolValue else {
                    return .success(.singleFile(FileWalker.canonicalDirectory(resolved)))
                }
                return FileWalker.boundDirectory(resolved, in: context).map { .directory($0) }
            }
    }

    // MARK: Candidate gathering

    /// A candidate file to scan: its absolute path and its session-relative path.
    private struct Candidate {
        /// The candidate's absolute path on disk.
        let absolutePath: String

        /// The candidate's path relative to the session root, used in the result.
        let relativePath: String
    }

    /// Gathers the candidate files for a target, applying the filename and type filters.
    ///
    /// A single-file target short-circuits to that one file (no filtering — the
    /// caller named it explicitly). A directory target is enumerated through the
    /// shared git-aware ``FileWalker`` and then filtered by the `glob` filename
    /// filter and the file-type filter, sorted by session-relative path so the
    /// result is deterministic.
    ///
    /// - Parameters:
    ///   - target: the resolved search target.
    ///   - sessionRoot: the canonical session root the relative paths are formed against.
    ///   - glob: the optional compiled filename filter.
    ///   - typeExtensions: the optional set of extensions the file-type filter selects.
    /// - Returns: the candidate files to scan.
    private static func candidateFiles(
        target: SearchTarget,
        sessionRoot: URL,
        glob: GlobPattern?,
        typeExtensions: Set<String>?
    ) -> [Candidate] {
        switch target {
        case .singleFile(let file):
            let relativePath =
                FileWalker.relativePath(ofAbsolute: file.path, under: sessionRoot.path)
                ?? URL(fileURLWithPath: file.path).lastPathComponent
            return [Candidate(absolutePath: file.path, relativePath: relativePath)]
        case .directory(let walkRoot):
            return directoryCandidates(
                walkRoot: walkRoot, sessionRoot: sessionRoot, glob: glob, typeExtensions: typeExtensions)
        }
    }

    /// Gathers and filters the candidate files under a directory walk root.
    ///
    /// - Parameters:
    ///   - walkRoot: the canonical directory to enumerate.
    ///   - sessionRoot: the canonical session root the relative paths are formed against.
    ///   - glob: the optional compiled filename filter, matched against the walk-relative path.
    ///   - typeExtensions: the optional set of extensions the file-type filter selects.
    /// - Returns: the filtered candidate files, sorted by session-relative path.
    private static func directoryCandidates(
        walkRoot: URL,
        sessionRoot: URL,
        glob: GlobPattern?,
        typeExtensions: Set<String>?
    ) -> [Candidate] {
        FileWalker.walkAndFilter(
            walkRoot: walkRoot,
            sessionRoot: sessionRoot,
            respectGitIgnore: true,
            accept: { absolute, relativeToWalk in
                if let glob, !glob.matches(relativePath: relativeToWalk, caseSensitive: false) { return false }
                if let typeExtensions, !typeExtensions.contains(fileExtension(path: absolute)) { return false }
                return true
            },
            build: { absolute, relativeToSession -> Candidate? in
                Candidate(absolutePath: absolute, relativePath: relativeToSession)
            }
        )
        .sorted { $0.relativePath < $1.relativePath }
    }

    /// The lowercased filename extension of a path, or the empty string when there is none.
    ///
    /// - Parameter path: the absolute path whose extension to read.
    /// - Returns: the lowercased extension, without the leading dot.
    private static func fileExtension(path: String) -> String {
        URL(fileURLWithPath: path).pathExtension.lowercased()
    }

    // MARK: Filter resolution

    /// Resolves the requested output-mode name to an ``OutputMode``, or `nil` when unknown.
    ///
    /// An absent name resolves to the default (`content`); any other name is
    /// looked up in ``outputModeMapByFoldedName``, so the accepted set lives in
    /// one place.
    ///
    /// The lookup ignores case, matching how the sibling `type` filter resolves
    /// (``typeExtensionMap`` is queried with `type.lowercased()`): the two
    /// user-facing string-enum parameters of one verb should not disagree
    /// about whether `Content` is spelled acceptably.
    ///
    /// - Parameter name: the requested output-mode name, or `nil`.
    /// - Returns: the resolved output mode, or `nil` when the name is unrecognized.
    private static func resolveOutputMode(name: String?) -> OutputMode? {
        outputModeMapByFoldedName[(name ?? defaultOutputModeName).lowercased()]
    }

    // MARK: Corrective messages

    /// A corrective message for a pattern that is not a valid regular expression.
    ///
    /// - Parameter pattern: the rejected pattern.
    /// - Returns: the corrective message.
    private static func invalidPatternMessage(pattern: String) -> String {
        "The `pattern` is not a valid regular expression: \(pattern)"
    }

    /// A corrective message for a `glob` filter that is not a valid glob pattern.
    ///
    /// - Parameter glob: the rejected glob filter.
    /// - Returns: the corrective message.
    private static func invalidGlobMessage(glob: String) -> String {
        "The `glob` filter is not a valid glob pattern: \(glob)"
    }

    /// A corrective message for a search path that does not exist.
    ///
    /// - Parameter path: the requested search path.
    /// - Returns: the corrective message.
    private static func pathMissingMessage(path: String) -> String {
        "The search path does not exist: \(path)"
    }

    /// A corrective message naming the valid `outputMode` values.
    ///
    /// The valid names are derived from the authoritative ``outputModeMap`` keys,
    /// so the message cannot drift out of step with the modes the engine accepts.
    private static var unknownOutputModeMessage: String {
        EnumParameter.unknownValueMessage(validNames: outputModeMap.keys, parameterName: "outputMode")
    }

    /// A corrective message for an unknown file type, naming the known types.
    ///
    /// The known types are derived from the authoritative ``typeExtensionMap``
    /// keys, so the message cannot drift out of step with the types the engine
    /// accepts. The sentence stays richer than the shared
    /// ``EnumParameter/unknownValueMessage(validNames:parameterName:)`` form
    /// on purpose: it also names the rejected value.
    ///
    /// - Parameter type: the rejected file type.
    /// - Returns: the corrective message.
    private static func unknownTypeMessage(type: String) -> String {
        let names = EnumParameter.nameList(typeExtensionMap.keys)
        return "The `type` parameter is not a known file type: \(type). Known types are: \(names)."
    }
}
