import FoundationModelsExtras

/// The external viewer that the GraphQL endpoint tests read with: one client
/// that is not a device of the user, so the owner and visibility rules of
/// session.md section 11.3 scope each of its calls.
extension GraphQLViewer {

    /// The ID of the client of ``external(owning:started:clientOwned:)``.
    static let externalClientId = "client-external"

    /// An external client that owns the sessions `owned` and whose connection
    /// started the sessions `started`.
    ///
    /// - Parameters:
    ///   - owned: The session IDs that the client owns.
    ///   - started: The session IDs that the connection of the client started.
    ///   - clientOwned: The session IDs that any client owns. The viewer adds
    ///     each ID of `owned` to this set.
    /// - Returns: The viewer.
    static func external(
        owning owned: Set<String> = [], started: Set<String> = [], clientOwned: Set<String> = []
    ) -> GraphQLViewer {
        GraphQLViewer(
            clientId: externalClientId, trust: .external, ownedSessions: owned, clientOwnedSessions: clientOwned,
            startedSessions: started)
    }
}
