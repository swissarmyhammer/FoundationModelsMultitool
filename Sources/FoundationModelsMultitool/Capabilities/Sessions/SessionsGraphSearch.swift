// The session search of the `sessions` GraphQL endpoint (D207 (d), (h)): the
// `searchSessions` query, which gives the sessions whose transcripts match a
// query, each with its score and its hits.
//
// The field and the `search sessions` operation of the `sessions` tool share
// one search, `SessionsVisibility.search(_:with:)`: one request builder, one
// searcher check and one visibility rule. A client asks this field through
// the tunnel (D207 (h)); a kit only shows a hit.
//
// The endpoint has no caller session. Thus the `folder` argument is the
// folder of the tab of the client: its sessions come first (D207 (d)), and
// the `folder:.` token of the query names it.

import Foundation
import FoundationModelsExtras
import GraphQL
import Graphiti
import ULID

// MARK: - Arguments and the types

/// The arguments of `Query.searchSessions`.
struct SessionsGraphSearchArguments: Codable, Sendable {
    /// The text of the query, in the syntax of ``SessionSearchQuery``.
    let query: String

    /// The folder of the tab of the client, or `nil` for none.
    let folder: String?

    /// The one session whose hits the search gives, or `nil`.
    let session: ToolkitID?

    /// True to include the archived sessions, or `nil` for false.
    let archived: Bool?

    /// The most sessions of the page, or `nil` for the default.
    let first: Int?

    /// The `nextCursor` of the page before, or `nil` for the first page.
    let after: String?

    /// The arguments of the shared search.
    ///
    /// - Returns: The arguments.
    /// - Throws: ``SessionsRefusal`` for a folder that is not absolute, or
    ///   for a session that is not a session id.
    func searchArguments() throws(SessionsRefusal) -> SessionSearchArguments {
        SessionSearchArguments(
            text: query, includeArchived: archived ?? false, limit: first,
            callerFolder: try SessionsToolInput.folder(folder),
            session: try session.map { id throws(SessionsRefusal) in try SessionsGraphInput.sessionID(id) },
            cursor: after)
    }
}

/// The `SessionSearchHitKind` enum: the kind of the matched chunk of a hit.
enum SessionsGraphSearchHitKind: String, Codable, CaseIterable, Sendable {
    /// A prompt of the user.
    case user = "USER"

    /// The messages of the agent in a turn.
    case agent = "AGENT"

    /// A message from another session.
    case message = "MESSAGE"

    /// A tool call.
    case tool = "TOOL"

    /// A plan.
    case plan = "PLAN"

    /// The thoughts of the agent in a turn.
    case thought = "THOUGHT"

    /// The session item: the name, the tags, the folder, the agent and the
    /// recap.
    case session = "SESSION"

    /// Makes the enum value of a kind of the searcher.
    ///
    /// - Parameter kind: The kind of the searcher.
    init(_ kind: SessionSearchHit.Kind) {
        switch kind {
        case .user: self = .user
        case .agent: self = .agent
        case .message: self = .message
        case .tool: self = .tool
        case .plan: self = .plan
        case .thought: self = .thought
        case .session: self = .session
        }
    }
}

/// The `TextRange` type: the character offsets of matched words in a
/// snippet.
struct SessionsGraphTextRange: Sendable {
    /// The offset of the first character.
    let start: Int

    /// The offset after the last character.
    let end: Int

    /// Makes the object of a range of the searcher.
    ///
    /// - Parameter range: The range.
    init(_ range: Range<Int>) {
        start = range.lowerBound
        end = range.upperBound
    }
}

/// The `SessionSearchHit` type: one hit in the transcript of a session.
struct SessionsGraphSearchHit: Sendable {
    /// The wire id of the entry that holds the snippet.
    let entryId: String

    /// The kind of the matched chunk.
    let kind: SessionsGraphSearchHitKind

    /// The author of the chunk, or `nil`.
    let author: String?

    /// The date of the chunk, or `nil`.
    let at: DateTime?

    /// The text around the matched words.
    let snippet: String

    /// The ranges of the matched words in ``snippet``.
    let ranges: [SessionsGraphTextRange]

    /// The matched words.
    let terms: [String]

    /// Makes the object of a hit of the searcher.
    ///
    /// - Parameter hit: The hit.
    init(_ hit: SessionSearchHit) {
        entryId = hit.entryID
        kind = SessionsGraphSearchHitKind(hit.kind)
        author = hit.author
        at = hit.date.map(DateTime.init)
        snippet = hit.snippet
        ranges = hit.ranges.map(SessionsGraphTextRange.init)
        terms = hit.terms
    }
}

/// The `SessionSearchResult` type: one session that matches a search, with
/// its hits.
struct SessionsGraphSearchResult: Sendable {
    /// The session, with its facts from the directory.
    let session: SessionsGraphSession

    /// The score in `[0, 1]` of the first match of the session.
    let score: Double

    /// The number of hits of the session.
    let hitCount: Int

