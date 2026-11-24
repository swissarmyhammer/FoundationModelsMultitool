// The external sessions in the `sessions` GraphQL endpoint (D212, design
// sections 4.5, 5.3 and 5.4): the `externalSessions` and
// `externalSessionCounts` queries, the
// `externalSessionChanges` and `externalSessionUpdates` subscriptions, the
// `continueExternalSession` and `rebuildExternalSessionIndex` mutations and
// their types.
//
// An external session is a session file of another agent, such as Claude
// Code or Codex. The host gives the index of these files through an
// ``ExternalSessionHost``. The fields call the shared steps of the
// `list external sessions`, `count external sessions`,
// `read external session`,
// `continue external session` and `rebuild external session index`
// operations of the `sessions` tool, so the tool
// ops and the endpoint share one rule, one corrective and the same codes:
// `EXTERNAL_SESSIONS_UNAVAILABLE`, `NO_SOURCE_ACCESS`,
// `UNKNOWN_EXTERNAL_SESSION`, `FOLDER_UNAVAILABLE` and
// `EXTERNAL_SESSION_FAILED`.
//
// Cancellation: the query and the mutation call the host in the task of the
// resolver, so the cancellation of the GraphQL call arrives at the host. A
// subscription reads the stream of the host in the task that reads its
// events, so the stream of the host stops when the client stops the
// subscription.
//
// The `folder` of each field: a call with no viewer is the agent of the caller session, so `.` is the folder of that
// session. A client has no caller session, so `.` gives `INVALID_FOLDER`.
//
// Who acts: a device of the user and the agent continue a session, as for a
// start. An external client cannot continue a session, as it cannot start
// one. A device of the user and the agent rebuild the index. An external
// client cannot rebuild it, because a rebuild removes the rows of each
// client.

import Foundation
import FoundationModelsExtras
import GraphQL
import Graphiti

// MARK: - Arguments and the types

/// The arguments of `Query.externalSessions`.
struct SessionsGraphExternalSessionsArguments: Codable, Sendable {
    /// The source agent, or `nil` for each source.
    let source: String?

    /// The working folder of the sessions as written, or `nil` for each
    /// folder.
    let folder: String?

    /// True to include the automated sessions, or `nil` for the default.
    let automated: Bool?

    /// The most sessions of the page, or `nil` for the default.
    let first: Int?

    /// The `nextCursor` of the page before, or `nil` for the first page.
    let after: String?

    /// The arguments of the shared list step.
    ///
    /// - Parameter callerFolder: The folder of the caller session, or `nil`
    ///   for a call with no caller session.
    /// - Returns: The arguments.
    func listArguments(callerFolder: URL?) -> ExternalSessionListArguments {
        ExternalSessionListArguments(
            source: source, folder: folder, automated: automated, limit: first, callerFolder: callerFolder,
            cursor: after)
    }
}

/// The arguments of `Query.externalSessionCounts`.
struct SessionsGraphExternalCountsArguments: Codable, Sendable {
    /// The source agent, or `nil` for each source.
    let source: String?

    /// The working folder of the sessions as written, or `nil` for each
    /// folder.
    let folder: String?

    /// The arguments of the shared count step.
    ///
    /// - Parameter callerFolder: The folder of the caller session, or `nil`
    ///   for a call with no caller session.
    /// - Returns: The arguments.
    func countArguments(callerFolder: URL?) -> ExternalSessionCountArguments {
        ExternalSessionCountArguments(source: source, folder: folder, callerFolder: callerFolder)
    }
}

/// The arguments of `Subscription.externalSessionChanges`.
struct SessionsGraphExternalChangesArguments: Codable, Sendable {
    /// The working folder to follow as written, or `nil` for each folder.
    let folder: String?
}

/// The arguments of `Subscription.externalSessionUpdates`.
struct SessionsGraphExternalUpdatesArguments: Codable, Sendable {
    /// The source agent, as written.
    let source: String

    /// The id of the session in the store of the source agent, as written.
    let id: String
}

/// The input of `Mutation.continueExternalSession`.
struct SessionsGraphContinueExternalInput: Codable, Sendable {
    /// The source agent, as written.
    let source: String

    /// The id of the session in the store of the source agent, as written.
    let id: String

    /// The folder of the new session as written, or `nil` for the working
    /// folder of the external session.
    let folder: String?

    /// The name of the new session, or `nil`.
    let name: String?

    /// The arguments of the shared continue step.
    ///
    /// - Parameter callerFolder: The folder of the caller session, or `nil`
    ///   for a call with no caller session.
    /// - Returns: The arguments.
    func continueArguments(callerFolder: URL?) -> ExternalSessionContinueArguments {
        ExternalSessionContinueArguments(
            source: source, id: id, folder: folder, name: name, callerFolder: callerFolder)
    }
}

