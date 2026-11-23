// `SessionTranscriptSearcher` — the full-text and semantic search of the
// session transcripts, which the host gives (D207 (b), (c), (g)).
//
// This package does not link FoundationModelsACP or the index of the
// transcripts. The chunks, the index and the `MetadataSearcher` of the
// transcripts are in FoundationModelsACPAgent. Thus the host gives the search
// through this protocol, and the `search sessions` operation of the
// `sessions` tool and the `searchSessions` field of the `sessions` endpoint
// call it. This package parses the query (``SessionSearchQuery``), so that
// the tool and the endpoint have one rule.
//
// The searcher also finds the sessions of other agents, such as Claude Code
// or Codex, in the index of the host (D212, design section 5.2). It matches
// only the index fields of these sessions, not the text of their turns, and
// it gives them in ``SessionSearchPage/externalSessions``, apart from the
// sessions of this server, because they have no ULID.

import Foundation
import FoundationModelsExtras
import ULID

/// Searches the transcripts of the sessions that this server records.
///
/// A host gives one to ``SessionsTool/init(directory:exporter:searcher:sharer:externalSessionHost:)``
/// and to ``SessionsGraph/endpoint(of:exporter:searcher:sharer:externalSessionHost:)``. With no searcher, the
/// `search sessions` operation gives a corrective that names the UI command
/// Search (⌘F).
///
/// The searcher gives the intent of the query (``SessionSearchQuery/rankingText``)
/// to its `MetadataSearcher`, and then applies the phrases, the exclusions and
/// the tokens of the query to the matches, in their order (D207 (c), (e)). A
/// query with no ranking text lists the hits that pass the filters, newest
/// first.
public protocol SessionTranscriptSearcher: Sendable {
    /// One page of the sessions that match a query.
    ///
    /// - Parameter request: The query, the session filter of the directory,
    ///   and the page.
    /// - Returns: The page of sessions, each one with its hits.
    /// - Throws: An error when the searcher cannot search.
    func search(_ request: SessionSearchRequest) async throws -> SessionSearchPage
}

/// One search of the session transcripts.
public struct SessionSearchRequest: Sendable, Equatable, Codable {
    /// The parsed query.
    public var query: SessionSearchQuery

    /// The sessions that the directory keeps for the `@<session>`, `#tag`,
    /// `agent:` and `folder:` tokens of the query. `nil` is each session that
    /// the caller can see.
    public var sessions: Set<ULID>?

    /// True to include the archived sessions (`is:archived`, or the
    /// `archived` argument), D204 (e).
    public var includeArchived: Bool

    /// The folder of the tab or of the caller session. Its sessions come
    /// first in the page, D207 (d).
    public var preferredFolder: URL?

    /// The one session whose hits the search gives, for Find Next Hit. `nil`
    /// searches each session of ``sessions``.
    public var session: ULID?

    /// The most sessions that one page gives. With ``session``, the most hits.
    public var limit: Int

    /// The cursor of the page, as the last page gave it in
    /// ``SessionSearchPage/nextCursor``. `nil` is the first page.
    public var cursor: String?

    /// Makes a request.
    ///
    /// - Parameters:
    ///   - query: The parsed query.
    ///   - sessions: The sessions that the directory keeps, or `nil` for each
    ///     visible session.
    ///   - includeArchived: True to include the archived sessions.
    ///   - preferredFolder: The folder whose sessions come first.
    ///   - session: The one session whose hits the search gives, or `nil`.
    ///   - limit: The most sessions of the page.
    ///   - cursor: The cursor of the page, or `nil` for the first page.
    public init(
        query: SessionSearchQuery,
        sessions: Set<ULID>?,
        includeArchived: Bool,
        preferredFolder: URL?,
        session: ULID?,
        limit: Int,
        cursor: String?
    ) {
        self.query = query
        self.sessions = sessions
        self.includeArchived = includeArchived
        self.preferredFolder = preferredFolder
        self.session = session
        self.limit = limit
        self.cursor = cursor
    }
}

/// One page of the sessions that match a search.
public struct SessionSearchPage: Sendable, Equatable, Codable {
    /// The sessions that match, in the order of the search: first the
    /// sessions of the preferred folder, then the others.
    public var sessions: [SessionSearchResult]

    /// The cursor of the next page, or `nil` when this page is the last one.
    public var nextCursor: String?

    /// The folders of matched sessions that the server cannot read now
    /// (D207 (b) (7)). Their results show the note "Folder not available".
    public var unavailableFolders: [URL]

    /// The sessions of other agents whose index fields match, the best score
    /// first (D212, design section 5.2).
    ///
    /// Only the first page of a search gives them, at most
    /// ``ExternalSessionSearchResult/maximumCount``. A page that a cursor
    /// names gives none. A search with a session filter
    /// (``SessionSearchRequest/sessions`` or ``SessionSearchRequest/session``)
    /// gives none, because the filter names sessions of this server: the
    /// `@<session>`, `#tag`, `agent:` and `folder:` tokens make a filter.
    public var externalSessions: [ExternalSessionSearchResult]

    /// Makes a page.
    ///
    /// - Parameters:
    ///   - sessions: The sessions that match.
    ///   - nextCursor: The cursor of the next page, or `nil`.
    ///   - unavailableFolders: The folders that the server cannot read now.
    ///   - externalSessions: The sessions of other agents that match. The
    ///     default is none.
    public init(
        sessions: [SessionSearchResult],
        nextCursor: String?,
        unavailableFolders: [URL],
        externalSessions: [ExternalSessionSearchResult] = []
    ) {
        self.sessions = sessions
        self.nextCursor = nextCursor
        self.unavailableFolders = unavailableFolders
        self.externalSessions = externalSessions
    }

