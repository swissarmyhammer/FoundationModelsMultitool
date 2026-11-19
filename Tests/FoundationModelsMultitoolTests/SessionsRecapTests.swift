// `SessionsRecapTests` — the behavioral suite of the recap of a session
// (D206 (g) and (h), task `^vtmgqyk`): the `recap` and `recapAt` fields of
// the `Session` type of the `sessions` endpoint, the "Recap:" line of
// `check session`, the `recap` fact of the line of `list sessions`, and the
// same texts in code mode.
//
// Each case registers its sessions in its own `InMemorySessionDirectory`, and
// sets a recap with the test hook `setRecap(of:_:at:)` at a fixed time. No
// case reads a clock or waits.

import Foundation
import FoundationModels
import FoundationModelsExtras
import GraphQL
import Testing
import ULID

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Behavioral tests for the recap of a session in the `sessions` endpoint and
/// in the `sessions` tool.
@Suite("SessionsRecapTests")
struct SessionsRecapTests {

    // MARK: - Constants

    /// The shared fixtures of the sessions tests.
    private typealias Fixtures = SessionsToolFixtures

    /// The recap of the session of a case.
    private static let recap = "Fixed the two failing API tests; the CI run is green."

    /// The time of ``recap``: one minute after the fixed time of the fixtures.
    private static let recapDate = Fixtures.fixedDate.addingTimeInterval(60)

    /// The `session` query of the recap facts of one session.
    private static let recapQuery = "query($id: ID!) { session(id: $id) { recap recapAt } }"

    /// The `session` query of the recap facts of one session, with the
    /// aliases of the two fields.
    private static let recapAliasQuery = "query($id: ID!) { session(id: $id) { sessionRecap recapTime } }"

    /// The "Recap:" line of `check session` for a session with no recap,
    /// then the start of the next line.
    private static let noRecapLines = "Recap: none\nLast summary:"

    /// The `recap` fact of the line of `list sessions`, as each line writes
    /// it.
    private static let listedRecapPrefix = "recap \""

    // MARK: - Helpers

    /// A directory with one registered session, and the `sessions` tool and
    /// endpoint over that directory.
    private struct Setup {
        /// The directory.
        let directory = InMemorySessionDirectory()

        /// The session of the case.
        let session = Fixtures.summary(title: "Review the parser")

        /// The endpoint over ``directory``.
        let graph: SessionsGraph

        /// The `sessions` tool over ``directory``.
        let tool: SessionsTool

        /// Registers ``session`` and makes the tool and the endpoint.
        ///
        /// - Parameter recap: The recap of ``session`` at
        ///   ``SessionsRecapTests/recapDate``, or `nil` for a session with no
        ///   recap.
        /// - Throws: What the directory or the tool throws.
        init(recap: String?) throws {
            directory.register(session)
            if let recap {
                try directory.setRecap(of: session.id, recap, at: SessionsRecapTests.recapDate)
            }
            graph = SessionsGraph.endpoint(of: directory)
            tool = try SessionsTool(directory: directory)
        }

        /// The variables of a query of ``session``.
        var variables: [String: Map] {
            ["id": .string(session.id.ulidString)]
        }

        /// The text of `check session` of ``session``.
        ///
        /// - Returns: The text.
        /// - Throws: What the tool throws.
        func checkSession() async throws -> String {
            try await tool.call(arguments: Fixtures.payload("check session", [("id", session.id.ulidString)]))
        }

        /// The line of ``session`` in the text of `list sessions`.
        ///
        /// - Returns: The line.
        /// - Throws: An error when the text has no line of ``session``.
        func listedLine() async throws -> String {
            let listing = try await tool.call(arguments: Fixtures.payload("list sessions"))
            let line = listing.split(separator: "\n").first { $0.contains(session.id.ulidString) }
            return String(try #require(line, "listing was: \(listing)"))
        }
    }

    // MARK: - The Session type

    /// `recap` and `recapAt` give the recap of the summary and its time.
    @Test("session(id:) gives the recap and recapAt of the summary")
    func theQueryGivesTheRecap() async throws {
        let setup = try Setup(recap: Self.recap)

        let session = try await GraphQLReply.run(Self.recapQuery, variables: setup.variables, on: setup.graph)
            .object("session")

        #expect(session["recap"] as? String == Self.recap)
        #expect(session["recapAt"] as? String == DateTime(Self.recapDate).rfc3339)
    }

