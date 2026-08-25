// `Grep` — the `tools.files.grep` verb.
//
// A behavioral port of `../FoundationModelsFileTool/Sources/FileTool/
// Operations/GrepFiles.swift`. The sibling is an `@Operation` that takes a
// `FileContext` through its `execute(in:)`; this package has no operation
// machinery, thus the verb is a plain `FoundationModels.Tool` that holds
// the context it searches, in the pattern of `Capabilities/Files/
// Glob.swift`. The sibling's `@OperationParam` aliases (`file_path`,
// `absolute_path`) do not port: plain `@Generable` arguments keep only the
// canonical names. The sibling's `GrepOutput` enum does not port to the
// surface either: the flat result carries a `correction` field in its
// place, and the engine's per-line `GrepMatch` maps onto the `@Generable`
// `GrepLine` here.
//
// eventplan.md § "Registration of capabilities: noun/verb": the capability
// supplies the noun, thus this verb's `name` is the bare `grep` and the
// surface path renders as `tools.files.grep`.
//
// A search the engine cannot make stays IN BAND, as a `correction` beside
// zero counts. It is never thrown: a bad regular expression, a bad `glob`
// filter, an unknown `type`, an unknown `outputMode`, and a missing path
// are each a mistake the model corrects inside the turn, and a thrown
// error would end the turn instead.

import FoundationModels

/// The arguments of `tools.files.grep`: the pattern to search for, where to
/// search, and how to shape the answer.
@Generable
struct GrepArguments {

    /// The regular-expression pattern to match against each line.
    @Guide(
        description:
            "The regular expression to match against each line of the searched files, in Swift "
            + "Regex syntax.")
    var pattern: String

    /// The file or directory to search, or `nil` to search the session root.
    @Guide(
        description:
            "The file or directory to search. Omit it to search the session root. A single file "
            + "is searched directly; a directory is walked.")
    var path: String?

    /// A filename filter applied to a directory walk, or `nil` for no filter.
    @Guide(
        description:
            "A filename filter applied to a directory walk, such as `*.swift`. Omit it to "
            + "search every file.")
    var glob: String?

    /// A file-type filter naming a known type, or `nil` for no filter.
    @Guide(
        description:
            "A file-type filter naming a known type, such as `swift`, `py`, or `md`. Omit it to "
            + "search every file. An unknown type comes back as a correction that lists the "
            + "known types.")
    var type: String?

    /// Whether matching ignores case, or `nil` for the default (`false`).
    @Guide(description: "Whether matching ignores case. Omit it for case-sensitive matching.")
    var caseInsensitive: Bool?

    /// The number of context lines on each side of a match, or `nil` for the
    /// default (two).
    @Guide(
        description:
            "The number of context lines on each side of a match. Omit it for the default of "
            + "two; 0 returns match lines only.")
    var contextLines: Int?

    /// The output mode (`content`, `filesWithMatches`, or `count`), or `nil`
    /// for the default (`content`).
    @Guide(
        description:
            "The output mode: `content` (the default) carries the matched and context lines, "
            + "`filesWithMatches` carries only the matching files, and `count` carries only the "
            + "totals.")
    var outputMode: String?
}

/// One line of `tools.files.grep`'s `content` mode: matched, or carried as
/// context.
@Generable(description: "one matched or context line of the searched files.")
struct GrepLine {

    /// The matching file's path relative to the session root.
    var file: String

    /// The 1-based physical line number of this line within its file.
    var line: Int

    /// The line's text, with its terminator excluded.
    var text: String

    /// Whether this line matched the pattern, rather than being context.
    var isMatch: Bool
}

/// The result of `tools.files.grep`: the mode-shaped matches, or the
/// correction that says why there are none.
///
/// `correction` and the matches are exclusive. A search that answers carries
/// no correction, and a correction carries no line, no file, and zero
/// counts. The output mode decides which optional fields a successful
/// search carries: `content` carries `matches`, `filesWithMatches` carries
/// `files`, and `count` carries neither.
@Generable(
    description: "the mode-shaped grep matches, or the correction that says why there are none.")
struct GrepResult {

    /// The matched and context lines, present only in the `content` mode.
    var matches: [GrepLine]?

    /// The relative paths of the files with at least one match, present only
    /// in the `filesWithMatches` mode.
    var files: [String]?

    /// The total number of matched lines across all files; context lines
    /// never count.
    var matchCount: Int

    /// The number of files with at least one matched line.
    var fileCount: Int

    /// The wall-clock duration of the search, in milliseconds.
    var elapsedMs: Double

    /// Why the search answered no result, or `nil` when the result stands.
    var correction: String?
}

extension Grep {

    /// The case-insensitivity the verb uses when `caseInsensitive` is absent.
    private static let defaultCaseInsensitive = false

