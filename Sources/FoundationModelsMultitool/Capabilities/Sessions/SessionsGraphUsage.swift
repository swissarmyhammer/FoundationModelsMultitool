// The Pinned and Recent lists of the `sessions` GraphQL endpoint (MT-10,
// D118): the `pinnedSessions` and `recentSessions` queries.
//
// The pins and the last-use times are in the usage store of this server, and
// not beside the recordings, thus the two lists are local to one Mac (D118
// (e)). The endpoint reads them only through `SessionSummary.pinnedAt`,
// `SessionSummary.lastUsedAt` and the `pinned` filter and the `order` of
// `SessionQuery`. A client that opens a session marks it as used through the
// host (ACP `session/new` and `session/load`), not through this endpoint.

import Foundation
import FoundationModelsExtras
import Graphiti
import GraphQL

// MARK: - Arguments

/// The arguments of `Query.recentSessions`.
struct SessionsGraphRecentArguments: Codable, Sendable {
    /// The most sessions to give, or `nil` for the default.
    let limit: Int?
}

// MARK: - Resolvers

extension SessionsGraphResolver {
    /// The most sessions that `Query.recentSessions` gives when the call
    /// names no limit.
    static let defaultRecentLimit = 20

    /// Resolves `Query.pinnedSessions`: each pinned session that the viewer
    /// can see, in pin order, the first pin first.
    ///
    /// - Parameters:
    ///   - context: The context of the call, which gives the visibility.
    ///   - arguments: No argument.
    /// - Returns: The sessions.
    /// - Throws: An error of the directory.
    func pinnedSessions(
        context: SessionsGraphContext, arguments _: NoArguments
    ) async throws -> [SessionsGraphSession] {
        let query = SessionQuery(
            pinned: true, includesRecorded: true, order: .pinOrder, limit: SessionsVisibility.unboundedLimit)
        return try await context.sessions.sessions(matching: query).map(SessionsGraphSession.init)
    }

    /// Resolves `Query.unreadableFolders`: the path of each recording root
    /// that the directory cannot list, for example a folder of another app
    /// that the sandbox does not permit (Testudo ^zzfv6c6). Each list passes
    /// over such a root and gives the sessions of the other roots, so a host
    /// can tell the user which folder it cannot read. Only the host (a call
    /// with no viewer) gets the paths: a session viewer gets none, because a
    /// folder of another session is not its fact.
    ///
    /// - Parameters:
    ///   - context: The context of the call, which gives the directory.
    ///   - arguments: No argument.
    /// - Returns: The paths, in the order of the roots.
    func unreadableFolders(
        context: SessionsGraphContext, arguments _: NoArguments
    ) async -> [String] {
        guard context.sessions.viewer == nil else { return [] }
        return await context.sessions.directory.unreadableRecordingRoots().map(\.path)
    }

    /// Resolves `Query.recentSessions`: the sessions that a client opened on
    /// this server, the last one first, with no pinned session.
    ///
    /// The directory puts the sessions with no last-use time after the
    /// others, thus the resolver removes them from the end, and a used
    /// session is never lost behind them.
    ///
    /// - Parameters:
    ///   - context: The context of the call, which gives the visibility.
    ///   - arguments: The limit.
    /// - Returns: The sessions, at most the limit of them.
    /// - Throws: An error of the directory.
    func recentSessions(
        context: SessionsGraphContext, arguments: SessionsGraphRecentArguments
    ) async throws -> [SessionsGraphSession] {
        let limit = SessionsToolInput.listLimit(arguments.limit, defaultingTo: Self.defaultRecentLimit)
        let query = SessionQuery(pinned: false, includesRecorded: true, order: .lastUsedFirst, limit: limit)
        return try await context.sessions.sessions(matching: query)
            .filter { $0.lastUsedAt != nil }
            .map(SessionsGraphSession.init)
    }
}

// MARK: - Schema

extension SessionsGraphAPI {
    /// The `Query.pinnedSessions` field.
    ///
    /// - Returns: The field.
    static func pinnedSessionsField() -> SchemaField {
        Field("pinnedSessions", at: SessionsGraphResolver.pinnedSessions)
            .description(
                "The Pinned list of this server: each pinned session that you can see, the first pin first. "
                    + "pinSession and unpinSession change it.")
    }

    /// The `Query.unreadableFolders` field.
    ///
    /// - Returns: The field.
    static func unreadableFoldersField() -> SchemaField {
        Field("unreadableFolders", at: SessionsGraphResolver.unreadableFolders)
            .description(
                "The path of each session folder of this server that it cannot read, for example a folder "
                    + "of another app that the sandbox does not permit. Each list leaves out its sessions "
                    + "and gives the sessions of the other folders.")
    }

    /// The `Query.recentSessions` field.
    ///
    /// - Returns: The field.
    static func recentSessionsField() -> SchemaField {
        Field("recentSessions", at: SessionsGraphResolver.recentSessions) {
            Argument("limit", at: \.limit)
                .defaultValue(SessionsGraphResolver.defaultRecentLimit)
                .description("The most sessions to give: 1 to \(SessionsToolInput.maximumListLimit).")
        }
        .description(
            "The Recent list of this server: the sessions that a client opened, the last one first. "
                + "A pinned session is not in it.")
    }
}
