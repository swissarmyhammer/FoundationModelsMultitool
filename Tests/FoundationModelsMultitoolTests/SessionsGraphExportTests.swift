// `SessionsGraphExportTests` — the `export` field of a session in the
// `sessions` GraphQL endpoint (D202 (g), task `^n9fhrz0`).
//
// Each case registers its sessions in its own `InMemorySessionDirectory`,
// gives the endpoint of that directory a fake exporter or no exporter, and
// reads the field with one viewer. The working folder of a session is a
// temporary folder of the case, so a case can prove that the field writes no
// file. No case reads a clock or waits.

import Foundation
import FoundationModelsExtras
import GraphQL
import Testing
import ULID

@testable import FoundationModelsMultitool

/// Behavioral tests for the `export` field of the `Session` type of
/// ``SessionsGraph``.
@Suite("SessionsGraphExportTests", .ownsTemporaryDirectories)
struct SessionsGraphExportTests {

    // MARK: - Constants

    /// The shared fixtures of the `sessions` tool tests.
    private typealias Fixtures = SessionsToolFixtures

    /// The Markdown that the fake exporter gives.
    private static let markdown = "# Fix the API tests\n\n## User\n\nRun the tests.\n"

    /// The text of the failure of the failing exporter.
    private static let failureText = "the history is gone"

    /// The `session` query of one id, with the `export` field and no
    /// argument.
    private static let exportQuery = "query($id: ID!) { session(id: $id) { export } }"

    /// The `session` query of one id, with the thoughts of the agent.
    private static let thoughtsQuery = "query($id: ID!) { session(id: $id) { export(thoughts: true) } }"

    /// The `session` query of one id, with the format named.
    private static let markdownQuery = "query($id: ID!) { session(id: $id) { export(format: MARKDOWN) } }"

    /// The `session` query of one id, with the aliases of the field and of
    /// its `thoughts` argument.
    private static let aliasQuery = "query($id: ID!) { session(id: $id) { exportSession(includeThoughts: true) } }"

    // MARK: - Helpers

    /// One session in its own directory and its own temporary working
    /// folder, and the endpoint of that directory.
    private struct Setup {
        /// The directory that holds ``session``.
        let directory = InMemorySessionDirectory()

        /// The working folder of ``session``.
        let folder = TestSupport.makeTemporaryDirectory(named: "SessionsGraphExportTests")

        /// The session.
        let session: SessionSummary

        /// The endpoint over ``directory``. The setup holds it, because the
        /// endpoint cache holds an endpoint weakly.
        let graph: SessionsGraph

        /// Registers the session, and gives `exporter` to the endpoint.
        ///
        /// - Parameter exporter: The exporter of the endpoint, or `nil` for
        ///   none.
        init(exporter: (any SessionTranscriptExporter)?) {
            session = Fixtures.summary(folder: folder)
            directory.register(session)
            graph = SessionsGraph.endpoint(of: directory, exporter: exporter)
        }

        /// The id of ``session`` as text.
        var id: String {
            session.id.ulidString
        }

        /// The names of the items in ``folder``.
        var namesInFolder: [String] {
            ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
        }
    }

    /// Runs `query` with the variable `id` on `graph`.
    ///
    /// - Parameters:
    ///   - query: The document, with the variable `$id`.
    ///   - id: The value of `$id`.
    ///   - viewer: The client of the call, or `nil` for the agent.
    ///   - graph: The endpoint.
    /// - Returns: The response.
    /// - Throws: What the endpoint throws, or an error when the response is
    ///   not a JSON object.
    private static func run(
        _ query: String, id: String, viewer: GraphQLViewer? = nil, on graph: SessionsGraph
    ) async throws -> GraphQLReply {
        try GraphQLReply(
            json: await graph.execute(
                query: query, variables: ["id": .string(id)], operationName: nil, viewer: viewer))
    }

    // MARK: - The text

    @Test("session(id:) { export } gives the text of the exporter")
    func exportGivesTheTextOfTheExporter() async throws {
        let setup = Setup(exporter: RecordingTranscriptExporter(text: Self.markdown))

        let reply = try await Self.run(Self.exportQuery, id: setup.id, on: setup.graph)

        #expect(try reply.object("session")["export"] as? String == Self.markdown, "errors: \(reply.messages)")
    }

    @Test("session(id:) { export } writes no file in the session folder")
    func exportWritesNoFile() async throws {
        let setup = Setup(exporter: RecordingTranscriptExporter(text: Self.markdown))

        _ = try await Self.run(Self.exportQuery, id: setup.id, on: setup.graph)

        #expect(setup.namesInFolder.isEmpty)
    }

