// The model seams of `searchTools`.
//
// Discovery does not know which model backs it. The host picks the models and
// gives them through the seams of FoundationModelsMetadataRegistry, which
// re-exports them from FoundationModelsRanker: a `SelectionConfig` for the
// selection tier, an `any TextEmbedding` for the searchers, and an
// `AgentSession` factory for the sample snippet. The adapters from Router
// handles to these seams are in `MultitoolCLI` (`RouterDiscoverySeams`), which
// is the host this package ships.
//
// The models of these sessions must not be the model of the session that
// calls `searchTools` — see `SelectionFactory`.
//
// This file keeps what the library adds around each session a host makes: a
// `TracedAgentSession`, and a span over each factory call. Both
// ends of a session factory are opaque from outside, and these spans are the
// only thing that tells a slow search from a stalled one.

import FoundationModelsMetadataRegistry
import Tracing

extension SearchToolsTool {
    /// Makes the selection tier for one catalog, given the ids of that
    /// catalog.
    ///
    /// A factory, and not a `SelectionConfig`, because a host often limits
    /// the output of a selection session to the catalog ids with a grammar,
    /// and a session gets its grammar when it is made. The host cannot know
    /// the ids before the registry is built, so the library calls this
    /// factory with them. `SelectionTier.idEnumSchema(ids:)` gives a host the
    /// JSON Schema for those ids.
    ///
    /// **The selection model must not be the model of the session that calls
    /// `searchTools`.** `searchTools` is synchronous: its body runs inside
    /// the open submission of the calling session, and that submission ends
    /// only when the body returns. A host that queues the work of each model
    /// in order (Router does) cannot start a selection session on that same
    /// model before the submission ends. Such a host refuses the wait at once
    /// — Router gives its `waitInsideOpenSubmission` error — or the wait
    /// never ends. A selection session on a different model waits its turn
    /// on the queue of its own model, and the search completes. Thus, give
    /// the selection tier a model that is different from the model of each
    /// session that mounts `searchTools`. Router's `flash` slot is that model
    /// when `flash` and `standard` name different models.
    ///
    /// When the selection session fails, `searchTools` does not hide it: the
    /// error of the session is the error of the call, and the model reads it.
    ///
    /// - Parameter ids: every id of the catalog, in catalog order.
    /// - Returns: the selection configuration for that catalog.
    /// - Throws: what the host throws while it builds the configuration, for
    ///   example when it cannot encode a grammar.
    public typealias SelectionFactory = @Sendable (_ ids: [String]) throws -> SelectionConfig

    /// Makes one session that runs under the given instructions.
    ///
    /// The session must mount no tools — see
    /// ``SampleSnippetConfig/makeSession``.
    ///
    /// The session must also not run on the model of the session that calls
    /// `searchTools`, for the reason that ``SelectionFactory`` gives. When the
    /// session fails, `searchTools` shows the error as a note beside the
    /// signatures.
    ///
    /// - Parameter instructions: the instructions of the session.
    /// - Returns: the session.
    public typealias SessionFactory = @Sendable (_ instructions: String) -> any AgentSession

    /// The selection tier the host's `factory` makes for `ids`, with every
    /// session it vends traced, or `nil` when there is no factory and
    /// discovery answers by retrieval alone.
    ///
    /// The one place the selection tier is wired. `init(registry:...)` and
    /// `makeSessionToolsAndStaging` both build it here.
    ///
    /// **No `preamble:` of this package, and that is a decision this package
    /// measured.** This tool used to seed the tier with a wording of its own,
    /// because the ranker default that shipped then spoke of "items" and
    /// closed on "return an empty list if nothing fits": driven over the
    /// files-and-shell catalog with the agent's own ten queries
    /// (`AgentSurfaceDiscoveryTests`, card `^zqz1zan`),
    /// `mlx-community/Qwen3-4B-4bit` answered eight of the ten with
    /// `{"ids":[]}` — every query for a way to write, edit or run — and the
    /// bench run ended with an empty patch. Ranker card `^zxm99zs` moved the
    /// deciding sentence into `String.selectionDefault` itself: "Prefer the
    /// closest candidates over an empty answer; answer with an empty list only
    /// when no candidate is related to the task at all."
    ///
    /// Card `^46j5hqw` then measured the two wordings against each other on
    /// the same model, the same catalog and the same grammar, three rounds of
    /// the ten queries each. The ranker default answered 30 of 30, held the
    /// write, edit or shell verb in every one of queries 4 to 9 in all three
    /// rounds, and assembled a 7,601-character prefix against the local
    /// wording's 7,600. So the local constant was deleted and the default
    /// takes its place. The preamble is now the host's choice, and the host
    /// this package ships keeps the default — `RouterDiscoverySeamsTests`
    /// holds the deciding sentence as the guard the old constant carried.
    ///
    /// - Parameters:
    ///   - factory: the host's selection factory, or `nil`.
    ///   - ids: every id in the catalog, which the factory receives.
    /// - Returns: the selection configuration with traced sessions, or `nil`.
    /// - Throws: what `factory` throws.
    static func makeSelection(_ factory: SelectionFactory?, ids: [String]) throws -> SelectionConfig? {
        guard let factory else { return nil }
        var selection = try factory(ids)
        selection.sessionSource = traced(selection.sessionSource)
        return selection
    }

