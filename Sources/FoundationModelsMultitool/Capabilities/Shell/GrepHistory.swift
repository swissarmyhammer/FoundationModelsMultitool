// `GrepHistory` — the `tools.shell.grepHistory` verb.
//
// A behavioral port of `../FoundationModelsShelltool/Sources/ShellTool/
// Operations/GrepHistory.swift`. The sibling is an `@Operation` that takes a
// `ShellContext`; this package has neither, thus the verb is a plain
// `FoundationModels.Tool` that holds the store it searches.
//
// eventplan.md § "Consolidation of the siblings" keeps this verb beside
// `tools.shell.getLines` on the CONTENT plane: it reads the captured output
// that stays in the per-session dotfolder, for a run that is still going and
// for a run that ended alike. It answers no question about the life of a run,
// which the shared background engine owns.
//
// The scan itself is `ShellState.grep`, which owns the compilation of the
// pattern, the optional escape for a literal match, the filter by run, and the
// cap. This file holds the shape of the answer and nothing else, thus the two
// readers of the log cannot drift apart.
//
// The `total`/`shown` split is the point of the verb: `limit` caps how many
// matches come back, and `total` always reports every match, thus the model
// knows to raise `limit` when it was cut short.
//
// A search the store cannot make stays IN BAND, as a `correction` beside no
// match. It is never thrown: a pattern that does not compile, and a token no
// command ran under, are each a mistake the model corrects inside the turn, and
// a thrown error would end the turn instead.

import FoundationModels

/// The arguments of `tools.shell.grepHistory`: what to search for, and how far.
@Generable
struct GrepHistoryArguments {

    /// The regular expression, or the exact text when `literal` is `true`.
    @Guide(
        description:
            "The regular expression to match against the captured output. With literal true it is "
            + "matched as exact text instead, thus no escaping is needed.")
    var pattern: String

    /// `true` to match `pattern` as exact text, or `nil` for a regular
    /// expression.
    @Guide(
        description:
            "Match the pattern as exact text instead of as a regular expression. Omit it for a "
            + "regular expression.")
    var literal: Bool?

    /// The completion token to search inside, or `nil` for each run of this
    /// session.
    @Guide(
        description:
            "The completion token of one run to search inside. Omit it to search every run of "
            + "this session.")
    var commandID: String?

    /// The cap on the matches that come back, or `nil` for the cap of the
    /// store.
    @Guide(description: "The most matches to answer with. Omit it for the default cap.")
    var limit: Int?
}

/// One matching line of `tools.shell.grepHistory`.
@Generable(description: "one matching line of the captured output.")
struct GrepHistoryMatch {

    /// The completion token of the run this line belongs to.
    var commandID: String

    /// The line number inside that run, counted from 1.
    var lineNumber: Int

    /// The text of the matching line, with its trailing whitespace dropped.
    var text: String
}

/// The result of `tools.shell.grepHistory`: the matches the search found, or
/// the correction that says why it found none.
///
/// `correction` and the matches are exclusive. A search that answers matches
/// carries no correction, and a correction carries no match and no count.
@Generable(
    description: "the matching lines of the captured output, or the correction that says why "
        + "there are none.")
struct GrepHistoryResult {

    /// The matching lines, capped at the limit the caller gave.
    var matches: [GrepHistoryMatch]

    /// How many matches `matches` carries.
    var shown: Int

    /// How many matches the scan found, which the limit does not change. A
    /// `total` over `shown` says the answer was cut short, thus a higher
    /// `limit` shows more.
    var total: Int

    /// Why the search found no match, or `nil` when the search was made.
    var correction: String?
}

extension GrepHistory {

    /// The count each corrective answer carries, because it found no match.
    private static let noMatchCount = 0

    /// Searches the captured output of this session.
    ///
    /// The token is examined before the scan. `ShellState.grep` reads a token
    /// that names no run as a filter that keeps nothing, thus a mistyped token
    /// would answer "no match" and say nothing about the mistake.
    ///
    /// - Parameter arguments: What to search for, and how far.
    /// - Returns: The matches the search found, or the correction that says why
    ///   it found none.
    /// - Throws: What `ShellState.grep` throws for a log file that does not
    ///   read. A pattern that does not compile does not reach the caller.
    func call(arguments: GrepHistoryArguments) async throws -> GrepHistoryResult {
        if let commandID = arguments.commandID,
            await state.record(commandID: commandID) == nil
        {
            return Self.corrected(Self.unknownTokenCorrection(commandID))
        }

        do {
            let found = try await state.grep(
                pattern: arguments.pattern,
                literal: arguments.literal ?? false,
                commandID: arguments.commandID,
                limit: arguments.limit
            )
            let matches = found.results.map {
                GrepHistoryMatch(commandID: $0.commandID, lineNumber: $0.lineNumber, text: $0.text)
            }
            return GrepHistoryResult(
                matches: matches, shown: matches.count, total: found.total, correction: nil)
        } catch ShellStateError.invalidRegex(let pattern, let underlyingMessage) {
            // The pattern is the model's own text, thus it can rephrase it
            // inside the turn. The correction carries the message of the
            // compiler exactly as `ShellState` took it.
            return Self.corrected(
                ShellStateError.invalidRegex(pattern: pattern, underlyingMessage: underlyingMessage)
                    .description)
        }
    }

    /// What a token no command of this session ran under says to the model.
    ///
    /// - Parameter commandID: The token the search named.
    /// - Returns: The correction.
    private static func unknownTokenCorrection(_ commandID: String) -> String {
        "No command of this session ran under the completion token \(commandID). Omit commandID "
            + "to search every run of this session."
    }

    /// The empty answer one correction stands in place of.
    ///
    /// - Parameter message: Why the search found no match.
    /// - Returns: The corrective result.
    private static func corrected(_ message: String) -> GrepHistoryResult {
        GrepHistoryResult(
            matches: [], shown: noMatchCount, total: noMatchCount, correction: message)
    }
}

/// Searches the captured output of this session's shell runs.
///
/// ```swift
/// // In a snippet the model writes:
/// //   const hits = await tools.shell.grepHistory({ pattern: "error", limit: 20 });
/// ```
///
/// The store it searches is the store the capability owns, thus each verb of
/// one capability answers for the same session.
struct GrepHistory: Tool {

    /// The verb this tool renders as, which the shell noun stands in front of:
    /// `tools.shell.grepHistory`.
    let name = "grepHistory"

    /// The usage instructions, as the model reads them.
    let description = """
        grepHistory searches the captured output of this session's shell runs, line by line, with \
        a regular expression — or with exact text when literal is true. Give commandID to search \
        inside one run, and omit it to search every run. shown is how many matches came back and \
        total is how many there are, thus a total over shown means a higher limit shows more. A \
        pattern that does not compile, and a token no run of this session ran under, each come \
        back as a correction rather than as an error — read it, correct the call, and ask again.
        """

    /// The store this verb searches, which the shell capability owns.
    let state: ShellState

    /// Makes the verb over one store.
    ///
    /// - Parameter state: The history and output store of the shell capability.
    init(state: ShellState) {
        self.state = state
    }
}
