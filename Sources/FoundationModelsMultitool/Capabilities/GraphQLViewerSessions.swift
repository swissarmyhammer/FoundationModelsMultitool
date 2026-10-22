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
