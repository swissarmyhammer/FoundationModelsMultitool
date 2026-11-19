// The import of a session of another agent in the `sessions` GraphQL
// endpoint (D209 (l)): the `importableSessions` query, the `importSession`
// mutation and their types.
//
// The query and the mutation call the shared steps of the `list imports` and
// `import session` operations of the `sessions` tool,
// `SessionsVisibility.importables(_:with:)` and
// `SessionsVisibility.importSession(_:with:)`. Thus the tool ops and the
// endpoint share one rule, one corrective and the same codes:
// `IMPORT_UNAVAILABLE`, `NO_SOURCE_ACCESS`, `IMPORT_FOLDER_UNAVAILABLE` and
// `IMPORT_FAILED`. Each import makes a new session, also when the source was
// imported before (Q85).
//
// An earlier import gives its `Session` only when the viewer can see that
// session. The page drops each other earlier import, so the page does not
// tell that the session exists, as `unavailableFolders` of a search does not.
//
// The `folder` of the query filters the source sessions, and the `folder` of
// the mutation is the folder of the new session. A call with no viewer is the
// agent of the caller session, so `.` is the folder of that session, as in
// the tool, and the sessions of that folder come first. A client has no
// caller session, so `.` gives `INVALID_FOLDER` with the corrective of the
// tool for a call in no session, and no folder comes first.
//
// Who acts: a device of the user and the agent import, as for a start. An
// external client cannot import a session, as it cannot start one: an import
// starts a new session that the external client does not own.

import Foundation
import FoundationModelsExtras
import Graphiti
import ULID

// MARK: - Arguments and the types

/// The arguments of `Query.importableSessions`.
struct SessionsGraphImportableArguments: Codable, Sendable {
    /// The source agent, or `nil` for each agent.
    let agent: String?

    /// The folder of the source sessions as written, or `nil` for each
    /// folder.
    let folder: String?

    /// The most sessions of the page, or `nil` for the default.
    let first: Int?

    /// The `nextCursor` of the page before, or `nil` for the first page.
    let after: String?

    /// The arguments of the shared list step.
    ///
    /// - Parameter callerFolder: The folder of the caller session, or `nil`
    ///   for a call with no caller session.
    /// - Returns: The arguments.
    func listArguments(callerFolder: URL?) -> ImportListArguments {
        ImportListArguments(agent: agent, folder: folder, limit: first, callerFolder: callerFolder, cursor: after)
    }
}

/// The input of `Mutation.importSession`.
struct SessionsGraphImportInput: Codable, Sendable {
    /// The source agent, as written.
    let agent: String

    /// The id or the file path of the source session, as written.
    let source: String

    /// The folder of the new session as written, or `nil` for the folder of
    /// the source session.
    let folder: String?

    /// The name of the new session, or `nil`.
    let name: String?

    /// The arguments of the shared import step.
    ///
    /// - Parameter callerFolder: The folder of the caller session, or `nil`
    ///   for a call with no caller session.
    /// - Returns: The arguments.
    func orderArguments(callerFolder: URL?) -> ImportOrderArguments {
        ImportOrderArguments(agent: agent, source: source, folder: folder, name: name, callerFolder: callerFolder)
    }
}

/// The `SessionPreviousImport` type: an earlier import of a source session,
/// whose session the viewer can see.
struct SessionsGraphPreviousImport: Sendable {
    /// The session that the import made, with its facts from the directory.
    let session: SessionsGraphSession

    /// The time of the import.
    let importedAt: DateTime
}

/// The `ImportableSession` type: one session of another agent that the
/// importer can import.
struct SessionsGraphImportableSession: Sendable {
    /// The source agent.
    let agent: String

    /// The id of the session in the store of the source agent.
    let sourceId: String

    /// The path of the file of the session.
    let sourcePath: String

    /// The title of the session, or `nil`.
    let title: String?

    /// The path of the working folder of the session, or `nil`.
    let folder: String?

    /// The time of the last record of the session, or `nil`.
    let lastDate: DateTime?

    /// The number of turns of the session.
    let turnCount: Int

    /// Each earlier import whose session the viewer can see.
    let previousImports: [SessionsGraphPreviousImport]

    /// Makes the object of one session of the importer.
    ///
    /// - Parameters:
    ///   - session: The session of the importer.
    ///   - summaries: The session of each earlier import that the viewer can
    ///     see. An earlier import with no entry is dropped.
    init(_ session: ImportableSession, summaries: [ULID: SessionSummary]) {
        agent = session.agent
        sourceId = session.sourceID
        sourcePath = session.sourcePath
        title = session.title
        folder = session.folder?.path
        lastDate = session.lastDate.map(DateTime.init)
        turnCount = session.turnCount
        previousImports = session.previousImports.compactMap { previous in
            summaries[previous.session].map { summary in
                SessionsGraphPreviousImport(
                    session: SessionsGraphSession(summary), importedAt: DateTime(previous.importedAt))
            }
        }
    }
}

