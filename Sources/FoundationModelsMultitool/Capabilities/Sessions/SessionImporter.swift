// `SessionImporter` — the import of a session of another agent, such as
// Claude Code or Codex, into a new session of this server, which the host
// gives (D209 (l)).
//
// This package does not link FoundationModelsACP and does not read the files
// of other agents. The readers of those files are in FoundationModelsACP, and
// the importer is in FoundationModelsACPAgent. Thus the host gives the import
// through this protocol, and the `list imports` and `import session`
// operations of the `sessions` tool call it.

import Foundation
import ULID

/// Lists the sessions of other agents that the host can import, and imports
/// one of them as a new session.
///
/// A host gives one to
/// ``SessionsTool/init(directory:exporter:searcher:sharer:importer:externalSessionHost:)`` and to
/// ``SessionsGraph/endpoint(of:exporter:searcher:sharer:importer:externalSessionHost:)``. With no
/// importer, the import operations give the corrective of the code
/// `IMPORT_UNAVAILABLE`.
///
/// An import is a copy (D209 (a)): it does not change the source file. Each
/// import makes a new session, also when the source was imported before
/// (D209 (n), Q85).
public protocol SessionImporter: Sendable {
    /// The sessions of other agents that the host can import, the newest
    /// first, with the sessions of ``ImportableSessionsRequest/preferredFolder``
    /// first.
    ///
    /// - Parameter request: The filter and the page of the list.
    /// - Returns: One page of the list, and the agents whose sessions the host
    ///   cannot read.
    /// - Throws: An error when the host cannot read the list.
    func importable(_ request: ImportableSessionsRequest) async throws -> ImportableSessionsPage

    /// Imports a session of another agent as a new session.
    ///
    /// - Parameter order: The source session, and the folder and the name of
    ///   the new session.
    /// - Returns: The new session.
    /// - Throws: ``SessionImportError/sourceUnreadable(agent:)`` when the host
    ///   cannot read the sessions of the agent,
    ///   ``SessionImportError/folderUnavailable(_:)`` when the folder of the
    ///   new session does not exist or the host cannot write it, and a different
    ///   error when the import fails.
    func importSession(_ order: SessionImportOrder) async throws -> SessionImportResult
}

/// What `list imports` asks the importer for.
public struct ImportableSessionsRequest: Sendable, Equatable, Codable {
    /// The source agent, for example `claude-code` or `codex`, or `nil` for
    /// each agent.
    public var agent: String?

    /// The folder of the source sessions, or `nil` for each folder.
    public var folder: URL?

    /// The folder whose sessions come first, or `nil`: the folder of the
    /// caller session.
    public var preferredFolder: URL?

    /// The most sessions of the page.
    public var limit: Int

    /// The cursor of the page, or `nil` for the first page.
    public var cursor: String?

    /// Makes a request.
    ///
    /// - Parameters:
    ///   - agent: The source agent, or `nil` for each agent.
    ///   - folder: The folder of the source sessions, or `nil` for each
    ///     folder.
    ///   - preferredFolder: The folder whose sessions come first, or `nil`.
    ///   - limit: The most sessions of the page.
    ///   - cursor: The cursor of the page, or `nil` for the first page.
    public init(agent: String?, folder: URL?, preferredFolder: URL?, limit: Int, cursor: String?) {
        self.agent = agent
        self.folder = folder
        self.preferredFolder = preferredFolder
        self.limit = limit
        self.cursor = cursor
    }
}

/// One session of another agent that the host can import.
public struct ImportableSession: Sendable, Equatable, Codable {
    /// The source agent, for example `claude-code` or `codex`.
    public var agent: String

    /// The id of the session in the store of the source agent.
    public var sourceID: String

    /// The path of the file of the session.
    public var sourcePath: String

    /// The title of the session, or `nil` when the source has none.
    public var title: String?

    /// The working folder of the session, or `nil` when the source has none.
    public var folder: URL?

    /// The time of the last record of the session, or `nil` when the source
    /// gives no time.
    public var lastDate: Date?

    /// The number of turns of the session.
    public var turnCount: Int

    /// Each earlier import of the session. This is only information: an
    /// import of the session makes a new session also when it has earlier
    /// imports (Q85).
    public var previousImports: [SessionPreviousImport]

