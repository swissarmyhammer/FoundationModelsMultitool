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
// TODO(MT-7): declare the risk facts of session.md section 8.3 on each
// operation (`send message` and `reply message` each send to another agent),
// when MT-1 and MT-7 land.

import Foundation
import FoundationModels
import FoundationModelsExtras
import Operations
import ULID

/// Sends a message to a session, an agent, a folder or a tag
/// (`send message`).
@Generable
@Operation(
    verb: "send", noun: "message",
    description: """
        Send a message to another session. Address it to a session id, @agent, @agent:/path, a folder path, \
        or #tag. An agent with no live session starts one. Gives what happened at each target.
        """)
struct SendMessage {
    /// The address of the message.
    @Guide(
        description: """
            The address: a session id, @agent (in the folder of your session), @agent:/path, \
            an absolute folder path (/path or ~/path), or #tag (each live session with the tag, but not yours).
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
            try await context.send(message, to: try SessionsToolInput.address(to), from: callerID)
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
            let originalID = try SessionsToolInput.messageID(inReplyTo)
            guard let original = try await context.receivedMessage(originalID, by: callerID) else {
                return SessionsToolText.unknownMessage(originalID)
            }
            guard case .session(let sender) = original.from else {
                return SessionsToolText.replyToUser(originalID)
            }
            return try await context.send(message, to: .session(sender), inReplyTo: originalID, from: callerID)
        }
    }
}

extension SessionsToolContext {
    /// Sends `text` from the caller to `address`, for `send message` and
    /// `reply message`.
    ///
    /// - Parameters:
    ///   - text: The text of the message.
    ///   - address: The target of the message.
    ///   - inReplyTo: The id of the message that this one answers, or `nil`.
    ///   - callerID: The caller session, which sends the message.
    /// - Returns: One line for each receipt, or the corrective of a send that
    ///   no target took.
    /// - Throws: ``SessionsToolInputError`` for a blank text, and each error
    ///   of `send(_:)`.
    func send(
        _ text: String, to address: SessionAddress, inReplyTo: MailID? = nil, from callerID: ULID
    ) async throws -> String {
        let body = try SessionsToolInput.requiredText(text, parameter: SessionsToolText.messageParameter)
        let outgoing = OutgoingSessionMessage(from: .session(callerID), to: address, text: body, inReplyTo: inReplyTo)
        return SessionsToolText.receipts(try await directory.send(outgoing))
    }
}
