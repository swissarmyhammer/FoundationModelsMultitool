// The GraphQL schema of the `sessions` endpoint (MT-10): the context, the
// resolver and the Graphiti API over one `SessionDirectory`.
//
// Each resolver reads the directory through the `SessionsVisibility` of the
// call, thus a session that the viewer cannot see never shows: a list leaves
// it out, and one session is `null` (EXTRAS-9 rules 4 and 5).

import Foundation
import FoundationModelsExtras
import GraphQL
import Graphiti
import ULID

// MARK: - Context and resolver

/// The context of one call of the `sessions` endpoint.
struct SessionsGraphContext: GraphQLRunContext {
    /// The warnings of the call.
    let warnings = ResponseWarnings()

    /// The sessions of the directory as the viewer of the call sees them.
    let sessions: SessionsVisibility

    /// The change feed of the endpoint, for the `cursor` query and the
    /// `changes` subscription. A subscription holds it through its context.
    let changes: SessionsGraphChangeFeed

    /// The exporter of the transcripts that the host gave the endpoint, or
    /// `nil` when no host gave one. `Session.export` reads it.
    let exporter: (any SessionTranscriptExporter)?

    /// The searcher of the transcripts that the host gave the endpoint, or
    /// `nil` when no host gave one. `Query.searchSessions` reads it.
    let searcher: (any SessionTranscriptSearcher)?

    /// The sharer that the endpoint keeps, or `nil` when no host gave one.
    /// `Session.share` and the share mutations read it.
    let sharer: (any SessionSharer)?

    /// The importer of the sessions of other agents that the host gave the
    /// endpoint, or `nil` when no host gave one. `Query.importableSessions`
    /// and `Mutation.importSession` read it.
    let importer: (any SessionImporter)?

    /// The host of the external sessions that the host gave the endpoint, or
    /// `nil` when no host gave one. `Query.externalSessions`,
    /// `Subscription.externalSessionChanges`,
    /// `Subscription.externalSessionUpdates` and
    /// `Mutation.continueExternalSession` read it (D212).
    let externalSessionHost: (any ExternalSessionHost)?
}

/// The root resolver of the `sessions` endpoint. It holds no state: each
/// resolver reads the directory through the context of the call.
struct SessionsGraphResolver: Sendable {
    /// The most sessions that `Query.sessions` gives when its filter names
    /// no limit (session.md section 11.2).
    static let defaultListLimit = 50

    /// Resolves `Query.sessions`.
    ///
    /// - Parameters:
    ///   - context: The context of the call, which gives the visibility.
    ///   - arguments: The filter.
    /// - Returns: The sessions that match the filter and that the viewer can
    ///   see, the newest first.
    /// - Throws: A ``SessionsRefusal`` for a filter that the endpoint cannot
    ///   read, or an error of the directory.
    func sessions(
        context: SessionsGraphContext, arguments: SessionsGraphSessionsArguments
    ) async throws -> [SessionsGraphSession] {
        let query = try (arguments.filter ?? SessionsGraphFilter()).query()
        return try await context.sessions.sessions(matching: query).map(SessionsGraphSession.init)
    }

    /// Resolves `Query.session`.
    ///
    /// - Parameters:
    ///   - context: The context of the call, which gives the visibility.
    ///   - arguments: The session id.
    /// - Returns: The session, or `nil` when no session has the id or the
    ///   viewer cannot see it.
    /// - Throws: ``SessionsRefusal`` for an id that is not a session id, or
    ///   an error of the directory.
    func session(
        context: SessionsGraphContext, arguments: SessionsGraphSessionArguments
    ) async throws -> SessionsGraphSession? {
        try await SessionsGraphSession.visible(SessionsGraphInput.sessionID(arguments.id), in: context)
    }