    /// The keys of the coded page.
    private enum CodingKeys: String, CodingKey {
        case sessions
        case nextCursor
        case unavailableFolders
        case externalSessions
    }

    /// Decodes a page. A page with no `externalSessions` key, as an older
    /// server writes it, has no external session.
    ///
    /// - Parameter decoder: The decoder.
    /// - Throws: Each error of the decoder.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessions = try container.decode([SessionSearchResult].self, forKey: .sessions)
        nextCursor = try container.decodeIfPresent(String.self, forKey: .nextCursor)
        unavailableFolders = try container.decode([URL].self, forKey: .unavailableFolders)
        externalSessions =
            try container.decodeIfPresent([ExternalSessionSearchResult].self, forKey: .externalSessions) ?? []
    }
}

/// One session of another agent whose index fields match a search (D212,
/// design section 5.2).
///
/// The searcher matches only the index fields of the session: the title, the
/// first prompt, the last prompt, the folder and the branch. It does not
/// search the text of the turns. To read the session, a client uses
/// `read external session` or `externalSessionUpdates`.
public struct ExternalSessionSearchResult: Sendable, Equatable, Codable {
    /// The most external sessions that one search gives.
    public static let maximumCount = 20

    /// The index field of the title.
    public static let titleField = "title"

    /// The index field of the first prompt.
    public static let firstPromptField = "firstPrompt"

    /// The index field of the last prompt.
    public static let lastPromptField = "lastPrompt"

    /// The index field of the folder.
    public static let folderField = "cwd"

    /// The index field of the git branch.
    public static let branchField = "gitBranch"

    /// The session, as the index of the host gives it.
    public var session: ExternalSessionSummary

    /// The score in `[0, 1]` of the match in the `MetadataSearcher`, on the
    /// same scale as ``SessionSearchResult/score``.
    public var score: Double

    /// The index field of the best match: ``titleField``,
    /// ``firstPromptField``, ``lastPromptField``, ``folderField`` or
    /// ``branchField``. `nil` for a match with only the cosine signal.
    public var field: String?

    /// Makes a result.
    ///
    /// - Parameters:
    ///   - session: The session, as the index gives it.
    ///   - score: The score in `[0, 1]` of the match.
    ///   - field: The index field of the best match, or `nil`.
    public init(session: ExternalSessionSummary, score: Double, field: String?) {
        self.session = session
        self.score = score
        self.field = field
    }
}

/// One session that matches a search, with its hits.
public struct SessionSearchResult: Sendable, Equatable, Codable {
    /// The id of the session.
    public var session: ULID

    /// The score in `[0, 1]` of the first match of the session in the
    /// `MetadataSearcher` (D207 (c) (2)). A client fuses the results of the
    /// server and of its local index with it (D207 (d)).
    public var score: Double

    /// The number of hits of the session. It can be larger than the number
    /// of ``hits``.
    public var hitCount: Int

    /// The hits of the session, the best hit first.
    public var hits: [SessionSearchHit]

    /// Makes a result.
    ///
    /// - Parameters:
    ///   - session: The id of the session.
    ///   - score: The score in `[0, 1]` of the first match of the session.
    ///   - hitCount: The number of hits of the session.
    ///   - hits: The hits of the session, the best hit first.
    public init(session: ULID, score: Double, hitCount: Int, hits: [SessionSearchHit]) {
        self.session = session
        self.score = score
        self.hitCount = hitCount
        self.hits = hits
    }
}

/// One hit in the transcript of a session: one matched chunk, or the session
/// item of the session.
public struct SessionSearchHit: Sendable, Equatable, Codable {
    /// The kind of a chunk of a transcript (D207 (a)), or the session item.
    public enum Kind: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
        /// A prompt of the user.
        case user

        /// The messages of the agent in a turn.
        case agent

        /// A message from another session.
        case message

        /// A tool call: its title, its content, its terminal output and its
        /// patch text.
        case tool

        /// A plan: the text of its items.
        case plan

        /// The thoughts of the agent in a turn (Q64).
        case thought

        /// A match of the session item: the name, the slug, the tags, the
        /// folder, the agent, the recap and the last summary (D207 (c) (2)).
        case session
    }

    /// The wire id of the entry that holds the snippet.
    public var entryID: String

    /// The kind of the matched chunk.
    public var kind: Kind

    /// The author of the chunk, or `nil` when it has none.
    public var author: String?

    /// The date of the chunk, or `nil` when it has none.
    public var date: Date?

    /// About 200 characters around the part of the chunk with the most query
    /// words.
    public var snippet: String

    /// The matched words, as ranges of character offsets in ``snippet``. Empty
    /// for a match with only the cosine signal.
    public var ranges: [Range<Int>]

    /// The matched words, for the marks of the transcript. Empty for a match
    /// with only the cosine signal.
    public var terms: [String]

    /// Makes a hit.
    ///
    /// - Parameters:
    ///   - entryID: The wire id of the entry that holds the snippet.
    ///   - kind: The kind of the matched chunk.
    ///   - author: The author of the chunk, or `nil`.
    ///   - date: The date of the chunk, or `nil`.
    ///   - snippet: The text around the matched words.
    ///   - ranges: The ranges of the matched words in `snippet`.
    ///   - terms: The matched words.
    public init(
        entryID: String,
        kind: Kind,
        author: String?,
        date: Date?,
        snippet: String,
        ranges: [Range<Int>],
        terms: [String]
    ) {
        self.entryID = entryID
        self.kind = kind
        self.author = author
        self.date = date
        self.snippet = snippet
        self.ranges = ranges
        self.terms = terms
    }
}
