// The mutations of the `sessions` GraphQL endpoint (MT-10, EXTRAS-9 rule 7):
// `startSession`, `tagSession`, `untagSession`, `renameSession`,
// `pinSession`, `unpinSession`, `archiveSession`, `unarchiveSession`,
// `forkSession`, `sendMessage` and `replyMessage`. The share mutations
// `shareSession`, `updateSessionShare` and `stopSharingSession` are in
// `SessionsGraphShare.swift`, and the `importSession` mutation is in
// `SessionsGraphImport.swift`.
//
// Each mutation has the name of the code-mode verb of a tool op of the
// `sessions` tool, or a name that tells its session when that verb does not
// (`updateSessionShare` for `updateShare`), and calls the work of that op in
// ``SessionsToolContext``:
// the op and the mutation change the directory the same way, and refuse a
// call with the same corrective (session.md section 11.4). The `id` of each
// change of one session reads `<id>`, `@<id>`, `<short id>`, `@<short id>`
// and `@<slug>` with the reader of its tool op (D200 (e)). A ``SessionsRefusal``
// is a coded error with that corrective; an id that the directory does not
// hold, or that the viewer cannot see, is the `NOT_FOUND` of the toolkit.
//
// Who acts (section 11.3): a client acts as its user, `user(clientID)`, and a
// call with no viewer acts as the agent of the caller session, as the tool
// does. An external client archives and unarchives only the sessions that it
// can see; it
// tags, untags, renames, pins, unpins, forks, shares, sends and replies only
// to the sessions that it owns;
// and it cannot start or import a session.

import Foundation
import FoundationModelsExtras
import GraphQL
import Graphiti
import Operations
import ULID

// MARK: - Names

/// One mutation of the endpoint, and the tool op whose rules it shares.
///
/// The name of the mutation is the code-mode verb of the op
/// (`tools.sessions.startSession` and `startSession`), or a name of the form
/// `verbNoun` that a mutation gives in its place. The alias tables take the
/// bare verb of the op for the mutation, the code-mode verb of the op for a
/// mutation of a different name, and the names of the parameters of the op,
/// and their aliases, for the fields of its input object.
struct SessionsGraphMutation: Sendable {
    /// The end of the name of the input object of a mutation.
    private static let inputSuffix = "Input"

    /// The aliases of the `id` of an input object that names a session.
    private static let sessionIDAliases = ["id": ["sessionId"]]

    /// `startSession`: its input calls the agent `agentId`.
    static let start = Self(StartSession.self, renaming: ["agent": "agentId"])

    /// `tagSession`.
    static let tag = Self(TagSession.self, adding: sessionIDAliases)

    /// `untagSession`.
    static let untag = Self(UntagSession.self, adding: sessionIDAliases)

    /// `renameSession`.
    static let rename = Self(RenameSession.self, adding: sessionIDAliases)

    /// `pinSession` (D118).
    static let pin = Self(PinSession.self, adding: sessionIDAliases)

    /// `unpinSession` (D118).
    static let unpin = Self(UnpinSession.self, adding: sessionIDAliases)

    /// `archiveSession`.
    static let archive = Self(ArchiveSession.self, adding: sessionIDAliases)

    /// `unarchiveSession` (D204).
    static let unarchive = Self(UnarchiveSession.self, adding: sessionIDAliases)

    /// `forkSession` (D205).
    static let fork = Self(ForkSession.self, adding: sessionIDAliases)

    /// `sendMessage`: its input has the source session, which the op does
    /// not have (D199 (f)).
    static let send = Self(SendMessage.self, adding: ["fromSession": ["fromSessionId", "from_session"]])

    /// `replyMessage`.
    static let reply = Self(ReplyMessage.self)

    /// The name of the parameter of a session in each share op.
    private static let sessionParameter = "id"

    /// `shareSession` (D208 (k)): its input has the session and the
    /// options object, whose fields are the other parameters of the op.
    static let share = Self(ShareSession.self, keeping: { $0 == sessionParameter })

    /// `updateSessionShare` (D208 (k)), the mutation of `updateShare`.
    static let updateShare = Self(UpdateShare.self, named: "updateSessionShare")

    /// `stopSharingSession` (D208 (k)), the mutation of `stopSharing`.
    static let stopSharing = Self(StopSharing.self, named: "stopSharingSession")

    /// `importSession` (D209 (l)).
    static let importSession = Self(ImportSession.self)

    /// Each mutation of the endpoint.
    static let all = [
        start, tag, untag, rename, pin, unpin, archive, unarchive, fork, send, reply, share, updateShare, stopSharing,
        importSession,
    ]

    /// The name of the input object of the options of `shareSession`.
    static let shareOptionsInputName = "SessionShareOptionsInput"

    /// The aliases of the fields of ``shareOptionsInputName``: the names of
    /// the option parameters of `share session`, and their aliases.
    static let shareOptionsAliases = inputAliases(
        of: ShareSession.self, renaming: ["thoughts": "includeThoughts", "toolOutput": "includeToolOutput"],
        keeping: { $0 != sessionParameter })

    /// The tool op of the mutation. The module name tells it from the
    /// `OperationDefinition` of GraphQL.
    let operation: any Operations.OperationDefinition.Type

    /// The name of the mutation: the code-mode verb of the op, or the name
    /// that the mutation gives in its place.
    let name: String

    /// The aliases of the fields of the input object, by the field name.
    let inputAliases: [String: [String]]

