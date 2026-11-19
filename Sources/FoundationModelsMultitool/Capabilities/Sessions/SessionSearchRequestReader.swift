// The one reader of a session search (D207 (d), (e)): the `search sessions`
// operation of the `sessions` tool and the `searchSessions` field of the
// `sessions` endpoint both turn their arguments into a
// `SessionSearchRequest` here.
//
// The reader parses the query with ``SessionSearchQuery``. Then the
// directory reads the session tokens: `@<session>` goes through the one
// resolver (D199 (d)), and the tag form, `agent:` and `folder:` (and the
// `folder` argument) filter the sessions that the caller can see. The
// searcher of the host gets the result as the session filter of the request.

import Foundation
import FoundationModelsExtras
import ULID

/// What one session search asks for, before the directory reads it.
struct SessionSearchArguments: Sendable {
    /// The text of the query, in the syntax of ``SessionSearchQuery``.
    let text: String

    /// The `folder` argument as written, or `nil`. `.` is the folder of the
    /// caller.
    var folder: String? = nil

    /// True to include the archived sessions (the `archived` argument).
    var includeArchived = false

    /// The most sessions of the page, or `nil` for the default.
    var limit: Int? = nil

    /// The folder of the tab or of the caller session, or `nil` when the
    /// call has none. Its sessions come first (D207 (d)), and a short id or
    /// a slug of `@<session>` looks in it first.
    var callerFolder: URL? = nil

    /// The one session whose hits the search gives, or `nil`.
    var session: ULID? = nil

    /// The cursor of the page, or `nil` for the first page.
    var cursor: String? = nil

    /// The time zone in which a day of `after:` and `before:` starts.
    var timeZone = TimeZone.current
}

/// The session filter of the tokens of a query: each part that is not empty
/// must match.
struct SessionSearchFilter: Sendable {
    /// The sessions that the `@<session>` tokens name.
    let sessions: [ULID]

    /// The tags of the `#<tag>` tokens.
    let tags: [String]

    /// The agent ids of the `agent:` tokens.
    let agents: [String]

    /// The folders of the `folder:` tokens and of the `folder` argument.
    let folders: [URL]

    /// True when the filter keeps each session.
    var keepsEachSession: Bool {
        sessions.isEmpty && tags.isEmpty && agents.isEmpty && folders.isEmpty
    }

    /// Tells if a session passes each part of the filter.
    ///
    /// - Parameter summary: The session.
    /// - Returns: `true` when the session passes.
    func admits(_ summary: SessionSummary) -> Bool {
        let folder = summary.workingDirectory.standardizedFileURL.path
        return sessions.allSatisfy { $0 == summary.id } && tags.allSatisfy(summary.tags.contains)
            && agents.allSatisfy { $0 == summary.agentID }
            && folders.allSatisfy { $0.standardizedFileURL.path == folder }
    }
}

extension SessionsVisibility {
    /// The number of sessions of a search that names no limit (D207 (g)).
    static let defaultSearchLimit = 20

    /// The most sessions of one search (D207 (g)).
    static let maximumSearchLimit = 50

    /// The path of the folder of the caller in a `folder:` token and in the
    /// `folder` argument.
    static let callerFolderPath = "."

    /// The request of one session search, as the viewer sees the sessions.
    ///
    /// - Parameter arguments: What the search asks for.
    /// - Returns: The request for the searcher of the host.
    /// - Throws: ``SessionsRefusal`` for a query with no term or a wrong
    ///   token, for a reference that names no session or more than one
    ///   session, and for a folder that is not absolute; each error of the
    ///   directory.
    func searchRequest(for arguments: SessionSearchArguments) async throws -> SessionSearchRequest {
        let query = try SessionSearchQuery(parsing: arguments.text, timeZone: arguments.timeZone)
        return SessionSearchRequest(
            query: query,
            sessions: try await sessionFilter(of: query, arguments: arguments),
            includeArchived: arguments.includeArchived || query.includesArchived,
            preferredFolder: arguments.callerFolder,
            session: arguments.session,
            limit: Self.searchLimit(arguments.limit),
            cursor: arguments.cursor)
    }