/// The input of `Mutation.rebuildExternalSessionIndex`.
struct SessionsGraphRebuildExternalIndexInput: Codable, Sendable {
    /// The source agent, as written.
    let source: String
}

/// The `ExternalSessionState` enum: how much of an external session the
/// index has read.
enum SessionsGraphExternalSessionState: String, Codable, CaseIterable, Sendable {
    /// The index found the file, and has not read it yet.
    case found = "FOUND"

    /// The index read the metadata windows of the file.
    case read = "READ"

    /// The index cannot read the file.
    case unreadable = "UNREADABLE"

    /// Makes the enum value of a state of the index.
    ///
    /// - Parameter state: The state of the index.
    init(_ state: ExternalSessionState) {
        switch state {
        case .found: self = .found
        case .read: self = .read
        case .unreadable: self = .unreadable
        }
    }
}

/// The `ExternalSessionKey` type: the identity of one external session.
struct SessionsGraphExternalSessionKey: Sendable {
    /// The source agent.
    let source: String

    /// The id of the session in the store of the source agent.
    let sourceId: String

    /// Makes the object of an id of the index.
    ///
    /// - Parameter id: The id.
    init(_ id: ExternalSessionID) {
        source = id.source
        sourceId = id.sourceID
    }
}

/// The `ExternalSessionContinuation` type: one session of this server that a
/// continue made from an external session.
struct SessionsGraphExternalSessionContinuation: Sendable {
    /// The id of the session of this server, canonical: a ULID in upper case.
    let id: ToolkitID

    /// The time when the continue made the session.
    let createdAt: DateTime

    /// Makes the object of a continuation of the index.
    ///
    /// - Parameter continuation: The continuation.
    init(_ continuation: ExternalSessionContinuation) {
        id = ToolkitID(continuation.sessionID.ulidString)
        createdAt = DateTime(continuation.createdAt)
    }
}

/// The `ExternalSession` type: one entry of the index of external sessions.
struct SessionsGraphExternalSession: Sendable {
    /// The source agent.
    let source: String

    /// The id of the session in the store of the source agent.
    let sourceId: String

    /// The path of the file, relative to the root of the source.
    let path: String

    /// The absolute path of the file, or `nil` when the file is not in the
    /// root to which the user gave access.
    let filePath: String?

    /// The name of the project folder of the file, or `nil`.
    let projectKey: String?

    /// The size of the file, in bytes. It is a `Float`, because a GraphQL
    /// `Int` holds only 32 bits.
    let size: Double

    /// The time of the last change of the file.
    let modified: DateTime

    /// The absolute path of the working folder, or `nil`.
    let cwd: String?

    /// The git branch, or `nil`.
    let gitBranch: String?

    /// True when a program started the session.
    let isAutomated: Bool

    /// The title, or `nil`.
    let title: String?

    /// The first prompt, cut short, or `nil`.
    let firstPrompt: String?

    /// The last prompt, cut short, or `nil`.
    let lastPrompt: String?

    /// The time of the first record, or `nil`.
    let firstDate: DateTime?

    /// The time of the last record, or `nil`.
    let lastDate: DateTime?

    /// How much of the file the index has read.
    let state: SessionsGraphExternalSessionState

    /// The text of the name of a row, or `nil`.
    let displayText: String?

    /// The date of a row.
    let displayDate: DateTime

    /// The sessions of this server that a continue made from this session,
    /// the oldest first.
    let continuedSessions: [SessionsGraphExternalSessionContinuation]

    /// Makes the object of an entry of the index.
    ///
    /// - Parameter summary: The entry.
    init(_ summary: ExternalSessionSummary) {
        source = summary.source
        sourceId = summary.sourceID
        path = summary.path
        filePath = summary.fileURL?.path
        projectKey = summary.projectKey
        size = Double(summary.size)
        modified = DateTime(summary.modified)
        cwd = summary.cwd?.path
        gitBranch = summary.gitBranch
        isAutomated = summary.isAutomated
        title = summary.title
        firstPrompt = summary.firstPrompt
        lastPrompt = summary.lastPrompt
        firstDate = summary.firstDate.map(DateTime.init)
        lastDate = summary.lastDate.map(DateTime.init)
        state = SessionsGraphExternalSessionState(summary.state)
        displayText = summary.displayText
        displayDate = DateTime(summary.displayDate)
        continuedSessions = summary.continuedSessions.map(SessionsGraphExternalSessionContinuation.init)
    }
}