    /// Makes a mutation of a tool op.
    ///
    /// - Parameters:
    ///   - operation: The tool op.
    ///   - name: The name of the mutation, or `nil` for the code-mode verb of
    ///     the op.
    ///   - renaming: The input field of each parameter of the op whose
    ///     name differs; the name of the parameter becomes an alias.
    ///   - adding: The aliases of the input object that the op does not have.
    ///   - keeping: Tells if the input object has the field of a parameter.
    ///     The default keeps each parameter.
    private init(
        _ operation: any Operations.OperationDefinition.Type,
        named name: String? = nil,
        renaming: [String: String] = [:],
        adding: [String: [String]] = [:],
        keeping: (String) -> Bool = { _ in true }
    ) {
        self.operation = operation
        self.name = name ?? OperationVerbTool.verbName(for: operation.opString)
        inputAliases = Self.inputAliases(of: operation, renaming: renaming, keeping: keeping)
            .merging(adding, uniquingKeysWith: +)
    }

    /// The aliases of the fields of an input object whose fields are
    /// parameters of a tool op: the name of each parameter and its aliases,
    /// less the name of the field.
    ///
    /// - Parameters:
    ///   - operation: The tool op.
    ///   - renaming: The input field of each parameter of the op whose name
    ///     differs.
    ///   - keeping: Tells if the input object has the field of a parameter.
    /// - Returns: The aliases, by the field name.
    private static func inputAliases(
        of operation: any Operations.OperationDefinition.Type, renaming: [String: String],
        keeping: (String) -> Bool
    ) -> [String: [String]] {
        let parameterAliases = operation.parameterMetadata.map { parameter in
            let field = renaming[parameter.name] ?? parameter.name
            return (field, ([parameter.name] + parameter.aliases).filter { $0 != field })
        }
        return Dictionary(
            parameterAliases.filter { keeping($0.0) && !$0.1.isEmpty }, uniquingKeysWith: +)
    }

    /// The other names of the mutation: the bare verb of the op, and the
    /// code-mode verb of the op when the mutation has a different name.
    var nameAliases: [String] {
        let verb = OperationVerbTool.verbName(for: operation.opString)
        return [operation.verb] + (verb == name ? [] : [verb])
    }

    /// The name of the input object of the mutation, for example
    /// `StartSessionInput`.
    var inputName: String {
        name.prefix(1).uppercased() + name.dropFirst() + Self.inputSuffix
    }

    /// The alias tables of the mutations, by the GraphQL name of the type:
    /// the other names of each mutation, and the fields of each input
    /// object and of the options input of `shareSession`.
    static var aliasTables: [String: [String: [String]]] {
        let verbs = Dictionary(uniqueKeysWithValues: all.map { ($0.name, $0.nameAliases) })
        let inputs = all.map { ($0.inputName, $0.inputAliases) }
        return Dictionary(
            uniqueKeysWithValues: inputs + [("Mutation", verbs), (shareOptionsInputName, shareOptionsAliases)])
    }
}

// MARK: - Text

/// The correctives of the rules that only the endpoint has: the rules of an
/// external client (session.md section 11.3).
enum SessionsGraphText {
    /// The corrective of a start by an external client.
    static let externalStart = """
        An external client cannot start a session: only a device of the user starts one. \
        Send a message to a session that you can see instead.
        """

    /// The corrective of an import by an external client: an import starts
    /// a new session, as a start does.
    static let externalImport = """
        An external client cannot import a session: only a device of the user imports one. \
        Send a message to a session that you can see instead.
        """

    /// The reason of the refused receipt of a message from an external client
    /// to a session that it sees but does not own (section 11.3).
    static let notOwnedReason = """
        not owned: an external client sends only to the sessions that it owns. \
        Send to your own session, or resume this session to own it.
        """

    /// The corrective of a send by an external client to an address that
    /// names no session that it can see: an agent, a tag or a folder.
    ///
    /// - Parameter text: The address.
    /// - Returns: The corrective.
    static func externalAddress(_ text: String) -> String {
        """
        "\(text)" names no session that you can see. An external client sends only to one session that it \
        can see, by its id, its short id or its slug. Query sessions to find one.
        """
    }

    /// The corrective of a call of the agent whose `fromSession` is not its
    /// caller session (D199 (f)).
    ///
    /// - Parameters:
    ///   - source: The session that `fromSession` names.
    ///   - caller: The caller session.
    /// - Returns: The corrective.
    static func sourceNotCaller(_ source: ULID, caller: ULID) -> String {
        """
        fromSession is \(source.ulidString), but a message of the agent comes from its own session \
        \(caller.ulidString). Remove fromSession, or give the id of your own session.
        """
    }
}

// MARK: - Who acts

extension SessionsGraphContext {
    /// The work of the tool ops, over the directory of the call.
    var actions: SessionsToolContext {
        SessionsToolContext(directory: sessions.directory)
    }

    /// True when the client of the call is not a device of the user.
    var viewerIsExternal: Bool {
        sessions.viewer?.trust == .external
    }

    /// The session or the user that makes a mutation: the user of the client
    /// of the call, or the caller session for a call with no viewer.
    ///
    /// - Parameter mutation: The mutation, for the corrective of a call with
    ///   no caller session.
    /// - Returns: The sender.
    /// - Throws: ``SessionsRefusal`` for a call with no viewer and no caller
    ///   session.
    func actor(of mutation: SessionsGraphMutation) throws(SessionsRefusal) -> SessionMessageSender {
        guard let viewer = sessions.viewer else {
            return .session(try actions.callerID(for: mutation.operation.opString))
        }
        return .user(clientID: viewer.clientId)
    }