    /// The limit of one search: `requested` brought into
    /// `1...maximumSearchLimit`, or ``defaultSearchLimit`` for no limit.
    ///
    /// - Parameter requested: The limit of the call, or `nil`.
    /// - Returns: The limit.
    static func searchLimit(_ requested: Int?) -> Int {
        pageLimit(requested, defaultLimit: defaultSearchLimit, maximumLimit: maximumSearchLimit)
    }

    /// The limit of one page: `requested` brought into `1...maximumLimit`,
    /// or `defaultLimit` for no limit.
    ///
    /// - Parameters:
    ///   - requested: The limit of the call, or `nil`.
    ///   - defaultLimit: The limit of a call with no limit.
    ///   - maximumLimit: The most items of one page.
    /// - Returns: The limit.
    static func pageLimit(_ requested: Int?, defaultLimit: Int, maximumLimit: Int) -> Int {
        min(max(requested ?? defaultLimit, 1), maximumLimit)
    }

    /// The sessions that the tokens of a query keep, among the sessions that
    /// the viewer can see.
    ///
    /// - Parameters:
    ///   - query: The parsed query.
    ///   - arguments: The arguments of the search.
    /// - Returns: The ids, or `nil` when the query and the arguments name no
    ///   session filter.
    /// - Throws: What ``searchRequest(for:)`` throws, but the parse.
    private func sessionFilter(
        of query: SessionSearchQuery, arguments: SessionSearchArguments
    ) async throws -> Set<ULID>? {
        let folderPaths = query.folders + [arguments.folder].compactMap { $0 }
        let filter = SessionSearchFilter(
            sessions: try await sessionIDs(referencedBy: query.sessionReferences, lookupFolder: arguments.callerFolder),
            tags: query.tags,
            agents: query.agents,
            folders: try folderPaths.map { path throws(SessionsRefusal) in
                try Self.requestFolder(
                    path, callerFolder: arguments.callerFolder, outcome: SessionsToolText.searchNotRunSentence)
            })
        guard !filter.keepsEachSession else {
            return nil
        }
        let candidates = try await sessions(matching: SessionQuery(includesRecorded: true, limit: Self.unboundedLimit))
        return Set(candidates.filter(filter.admits).map(\.id))
    }

    /// The session that each `@<session>` token names, through the one
    /// resolver.
    ///
    /// - Parameters:
    ///   - references: The texts after `@` of the tokens.
    ///   - lookupFolder: The folder in which a short id or a slug looks
    ///     first, or `nil`.
    /// - Returns: The ids, in the order of the tokens.
    /// - Throws: ``SessionsRefusal`` for a reference that names no session or
    ///   more than one session; each error of the directory.
    private func sessionIDs(referencedBy references: [String], lookupFolder: URL?) async throws -> [ULID] {
        var ids: [ULID] = []
        // A loop and not a `map`: each lookup awaits the directory.
        for reference in references {
            ids.append(
                try await sessionID(
                    referencedBy: "@\(reference)", lookupFolder: lookupFolder,
                    outcome: SessionsToolText.searchNotRunSentence))
        }
        return ids
    }

    /// The folder of a `folder:` token or of a `folder` argument: the one
    /// reader of the folder of the search and of the import operations.
    ///
    /// - Parameters:
    ///   - path: The path as written: ``callerFolderPath``, an absolute path,
    ///     or a path that starts with `~`.
    ///   - callerFolder: The folder of the caller, or `nil`.
    ///   - outcome: The sentence of the corrective that tells what the call
    ///     did not do.
    /// - Returns: The folder.
    /// - Throws: ``SessionsRefusal`` for ``callerFolderPath`` in a call with
    ///   no caller folder, and for a relative path.
    static func requestFolder(_ path: String, callerFolder: URL?, outcome: String) throws(SessionsRefusal) -> URL {
        guard path.trimmingCharacters(in: .whitespacesAndNewlines) == callerFolderPath else {
            return try SessionsToolInput.absoluteFolder(path)
        }
        guard let callerFolder else {
            throw SessionsRefusal(.invalidFolder, SessionsToolText.noCallerFolder(outcome))
        }
        return callerFolder
    }
}