    /// Searches file contents and answers the mode-shaped matches, or the
    /// correction that says why there are none.
    ///
    /// Applies the case-insensitivity default and delegates to
    /// ``GrepEngine/run(pattern:path:glob:type:caseSensitive:contextLines:outputMode:in:)``,
    /// which performs the validation, the target resolution, the git-aware
    /// walk, the binary skip, the line matching, the context assembly, and
    /// the output-mode shaping. The engine owns the `contextLines` and
    /// `outputMode` defaults, so both pass through unchanged. Each
    /// recoverable failure comes back as the `correction` field of the
    /// result; nothing here throws for a bad pattern, filter, mode, or path.
    ///
    /// This is the one place the wire spelling and the engine spelling meet.
    /// The verb's parameter is `caseInsensitive` — the upstream Rust `files`
    /// tool's name, which the surface keeps — while the engine takes
    /// `caseSensitive` so it reads the same way as ``GlobEngine``. The
    /// inversion happens here and nowhere else.
    ///
    /// - Parameter arguments: What to search for, where, and how to shape
    ///   the answer.
    /// - Returns: The mode-shaped matches, or the correction.
    func call(arguments: GrepArguments) async throws -> GrepResult {
        let output = GrepEngine().run(
            pattern: arguments.pattern,
            path: arguments.path,
            glob: arguments.glob,
            type: arguments.type,
            caseSensitive: !(arguments.caseInsensitive ?? Self.defaultCaseInsensitive),
            contextLines: arguments.contextLines,
            outputMode: arguments.outputMode,
            in: context
        )
        switch output {
        case .content(let matches):
            return GrepResult(
                matches: matches.matches.map { lines in
                    lines.map {
                        GrepLine(file: $0.file, line: $0.line, text: $0.text, isMatch: $0.isMatch)
                    }
                },
                files: matches.files,
                matchCount: matches.matchCount,
                fileCount: matches.fileCount,
                elapsedMs: matches.elapsedMilliseconds,
                correction: nil
            )
        case .corrective(let message):
            return Self.corrected(message)
        }
    }

    /// The empty answer one correction stands in place of: no line, no file,
    /// zero counts.
    ///
    /// - Parameter message: Why the search answered no result.
    /// - Returns: The corrective result.
    private static func corrected(_ message: String) -> GrepResult {
        GrepResult(
            matches: nil, files: nil, matchCount: 0, fileCount: 0, elapsedMs: 0, correction: message)
    }
}

/// Searches file contents for a regular expression, git-aware and shaped by
/// output mode.
///
/// ```swift
/// // In a snippet the model writes:
/// //   const hits = await tools.files.grep({ pattern: "TODO", path: "Sources", type: "swift" });
/// ```
///
/// The contract: the search target resolves through the session's
/// ``PathGuard`` — a single file short-circuits the walk, and a directory is
/// enumerated through the git-aware ``FileWalker``, thus a gitignored
/// directory such as `build/` is never descended into. A file whose first
/// bytes hold a NUL is binary and is skipped. Each line is matched with
/// Swift `Regex`, case-sensitively unless `caseInsensitive` is true.
/// `contextLines` puts that many lines on each side of a match (default
/// two; overlapping windows merge into one hunk), and only matched lines
/// count toward `matchCount`. The `content` mode (the default) carries the
/// matched and context lines; `filesWithMatches` carries only the matching
/// files; `count` carries only the totals. A bad regular expression, a bad
/// `glob` filter, an unknown `type`, an unknown `outputMode`, and a missing
/// path each come back as a `correction` rather than as an error.
///
/// The context it searches is the context the files capability owns, thus
/// each verb of one capability answers for the same session.
struct Grep: Tool {

    /// The verb this tool renders as, which the files noun stands in front
    /// of: `tools.files.grep`.
    let name = "grep"

    /// The usage instructions, as the model reads them.
    let description = """
        grep searches file contents for a regular expression, line by line. A path that names a \
        file searches that file; a path that names a directory walks it git-aware, thus \
        gitignored directories are never searched, and binary files are skipped. glob filters \
        the walked files by name and type filters them by a known file type. Matching is \
        case-sensitive unless caseInsensitive is true. contextLines puts that many lines around \
        each match (default two), and only matched lines count toward matchCount. outputMode \
        content (the default) answers the lines, filesWithMatches answers only the files, and \
        count answers only the totals. A bad pattern, a bad glob, an unknown type, an unknown \
        outputMode, and a missing path each come back as a correction rather than as an error — \
        read it, correct the call, and ask again.
        """

    /// The session context this verb searches, which the files capability owns.
    ///
    /// The compiler-synthesized memberwise initializer takes this one
    /// property, thus the capability makes the verb as `Grep(context:)`.
    let context: FileContext
}