    /// The session of an id argument, which the viewer must see.
    ///
    /// - Parameter id: The id argument.
    /// - Returns: The session id.
    /// - Throws: ``SessionsRefusal`` for an id that is not a session id, the
    ///   `NOT_FOUND` of the toolkit for a session that the directory does not
    ///   hold or that the viewer cannot see, and each error of the directory.
    func visibleSession(_ id: ToolkitID) async throws -> ULID {
        let sessionID = try SessionsGraphInput.sessionID(id)
        try await requireVisible(sessionID)
        return sessionID
    }

    /// The session that the `id` of a session mutation names, which the
    /// viewer must own: an external client changes only the sessions that it
    /// owns (section 11.3), and a device of the user and the agent change
    /// each session.
    ///
    /// - Parameter id: The `id` argument: a reference, as
    ///   ``referencedSession(_:)`` reads it.
    /// - Returns: The session id.
    /// - Throws: ``SessionsRefusal`` for a reference that names no session
    ///   that the viewer can see or more than one session, the `NOT_FOUND` of
    ///   the toolkit for a session that the viewer cannot see or does not
    ///   own, and each error of the directory.
    func ownedSession(_ id: ToolkitID) async throws -> ULID {
        try await ownedSummary(try await referencedSession(id)).id
    }

    /// The session that the `id` of a session mutation names: `<id>`,
    /// `@<id>`, `<short id>`, `@<short id>` or `@<slug>`, read as its tool op
    /// reads it (D200 (e)), among the sessions that the viewer can see. A
    /// call of the agent looks first in the folder of its caller session; a
    /// client looks in all the sessions at once.
    ///
    /// - Parameters:
    ///   - id: The `id` argument.
    ///   - scope: The sessions that a short id and a slug look at. The
    ///     default is the sessions that are not archived.
    /// - Returns: The session id. A full id is not checked against the
    ///   viewer: the caller checks it.
    /// - Throws: ``SessionsRefusal`` for a reference that names no session
    ///   that the viewer can see or more than one session, and each error of
    ///   the directory.
    func referencedSession(_ id: ToolkitID, scope: SessionsReferenceScope = .unarchived) async throws -> ULID {
        let callerID = sessions.viewer == nil ? actions.callerID : nil
        return try await sessions.sessionID(referencedBy: id.text, callerID: callerID, scope: scope)
    }

    /// The summary of a session that the viewer must own: an external client
    /// owns it, or the viewer is a device of the user or the agent.
    ///
    /// - Parameter id: The session id.
    /// - Returns: The summary.
    /// - Throws: The `NOT_FOUND` of the toolkit for a session that the
    ///   viewer cannot see or does not own, and each error of the directory.
    func ownedSummary(_ id: ULID) async throws -> SessionSummary {
        guard let summary = try await sessions.summary(of: id), viewerOwns(id) else {
            throw GraphQLToolkitError.notFound(kind: SessionsGraphResolver.sessionKind, id: id.ulidString)
        }
        return summary
    }

    /// The session in which the user wrote a message (D199 (f)), from the
    /// `fromSession` of a send. A device of the user and an external client
    /// name a session that they own; a call of the agent sends from its
    /// caller session, thus only that session is a correct `fromSession`.
    ///
    /// - Parameters:
    ///   - id: The `fromSession` argument, or `nil`.
    ///   - sender: The sender of the message.
    /// - Returns: The source session of a user sender, or `nil` when the
    ///   call names none or the sender is a session.
    /// - Throws: ``SessionsRefusal`` for an id that is not a session id and
    ///   for a call of the agent that names an other session; the
    ///   `NOT_FOUND` of the toolkit for a session that the viewer cannot see
    ///   or does not own; each error of the directory.
    func sourceSession(_ id: ToolkitID?, of sender: SessionMessageSender) async throws -> SessionSummary? {
        guard let id else {
            return nil
        }
        let sourceID = try SessionsGraphInput.sessionID(id)
        switch sender {
        case .session(let caller):
            guard sourceID == caller else {
                throw SessionsRefusal(.sourceNotCaller, SessionsGraphText.sourceNotCaller(sourceID, caller: caller))
            }
            return nil
        case .user:
            return try await ownedSummary(sourceID)
        }
    }

    /// Tells if the viewer may change a session or send to it: an external
    /// client owns it, or the viewer is a device of the user or the agent.
    ///
    /// - Parameter id: The session id.
    /// - Returns: `true` when the viewer may act on the session.
    func viewerOwns(_ id: ULID) -> Bool {
        guard viewerIsExternal, let viewer = sessions.viewer else {
            return true
        }
        return viewer.owns(id.ulidString)
    }

    /// The receipts of a message from the viewer to a session that it sees
    /// but does not own: one refused receipt, and no message goes.
    ///
    /// - Parameter id: The target session.
    /// - Returns: The receipts.
    func notOwnedReceipts(to id: ULID) -> [SessionsGraphReceipt] {
        let refusal = SessionSendReceipt(target: id, outcome: .refused, reason: SessionsGraphText.notOwnedReason)
        return [SessionsGraphReceipt(refusal)]
    }

    /// Checks that the viewer sees a session.
    ///
    /// - Parameter id: The session id.
    /// - Throws: The `NOT_FOUND` of the toolkit for a session that the
    ///   directory does not hold or that the viewer cannot see, and each
    ///   error of the directory.
    func requireVisible(_ id: ULID) async throws {
        guard try await sessions.summary(of: id) != nil else {
            throw GraphQLToolkitError.notFound(kind: SessionsGraphResolver.sessionKind, id: id.ulidString)
        }
    }

