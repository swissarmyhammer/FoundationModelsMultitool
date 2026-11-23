// The `search sessions` operation of the `sessions` tool (D207 (g), D100: the
// agent can do what the UI can do).
//
// The operation searches the transcripts of the sessions that this server
// records, and answers plain text: for each session one line with its short
// id, its name, its folder, the date and the number of hits, then at most
// three snippets, then one line for each session of another agent whose
// index fields match, and at the end the limit of the search. It never gives a
// full transcript: the model reads more with `export session` and the file
// tools. The host gives the search through a ``SessionTranscriptSearcher``.
// With no searcher, the operation gives a corrective that names the UI
// command Search (⌘F).
//
// Each error is a corrective text, never a thrown model error.

import Foundation
import FoundationModels
import FoundationModelsExtras
import Operations
import ULID

/// One session of the page of a search, with its facts from the directory.
struct SessionSearchMatch: Sendable {
    /// The result of the searcher.
    let result: SessionSearchResult

    /// The facts of the session, as the directory gives them now.
    let summary: SessionSummary
}

/// One page of a session search, as the viewer of the search sees it: the
/// `search sessions` operation and the `searchSessions` field of the
/// `sessions` endpoint both read it.
struct SessionSearchOutcome: Sendable {
    /// The page of the searcher.
    let page: SessionSearchPage

    /// The results of ``page`` whose sessions the viewer can see, each with
    /// its facts from the directory, in the order of the page.
    let matches: [SessionSearchMatch]
}

/// Searches the transcripts of the sessions of this server
/// (`search sessions`).
@Generable
@Operation(
    verb: "search", noun: "sessions",
    description: """
        Search the transcripts of the sessions on this server by their words or by their meaning. Gives for each \
        session its @<short id>, its name, its folder, the date and the number of hits, and at most three snippets. \
        To read more, export the session with export session and read the file. Then gives the sessions of other \
        agents, such as Claude Code or Codex, whose title, prompts, folder or branch match.
        """)
struct SearchSessions {
    /// The text of the query.
    @Guide(
        description: """
            The search text: words, "a phrase" and -word, and the tokens @<session>, #<tag>, agent:<id>, \
            folder:<path> (folder:. is your folder), from:user, from:agent, from:message, from:tool, from:plan, \
            from:thought, after:YYYY-MM-DD, before:YYYY-MM-DD and is:archived.
            """)
    @OperationParam(aliases: ["text", "q"])
    var query: String

    /// The folder of the sessions.
    @Guide(
        description: """
            Optional. The absolute path of the folder of the sessions, or . for the folder of your session. ~ expands.
            """)
    @OperationParam(aliases: ["cwd"])
    var folder: String?

    /// True to include the archived sessions.
    @Guide(description: "Optional. True to also search the archived sessions. The default is false.")
    @OperationParam(aliases: ["includeArchived"])
    var archived: Bool?

    /// The most sessions to give.
    @Guide(description: "Optional. The most sessions to give: 1 to 50. The default is 20.")
    @OperationParam(aliases: ["first"])
    var limit: Int?
}

extension SearchSessions {
    /// Searches the sessions that the caller can see.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: One line for each session with at most three snippets,
    ///   and the limit of the search; or the line that no session matches.
    ///   A corrective for a server with no searcher, a query with no term or
    ///   a wrong token, a reference that names no session or more than one
    ///   session, a relative folder, and a search that fails.
    func execute(in context: SessionsToolContext) async throws -> String {
        do {
            let arguments = SessionSearchArguments(
                text: query, folder: folder, includeArchived: archived ?? false, limit: limit,
                callerFolder: try await context.callerFolder())
            return try await context.search(arguments)
        } catch {
            return SessionsToolText.corrective(for: error)
        }
    }
}