    @Test("export with no argument asks the exporter for the session with no thoughts")
    func exportWithNoArgumentAsksForNoThoughts() async throws {
        let exporter = RecordingTranscriptExporter(text: Self.markdown)
        let setup = Setup(exporter: exporter)

        _ = try await Self.run(Self.exportQuery, id: setup.id, on: setup.graph)

        #expect(
            await exporter.requests == [TranscriptExportRequest(session: setup.session.id, includeThoughts: false)])
    }

    @Test("export(thoughts: true) asks the exporter for the thoughts")
    func exportWithThoughtsAsksForTheThoughts() async throws {
        let exporter = RecordingTranscriptExporter(text: Self.markdown)
        let setup = Setup(exporter: exporter)

        _ = try await Self.run(Self.thoughtsQuery, id: setup.id, on: setup.graph)

        #expect(await exporter.requests.map(\.includeThoughts) == [true])
    }

    @Test("export(format: MARKDOWN) gives the text of the exporter")
    func exportWithTheMarkdownFormatGivesTheText() async throws {
        let setup = Setup(exporter: RecordingTranscriptExporter(text: Self.markdown))

        let reply = try await Self.run(Self.markdownQuery, id: setup.id, on: setup.graph)

        #expect(try reply.object("session")["export"] as? String == Self.markdown, "errors: \(reply.messages)")
    }

    // MARK: - The refusals

    @Test("export on an endpoint with no exporter gives MISSING_EXPORTER with the corrective of the tool")
    func exportWithNoExporterGivesTheRefusal() async throws {
        let setup = Setup(exporter: nil)

        let reply = try await Self.run(Self.exportQuery, id: setup.id, on: setup.graph)

        #expect(reply.codes == ["MISSING_EXPORTER"])
        #expect(reply.messages == [SessionsToolText.noExporter])
    }

    @Test("export whose exporter fails gives EXPORT_FAILED with the corrective of the tool")
    func exportWhoseExporterFailsGivesTheRefusal() async throws {
        let failure = TranscriptExportFailure(description: Self.failureText)
        let setup = Setup(exporter: FailingTranscriptExporter(failure: failure))

        let reply = try await Self.run(Self.exportQuery, id: setup.id, on: setup.graph)

        #expect(reply.codes == ["EXPORT_FAILED"])
        #expect(reply.messages == [SessionsToolText.exportFailed(setup.session.id, error: failure)])
    }

    // MARK: - The visibility

    @Test("an external viewer cannot export a session that it cannot see")
    func anExternalViewerCannotExportAHiddenSession() async throws {
        let exporter = RecordingTranscriptExporter(text: Self.markdown)
        let setup = Setup(exporter: exporter)

        let reply = try await Self.run(
            Self.exportQuery, id: setup.id, viewer: GraphQLViewer.external(), on: setup.graph)

        #expect(reply.isNull("session"))
        #expect(await exporter.requests.isEmpty)
    }

    @Test("an external viewer exports a session that it owns")
    func anExternalViewerExportsAnOwnedSession() async throws {
        let setup = Setup(exporter: RecordingTranscriptExporter(text: Self.markdown))
        let viewer = GraphQLViewer.external(owning: [setup.id])

        let reply = try await Self.run(Self.exportQuery, id: setup.id, viewer: viewer, on: setup.graph)

        #expect(try reply.object("session")["export"] as? String == Self.markdown, "errors: \(reply.messages)")
    }

    // MARK: - The aliases

    @Test("the alias exportSession reaches export, and shows in extensions.rewrites")
    func theExportSessionAliasReachesExport() async throws {
        let setup = Setup(exporter: RecordingTranscriptExporter(text: Self.markdown))

        let reply = try await Self.run(Self.aliasQuery, id: setup.id, on: setup.graph)

        #expect(reply.rewrote("exportSession", to: "export"))
    }

    @Test("the alias includeThoughts of export asks the exporter for the thoughts")
    func theIncludeThoughtsAliasAsksForTheThoughts() async throws {
        let exporter = RecordingTranscriptExporter(text: Self.markdown)
        let setup = Setup(exporter: exporter)

        let reply = try await Self.run(Self.aliasQuery, id: setup.id, on: setup.graph)

        #expect(await exporter.requests.map(\.includeThoughts) == [true], "errors: \(reply.messages)")
        #expect(reply.rewrote("includeThoughts", to: "thoughts"))
    }
}