/// The `ExternalSessionIndexState` type: the progress of the index.
struct SessionsGraphExternalIndexState: Sendable {
    /// The number of session files that the index found.
    let filesFound: Int

    /// The number of session files that the index read, or cannot read.
    let filesRead: Int

    /// True when the index read each file that it found.
    let isComplete: Bool

    /// Makes the object of a state of the index.
    ///
    /// - Parameter state: The state.
    init(_ state: ExternalSessionIndexState) {
        filesFound = state.filesFound
        filesRead = state.filesRead
        isComplete = state.isComplete
    }
}

/// The `ExternalSessionPage` type: one page of the external sessions.
struct SessionsGraphExternalSessionPage: Sendable {
    /// The sessions of the page, the newest first.
    let sessions: [SessionsGraphExternalSession]

    /// The progress of the index when the host made the page.
    let indexState: SessionsGraphExternalIndexState

    /// The cursor of the next page, or `nil` when this page is the last.
    let nextCursor: String?

    /// The sources whose sessions the host cannot read.
    let unreadableSources: [String]

    /// The progress of the index for the folder of the query, or `nil` for a query with no
    /// folder.
    let folderIndexState: SessionsGraphExternalIndexState?

    /// Makes the object of a page of the host.
    ///
    /// - Parameter page: The page.
    init(_ page: ExternalSessionPage) {
        sessions = page.sessions.map(SessionsGraphExternalSession.init)
        indexState = SessionsGraphExternalIndexState(page.indexState)
        nextCursor = page.nextCursor
        unreadableSources = page.unreadableSources
        folderIndexState = page.folderIndexState.map(SessionsGraphExternalIndexState.init)
    }
}

/// The `ExternalSessionCounts` type: the counts of the sessions that the
/// index has now, for one scope.
struct SessionsGraphExternalSessionCounts: Sendable {
    /// The number of typed sessions.
    let typedCount: Int

    /// The number of automated sessions.
    let automatedCount: Int

    /// The progress of the index for the scope of the counts.
    let indexState: SessionsGraphExternalIndexState

    /// Makes the object of the counts of the host.
    ///
    /// - Parameter counts: The counts.
    init(_ counts: ExternalSessionCounts) {
        typedCount = counts.typedCount
        automatedCount = counts.automatedCount
        indexState = SessionsGraphExternalIndexState(counts.indexState)
    }
}

/// The `ExternalSessionChange` type: one change of the index.
struct SessionsGraphExternalSessionChange: Sendable {
    /// The sessions that the index added or changed.
    let changed: [SessionsGraphExternalSession]

    /// The sessions whose files are gone.
    let removed: [SessionsGraphExternalSessionKey]

    /// The progress of the index after the change.
    let indexState: SessionsGraphExternalIndexState

    /// The progress of the index for the followed folder after the change, or `nil` for a
    /// stream of each folder.
    let folderIndexState: SessionsGraphExternalIndexState?

    /// Makes the object of a change of the host.
    ///
    /// - Parameter change: The change.
    init(_ change: ExternalSessionChange) {
        changed = change.changed.map(SessionsGraphExternalSession.init)
        removed = change.removed.map(SessionsGraphExternalSessionKey.init)
        indexState = SessionsGraphExternalIndexState(change.indexState)
        folderIndexState = change.folderIndexState.map(SessionsGraphExternalIndexState.init)
    }
}

/// The `ExternalSessionEntry` type: one entry of the history of an external
/// session.
struct SessionsGraphExternalSessionEntry: Sendable {
    /// The kind of the entry, for example `user_message_chunk`.
    let kind: String

    /// The time of the entry.
    let timestamp: DateTime

    /// The content of the entry, as a JSON value.
    let payload: Map

    /// Makes the object of an entry of the host.
    ///
    /// - Parameter entry: The entry.
    /// - Throws: The error of the encode of the payload.
    init(_ entry: SessionTranscriptEntry) throws {
        kind = entry.kind
        timestamp = DateTime(entry.timestamp)
        payload = try Map(entry.payload)
    }
}

/// The `ExternalSessionUpdateBatch` type: one batch of the history of an
/// external session.
struct SessionsGraphExternalSessionUpdateBatch: Sendable {
    /// The entries of the batch, oldest first.
    let entries: [SessionsGraphExternalSessionEntry]

    /// Makes the object of a batch of the host.
    ///
    /// - Parameter batch: The batch.
    /// - Throws: The error of the encode of a payload.
    init(_ batch: ExternalSessionUpdateBatch) throws {
        entries = try batch.entries.map(SessionsGraphExternalSessionEntry.init)
    }
}

// MARK: - The resolvers