extension SessionsToolContext {
    /// The working folder of the caller session, or `nil` for a call with no
    /// caller session.
    ///
    /// - Returns: The folder.
    /// - Throws: Each error of the directory.
    func callerFolder() async throws -> URL? {
        guard let callerID else {
            return nil
        }
        return try await sessions.workingFolder(of: .session(callerID))
    }

    /// Searches the sessions for `search sessions`.
    ///
    /// - Parameter arguments: What the search asks for.
    /// - Returns: The answer of the operation.
    /// - Throws: Each error of ``SessionsVisibility/search(_:with:)``.
    func search(_ arguments: SessionSearchArguments) async throws -> String {
        let outcome = try await sessions.search(arguments, with: searcher)
        return SessionsToolText.searchAnswer(
            outcome.matches, externalSessions: outcome.page.externalSessions, query: arguments.text,
            timeZone: arguments.timeZone)
    }

    /// The searcher of the host, for a search.
    ///
    /// - Parameter searcher: The searcher of the host, or `nil`.
    /// - Returns: The searcher.
    /// - Throws: ``SessionsRefusal`` with the code `MISSING_SEARCHER` when
    ///   `searcher` is `nil`.
    static func requiredSearcher(
        _ searcher: (any SessionTranscriptSearcher)?
    ) throws(SessionsRefusal) -> any SessionTranscriptSearcher {
        guard let searcher else {
            throw SessionsRefusal(.missingSearcher, SessionsToolText.noSearcher)
        }
        return searcher
    }

    /// The page that the searcher gives for a request.
    ///
    /// - Parameters:
    ///   - request: The request.
    ///   - searcher: The searcher of the host.
    /// - Returns: The page.
    /// - Throws: ``SessionsRefusal`` with the code `SEARCH_FAILED` when the
    ///   searcher fails.
    static func page(
        of request: SessionSearchRequest, from searcher: any SessionTranscriptSearcher
    ) async throws(SessionsRefusal) -> SessionSearchPage {
        do {
            return try await searcher.search(request)
        } catch {
            throw SessionsRefusal(.searchFailed, SessionsToolText.searchFailed(error))
        }
    }
}

extension SessionsVisibility {
    /// Searches the sessions that the viewer can see: the one search of the
    /// `search sessions` operation and of the `searchSessions` field.
    ///
    /// The search asks the searcher only after the directory read the query,
    /// so a call with a wrong query does no search.
    ///
    /// - Parameters:
    ///   - arguments: What the search asks for.
    ///   - searcher: The searcher of the host, or `nil` when the host gave
    ///     none.
    /// - Returns: The page of the searcher and its visible results.
    /// - Throws: ``SessionsRefusal`` for a server with no searcher, each error
    ///   of ``searchRequest(for:)`` and of
    ///   ``SessionsToolContext/page(of:from:)``, and each error of the
    ///   directory.
    func search(
        _ arguments: SessionSearchArguments, with searcher: (any SessionTranscriptSearcher)?
    ) async throws -> SessionSearchOutcome {
        let searcher = try SessionsToolContext.requiredSearcher(searcher)
        let request = try await searchRequest(for: arguments)
        let page = try await SessionsToolContext.page(of: request, from: searcher)
        return SessionSearchOutcome(page: page, matches: try await matches(in: page))
    }

    /// Each result of a page with the facts of its session. A result whose
    /// session the viewer cannot see now, for example a session that was
    /// deleted after the searcher indexed it, is not in the answer.
    ///
    /// - Parameter page: The page of the searcher.
    /// - Returns: The matches, in the order of the page.
    /// - Throws: Each error of the directory.
    private func matches(in page: SessionSearchPage) async throws -> [SessionSearchMatch] {
        var matches: [SessionSearchMatch] = []
        // A loop and not a `compactMap`: each lookup awaits the directory.
        for result in page.sessions {
            if let summary = try await summary(of: result.session) {
                matches.append(SessionSearchMatch(result: result, summary: summary))
            }
        }
        return matches
    }
}
