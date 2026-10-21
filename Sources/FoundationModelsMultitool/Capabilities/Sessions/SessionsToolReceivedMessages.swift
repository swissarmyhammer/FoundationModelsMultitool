// `SessionsToolReceivedMessages` — the record of the messages that
// `read inbox` gave to each caller session, which `reply message` reads.
//
// The port of the session directory gives no message by its id:
// `inbox(of:markRead:)` gives only the unread messages, and `read inbox`
// marks each message read. Thus a reply to a message that `read inbox` gave
// finds that message here. The record lives in memory, one for each
// `SessionsTool`, and every copy of that tool shares it. It keeps the newest
// messages up to a limit.

import FoundationModelsExtras
import ULID

/// The messages that `read inbox` gave, by their id, the newest ones up to a
/// limit.
actor SessionsToolReceivedMessages {
    /// The most messages that the record keeps by default.
    static let defaultLimit = 1_000

    /// The most messages that the record keeps. A record past it forgets the
    /// oldest messages first.
    private let limit: Int

    /// Each kept message, by its id.
    private var messages: [MailID: SessionMessage] = [:]

    /// The id of each kept message, the oldest first.
    private var order: [MailID] = []

    /// Makes an empty record.
    ///
    /// - Parameter limit: The most messages that the record keeps. The default
    ///   is ``defaultLimit``.
    init(limit: Int = defaultLimit) {
        self.limit = limit
    }

    /// Keeps `read`, and forgets the oldest messages past the limit.
    ///
    /// - Parameter read: The messages that one `read inbox` call gave, the
    ///   oldest first.
    func record(_ read: [SessionMessage]) {
        let newIDs = read.map(\.id).filter { messages[$0] == nil }
        messages.merge(read.map { ($0.id, $0) }) { _, newer in newer }
        order.append(contentsOf: newIDs)
        let excess = max(order.count - limit, 0)
        for id in order.prefix(excess) {
            messages[id] = nil
        }
        order.removeFirst(excess)
    }

    /// The kept message `id`, when it went to `recipient`.
    ///
    /// - Parameters:
    ///   - id: The id of the message.
    ///   - recipient: The session that asks for it.
    /// - Returns: The message, or `nil` when the record keeps no message with
    ///   the id that went to `recipient`.
    func message(_ id: MailID, to recipient: ULID) -> SessionMessage? {
        messages[id].flatMap { $0.to == recipient ? $0 : nil }
    }
}
