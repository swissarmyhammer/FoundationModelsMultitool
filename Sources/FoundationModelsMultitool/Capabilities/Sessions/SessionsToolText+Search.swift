// The correctives of the parse of a session search query (D207 (e)).
//
// Each corrective names the token as the query wrote it, and tells the form
// that the token takes.

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
}
