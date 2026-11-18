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
        return try await visible(among: directory.sessions(matching: Self.unbounded(query)), limit: query.limit)
    }

    /// The summaries of the sessions that match `query`, that `accepts`
    /// keeps, and that the viewer can see, in the order of their ids, each
    /// with an id after `cursor`. At most ``SessionQuery/limit`` of them.
    ///
    /// The id order is stable: a session that starts later has a newer id,
    /// thus it comes after each session that a reader already got. The
    /// directory gives each match, and the limit cuts the visible ones.
    ///
    /// - Parameters:
    ///   - query: The filter. Its order is not read.
    ///   - cursor: The id that each summary must come after, or `nil` for
    ///     the first summaries.
    ///   - accepts: Tells if a summary that matches `query` can be in the
    ///     result.
    /// - Returns: The summaries.
    /// - Throws: The error of the directory.
    func sessionsInIDOrder(
        matching query: SessionQuery, after cursor: ULID?, where accepts: (SessionSummary) -> Bool
    ) async throws -> [SessionSummary] {
        let candidates = try await directory.sessions(matching: Self.unbounded(query))
            .filter { summary in accepts(summary) && cursor.map { summary.id > $0 } ?? true }
            .sorted { $0.id < $1.id }
        return try await visible(among: candidates, limit: query.limit)
    }

    /// The query with the limit ``unboundedLimit``, so the directory gives
    /// each match.
    ///
    /// - Parameter query: The filter.
    /// - Returns: The query with no limit.
    private static func unbounded(_ query: SessionQuery) -> SessionQuery {
        var unbounded = query
        unbounded.limit = unboundedLimit
        return unbounded
    }

    /// The first `limit` summaries of `candidates` that the viewer can see,
    /// in the order of `candidates`.
    ///
    /// - Parameters:
    ///   - candidates: The summaries, in the order of the result.
    ///   - limit: The most summaries to give.
    /// - Returns: The summaries.
    /// - Throws: The error of the directory.
    private func visible(among candidates: [SessionSummary], limit: Int) async throws -> [SessionSummary] {
        guard externalViewer != nil else {
            return Array(candidates.prefix(limit))
        }
        var visible: [SessionSummary] = []
        // A loop and not a `filter`: each check awaits the directory, and the
        // loop stops at the limit.
        for summary in candidates where visible.count < limit {
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
