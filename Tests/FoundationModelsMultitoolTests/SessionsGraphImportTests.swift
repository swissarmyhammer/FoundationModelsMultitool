// `SessionsGraphImportTests` — the `importableSessions` query and the
// `importSession` mutation of the `sessions` GraphQL endpoint (D209 (l),
// task `^fr3tyrn`).
//
// Each case uses its own `InMemorySessionDirectory` and its own fake importer
// from the fixtures. The fake makes a real session in the directory, so each
// case reads the new session from the directory. A case that compares a
// refusal with the tool calls the `sessions` tool and the endpoint over the
// same directory, and compares the corrective of the tool with the message
// of the coded error. No case waits for a time.

import Foundation
import FoundationModels
import FoundationModelsExtras
import GraphQL
import Testing
import ULID

@testable import FoundationModelsMultitool

/// Behavioral tests for the import fields of the `sessions` endpoint: the
/// page of `importableSessions`, the new session of `importSession`, the
/// refusals that the endpoint shares with the tool, the rules of the viewer,
/// the aliases, and the types of the SDL.
@Suite("SessionsGraphImportTests", .ownsTemporaryDirectories, .timeLimit(.minutes(1)))
struct SessionsGraphImportTests {

    // MARK: - Constants

    /// The shared fixtures of the `sessions` tool tests.
    private typealias Fixtures = SessionsToolFixtures

    /// A device of the user, which owns no session.
    private static let deviceViewer = SessionsGraphChangesTests.deviceViewer

    /// The source agent of ``titledSource``.
    private static let claudeCode = "claude-code"

    /// The source agent of ``untitledSource``.
    private static let codex = "codex"

    /// The folder of ``untitledSource``: not the folder of the caller.
    private static let otherFolder = URL(fileURLWithPath: "/work/other")

    /// ``otherFolder`` as the endpoint reads a `folder` argument: a directory
    /// URL.
    private static let otherFolderAsDirectory = URL(fileURLWithPath: otherFolder.path, isDirectory: true)

    /// ``Fixtures/workingFolder`` as the endpoint reads a `folder` argument:
    /// a directory URL.
    private static let workingFolderAsDirectory = URL(fileURLWithPath: Fixtures.workingFolder.path, isDirectory: true)

    /// A source session of Claude Code in the folder of the caller, with a
    /// title.
    private static let titledSource = RecordingSessionImporter.source(
        agent: claudeCode, sourceID: "a1b2c3", title: "Fix the parser", folder: Fixtures.workingFolder, turnCount: 12)

    /// A source session of Codex in a different folder, with no title.
    private static let untitledSource = RecordingSessionImporter.source(
        agent: codex, sourceID: "rollout-42", title: nil, folder: otherFolder, turnCount: 4)

    /// A source id that the fake importer does not have.
    private static let unknownSourceID = "no-such-source"

    /// The cursor that a page case gives in `after`.
    private static let pageCursor = "page-2"

    /// The `first` that a page case gives.
    private static let pageSize = 5

    /// The time of each import of the fake, as the endpoint gives it.
    private static let importedAtText = DateTime(RecordingSessionImporter.importedAt).rfc3339

    /// The `importableSessions` query of each agent, with each field of a
    /// session and of its earlier imports.
    private static let importablesQuery = """
        { importableSessions { nextCursor unreadableSources sessions { agent sourceId sourcePath title folder \
        lastDate turnCount previousImports { session { id } importedAt } } } }
        """

    /// The `importableSessions` query of the sessions of the folder `.`.
    private static let dotFolderQuery = "{ importableSessions(folder: \".\") { sessions { sourceId } } }"

    /// The `importableSessions` query with ``otherFolder`` as the folder
    /// whose sessions come first.
    private static let preferredFolderQuery =
        "{ importableSessions(preferredFolder: \"\(otherFolder.path)\") { sessions { sourceId } } }"

    /// A `preferredFolder` that is not absolute.
    private static let relativeFolder = "work/other"

    /// The `importSession` mutation of ``titledSource``, with the id, the
    /// title and the folder of the new session.
    private static let importTitledMutation = """
        mutation { importSession(input: {agent: "claude-code", source: "a1b2c3"}) { id title cwd } }
        """