extension SessionsGraphContext {
    /// The folder of the caller session for the folder `.` of an external
    /// session field: the folder of the caller session for a call of the
    /// agent, and `nil` for a client, which has no caller session.
    ///
    /// - Returns: The folder, or `nil`.
    /// - Throws: Each error of the directory.
    func callerFolderOfDot() async throws -> URL? {
        guard sessions.viewer == nil else {
            return nil
        }
        return try await actions.callerFolder()
    }
}

extension SessionsGraphResolver {
    /// Resolves `Query.externalSessions`: one page of the external sessions
    /// of the index of the host. The host runs in the task of this
    /// resolver, so the cancellation of the call arrives at the host.
    ///
    /// - Parameters:
    ///   - context: The context of the call, which gives the host.
    ///   - arguments: The source, the folder, the automated filter and the
    ///     page.
    /// - Returns: The page.
    /// - Throws: ``SessionsRefusal`` with the code
    ///   `EXTERNAL_SESSIONS_UNAVAILABLE` when the endpoint has no host,
    ///   `INVALID_FOLDER` for a folder that the step cannot read,
    ///   `NO_SOURCE_ACCESS` and `EXTERNAL_SESSION_FAILED` for an error of the
    ///   host; `CancellationError`; the coded error of each error of the
    ///   directory.
    func externalSessions(
        context: SessionsGraphContext, arguments: SessionsGraphExternalSessionsArguments
    ) async throws -> SessionsGraphExternalSessionPage {
        try await Self.coding {
            let listArguments = arguments.listArguments(callerFolder: try await context.callerFolderOfDot())
            return SessionsGraphExternalSessionPage(
                try await SessionsToolContext.externalSessions(listArguments, with: context.externalSessionHost))
        }
    }

    /// Resolves `Query.externalSessionCounts`: the counts of the external
    /// sessions of the index of the host, with no pages. The host runs in the
    /// task of this resolver, so the cancellation of the call arrives at the
    /// host.
    ///
    /// - Parameters:
    ///   - context: The context of the call, which gives the host.
    ///   - arguments: The source and the folder.
    /// - Returns: The counts.
    /// - Throws: ``SessionsRefusal`` with the code
    ///   `EXTERNAL_SESSIONS_UNAVAILABLE` when the endpoint has no host,
    ///   `INVALID_FOLDER` for a folder that the step cannot read, and
    ///   `EXTERNAL_SESSION_FAILED` for an error of the host;
    ///   `CancellationError`; the coded error of each error of the directory.
    func externalSessionCounts(
        context: SessionsGraphContext, arguments: SessionsGraphExternalCountsArguments
    ) async throws -> SessionsGraphExternalSessionCounts {
        try await Self.coding {
            let countArguments = arguments.countArguments(callerFolder: try await context.callerFolderOfDot())
            return SessionsGraphExternalSessionCounts(
                try await SessionsToolContext.externalSessionCounts(
                    countArguments, with: context.externalSessionHost
                ).counts)
        }
    }

    /// Resolves the source stream of `Subscription.externalSessionChanges`:
    /// the changes of the index of the host for a folder.
    ///
    /// - Parameters:
    ///   - context: The context of the call, which gives the host.
    ///   - arguments: The folder.
    /// - Returns: The stream of the host. It stops when the client stops the
    ///   subscription.
    /// - Throws: ``SessionsRefusal`` with the code
    ///   `EXTERNAL_SESSIONS_UNAVAILABLE` when the endpoint has no host, and
    ///   `INVALID_FOLDER` for a folder that the step cannot read; the coded
    ///   error of each error of the directory.
    func externalSessionChanges(
        context: SessionsGraphContext, arguments: SessionsGraphExternalChangesArguments
    ) async throws -> AsyncStream<ExternalSessionChange> {
        try await Self.coding {
            try SessionsToolContext.externalSessionChanges(
                folder: arguments.folder, callerFolder: try await context.callerFolderOfDot(),
                with: context.externalSessionHost)
        }
    }

    /// Resolves the source stream of `Subscription.externalSessionUpdates`:
    /// the history of one external session, in batches.
    ///
    /// - Parameters:
    ///   - context: The context of the call, which gives the host.
    ///   - arguments: The source and the id of the session.
    /// - Returns: The batches. The stream of the host stops when the client
    ///   stops the subscription. An error of the host ends the stream with
    ///   its refusal: `NO_SOURCE_ACCESS`, `UNKNOWN_EXTERNAL_SESSION` or
    ///   `EXTERNAL_SESSION_FAILED`.
    /// - Throws: ``SessionsRefusal`` with the code
    ///   `EXTERNAL_SESSIONS_UNAVAILABLE` when the endpoint has no host, and
    ///   `BLANK_TEXT` for a blank source or id.
    func externalSessionUpdates(
        context: SessionsGraphContext, arguments: SessionsGraphExternalUpdatesArguments
    ) async throws -> ExternalSessionUpdateSequence {
        try SessionsToolContext.externalSessionUpdates(
            source: arguments.source, id: arguments.id, with: context.externalSessionHost)
    }

