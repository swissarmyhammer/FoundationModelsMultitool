// The text of the `share session`, `update share` and `stop sharing`
// operations of the `sessions` tool: their answers and their correctives
// (D208 (k)).
//
// The answer gives the link and the state of the share, never the content:
// the tool never reads the snapshot of a share.

import Foundation
import ULID

extension SessionsToolText {
    /// The name of the UI command that shares a session, which the
    /// corrective of a server that cannot share names.
    static let shareUICommand = "Share Session…"

    /// The corrective of a share operation on a server whose host gives no
    /// sharer.
    static let noSharer = """
        This server cannot share a session: its host gives no session sharer. Nothing was shared. The user can \
        share a session with the command \(shareUICommand) of the Session menu.
        """

    /// The answer of `share session` and of `update share`: what the call
    /// did, and the link and the state of the share.
    ///
    /// - Parameters:
    ///   - share: The share.
    ///   - id: The shared session.
    ///   - change: What the call did to the share.
    /// - Returns: The answer, which has no content of the session.
    static func shareAnswer(_ share: SessionShare, of id: ULID, change: SessionShareChange) -> String {
        "\(changeSentence(change, of: id)) \(shareState(share))"
    }

    /// The answer of `stop sharing`.
    ///
    /// - Parameter id: The session.
    /// - Returns: The answer.
    static func sharingStopped(_ id: ULID) -> String {
        """
        Stopped the share of session \(id.ulidString). Its link opens nothing now. Copies that people saved stay.
        """
    }

    /// The corrective of `update share` and `stop sharing` on a session that
    /// has no share.
    ///
    /// - Parameter id: The session.
    /// - Returns: The corrective, which names `share session`.
    static func notShared(_ id: ULID) -> String {
        """
        Session \(id.ulidString) has no share. Nothing changed. To share it, use \(ShareSession.opString).
        """
    }

    /// The corrective of a sharer that failed.
    ///
    /// - Parameters:
    ///   - id: The session.
    ///   - error: The error of the sharer.
    /// - Returns: The corrective, which names the error and the UI command.
    static func shareFailed(_ id: ULID, error: any Error) -> String {
        """
        The share of session \(id.ulidString) failed: \(error). The user can share a session with the command \
        \(shareUICommand) of the Session menu.
        """
    }

    /// The first sentence of a share answer: what the call did.
    ///
    /// - Parameters:
    ///   - change: What the call did to the share.
    ///   - id: The session.
    /// - Returns: The sentence.
    private static func changeSentence(_ change: SessionShareChange, of id: ULID) -> String {
        switch change {
        case .new:
            "Shared session \(id.ulidString)."
        case .existing:
            "Session \(id.ulidString) has a share already. Nothing changed. To update it, use \(UpdateShare.opString)."
        case .updated:
            "Updated the share of session \(id.ulidString)."
        }
    }

    /// The link and the state of a share.
    ///
    /// - Parameter share: The share.
    /// - Returns: One sentence for each fact of the state.
    private static func shareState(_ share: SessionShare) -> String {
        let access = share.anyoneWithLink ? "anyone with the link" : "only the invited people"
        return """
            Link: \(share.url.absoluteString). Who can open it: \(access). \
            Thoughts: \(inShare(share.options.includeThoughts)). \
            Tool output: \(inShare(share.options.includeToolOutput)). \
            Keep Updated: \(share.options.keepUpdated ? "on" : "off"). \
            Updated: \(share.updatedAt.formatted(.iso8601)).
            """
    }

    /// The words that tell whether a part of the session is in the share.
    ///
    /// - Parameter isIncluded: True when the part is in the share.
    /// - Returns: The words.
    private static func inShare(_ isIncluded: Bool) -> String {
        isIncluded ? "in the share" : "not in the share"
    }
}
