// The object types, the enums and the input objects of the `sessions`
// GraphQL endpoint (MT-10, session.md section 11.2).
//
// Each enum has the GraphQL names as its raw values, in `UPPER_SNAKE`, and
// maps the value of the directory. Each object holds the values that its
// fields give; a field that reads the directory again resolves in
// `SessionsGraphSchema.swift`.

import Foundation
import FoundationModelsExtras
import ULID

// MARK: - Enums

/// The `SessionKind` enum: the kind of a session.
enum SessionsGraphKind: String, Codable, CaseIterable, Sendable {
    /// A root session.
    case root = "ROOT"

    /// A subagent of another session.
    case subagent = "SUBAGENT"

    /// A fork of another session.
    case fork = "FORK"

    /// Makes the enum value of a kind of the directory.
    ///
    /// - Parameter kind: The kind of the directory.
    init(_ kind: SessionKind) {
        switch kind {
        case .root: self = .root
        case .subagent: self = .subagent
        case .fork: self = .fork
        }
    }

    /// The kind of the directory.
    var kind: SessionKind {
        switch self {
        case .root: .root
        case .subagent: .subagent
        case .fork: .fork
        }
    }
}

/// The `SessionState` enum: the work state of a session.
enum SessionsGraphState: String, Codable, CaseIterable, Sendable {
    /// The session runs a turn.
    case working = "WORKING"

    /// The session waits for an answer.
    case needsInput = "NEEDS_INPUT"

    /// The session runs no turn.
    case idle = "IDLE"

    /// The session ended.
    case archived = "ARCHIVED"

    /// Makes the enum value of a state of the directory.
    ///
    /// - Parameter state: The state of the directory.
    init(_ state: SessionState) {
        switch state {
        case .working: self = .working
        case .needsInput: self = .needsInput
        case .idle: self = .idle
        case .archived: self = .archived
        }
    }

    /// The state of the directory.
    var state: SessionState {
        switch self {
        case .working: .working
        case .needsInput: .needsInput
        case .idle: .idle
        case .archived: .archived
        }
    }
}

/// The `SessionOrigin` enum: how a session started.
enum SessionsGraphOrigin: String, Codable, CaseIterable, Sendable {
    /// A client started it.
    case client = "CLIENT"

    /// The `sessions` tool of another session started it.
    case tool = "TOOL"

    /// A message to an agent started it.
    case message = "MESSAGE"

    /// A trigger started it.
    case trigger = "TRIGGER"

    /// A user forked another session.
    case fork = "FORK"

    /// Makes the enum value of an origin of the directory.
    ///
    /// - Parameter origin: The origin of the directory.
    init(_ origin: SessionDirectoryOrigin) {
        switch origin {
        case .client: self = .client
        case .tool: self = .tool
        case .message: self = .message
        case .trigger: self = .trigger
        case .fork: self = .fork
        }
    }
}

// MARK: - Object types

/// The `Session` object: the facts of one session that the viewer can see.
struct SessionsGraphSession: Sendable {
    /// The session id, canonical: a ULID in upper case.
    let id: ToolkitID

    /// The id of the agent in the agent catalog.
    let agentId: String

    /// The display name of the agent, or `nil`.
    let agentName: String?

    /// The absolute path of the working folder.
    let cwd: String

    /// The title, or `nil`.
    let title: String?

    /// The tags, sorted.
    let tags: [String]

    /// The kind.
    let kind: SessionsGraphKind

    /// The work state.
    let state: SessionsGraphState

    /// How the session started.
    let origin: SessionsGraphOrigin

    /// The time the session started.
    let createdAt: DateTime

    /// The time of the last change of the facts or the state.
    let updatedAt: DateTime

    /// The last final message, cut to a fixed length, or `nil`.
    let lastSummary: String?

    /// True when the session is in memory now.
    let isLive: Bool

    /// The session id, as the directory reads it.
    let sessionID: ULID

    /// The parent of a subagent or the original of a fork, or `nil`.
    let parentID: ULID?

    /// The session that started this root session, or `nil`.
    let starterID: ULID?

