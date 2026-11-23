// `SessionsGraphProvenanceTests` — the `importedFrom` field of a session of
// the `sessions` GraphQL endpoint, and its type `SessionImportProvenance`
// (D209, D212).
//
// Each case uses its own `InMemorySessionDirectory`. A case makes an imported
// session with `importSession(_:transcript:)` of the directory, as the copy
// of `continueExternalSession` in the host does, and reads it with the
// `sessions` query. No case waits for a time.

import Foundation
import FoundationModels
import FoundationModelsExtras
import GraphQL
import Testing
import ULID

@testable import FoundationModelsMultitool

/// Behavioral tests for the provenance of an imported session in the
/// `sessions` endpoint: each field, the `null` values, the aliases, and the
/// types of the SDL.
@Suite("SessionsGraphProvenanceTests", .ownsTemporaryDirectories)
struct SessionsGraphProvenanceTests {

    // MARK: - Constants

    /// The shared fixtures of the `sessions` tool tests.
    private typealias Fixtures = SessionsToolFixtures

    /// A device of the user, which owns no session.
    private static let deviceViewer = SessionsGraphChangesTests.deviceViewer

    /// The number of records that each import of a case does not read.
    private static let skippedRecordCount = 3

    /// The fixed time of each import of a case.
    private static let importedAt = Date(timeIntervalSince1970: Fixtures.fixedSecondsSince1970)

    /// The provenance of a source session of Claude Code, with a title.
    private static let titledProvenance = SessionImportProvenance(
        agent: "claude-code", sourceID: "a1b2c3", sourcePath: "/sources/claude-code/a1b2c3.jsonl",
        sourceTitle: "Fix the parser", sourceLastDate: Fixtures.fixedDate, importedAt: importedAt,
        skippedRecordCount: skippedRecordCount)

    /// The provenance of a source session of Codex, with no title.
    private static let untitledProvenance = SessionImportProvenance(
        agent: "codex", sourceID: "rollout-42", sourcePath: "/sources/codex/rollout-42.jsonl", sourceTitle: nil,
        sourceLastDate: Fixtures.fixedDate, importedAt: importedAt, skippedRecordCount: skippedRecordCount)

    /// The fields of the `importedFrom` of a session, each field of
    /// `SessionImportProvenance` but `sourceTitle`.
    private static let provenanceSelection = """
        importedFrom { agent sourceId sourcePath sourceLastDate importedAt skippedRecordCount }
        """

    /// The `sessions` query of each session, live or not, with the id and
    /// the `importedFrom` of each session.
    private static let sessionsWithProvenanceQuery = """
        { sessions(filter: {includeRecorded: true}) { id \(provenanceSelection) } }
        """

    /// The `sessions` query of each session, live or not, with the id and
    /// the `sourceTitle` of the `importedFrom` of each session.
    private static let sessionsWithSourceTitleQuery = """
        { sessions(filter: {includeRecorded: true}) { id importedFrom { sourceTitle } } }
        """

    /// ``sessionsWithSourceTitleQuery`` with the alias `source_title` for
    /// `sourceTitle`.
    private static let sessionsWithSourceTitleAliasQuery = """
        { sessions(filter: {includeRecorded: true}) { id importedFrom { source_title } } }
        """

    /// Each field of ``titledProvenance``, in the order of
    /// ``provenanceSelection``, as text.
    private static let titledProvenanceTexts = [
        titledProvenance.agent, titledProvenance.sourceID, titledProvenance.sourcePath,
        DateTime(Fixtures.fixedDate).rfc3339, DateTime(importedAt).rfc3339, String(skippedRecordCount),
    ]

    // MARK: - Helpers

    /// One directory and its endpoint.
    private struct Setup {
        /// The directory that gets the imported sessions.
        let directory = Fixtures.directoryWithLauncher()

        /// The endpoint over ``directory``. The setup holds it, because the
        /// endpoint cache holds an endpoint weakly.
        let graph: SessionsGraph

        /// Makes the endpoint of the directory.
        init() {
            graph = SessionsGraph.endpoint(of: directory)
        }

