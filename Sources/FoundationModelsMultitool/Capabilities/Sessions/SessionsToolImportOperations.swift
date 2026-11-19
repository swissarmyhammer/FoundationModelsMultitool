// The `list imports` and `import session` operations of the `sessions` tool
// (D209 (l), D100: the agent can do what the UI can do).
//
// `list imports` lists the sessions of other agents, such as Claude Code or
// Codex, that the host can import, and `import session` copies one of them
// into a new session of this server. Each import makes a new session, also
// when the source was imported before (Q85): the earlier imports that
// `list imports` gives are only information. The host gives the import
// through a ``SessionImporter``. With no importer, each operation gives the
// corrective of the code `IMPORT_UNAVAILABLE`.
//
// Each error is a corrective text, never a thrown model error. The steps are
// functions of ``SessionsVisibility`` and ``SessionsToolContext``, so the
// query and the mutation of the `sessions` endpoint use the same steps and
// the same correctives.

import Foundation
import FoundationModels
import FoundationModelsExtras
import Operations
import ULID

/// What one `list imports` asks for, before the directory reads the folder.
struct ImportListArguments: Sendable {
    /// The source agent, or `nil` for each agent.
    var agent: String? = nil

    /// The `folder` argument as written, or `nil`. `.` is the folder of the
    /// caller.
    var folder: String? = nil

    /// The most sessions of the page, or `nil` for the default.
    var limit: Int? = nil

    /// The folder of the tab or of the caller session, or `nil` when the call
    /// has none. Its sessions come first.
    var callerFolder: URL? = nil

    /// The cursor of the page, or `nil` for the first page.
    var cursor: String? = nil
}

/// What one `import session` asks for, before the directory reads the
/// folder.
struct ImportOrderArguments: Sendable {
    /// The source agent, as written.
    let agent: String

    /// The id or the file path of the source session, as written.
    let source: String

    /// The `folder` argument as written, or `nil`. `.` is the folder of the
    /// caller.
    var folder: String? = nil

    /// The name of the new session, or `nil`.
    var name: String? = nil

    /// The folder of the caller session, or `nil` when the call has none.
    var callerFolder: URL? = nil
}

/// One page of the sessions to import, as the viewer sees it: the
/// `list imports` operation and the endpoint both read it.
struct ImportableSessionsOutcome: Sendable {
    /// The page of the importer.
    let page: ImportableSessionsPage

    /// The session of each earlier import that the viewer can see, by its
    /// id. An earlier import whose session the viewer cannot see has no
    /// entry.
    let summaries: [ULID: SessionSummary]
}

/// The new session of one import, as the directory gives it after the
/// import.
struct SessionImportOutcome: Sendable {
    /// The order that the importer got.
    let order: SessionImportOrder

    /// The new session.
    let summary: SessionSummary

    /// The number of records of the source that the import did not read.
    let skippedRecordCount: Int
}

/// Lists the sessions of other agents that the host can import
/// (`list imports`).
@Generable
@Operation(
    verb: "list", noun: "imports",
    description: """
        List the sessions of other agents, such as Claude Code or Codex, that this server can import. Gives for \
        each session its agent, its source id, its title, its folder, its date, its number of turns and each \
        earlier import. To import one, use import session.
        """)
struct ListImports {
    /// The source agent.
    @Guide(description: "Optional. The source agent: claude-code or codex. The default is each agent.")
    @OperationParam(aliases: ["from", "sourceAgent"])
    var agent: String?

    /// The folder of the source sessions.
    @Guide(
        description: """
            Optional. The absolute path of the folder of the source sessions, or . for the folder of your session. \
            ~ expands. The default is each folder.
            """)
    @OperationParam(aliases: ["cwd"])
    var folder: String?

    /// The most sessions to give.
    @Guide(description: "Optional. The most sessions to give: 1 to 50. The default is 20.")
    @OperationParam(aliases: ["first"])
    var limit: Int?
}

extension ListImports {
    /// Lists the sessions that the host can import.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: One line for each session, one line for each agent with no
    ///   access, and the advice of the import. A corrective for a server with
    ///   no importer, a relative folder, and an importer that fails.
    func execute(in context: SessionsToolContext) async throws -> String {
        do {
            let arguments = ImportListArguments(
                agent: agent, folder: folder, limit: limit, callerFolder: try await context.callerFolder())
            return SessionsToolText.importList(
                try await context.sessions.importables(arguments, with: context.importer))
        } catch {
            return SessionsToolText.corrective(for: error)
        }
    }
}

/// Imports a session of another agent as a new session (`import session`).
@Generable
@Operation(
    verb: "import", noun: "session",
    description: """
        Import a session of another agent, such as Claude Code or Codex, as a new session of this server. The \
        import copies the session and does not change the source. Each call makes a new session, also when the \
        source was imported before.
        """)