    /// Makes an importable session.
    ///
    /// - Parameters:
    ///   - agent: The source agent.
    ///   - sourceID: The id of the session in the store of the source agent.
    ///   - sourcePath: The path of the file of the session.
    ///   - title: The title of the session, or `nil`.
    ///   - folder: The working folder of the session, or `nil`.
    ///   - lastDate: The time of the last record, or `nil`.
    ///   - turnCount: The number of turns.
    ///   - previousImports: Each earlier import of the session.
    public init(
        agent: String, sourceID: String, sourcePath: String, title: String?, folder: URL?, lastDate: Date?,
        turnCount: Int, previousImports: [SessionPreviousImport]
    ) {
        self.agent = agent
        self.sourceID = sourceID
        self.sourcePath = sourcePath
        self.title = title
        self.folder = folder
        self.lastDate = lastDate
        self.turnCount = turnCount
        self.previousImports = previousImports
    }
}

/// An earlier import of a session of another agent.
public struct SessionPreviousImport: Sendable, Equatable, Codable {
    /// The session that the import made.
    public var session: ULID

    /// The time of the import.
    public var importedAt: Date

    /// Makes an earlier import.
    ///
    /// - Parameters:
    ///   - session: The session that the import made.
    ///   - importedAt: The time of the import.
    public init(session: ULID, importedAt: Date) {
        self.session = session
        self.importedAt = importedAt
    }
}

/// One page of the sessions that the host can import.
public struct ImportableSessionsPage: Sendable, Equatable, Codable {
    /// The sessions of the page, in the order of the importer.
    public var sessions: [ImportableSession]

    /// The cursor of the next page, or `nil` when no session follows.
    public var nextCursor: String?

    /// The source agents whose sessions the host cannot read, because the
    /// user gave no access to their folder.
    public var unreadableSources: [String]

    /// Makes a page.
    ///
    /// - Parameters:
    ///   - sessions: The sessions of the page.
    ///   - nextCursor: The cursor of the next page, or `nil`.
    ///   - unreadableSources: The source agents whose sessions the host
    ///     cannot read.
    public init(sessions: [ImportableSession], nextCursor: String?, unreadableSources: [String]) {
        self.sessions = sessions
        self.nextCursor = nextCursor
        self.unreadableSources = unreadableSources
    }
}

/// What `import session` asks the importer to import.
public struct SessionImportOrder: Sendable, Equatable, Codable {
    /// The source agent, for example `claude-code` or `codex`.
    public var agent: String

    /// The source session: its id in the store of the source agent, or the
    /// path of its file.
    public var source: String

    /// The working folder of the new session, or `nil` for the folder of the
    /// source session.
    public var folder: URL?

    /// The name of the new session, or `nil` for the title of the source
    /// session, else `<agent>-import`.
    public var name: String?

    /// Makes an order.
    ///
    /// - Parameters:
    ///   - agent: The source agent.
    ///   - source: The id or the file path of the source session.
    ///   - folder: The working folder of the new session, or `nil`.
    ///   - name: The name of the new session, or `nil`.
    public init(agent: String, source: String, folder: URL?, name: String?) {
        self.agent = agent
        self.source = source
        self.folder = folder
        self.name = name
    }
}

/// The new session of an import.
public struct SessionImportResult: Sendable, Equatable, Codable {
    /// The id of the new session.
    public var session: ULID

    /// The name of the new session.
    public var name: String

    /// The number of records of the source that the import did not read.
    public var skippedRecordCount: Int

    /// Makes a result.
    ///
    /// - Parameters:
    ///   - session: The id of the new session.
    ///   - name: The name of the new session.
    ///   - skippedRecordCount: The number of records that the import did not
    ///     read.
    public init(session: ULID, name: String, skippedRecordCount: Int) {
        self.session = session
        self.name = name
        self.skippedRecordCount = skippedRecordCount
    }
}

/// The errors of an importer that the `sessions` tool turns into a
/// corrective with its own code. The tool turns each other error of an
/// importer into the corrective of a failed import.
public enum SessionImportError: Error, Sendable, Equatable, Codable {
    /// The host cannot read the sessions of the source agent, because the
    /// user gave no access to their folder. Only the user can give access,
    /// with the command Import Sessions….
    case sourceUnreadable(agent: String)

    /// The working folder of the new session does not exist, or the host
    /// cannot write it.
    case folderUnavailable(URL)
}
