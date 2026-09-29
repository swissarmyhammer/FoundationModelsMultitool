import FoundationModelsMetadataRegistry
import Tracing

/// An `AgentSession` that records every call it forwards, and forwards
/// everything unchanged.
///
/// ## Why the seam is wrapped rather than the tier instrumented
///
/// The selection tier's two suspension points — forking its cached root
/// session, and generating a selection on the fork — both live inside
/// `SelectionTier`, in `FoundationModelsRanker`. This package cannot put a
/// span there. What it *does* own is the session the tier calls those two
/// methods on: `SelectionConfig.model` is a closure `SearchToolsTool` supplies,
/// so wrapping the session it returns is the one place from which those calls
/// are observable at all.
///
/// That matters because both are `async`. A call suspended in either occupies
/// no OS thread, so it appears in no sample and in no stack — see
/// ``MultitoolTelemetry/SpanName``. A `searchTools` call that never returns is
/// otherwise a silence with two candidate causes inside it, and these spans
/// tell them apart: an `agent_session.fork` enter record with no ended span,
/// or an `agent_session.respond` enter record with no ended span.
///
/// ## What it forwards
///
/// `respond(to:)` and `fork()` are the protocol's only requirements, and a
/// fork is wrapped again so a child's own calls stay traced. The generic
/// `respond(to:generating:)` is a protocol-extension default implemented over
/// `respond(to:)`, so it is covered without being restated here — restating it
/// would replace the shared default with a copy.
struct TracedAgentSession: AgentSession {
    /// The role a session vended for the searcher's selection tier carries.
    static let selectionRole = "selection"

    /// The role a session vended for sample-snippet generation carries.
    static let sampleSnippetRole = "sampleSnippet"

    /// The session every call is forwarded to.
    let wrapped: any AgentSession

    /// What this session is for — ``selectionRole`` or ``sampleSnippetRole``.
    ///
    /// Each span carries it, because one `searchTools` call can drive both
    /// and the two would otherwise be indistinguishable.
    let role: String

    /// Sends `prompt` to the wrapped session, recording the call.
    ///
    /// The span records the length of the prompt and of the response, never
    /// their text: a selection prompt carries the caller's own task
    /// description, and telemetry is not the place to copy it.
    ///
    /// - Parameter prompt: the prompt to respond to.
    /// - Returns: the wrapped session's complete text response.
    /// - Throws: whatever the wrapped session throws.
    func respond(to prompt: String) async throws -> String {
        try await MultitoolTelemetry.traced(
            .agentSessionRespond, attributes: [.sessionRole: role, .promptCharacters: prompt.count]
        ) { span in
            let response = try await wrapped.respond(to: prompt)
            span.attributes[MultitoolTelemetry.AttributeKey.outputCharacters.rawValue] = response.count
            return response
        }
    }

    /// Forks the wrapped session, recording the call, and traces the child too.
    ///
    /// - Returns: the forked child session, wrapped.
    /// - Throws: whatever the wrapped session throws while forking.
    func fork() async throws -> any AgentSession {
        try await MultitoolTelemetry.traced(.agentSessionFork, attributes: [.sessionRole: role]) { _ in
            TracedAgentSession(wrapped: try await wrapped.fork(), role: role)
        }
    }
}