    /// The hits of the session, the best hit first.
    let hits: [SessionsGraphSearchHit]

    /// Makes the object of one visible result.
    ///
    /// - Parameter match: The result and the facts of its session.
    init(_ match: SessionSearchMatch) {
        session = SessionsGraphSession(match.summary)
        score = match.result.score
        hitCount = match.result.hitCount
        hits = match.result.hits.map(SessionsGraphSearchHit.init)
    }
}

/// The `ExternalSessionSearchResult` type: one session of another agent
/// whose index fields match a search.
struct SessionsGraphExternalSearchResult: Sendable {
    /// The session, as the index of the host gives it.
    let session: SessionsGraphExternalSession

    /// The score in `[0, 1]` of the match.
    let score: Double

    /// The index field of the best match, or `nil`.
    let field: String?

    /// Makes the object of one external result of the searcher.
    ///
    /// - Parameter result: The result.
    init(_ result: ExternalSessionSearchResult) {
        session = SessionsGraphExternalSession(result.session)
        score = result.score
        field = result.field
    }
}

/// The `SessionSearchConnection` type: one page of the sessions that match a
/// search.
struct SessionsGraphSearchConnection: Sendable {
    /// The sessions that match and that the viewer can see.
    let results: [SessionsGraphSearchResult]

    /// The cursor of the next page, or `nil` when this page is the last.
    let nextCursor: String?

    /// The paths of the folders of ``results`` that the server cannot read
    /// now.
    let unavailableFolders: [String]

    /// The sessions of other agents whose index fields match, the best score
    /// first. Only the first page gives them.
    let externalSessions: [SessionsGraphExternalSearchResult]

    /// Makes the page of one search.
    ///
    /// A folder of a session that the viewer cannot see is not in
    /// ``unavailableFolders``, so the page does not tell that the session
    /// exists.
    ///
    /// - Parameter outcome: The page of the searcher and its visible results.
    init(_ outcome: SessionSearchOutcome) {
        let visibleFolders = Set(outcome.matches.map { Self.path(of: $0.summary.workingDirectory) })
        results = outcome.matches.map(SessionsGraphSearchResult.init)
        nextCursor = outcome.page.nextCursor
        unavailableFolders = outcome.page.unavailableFolders.map(Self.path(of:)).filter(visibleFolders.contains)
        externalSessions = outcome.page.externalSessions.map(SessionsGraphExternalSearchResult.init)
    }

    /// The path of a folder, in one form for each spelling of the folder.
    ///
    /// - Parameter folder: The folder.
    /// - Returns: The standardized path.
    private static func path(of folder: URL) -> String {
        folder.standardizedFileURL.path
    }
}

// MARK: - Resolver

extension SessionsGraphResolver {
    /// Resolves `Query.searchSessions`: the sessions whose transcripts match
    /// the query and that the viewer can see, each with its score and its
    /// hits.
    ///
    /// - Parameters:
    ///   - context: The context of the call, which gives the visibility and
    ///     the searcher.
    ///   - arguments: The query, the folder of the tab, the session, the
    ///     archived flag and the page.
    /// - Returns: The page.
    /// - Throws: ``SessionsRefusal`` with the code `MISSING_SEARCHER` when the
    ///   endpoint has no searcher, each other refusal of the search, and an
    ///   error of the directory.
    func searchSessions(
        context: SessionsGraphContext, arguments: SessionsGraphSearchArguments
    ) async throws -> SessionsGraphSearchConnection {
        let outcome = try await context.sessions.search(try arguments.searchArguments(), with: context.searcher)
        return SessionsGraphSearchConnection(outcome)
    }
}

// MARK: - Schema

extension SessionsGraphAPI {
    /// The `Query.searchSessions` field.
    ///
    /// - Returns: The field.
    static func searchSessionsField() -> SchemaField {
        Field("searchSessions", at: SessionsGraphResolver.searchSessions) {
            Argument("query", at: \.query)
                .description(
                    "The search text: words, \"a phrase\" and -word, and the tokens @<session>, #<tag>, agent:<id>, "
                        + "folder:<path> (folder:. is the folder argument), from:<kind>, after:YYYY-MM-DD, "
                        + "before:YYYY-MM-DD and is:archived.")
            Argument("folder", at: \.folder)
                .description(
                    "The absolute path of the folder of your tab. Its sessions come first, and folder:. names it. "
                        + "~ expands.")
            Argument("session", at: \.session)
                .description("One session id. The field then gives each hit of that session, up to first.")
            Argument("archived", at: \.archived)
                .defaultValue(false)
                .description("True to also search the archived sessions.")
            Argument("first", at: \.first)
                .defaultValue(SessionsVisibility.defaultSearchLimit)
                .description(
                    "The most sessions to give, or with session the most hits: 1 to "
                        + "\(SessionsVisibility.maximumSearchLimit).")
            Argument("after", at: \.after)
                .description("The nextCursor of the page before, or no cursor for the first page.")
        }
        .description(
            "The sessions on this server whose transcripts match the query by their words or by their meaning, "
                + "each with its score and its hits. The sessions of the folder argument come first. The search "
                + "covers only the sessions that this server records. An external client sees only the sessions "
                + "that it can see, as in sessions. MISSING_SEARCHER when this server cannot search.")
    }

