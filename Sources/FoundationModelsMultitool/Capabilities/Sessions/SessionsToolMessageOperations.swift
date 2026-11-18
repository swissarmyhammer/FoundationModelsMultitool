// The message operations of the `sessions` tool: `send message` and
// `reply message` (session.md sections 8.2, 9 and 10).
//
// Each operation acts for the caller session: a call with no caller gives a
// corrective, as section 8.2 says. The directory applies the address rules,
// the delivery rules and the loop guards; the tool reads the address, sends
// through `SessionDirectory.send(_:)`, and gives one line for each receipt.
// A send that no target took is a corrective that names each reason, and an
// error of the directory is a corrective, never a thrown model error:
// ``SessionsToolContext/answer(asCallerOf:_:)`` catches each error and gives
// ``SessionsToolText/corrective(for:)``.
//
// The work of each send is in the extension of ``SessionsToolContext`` at the
// end of this file, which the `sendMessage` and `replyMessage` mutations of
// the `sessions` endpoint call too (MT-10).
//
// TODO(MT-7): declare the risk facts of session.md section 8.3 on each
// operation (`send message` and `reply message` each send to another agent),
// when MT-1 and MT-7 land.

import Foundation
import FoundationModels
import FoundationModelsExtras
import Operations
import ULID

/// Sends a message to one session, to an agent, or to a tag
/// (`send message`, D199).
@Generable
@Operation(
    verb: "send", noun: "message",
    description: """
        Send a message to another session. Name one session with @<id>, @<short id> or @<slug>; the slug is \
        made from the name of the session. An agent is a session: @<agent name> reaches the session with that \
        slug, and starts a new session of the agent when no session has it. #tag reaches each live session with \
        the tag. @agent:/path and a folder path are aliases. Gives what happened at each target.
        """)
struct SendMessage {
    /// The address of the message.
    @Guide(
        description: """
            The address. One session: @<id>, <id>, @<short id>, <short id> or @<slug> (a short id or a slug \
            looks in the folder of your session first). @<agent name> with no session of that slug starts that \
            agent. #tag: each live session with the tag, but not yours. Aliases: @agent:/path (the lookup is in \
            that folder first) and an absolute folder path (/path or ~/path).
            """)
    @OperationParam(aliases: ["address", "target", "recipient"])
    var to: String

    /// The text of the message.
    @Guide(description: "The full text. The target sees only this text.")
    @OperationParam(aliases: ["text", "content", "body"])
    var message: String
}

extension SendMessage {
    /// Sends the message from the caller to each session that `to` names.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: One line for each receipt. A corrective for a call with no
    ///   caller, a blank message, an address in no form, a send that no
    ///   target took, or an error of the directory.
    func execute(in context: SessionsToolContext) async throws -> String {
        await context.answer(asCallerOf: Self.opString) { callerID in
            let sender = SessionMessageSender.session(callerID)
            let reading = try await context.sessions.messageAddress(to, from: sender)
            let receipts = try await context.send(text: message, to: reading.address, from: sender)
            return SessionsToolText.receipts(receipts, rewrite: reading.rewrite?.report)
        }
    }
}

/// Answers a message that the caller got (`reply message`).
@Generable
@Operation(
    verb: "reply", noun: "message",
    description: """
        Reply to a message that another session sent you. The reply goes to the sender of that message. \
        Gives what happened at the target.
        """)
struct ReplyMessage {
    /// The id of the message to answer.
    @Guide(description: "The id of a message that you got, from readInbox.")
    @OperationParam(aliases: ["messageId", "replyTo", "id"])
    var inReplyTo: String

    /// The text of the reply.
    @Guide(description: "The full text of the reply. The sender sees only this text.")
    @OperationParam(aliases: ["text", "content", "body"])
    var message: String
}

extension ReplyMessage {
    /// Sends the reply to the session that sent the message `inReplyTo`,
    /// with `inReplyTo` in its record.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: One line for each receipt. A corrective for a call with no
    ///   caller, a text that is not a message id, an id that no message to
    ///   the caller has, a message from the user, a blank message, a send
    ///   that no target took, or an error of the directory.
    func execute(in context: SessionsToolContext) async throws -> String {
        await context.answer(asCallerOf: Self.opString) { callerID in
            let original = try await context.replyTarget(of: inReplyTo, to: callerID)
            let receipts = try await context.send(
                text: message, to: .session(original.sender), inReplyTo: original.id, from: .session(callerID))
            return SessionsToolText.receipts(receipts)
        }
    }
}

extension SessionsToolContext {
    /// Sends `text` from `sender` to `address`, for `send message`,
    /// `reply message` and the `sendMessage` and `replyMessage` mutations.
    ///
    /// The address of an agent comes from `@<name>` that names no session
    /// (D199 (e)). The launcher of the directory is the agent catalog: when
    /// no agent folder has the name, the send refuses with the corrective
    /// that no session and no agent has the name.
    ///
    /// - Parameters:
    ///   - text: The text of the message.
    ///   - address: The target of the message.
    ///   - inReplyTo: The id of the message that this one answers, or `nil`.
    ///   - sender: The session or the user that sends the message.
    ///   - sourceSession: The session in which the user wrote the message
    ///     (D199 (f)), or `nil`. Only a user sender uses it. The default is
    ///     `nil`.
    /// - Returns: One receipt for each target.
    /// - Throws: ``SessionsRefusal`` for a blank text and for an agent name
    ///   that no agent has, and each other error of
    ///   `SessionDirectory.send(_:)`.
    func send(
        text: String, to address: SessionAddress, inReplyTo: MailID? = nil, from sender: SessionMessageSender,
        sourceSession: ULID? = nil
    ) async throws -> [SessionSendReceipt] {
        let body = try SessionsToolInput.requiredText(text, parameter: SessionsToolText.messageParameter)
        let outgoing = OutgoingSessionMessage(
            from: sender, to: address, text: body, inReplyTo: inReplyTo, sourceSession: sourceSession)
        do {
            return try await directory.send(outgoing)
        } catch SessionDirectoryError.unknownAgent(let name, let nearNames) {
            throw SessionsRefusal(.unknownAgent, SessionsToolText.noSessionOrAgent(name, nearNames: nearNames))
        }
    }

    /// The message that a reply answers, and the session that sent it, for
    /// `reply message` and the `replyMessage` mutation.
    ///
    /// - Parameters:
    ///   - text: The text of the id of the message.
    ///   - recipient: The session that got the message.
    /// - Returns: The id of the message, and the session that sent it, which
    ///   the reply goes to.
    /// - Throws: ``SessionsRefusal`` for a text that is not a message id or
    ///   a message from the user, ``SessionsUnknownMessage`` for an id that
    ///   no message to `recipient` has, and each error of `message(_:to:)`.
    func replyTarget(of text: String, to recipient: ULID) async throws -> (id: MailID, sender: ULID) {
        let originalID = try SessionsToolInput.messageID(text)
        guard let original = try await directory.message(originalID, to: recipient) else {
            throw SessionsUnknownMessage(id: originalID)
        }
        guard case .session(let sender) = original.from else {
            throw SessionsRefusal(.userMessage, SessionsToolText.replyToUser(originalID))
        }
        return (originalID, sender)
    }
}
