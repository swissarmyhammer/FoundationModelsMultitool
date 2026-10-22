// The sessions that an external client may read through a GraphQL endpoint
// (session.md section 11.3): the `sessions` and `snapshots` endpoints share
// this one rule, so the two endpoints never disagree on a session.

import FoundationModelsExtras

extension GraphQLViewer {
    /// This viewer when its client is not a device of the user, or `nil` for
    /// a device of the user, which sees and changes each session. Only an
    /// external client has the visibility and owner rules to apply.
    var externalClient: GraphQLViewer? {
        switch trust {
        case .userDevice:
            nil
        case .external:
            self
        }
    }

    /// Tells if this client reads a session as its own: it owns the session
    /// now, or its connection started the session and may have handed it to
    /// another client since. The rule reads only the viewer. A change that
    /// needs the owner, a rollback of the `snapshots` endpoint or a tag, an
    /// untag, a rename, a send or a reply of the `sessions` endpoint, asks
    /// ``owns(_:)`` instead.
    ///
    /// - Parameter sessionId: The id of the session.
    /// - Returns: `true` when the session is in ``ownedSessions`` or in
    ///   ``startedSessions``.
    func isOwnerOrStarter(of sessionId: String) -> Bool {
        owns(sessionId) || startedSessions.contains(sessionId)
    }
}

/// A reader that one call scopes to the client of the call: the visibility of
/// the `sessions` endpoint and the context of the `snapshots` endpoint. Both
/// read the one viewer rule here, so the two endpoints never disagree on
/// which caller a rule binds.
protocol GraphQLViewerScoping {
    /// The client of the call, or `nil` for the agent.
    var viewer: GraphQLViewer? { get }
}

extension GraphQLViewerScoping {
    /// The client of the call when it is not a device of the user, or `nil`
    /// when the caller sees and changes each session: the agent or a device
    /// of the user.
    var externalViewer: GraphQLViewer? {
        viewer?.externalClient
    }

    /// Tells if the caller passes a rule that binds only an external client.
    /// The agent and a device of the user pass each such rule.
    ///
    /// - Parameter externalRule: The rule, which reads the external client.
    /// - Returns: `true` when the caller is no external client, or when the
    ///   external client passes `externalRule`.
    func admits(_ externalRule: (GraphQLViewer) -> Bool) -> Bool {
        externalViewer.map(externalRule) ?? true
    }
}
