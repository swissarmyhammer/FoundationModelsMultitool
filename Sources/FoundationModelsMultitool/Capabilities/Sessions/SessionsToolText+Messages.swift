// The text of the message operations of the `sessions` tool: the answers of
// `send message` and `reply message`, and their correctives (session.md
// sections 8.2, 9 and 10).
//
// The answer gives one line for each receipt of the directory. When no target
// took the message, the answer is a corrective: it says so first, and each
// line names the reason of its refusal, as session.md section 10.3 says.

import Foundation
import FoundationModelsExtras
import ULID

extension SessionsToolText {
    /// The note of a `sent` receipt to an archived target (D204). The
    /// directory does not refuse an archived target: the message waits in its
    /// inbox.
    static let archivedReason = "archived"

    /// The sentence of a `sent` receipt with the note ``archivedReason``: the
    /// message waits in the inbox of the archived session (D204).
    static let archivedNoteSentence =
        "The session is archived. The message waits in its inbox until the user unarchives and opens it."

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
        one session as @<id>, <id>, @<short id>, <short id> or @<slug> (an agent name that no session has \
        starts a new session of that agent), or #tag for each live session with the tag
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
    /// first. An archived target does not refuse a message (D204), so a
    /// refusal gets no advice after its line.
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
        return ([notSentSentence] + lines).joined(separator: "\n")
    }

    /// The corrective of a reference that names more than one session (D199
    /// (d), D200 (e)): the call did nothing, and each match shows with its
    /// id, its name and its folder.
    ///
    /// - Parameters:
    ///   - reference: The reference, as written.
    ///   - matches: The sessions that match.
    ///   - outcome: The sentence that tells what the call did not do:
    ///     ``notSentSentence`` for a message, ``notChangedSentence`` for a
    ///     session operation.
    /// - Returns: The corrective.
    static func ambiguousReference(_ reference: String, matches: [SessionSummary], outcome: String) -> String {
        let lines = matches.map { match in
            "- \(match.id.ulidString): name \"\(name(of: match))\", folder \(match.workingDirectory.path)"
        }
        let heading = """
            "\(reference)" names more than one session. \(outcome) \
            Give the id or the short id of one of these sessions:
            """
        return ([heading] + lines).joined(separator: "\n")
    }

    /// The corrective of `@<name>` when no session and no agent has the name
    /// (D199 (e), (h)).
    ///
    /// - Parameters:
    ///   - name: The name after the `@`.
    ///   - nearNames: The agents with a near name.
    /// - Returns: The corrective, which names `listSessions`.
    static func noSessionOrAgent(_ name: String, nearNames: [String]) -> String {
        let near = nearNames.isEmpty ? "" : " Agents with a near name: \(nearNames.joined(separator: ", "))."
        return """
            No session and no agent has the name "\(name)". \(notSentSentence)\(near) \(findSessionSentence)
            """
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
        case .sent:
            let written =
                "- Sent to \(session): the message is written to the inbox of the session and not yet delivered."
            return written + note(of: receipt) + messageID
        }
    }

    /// The note of a `sent` receipt, after the outcome of its line: the
    /// sentence of the note ``archivedReason``, or nothing.
    ///
    /// - Parameter receipt: The `sent` receipt.
    /// - Returns: The note with a space before it, or an empty text.
    private static func note(of receipt: SessionSendReceipt) -> String {
        receipt.reason == archivedReason ? " \(archivedNoteSentence)" : ""
    }
}