struct ImportSession {
    /// The source agent.
    @Guide(description: "The source agent: claude-code or codex.")
    @OperationParam(aliases: ["from", "sourceAgent"])
    var agent: String

    /// The source session.
    @Guide(description: "The source session: its source id from list imports, or the path of its file.")
    @OperationParam(aliases: ["sourceId", "path"])
    var source: String

    /// The folder of the new session.
    @Guide(
        description: """
            Optional. The absolute path of the folder of the new session, or . for the folder of your session. ~ \
            expands. The default is the folder of the source session.
            """)
    @OperationParam(aliases: ["cwd"])
    var folder: String?

    /// The name of the new session.
    @Guide(
        description: """
            Optional. The name of the new session. The default is the title of the source session, else \
            <agent>-import.
            """)
    @OperationParam(aliases: ["title"])
    var name: String?
}

extension ImportSession {
    /// Imports the source session as a new session.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: The short id, the name, the id and the folder of the new
    ///   session, and the number of records that the import did not read. A
    ///   corrective for a call with no caller, a server with no importer, a
    ///   blank agent or source, a relative folder, a source agent with no
    ///   access, a folder that is not available, and an importer that fails.
    func execute(in context: SessionsToolContext) async throws -> String {
        await context.answer(asCallerOf: Self.opString) { _ in
            let arguments = ImportOrderArguments(
                agent: agent, source: source, folder: folder, name: name, callerFolder: try await context.callerFolder()
            )
            return SessionsToolText.imported(
                try await context.sessions.importSession(arguments, with: context.importer))
        }
    }
}

extension SessionsVisibility {
    /// The number of sessions of a `list imports` that names no limit
    /// (D209 (l)).
    static let defaultImportLimit = 20

    /// The most sessions of one `list imports`.
    static let maximumImportLimit = 50

    /// Lists the sessions that the host can import: the one list step of
    /// `list imports` and of the endpoint.
    ///
    /// - Parameters:
    ///   - arguments: What the list asks for.
    ///   - importer: The importer of the host, or `nil` when the host gave
    ///     none.
    /// - Returns: The page of the importer, with the session of each earlier
    ///   import that the viewer can see.
    /// - Throws: ``SessionsRefusal`` for a server with no importer, a
    ///   relative folder, and an importer that fails; each error of the
    ///   directory.
    func importables(
        _ arguments: ImportListArguments, with importer: (any SessionImporter)?
    ) async throws -> ImportableSessionsOutcome {
        let importer = try SessionsToolContext.requiredImporter(importer)
        let request = try Self.importableRequest(for: arguments)
        let page = try await SessionsToolContext.importerResult(failure: SessionsToolText.importListFailed) {
            try await importer.importable(request)
        }
        return ImportableSessionsOutcome(page: page, summaries: try await summaries(ofImportsIn: page))
    }

    /// Imports a session of another agent: the one import step of
    /// `import session` and of the endpoint. Each call makes a new session.
    /// The step reads the new session from the directory after the import.
    ///
    /// - Parameters:
    ///   - arguments: What the import asks for.
    ///   - importer: The importer of the host, or `nil` when the host gave
    ///     none.
    /// - Returns: The new session, as the directory gives it.
    /// - Throws: ``SessionsRefusal`` for a server with no importer, a blank
    ///   agent or source, a relative folder, a source agent with no access, a
    ///   folder that is not available, and an importer that fails;
    ///   `SessionDirectoryError.unknownSession` when the viewer cannot see the
    ///   new session; each error of the directory.
    func importSession(
        _ arguments: ImportOrderArguments, with importer: (any SessionImporter)?
    ) async throws -> SessionImportOutcome {
        let importer = try SessionsToolContext.requiredImporter(importer)
        let order = try Self.importOrder(for: arguments)
        let result = try await SessionsToolContext.importerResult(failure: { SessionsToolText.importFailed(order, $0) })
        {
            try await importer.importSession(order)
        }
        guard let summary = try await summary(of: result.session) else {
            throw SessionDirectoryError.unknownSession(result.session)
        }
        return SessionImportOutcome(order: order, summary: summary, skippedRecordCount: result.skippedRecordCount)
    }

    /// The request of one `list imports`.
    ///
    /// - Parameter arguments: What the list asks for.
    /// - Returns: The request for the importer of the host.
    /// - Throws: ``SessionsRefusal`` for a relative folder, and for `.` in a
    ///   call with no caller folder.
    static func importableRequest(for arguments: ImportListArguments) throws(SessionsRefusal)
        -> ImportableSessionsRequest
    {
        ImportableSessionsRequest(
            agent: SessionsToolInput.nonBlank(arguments.agent),
            folder: try importFolder(
                arguments.folder, callerFolder: arguments.callerFolder,
                outcome: SessionsToolText.importListNotRunSentence),
            preferredFolder: arguments.callerFolder,
            limit: pageLimit(arguments.limit, defaultLimit: defaultImportLimit, maximumLimit: maximumImportLimit),
            cursor: arguments.cursor)
    }

