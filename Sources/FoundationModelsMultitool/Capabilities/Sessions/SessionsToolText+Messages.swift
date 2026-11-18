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
        one session as @<id>, <id>, @<short id>, <short id> or @<slug> (an agent name that no session has \
        starts a new session of that agent), #tag for each live session with the tag, or the aliases @agent:/path \
        and an absolute folder path that starts with / or ~
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

    /// The answer of `send message`: the report of the rewrite of an alias
    /// when the address is one, then the lines of ``receipts(_:)``.
    ///
    /// - Parameters:
    ///   - receipts: The receipts of the send.
    ///   - rewrite: The report of the rewrite of an alias, or `nil`.
    /// - Returns: The answer.
    static func receipts(_ receipts: [SessionSendReceipt], rewrite: String?) -> String {
        ([rewrite].compactMap { $0 } + [self.receipts(receipts)]).joined(separator: "\n")
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
            "- \(match.id.ulidString): name \"\(match.title ?? match.slug)\", folder \(match.workingDirectory.path)"
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

    /// The report of the rewrite of the alias `@agent:/path` (D199 (e), in
    /// the style of D86): the reader reads it as `@agent`, with the lookup in
    /// the folder of the alias first.
    ///
    /// - Parameters:
    ///   - alias: The address as written.
    ///   - name: The name after the `@`.
    ///   - folder: The folder of the alias.
    /// - Returns: The report.
    static func agentAliasRewrite(_ alias: String, name: String, folder: URL) -> String {
        """
        Rewrite: "\(alias)" is an alias of \(agentAliasCanonical(name: name, folder: folder)), \
        in place of the folder of your session.
        """
    }

    /// The canonical form of the alias `@agent:/path`, as
    /// ``agentAliasRewrite(_:name:folder:)`` tells it: `@agent` with the
    /// lookup in the folder of the alias first.
    ///
    /// - Parameters:
    ///   - name: The name after the `@`.
    ///   - folder: The folder of the alias.
    /// - Returns: The canonical form.
    static func agentAliasCanonical(name: String, folder: URL) -> String {
        "\"@\(name)\", with the lookup in \(folder.path) first"
    }

    /// The report of the rewrite of the alias of a folder path alone (D199
    /// (e), in the style of D86): the path names the newest root session in
    /// the folder.
    ///
    /// - Parameters:
    ///   - alias: The address as written.
    ///   - folder: The folder.
    /// - Returns: The report.
    static func folderAliasRewrite(_ alias: String, folder: URL) -> String {
        """
        Rewrite: "\(alias)" is an alias of \(folderAliasCanonical(folder: folder)). \
        To name one session, give @<id>, @<short id> or @<slug>.
        """
    }

    /// The canonical form of the alias of a folder path alone, as
    /// ``folderAliasRewrite(_:folder:)`` tells it: the newest root session
    /// in the folder.
    ///
    /// - Parameter folder: The folder.
    /// - Returns: The canonical form.
    static func folderAliasCanonical(folder: URL) -> String {
        "the newest root session in \(folder.path)"
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
        case .sent:
            return
                "- Sent to \(session): the message is written to the inbox of the session and not yet delivered.\(messageID)"
        }
    }
}