    /// Resolves `Query.inbox`: the unread messages to a session, the oldest
    /// first. The query never marks a message read (D72): only the `read
    /// inbox` op of the `sessions` tool does, because only the target
    /// session reads its inbox to act on it.
    ///
    /// - Parameters:
    ///   - context: The context of the call, which gives the visibility.
    ///   - arguments: The session id and the limit.
    /// - Returns: The messages, at most the limit of them, or none when no
    ///   session has the id or the viewer cannot see it.
    /// - Throws: ``SessionsRefusal`` for an id that is not a session id, or
    ///   an error of the directory.
    func inbox(
        context: SessionsGraphContext, arguments: SessionsGraphInboxArguments
    ) async throws -> [SessionsGraphMessage] {
        let id = try SessionsGraphInput.sessionID(arguments.sessionId)
        guard let target = try await SessionsGraphSession.visible(id, in: context) else {
            return []
        }
        let limit = SessionsToolInput.listLimit(arguments.limit, defaultingTo: Self.defaultListLimit)
        let messages = try await context.sessions.directory.inbox(of: id, markRead: false)
        return messages.prefix(limit).map { SessionsGraphMessage($0, to: target) }
    }
}

extension SessionsGraphSession {
    /// The session `id` as an object, when the viewer of the call can see
    /// it.
    ///
    /// - Parameters:
    ///   - id: The session id, or `nil`.
    ///   - context: The context of the call.
    /// - Returns: The session, or `nil` for no id, an id that no session has,
    ///   or a session that the viewer cannot see.
    /// - Throws: An error of the directory.
    static func visible(_ id: ULID?, in context: SessionsGraphContext) async throws -> SessionsGraphSession? {
        guard let id else {
            return nil
        }
        return try await context.sessions.summary(of: id).map(SessionsGraphSession.init)
    }

    /// Resolves `Session.parent`: the parent of a subagent, or the original
    /// of a fork.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: No argument.
    /// - Returns: The session, or `nil` when there is none or the viewer
    ///   cannot see it.
    /// - Throws: An error of the directory.
    func parent(context: SessionsGraphContext, arguments _: NoArguments) async throws -> SessionsGraphSession? {
        try await Self.visible(parentID, in: context)
    }

    /// Resolves `Session.startedBy`: the session that started this root
    /// session.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: No argument.
    /// - Returns: The session, or `nil` when there is none or the viewer
    ///   cannot see it.
    /// - Throws: An error of the directory.
    func startedBy(context: SessionsGraphContext, arguments _: NoArguments) async throws -> SessionsGraphSession? {
        try await Self.visible(starterID, in: context)
    }

    /// Resolves `Session.children`: the subagents of this session, live or
    /// not, the newest first. A fork is not a child.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: No argument.
    /// - Returns: The subagents that the viewer can see.
    /// - Throws: An error of the directory.
    func children(context: SessionsGraphContext, arguments _: NoArguments) async throws -> [SessionsGraphSession] {
        let query = SessionQuery(
            kind: .subagent, parentID: sessionID, includesRecorded: true, limit: SessionsVisibility.unboundedLimit)
        return try await context.sessions.sessions(matching: query).map(SessionsGraphSession.init)
    }

    /// Resolves `Session.ownedByViewer` (D11): the client of the call owns
    /// the session now, in the owner registry that the host reads into the
    /// viewer. The agent, a call with no viewer, is no client: it owns no
    /// session.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: No argument.
    /// - Returns: `true` when the viewer owns the session.
    func ownedByViewer(context: SessionsGraphContext, arguments _: NoArguments) -> Bool {
        context.sessions.viewer?.owns(sessionID.ulidString) ?? false
    }

    /// Resolves `Session.hasOwner`: a client, the client of the call or
    /// another one, owns the session now. The agent, a call with no viewer,
    /// reads no owner registry: it reads `false`.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: No argument.
    /// - Returns: `true` when a client owns the session.
    func hasOwner(context: SessionsGraphContext, arguments _: NoArguments) -> Bool {
        context.sessions.viewer?.clientOwnedSessions.contains(sessionID.ulidString) ?? false
    }

