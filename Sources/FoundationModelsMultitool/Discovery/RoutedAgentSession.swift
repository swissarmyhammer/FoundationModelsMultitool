import FoundationModelsRanker
import FoundationModelsRouter

// `RoutedAgentSession` — a Router session presented as an `AgentSession`.
//
// `FoundationModelsRanker` declared this type until `34fe8d4`, where it was
// removed. The supported route is now for each consumer to conform its own
// session type, thus this package holds the conformance. The shape is the one
// the ranker deleted, kept unchanged on purpose: a different shape here would
// be a third definition of the same seam, which is the outcome both packages
// want least.

/// A `RoutedSession` presented to the selection tier as an `AgentSession`.
///
/// The tier holds every session as `any AgentSession` and knows nothing of
/// Router. This is the whole of the join between the two.
struct RoutedAgentSession: AgentSession {

    /// The Router session every call travels to.
    private let session: any RoutedSession

    /// Makes the presentation over one Router session.
    ///
    /// - Parameter session: The session to present.
    init(session: any RoutedSession) {
        self.session = session
    }

    /// Sends `prompt` to the session and answers with its complete text.
    ///
    /// - Parameter prompt: The prompt to send.
    /// - Returns: The session's complete text response.
    /// - Throws: Whatever the underlying session throws.
    func respond(to prompt: String) async throws -> String {
        try await session.respond(to: prompt)
    }

    /// Forks a child session that continues this one's conversation.
    ///
    /// **This override is load-bearing, and the protocol default is wrong for
    /// a Router session.** `AgentSession.fork()` defaults to returning `self`,
    /// which is correct only for a session that cannot really fork. A
    /// `RoutedSession` forks at the cache level: the child gets a copy of the
    /// prefilled KV cache. Taking the default would leave the selection tier's
    /// cached-root path re-sending the assembled prefix on every call, and the
    /// loss would be silent — the tier would still answer correctly, only
    /// slower and at more tokens.
    ///
    /// - Returns: The forked child session.
    /// - Throws: Whatever the underlying session throws while forking.
    func fork() async throws -> any AgentSession {
        RoutedAgentSession(session: try await session.fork(workingDirectory: nil))
    }
}
