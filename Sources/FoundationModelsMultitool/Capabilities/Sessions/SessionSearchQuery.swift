// `SessionSearchQuery` — the parsed query of a session search (D207 (e)).
//
// The `search sessions` operation of the `sessions` tool and the
// `searchSessions` field of the `sessions` endpoint parse the query with one
// rule, here. This package only parses: the directory resolves the session
// tokens, and the searcher of the host applies the phrases, the exclusions
// and the other tokens to its matches.

import Foundation

/// The parsed query of a session search.
///
/// The syntax, one term after the other, with space between the terms:
///
/// - `word`: a plain word. It goes into ``words`` and ``rankingText``.
/// - `"two words"`: a phrase. The text of a hit must have it. A quote with no
///   closing quote makes a phrase to the end of the query.
/// - `-word` and `-"two words"`: an exclusion. A hit whose text has it is
///   removed. A lone `-` is ignored.
/// - `from:<kind>`: keeps the chunks of one kind: `user`, `agent`, `message`,
///   `tool`, `plan` or `thought`. Two `from:` tokens keep the two kinds. With
///   no `from:` token, the kinds are each kind but `thought` (Q64).
/// - `after:<date>` and `before:<date>`: keep the chunks on or after the first
///   instant of the day, and before the first instant of the day. The only
///   date form is ISO 8601 `YYYY-MM-DD`, for example `2026-11-19`. The day
///   starts at midnight in the time zone of the parse. Of two `after:` tokens
///   the later day is kept, and of two `before:` tokens the earlier day.
/// - `@<session>`: one session, through the resolver of the directory.
/// - `#<tag>`: the sessions with the tag.
/// - `agent:<name>`: the sessions of one agent.
/// - `folder:<path>`: the sessions of one folder. `folder:.` is the folder of
///   the tab or of the caller session.
/// - `is:archived`: includes the archived sessions.
///
/// The keys are in any letter case, and so are the values of `from:` and
/// `is:`. A `key:` token with a key that is not in this list is a plain word.
/// A token in quotes is a phrase, not a token. A query with tokens and no
/// words is valid: its ``rankingText`` is empty, and the searcher lists the
/// hits by date, newest first.
public struct SessionSearchQuery: Sendable, Equatable, Codable {
    /// The kind of a chunk that a `from:` token names.
    public typealias Kind = SessionSearchHit.Kind

    /// The kinds of a query with no `from:` token: each kind but `thought`
    /// (Q64).
    public static let defaultKinds = Set(Kind.allCases).subtracting([.thought])

    /// The plain words, in the order of the query.
    public var words: [String]

    /// The phrases, with no quotes. The text of a hit must have each one.
    public var phrases: [String]

    /// The excluded words and phrases, with no `-` and no quotes.
    public var excluded: [String]

    /// The kinds of chunk that the `from:` tokens keep, or ``defaultKinds``.
    public var kinds: Set<Kind>

    /// The first instant of the day of the `after:` token, or `nil`.
    public var after: Date?

    /// The first instant of the day of the `before:` token, or `nil`.
    public var before: Date?

    /// The words of the query and of its phrases, in the order of the query,
    /// with no tokens, no quotes and no exclusions. It is the intent that the
    /// `MetadataSearcher` gets. It is empty for a query with only tokens.
    public var rankingText: String

    /// The texts after `@` of the `@<session>` tokens, for the resolver of
    /// the directory (D199 (d)).
    public var sessionReferences: [String]

    /// The tags of the `#<tag>` tokens, with no `#`.
    public var tags: [String]

    /// The names of the `agent:` tokens.
    public var agents: [String]

    /// The paths of the `folder:` tokens, as written. `.` is the folder of
    /// the tab or of the caller session.
    public var folders: [String]

    /// True when the query has the `is:archived` token.
    public var includesArchived: Bool

    /// Makes a query from its parts.
    ///
    /// - Parameters:
    ///   - words: The plain words.
    ///   - phrases: The phrases, with no quotes.
    ///   - excluded: The excluded words and phrases.
    ///   - kinds: The kinds of chunk to keep.
    ///   - after: The first instant to keep, or `nil`.
    ///   - before: The instant before which to keep, or `nil`.
    ///   - rankingText: The intent for the searcher.
    ///   - sessionReferences: The texts of the `@<session>` tokens.
    ///   - tags: The tags of the `#<tag>` tokens.
    ///   - agents: The names of the `agent:` tokens.
    ///   - folders: The paths of the `folder:` tokens.
    ///   - includesArchived: True to include the archived sessions.
    public init(
        words: [String] = [],
        phrases: [String] = [],
        excluded: [String] = [],
        kinds: Set<Kind> = SessionSearchQuery.defaultKinds,
        after: Date? = nil,
        before: Date? = nil,
        rankingText: String = "",
        sessionReferences: [String] = [],
        tags: [String] = [],
        agents: [String] = [],
        folders: [String] = [],
        includesArchived: Bool = false
    ) {
        self.words = words
        self.phrases = phrases
        self.excluded = excluded
        self.kinds = kinds
        self.after = after
        self.before = before
        self.rankingText = rankingText
        self.sessionReferences = sessionReferences
        self.tags = tags
        self.agents = agents
        self.folders = folders
        self.includesArchived = includesArchived
    }

    /// Parses the text of a query.
    ///
    /// - Parameters:
    ///   - text: The query, in the syntax of ``SessionSearchQuery``.
    ///   - timeZone: The time zone in which a day of `after:` and `before:`
    ///     starts. The default is the time zone of the server.
    /// - Throws: A refusal with the code `BLANK_TEXT` when the query has no
    ///   term, and with the code `INVALID_QUERY` when a token has a wrong
    ///   value. The corrective text names the token.
    public init(parsing text: String, timeZone: TimeZone = .current) throws {
        self = try SessionSearchQueryParser.query(of: text, timeZone: timeZone)
    }
}