    /// The order of one `import session`.
    ///
    /// - Parameter arguments: What the import asks for.
    /// - Returns: The order for the importer of the host.
    /// - Throws: ``SessionsRefusal`` for a blank agent or source, a relative
    ///   folder, and `.` in a call with no caller folder.
    static func importOrder(for arguments: ImportOrderArguments) throws(SessionsRefusal) -> SessionImportOrder {
        SessionImportOrder(
            agent: try SessionsToolInput.requiredText(arguments.agent, parameter: SessionsToolText.agentParameter),
            source: try SessionsToolInput.requiredText(arguments.source, parameter: SessionsToolText.sourceParameter),
            folder: try importFolder(
                arguments.folder, callerFolder: arguments.callerFolder, outcome: SessionsToolText.importNotRunSentence),
            name: SessionsToolInput.nonBlank(arguments.name))
    }

    /// The folder of a `folder` argument of an import operation, or `nil`
    /// for no folder.
    ///
    /// - Parameters:
    ///   - path: The `folder` argument as written, or `nil`.
    ///   - callerFolder: The folder of the caller, or `nil`.
    ///   - outcome: The sentence of the corrective that tells what the call
    ///     did not do.
    /// - Returns: The folder, or `nil`.
    /// - Throws: ``SessionsRefusal`` for a relative folder, and for `.` in a
    ///   call with no caller folder.
    private static func importFolder(
        _ path: String?, callerFolder: URL?, outcome: String
    ) throws(SessionsRefusal) -> URL? {
        guard let path = SessionsToolInput.nonBlank(path) else {
            return nil
        }
        return try requestFolder(path, callerFolder: callerFolder, outcome: outcome)
    }

    /// The session of each earlier import of a page whose session the
    /// viewer can see.
    ///
    /// - Parameter page: The page of the importer.
    /// - Returns: The summary of each visible session, by its id.
    /// - Throws: Each error of the directory.
    private func summaries(ofImportsIn page: ImportableSessionsPage) async throws -> [ULID: SessionSummary] {
        var summaries: [ULID: SessionSummary] = [:]
        // A loop and not a `map`: each lookup awaits the directory.
        for previous in page.sessions.flatMap(\.previousImports) {
            summaries[previous.session] = try await summary(of: previous.session)
        }
        return summaries
    }
}

extension SessionsToolContext {
    /// The importer of the host, for an import call.
    ///
    /// The import operations and the import fields of the `sessions`
    /// endpoint refuse a call with no importer with this one refusal.
    ///
    /// - Parameter importer: The importer of the host, or `nil`.
    /// - Returns: The importer.
    /// - Throws: ``SessionsRefusal`` with the code `IMPORT_UNAVAILABLE` when
    ///   `importer` is `nil`.
    static func requiredImporter(_ importer: (any SessionImporter)?) throws(SessionsRefusal) -> any SessionImporter {
        guard let importer else {
            throw SessionsRefusal(.importUnavailable, SessionsToolText.noImporter)
        }
        return importer
    }

    /// The result of one call of the importer. A ``SessionImportError``
    /// becomes the refusal of its case, a `SessionDirectoryError` stays as
    /// it is, and each other error becomes the refusal of a failed import.
    ///
    /// - Parameters:
    ///   - failure: The corrective of a different error of the importer.
    ///   - call: The call of the importer.
    /// - Returns: What `call` gave.
    /// - Throws: ``SessionsRefusal`` with the code `NO_SOURCE_ACCESS`,
    ///   `IMPORT_FOLDER_UNAVAILABLE` or `IMPORT_FAILED`, or the
    ///   `SessionDirectoryError` of the importer.
    static func importerResult<Value: Sendable>(
        failure: (any Error) -> String, _ call: () async throws -> Value
    ) async throws -> Value {
        do {
            return try await call()
        } catch let error as SessionImportError {
            throw refusal(for: error)
        } catch let error as SessionDirectoryError {
            throw error
        } catch {
            throw SessionsRefusal(.importFailed, failure(error))
        }
    }

    /// The refusal of an error of the importer.
    ///
    /// - Parameter error: The error.
    /// - Returns: The refusal with the code and the corrective of the case.
    static func refusal(for error: SessionImportError) -> SessionsRefusal {
        switch error {
        case .sourceUnreadable(let agent):
            SessionsRefusal(.noSourceAccess, SessionsToolText.noSourceAccess(agent))
        case .folderUnavailable(let folder):
            SessionsRefusal(.importFolderUnavailable, SessionsToolText.importFolderUnavailable(folder))
        }
    }
}