    /// Resolves `Session.export` (D202 (g)): the text of the transcript of
    /// this session from the exporter of the endpoint. It writes no file: a
    /// client can be on a different Mac, so the client saves the text.
    ///
    /// The viewer can see this session, because a `Session` object shows
    /// only a session that the viewer can see.
    ///
    /// - Parameters:
    ///   - context: The context of the call, which gives the exporter.
    ///   - arguments: The format and the thoughts option.
    /// - Returns: The text.
    /// - Throws: ``SessionsRefusal`` with the code `MISSING_EXPORTER` when
    ///   the endpoint has no exporter, or `EXPORT_FAILED` when the exporter
    ///   fails; each with the corrective of the `export session` operation.
    func export(context: SessionsGraphContext, arguments: SessionsGraphExportArguments) async throws -> String {
        let exporter = try SessionsToolContext.requiredExporter(context.exporter)
        return try await SessionsToolContext.transcript(
            of: sessionID, from: exporter, format: (arguments.format ?? .markdown).format,
            includeThoughts: arguments.thoughts ?? false)
    }

    /// Resolves `Session.unreadCount`: the count of the unread messages to
    /// this session. It marks none read.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: No argument.
    /// - Returns: The count, or 0 when the directory no longer holds the
    ///   session.
    /// - Throws: Each other error of the directory.
    func unreadCount(context: SessionsGraphContext, arguments _: NoArguments) async throws -> Int {
        do {
            return try await context.sessions.directory.inbox(of: sessionID, markRead: false).count
        } catch SessionDirectoryError.unknownSession(let missing) where missing == sessionID {
            return 0
        }
    }
}

extension SessionsGraphSender {
    /// Resolves `Sender.session`: the sending session.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: No argument.
    /// - Returns: The session, or `nil` for a message from a user, or for a
    ///   session that the viewer cannot see.
    /// - Throws: An error of the directory.
    func session(context: SessionsGraphContext, arguments _: NoArguments) async throws -> SessionsGraphSession? {
        try await SessionsGraphSession.visible(sessionID, in: context)
    }
}

// MARK: - Arguments

extension SessionsGraphFilter {
    /// The directory query of this filter, with the rules of `list sessions`.
    ///
    /// - Returns: The query.
    /// - Throws: ``SessionsRefusal`` for a relative `cwd`, or for an id that
    ///   is not a session id.
    func query() throws(SessionsRefusal) -> SessionQuery {
        let filter = SessionQuery(
            workingDirectory: try SessionsToolInput.folder(cwd),
            agentID: agentId,
            tag: tag,
            kind: kind?.kind,
            state: state?.state,
            parentID: try parentId.map(SessionsGraphInput.sessionID),
            startedBy: try startedById.map(SessionsGraphInput.sessionID))
        return SessionsToolInput.listQuery(
            filter, includeRecorded: includeRecorded, limit: limit,
            defaultingTo: SessionsGraphResolver.defaultListLimit)
    }
}

/// The readers of the arguments of the `sessions` endpoint: the readers of
/// the `sessions` tool, whose refusals are the coded errors of the endpoint.
enum SessionsGraphInput {
    /// The session id of an id argument, in any letter case, as the
    /// `sessions` tool reads it.
    ///
    /// - Parameter id: The id argument.
    /// - Returns: The session id.
    /// - Throws: ``SessionsRefusal`` with the code `INVALID_SESSION_ID` when
    ///   the id is not a session id.
    static func sessionID(_ id: ToolkitID) throws(SessionsRefusal) -> ULID {
        try SessionsToolInput.sessionID(id.text)
    }
}

// MARK: - The API

/// The Graphiti engine of the `sessions` endpoint.
struct SessionsGraphAPI: API {
    /// The schema of the endpoint, built once. It does not depend on a
    /// directory: the context of a call holds the directory.
    static let builtSchema = Result { try makeSchema() }

    /// The root resolver.
    let resolver = SessionsGraphResolver()

    /// The schema.
    let schema: Schema<SessionsGraphResolver, SessionsGraphContext>

    /// One type of the schema: an enum, an object type or an input object.
    typealias SchemaType = TypeComponent<SessionsGraphResolver, SessionsGraphContext>

    /// One root field of the schema: a query, a mutation or a subscription.
    typealias SchemaField = FieldComponent<SessionsGraphResolver, SessionsGraphContext>