    /// The `SessionSearchHitKind` enum.
    ///
    /// - Returns: The enum.
    static func searchHitKindEnum() -> SchemaType {
        Enum(SessionsGraphSearchHitKind.self, as: "SessionSearchHitKind") {
            Value(.user).description("A prompt of the user.")
            Value(.agent).description("The messages of the agent in a turn.")
            Value(.message).description("A message from another session.")
            Value(.tool).description("A tool call: its title, its content and its output.")
            Value(.plan).description("A plan: the text of its items.")
            Value(.thought).description("The thoughts of the agent in a turn.")
            Value(.session).description(
                "The session item: the name, the slug, the tags, the folder, the agent, the recap and the last "
                    + "summary.")
        }
        .description("The kind of the matched chunk of a hit.")
    }

    /// The `TextRange` type.
    ///
    /// - Returns: The type.
    static func textRangeType() -> SchemaType {
        Type(SessionsGraphTextRange.self, as: "TextRange") {
            Field("start", at: \.start).description("The character offset of the first matched character.")
            Field("end", at: \.end).description("The character offset after the last matched character.")
        }
        .description("The character offsets of matched words in a snippet.")
    }

    /// The `SessionSearchHit` type.
    ///
    /// - Returns: The type.
    static func searchHitType() -> SchemaType {
        Type(SessionsGraphSearchHit.self, as: "SessionSearchHit") {
            Field("entryId", at: \.entryId).description("The wire id of the entry of the transcript that holds it.")
            Field("kind", at: \.kind).description("The kind of the matched chunk.")
            Field("author", at: \.author).description("The author of the chunk, or null.")
            Field("at", at: \.at).description("The time of the chunk, or null.")
            Field("snippet", at: \.snippet).description("The text around the matched words.")
            Field("ranges", at: \.ranges)
                .description("The matched words in the snippet. Empty for a match by meaning only.")
            Field("terms", at: \.terms)
                .description("The matched words, for the marks of the transcript. Empty for a match by meaning only.")
        }
        .description("One hit in the transcript of a session.")
    }

    /// The `SessionSearchResult` type.
    ///
    /// - Returns: The type.
    static func searchResultType() -> SchemaType {
        Type(SessionsGraphSearchResult.self, as: "SessionSearchResult") {
            Field("session", at: \.session)
                .description(
                    "The session, with its facts from this server now: the name, the folder, the state and the recap.")
            Field("score", at: \.score)
                .description("The score from 0 to 1 of the first match of the session. A client fuses lists with it.")
            Field("hitCount", at: \.hitCount).description("The number of hits. It can be more than the hits given.")
            Field("hits", at: \.hits).description("The hits of the session, the best hit first.")
        }
        .description("One session that matches a search, with its hits.")
    }

    /// The `ExternalSessionSearchResult` type.
    ///
    /// - Returns: The type.
    static func externalSearchResultType() -> SchemaType {
        Type(SessionsGraphExternalSearchResult.self, as: "ExternalSessionSearchResult") {
            Field("session", at: \.session).description("The session of the other agent, as the index gives it.")
            Field("score", at: \.score)
                .description("The score from 0 to 1 of the match, on the scale of the score of SessionSearchResult.")
            Field("field", at: \.field)
                .description(
                    "The index field of the best match: title, firstPrompt, lastPrompt, cwd or gitBranch. Null for "
                        + "a match by meaning only.")
        }
        .description(
            "One session of another agent, such as Claude Code or Codex, whose index fields match a search. The "
                + "search matches only the title, the prompts, the folder and the branch, not the text of the turns. "
                + "Read the session with externalSessionUpdates.")
    }

    /// The `SessionSearchConnection` type.
    ///
    /// - Returns: The type.
    static func searchConnectionType() -> SchemaType {
        Type(SessionsGraphSearchConnection.self, as: "SessionSearchConnection") {
            Field("results", at: \.results)
                .description("The sessions that match: first the sessions of the folder argument, then the others.")
            Field("nextCursor", at: \.nextCursor)
                .description("The cursor of the next page, or null when this page is the last.")
            Field("unavailableFolders", at: \.unavailableFolders)
                .description("The paths of the folders of the results that this server cannot read now.")
            Field("externalSessions", at: \.externalSessions)
                .description(
                    "The sessions of other agents whose title, prompts, folder or branch match, the best score "
                        + "first. Only the first page gives them, at most \(ExternalSessionSearchResult.maximumCount). "
                        + "A query with a @<session>, #<tag>, agent: or folder: token, or with the session argument, "
                        + "gives none.")
        }
        .description("One page of the sessions that match a search.")
    }
}
