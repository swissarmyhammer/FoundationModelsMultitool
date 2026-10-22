// `GraphQLViewerScopingTests` — the unit suite of the one viewer rule that
// the `sessions` and `snapshots` endpoints share (session.md section 11.3).

import FoundationModelsExtras
import Testing

@testable import FoundationModelsMultitool

/// Unit tests for ``GraphQLViewerScoping``: which caller is an external
/// client, and which caller a rule for an external client binds.
@Suite("GraphQLViewerScopingTests")
struct GraphQLViewerScopingTests {

    /// The session ID that the external client owns.
    private static let ownedSessionId = "session-owned"

    /// A session ID that the external client does not own.
    private static let otherSessionId = "session-other"

    /// The ID of a device of the user.
    private static let deviceClientId = "client-device"

    /// A reader that a call scopes to its viewer, as each endpoint context is.
    private struct Reader: GraphQLViewerScoping {
        /// The client of the call, or `nil` for the agent.
        let viewer: GraphQLViewer?
    }

    /// A device of the user, which sees and changes each session.
    private static let device = GraphQLViewer(clientId: deviceClientId, trust: .userDevice)

    /// A client that is not a device of the user, and that owns
    /// ``ownedSessionId``.
    private static let external = GraphQLViewer.external(owning: [ownedSessionId])

    /// The agent and a device of the user have no external viewer; an
    /// external client is its own external viewer.
    @Test("only an external client has an external viewer")
    func onlyAnExternalClientHasAnExternalViewer() {
        #expect(Reader(viewer: nil).externalViewer == nil)
        #expect(Reader(viewer: Self.device).externalViewer == nil)
        #expect(Reader(viewer: Self.external).externalViewer?.clientId == GraphQLViewer.externalClientId)
    }

    /// A rule for an external client binds only an external client: the
    /// agent and a device of the user pass a rule that the client fails.
    @Test("a rule for an external client binds only an external client")
    func aRuleBindsOnlyAnExternalClient() {
        let rule: (GraphQLViewer) -> Bool = { $0.owns(Self.otherSessionId) }

        #expect(Reader(viewer: nil).admits(rule))
        #expect(Reader(viewer: Self.device).admits(rule))
        #expect(!Reader(viewer: Self.external).admits(rule))
        #expect(Reader(viewer: Self.external).admits { $0.owns(Self.ownedSessionId) })
    }
}
