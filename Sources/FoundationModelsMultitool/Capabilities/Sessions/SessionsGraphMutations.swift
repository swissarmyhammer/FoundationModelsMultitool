// The mutations of the `sessions` GraphQL endpoint (MT-10, EXTRAS-9 rule 7):
// `startSession`, `tagSession`, `untagSession`, `renameSession`,
// `archiveSession`, `sendMessage` and `replyMessage`.
//
// Each mutation has the name of the code-mode verb of a tool op of the
// `sessions` tool, and calls the work of that op in ``SessionsToolContext``:
// the op and the mutation change the directory the same way, and refuse a
// call with the same corrective (session.md section 11.4). A ``SessionsRefusal``
// is a coded error with that corrective; an id that the directory does not
// hold, or that the viewer cannot see, is the `NOT_FOUND` of the toolkit.
//
// Who acts (section 11.3): a client acts as its user, `user(clientID)`, and a
// call with no viewer acts as the agent of the caller session, as the tool
// does. An external client archives only the sessions that it can see; it
// tags, untags, renames, sends and replies only to the sessions that it owns;
// and it cannot start a session.

import Foundation
import FoundationModelsExtras
import Graphiti
import GraphQL
import Operations
import ULID

// MARK: - Names

/// One mutation of the endpoint, and the tool op whose rules it shares.
///
/// The name of the mutation is the code-mode verb of the op
/// (`tools.sessions.startSession` and `startSession`). The alias tables take
/// the bare verb of the op for the mutation, and the names of the parameters
/// of the op, and their aliases, for the fields of its input object.
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

    /// `archiveSession`.
    static let archive = Self(ArchiveSession.self, adding: sessionIDAliases)

    /// `sendMessage`.
    static let send = Self(SendMessage.self)

    /// `replyMessage`.
    static let reply = Self(ReplyMessage.self)

    /// Each mutation of the endpoint.
    static let all = [start, tag, untag, rename, archive, send, reply]

    /// The tool op of the mutation. The module name tells it from the
    /// `OperationDefinition` of GraphQL.
    let operation: any Operations.OperationDefinition.Type

    /// The aliases of the fields of the input object, by the field name.
    let inputAliases: [String: [String]]

    /// Makes a mutation of a tool op.
    ///
    /// - Parameters:
    ///   - operation: The tool op.
    ///   - renaming: The input field of each parameter of the op whose
    ///     name differs; the name of the parameter becomes an alias.
    ///   - adding: The aliases of the input object that the op does not have.
    private init(
        _ operation: any Operations.OperationDefinition.Type,
        renaming: [String: String] = [:],
        adding: [String: [String]] = [:]
    ) {
        self.operation = operation
        let parameterAliases = operation.parameterMetadata.map { parameter in
            let field = renaming[parameter.name] ?? parameter.name
            return (field, ([parameter.name] + parameter.aliases).filter { $0 != field })
        }
        inputAliases = Dictionary(parameterAliases.filter { !$0.1.isEmpty }, uniquingKeysWith: +)
            .merging(adding, uniquingKeysWith: +)
    }

    /// The name of the mutation: the code-mode verb of the op.
    var name: String {
        OperationVerbTool.verbName(for: operation.opString)
    }

    /// The name of the input object of the mutation, for example
    /// `StartSessionInput`.
    var inputName: String {
        name.prefix(1).uppercased() + name.dropFirst() + Self.inputSuffix
    }

    /// The alias tables of the mutations, by the GraphQL name of the type:
    /// the bare verb of each mutation, and the fields of each input object.
    static var aliasTables: [String: [String: [String]]] {
        let verbs = Dictionary(uniqueKeysWithValues: all.map { ($0.name, [$0.operation.verb]) })
        let inputs = all.map { ($0.inputName, $0.inputAliases) }
        return Dictionary(uniqueKeysWithValues: inputs + [("Mutation", verbs)])
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

    /// The reason of the refused receipt of a message from an external client
    /// to a session that it sees but does not own (section 11.3).
    static let notOwnedReason = """
        not owned: an external client sends only to the sessions that it owns. \
        Send to your own session, or resume this session to own it.
        """

    /// The corrective of a send by an external client to an address that is
    /// not a session id.
    ///
    /// - Parameter text: The address.
    /// - Returns: The corrective.
    static func externalAddress(_ text: String) -> String {
        """
        "\(text)" is not a session id. An external client sends only to the id of a session that it can see. \
        Query sessions to find one.
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

    /// The session of an id argument, which the viewer must own: an external
    /// client changes only the sessions that it owns (section 11.3), and a
    /// device of the user and the agent change each session.
    ///
    /// - Parameter id: The id argument.
    /// - Returns: The session id.
    /// - Throws: ``SessionsRefusal`` for an id that is not a session id, the
    ///   `NOT_FOUND` of the toolkit for a session that the viewer cannot see
    ///   or does not own, and each error of the directory.
    func ownedSession(_ id: ToolkitID) async throws -> ULID {
        let sessionID = try await visibleSession(id)
        guard viewerOwns(sessionID) else {
            throw GraphQLToolkitError.notFound(kind: SessionsGraphResolver.sessionKind, id: sessionID.ulidString)
        }
        return sessionID
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

    /// The target of a message address, as the tool reads it, which the
    /// viewer may send to: a session that it sees, or, for a device of the
    /// user and the agent, each other form of address.
    ///
    /// - Parameter text: The address.
    /// - Returns: The address.
    /// - Throws: ``SessionsRefusal`` for a text in no form, or for an external
    ///   client that does not give a session id; the `NOT_FOUND` of the
    ///   toolkit for a session that the viewer cannot see.
    func address(_ text: String) async throws -> SessionAddress {
        let address = try SessionsToolInput.address(text)
        if case .session(let id) = address {
            try await requireVisible(id)
        } else if viewerIsExternal {
            throw SessionsRefusal(.invalidAddress, SessionsGraphText.externalAddress(text))
        }
        return address
    }
}

// MARK: - Resolvers

extension SessionsGraphResolver {
    /// The kind that `NOT_FOUND` names for a session.
    static let sessionKind = "session"

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
        try await Self.coding {
            let archiver = try context.actor(of: .archive)
            let target = try await context.visibleSession(arguments.input.id)
            return SessionsGraphSession(try await context.actions.archive(session: target, by: archiver))
        }
    }

    /// Resolves `Mutation.sendMessage`. The message of a client is input of
    /// its user; the directory applies the same rules as for the tool.
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
            let sender = try context.actor(of: .send)
            let address = try await context.address(arguments.input.to)
            if case .session(let target) = address, !context.viewerOwns(target) {
                return context.notOwnedReceipts(to: target)
            }
            let receipts = try await context.actions.send(text: arguments.input.message, to: address, from: sender)
            return receipts.map(SessionsGraphReceipt.init)
        }
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

    // MARK: Coded errors

    /// Runs the work of a mutation, and gives each error that the tool
    /// answers as a corrective as a coded error: a ``SessionsRefusal`` stays,
    /// an unknown session or message is the `NOT_FOUND` of the toolkit, and
    /// each other error of the directory is the refusal with its corrective.
    ///
    /// - Parameter work: The work.
    /// - Returns: What `work` gave.
    /// - Throws: The coded error, or each other error of `work`.
    private static func coding<Result>(_ work: () async throws -> Result) async throws -> Result {
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
        let kind: SessionsRefusal.Kind
        switch error {
        case .unknownSession(let id):
            return GraphQLToolkitError.notFound(kind: sessionKind, id: id.ulidString)
        case .unknownAgent:
            kind = .unknownAgent
        case .notADirectory:
            kind = .invalidFolder
        case .chainTooDeep:
            kind = .deepChain
        case .messageTooLong:
            kind = .longMessage
        case .invalidTag:
            kind = .invalidTag
        case .noLauncher:
            kind = .missingLauncher
        }
        return SessionsRefusal(kind, SessionsToolText.corrective(for: error))
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
    /// The text of the description of the `id` of an input object.
    private static let idDescription = "The session id, in any letter case. A session that you cannot see is NOT_FOUND."

    /// The text of the description of the `id` of an input object whose
    /// session the viewer must own (section 11.3).
    private static let ownedIDDescription =
        "The session id, in any letter case. A session that you cannot see, or that an external client does not "
        + "own, is NOT_FOUND."

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
            Value(.refused).description("A loop guard, an archived target or no match refused the message.")
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
            Field("reason", at: \.reason).description("Why the target refused the message, or null.")
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

    /// The `ArchiveSessionInput` input object.
    ///
    /// - Returns: The input object.
    static func archiveInput() -> SchemaType {
        Input(SessionsGraphArchiveInput.self, as: SessionsGraphMutation.archive.inputName) {
            InputField("id", at: \.id).description(idDescription)
        }
        .description("The session to archive.")
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
                .archive, at: SessionsGraphResolver.archiveSession, input: "The session.",
                description: "Archives a session: stops its turn and ends its work. It takes no more messages, and its "
                    + "transcript stays."),
            mutationField(
                .send, at: SessionsGraphResolver.sendMessage, input: "The address and the text.",
                description: "Sends a message from you to a session, an agent, a folder or a tag. "
                    + "\(receiptsDescription) \(ownedTargetRule)"),
            mutationField(
                .reply, at: SessionsGraphResolver.replyMessage,
                input: "The session that got the message, the message and the text.",
                description: "Replies to a message that a session got, from you. \(receiptsDescription) "
                    + ownedTargetRule),
        ]
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
    private static func mutationField<Input: Codable & Sendable, Output: Sendable>(
        _ mutation: SessionsGraphMutation,
        at resolve: @escaping AsyncResolve<
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