    /// The target of a message address, read by the one reader of the tool
    /// over the sessions that the viewer sees (D100, D199), which the viewer
    /// may send to: a session that it sees, or, for a device of the user and
    /// the agent, each other form of address.
    ///
    /// - Parameters:
    ///   - text: The address.
    ///   - sender: The session or the user that sends the message.
    ///   - sourceFolder: The working folder of the session in which the user
    ///     wrote the message, in which a short id and a slug look first, or
    ///     `nil`.
    /// - Returns: The target, and the report of the rewrite of an alias.
    /// - Throws: ``SessionsRefusal`` for a text in no form, for a reference
    ///   that names more than one session, or for an external client that
    ///   does not name a session; the `NOT_FOUND` of the toolkit for a
    ///   session that the viewer cannot see.
    func address(
        _ text: String, from sender: SessionMessageSender, sourceFolder: URL?
    ) async throws -> SessionsAddressReading {
        let reading = try await sessions.messageAddress(text, from: sender, sourceFolder: sourceFolder)
        if case .session(let id) = reading.address {
            try await requireVisible(id)
        } else if viewerIsExternal {
            throw SessionsRefusal(.invalidAddress, SessionsGraphText.externalAddress(text))
        }
        return reading
    }
}

// MARK: - Resolvers

extension SessionsGraphResolver {
    /// The kind that `NOT_FOUND` names for a session.
    static let sessionKind = "session"

    /// The path of the `to` field of the input of `Mutation.sendMessage`,
    /// which a rewrite of an address alias names.
    static let sendAddressPath = ["sendMessage", "input", "to"]

    /// The kind that `NOT_FOUND` names for a message.
    static let messageKind = "message"

    /// Resolves `Mutation.startSession`: a device of the user starts a session
    /// of the origin `client` that only its client opens in a tab, and the
    /// agent starts a session of the origin `tool` (D90).
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The input object.
    /// - Returns: The new session.
    /// - Throws: The coded error of a refusal, and each other error of the
    ///   directory.
    func startSession(
        context: SessionsGraphContext, arguments: SessionsGraphMutationArguments<SessionStartArguments>
    ) async throws -> SessionsGraphSession {
        try await Self.coding {
            guard !context.viewerIsExternal else {
                throw SessionsRefusal(.untrustedClient, SessionsGraphText.externalStart)
            }
            let starter = try context.actor(of: .start)
            return SessionsGraphSession(try await context.actions.start(with: arguments.input, by: starter))
        }
    }

    /// Resolves `Mutation.tagSession`.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The input object.
    /// - Returns: The session after the call.
    /// - Throws: The coded error of a refusal, and each other error of the
    ///   directory.
    func tagSession(
        context: SessionsGraphContext, arguments: SessionsGraphMutationArguments<SessionsGraphTagInput>
    ) async throws -> SessionsGraphSession {
        try await Self.changedSession(arguments.input.id, in: context) { target in
            try await context.actions.addTags(named: arguments.input.tags, to: target)
        }
    }

    /// Resolves `Mutation.untagSession`.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The input object.
    /// - Returns: The session after the call.
    /// - Throws: The coded error of a refusal, and each other error of the
    ///   directory.
    func untagSession(
        context: SessionsGraphContext, arguments: SessionsGraphMutationArguments<SessionsGraphUntagInput>
    ) async throws -> SessionsGraphSession {
        try await Self.changedSession(arguments.input.id, in: context) { target in
            try await context.actions.removeTags(named: arguments.input.tags, from: target)
        }
    }

    /// Resolves `Mutation.renameSession` (Session > Rename, D84).
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The input object.
    /// - Returns: The session after the call.
    /// - Throws: The coded error of a refusal, and each other error of the
    ///   directory.
    func renameSession(
        context: SessionsGraphContext, arguments: SessionsGraphMutationArguments<SessionsGraphRenameInput>
    ) async throws -> SessionsGraphSession {
        try await Self.changedSession(arguments.input.id, in: context) { target in
            try await context.actions.rename(session: target, to: arguments.input.title)
        }
    }

    /// Resolves `Mutation.pinSession` (D118): the session goes into the
    /// Pinned list of this server. A second pin keeps its place.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The input object.
    /// - Returns: The session after the call.
    /// - Throws: The coded error of a refusal, and each other error of the
    ///   directory.
    func pinSession(
        context: SessionsGraphContext, arguments: SessionsGraphMutationArguments<SessionsGraphPinInput>
    ) async throws -> SessionsGraphSession {
        try await Self.changedSession(arguments.input.id, in: context) { target in
            try await context.actions.setPinned(session: target, to: true)
        }
    }

    /// Resolves `Mutation.unpinSession` (D118): the session goes out of the
    /// Pinned list of this server.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The input object.
    /// - Returns: The session after the call.
    /// - Throws: The coded error of a refusal, and each other error of the
    ///   directory.
    func unpinSession(
        context: SessionsGraphContext, arguments: SessionsGraphMutationArguments<SessionsGraphUnpinInput>
    ) async throws -> SessionsGraphSession {
        try await Self.changedSession(arguments.input.id, in: context) { target in
            try await context.actions.setPinned(session: target, to: false)
        }
    }