    /// Resolves `Mutation.continueExternalSession`: copies an external
    /// session into a new session. Each call makes a new session. An
    /// external client cannot continue, as it cannot start a session; the
    /// actor comes next, as for a start, then the shared continue step. The
    /// host runs in the task of this resolver, so the cancellation of the
    /// call arrives at the host.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The input object.
    /// - Returns: The new session, as the host gives it.
    /// - Throws: The coded error of a refusal, `CancellationError`, and each
    ///   other error of the directory.
    func continueExternalSession(
        context: SessionsGraphContext, arguments: SessionsGraphMutationArguments<SessionsGraphContinueExternalInput>
    ) async throws -> SessionsGraphSession {
        try await Self.coding {
            guard !context.viewerIsExternal else {
                throw SessionsRefusal(.untrustedClient, SessionsGraphText.externalContinue)
            }
            _ = try context.actor(of: .continueExternalSession)
            let continueArguments = arguments.input.continueArguments(
                callerFolder: try await context.callerFolderOfDot())
            return SessionsGraphSession(
                try await SessionsToolContext.continueExternalSession(
                    continueArguments, with: context.externalSessionHost
                ).summary)
        }
    }

    /// Resolves `Mutation.rebuildExternalSessionIndex`: makes the index of one
    /// source again. An external client cannot rebuild the index. The host
    /// runs in the task of this resolver, so the cancellation of the call
    /// arrives at the host.
    ///
    /// - Parameters:
    ///   - context: The context of the call, which gives the host.
    ///   - arguments: The input object, with the source.
    /// - Returns: True when the host started the rebuild.
    /// - Throws: ``SessionsRefusal`` with the code `UNTRUSTED_CLIENT` for an
    ///   external client, `EXTERNAL_SESSIONS_UNAVAILABLE` when the endpoint
    ///   has no host, `BLANK_TEXT` for a blank source, `NO_SOURCE_ACCESS` for
    ///   a source that the host does not know or cannot read, and
    ///   `EXTERNAL_SESSION_FAILED` for a different error of the host;
    ///   `CancellationError`.
    func rebuildExternalSessionIndex(
        context: SessionsGraphContext, arguments: SessionsGraphMutationArguments<SessionsGraphRebuildExternalIndexInput>
    ) async throws -> Bool {
        try await Self.coding {
            guard !context.viewerIsExternal else {
                throw SessionsRefusal(.untrustedClient, SessionsGraphText.externalRebuild)
            }
            _ = try await SessionsToolContext.rebuildExternalSessionIndex(
                source: arguments.input.source, with: context.externalSessionHost)
            return true
        }
    }
}

// MARK: - The schema

extension SessionsGraphAPI {
    /// The text of the rule of the folder `.` of an external session field.
    private static let externalDotFolderRule =
        "For the agent, . is the folder of its session. A client has no session, so . gives INVALID_FOLDER."

    /// The text of the rule of each external session field with no host.
    private static let noExternalHostRule =
        "EXTERNAL_SESSIONS_UNAVAILABLE when this server has no index of the sessions of other agents."

    /// The text of the rule of a source with no access.
    private static let noExternalAccessRule =
        "NO_SOURCE_ACCESS when the user gave no access to the sessions of the source: only the user can give "
        + "access, with the command Allow Access."

    /// The `Query.externalSessions` field.
    ///
    /// - Returns: The field.
    static func externalSessionsField() -> SchemaField {
        Field("externalSessions", at: SessionsGraphResolver.externalSessions) {
            Argument("source", at: \.source).description("The source agent: claude-code or codex. None: each source.")
            Argument("folder", at: \.folder)
                .description(
                    "The absolute path of the working folder of the sessions. ~ expands. \(externalDotFolderRule) "
                        + "None: each folder.")
            Argument("automated", at: \.automated)
                .defaultValue(false)
                .description("True to also give the sessions that a program started. False: only the typed sessions.")
            Argument("first", at: \.first)
                .defaultValue(SessionsToolContext.defaultExternalSessionLimit)
                .description("The most sessions to give: 1 to \(SessionsToolContext.maximumExternalSessionLimit).")
            Argument("after", at: \.after)
                .description("The nextCursor of the page before, or no cursor for the first page.")
        }
        .description(
            "The sessions of other agents, such as Claude Code or Codex, from the index of this server, the newest "
                + "first. The query reads the index and never waits for it: the page has the sessions that the "
                + "index has now and its indexState. With a folder, the index reads the files of that folder first, "
                + "and externalSessionChanges gives the other sessions later. \(noExternalHostRule) "
                + "EXTERNAL_SESSION_FAILED when the list fails.")
    }

