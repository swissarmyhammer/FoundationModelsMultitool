// The text of the message operations of the `sessions` tool: the answers of
// `send message` and `reply message`, and their correctives (session.md
// sections 8.2, 9 and 10).
//
// The answer gives one line for each receipt of the directory. When no target
// took the message, the answer is a corrective: it says so first, and each
// line names the reason of its refusal, as session.md section 10.3 says.

import FoundationModelsExtras
import ULID

extension SessionsToolText {
    /// The reason of a refusal of an archived target (session.md section 9).
    static let archivedReason = "archived"

    /// The first sentence of an answer in which no target took the message.
    static let notSentSentence = "The message was not sent."

    /// The answer of a send that gave no receipt.
    static let noTargetSentence = "No session took the message."

    /// The name of the target of a receipt with no target session.
    private static let unnamedTarget = "the target"

    /// The reason of a refusal whose receipt gives none.
    private static let noReason = "the directory gave no reason."

    /// The forms of a message address, for the corrective of a text in no
    /// form.
    static let addressForms = """
        a session id, @agent, @agent:/path, an absolute folder path that starts with / or ~, or #tag
        """

    /// The code-mode verb of `read inbox`, which each corrective about a
    /// message id names.
    static var readInboxVerb: String {
        OperationVerbTool.verbName(for: ReadInbox.opString)
    }

    /// The code-mode verb of `send message`, which the corrective of an
    /// unknown message names.
    static var sendMessageVerb: String {
        OperationVerbTool.verbName(for: SendMessage.opString)
    }

    /// The sentence that tells how to find the id of a message.
    private static var findMessageSentence: String {
        "Call \(readInboxVerb) (op `\(ReadInbox.opString)`) to get the id of a message."
    }

    /// The answer of `send message` and `reply message`: one line for each
    /// receipt. When no receipt took the message, ``notSentSentence`` comes
    /// first, and a refusal with the reason ``archivedReason`` adds the advice
    /// to start a new session.
    ///
    /// - Parameter receipts: The receipts of the send.
    /// - Returns: The answer.
    static func receipts(_ receipts: [SessionSendReceipt]) -> String {
        guard !receipts.isEmpty else {
            return noTargetSentence
        }
        let lines = receipts.map(line(for:))
        guard receipts.allSatisfy({ $0.outcome == .refused }) else {
            return lines.joined(separator: "\n")
        }
        let advice = receipts.contains { $0.reason == archivedReason } ? archivedAdvice : nil
        return ([notSentSentence] + lines + [advice].compactMap { $0 }).joined(separator: "\n")
    }

    /// The corrective of a text that names no message address.
    ///
    /// - Parameter text: The text.
    /// - Returns: The corrective, which names each form.
    static func notAnAddress(_ text: String) -> String {
        "\"\(text)\" is not a message address. Give \(addressForms). \(findSessionSentence)"
    }

    /// The corrective of a text that is not a message id.
    ///
    /// - Parameter text: The text.
    /// - Returns: The corrective, which names `readInbox`.
    static func notAMessageID(_ text: String) -> String {
        "\"\(text)\" is not a message id. A message id is a ULID of 26 characters. \(findMessageSentence)"
    }

    /// The corrective of a reply to an id that no message to the caller has.
    ///
    /// - Parameter id: The id.
    /// - Returns: The corrective, which names `readInbox` and `sendMessage`.
    static func unknownMessage(_ id: MailID) -> String {
        """
        You got no message with the id \(id). \(findMessageSentence) \
        To write to a session with no message to answer, call \(sendMessageVerb).
        """
    }

    /// The corrective of a reply to a message from the user.
    ///
    /// - Parameter id: The id of the message.
    /// - Returns: The corrective.
    static func replyToUser(_ id: MailID) -> String {
        """
        Message \(id) is from the user, not from a session. Answer the user in your own reply in this session; \
        reply message answers only a message from another session.
        """
    }

    /// The advice of a refusal with the reason ``archivedReason``, which names
    /// `startSession`.
    private static var archivedAdvice: String {
        "An archived session takes no messages. To go on with its work, call \(startSessionVerb) to start a new session."
    }

    /// The line of one receipt: what happened at the target, and the id of
    /// the message when the directory made one.
    ///
    /// - Parameter receipt: The receipt.
    /// - Returns: The line.
    private static func line(for receipt: SessionSendReceipt) -> String {
        let target = receipt.target.map { "session \($0.ulidString)" }
        let session = target ?? unnamedTarget
        let messageID = receipt.messageID.map { " Message id \($0)." } ?? ""
        switch receipt.outcome {
        case .delivered:
            return "- Delivered to \(session): it was idle, and the message starts a turn.\(messageID)"
        case .queued:
            return "- Queued for \(session): it works, and the message waits for the end of its turn.\(messageID)"
        case .started:
            return "- Started \(session) with the message as its first message. \(startSentence)\(messageID)"
        case .refused:
            let refuser = target.map { " by \($0)" } ?? ""
            return "- Refused\(refuser): \(receipt.reason ?? noReason)"
        }
    }
}