    /// Builds the schema of the endpoint. The mutations and their types are
    /// in `SessionsGraphMutations.swift`, the `share` field of a session, the
    /// share mutations and their types are in `SessionsGraphShare.swift`,
    /// the `sessionPage` query and its
    /// type are in `SessionsGraphPages.swift`, the `searchSessions` query and
    /// its types are in `SessionsGraphSearch.swift`, the `importableSessions`
    /// query, the `importSession` mutation and their types are in
    /// `SessionsGraphImport.swift`, the `externalSessions` query, the
    /// `externalSessionChanges` and `externalSessionUpdates` subscriptions,
    /// the `continueExternalSession` mutation and their types are in
    /// `SessionsGraphExternal.swift`, and the `cursor` query, the
    /// `changes` subscription and its type are in `SessionsGraphChanges.swift`.
    ///
    /// - Returns: The schema.
    /// - Throws: An error of the schema builder.
    private static func makeSchema() throws -> Schema<SessionsGraphResolver, SessionsGraphContext> {
        try SchemaBuilder(SessionsGraphResolver.self, SessionsGraphContext.self)
            .addToolkitScalars()
            .addToolkitIDScalar()
            .add {
                kindEnum()
                stateEnum()
                originEnum()
                outcomeEnum()
                exportFormatEnum()
                sessionType()
                senderType()
                messageType()
                receiptType()
                filterInput()
                sessionPageType()
                searchHitKindEnum()
                textRangeType()
                searchHitType()
                searchResultType()
                searchConnectionType()
                startInput()
                tagInput()
                untagInput()
                renameInput()
                pinInput()
                unpinInput()
                archiveInput()
                unarchiveInput()
                forkInput()
                sendInput()
                replyInput()
                shareOptionsType()
                shareType()
                shareOptionsInput()
                shareInput()
                updateShareInput()
                stopSharingInput()
                changeType()
                importableSessionType()
                previousImportType()
                importProvenanceType()
                importableSessionPageType()
                importInput()
                externalSessionStateEnum()
                externalSessionType()
                externalSessionKeyType()
                externalIndexStateType()
                externalSessionPageType()
                externalSessionChangeType()
                externalSessionEntryType()
                externalSessionUpdateBatchType()
                continueExternalInput()
            }
            .addQuery {
                sessionsField()
                sessionPageField()
                searchSessionsField()
                sessionField()
                inboxField()
                pinnedSessionsField()
                recentSessionsField()
                cursorField()
                importableSessionsField()
                externalSessionsField()
            }
            .addMutation(mutationFields)
            .addSubscription {
                changesField()
                externalSessionChangesField()
                externalSessionUpdatesField()
            }
            .build()
    }

    // MARK: Queries

    /// The `Query.sessions` field.
    ///
    /// - Returns: The field.
    private static func sessionsField() -> FieldComponent<SessionsGraphResolver, SessionsGraphContext> {
        Field("sessions", at: SessionsGraphResolver.sessions) {
            Argument("filter", at: \.filter).description("The filter. With no filter, each live session.")
        }
        .description(
            "The sessions on this server that match the filter, the newest first. An external client sees only "
                + "the sessions that it owns or that its connection started, their subagents, and the sessions "
                + "that they started.")
    }

    /// The `Query.session` field.
    ///
    /// - Returns: The field.
    private static func sessionField() -> FieldComponent<SessionsGraphResolver, SessionsGraphContext> {
        Field("session", at: SessionsGraphResolver.session) {
            Argument("id", at: \.id).description("The session id, in any letter case.")
        }
        .description("One session, or null when no session that you can see has the id.")
    }

    /// The `Query.inbox` field.
    ///
    /// - Returns: The field.
    private static func inboxField() -> FieldComponent<SessionsGraphResolver, SessionsGraphContext> {
        Field("inbox", at: SessionsGraphResolver.inbox) {
            Argument("sessionId", at: \.sessionId).description("The session whose messages to read.")
            Argument("limit", at: \.limit)
                .defaultValue(SessionsGraphResolver.defaultListLimit)
                .description("The most messages to give: 1 to \(SessionsToolInput.maximumListLimit).")
        }
        .description(
            "The unread messages to a session, the oldest first. The query does not mark them read: only the "
                + "session itself reads its inbox. A session that you cannot see gives none.")
    }

