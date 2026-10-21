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
/// | `external` | the sessions that it owns, their subagents, and the sessions that they started, to any depth |
///
/// A session is thus visible to an external client when the client owns it,
/// or owns a session up its chain of anchors: the anchor of a subagent is its
/// parent, and the anchor of each other session is the session that started
/// it. A fork has the original as its parent, but it is not a subagent, thus
/// the original does not make it visible.
///
/// The `sessions` tool reads the directory through it with no viewer: the
/// agent of the session sees each session. The `sessions` endpoint reads it
/// with the viewer of each call.
struct SessionsVisibility: Sendable {
    /// The limit of a directory query that must give each match: a list for
    /// an external client is cut after the visibility rule, not before.
    static let unboundedLimit = Int.max

    /// The session directory.
    let directory: any SessionDirectory

    /// The client that reads the directory, or `nil` for the agent.
    let viewer: GraphQLViewer?

    /// The external client that reads the directory, or `nil` when the
    /// reader sees each session.
    private var externalViewer: GraphQLViewer? {
        switch viewer?.trust {
        case nil, .userDevice:
            nil
        case .external:
            viewer
        }
    }

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
        guard let externalViewer else {
            return try await directory.sessions(matching: query)
        }
        var unbounded = query
        unbounded.limit = Self.unboundedLimit
        var visible: [SessionSummary] = []
        // A loop and not a `filter`: each check awaits the directory, and the
        // loop stops at the limit.
        for summary in try await directory.sessions(matching: unbounded) where visible.count < query.limit {
            if try await isVisible(summary, to: externalViewer) {
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
        guard let externalViewer else {
            return summary
        }
        return try await isVisible(summary, to: externalViewer) ? summary : nil
    }

    /// Tells if an external client can see a session: it owns the session,
    /// or a session up its chain of anchors.
    ///
    /// - Parameters:
    ///   - summary: The session.
    ///   - client: The external client.
    /// - Returns: `true` when the client can see the session.
    /// - Throws: The error of the directory.
    private func isVisible(_ summary: SessionSummary, to client: GraphQLViewer) async throws -> Bool {
        var visited: Set<ULID> = []
        var current: SessionSummary? = summary
        // A chain that loops back ends: each session is checked one time.
        while let session = current, visited.insert(session.id).inserted {
            if client.owns(session.id.ulidString) {
                return true
            }
            current = try await anchor(of: session)
        }
        return false
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