    /// Resolves `Mutation.archiveSession` (Session > Archive, D68): any
    /// session that the viewer can see (D72).
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The input object.
    /// - Returns: The archived session.
    /// - Throws: The coded error of a refusal, and each other error of the
    ///   directory.
    func archiveSession(
        context: SessionsGraphContext, arguments: SessionsGraphMutationArguments<SessionsGraphArchiveInput>
    ) async throws -> SessionsGraphSession {
        try await Self.visibleSessionChange(of: .archive, on: arguments.input.id, scope: .unarchived, in: context) {
            try await context.actions.archive(session: $0, by: $1)
        }
    }

    /// Resolves `Mutation.unarchiveSession` (D204): any archived session that
    /// the viewer can see, as `archiveSession`. A short id and a slug of the
    /// `id` match only the archived sessions, as `unarchive session` reads
    /// them. A session that is not archived gives the coded error
    /// `NOT_ARCHIVED`.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The input object.
    /// - Returns: The unarchived session.
    /// - Throws: The coded error of a refusal, and each other error of the
    ///   directory.
    func unarchiveSession(
        context: SessionsGraphContext, arguments: SessionsGraphMutationArguments<SessionsGraphUnarchiveInput>
    ) async throws -> SessionsGraphSession {
        try await Self.visibleSessionChange(of: .unarchive, on: arguments.input.id, scope: .archived, in: context) {
            try await context.actions.unarchive(session: $0, by: $1)
        }
    }

    /// Resolves `Mutation.forkSession` (D205): the fork has the history of
    /// the source up to its last completed turn. A running turn is not
    /// copied, and it continues in the source. The source is a session that
    /// the viewer owns, as for the other changes of one session: an external
    /// client forks only a session that it owns. A fork from a device opens a
    /// tab only on that client, and a fork by the agent opens no tab.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The input object.
    /// - Returns: The fork.
    /// - Throws: The coded error of a refusal, and each other error of the
    ///   directory.
    func forkSession(
        context: SessionsGraphContext, arguments: SessionsGraphMutationArguments<SessionsGraphForkInput>
    ) async throws -> SessionsGraphSession {
        try await Self.coding {
            let forker = try context.actor(of: .fork)
            let source = try await context.ownedSession(arguments.input.id)
            return SessionsGraphSession(
                try await context.actions.fork(
                    session: source, at: .lastCompletedTurn, firstPrompt: arguments.input.message, by: forker))
        }
    }

    /// Resolves `Mutation.sendMessage`. The message of a client is input of
    /// its user; the directory applies the same rules as for the tool.
    ///
    /// The `fromSession` of a user sender is the source session of the
    /// message, and its working folder is the lookup folder of the address
    /// (D199 (f)). The check of `fromSession` comes before the address, thus
    /// a source that the viewer cannot use stops the send first. An address
    /// alias adds its rewrite to `extensions.rewrites`.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The input object.
    /// - Returns: One receipt for each target.
    /// - Throws: The coded error of a refusal, and each other error of the
    ///   directory.
    func sendMessage(
        context: SessionsGraphContext, arguments: SessionsGraphMutationArguments<SessionsGraphSendInput>
    ) async throws -> [SessionsGraphReceipt] {
        try await Self.coding {
            let input = arguments.input
            let sender = try context.actor(of: .send)
            let source = try await context.sourceSession(input.fromSession, of: sender)
            let reading = try await context.address(input.to, from: sender, sourceFolder: source?.workingDirectory)
            Self.report(reading.rewrite)
            let address = reading.address
            if case .session(let target) = address, !context.viewerOwns(target) {
                return context.notOwnedReceipts(to: target)
            }
            let receipts = try await context.actions.send(
                text: input.message, to: address, from: sender, sourceSession: source?.id)
            return receipts.map(SessionsGraphReceipt.init)
        }
    }

    /// Adds the rewrite of an address alias to `extensions.rewrites` of the
    /// response (D199 (e), D86), with the alias, the canonical form that the
    /// answer of the tool tells, and the path of the `to` field. An address
    /// that is not an alias adds no rewrite.
    ///
    /// - Parameter rewrite: The rewrite of the alias, or `nil`.
    private static func report(_ rewrite: SessionsAddressRewrite?) {
        guard let rewrite else {
            return
        }
        ResolverRewrites.current?.add(NameRewrite(from: rewrite.alias, to: rewrite.canonical, path: sendAddressPath))
    }

    /// Resolves `Mutation.replyMessage`: the reply goes to the session that
    /// sent the message, which the viewer must see too. An external client
    /// replies only to a session that it owns.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The input object.
    /// - Returns: One receipt for each target.
    /// - Throws: The coded error of a refusal, and each other error of the
    ///   directory.
    func replyMessage(
        context: SessionsGraphContext, arguments: SessionsGraphMutationArguments<SessionsGraphReplyInput>
    ) async throws -> [SessionsGraphReceipt] {
        let input = arguments.input
        return try await Self.coding {
            let sender = try context.actor(of: .reply)
            let recipient = try await context.visibleSession(input.sessionId)
            let original = try await context.actions.replyTarget(of: input.inReplyTo.text, to: recipient)
            guard try await context.sessions.summary(of: original.sender) != nil else {
                throw SessionsUnknownMessage(id: original.id)
            }
            guard context.viewerOwns(original.sender) else {
                return context.notOwnedReceipts(to: original.sender)
            }
            let receipts = try await context.actions.send(
                text: input.message, to: .session(original.sender), inReplyTo: original.id, from: sender)
            return receipts.map(SessionsGraphReceipt.init)
        }
    }

