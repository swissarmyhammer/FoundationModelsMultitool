// `SessionSharer` — the share of a session as a link over iCloud sharing,
// which the host gives (D208 (k)).
//
// This package does not link FoundationModelsACP and does not name CloudKit.
// The snapshot of a session is built in FoundationModelsACPAgent, and the
// app keeps the share in CloudKit. Thus the host gives the share through this
// protocol, and the `share session`, `update share` and `stop sharing`
// operations of the `sessions` tool call it.

import Foundation
import ULID

/// Shares a session as a read-only link, updates the snapshot of the share,
/// and stops the share.
///
/// A host gives one to ``SessionsTool/init(directory:exporter:searcher:sharer:externalSessionHost:)``
/// and to ``SessionsGraph/endpoint(of:exporter:searcher:sharer:externalSessionHost:)``. With no
/// sharer, the share operations give the corrective of the code
/// `SHARING_UNAVAILABLE`.
///
/// A share is a snapshot of the session (D208 (a)). The tool never reads the
/// content of the snapshot: each answer gives the URL and the state of the
/// share only.
public protocol SessionSharer: Sendable {
    /// Makes a new share of a session, with a snapshot of the session now.
    ///
    /// The tool calls this only for a session that has no share
    /// (``share(of:)`` gives `nil`).
    ///
    /// - Parameters:
    ///   - session: The id of the session.
    ///   - options: The content and the state of the share.
    /// - Returns: The new share.
    /// - Throws: An error when the host cannot build the snapshot or save
    ///   the share.
    func share(_ session: ULID, options: SessionShareOptions) async throws -> SessionShare

    /// Replaces the snapshot of the share of a session with a snapshot of
    /// the session now, and keeps `options` with the share. The URL of the
    /// share does not change.
    ///
    /// The tool calls this only for a session that has a share. It gives
    /// the options of that share, with the switch Keep Updated that the call
    /// asks for.
    ///
    /// - Parameters:
    ///   - session: The id of the session.
    ///   - options: The options of the share after the update.
    /// - Returns: The updated share.
    /// - Throws: An error when the host cannot build the snapshot or save
    ///   the share.
    func update(_ session: ULID, options: SessionShareOptions) async throws -> SessionShare

    /// Stops the share of a session: the link then opens nothing.
    ///
    /// The tool calls this only for a session that has a share.
    ///
    /// - Parameter session: The id of the session.
    /// - Throws: An error when the host cannot remove the share.
    func stop(_ session: ULID) async throws

    /// The share of a session.
    ///
    /// - Parameter session: The id of the session.
    /// - Returns: The share, or `nil` when the session has no share.
    /// - Throws: An error when the host cannot read the share.
    func share(of session: ULID) async throws -> SessionShare?

    /// The ids of the sessions whose share changed outside a call of this
    /// package: for example, the owner stopped the share on a different
    /// device, CloudKit deleted the zone of the share, or a participant left
    /// the share.
    ///
    /// The `sessions` endpoint reads the stream and puts each change into
    /// the change feed of the session. A host that has no change from
    /// outside does not write this requirement: the default stream finishes
    /// at once, with no element.
    ///
    /// - Returns: A stream that yields the id of each session whose share
    ///   changed.
    func shareChanges() -> AsyncStream<ULID>
}

extension SessionSharer {
    /// A stream that finishes at once, with no element: the host has no
    /// change of a share from outside a call of this package.
    ///
    /// - Returns: The empty stream.
    public func shareChanges() -> AsyncStream<ULID> {
        AsyncStream { $0.finish() }
    }
}

/// The content and the state of the share of a session (D208 (d), (f),
/// (g)).
public struct SessionShareOptions: Sendable, Equatable, Codable {
    /// The options of `share session` when the call gives no option: the
    /// thoughts and the tool output are in the share (Q76), anyone with the
    /// link can open it (Q75), and the share is frozen (Q74). This is the
    /// one place of these defaults.
    public static let defaults = SessionShareOptions(
        includeThoughts: true, includeToolOutput: true, anyoneWithLink: true, keepUpdated: false)

    /// True when the snapshot has the thoughts of the agent.
    public var includeThoughts: Bool

    /// True when the snapshot has the output of the tool calls.
    public var includeToolOutput: Bool

    /// True when anyone with the link can open the share. False when only
    /// the invited people can open it.
    public var anyoneWithLink: Bool

    /// True when the host updates the snapshot at the end of each turn of
    /// the session. False when the snapshot changes only on an update.
    public var keepUpdated: Bool

    /// Makes the options.
    ///
    /// - Parameters:
    ///   - includeThoughts: True to put the thoughts of the agent in the
    ///     snapshot.
    ///   - includeToolOutput: True to put the output of the tool calls in
    ///     the snapshot.
    ///   - anyoneWithLink: True when anyone with the link can open the
    ///     share.
    ///   - keepUpdated: True to update the snapshot at the end of each turn.
    public init(includeThoughts: Bool, includeToolOutput: Bool, anyoneWithLink: Bool, keepUpdated: Bool) {
        self.includeThoughts = includeThoughts
        self.includeToolOutput = includeToolOutput
        self.anyoneWithLink = anyoneWithLink
        self.keepUpdated = keepUpdated
    }
}

/// The share of a session: its link and its state, never its content.
public struct SessionShare: Sendable, Equatable, Codable {
    /// The link of the share.
    public var url: URL

    /// True when anyone with the link can open the share now. The owner can
    /// change this in the share UI of the system, so it can be different
    /// from ``options``.
    public var anyoneWithLink: Bool

    /// The options of the share.
    public var options: SessionShareOptions

    /// The time of the snapshot of the share.
    public var updatedAt: Date

    /// Makes a share.
    ///
    /// - Parameters:
    ///   - url: The link of the share.
    ///   - anyoneWithLink: True when anyone with the link can open the
    ///     share now.
    ///   - options: The options of the share.
    ///   - updatedAt: The time of the snapshot of the share.
    public init(url: URL, anyoneWithLink: Bool, options: SessionShareOptions, updatedAt: Date) {
        self.url = url
        self.anyoneWithLink = anyoneWithLink
        self.options = options
        self.updatedAt = updatedAt
    }
}