    /// A session with no recap gives `recap: null` and `recapAt: null`.
    @Test("session(id:) of a session with no recap gives recap and recapAt null")
    func theQueryGivesNullWithNoRecap() async throws {
        let setup = try Setup(recap: nil)

        let session = try await GraphQLReply.run(Self.recapQuery, variables: setup.variables, on: setup.graph)
            .object("session")

        #expect(session["recap"] is NSNull)
        #expect(session["recapAt"] is NSNull)
    }

    /// The aliases `sessionRecap` and `recapTime` (D86) reach `recap` and
    /// `recapAt`, and the response names each rewrite.
    @Test("the aliases sessionRecap and recapTime reach recap and recapAt")
    func theAliasesReachTheRecapFields() async throws {
        let setup = try Setup(recap: Self.recap)

        let reply = try await GraphQLReply.run(Self.recapAliasQuery, variables: setup.variables, on: setup.graph)

        #expect(reply.rewrote("sessionRecap", to: "recap"), "errors: \(reply.messages)")
        #expect(reply.rewrote("recapTime", to: "recapAt"), "errors: \(reply.messages)")
    }

    // MARK: - check session

    /// `check session` gives the line "Recap: <recap>" before the line
    /// "Last summary:".
    @Test("check session gives the recap line before the last summary line")
    func checkSessionGivesTheRecap() async throws {
        let setup = try Setup(recap: Self.recap)

        let output = try await setup.checkSession()

        #expect(output.contains("Recap: \(Self.recap)\nLast summary:"), "output was: \(output)")
    }

    /// `check session` of a session with no recap gives "Recap: none" before
    /// the line "Last summary:".
    @Test("check session of a session with no recap gives Recap: none")
    func checkSessionGivesNoneWithNoRecap() async throws {
        let setup = try Setup(recap: nil)

        let output = try await setup.checkSession()

        #expect(output.contains(Self.noRecapLines), "output was: \(output)")
    }

    // MARK: - list sessions

    /// The line of a session with a recap ends with `recap "<recap>"`.
    @Test("the list sessions line of a session with a recap ends with the recap")
    func listSessionsGivesTheRecap() async throws {
        let setup = try Setup(recap: Self.recap)

        let line = try await setup.listedLine()

        #expect(line.hasSuffix(", \(Self.listedRecapPrefix)\(Self.recap)\""), "line was: \(line)")
    }

    /// The line of a session with no recap has no `recap` fact.
    @Test("the list sessions line of a session with no recap has no recap fact")
    func listSessionsGivesNothingWithNoRecap() async throws {
        let setup = try Setup(recap: nil)

        let line = try await setup.listedLine()

        #expect(!line.contains(Self.listedRecapPrefix), "line was: \(line)")
    }

    // MARK: - Code mode

    /// What the snippet reports about `listSessions` and `checkSession`.
    private struct SnippetReport: Decodable {
        /// What `listSessions` gave.
        let listed: String

        /// What `checkSession` gave.
        let checked: String
    }

    /// In code mode, `tools.sessions.listSessions` and
    /// `tools.sessions.checkSession` give the recap, as the tool does.
    @Test("tools.sessions.listSessions and checkSession give the recap in a runCode snippet")
    func theVerbsGiveTheRecapInASnippet() async throws {
        let setup = try Setup(recap: Self.recap)
        let multiTool = MultiTool(
            registry: try MultiTool.Builder(mode: .open).withSessions(setup.tool).buildRegistry())

        let output = try await multiTool.call(
            arguments: RunCodeArguments(
                code: """
                    const listed = await tools.sessions.listSessions({});
                    const checked = await tools.sessions.checkSession({ id: "\(setup.session.id.ulidString)" });
                    return { listed, checked };
                    """))

        let report = try RunOutput.decoded(SnippetReport.self, from: output)
        #expect(report.listed.contains("\(Self.listedRecapPrefix)\(Self.recap)\""), "listed was: \(report.listed)")
        #expect(report.checked.contains("Recap: \(Self.recap)"), "checked was: \(report.checked)")
    }
}