    // MARK: Enums

    /// The `SessionKind` enum.
    ///
    /// - Returns: The enum.
    private static func kindEnum() -> SchemaType {
        Enum(SessionsGraphKind.self, as: "SessionKind") {
            Value(.root).description("A root session: a client, another session, a message or a trigger started it.")
            Value(.subagent).description("A subagent: the agents tool of its parent started it.")
            Value(.fork).description("A fork: a user forked another session.")
        }
        .description("The kind of a session.")
    }

    /// The `SessionState` enum.
    ///
    /// - Returns: The enum.
    private static func stateEnum() -> SchemaType {
        Enum(SessionsGraphState.self, as: "SessionState") {
            Value(.working).description("The session runs a turn.")
            Value(.needsInput).description("The session waits for an answer: an elicitation or a permission.")
            Value(.idle).description("The session runs no turn. A message to it starts a turn.")
            Value(.archived).description(
                "The session is archived: hidden from the lists, not live. `unarchiveSession` brings it back.")
        }
        .description("The work state of a session.")
    }

    /// The `SessionOrigin` enum.
    ///
    /// - Returns: The enum.
    private static func originEnum() -> SchemaType {
        Enum(SessionsGraphOrigin.self, as: "SessionOrigin") {
            Value(.client).description("A client started it.")
            Value(.tool).description("The sessions tool of another session started it.")
            Value(.message).description("A message to an agent with no session started it.")
            Value(.trigger).description("A trigger, for example of a kanban task, started it.")
            Value(.fork).description("A user forked another session.")
            Value(.import).description("An import of a session of another agent made it.")
        }
        .description("How a session started.")
    }

    /// The `SessionExportFormat` enum.
    ///
    /// - Returns: The enum.
    private static func exportFormatEnum() -> SchemaType {
        Enum(SessionsGraphExportFormat.self, as: "SessionExportFormat") {
            Value(.markdown).description("A Markdown document.")
        }
        .description("The format of the text of an export of a session.")
    }

    // MARK: Object types and input objects

    /// The `Session` type.
    ///
    /// - Returns: The type.
    private static func sessionType() -> SchemaType {
        Type(SessionsGraphSession.self, as: "Session") {
            Field("id", at: \.id).description("The session id: a ULID.")
            Field("shortId", at: \.shortId)
                .description("The short id: the last 7 characters of the session id, in lower case. It never changes.")
            Field("slug", at: \.slug)
                .description(
                    "The slug of the name of the session. It changes with a rename. With no name: the short id.")
            Field("agentId", at: \.agentId).description("The id of the agent in the agent catalog.")
            Field("agentName", at: \.agentName).description("The display name of the agent, or null.")
            Field("cwd", at: \.cwd).description("The absolute path of the working folder.")
            Field("title", at: \.title).description("The title, or null when no user or session gave one.")
            Field("tags", at: \.tags).description("The tags, sorted.")
            Field("kind", at: \.kind).description("The kind of the session.")
            Field("state", at: \.state).description("The work state of the session.")
            Field("origin", at: \.origin).description("How the session started.")
            Field("parent", at: SessionsGraphSession.parent)
                .description("A subagent: its parent. A fork: the original. Else, or when you cannot see it, null.")
            Field("startedBy", at: SessionsGraphSession.startedBy)
                .description("The session that started this root session, or null.")
            Field("children", at: SessionsGraphSession.children)
                .description("The subagents of this session, live or not, the newest first.")
            Field("createdAt", at: \.createdAt).description("The time the session started.")
            Field("updatedAt", at: \.updatedAt).description("The time of the last change of its facts or state.")
            Field("lastSummary", at: \.lastSummary).description("The last final message, cut short, or null.")
            Field("recap", at: \.recap)
                .description("One sentence about what the session did and where it stands now, or null.")
            Field("recapAt", at: \.recapAt)
                .description("The time of the recap, or null when the session has no recap.")
            Field("isLive", at: \.isLive).description("True when the session is in memory now.")
            Field("pinned", at: \.pinned).description("True when the session is in the Pinned list of this server.")
            Field("pinnedAt", at: \.pinnedAt)
                .description("The time of the pin, or null when the session is not pinned.")
            Field("lastUsedAt", at: \.lastUsedAt)
                .description("The last time that a client opened the session on this server, or null.")
            Field("archivedAt", at: \.archivedAt)
                .description("The time of the archive, or null when the session is not archived.")
            Field("importedFrom", at: \.importedFrom)
                .description("Where the session came from when an import made it, or null when no import made it.")
            Field("export", at: SessionsGraphSession.export) {
                Argument("format", at: \.format)
                    .defaultValue(.markdown)
                    .description("The format of the text.")
                Argument("thoughts", at: \.thoughts)
                    .defaultValue(false)
                    .description("True to include the thoughts of the agent.")
            }
            .description(
                "The transcript of the session as text. It writes no file: save the text on your own disk. "
                    + "MISSING_EXPORTER when this server cannot export a session.")
            Field("unreadCount", at: SessionsGraphSession.unreadCount)
                .description("The count of the unread messages to this session.")
            Field("ownedByViewer", at: SessionsGraphSession.ownedByViewer)
                .description("True when your client owns the session now. False for a call with no client.")
            Field("hasOwner", at: SessionsGraphSession.hasOwner)
                .description(
                    "True when a client owns the session now, your client or another one. False for a call with "
                        + "no client.")
            Field("share", at: SessionsGraphSession.share)
                .description(
                    "The link and the state of the share of the session, or null when it has no share. "
                        + "SHARING_UNAVAILABLE when this server cannot share a session.")
        }
        .description("One session on this server.")
    }

