// `Glob` — the `tools.files.glob` verb.
//
// A behavioral port of `../FoundationModelsFileTool/Sources/FileTool/
// Operations/GlobFiles.swift`. The sibling is an `@Operation` that takes a
// `FileContext` through its `execute(in:)`; this package has no operation
// machinery, thus the verb is a plain `FoundationModels.Tool` that holds
// the context it searches, in the pattern of `Capabilities/Shell/
// GetLines.swift`. The sibling's `@OperationParam` aliases (`file_path`,
// `absolute_path`) do not port: plain `@Generable` arguments keep only the
// canonical names.
//
// eventplan.md § "Registration of capabilities: noun/verb": the capability
// supplies the noun, thus this verb's `name` is the bare `glob` and the
// surface path renders as `tools.files.glob`.
//
// A search the engine cannot make stays IN BAND, as a `correction` beside
// an empty match list. It is never thrown: a bad pattern, a broad pattern
// with no `path`, a bad `path`, and a missing directory are each a mistake
// the model corrects inside the turn, and a thrown error would end the
// turn instead.

import FoundationModels

/// The arguments of `tools.files.glob`: the pattern to match, and how to
/// match it.
@Generable
struct GlobArguments {

    /// The glob pattern to match against each file's relative path.
    @Guide(
        description:
            "The glob pattern to match: `*`, `?`, `[...]`, and `**` are supported. A pattern "
            + "with no `/` and no `**` matches file names alone; each other pattern matches the "
            + "path relative to the searched directory.")
    var pattern: String

    /// The directory to search, or `nil` to search the session root.
    @Guide(
        description:
            "The directory to search. Omit it to search the session root. A broad pattern such "
            + "as `*` or `**/*.swift` must give a path.")
    var path: String?

    /// Whether matching is case-sensitive, or `nil` for the default (`false`).
    @Guide(description: "Whether matching is case-sensitive. Omit it for case-insensitive matching.")
    var caseSensitive: Bool?

    /// Whether a present repository's ignore rules are honored, or `nil` for
    /// the default (`true`).
    @Guide(
        description:
            "Whether the ignore rules of a git repository are honored. Omit it to honor them; "
            + "pass false to also match ignored files.")
    var respectGitIgnore: Bool?
}

/// The result of `tools.files.glob`: the matching files, or the correction
/// that says why there are none.
///
/// `correction` and the matches are exclusive. A search that answers matches
/// carries no correction, and a correction carries no file, a `total` of
/// zero, and no cap.
@Generable(
    description: "the matching files, newest first, or the correction that says why there are none.")
struct GlobResult {

    /// The glob pattern this search matched against.
    var pattern: String

    /// The matching paths relative to the session root, most recently
    /// modified first.
    var files: [String]

    /// The total number of matching files found, before the cap.
    var total: Int

    /// Whether `total` went past the result cap, thus `files` is a truncated
    /// prefix carrying the cap's worth of the newest matches.
    var capped: Bool

    /// Why the search answered no file, or `nil` when the matches stand.
    var correction: String?
}

extension Glob {

    /// The case sensitivity the verb uses when `caseSensitive` is absent.
    private static let defaultCaseSensitive = false

    /// The gitignore behavior the verb uses when `respectGitIgnore` is absent.
    private static let defaultRespectGitIgnore = true

    /// Finds the matching files and answers them newest first, or answers
    /// the correction that says why there are none.
    ///
    /// Applies the parameter defaults and delegates to
    /// ``GlobEngine/run(pattern:path:caseSensitive:respectGitIgnore:in:)``,
    /// which performs the validation, the broad-pattern guard, the
    /// search-root bounding through ``PathGuard``, the walk, the matching,
    /// the newest-first order, and the cap. Each recoverable failure comes
    /// back as the `correction` field of the result; nothing here throws
    /// for a bad pattern, a broad pattern, a bad path, or a missing
    /// directory.
    ///
    /// - Parameter arguments: What to match, and how.
    /// - Returns: The matches newest first, or the correction.
    func call(arguments: GlobArguments) async throws -> GlobResult {
        let output = GlobEngine().run(
            pattern: arguments.pattern,
            path: arguments.path,
            caseSensitive: arguments.caseSensitive ?? Self.defaultCaseSensitive,
            respectGitIgnore: arguments.respectGitIgnore ?? Self.defaultRespectGitIgnore,
            in: context
        )
        switch output {
        case .content(let matches):
            return GlobResult(
                pattern: matches.pattern,
                files: matches.files,
                total: matches.total,
                capped: matches.capped,
                correction: nil
            )
        case .corrective(let message):
            return GlobResult(
                pattern: arguments.pattern,
                files: [],
                total: 0,
                capped: false,
                correction: message
            )
        }
    }
}

/// Finds the files whose relative path matches a glob pattern, newest first.
///
/// ```swift
/// // In a snippet the model writes:
/// //   const recent = await tools.files.glob({ pattern: "*.swift", path: "Sources" });
/// ```
///
/// The contract: matches come back as paths relative to the session root,
/// sorted by modification time with the newest first, and capped at the
/// engine's 10,000-file default with an honest `capped` flag. The walk is
/// git-aware — inside a repository the ignore rules hide ignored files
/// unless `respectGitIgnore` is off — and the search root is bounded
/// through the session's ``PathGuard``, thus the search never leaves the
/// workspace and never walks the filesystem root. A bad pattern, a broad
/// pattern with no `path`, a bad `path`, and a missing directory each come
/// back as a `correction` rather than as an error.
///
/// The context it searches is the context the files capability owns, thus
/// each verb of one capability answers for the same session.
struct Glob: Tool {

    /// The verb this tool renders as, which the files noun stands in front
    /// of: `tools.files.glob`.
    let name = "glob"

    /// The usage instructions, as the model reads them.
    let description = """
        glob finds the files whose relative path matches a glob pattern, newest first. `*`, \
        `?`, `[...]`, and `**` are supported, and matching is case-insensitive unless \
        caseSensitive is true. Matches are relative to the session root, capped at 10,000 with \
        an honest capped flag, and inside a git repository the ignore rules apply unless \
        respectGitIgnore is false. A broad pattern such as `*` or `**/*.swift` must give a \
        path. A bad pattern, a broad pattern with no path, a bad path, and a missing directory \
        each come back as a correction rather than as an error — read it, correct the call, \
        and ask again.
        """

    /// The session context this verb searches, which the files capability owns.
    let context: FileContext

    /// Makes the verb over one session context.
    ///
    /// - Parameter context: The per-session state of the file verbs.
    init(context: FileContext) {
        self.context = context
    }
}
