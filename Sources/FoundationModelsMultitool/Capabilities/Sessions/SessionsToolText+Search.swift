// The text of the `search sessions` operation of the `sessions` tool: its
// answer (D207 (g)), its correctives, and the correctives of the parse of a
// session search query (D207 (e)).
//
// Each corrective of the parse names the token as the query wrote it, and
// tells the form that the token takes.

import Foundation

extension SessionsToolText {
    /// The name of the `query` argument of a session search.
    static let queryParameter = "query"

    /// The example day of the date correctives.
    private static let exampleDay = "2026-11-19"

    /// The corrective of an `after:` or `before:` token whose value is not a
    /// day in the form `YYYY-MM-DD`.
    ///
    /// - Parameter token: The token, as written.
    /// - Returns: The corrective, which names the token and the date form.
    static func wrongSearchDate(_ token: String) -> String {
        """
        The token "\(token)" has no valid date. Give the date as YYYY-MM-DD, for example after:\(exampleDay) or \
        before:\(exampleDay).
        """
    }

    /// The corrective of a `from:` token whose value names no kind.
    ///
    /// - Parameter token: The token, as written.
    /// - Returns: The corrective, which names the token and each kind.
    static func unknownSearchKind(_ token: String) -> String {
        let forms = SessionSearchQueryParser.fromKinds.map { "from:\($0.rawValue)" }.joined(separator: ", ")
        return "The token \"\(token)\" names no kind of entry. Give one of \(forms)."
    }

    /// The corrective of an `is:` token whose value is not `archived`.
    ///
    /// - Parameter token: The token, as written.
    /// - Returns: The corrective, which names the token and `is:archived`.
    static func unknownSearchState(_ token: String) -> String {
        """
        The token "\(token)" names no state. Give is:\(SessionSearchQueryParser.archivedValue) to include the \
        archived sessions, or remove the token.
        """
    }

    /// The corrective of a `key:` token with no value.
    ///
    /// - Parameter token: The token, as written.
    /// - Returns: The corrective, which names the token.
    static func searchTokenWithNoValue(_ token: String) -> String {
        "The token \"\(token)\" has no value. Give a value after the colon, or remove the token."
    }

    // MARK: - search sessions

    /// The name of the UI command that searches the sessions, which each
    /// corrective of a server that cannot search names.
    static let searchUICommand = "Search (⌘F)"

    /// The most hits that the answer gives for one session.
    static let maximumShownHits = 3

    /// The last line of each answer: the limit of the search (D207 (d)).
    static let searchLimitSentence = """
        The search covers the transcripts of the sessions that this server records. For the sessions of other \
        agents such as Claude Code or Codex, it covers only the title, the first and last prompts, the folder and \
        the branch.
        """

    /// The line after the sessions of other agents in an answer.
    static let externalSearchAdvice = """
        To read a session of another agent, use \(ReadExternalSession.opString) with its source and its id.
        """

    /// The sentence of a corrective that tells that the search did not run.
    static let searchNotRunSentence = "The search did not run."

    /// The sentence that tells the user how to search the sessions in the
    /// UI.
    private static let searchInUISentence =
        "The user can search the sessions with the command \(searchUICommand) of the Edit menu."

    /// The corrective of `search sessions` on a server whose host gives no
    /// searcher.
    static let noSearcher = """
        This server cannot search the sessions: its host gives no transcript searcher. \(searchInUISentence)
        """

    /// The corrective of the folder `.` in a call with no caller session.
    ///
    /// - Parameter outcome: The sentence that tells what the call did not do.
    /// - Returns: The corrective.
    static func noCallerFolder(_ outcome: String) -> String {
        """
        The folder . is the folder of your session, and this call runs in no session. \(outcome) Give the absolute \
        path of a folder.
        """
    }

    /// The corrective of a searcher that could not search.
    ///
    /// - Parameter error: The error of the searcher.
    /// - Returns: The corrective, which names the UI command.
    static func searchFailed(_ error: any Error) -> String {
        "The search of the sessions failed: \(error). Try the call again. \(searchInUISentence)"
    }

    /// The answer of `search sessions`: one line for each session, each with
    /// at most ``maximumShownHits`` hits, then one line for each session of
    /// another agent and ``externalSearchAdvice``, then
    /// ``searchLimitSentence``. With no session of either kind, the line that
    /// no session matches the query.
    ///
    /// - Parameters:
    ///   - matches: The sessions of the page, in the order of the search.
    ///   - externalSessions: The sessions of other agents that match, the
    ///     best first.
    ///   - query: The query, as written.
    ///   - timeZone: The time zone of the day of each line.
    /// - Returns: The answer.
    static func searchAnswer(
        _ matches: [SessionSearchMatch], externalSessions: [ExternalSessionSearchResult], query: String,
        timeZone: TimeZone
    ) -> String {
        let sessionLines = matches.flatMap { searchLines(of: $0, timeZone: timeZone) }
        let externalLines =
            externalSessions.isEmpty
            ? [] : externalSessions.map { externalSessionLine($0.session) } + [externalSearchAdvice]
        let lines =
            sessionLines.isEmpty && externalLines.isEmpty ? [noSearchMatch(query)] : sessionLines + externalLines
        return (lines + [searchLimitSentence]).joined(separator: "\n")
    }

    /// The line that no session matches a query.
    ///
    /// - Parameter query: The query, as written.
    /// - Returns: The line.
    private static func noSearchMatch(_ query: String) -> String {
        "No session matches the query \"\(query.trimmingCharacters(in: .whitespacesAndNewlines))\"."
    }

    /// The lines of one session: `@<short id> <name> (<folder>) <date> – <n>
    /// hits`, then one line for each of its first hits.
    ///
    /// The date is the day of the best hit, or the day of the last change of
    /// the session when the best hit has no date.
    ///
    /// - Parameters:
    ///   - match: The session.
    ///   - timeZone: The time zone of the day.
    /// - Returns: The lines.
    private static func searchLines(of match: SessionSearchMatch, timeZone: TimeZone) -> [String] {
        let summary = match.summary
        let date = match.result.hits.first?.date ?? summary.updatedAt
        let day = Date.ISO8601FormatStyle(timeZone: timeZone).year().month().day().format(date)
        let heading = """
            @\(summary.shortID) \(name(of: summary)) (\(summary.workingDirectory.path)) \(day) – \
            \(match.result.hitCount) hits
            """
        return [heading] + match.result.hits.prefix(maximumShownHits).map(hitLine)
    }

    /// The line of one hit: `  <author>: <snippet>`, with the snippet on one
    /// line. A hit with no author gives the kind of its entry.
    ///
    /// - Parameter hit: The hit.
    /// - Returns: The line.
    private static func hitLine(_ hit: SessionSearchHit) -> String {
        let snippet = hit.snippet.split(whereSeparator: \.isNewline).joined(separator: " ")
        return "  \(hit.author ?? hit.kind.rawValue): \(snippet)"
    }
}