    /// The fields of the `importedFrom` of a session, each field of
    /// `SessionImportProvenance`.
    private static let provenanceSelection = """
        importedFrom { agent sourceId sourcePath sourceLastDate importedAt skippedRecordCount }
        """

    /// The `importSession` mutation of ``titledSource``, with the
    /// `importedFrom` of the new session.
    private static let importWithProvenanceMutation = """
        mutation { importSession(input: {agent: "claude-code", source: "a1b2c3"}) { \(provenanceSelection) } }
        """

    /// The `sessions` query of each session, live or not, with the id and
    /// the `importedFrom` of each session.
    private static let sessionsWithProvenanceQuery = """
        { sessions(filter: {includeRecorded: true}) { id \(provenanceSelection) } }
        """

    /// Each field of the `importedFrom` of an import of ``titledSource``, in
    /// the order of ``provenanceSelection``, as text.
    private static let titledProvenanceTexts = [
        claudeCode, titledSource.sourceID, titledSource.sourcePath, DateTime(Fixtures.fixedDate).rfc3339,
        importedAtText, String(RecordingSessionImporter.skippedRecordCount),
    ]

    /// The op string of `list imports`.
    private static let listOp = "list imports"

    /// The op string of `import session`.
    private static let importOp = "import session"

    // MARK: - Helpers

    /// One directory, a fake importer of ``titledSource`` and
    /// ``untitledSource`` over it, and the endpoint of that directory with
    /// that importer.
    private struct Setup {
        /// The directory that gets the new sessions.
        let directory = Fixtures.directoryWithLauncher()

        /// The fake importer of the endpoint.
        let importer: RecordingSessionImporter

        /// The endpoint over ``directory``. The setup holds it, because the
        /// endpoint cache holds an endpoint weakly.
        let graph: SessionsGraph

        /// Makes the importer and gives it to the endpoint.
        ///
        /// - Parameters:
        ///   - unreadableSources: The agents whose sessions the fake cannot
        ///     read. The default is none.
        ///   - unavailableFolders: The folders in which the fake cannot make
        ///     a session. The default is none.
        init(unreadableSources: [String] = [], unavailableFolders: [URL] = []) {
            importer = RecordingSessionImporter(
                directory: directory, sources: [titledSource, untitledSource], unreadableSources: unreadableSources,
                unavailableFolders: unavailableFolders)
            graph = SessionsGraph.endpoint(of: directory, importer: importer)
        }

        /// Runs one document on ``graph``.
        ///
        /// - Parameters:
        ///   - document: The document.
        ///   - viewer: The client of the call. The default is a device of the
        ///     user.
        /// - Returns: The response.
        /// - Throws: What the endpoint throws.
        func run(_ document: String, viewer: GraphQLViewer? = deviceViewer) async throws -> GraphQLReply {
            try await GraphQLReply.run(document, viewer: viewer, on: graph)
        }

        /// Runs one document on ``graph`` as the agent of a caller session in
        /// ``Fixtures/workingFolder``.
        ///
        /// - Parameter document: The document.
        /// - Returns: The response.
        /// - Throws: What the endpoint throws.
        func runAsCaller(_ document: String) async throws -> GraphQLReply {
            try await Fixtures.asCaller(in: directory) { _ in try await run(document, viewer: nil) }
        }

        /// Runs one document on ``graph``, and calls one operation of a tool
        /// with the importer over ``directory``, both as the agent of the
        /// same caller session.
        ///
        /// - Parameters:
        ///   - document: The document.
        ///   - op: The op string.
        ///   - fields: The fields of the operation.
        /// - Returns: The response, and the answer of the tool.
        /// - Throws: What the endpoint or the tool throws.
        func runWithTool(
            _ document: String, op: String, _ fields: [(String, any ConvertibleToGeneratedContent)]
        ) async throws -> (reply: GraphQLReply, answer: String) {
            try await SessionsGraphImportTests.runWithTool(
                document, op: op, fields, importer: importer, in: directory, on: graph)
        }

        /// The imported sessions of ``directory``, in the order of their ids.
        ///
        /// - Returns: Each session with a provenance.
        /// - Throws: What the directory throws.
        func importedSessions() async throws -> [SessionSummary] {
            try await SessionsGraphImportTests.importedSessions(in: directory)
        }