    /// The `Query.externalSessionCounts` field.
    ///
    /// - Returns: The field.
    static func externalSessionCountsField() -> SchemaField {
        Field("externalSessionCounts", at: SessionsGraphResolver.externalSessionCounts) {
            Argument("source", at: \.source).description("The source agent: claude-code or codex. None: each source.")
            Argument("folder", at: \.folder)
                .description(
                    "The absolute path of the working folder of the sessions. ~ expands. \(externalDotFolderRule) "
                        + "None: each folder.")
        }
        .description(
            "The numbers of the typed and the automated sessions of other agents in the index of this server, with "
                + "no pages. The query reads the index and never waits for it: the counts include only the "
                + "sessions that the index found, and indexState tells when they are final. \(noExternalHostRule) "
                + "EXTERNAL_SESSION_FAILED when the count fails.")
    }

    /// The `Subscription.externalSessionChanges` field.
    ///
    /// - Returns: The field.
    static func externalSessionChangesField() -> SchemaField {
        SubscriptionField(
            "externalSessionChanges",
            at: { (change: ExternalSessionChange) in
                { (_: SessionsGraphContext, _: SessionsGraphExternalChangesArguments) async throws
                    -> SessionsGraphExternalSessionChange in
                    SessionsGraphExternalSessionChange(change)
                }
            },
            atSub: SessionsGraphResolver.externalSessionChanges
        ) {
            Argument("folder", at: \.folder)
                .description(
                    "The absolute path of the working folder to follow. ~ expands. \(externalDotFolderRule) None: each "
                        + "folder.")
        }
        .description(
            "The changes of the index of the sessions of other agents: the sessions that the index added or changed, "
                + "the sessions whose files are gone, and the progress of the index. \(noExternalHostRule)")
    }

    /// The `Subscription.externalSessionUpdates` field.
    ///
    /// - Returns: The field.
    static func externalSessionUpdatesField() -> SchemaField {
        SubscriptionField(
            "externalSessionUpdates",
            at: { (batch: ExternalSessionUpdateBatch) in
                { (_: SessionsGraphContext, _: SessionsGraphExternalUpdatesArguments) async throws
                    -> SessionsGraphExternalSessionUpdateBatch in
                    try SessionsGraphExternalSessionUpdateBatch(batch)
                }
            },
            atSub: SessionsGraphResolver.externalSessionUpdates
        ) {
            Argument("source", at: \.source).description("The source agent: claude-code or codex.")
            Argument("id", at: \.id).description("The sourceId of the session, from externalSessions.")
        }
        .description(
            "The history of one session of another agent, in batches, oldest first, for a read-only view. The first "
                + "batches come while the read of the file continues, and the subscription ends after the last "
                + "batch. Nothing is written. Stop the subscription to stop the read. \(noExternalHostRule) "
                + "\(noExternalAccessRule) UNKNOWN_EXTERNAL_SESSION when the index has no such session, and "
                + "EXTERNAL_SESSION_FAILED when the read fails.")
    }

    /// The `ExternalSessionState` enum.
    ///
    /// - Returns: The enum.
    static func externalSessionStateEnum() -> SchemaType {
        Enum(SessionsGraphExternalSessionState.self, as: "ExternalSessionState") {
            Value(.found).description("The index found the file, and has not read it yet.")
            Value(.read).description("The index read the metadata of the file.")
            Value(.unreadable).description("The index cannot read the file.")
        }
        .description("How much of the file of an external session the index has read.")
    }