/// The `ImportableSessionPage` type: one page of the sessions of other
/// agents that the importer can import.
struct SessionsGraphImportableSessionPage: Sendable {
    /// The sessions of the page, in the order of the importer.
    let sessions: [SessionsGraphImportableSession]

    /// The cursor of the next page, or `nil` when this page is the last.
    let nextCursor: String?

    /// The source agents whose sessions the importer cannot read.
    let unreadableSources: [String]

    /// Makes the page of one list.
    ///
    /// - Parameter outcome: The page of the importer, with the session of
    ///   each earlier import that the viewer can see.
    init(_ outcome: ImportableSessionsOutcome) {
        sessions = outcome.page.sessions.map { SessionsGraphImportableSession($0, summaries: outcome.summaries) }
        nextCursor = outcome.page.nextCursor
        unreadableSources = outcome.page.unreadableSources
    }
}

// MARK: - The resolvers

extension SessionsGraphContext {
    /// The folder of the caller session for the folder `.` of an import
    /// field: the folder of the caller session for a call of the agent, and
    /// `nil` for a client, which has no caller session.
    ///
    /// - Returns: The folder, or `nil`.
    /// - Throws: Each error of the directory.
    func importCallerFolder() async throws -> URL? {
        guard sessions.viewer == nil else {
            return nil
        }
        return try await actions.callerFolder()
    }
}

extension SessionsGraphResolver {
    /// Resolves `Query.importableSessions`: the sessions of other agents
    /// that the importer of the endpoint can import, each with the earlier
    /// imports whose session the viewer can see.
    ///
    /// - Parameters:
    ///   - context: The context of the call, which gives the visibility and
    ///     the importer.
    ///   - arguments: The agent, the folder and the page.
    /// - Returns: The page.
    /// - Throws: ``SessionsRefusal`` with the code `IMPORT_UNAVAILABLE` when
    ///   the endpoint has no importer, `INVALID_FOLDER` for a folder that the
    ///   step cannot read, and `IMPORT_FAILED` when the importer fails; the
    ///   coded error of each error of the directory.
    func importableSessions(
        context: SessionsGraphContext, arguments: SessionsGraphImportableArguments
    ) async throws -> SessionsGraphImportableSessionPage {
        try await Self.coding {
            let listArguments = arguments.listArguments(callerFolder: try await context.importCallerFolder())
            return SessionsGraphImportableSessionPage(
                try await context.sessions.importables(listArguments, with: context.importer))
        }
    }

    /// Resolves `Mutation.importSession`: imports a session of another agent
    /// as a new session. Each call makes a new session. An external client
    /// cannot import, as it cannot start a session; the actor comes next, as
    /// for a start, then the shared import step.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The input object.
    /// - Returns: The new session, as the directory gives it.
    /// - Throws: The coded error of a refusal, and each other error of the
    ///   directory.
    func importSession(
        context: SessionsGraphContext, arguments: SessionsGraphMutationArguments<SessionsGraphImportInput>
    ) async throws -> SessionsGraphSession {
        try await Self.coding {
            guard !context.viewerIsExternal else {
                throw SessionsRefusal(.untrustedClient, SessionsGraphText.externalImport)
            }
            _ = try context.actor(of: .importSession)
            let orderArguments = arguments.input.orderArguments(callerFolder: try await context.importCallerFolder())
            return SessionsGraphSession(
                try await context.sessions.importSession(orderArguments, with: context.importer).summary)
        }
    }
}

// MARK: - The schema

extension SessionsGraphAPI {
    /// The text of the rule of the folder `.` of an import field.
    private static let dotFolderRule =
        "For the agent, . is the folder of its session. A client has no session, so . gives INVALID_FOLDER."

    /// The text of the rule of each import field with no importer.
    private static let noImporterRule = "IMPORT_UNAVAILABLE when this server cannot import a session."