        /// Imports ``titledSource`` one time with the importer, not with the
        /// endpoint.
        ///
        /// - Returns: The id of the new session.
        /// - Throws: What the importer throws.
        func importTitledSource() async throws -> ULID {
            let order = SessionImportOrder(
                agent: claudeCode, source: titledSource.sourceID, folder: nil, name: nil)
            return try await importer.importSession(order).session
        }
    }

    /// Runs one document on an endpoint, and calls one operation of a tool
    /// with `importer` over `directory`, both as the agent of the same caller
    /// session.
    ///
    /// - Parameters:
    ///   - document: The document.
    ///   - op: The op string.
    ///   - fields: The fields of the operation.
    ///   - importer: The importer of the tool, or `nil` for none.
    ///   - directory: The directory of the tool and of the endpoint.
    ///   - graph: The endpoint.
    /// - Returns: The response, and the answer of the tool.
    /// - Throws: What the endpoint or the tool throws.
    private static func runWithTool(
        _ document: String, op: String, _ fields: [(String, any ConvertibleToGeneratedContent)],
        importer: (any SessionImporter)?, in directory: InMemorySessionDirectory, on graph: SessionsGraph
    ) async throws -> (reply: GraphQLReply, answer: String) {
        let tool = try SessionsTool(directory: directory, importer: importer)
        return try await Fixtures.asCaller(in: directory) { _ in
            let answer = try await tool.call(arguments: Fixtures.payload(op, fields))
            return (try await GraphQLReply.run(document, on: graph), answer)
        }
    }

    /// The imported sessions of a directory, in the order of their ids.
    ///
    /// - Parameter directory: The directory.
    /// - Returns: Each session with a provenance.
    /// - Throws: What the directory throws.
    private static func importedSessions(in directory: InMemorySessionDirectory) async throws -> [SessionSummary] {
        try await directory.sessions(matching: SessionQuery(includesRecorded: true))
            .filter { $0.importedFrom != nil }
            .sorted { $0.id.ulidString < $1.id.ulidString }
    }

    /// The sessions of the page of an `importableSessions` response.
    ///
    /// - Parameter reply: The response.
    /// - Returns: The sessions.
    /// - Throws: An error when the response has no page.
    private static func sessions(of reply: GraphQLReply) throws -> [[String: Any]] {
        try #require(try reply.object("importableSessions")["sessions"] as? [[String: Any]])
    }

    /// The earlier imports of the first session of an `importableSessions`
    /// response.
    ///
    /// - Parameter reply: The response.
    /// - Returns: The earlier imports.
    /// - Throws: An error when the response has no first session.
    private static func previousImports(in reply: GraphQLReply) throws -> [[String: Any]] {
        let first = try #require(try sessions(of: reply).first)
        return try #require(first["previousImports"] as? [[String: Any]])
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

    // MARK: - importableSessions

    /// `importableSessions` gives each field of a source session of the
    /// importer.
    @Test("importableSessions gives each field of a source session")
    func importableSessionsGivesEachFieldOfASource() async throws {
        let setup = Setup()

        let reply = try await setup.run(Self.importablesQuery)
        let first = try #require(try Self.sessions(of: reply).first)

        #expect(reply.codes.isEmpty, "errors: \(reply.messages)")
        #expect(
            [
                first["agent"], first["sourceId"], first["sourcePath"], first["title"], first["folder"],
                first["lastDate"], first["turnCount"],
            ].map { "\($0 ?? "nil")" } == [
                Self.claudeCode, Self.titledSource.sourceID, Self.titledSource.sourcePath, "Fix the parser",
                Fixtures.workingFolder.path, DateTime(Fixtures.fixedDate).rfc3339, "12",
            ])
    }

    /// A source session with no title gives `null` as its title.
    @Test("importableSessions gives null as the title of a source with no title")
    func importableSessionsGivesNullForNoTitle() async throws {
        let setup = Setup()

        let reply = try await setup.run(Self.importablesQuery)

        #expect(try Self.sessions(of: reply).last?["title"] is NSNull)
    }