    /// The `ExternalSession` type.
    ///
    /// - Returns: The type.
    static func externalSessionType() -> SchemaType {
        Type(SessionsGraphExternalSession.self, as: "ExternalSession") {
            Field("source", at: \.source).description("The source agent, for example claude-code or codex.")
            Field("sourceId", at: \.sourceId)
                .description(
                    "The id of the session in the store of the source agent. continueExternalSession and "
                        + "externalSessionUpdates take it as id.")
            Field("path", at: \.path).description("The path of the file of the session, relative to the source root.")
            Field("filePath", at: \.filePath)
                .description(
                    "The absolute path of the file of the session, with the symbolic links resolved. Null when the "
                        + "file is not in the folder to which the user gave access.")
            Field("projectKey", at: \.projectKey)
                .description("The name of the project folder of the file, or null when the source has none.")
            Field("size", at: \.size).description("The size of the file, in bytes.")
            Field("modified", at: \.modified).description("The time of the last change of the file.")
            Field("cwd", at: \.cwd)
                .description("The absolute path of the working folder of the session, or null when it is not known.")
            Field("gitBranch", at: \.gitBranch).description("The git branch of the session, or null.")
            Field("isAutomated", at: \.isAutomated)
                .description("True when a program started the session. False for a session that a person typed.")
            Field("title", at: \.title).description("The title of the session, or null.")
            Field("firstPrompt", at: \.firstPrompt).description("The first prompt, cut short, or null.")
            Field("lastPrompt", at: \.lastPrompt).description("The last prompt, cut short, or null.")
            Field("firstDate", at: \.firstDate).description("The time of the first record, or null.")
            Field("lastDate", at: \.lastDate).description("The time of the last record, or null.")
            Field("state", at: \.state).description("How much of the file the index has read.")
            Field("displayText", at: \.displayText)
                .description(
                    "The text of the name of a row: the title, else the first prompt, else the last prompt. Null when "
                        + "the session has none: then the name of the row is displayDate.")
            Field("displayDate", at: \.displayDate)
                .description("The date of a row: lastDate, else modified.")
            Field("continuedSessions", at: \.continuedSessions)
                .description(
                    "The sessions of this server that continueExternalSession made from this session, the oldest "
                        + "first. Empty when no continue made a session.")
        }
        .description("One session of another agent in the index of this server. It is not a session of this server.")
    }

    /// The `ExternalSessionContinuation` type.
    ///
    /// - Returns: The type.
    static func externalSessionContinuationType() -> SchemaType {
        Type(SessionsGraphExternalSessionContinuation.self, as: "ExternalSessionContinuation") {
            Field("id", at: \.id)
                .description("The id of the session of this server that the continue made. session(id:) gives it.")
            Field("createdAt", at: \.createdAt).description("The time when the continue made the session.")
        }
        .description("One session of this server that a continue made from a session of another agent.")
    }

    /// The `ExternalSessionKey` type.
    ///
    /// - Returns: The type.
    static func externalSessionKeyType() -> SchemaType {
        Type(SessionsGraphExternalSessionKey.self, as: "ExternalSessionKey") {
            Field("source", at: \.source).description("The source agent.")
            Field("sourceId", at: \.sourceId).description("The id of the session in the store of the source agent.")
        }
        .description("The identity of one session of another agent.")
    }

    /// The `ExternalSessionIndexState` type.
    ///
    /// - Returns: The type.
    static func externalIndexStateType() -> SchemaType {
        Type(SessionsGraphExternalIndexState.self, as: "ExternalSessionIndexState") {
            Field("filesFound", at: \.filesFound).description("The number of session files that the index found.")
            Field("filesRead", at: \.filesRead)
                .description("The number of session files that the index read, or cannot read.")
            Field("isComplete", at: \.isComplete).description("True when the index read each file that it found.")
        }
        .description("The progress of the index of the sessions of other agents.")
    }

    /// The `ExternalSessionPage` type.
    ///
    /// - Returns: The type.
    static func externalSessionPageType() -> SchemaType {
        Type(SessionsGraphExternalSessionPage.self, as: "ExternalSessionPage") {
            Field("sessions", at: \.sessions).description("The sessions of the page, the newest first.")
            Field("indexState", at: \.indexState)
                .description("The progress of the index of each root when the page was made.")
            Field("folderIndexState", at: \.folderIndexState)
                .description(
                    "The progress of the index for the files of the folder of the query when the page was made, "
                        + "or null for a query with no folder.")
            Field("nextCursor", at: \.nextCursor)
                .description("The cursor of the next page, or null when this page is the last.")
            Field("unreadableSources", at: \.unreadableSources)
                .description(
                    "The source agents whose sessions this server cannot read: the user gave no access to their "
                        + "folder. Only the user can give access, with the command Allow Access.")
        }
        .description("One page of the sessions of other agents.")
    }

    /// The `ExternalSessionCounts` type.
    ///
    /// - Returns: The type.
    static func externalSessionCountsType() -> SchemaType {
        Type(SessionsGraphExternalSessionCounts.self, as: "ExternalSessionCounts") {
            Field("typedCount", at: \.typedCount).description("The number of the sessions that a person typed.")
            Field("automatedCount", at: \.automatedCount)
                .description("The number of the sessions that a program started.")
            Field("indexState", at: \.indexState)
                .description(
                    "The progress of the index for the scope of the counts. When isComplete is true, the counts are "
                        + "final.")
        }
        .description("The counts of the sessions of other agents that the index has now, for one scope.")
    }