    /// The `Query.importableSessions` field.
    ///
    /// - Returns: The field.
    static func importableSessionsField() -> SchemaField {
        Field("importableSessions", at: SessionsGraphResolver.importableSessions) {
            Argument("agent", at: \.agent).description("The source agent: claude-code or codex. None: each agent.")
            Argument("folder", at: \.folder)
                .description(
                    "The absolute path of the folder of the source sessions. ~ expands. \(dotFolderRule) None: each "
                        + "folder.")
            Argument("first", at: \.first)
                .defaultValue(SessionsVisibility.defaultImportLimit)
                .description("The most sessions to give: 1 to \(SessionsVisibility.maximumImportLimit).")
            Argument("after", at: \.after)
                .description("The nextCursor of the page before, or no cursor for the first page.")
        }
        .description(
            "The sessions of other agents, such as Claude Code or Codex, that this server can import, the newest "
                + "first, each with its earlier imports. For the agent, the sessions of the folder of its session "
                + "come first. An import of a session makes a new session also when it has earlier imports. "
                + "\(noImporterRule) IMPORT_FAILED when the list fails.")
    }

    /// The `ImportableSession` type.
    ///
    /// - Returns: The type.
    static func importableSessionType() -> SchemaType {
        Type(SessionsGraphImportableSession.self, as: "ImportableSession") {
            Field("agent", at: \.agent).description("The source agent, for example claude-code or codex.")
            Field("sourceId", at: \.sourceId)
                .description("The id of the session in the store of the source agent. importSession takes it.")
            Field("sourcePath", at: \.sourcePath).description("The path of the file of the session.")
            Field("title", at: \.title).description("The title of the session, or null when the source has none.")
            Field("folder", at: \.folder)
                .description(
                    "The absolute path of the working folder of the session, or null when the source has none.")
            Field("lastDate", at: \.lastDate)
                .description("The time of the last record of the session, or null when the source gives no time.")
            Field("turnCount", at: \.turnCount).description("The number of turns of the session.")
            Field("previousImports", at: \.previousImports)
                .description(
                    "Each earlier import of the session whose session you can see. This is only information: an "
                        + "import makes a new session also when the session has earlier imports.")
        }
        .description("One session of another agent that this server can import.")
    }

    /// The `SessionPreviousImport` type.
    ///
    /// - Returns: The type.
    static func previousImportType() -> SchemaType {
        Type(SessionsGraphPreviousImport.self, as: "SessionPreviousImport") {
            Field("session", at: \.session).description("The session that the import made, with its facts now.")
            Field("importedAt", at: \.importedAt).description("The time of the import.")
        }
        .description("An earlier import of a session of another agent.")
    }

    /// The `ImportableSessionPage` type.
    ///
    /// - Returns: The type.
    static func importableSessionPageType() -> SchemaType {
        Type(SessionsGraphImportableSessionPage.self, as: "ImportableSessionPage") {
            Field("sessions", at: \.sessions).description("The sessions of the page.")
            Field("nextCursor", at: \.nextCursor)
                .description("The cursor of the next page, or null when this page is the last.")
            Field("unreadableSources", at: \.unreadableSources)
                .description(
                    "The source agents whose sessions this server cannot read: the user gave no access to their "
                        + "folder. Only the user can give access, with the command Import Sessions….")
        }
        .description("One page of the sessions of other agents that this server can import.")
    }

    /// The `ImportSessionInput` input object.
    ///
    /// - Returns: The input object.
    static func importInput() -> SchemaType {
        Input(SessionsGraphImportInput.self, as: SessionsGraphMutation.importSession.inputName) {
            InputField("agent", at: \.agent).description("The source agent: claude-code or codex.")
            InputField("source", at: \.source)
                .description("The source session: its sourceId from importableSessions, or the path of its file.")
            InputField("folder", at: \.folder)
                .description(
                    "The absolute path of the folder of the new session. ~ expands. \(dotFolderRule) None: the folder "
                        + "of the source session.")
            InputField("name", at: \.name)
                .description("The name of the new session. None: the title of the source session, else <agent>-import.")
        }
        .description("The session of another agent to import, and the folder and the name of the new session.")
    }

    /// The field of the `importSession` mutation.
    ///
    /// - Returns: The field.
    static func importMutationField() -> SchemaField {
        mutationField(
            .importSession, at: SessionsGraphResolver.importSession,
            input: "The source session, and the folder and the name of the new session.",
            description: "Imports a session of another agent, such as Claude Code or Codex, as a new session. The "
                + "import copies the session and does not change the source. Each call makes a new session, also "
                + "when the source was imported before. Gives the new session. An external client cannot import a "
                + "session. \(noImporterRule) NO_SOURCE_ACCESS when the user gave no access to the sessions of the "
                + "agent, IMPORT_FOLDER_UNAVAILABLE when the folder does not exist or this server cannot write it, "
                + "and IMPORT_FAILED when the import fails.")
    }
}
