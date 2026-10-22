// `SessionsVisibility` — the one visibility rule of the sessions of the
// server (session.md section 11.3, EXTRAS-9 rule 4), which the `sessions`
// tool and the `sessions` GraphQL endpoint share (MT-10).

import FoundationModelsExtras
import ULID

/// The sessions of a directory as one viewer sees them.
///
/// | Viewer | Sees |
/// |--------|------|
/// | none: the agent of the session | each session |
/// | `userDevice` | each session |
/// | `external` | the sessions that it owns or that its connection started, their subagents, and the sessions that they started, to any depth |
///
/// A session is thus visible to an external client when the client owns it or
/// its connection started it, or the same holds for a session up its chain of
/// anchors: the anchor of a subagent is its parent, and the anchor of each
/// other session is the session that started it. A fork has the original as
/// its parent, but it is not a subagent, thus the original does not make it
/// visible. A session that the connection started stays visible after another
/// client takes it over; a tag, an untag, a rename, a send and a reply still
/// need the client to own it.
///
/// The `sessions` tool reads the directory through it with no viewer: the
/// agent of the session sees each session. The `sessions` endpoint reads it
/// with the viewer of each call.
struct SessionsVisibility: Sendable, GraphQLViewerScoping {
    /// The limit of a directory query that must give each match: a list for
    /// an external client is cut after the visibility rule, not before.
    static let unboundedLimit = Int.max

    /// The session directory.
    let directory: any SessionDirectory

    /// The client that reads the directory, or `nil` for the agent.
    let viewer: GraphQLViewer?

    /// The summaries of the sessions that match `query` and that the viewer
    /// can see, at most ``SessionQuery/limit`` of them, the newest first.
    ///
    /// For an external client the directory gives each match, and the limit
    /// cuts the visible ones, thus a visible session is never lost behind
    /// newer sessions that the client cannot see.
    ///
    /// - Parameter query: The filter.
    /// - Returns: The summaries.
    /// - Throws: The error of the directory.
    func sessions(matching query: SessionQuery) async throws -> [SessionSummary] {
        guard externalViewer != nil else {
            return try await directory.sessions(matching: query)
        }
        var unbounded = query
        unbounded.limit = Self.unboundedLimit
        var visible: [SessionSummary] = []
        // A loop and not a `filter`: each check awaits the directory, and the
        // loop stops at the limit.
        for summary in try await directory.sessions(matching: unbounded) where visible.count < query.limit {
            if try await isVisible(summary) {
                visible.append(summary)
            }
        }
        return visible
    }

    /// The summary of the session `id` when the viewer can see it.
    ///
    /// - Parameter id: The session id.
    /// - Returns: The summary, or `nil` when no session has the id or the
    ///   viewer cannot see it.
    /// - Throws: The error of the directory.
    func summary(of id: ULID) async throws -> SessionSummary? {
        guard let summary = try await directory.summary(of: id) else {
            return nil
        }
        guard externalViewer != nil else {
            return summary
        }
        return try await isVisible(summary) ? summary : nil
    }

    /// Tells if the viewer can see a session, from its chain of anchors.
    ///
    /// This is the rule itself, with no read of the directory, so a reader
    /// that holds the chain, for example the change feed of the `sessions`
    /// endpoint, applies it at once. The agent and a device of the user see
    /// each session; an external client sees a session when it owns a
    /// session of the chain, or its connection started one.
    ///
    /// - Parameter chain: The session and its anchors, as
    ///   ``anchorChain(of:)`` gives them.
    /// - Returns: `true` when the viewer can see the session.
    func sees(anchorChain chain: [ULID]) -> Bool {
        admits { client in chain.contains { client.isOwnerOrStarter(of: $0.ulidString) } }
    }

    /// The chain of anchors of a session: the session first, then its
    /// anchor, the anchor of that anchor, and so on. The chain reads the
    /// directory, and does not depend on the viewer.
    ///
    /// A chain that loops back ends: each session is in it one time. A
    /// session whose anchor the directory does not hold ends the chain.
    ///
    /// - Parameter summary: The session.
    /// - Returns: The ids of the chain, the session first.
    /// - Throws: The error of the directory.
    func anchorChain(of summary: SessionSummary) async throws -> [ULID] {
        var chain: [ULID] = []
        var visited: Set<ULID> = []
        var current: SessionSummary? = summary
        while let session = current, visited.insert(session.id).inserted {
            chain.append(session.id)
            current = try await anchor(of: session)
        }
        return chain
    }

    /// Tells if the viewer can see a session: an external client sees it
    /// when it owns or started the session, or a session up its chain of
    /// anchors.
    ///
    /// - Parameter summary: The session.
    /// - Returns: `true` when the viewer can see the session.
    /// - Throws: The error of the directory.
    private func isVisible(_ summary: SessionSummary) async throws -> Bool {
        sees(anchorChain: try await anchorChain(of: summary))
    }

    /// The anchor of a session: the parent of a subagent, or the session
    /// that started each other session.
    ///
    /// - Parameter session: The session.
    /// - Returns: The anchor, or `nil` when the session has none or the
    ///   directory does not hold it.
    /// - Throws: The error of the directory.
    private func anchor(of session: SessionSummary) async throws -> SessionSummary? {
        let anchorID = session.kind == .subagent ? session.parentID : session.startedBy
        guard let anchorID else {
            return nil
        }
        return try await directory.summary(of: anchorID)
    }
}