    /// The `ExternalSessionChange` type.
    ///
    /// - Returns: The type.
    static func externalSessionChangeType() -> SchemaType {
        Type(SessionsGraphExternalSessionChange.self, as: "ExternalSessionChange") {
            Field("changed", at: \.changed).description("The sessions that the index added or changed.")
            Field("removed", at: \.removed).description("The sessions whose files are gone.")
            Field("indexState", at: \.indexState)
                .description("The progress of the index of each root after the change.")
            Field("folderIndexState", at: \.folderIndexState)
                .description(
                    "The progress of the index for the files of the followed folder after the change, or null "
                        + "for a stream of each folder.")
        }
        .description("One change of the index of the sessions of other agents.")
    }

    /// The `ExternalSessionEntry` type.
    ///
    /// - Returns: The type.
    static func externalSessionEntryType() -> SchemaType {
        Type(SessionsGraphExternalSessionEntry.self, as: "ExternalSessionEntry") {
            Field("kind", at: \.kind).description("The kind of the entry, for example user_message_chunk or tool_call.")
            Field("timestamp", at: \.timestamp).description("The time of the entry.")
            Field("payload", at: \.payload).description("The content of the entry.")
        }
        .description("One entry of the history of a session of another agent.")
    }

    /// The `ExternalSessionUpdateBatch` type.
    ///
    /// - Returns: The type.
    static func externalSessionUpdateBatchType() -> SchemaType {
        Type(SessionsGraphExternalSessionUpdateBatch.self, as: "ExternalSessionUpdateBatch") {
            Field("entries", at: \.entries).description("The entries of the batch, oldest first.")
        }
        .description("One batch of the history of a session of another agent.")
    }

    /// The `ContinueExternalSessionInput` input object.
    ///
    /// - Returns: The input object.
    static func continueExternalInput() -> SchemaType {
        Input(SessionsGraphContinueExternalInput.self, as: SessionsGraphMutation.continueExternalSession.inputName) {
            InputField("source", at: \.source).description("The source agent: claude-code or codex.")
            InputField("id", at: \.id).description("The sourceId of the session, from externalSessions.")
            InputField("folder", at: \.folder)
                .description(
                    "The absolute path of the folder of the new session. ~ expands. \(externalDotFolderRule) None: "
                        + "the working folder of the source session.")
            InputField("name", at: \.name)
                .description(
                    "The name of the new session. None: the default name. A name that a session of the folder has "
                        + "gets the next free number.")
        }
        .description("The session of another agent to continue, and the folder and the name of the new session.")
    }

    /// The field of the `continueExternalSession` mutation.
    ///
    /// - Returns: The field.
    static func continueExternalMutationField() -> SchemaField {
        mutationField(
            .continueExternalSession, at: SessionsGraphResolver.continueExternalSession,
            input: "The source session, and the folder and the name of the new session.",
            description: "Continues a session of another agent, such as Claude Code or Codex, in a new session with "
                + "its full history. The source does not change. Each call makes a new session, also when the "
                + "source was continued before. Gives the new session. An external client cannot continue a "
                + "session. \(noExternalHostRule) \(noExternalAccessRule) UNKNOWN_EXTERNAL_SESSION when the index "
                + "has no such session, FOLDER_UNAVAILABLE when the folder does not exist or this server cannot "
                + "write it, and EXTERNAL_SESSION_FAILED when the copy fails.")
    }

    /// The field of the `rebuildExternalSessionIndex` mutation.
    ///
    /// - Returns: The field.
    static func rebuildExternalIndexMutationField() -> SchemaField {
        mutationField(
            .rebuildExternalIndex, at: SessionsGraphResolver.rebuildExternalSessionIndex,
            input: "The source whose index to rebuild.",
            description: "Rebuilds the index of the sessions of one other agent. The index removes the sessions of "
                + "the source, and then finds and reads each session file of the source again. The call returns true "
                + "when the new find starts, not when the read ends: externalSessionChanges gives the removed "
                + "sessions and then the new sessions. An external client cannot rebuild the index. "
                + "\(noExternalHostRule) NO_SOURCE_ACCESS when this server does not know the source or the user gave "
                + "no access to its sessions: only the user can give access, with the command Allow Access. "
                + "EXTERNAL_SESSION_FAILED when the rebuild fails.")
    }

    /// The `RebuildExternalSessionIndexInput` input object.
    ///
    /// - Returns: The input object.
    static func rebuildExternalIndexInput() -> SchemaType {
        Input(SessionsGraphRebuildExternalIndexInput.self, as: SessionsGraphMutation.rebuildExternalIndex.inputName) {
            InputField("source", at: \.source).description("The source agent: claude-code or codex.")
        }
        .description("The source agent whose index of sessions to rebuild.")
    }
}