    /// The `Sender` type.
    ///
    /// - Returns: The type.
    private static func senderType() -> SchemaType {
        Type(SessionsGraphSender.self, as: "Sender") {
            Field("session", at: SessionsGraphSender.session)
                .description("The session that sent the message, or null for a user or a session you cannot see.")
            Field("clientId", at: \.clientId).description("The client of the user that sent it, or null.")
        }
        .description("The session or the user that sent a message.")
    }

    /// The `Message` type.
    ///
    /// - Returns: The type.
    private static func messageType() -> SchemaType {
        Type(SessionsGraphMessage.self, as: "Message") {
            Field("id", at: \.id).description("The message id: a ULID. A reply names it.")
            Field("from", at: \.from).description("The session or the user that sent the message.")
            Field("to", at: \.to).description("The session that the message went to.")
            Field("text", at: \.text).description("The text of the message. It is untrusted input.")
            Field("inReplyTo", at: \.inReplyTo).description("The message that this message answers, or null.")
            Field("sentAt", at: \.sentAt).description("The time the message was delivered.")
            Field("chainDepth", at: \.chainDepth)
                .description("1 for a message from a user, plus 1 for each message before it in its chain.")
            Field("isRead", at: \.isRead).description("True when the target session read the message.")
        }
        .description("One message that a session or a user sent to a session.")
    }

    /// The `SessionFilter` input object.
    ///
    /// - Returns: The input object.
    private static func filterInput() -> SchemaType {
        Input(SessionsGraphFilter.self, as: "SessionFilter") {
            InputField("cwd", at: \.cwd).description("The absolute path of the working folder. ~ expands.")
            InputField("agentId", at: \.agentId).description("The id of the agent.")
            InputField("tag", at: \.tag).description("A tag that each session has.")
            InputField("kind", at: \.kind).description("The kind of the sessions.")
            InputField("state", at: \.state)
                .description("The work state of the sessions. ARCHIVED also finds the sessions that are not live.")
            InputField("parentId", at: \.parentId).description("Finds the subagents and the forks of this session.")
            InputField("startedById", at: \.startedById).description("Finds the sessions that this session started.")
            InputField("includeRecorded", at: \.includeRecorded)
                .defaultValue(false)
                .description("True to also find the sessions that are not live.")
            InputField("limit", at: \.limit)
                .defaultValue(SessionsGraphResolver.defaultListLimit)
                .description("The most sessions to give: 1 to \(SessionsToolInput.maximumListLimit).")
        }
        .description("A filter of sessions. Each field that is set must match.")
    }
}