    /// `importableSessions` gives each earlier import of a source with its
    /// `Session` from the directory and the time of the import.
    @Test("importableSessions gives each earlier import with its Session and its date")
    func importableSessionsGivesEachEarlierImport() async throws {
        let setup = Setup()
        let firstCopy = try await setup.importTitledSource()
        let secondCopy = try await setup.importTitledSource()

        let imports = try Self.previousImports(in: try await setup.run(Self.importablesQuery))

        #expect(
            Set(imports.map { ($0["session"] as? [String: Any])?["id"] as? String })
                == [firstCopy.ulidString, secondCopy.ulidString])
        #expect(imports.map { $0["importedAt"] as? String } == [Self.importedAtText, Self.importedAtText])
    }

    /// `importableSessions` gives each agent whose sessions the importer
    /// cannot read in `unreadableSources`.
    @Test("importableSessions gives each agent with no access in unreadableSources")
    func importableSessionsGivesTheUnreadableSources() async throws {
        let setup = Setup(unreadableSources: [Self.codex])

        let reply = try await setup.run(Self.importablesQuery)

        #expect(try reply.object("importableSessions")["unreadableSources"] as? [String] == [Self.codex])
    }

    /// The last page of the importer gives `null` as its `nextCursor`.
    @Test("importableSessions gives null as the nextCursor of the last page")
    func importableSessionsGivesNullForTheLastPage() async throws {
        let setup = Setup()

        let reply = try await setup.run(Self.importablesQuery)

        #expect(try reply.object("importableSessions")["nextCursor"] is NSNull)
    }

    /// `importableSessions` gives the agent, the folder, `first` and `after`
    /// to the importer. A client has no caller session, so no folder comes
    /// first.
    @Test("importableSessions gives the agent, the folder, first and after to the importer")
    func importableSessionsGivesTheRequest() async throws {
        let setup = Setup()

        _ = try await setup.run(
            "{ importableSessions(agent: \"\(Self.codex)\", folder: \"\(Self.otherFolder.path)\", "
                + "first: \(Self.pageSize), after: \"\(Self.pageCursor)\") { nextCursor } }")

        #expect(
            await setup.importer.requests == [
                ImportableSessionsRequest(
                    agent: Self.codex, folder: Self.otherFolderAsDirectory, preferredFolder: nil, limit: Self.pageSize,
                    cursor: Self.pageCursor)
            ])
    }

    /// `importableSessions` with no `first` asks the importer for 20
    /// sessions.
    @Test("importableSessions with no first asks the importer for 20 sessions")
    func importableSessionsAsksForTwentyByDefault() async throws {
        let setup = Setup()

        _ = try await setup.run(Self.importablesQuery)

        #expect(await setup.importer.requests.map(\.limit) == [SessionsVisibility.defaultImportLimit])
    }

    /// The folder `.` of a client names no folder, because a client has no
    /// caller session: the query gives `INVALID_FOLDER` and asks the
    /// importer nothing.
    @Test("importableSessions with folder . from a client gives INVALID_FOLDER and asks the importer nothing")
    func importableSessionsWithTheDotFolderFromAClientIsRefused() async throws {
        let setup = Setup()

        let reply = try await setup.run(Self.dotFolderQuery)

        #expect(reply.codes == ["INVALID_FOLDER"])
        #expect(await setup.importer.requests == [])
    }

    /// The folder `.` of the agent is the folder of its caller session, as
    /// in the tool, and the sessions of that folder come first.
    @Test("importableSessions with folder . from the agent asks for the folder of the caller session")
    func importableSessionsWithTheDotFolderFromTheAgentUsesTheCallerFolder() async throws {
        let setup = Setup()

        _ = try await setup.runAsCaller(Self.dotFolderQuery)

        #expect(
            await setup.importer.requests.map { [$0.folder, $0.preferredFolder] } == [
                [Fixtures.workingFolder, Fixtures.workingFolder]
            ])
    }

    /// The `preferredFolder` of a client goes to the importer as the folder
    /// whose sessions come first. It does not filter, so the request has no
    /// `folder`.
    @Test("importableSessions with preferredFolder from a client gives that folder first and no filter")
    func importableSessionsGivesThePreferredFolderOfAClient() async throws {
        let setup = Setup()

        _ = try await setup.run(Self.preferredFolderQuery)

        #expect(
            await setup.importer.requests.map { [$0.folder, $0.preferredFolder] } == [
                [nil, Self.otherFolderAsDirectory]
            ])
    }

    /// A client with no `preferredFolder` has no folder that comes first.
    @Test("importableSessions with no preferredFolder from a client gives no folder first")
    func importableSessionsGivesNoPreferredFolderForAClient() async throws {
        let setup = Setup()

        _ = try await setup.run(Self.importablesQuery)

        #expect(await setup.importer.requests.map(\.preferredFolder) == [nil])
    }

    /// The agent with no `preferredFolder` gets the sessions of the folder of
    /// its caller session first.
    @Test("importableSessions with no preferredFolder from the agent gives the folder of the caller session first")
    func importableSessionsGivesTheCallerFolderFirstForTheAgent() async throws {
        let setup = Setup()

        _ = try await setup.runAsCaller(Self.importablesQuery)

        #expect(await setup.importer.requests.map(\.preferredFolder) == [Fixtures.workingFolder])
    }

    /// The `preferredFolder` of the agent replaces the folder of its caller
    /// session.
    @Test("importableSessions with preferredFolder from the agent gives that folder first")
    func importableSessionsGivesThePreferredFolderOfTheAgent() async throws {
        let setup = Setup()

        _ = try await setup.runAsCaller(Self.preferredFolderQuery)

        #expect(await setup.importer.requests.map(\.preferredFolder) == [Self.otherFolderAsDirectory])
    }

    /// A `preferredFolder` that is not absolute gives `INVALID_FOLDER` and
    /// asks the importer nothing.
    @Test("importableSessions with a relative preferredFolder gives INVALID_FOLDER and asks the importer nothing")
    func importableSessionsWithARelativePreferredFolderIsRefused() async throws {
        let setup = Setup()

        let reply = try await setup.run(
            "{ importableSessions(preferredFolder: \"\(Self.relativeFolder)\") { sessions { sourceId } } }")

        #expect(reply.codes == ["INVALID_FOLDER"])
        #expect(await setup.importer.requests == [])
    }

    /// An external client does not see an earlier import whose session it
    /// cannot see: the page drops it, so the page does not tell that the
    /// session exists.
    @Test("importableSessions drops an earlier import whose session an external client cannot see")
    func importableSessionsDropsAnInvisibleEarlierImport() async throws {
        let setup = Setup()
        _ = try await setup.importTitledSource()

        let reply = try await setup.run(Self.importablesQuery, viewer: .external())

        #expect(try Self.previousImports(in: reply).isEmpty)
    }

    /// An external client sees an earlier import of a session that it owns.
    @Test("importableSessions gives an external client an earlier import of a session that it owns")
    func importableSessionsGivesAnOwnedEarlierImport() async throws {
        let setup = Setup()
        let copy = try await setup.importTitledSource()

        let reply = try await setup.run(Self.importablesQuery, viewer: .external(owning: [copy.ulidString]))

        #expect(
            try Self.previousImports(in: reply).map { ($0["session"] as? [String: Any])?["id"] as? String } == [
                copy.ulidString
            ])
    }

    // MARK: - importSession

    /// `importSession` gives the new session as the directory gives it.
    @Test("importSession gives the new Session of the directory")
    func importSessionGivesTheNewSession() async throws {
        let setup = Setup()

        let reply = try await setup.run(Self.importTitledMutation)
        let session = try reply.object("importSession")
        let copy = try #require(try await setup.importedSessions().first)

        #expect(reply.codes.isEmpty, "errors: \(reply.messages)")
        #expect(
            [session["id"], session["title"], session["cwd"]].map { $0 as? String } == [
                copy.id.ulidString, "Fix the parser", Fixtures.workingFolder.path,
            ])
    }

    /// A second `importSession` of the same source makes a second session,
    /// and gives that second session (Q85).
    @Test("a second importSession of the same source gives a second session")
    func aSecondImportSessionGivesASecondSession() async throws {
        let setup = Setup()

        let first = try await setup.run(Self.importTitledMutation).object("importSession")
        let second = try await setup.run(Self.importTitledMutation).object("importSession")
        let ids: Set<String?> = [first["id"] as? String, second["id"] as? String]

        #expect(ids == Set(try await setup.importedSessions().map { Optional($0.id.ulidString) }))
        #expect(ids.count == 2)
    }

    /// `importSession` gives the agent, the source, the folder and the name
    /// of its input to the importer.
    @Test("importSession gives the agent, the source, the folder and the name to the importer")
    func importSessionGivesTheOrder() async throws {
        let setup = Setup()

        _ = try await setup.run(
            "mutation { importSession(input: {agent: \"\(Self.codex)\", source: \"\(Self.untitledSource.sourceID)\", "
                + "folder: \"\(Fixtures.workingFolder.path)\", name: \"Rollout\"}) { id } }")

        #expect(
            await setup.importer.orders == [
                SessionImportOrder(
                    agent: Self.codex, source: Self.untitledSource.sourceID, folder: Self.workingFolderAsDirectory,
                    name: "Rollout")
            ])
    }

    /// The folder `.` of the agent is the folder of its caller session, as
    /// in the tool.
    @Test("importSession with folder . from the agent imports into the folder of the caller session")
    func importSessionWithTheDotFolderFromTheAgentUsesTheCallerFolder() async throws {
        let setup = Setup()

        _ = try await setup.runAsCaller(
            "mutation { importSession(input: {agent: \"\(Self.codex)\", source: \"\(Self.untitledSource.sourceID)\", "
                + "folder: \".\"}) { id } }")

        #expect(await setup.importer.orders.map(\.folder) == [Fixtures.workingFolder])
    }

    /// An external client cannot import a session, as it cannot start one:
    /// the mutation gives `UNTRUSTED_CLIENT`, and asks the importer nothing.
    @Test("importSession from an external client gives UNTRUSTED_CLIENT and asks the importer nothing")
    func importSessionFromAnExternalClientIsRefused() async throws {
        let setup = Setup()

        let reply = try await setup.run(Self.importTitledMutation, viewer: .external())

        #expect(reply.codes == ["UNTRUSTED_CLIENT"])
        #expect(await setup.importer.orders == [])
    }

    /// The agent acts as its caller session, so a call with no caller
    /// session gets `MISSING_CALLER` with the corrective of the tool, and
    /// imports nothing.
    @Test("importSession by the agent with no caller session gives MISSING_CALLER with the corrective of the tool")
    func importSessionWithNoCallerGivesMissingCaller() async throws {
        let setup = Setup()

        let answer = try await SessionsTool(directory: setup.directory, importer: setup.importer)
            .call(arguments: Fixtures.payload(Self.importOp, [("agent", Self.claudeCode), ("source", "a1b2c3")]))
        let reply = try await setup.run(Self.importTitledMutation, viewer: nil)

        #expect(reply.codes == ["MISSING_CALLER"])
        #expect(reply.messages == [answer])
        #expect(await setup.importer.orders == [])
    }

    // MARK: - importedFrom

    /// The answer of `importSession` gives where the new session came from:
    /// each field of the provenance of the import.
    @Test("importSession gives each field of the importedFrom of the new session")
    func importSessionGivesTheImportedFrom() async throws {
        let setup = Setup()

        let reply = try await setup.run(Self.importWithProvenanceMutation)

        #expect(reply.codes.isEmpty, "errors: \(reply.messages)")
        #expect(try Self.provenanceTexts(of: try reply.object("importSession")) == Self.titledProvenanceTexts)
    }

    /// `sessions` gives each field of the `importedFrom` of an imported
    /// session.
    @Test("sessions gives each field of the importedFrom of an imported session")
    func sessionsGivesTheImportedFrom() async throws {
        let setup = Setup()
        let copy = try await setup.importTitledSource()

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
        let copy = try await setup.importTitledSource()

        let reply = try await setup.run(
            "{ sessions(filter: {includeRecorded: true}) { id imported_from { source_id source_path } } }")
        let provenance = try #require(try Self.session(copy, in: reply)["imported_from"] as? [String: Any])

        #expect(reply.codes.isEmpty, "errors: \(reply.messages)")
        #expect(reply.rewrote("imported_from", to: "importedFrom"))
        #expect(
            [provenance["source_id"], provenance["source_path"]].map { $0 as? String } == [
                Self.titledSource.sourceID, Self.titledSource.sourcePath,
            ])
    }

    // MARK: - The refusals of the tool

    /// The query with no importer gives `IMPORT_UNAVAILABLE` with the
    /// corrective of `list imports`.
    @Test("importableSessions with no importer gives IMPORT_UNAVAILABLE with the corrective of the tool")
    func importableSessionsWithNoImporterIsRefused() async throws {
        let directory = Fixtures.directoryWithLauncher()
        let graph = SessionsGraph.endpoint(of: directory)

        let (reply, answer) = try await Self.runWithTool(
            Self.importablesQuery, op: Self.listOp, [], importer: nil, in: directory, on: graph)

        #expect(reply.codes == ["IMPORT_UNAVAILABLE"])
        #expect(reply.messages == [answer])
    }

    /// The mutation with no importer gives `IMPORT_UNAVAILABLE` with the
    /// corrective of `import session`, and makes no session.
    @Test("importSession with no importer gives IMPORT_UNAVAILABLE with the corrective of the tool")
    func importSessionWithNoImporterIsRefused() async throws {
        let directory = Fixtures.directoryWithLauncher()
        let graph = SessionsGraph.endpoint(of: directory)

        let (reply, answer) = try await Self.runWithTool(
            Self.importTitledMutation, op: Self.importOp, [("agent", Self.claudeCode), ("source", "a1b2c3")],
            importer: nil, in: directory, on: graph)

        #expect(reply.codes == ["IMPORT_UNAVAILABLE"])
        #expect(reply.messages == [answer])
        #expect(try await Self.importedSessions(in: directory).isEmpty)
    }

    /// One import that the importer refuses, and the code of the refusal.
    struct ImportRefusalCase: Sendable, CustomTestStringConvertible {
        /// The code that the endpoint gives.
        let code: String

        /// The source agent of the import.
        let agent: String

        /// The source id of the import.
        let source: String

        /// The name of the case in the test report.
        var testDescription: String { code }

        /// The input object of the mutation.
        var input: String {
            "{agent: \"\(agent)\", source: \"\(source)\"}"
        }

        /// The fields of the `import session` operation.
        var fields: [(String, any ConvertibleToGeneratedContent)] {
            [("agent", agent), ("source", source)]
        }
    }

    /// One case for each refusal of the importer that the tool and the
    /// endpoint share. The setup of the cases cannot read the sessions of
    /// Codex, and cannot make a session in the folder of ``titledSource``.
    static let importRefusalCases = [
        ImportRefusalCase(code: "NO_SOURCE_ACCESS", agent: codex, source: untitledSource.sourceID),
        ImportRefusalCase(code: "IMPORT_FOLDER_UNAVAILABLE", agent: claudeCode, source: titledSource.sourceID),
        ImportRefusalCase(code: "IMPORT_FAILED", agent: claudeCode, source: unknownSourceID),
    ]

    /// The mutation refuses what `import session` refuses, with the code of
    /// the refusal and the corrective of the tool as its message.
    @Test("importSession refuses with the code and the corrective of the tool", arguments: importRefusalCases)
    func importSessionRefusesAsTheToolDoes(_ refusal: ImportRefusalCase) async throws {
        let setup = Setup(unreadableSources: [Self.codex], unavailableFolders: [Fixtures.workingFolder])

        let (reply, answer) = try await setup.runWithTool(
            "mutation { importSession(input: \(refusal.input)) { id } }", op: Self.importOp, refusal.fields)

        #expect(reply.codes == [refusal.code])
        #expect(reply.messages == [answer])
    }

    /// The query with an importer that fails gives `IMPORT_FAILED` with the
    /// corrective of `list imports`.
    @Test("importableSessions with an importer that fails gives IMPORT_FAILED with the corrective of the tool")
    func importableSessionsWithAFailingImporterIsRefused() async throws {
        let directory = Fixtures.directoryWithLauncher()
        let importer = FailingSessionImporter(failure: SessionImporterFailure(description: Self.unknownSourceID))
        let graph = SessionsGraph.endpoint(of: directory, importer: importer)

        let (reply, answer) = try await Self.runWithTool(
            Self.importablesQuery, op: Self.listOp, [], importer: importer, in: directory, on: graph)

        #expect(reply.codes == ["IMPORT_FAILED"])
        #expect(reply.messages == [answer])
    }

    // MARK: - Aliases

    /// The query takes the code-mode verb of `list imports` and the names of
    /// its parameters, and reports each rewrite.
    @Test("importableSessions takes listImports and the parameter names of list imports")
    func importableSessionsTakesTheAliases() async throws {
        let setup = Setup()

        let reply = try await setup.run(
            "{ listImports(from: \"\(Self.codex)\", limit: \(Self.pageSize)) { items { sourceID } } }")

        #expect(reply.codes.isEmpty, "errors: \(reply.messages)")
        #expect(reply.rewrote("listImports", to: "importableSessions"))
        #expect(await setup.importer.requests.map { [$0.agent ?? "", String($0.limit)] } == [[Self.codex, "5"]])
    }

    /// The query takes `preferred_folder` for `preferredFolder`, and reports
    /// the rewrite.
    @Test("importableSessions takes preferred_folder for preferredFolder")
    func importableSessionsTakesThePreferredFolderAlias() async throws {
        let setup = Setup()

        let reply = try await setup.run(
            "{ importableSessions(preferred_folder: \"\(Self.otherFolder.path)\") { sessions { sourceId } } }")

        #expect(reply.rewrote("preferred_folder", to: "preferredFolder"))
        #expect(await setup.importer.requests.map(\.preferredFolder) == [Self.otherFolderAsDirectory])
    }

    /// The mutation takes the bare verb of `import session` and the aliases
    /// of the parameters of the op for the fields of its input.
    @Test("importSession takes import and the aliases of the parameters of import session")
    func importSessionTakesTheAliases() async throws {
        let setup = Setup()

        let reply = try await setup.run(
            "mutation { import(input: {from: \"\(Self.codex)\", sourceId: \"\(Self.untitledSource.sourceID)\", "
                + "cwd: \"\(Fixtures.workingFolder.path)\", title: \"Rollout\"}) { id } }")

        #expect(reply.codes.isEmpty, "errors: \(reply.messages)")
        #expect(
            await setup.importer.orders == [
                SessionImportOrder(
                    agent: Self.codex, source: Self.untitledSource.sourceID, folder: Self.workingFolderAsDirectory,
                    name: "Rollout")
            ])
    }

    // MARK: - The SDL

    /// The names of the types that the import fields add to the schema.
    static let importTypeNames = [
        "ImportableSession", "SessionPreviousImport", "ImportableSessionPage", "ImportSessionInput",
        "SessionImportProvenance",
    ]

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

    /// The SDL of the endpoint has each type of the import fields.
    @Test("the SDL has each type of the import fields", arguments: importTypeNames)
    func theSchemaHasEachImportType(_ name: String) throws {
        let graph = SessionsGraph.endpoint(of: InMemorySessionDirectory())

        let schema = try buildSchema(source: graph.schema)

        #expect(schema.getType(name: name) != nil)
    }

    /// The SDL of the endpoint has the query and the mutation of the import.
    @Test("the SDL has the query importableSessions and the mutation importSession")
    func theSchemaHasTheImportFields() throws {
        let graph = SessionsGraph.endpoint(of: InMemorySessionDirectory())

        let schema = try buildSchema(source: graph.schema)

        #expect(
            [
                try schema.queryType?.fields()["importableSessions"] != nil,
                try schema.mutationType?.fields()["importSession"] != nil,
            ] == [true, true])
    }

    /// The SDL of the endpoint has the optional argument `preferredFolder`
    /// of `importableSessions`, of the type `String`.
    @Test("the SDL has the optional argument preferredFolder of importableSessions")
    func theSchemaHasThePreferredFolderArgument() throws {
        let graph = SessionsGraph.endpoint(of: InMemorySessionDirectory())

        let schema = try buildSchema(source: graph.schema)
        let field = try #require(try schema.queryType?.fields()["importableSessions"])

        #expect((field.args["preferredFolder"]?.type as? GraphQLScalarType)?.name == "String")
    }
}
