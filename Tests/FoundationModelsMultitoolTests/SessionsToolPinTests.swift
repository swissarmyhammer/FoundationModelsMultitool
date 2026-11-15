// `SessionsToolPinTests` — the behavioral suite of the `pin session` and
// `unpin session` operations of the `sessions` tool (MT-2, D118, D100 (a)).
//
// Each case uses its own `InMemorySessionDirectory` with a fixed clock, and
// reads the pin through the directory and through the `pinnedSessions` query
// of the endpoint of the same tool. No case waits.

import Foundation
import FoundationModelsExtras
import GraphQL
import Testing
import ULID

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Behavioral tests for the `pin session` and `unpin session` operations of
/// the `sessions` tool.
@Suite("SessionsToolPinTests", .ownsTemporaryDirectories)
struct SessionsToolPinTests {

    // MARK: - Constants

    /// The shared fixtures of the sessions tests.
    private typealias Fixtures = SessionsToolFixtures

    /// The words of the answer of a pin.
    private static let pinnedWords = "is pinned"

    /// The words of the answer of an unpin.
    private static let unpinnedWords = "is not pinned"

    /// The code-mode verb name that the unknown-session corrective names.
    private static let listSessionsVerb = "listSessions"

    /// The `pinnedSessions` query of the endpoint.
    private static let pinnedQuery = "{ pinnedSessions { id } }"

    /// A session id that no session has.
    private static let absentID = ULID()

    // MARK: - Helpers

    /// The summary of the session `id`.
    ///
    /// - Parameters:
    ///   - id: The session id.
    ///   - directory: The directory.
    /// - Returns: The summary.
    /// - Throws: An error when the directory does not hold the session.
    private static func summary(of id: ULID, in directory: InMemorySessionDirectory) async throws -> SessionSummary {
        try #require(try await directory.summary(of: id))
    }

    /// The ids of the Pinned list of the endpoint of `tool`.
    ///
    /// - Parameter tool: The tool.
    /// - Returns: The ids, in pin order.
    /// - Throws: What the endpoint throws.
    private static func pinnedIDs(of tool: SessionsTool) async throws -> [String] {
        let endpoint = try #require(tool.graphQLEndpoints.first as? SessionsGraph)
        let json = try await endpoint.execute(query: pinnedQuery, variables: [:], operationName: nil, viewer: nil)
        return try GraphQLReply(json: json).list("pinnedSessions").compactMap { $0["id"] as? String }
    }

    // MARK: - pin session

    @Test("pin session pins the session and the endpoint shows it in the Pinned list")
    func pinSessionPinsTheSession() async throws {
        let directory = Fixtures.directoryWithLauncher()
        let other = Fixtures.summary()
        directory.register(other)
        let tool = try SessionsTool(directory: directory)

        let output = try await Fixtures.asCaller(in: directory) { _ in
            try await tool.call(arguments: Fixtures.payload("pin session", [("id", other.id.ulidString)]))
        }

        #expect(output.contains(Self.pinnedWords), "output was: \(output)")
        #expect(try await Self.summary(of: other.id, in: directory).isPinned)
        #expect(try await Self.pinnedIDs(of: tool) == [other.id.ulidString])
    }

    @Test("pin session with no id pins the caller session")
    func pinSessionWithNoIDPinsTheCaller() async throws {
        let directory = Fixtures.directoryWithLauncher()
        let tool = try SessionsTool(directory: directory)

        let callerID = try await Fixtures.asCaller(in: directory) { callerID in
            _ = try await tool.call(arguments: Fixtures.payload("pin session"))
            return callerID
        }

        #expect(try await Self.summary(of: callerID, in: directory).isPinned)
    }

    @Test("pin session of an unknown id gives a corrective with the id and listSessions")
    func pinSessionOfAnUnknownIDIsACorrective() async throws {
        let directory = Fixtures.directoryWithLauncher()
        let tool = try SessionsTool(directory: directory)

        let output = try await Fixtures.asCaller(in: directory) { _ in
            try await tool.call(arguments: Fixtures.payload("pin session", [("id", Self.absentID.ulidString)]))
        }

        #expect(output.contains(Self.absentID.ulidString), "output was: \(output)")
        #expect(output.contains(Self.listSessionsVerb), "output was: \(output)")
    }

    @Test("pin session with no ToolContext gives a corrective and pins nothing")
    func pinSessionWithNoCallerIsACorrective() async throws {
        let directory = Fixtures.directoryWithLauncher()
        let other = Fixtures.summary()
        directory.register(other)
        let tool = try SessionsTool(directory: directory)

        let output = try await tool.call(arguments: Fixtures.payload("pin session", [("id", other.id.ulidString)]))

        #expect(output.contains("session"), "output was: \(output)")
        #expect(try await Self.summary(of: other.id, in: directory).isPinned == false)
    }

    // MARK: - unpin session

    @Test("unpin session unpins the session and the endpoint removes it from the Pinned list")
    func unpinSessionUnpinsTheSession() async throws {
        let directory = Fixtures.directoryWithLauncher()
        let other = Fixtures.summary(pinnedAt: Fixtures.fixedDate)
        directory.register(other)
        let tool = try SessionsTool(directory: directory)

        let output = try await Fixtures.asCaller(in: directory) { _ in
            try await tool.call(arguments: Fixtures.payload("unpin session", [("id", other.id.ulidString)]))
        }

        #expect(output.contains(Self.unpinnedWords), "output was: \(output)")
        #expect(try await Self.summary(of: other.id, in: directory).isPinned == false)
        #expect(try await Self.pinnedIDs(of: tool).isEmpty)
    }

    // MARK: - list sessions

    @Test("list sessions shows a pinned session as pinned")
    func listSessionsShowsThePin() async throws {
        let directory = Fixtures.directoryWithLauncher()
        let pinned = Fixtures.summary(title: "Pinned one", pinnedAt: Fixtures.fixedDate)
        directory.register(pinned)
        let tool = try SessionsTool(directory: directory)

        let output = try await Fixtures.asCaller(in: directory) { _ in
            try await tool.call(arguments: Fixtures.payload("list sessions"))
        }

        let line = output.split(separator: "\n").first { $0.contains(pinned.id.ulidString) }
        #expect(line?.contains("pinned") == true, "output was: \(output)")
    }
}