        /// Runs one document on ``graph`` as a device of the user.
        ///
        /// - Parameter document: The document.
        /// - Returns: The response.
        /// - Throws: What the endpoint throws.
        func run(_ document: String) async throws -> GraphQLReply {
            try await GraphQLReply.run(document, viewer: deviceViewer, on: graph)
        }

        /// Imports one session with a provenance into ``directory``.
        ///
        /// - Parameter provenance: The provenance of the new session.
        /// - Returns: The id of the new session.
        /// - Throws: What the directory throws.
        func importSession(with provenance: SessionImportProvenance) async throws -> ULID {
            let request = SessionImportRequest(
                workingDirectory: Fixtures.workingFolder,
                title: provenance.sourceTitle ?? "\(provenance.agent)-import", provenance: provenance)
            return try await directory.importSession(request, transcript: Transcript()).id
        }
    }

    /// Each field of an `importedFrom` object, in the order of
    /// ``provenanceSelection``, as text.
    ///
    /// - Parameter session: A `Session` object of a response.
    /// - Returns: The text of each field.
    /// - Throws: An error when the session has no `importedFrom` object.
    private static func provenanceTexts(of session: [String: Any]) throws -> [String] {
        let provenance = try #require(session["importedFrom"] as? [String: Any])
        return ["agent", "sourceId", "sourcePath", "sourceLastDate", "importedAt", "skippedRecordCount"]
            .map { "\(provenance[$0] ?? "nil")" }
    }

    /// The `sourceTitle` of the `importedFrom` of the session `id` in a
    /// `sessions` response.
    ///
    /// - Parameters:
    ///   - id: The session id.
    ///   - reply: The response.
    /// - Returns: The value of `sourceTitle`: a string, or `NSNull` for
    ///   `null`, or `nil` when the object has no `sourceTitle`.
    /// - Throws: An error when the response has no session with that id or
    ///   the session has no `importedFrom` object.
    private static func sourceTitle(of id: ULID, in reply: GraphQLReply) throws -> Any? {
        let provenance = try #require(try session(id, in: reply)["importedFrom"] as? [String: Any])
        return provenance["sourceTitle"]
    }

    /// The `Session` object of the session `id` in a `sessions` response.
    ///
    /// - Parameters:
    ///   - id: The session id.
    ///   - reply: The response.
    /// - Returns: The session.
    /// - Throws: An error when the response has no session with that id.
    private static func session(_ id: ULID, in reply: GraphQLReply) throws -> [String: Any] {
        try #require(try reply.list("sessions").first { $0["id"] as? String == id.ulidString })
    }

    // MARK: - importedFrom

    /// `sessions` gives each field of the `importedFrom` of an imported
    /// session.
    @Test("sessions gives each field of the importedFrom of an imported session")
    func sessionsGivesTheImportedFrom() async throws {
        let setup = Setup()
        let copy = try await setup.importSession(with: Self.titledProvenance)

        let reply = try await setup.run(Self.sessionsWithProvenanceQuery)

        #expect(reply.codes.isEmpty, "errors: \(reply.messages)")
        #expect(try Self.provenanceTexts(of: try Self.session(copy, in: reply)) == Self.titledProvenanceTexts)
    }

    /// A session that was not imported gives `null` as its `importedFrom`.
    @Test("sessions gives null as the importedFrom of a session that was not imported")
    func sessionsGivesNullForASessionThatWasNotImported() async throws {
        let setup = Setup()
        let session = Fixtures.summary()
        setup.directory.register(session)

        let reply = try await setup.run(Self.sessionsWithProvenanceQuery)

        #expect(try Self.session(session.id, in: reply)["importedFrom"] is NSNull)
    }