    /// Runs the change of a mutation on the session of an id argument, which
    /// the viewer must own (section 11.3).
    ///
    /// - Parameters:
    ///   - id: The id argument.
    ///   - context: The context of the call.
    ///   - change: The change, given the session id.
    /// - Returns: The session after the change.
    /// - Throws: The coded error of a refusal, and each other error of the
    ///   directory.
    private static func changedSession(
        _ id: ToolkitID, in context: SessionsGraphContext, _ change: (ULID) async throws -> SessionSummary
    ) async throws -> SessionsGraphSession {
        try await coding {
            SessionsGraphSession(try await change(try await context.ownedSession(id)))
        }
    }

    /// Runs the action of a mutation on the session of an id argument, which
    /// the viewer must see (D72): the action of `archiveSession` and
    /// `unarchiveSession`. The actor comes first, then the reference, then
    /// the check of the viewer.
    ///
    /// - Parameters:
    ///   - mutation: The mutation, for the corrective of a call with no
    ///     caller session.
    ///   - id: The id argument.
    ///   - scope: The sessions that a short id and a slug of `id` look at.
    ///   - context: The context of the call.
    ///   - action: The action, given the session id and the actor.
    /// - Returns: The session after the action.
    /// - Throws: The coded error of a refusal, and each other error of the
    ///   directory.
    private static func visibleSessionChange(
        of mutation: SessionsGraphMutation, on id: ToolkitID, scope: SessionsReferenceScope,
        in context: SessionsGraphContext, _ action: (ULID, SessionMessageSender) async throws -> SessionSummary
    ) async throws -> SessionsGraphSession {
        try await coding {
            let actor = try context.actor(of: mutation)
            let target = try await context.referencedSession(id, scope: scope)
            try await context.requireVisible(target)
            return SessionsGraphSession(try await action(target, actor))
        }
    }

    // MARK: Coded errors

    /// Runs the work of a mutation, and gives each error that the tool
    /// answers as a corrective as a coded error: a ``SessionsRefusal`` stays,
    /// an unknown session or message is the `NOT_FOUND` of the toolkit, and
    /// each other error of the directory is the refusal with its corrective.
    ///
    /// - Parameter work: The work.
    /// - Returns: What `work` gave.
    /// - Throws: The coded error, or each other error of `work`.
    static func coding<Result>(_ work: () async throws -> Result) async throws -> Result {
        do {
            return try await work()
        } catch let error as SessionDirectoryError {
            throw codedError(of: error)
        } catch let unknown as SessionsUnknownMessage {
            throw GraphQLToolkitError.notFound(kind: messageKind, id: unknown.id.description)
        }
    }

    /// The coded error of an error of the directory, with the corrective that
    /// the tool gives for it.
    ///
    /// - Parameter error: The error.
    /// - Returns: The `NOT_FOUND` of the toolkit for an unknown session, and
    ///   a ``SessionsRefusal`` for each other error.
    private static func codedError(of error: SessionDirectoryError) -> any CodedError {
        guard let kind = refusalKind(of: error) else {
            if case .unknownSession(let id) = error {
                return GraphQLToolkitError.notFound(kind: sessionKind, id: id.ulidString)
            }
            preconditionFailure("each error but an unknown session has a refusal kind")
        }
        return SessionsRefusal(kind, SessionsToolText.corrective(for: error))
    }

    /// The kind of the refusal of an error of the directory.
    ///
    /// - Parameter error: The error.
    /// - Returns: The kind, or `nil` for an unknown session, which is the
    ///   `NOT_FOUND` of the toolkit.
    static func refusalKind(of error: SessionDirectoryError) -> SessionsRefusal.Kind? {
        switch error {
        case .unknownSession:
            nil
        case .unknownAgent:
            .unknownAgent
        case .notADirectory:
            .invalidFolder
        case .chainTooDeep:
            .deepChain
        case .messageTooLong:
            .longMessage
        case .invalidTag:
            .invalidTag
        case .noLauncher:
            .missingLauncher
        case .archivedSession:
            .archivedSession
        case .forkCutOutOfRange:
            .forkCutOutOfRange
        case .forkUnsupported:
            .forkUnsupported
        case .importUnsupported:
            .importUnsupported
        }
    }
}

extension SessionsGraphReceipt {
    /// Resolves `SendReceipt.target`.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: No argument.
    /// - Returns: The target session, or `nil` when no session matched the
    ///   address or the viewer cannot see it.
    /// - Throws: An error of the directory.
    func target(context: SessionsGraphContext, arguments _: NoArguments) async throws -> SessionsGraphSession? {
        try await SessionsGraphSession.visible(targetID, in: context)
    }
}

// MARK: - Schema

extension SessionsGraphAPI {
    /// The text of the forms of the `id` of an input object (D200 (e)).
    private static let referenceDescription =
        "The session: its id in any letter case or its short id, with or without @, or @ and its slug. A short id "
        + "or a slug names only a session that you can see."

    /// The text of the description of the `id` of an input object.
    private static let idDescription = "\(referenceDescription) An id of a session that you cannot see is NOT_FOUND."

    /// The text of the description of the `id` of the input of
    /// `unarchiveSession`: a short id and a slug name only an archived
    /// session (D204 (c)).
    private static let archivedIDDescription =
        "The archived session: its id in any letter case or its short id, with or without @, or @ and its slug. A "
        + "short id or a slug names only an archived session that you can see. An id of a session that you cannot "
        + "see is NOT_FOUND."

    /// The text of the description of the `id` of an input object whose
    /// session the viewer must own (section 11.3).
    private static let ownedIDDescription =
        "\(referenceDescription) An id of a session that you cannot see, or a session that an external client "
        + "does not own, is NOT_FOUND."