    /// The sample-snippet configuration over the host's `factory`, with every
    /// session it vends traced, or `nil` when there is no factory and
    /// discovery answers with the signatures alone.
    ///
    /// The one place sample generation is wired. `init(registry:...)` and
    /// `makeSessionToolsAndStaging` both build it here.
    ///
    /// - Parameter factory: the host's generation session factory, or `nil`.
    /// - Returns: the sample configuration, or `nil`.
    static func makeSample(sessionFactory factory: SessionFactory?) -> SampleSnippetConfig? {
        factory.map { factory in
            SampleSnippetConfig(makeSession: { instructions in
                tracedSession(
                    role: TracedAgentSession.sampleSnippetRole, instructions: instructions, make: factory)
            })
        }
    }

    /// `source` with every session it gives wrapped in a
    /// `TracedAgentSession` of the selection role.
    ///
    /// - Parameter source: the session source the host configured.
    /// - Returns: the same source, traced.
    private static func traced(_ source: SelectionSessionSource) -> SelectionSessionSource {
        switch source {
        case .factory(let factory):
            return .factory { instructions in
                try await tracedSelectionSession(instructions: instructions, make: factory)
            }
        case .session(let session):
            return .session(TracedAgentSession(wrapped: session, role: TracedAgentSession.selectionRole))
        }
    }

    /// Makes one selection session through the host's asynchronous `make`,
    /// inside a span, and wraps it in a `TracedAgentSession`.
    ///
    /// The selection factory can `await`, for example while a pooled model
    /// loads at the first request, and it can `throw`. The span stays open
    /// until the factory returns, so a slow load shows as a long
    /// `agent_session.make` span, and the "enter" record of the span shows a
    /// load that never ends. An error from `make` sets the error status of
    /// the span, and then comes out of this call unchanged.
    ///
    /// - Parameters:
    ///   - instructions: the instructions of the session.
    ///   - make: the host's selection factory.
    /// - Returns: the traced session.
    /// - Throws: what `make` throws.
    private static func tracedSelectionSession(
        instructions: String,
        make: @Sendable (String) async throws -> any AgentSession
    ) async throws -> any AgentSession {
        let role = TracedAgentSession.selectionRole
        return try await MultitoolTelemetry.traced(
            .agentSessionMake, attributes: makeSpanAttributes(role: role, instructions: instructions)
        ) { _ in
            TracedAgentSession(wrapped: try await make(instructions), role: role)
        }
    }

    /// Makes one session through the host's `make`, inside a span, and wraps
    /// it in a `TracedAgentSession`.
    ///
    /// Traced here because both ends of a factory are opaque from outside.
    /// The call is synchronous but not cheap, and everything done with the
    /// session it returns happens behind the `AgentSession` seam. See
    /// `TracedAgentSession`. The span is an `agent_session.make` span, and the
    /// role tells the sample factory from the selection factory, which
    /// ``tracedSelectionSession(instructions:make:)`` traces.
    ///
    /// - Parameters:
    ///   - role: the role the traced session reports.
    ///   - instructions: the instructions of the session.
    ///   - make: the host's factory.
    /// - Returns: the traced session.
    private static func tracedSession(
        role: String,
        instructions: String,
        make: SessionFactory
    ) -> any AgentSession {
        MultitoolTelemetry.tracedSynchronously(
            .agentSessionMake, attributes: makeSpanAttributes(role: role, instructions: instructions)
        ) {
            TracedAgentSession(wrapped: make(instructions), role: role)
        }
    }

    /// The attributes of an `agent_session.make` span: the role of the
    /// session and the length of its instructions, never their text.
    ///
    /// - Parameters:
    ///   - role: the role the traced session reports.
    ///   - instructions: the instructions of the session.
    /// - Returns: the span attributes.
    private static func makeSpanAttributes(
        role: String,
        instructions: String
    ) -> [MultitoolTelemetry.AttributeKey: (any SpanAttributeConvertible)?] {
        [.sessionRole: role, .instructionCharacters: instructions.count]
    }
}