    /// Makes the object of a summary of the directory.
    ///
    /// - Parameter summary: The summary.
    init(_ summary: SessionSummary) {
        sessionID = summary.id
        parentID = summary.parentID
        starterID = summary.startedBy
        id = ToolkitID(summary.id.ulidString)
        agentId = summary.agentID
        agentName = summary.agentName
        cwd = summary.workingDirectory.path
        title = summary.title
        tags = summary.tags.sorted()
        kind = SessionsGraphKind(summary.kind)
        state = SessionsGraphState(summary.state)
        origin = SessionsGraphOrigin(summary.origin)
        createdAt = DateTime(summary.createdAt)
        updatedAt = DateTime(summary.updatedAt)
        lastSummary = summary.lastSummary
        isLive = summary.isLive
    }
}

/// The `Sender` object: the session or the user that sent a message.
struct SessionsGraphSender: Sendable {
    /// The sending session, or `nil` for a message from a user.
    let sessionID: ULID?

    /// The client of the user that sent the message, or `nil` for a message
    /// from a session.
    let clientId: String?

    /// Makes the object of a sender of the directory.
    ///
    /// - Parameter sender: The sender.
    init(_ sender: SessionMessageSender) {
        switch sender {
        case .session(let id):
            sessionID = id
            clientId = nil
        case .user(let clientID):
            sessionID = nil
            clientId = clientID
        }
    }
}

/// The `Message` object: one message that the directory delivered to a
/// session.
struct SessionsGraphMessage: Sendable {
    /// The id of the message, canonical: a ULID in upper case.
    let id: ToolkitID

    /// The session or the user that sent the message.
    let from: SessionsGraphSender

    /// The session that the message went to.
    let to: SessionsGraphSession

    /// The text of the message.
    let text: String

    /// The id of the message that this message answers, or `nil`.
    let inReplyTo: ToolkitID?

    /// The time the directory delivered the message.
    let sentAt: DateTime

    /// The depth of the message in its chain.
    let chainDepth: Int

    /// True when the target read the message.
    let isRead: Bool

    /// Makes the object of a message of the directory.
    ///
    /// - Parameters:
    ///   - message: The message.
    ///   - target: The session that the message went to.
    init(_ message: SessionMessage, to target: SessionsGraphSession) {
        id = ToolkitID(message.id.description)
        from = SessionsGraphSender(message.from)
        to = target
        text = message.text
        inReplyTo = message.inReplyTo.map { ToolkitID($0.description) }
        sentAt = DateTime(message.sentAt)
        chainDepth = message.chainDepth
        isRead = message.isRead
    }
}

// MARK: - Input objects and arguments

/// The `SessionFilter` input object of `Query.sessions`: each field that is
/// set must match. The value with no field set is the filter of a call that
/// gives no filter.
struct SessionsGraphFilter: Codable, Sendable {
    /// The absolute path of the working folder; `~` expands.
    var cwd: String?

    /// The agent id.
    var agentId: String?

    /// A tag that each session has.
    var tag: String?

    /// The kind.
    var kind: SessionsGraphKind?

    /// The work state.
    var state: SessionsGraphState?

    /// The parent of a subagent, or the original of a fork.
    var parentId: ToolkitID?

    /// The session that started the sessions.
    var startedById: ToolkitID?

    /// True to also find the sessions that are not live.
    var includeRecorded: Bool?

    /// The most sessions to give.
    var limit: Int?
}

/// The arguments of `Query.sessions`.
struct SessionsGraphSessionsArguments: Codable, Sendable {
    /// The filter, or `nil` for each live session.
    let filter: SessionsGraphFilter?
}

/// The arguments of `Query.session`.
struct SessionsGraphSessionArguments: Codable, Sendable {
    /// The session id, in any letter case.
    let id: ToolkitID
}

/// The arguments of `Query.inbox`.
struct SessionsGraphInboxArguments: Codable, Sendable {
    /// The session whose messages the query reads, in any letter case.
    let sessionId: ToolkitID

    /// The most messages to give, or `nil` for the default.
    let limit: Int?
}