    /// The text of the rule of an external client for a send or a reply.
    private static let ownedTargetRule =
        "An external client sends only to a session that it owns: a session that it sees but does not own gives a "
        + "REFUSED receipt."

    /// The text of the description of the `message` of a send or a reply.
    private static let messageDescription = "The full text. The target sees only this text."

    /// The text of the description of each mutation that gives receipts.
    private static let receiptsDescription = "Gives what happened at each target."

    /// The `SendOutcome` enum.
    ///
    /// - Returns: The enum.
    static func outcomeEnum() -> SchemaType {
        Enum(SessionsGraphOutcome.self, as: "SendOutcome") {
            Value(.delivered).description("The target was idle: the message starts a turn.")
            Value(.queued).description("The target works: the message waits for the end of its turn.")
            Value(.started).description("An agent with no live session started one with the message.")
            Value(.refused).description("A loop guard or no match refused the message.")
            Value(.sent).description(
                "The target is not live: the message is written to its inbox and not yet delivered.")
        }
        .description("What happened to a message at one target.")
    }

    /// The `SendReceipt` type.
    ///
    /// - Returns: The type.
    static func receiptType() -> SchemaType {
        Type(SessionsGraphReceipt.self, as: "SendReceipt") {
            Field("messageId", at: \.messageId).description("The id of the message, or null when none was made.")
            Field("target", at: SessionsGraphReceipt.target)
                .description("The target session, or null for no match or a session that you cannot see.")
            Field("outcome", at: \.outcome).description("What happened to the message.")
            Field("reason", at: \.reason).description(
                "Why the message was refused, or a note of a SENT receipt, for example `archived` for an archived "
                    + "target. Null when there is no reason and no note.")
        }
        .description("What happened to a message at one target.")
    }

    /// The `StartSessionInput` input object.
    ///
    /// - Returns: The input object.
    static func startInput() -> SchemaType {
        Input(SessionStartArguments.self, as: SessionsGraphMutation.start.inputName) {
            InputField("agentId", at: \.agentId)
                .description("The agent id. With none, the AGENT.md of the folder, else the default agent.")
            InputField("cwd", at: \.cwd)
                .description("The absolute path of an existing folder. ~ expands. With none, the default folder.")
            InputField("message", at: \.message).description("The first message. The new agent sees only this text.")
            InputField("tags", at: \.tags).description("The tags of the new session.")
            InputField("title", at: \.title).description("The title of the new session.")
        }
        .description("A new root session of an agent, with its first message.")
    }

    /// The `TagSessionInput` input object.
    ///
    /// - Returns: The input object.
    static func tagInput() -> SchemaType {
        Input(SessionsGraphTagInput.self, as: SessionsGraphMutation.tag.inputName) {
            InputField("id", at: \.id).description(ownedIDDescription)
            InputField("tags", at: \.tags).description("The tags to add. \(SessionsToolText.tagRule)")
        }
        .description("The tags to add to a session.")
    }

    /// The `UntagSessionInput` input object.
    ///
    /// - Returns: The input object.
    static func untagInput() -> SchemaType {
        Input(SessionsGraphUntagInput.self, as: SessionsGraphMutation.untag.inputName) {
            InputField("id", at: \.id).description(ownedIDDescription)
            InputField("tags", at: \.tags).description("The tags to remove.")
        }
        .description("The tags to remove from a session.")
    }

    /// The `RenameSessionInput` input object.
    ///
    /// - Returns: The input object.
    static func renameInput() -> SchemaType {
        Input(SessionsGraphRenameInput.self, as: SessionsGraphMutation.rename.inputName) {
            InputField("id", at: \.id).description(ownedIDDescription)
            InputField("title", at: \.title).description("The new title.")
        }
        .description("The new title of a session.")
    }

    /// The `PinSessionInput` input object.
    ///
    /// - Returns: The input object.
    static func pinInput() -> SchemaType {
        Input(SessionsGraphPinInput.self, as: SessionsGraphMutation.pin.inputName) {
            InputField("id", at: \.id).description(idDescription)
        }
        .description("The session to pin.")
    }

    /// The `UnpinSessionInput` input object.
    ///
    /// - Returns: The input object.
    static func unpinInput() -> SchemaType {
        Input(SessionsGraphUnpinInput.self, as: SessionsGraphMutation.unpin.inputName) {
            InputField("id", at: \.id).description(idDescription)
        }
        .description("The session to unpin.")
    }

    /// The `ArchiveSessionInput` input object.
    ///
    /// - Returns: The input object.
    static func archiveInput() -> SchemaType {
        Input(SessionsGraphArchiveInput.self, as: SessionsGraphMutation.archive.inputName) {
            InputField("id", at: \.id).description(idDescription)
        }
        .description("The session to archive.")
    }

    /// The `UnarchiveSessionInput` input object.
    ///
    /// - Returns: The input object.
    static func unarchiveInput() -> SchemaType {
        Input(SessionsGraphUnarchiveInput.self, as: SessionsGraphMutation.unarchive.inputName) {
            InputField("id", at: \.id).description(archivedIDDescription)
        }
        .description("The archived session to unarchive.")
    }

    /// The `ForkSessionInput` input object.
    ///
    /// - Returns: The input object.
    static func forkInput() -> SchemaType {
        Input(SessionsGraphForkInput.self, as: SessionsGraphMutation.fork.inputName) {
            InputField("id", at: \.id).description(ownedIDDescription)
            InputField("message", at: \.message)
                .description("The first prompt of the fork. With none, the fork waits for a message.")
        }
        .description("The session to fork, and the first prompt of the fork.")
    }

