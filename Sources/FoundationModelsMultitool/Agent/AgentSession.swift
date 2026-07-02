import FoundationModelsRouter

/// The minimal seam `MultiToolAgent` drives each turn through: send a
/// prompt, get text back.
///
/// Plan.md's Router-integration finding is that `RoutedSession` (Router's
/// own actor protocol) already has exactly this shape — `respond(to:) async
/// throws -> String`, for both a plain session
/// (`RoutedLLM.makeSession(instructions:workingDirectory:)`) and a guided
/// one (`RoutedLLM.makeGuidedSession(_:instructions:workingDirectory:)`),
/// which constrains its output internally but still returns plain text
/// through the same method.
///
/// `MultiToolAgent` depends on this seam — never on `RoutedSession` or
/// `RoutedLLM` directly — so a unit test can drive the loop against a
/// scripted fake conforming to this protocol, with zero GPU and no Router
/// dependency at all. `RoutedAgentSession` below is the only production
/// conformer, adapting a real `RoutedSession` to it.
protocol AgentSession: Sendable {
    /// Sends `prompt` to the session and returns its complete text response.
    ///
    /// - Parameter prompt: the prompt to respond to — for `MultiToolAgent`,
    ///   the running transcript for this turn (see
    ///   `MultiToolAgent.respond(to:)`).
    /// - Returns: the session's complete text response.
    /// - Throws: whatever the underlying session throws.
    func respond(to prompt: String) async throws -> String
}

/// Adapts a Router `RoutedSession` to the `AgentSession` seam
/// `MultiToolAgent` drives.
///
/// A thin wrapper, not a reimplementation: every call forwards to the
/// wrapped session unchanged. `RoutedSession` is itself an `Actor`-bound
/// protocol (Router's session is a real actor internally), so this struct
/// only ever holds the existential and `await`s across it — it adds no
/// state and no synchronization of its own.
struct RoutedAgentSession: AgentSession {
    /// The Router session every call forwards to.
    private let session: any RoutedSession

    /// Wraps `session` as an `AgentSession`.
    ///
    /// - Parameter session: the Router session to adapt. Vended by
    ///   `RoutedLLM.makeSession(instructions:workingDirectory:)` (plain) or
    ///   `RoutedLLM.makeGuidedSession(_:instructions:workingDirectory:)`
    ///   (guided) — both satisfy `RoutedSession`, so both adapt identically
    ///   here.
    init(session: any RoutedSession) {
        self.session = session
    }

    func respond(to prompt: String) async throws -> String {
        try await session.respond(to: prompt)
    }
}