    /// `sessions` takes the snake-case aliases of `importedFrom` and of the
    /// fields of `SessionImportProvenance`, gives each value at the name of
    /// the call, and reports the rewrite.
    @Test("sessions takes imported_from and the snake-case names of the fields of the provenance")
    func sessionsTakesTheProvenanceAliases() async throws {
        let setup = Setup()
        let copy = try await setup.importSession(with: Self.titledProvenance)

        let reply = try await setup.run(
            "{ sessions(filter: {includeRecorded: true}) { id imported_from { source_id source_path } } }")
        let provenance = try #require(try Self.session(copy, in: reply)["imported_from"] as? [String: Any])

        #expect(reply.codes.isEmpty, "errors: \(reply.messages)")
        #expect(reply.rewrote("imported_from", to: "importedFrom"))
        #expect(
            [provenance["source_id"], provenance["source_path"]].map { $0 as? String } == [
                Self.titledProvenance.sourceID, Self.titledProvenance.sourcePath,
            ])
    }

    /// `sessions` gives the title of the source session as the
    /// `sourceTitle` of the `importedFrom` of an imported session.
    @Test("sessions gives the sourceTitle of the importedFrom of an imported session with a source title")
    func sessionsGivesTheSourceTitle() async throws {
        let setup = Setup()
        let copy = try await setup.importSession(with: Self.titledProvenance)

        let reply = try await setup.run(Self.sessionsWithSourceTitleQuery)

        #expect(try Self.sourceTitle(of: copy, in: reply) as? String == Self.titledProvenance.sourceTitle)
    }

    /// A provenance with no source title gives `null` as its
    /// `sourceTitle`.
    @Test("sessions gives null as the sourceTitle of a provenance with no source title")
    func sessionsGivesNullForNoSourceTitle() async throws {
        let setup = Setup()
        let copy = try await setup.importSession(with: Self.untitledProvenance)

        let reply = try await setup.run(Self.sessionsWithSourceTitleQuery)

        #expect(try Self.sourceTitle(of: copy, in: reply) is NSNull)
    }

    /// `sessions` takes `source_title` for the `sourceTitle` of the
    /// provenance, and gives the value at the name of the call.
    @Test("sessions takes source_title and gives the sourceTitle at the name of the call")
    func sessionsTakesTheSourceTitleAlias() async throws {
        let setup = Setup()
        let copy = try await setup.importSession(with: Self.titledProvenance)

        let reply = try await setup.run(Self.sessionsWithSourceTitleAliasQuery)
        let provenance = try #require(try Self.session(copy, in: reply)["importedFrom"] as? [String: Any])

        #expect(provenance["source_title"] as? String == Self.titledProvenance.sourceTitle)
    }

    /// `sessions` reports the rewrite of `source_title` to `sourceTitle`.
    @Test("sessions reports the rewrite of source_title to sourceTitle")
    func sessionsReportsTheSourceTitleRewrite() async throws {
        let setup = Setup()
        _ = try await setup.importSession(with: Self.titledProvenance)

        let reply = try await setup.run(Self.sessionsWithSourceTitleAliasQuery)

        #expect(reply.rewrote("source_title", to: "sourceTitle"))
    }

    // MARK: - The SDL

    /// The SDL of the endpoint has the nullable field `importedFrom` of a
    /// session, of the type `SessionImportProvenance`. A non-null type is a
    /// `GraphQLNonNull` wrapper, not an object type.
    @Test("the SDL has the nullable field importedFrom of a Session")
    func theSchemaHasTheImportedFromField() throws {
        let graph = SessionsGraph.endpoint(of: InMemorySessionDirectory())

        let schema = try buildSchema(source: graph.schema)
        let session = try #require(schema.getType(name: "Session") as? GraphQLObjectType)
        let field = try #require(try session.fields()["importedFrom"])

        #expect((field.type as? GraphQLObjectType)?.name == "SessionImportProvenance")
    }

    /// The SDL of the endpoint has the nullable field `sourceTitle` of a
    /// `SessionImportProvenance`, of the type `String`. A non-null type is a
    /// `GraphQLNonNull` wrapper, not a scalar type.
    @Test("the SDL has the nullable field sourceTitle of a SessionImportProvenance")
    func theSchemaHasTheSourceTitleField() throws {
        let graph = SessionsGraph.endpoint(of: InMemorySessionDirectory())

        let schema = try buildSchema(source: graph.schema)
        let provenance = try #require(schema.getType(name: "SessionImportProvenance") as? GraphQLObjectType)
        let field = try #require(try provenance.fields()["sourceTitle"])

        #expect((field.type as? GraphQLScalarType)?.name == "String")
    }
}