    /// The `SendMessageInput` input object.
    ///
    /// - Returns: The input object.
    static func sendInput() -> SchemaType {
        Input(SessionsGraphSendInput.self, as: SessionsGraphMutation.send.inputName) {
            InputField("to", at: \.to)
                .description(
                    "The address: a session id, @agent, @agent:/path, an absolute folder path, or #tag. An external "
                        + "client gives a session id. A session that you cannot see is NOT_FOUND. \(ownedTargetRule)")
            InputField("message", at: \.message).description(messageDescription)
            InputField("fromSession", at: \.fromSession)
                .description(
                    "The session in which you wrote the message, in any letter case. Its folder is where a short id "
                        + "or a slug of the address looks first. A session that you cannot see, or that an external "
                        + "client does not own, is NOT_FOUND. A call of the agent gives only its own session.")
        }
        .description("A message and its address.")
    }

    /// The `ReplyMessageInput` input object.
    ///
    /// - Returns: The input object.
    static func replyInput() -> SchemaType {
        Input(SessionsGraphReplyInput.self, as: SessionsGraphMutation.reply.inputName) {
            InputField("sessionId", at: \.sessionId)
                .description("The session that got the message. A session that you cannot see is NOT_FOUND.")
            InputField("inReplyTo", at: \.inReplyTo)
                .description(
                    "The id of the message to answer. The reply goes to its sender: a sender that you cannot see "
                        + "makes the message NOT_FOUND. \(ownedTargetRule)")
            InputField("message", at: \.message).description(messageDescription)
        }
        .description("A reply to a message that a session got. It goes to the session that sent the message.")
    }

    /// The fields of the `Mutation` type: one for each mutation, in the order
    /// of ``SessionsGraphMutation/all``.
    ///
    /// - Returns: The fields.
    static func mutationFields() -> [SchemaField] {
        [
            mutationField(
                .start, at: SessionsGraphResolver.startSession,
                input: "The agent, the folder and the first message.",
                description: "Starts a new root session of an agent. It works in the background, and only your client "
                    + "opens it in a tab. An external client cannot start a session."),
            mutationField(
                .tag, at: SessionsGraphResolver.tagSession, input: "The session and the tags.",
                description: "Adds tags to a session. Gives the session with its tags."),
            mutationField(
                .untag, at: SessionsGraphResolver.untagSession, input: "The session and the tags.",
                description: "Removes tags from a session. Gives the session with the tags that stay."),
            mutationField(
                .rename, at: SessionsGraphResolver.renameSession, input: "The session and its new title.",
                description: "Sets the title of a session."),
            mutationField(
                .pin, at: SessionsGraphResolver.pinSession, input: "The session.",
                description: "Pins a session: it goes into the Pinned list of this server, after the other pins. A "
                    + "second pin keeps its place. Gives the session."),
            mutationField(
                .unpin, at: SessionsGraphResolver.unpinSession, input: "The session.",
                description: "Unpins a session: it goes out of the Pinned list of this server. Gives the session."),
            mutationField(
                .archive, at: SessionsGraphResolver.archiveSession, input: "The session.",
                description: "Archives a session: stops its turn and hides it from the lists. It is not deleted: its "
                    + "transcript and its inbox stay, a message to it waits in its inbox, and unarchiveSession "
                    + "brings it back."),
            mutationField(
                .unarchive, at: SessionsGraphResolver.unarchiveSession, input: "The archived session.",
                description: "Unarchives a session: it shows in the lists again. It stays a recorded session until a "
                    + "client opens it, and its transcript and its inbox are as they were. A session that is not "
                    + "archived gives NOT_ARCHIVED."),
            mutationField(
                .fork, at: SessionsGraphResolver.forkSession, input: "The session and the first prompt of the fork.",
                description: "Forks a session: a new session of the kind FORK, in the folder of the source, with the "
                    + "history of the source up to its last completed turn. Then the fork works alone. An archived "
                    + "source gives ARCHIVED_SESSION, and a server that cannot fork gives FORK_UNSUPPORTED. Gives "
                    + "the fork."),
            mutationField(
                .send, at: SessionsGraphResolver.sendMessage, input: "The address and the text.",
                description: "Sends a message from you to a session, an agent, a folder or a tag. "
                    + "\(receiptsDescription) \(ownedTargetRule)"),
            mutationField(
                .reply, at: SessionsGraphResolver.replyMessage,
                input: "The session that got the message, the message and the text.",
                description: "Replies to a message that a session got, from you. \(receiptsDescription) "
                    + ownedTargetRule),
        ] + shareMutationFields() + [importMutationField()]
    }

    /// The field of one mutation: its name, its resolver, and its one
    /// `input` argument.
    ///
    /// - Parameters:
    ///   - mutation: The mutation, which gives the name of the field.
    ///   - resolve: The resolver of the field.
    ///   - input: The description of the `input` argument.
    ///   - description: The description of the field.
    /// - Returns: The field.
    static func mutationField<Input: Codable & Sendable, Output: Sendable>(
        _ mutation: SessionsGraphMutation,
        at resolve:
            @escaping AsyncResolve<
                SessionsGraphResolver, SessionsGraphContext, SessionsGraphMutationArguments<Input>, Output
            >,
        input: String,
        description: String
    ) -> SchemaField {
        Field(mutation.name, at: resolve) {
            Argument("input", at: \.input).description(input)
        }
        .description(description)
    }
}
