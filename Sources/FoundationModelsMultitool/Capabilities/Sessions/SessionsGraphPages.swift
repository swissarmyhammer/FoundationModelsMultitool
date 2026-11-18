// The page reads of the `sessions` GraphQL endpoint (D199): the `sessionPage`
// query, which gives each session that matches a filter in pages, in the
// order of the session ids.
//
// The id order is stable: a session that starts during a read has a newer id
// than each session before it, thus it comes on a later page, and no session
// moves from one page to another. The `sessions` query keeps its order, the
// newest first, and its limit.

import Foundation
import FoundationModelsExtras
import GraphQL
import Graphiti
import ULID

// MARK: - Arguments and the page

/// The arguments of `Query.sessionPage`.
struct SessionsGraphPageArguments: Codable, Sendable {
    /// The filter, or `nil` for each live session.
    let filter: SessionsGraphFilter?

    /// The cursor of the page before: its `nextCursor`, or `nil` for the
    /// first page.
    let after: String?
}

/// The `SessionPage` type: one page of sessions, and the cursor of the next
/// page.
struct SessionsGraphPage: Sendable {
    /// The sessions of the page, in the order of their ids.
    let sessions: [SessionsGraphSession]

    /// The cursor of the next page, or `nil` when this page is the last.
    let nextCursor: String?
}

// MARK: - Resolver

extension SessionsGraphResolver {
    /// Resolves `Query.sessionPage`: one page of the sessions that match the
    /// filter and that the viewer can see, in the order of their ids.
    ///
    /// A page has no archived session unless the filter asks for the state
    /// `ARCHIVED`. Thus a filter with `includeRecorded` gives each session
    /// that is not archived. The limit of the filter is the page size.
    ///
    /// - Parameters:
    ///   - context: The context of the call, which gives the visibility.
    ///   - arguments: The filter and the cursor.
    /// - Returns: The page.
    /// - Throws: A ``SessionsRefusal`` for a filter or a cursor that the
    ///   endpoint cannot read, or an error of the directory.
    func sessionPage(
        context: SessionsGraphContext, arguments: SessionsGraphPageArguments
    ) async throws -> SessionsGraphPage {
        var query = try (arguments.filter ?? SessionsGraphFilter()).query()
        let cursor = try SessionsGraphInput.cursor(arguments.after)
        let pageSize = query.limit
        // One session more than the page tells if a next page exists.
        query.limit = pageSize + 1
        let includesArchived = query.state == .archived
        let found = try await context.sessions.sessionsInIDOrder(matching: query, after: cursor) { summary in
            includesArchived || summary.state != .archived
        }
        let page = found.prefix(pageSize)
        return SessionsGraphPage(
            sessions: page.map(SessionsGraphSession.init),
            nextCursor: found.count > pageSize ? page.last?.id.ulidString : nil)
    }
}

// MARK: - The cursor

extension SessionsGraphInput {
    /// The session id of a page cursor, in any letter case.
    ///
    /// - Parameter text: The cursor, or `nil` for the first page.
    /// - Returns: The id of the last session of the page before, or `nil`
    ///   for no cursor.
    /// - Throws: ``SessionsRefusal`` with the code `INVALID_CURSOR` when the
    ///   cursor is not a cursor that the endpoint gave.
    static func cursor(_ text: String?) throws(SessionsRefusal) -> ULID? {
        guard let text else {
            return nil
        }
        return try SessionsToolInput.requiredULID(text, kind: .invalidCursor, corrective: SessionsGraphText.notACursor)
    }
}

extension SessionsGraphText {
    /// The corrective of a page cursor that the endpoint did not give.
    ///
    /// - Parameter text: The cursor.
    /// - Returns: The corrective.
    static func notACursor(_ text: String) -> String {
        """
        "\(text)" is not a cursor of sessionPage. Give the nextCursor of the page before, \
        or no cursor for the first page.
        """
    }
}

// MARK: - Schema

extension SessionsGraphAPI {
    /// The `Query.sessionPage` field.
    ///
    /// - Returns: The field.
    static func sessionPageField() -> SchemaField {
        Field("sessionPage", at: SessionsGraphResolver.sessionPage) {
            Argument("filter", at: \.filter)
                .description(
                    "The filter. Its limit is the page size. Set includeRecorded to get each session that is not "
                        + "archived.")
            Argument("after", at: \.after)
                .description("The nextCursor of the page before, or no cursor for the first page.")
        }
        .description(
            "One page of the sessions on this server that match the filter, in the order of their ids. A session "
                + "that starts during the read comes on a later page, thus each session shows one time. A page has "
                + "no archived session unless the filter has the state ARCHIVED. An external client sees only the "
                + "sessions that it can see, as in sessions.")
    }

    /// The `SessionPage` type.
    ///
    /// - Returns: The type.
    static func sessionPageType() -> SchemaType {
        Type(SessionsGraphPage.self, as: "SessionPage") {
            Field("sessions", at: \.sessions).description("The sessions of the page, in the order of their ids.")
            Field("nextCursor", at: \.nextCursor)
                .description("The cursor of the next page, or null when this page is the last.")
        }
        .description("One page of sessions, and the cursor of the next page.")
    }
}
