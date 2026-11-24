// `SessionsGraphExternalTests` — the external session fields of the
// `sessions` GraphQL endpoint (D212, design section 7): the
// `externalSessions` and `externalSessionCounts` queries, the `externalSessionChanges` and
// `externalSessionUpdates` subscriptions and the `continueExternalSession`
// and `rebuildExternalSessionIndex` mutations.
//
// Each case uses its own `InMemorySessionDirectory` and its own fake host
// from the fixtures. A case that proves an order waits for a signal of the
// fake host, never for a time.

import Foundation
import FoundationModelsExtras
import GraphQL
import Testing

@testable import FoundationModelsMultitool

/// Behavioral tests for the external session fields of the `sessions`
/// endpoint.
@Suite("SessionsGraphExternalTests", .ownsTemporaryDirectories)
struct SessionsGraphExternalTests {

    // MARK: - Constants

    /// The shared fixtures of the `sessions` tool tests.
    private typealias Fixtures = SessionsToolFixtures

    /// The fake host type.
    private typealias Host = FakeExternalSessionHost

    /// A device of the user, which owns no session.
    private static let deviceViewer = SessionsGraphChangesTests.deviceViewer

    /// The folder of a continue case: not the folder of the source.
    private static let otherFolder = URL(fileURLWithPath: "/work/other")

    /// The name of the new session of a continue case.
    private static let newName = "parser-fix"

    /// The `externalSessions` query with each field of a session and of the
    /// page, with the automated sessions.
    private static let pageQuery = """
        { externalSessions(automated: true) { nextCursor unreadableSources indexState { filesFound filesRead \
        isComplete } sessions { source sourceId path projectKey size modified cwd gitBranch isAutomated title \
        firstPrompt lastPrompt firstDate lastDate state displayText displayDate } } }
        """

    /// The `externalSessions` query with the source id of each session.
    private static let idsQuery = "{ externalSessions { sessions { sourceId } } }"

    /// The `continueExternalSession` mutation of the typed session into
    /// ``otherFolder`` with ``newName``.
    private static let continueMutation = """
        mutation { continueExternalSession(input: {source: "claude-code", id: "a1b2c3", folder: "/work/other", \
        name: "parser-fix"}) { title cwd } }
        """

    /// The `externalSessionCounts` query of each source and each folder.
    private static let countsQuery =
        "{ externalSessionCounts { typedCount automatedCount indexState { filesFound filesRead isComplete } } }"

    /// The `rebuildExternalSessionIndex` mutation of the source Codex.
    private static let rebuildMutation = "mutation { rebuildExternalSessionIndex(input: {source: \"codex\"}) }"

    /// The `externalSessionChanges` subscription of the working folder.
    private static let changesSubscription = """
        subscription { externalSessionChanges(folder: "/work/project") { changed { sourceId title } removed { \
        source sourceId } indexState { filesFound filesRead isComplete } } }
        """

    /// The `externalSessionUpdates` subscription of the typed session.
    private static let updatesSubscription = """
        subscription { externalSessionUpdates(source: "claude-code", id: "a1b2c3") { entries { kind timestamp \
        payload } } }
        """

    /// The `externalSessionUpdates` subscription of a session that the
    /// index does not have.
    private static let unknownUpdatesSubscription = """
        subscription { externalSessionUpdates(source: "claude-code", id: "no-such-session") { entries { kind } } }
        """

    // MARK: - Helpers

    /// One directory, a fake host, and the endpoint of that directory with
    /// that host.
    private struct Setup {
        /// The directory of the endpoint.
        let directory = Fixtures.directoryWithLauncher()

        /// The fake host of the endpoint.
        let host: FakeExternalSessionHost

        /// The endpoint over ``directory``. The setup holds it, because the
        /// endpoint cache holds an endpoint weakly.
        let graph: SessionsGraph

        /// Gives the host to the endpoint.
        ///
        /// - Parameter host: The fake host. The default has the fixed
        ///   sessions and a complete index.
        init(host: FakeExternalSessionHost = FakeExternalSessionHost()) {
            self.host = host
            graph = SessionsGraph.endpoint(of: directory, externalSessionHost: host)
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

        /// Starts one subscription on ``graph`` as a device of the user.
        ///
        /// - Parameter document: The subscription document.
        /// - Returns: The responses.
        /// - Throws: What the endpoint throws.
        func subscribe(_ document: String) async throws -> AsyncThrowingStream<String, Error> {
            try await graph.subscribe(query: document, variables: [:], operationName: nil, viewer: deviceViewer)
        }
    }

    /// The first response of a subscription.
    ///
    /// - Parameter responses: The responses.
    /// - Returns: The first response.
    /// - Throws: An error when the stream ends with no response.
    private static func firstReply(of responses: AsyncThrowingStream<String, Error>) async throws -> GraphQLReply {
        var iterator = responses.makeAsyncIterator()
        return try GraphQLReply(json: try #require(try await iterator.next()))
    }

    /// The text at `content.text` of the payload of each entry of an update
    /// response.
    ///
    /// - Parameter reply: The response of `externalSessionUpdates`.
    /// - Returns: The texts, in the order of the entries. An entry with no
    ///   text gives its title.
    private static func entryTexts(of reply: GraphQLReply) throws -> [String] {
        let entries = try #require(try reply.object("externalSessionUpdates")["entries"] as? [[String: Any]])
        return try entries.map { entry in
            let payload = try #require(entry["payload"] as? [String: Any])
            let content = payload["content"] as? [String: Any]
            return try #require(content?["text"] as? String ?? payload["title"] as? String)
        }
    }

    // MARK: - Cancellation

    @Test("the cancellation of an externalSessions call arrives at the host")
    func theCancellationOfTheQueryArrivesAtTheHost() async throws {
        let setup = Setup(host: FakeExternalSessionHost(blocksCalls: true))
        var starts = setup.host.queryStarts.makeAsyncIterator()
        var cancellations = setup.host.queryCancellations.makeAsyncIterator()
        let graph = setup.graph
        let call = Task {
            try await graph.execute(query: Self.idsQuery, variables: [:], operationName: nil, viewer: Self.deviceViewer)
        }

        _ = await starts.next()
        call.cancel()
        let cancelled: Void? = await cancellations.next()
        _ = try? await call.value

        #expect(cancelled != nil)
        #expect(setup.host.queries.count == 1)
    }

    @Test("the cancellation of an externalSessionCounts call arrives at the host")
    func theCancellationOfTheCountsQueryArrivesAtTheHost() async throws {
        let setup = Setup(host: FakeExternalSessionHost(blocksCalls: true))
        var starts = setup.host.queryStarts.makeAsyncIterator()
        var cancellations = setup.host.queryCancellations.makeAsyncIterator()
        let graph = setup.graph
        let call = Task {
            try await graph.execute(query: Self.countsQuery, variables: [:], operationName: nil, viewer: Self.deviceViewer)
        }

        _ = await starts.next()
        call.cancel()
        let cancelled: Void? = await cancellations.next()
        _ = try? await call.value

        #expect(cancelled != nil)
        #expect(setup.host.countScopes.count == 1)
    }

    @Test("the cancellation of a continueExternalSession call arrives at the host")
    func theCancellationOfTheContinueMutationArrivesAtTheHost() async throws {
        let setup = Setup(host: FakeExternalSessionHost(blocksCalls: true))
        var starts = setup.host.continueStarts.makeAsyncIterator()
        var cancellations = setup.host.continueCancellations.makeAsyncIterator()
        let graph = setup.graph
        let call = Task {
            try await graph.execute(query: Self.continueMutation, variables: [:], operationName: nil, viewer: Self.deviceViewer)
        }

        _ = await starts.next()
        call.cancel()
        let cancelled: Void? = await cancellations.next()
        _ = try? await call.value

        #expect(cancelled != nil)
        #expect(setup.host.continueRequests.count == 1)
    }

    // MARK: - externalSessions

    @Test("the externalSessions page has the rows, the indexState, the next cursor and the unreadable sources")
    func thePageHasTheIndexState() async throws {
        let index = ExternalSessionIndexState(filesFound: 400, filesRead: 120, isComplete: false)
        let setup = Setup(
            host: FakeExternalSessionHost(indexState: index, nextCursor: "page-2", unreadableSources: [Host.codex]))

        let reply = try await setup.run(Self.pageQuery)

        #expect(reply.codes.isEmpty, "errors: \(reply.messages)")
        let page = try reply.object("externalSessions")
        let state = try #require(page["indexState"] as? [String: Any])
        #expect(state["filesFound"] as? Int == 400)
        #expect(state["filesRead"] as? Int == 120)
        #expect(state["isComplete"] as? Bool == false)
        #expect(page["nextCursor"] as? String == "page-2")
        #expect(page["unreadableSources"] as? [String] == [Host.codex])
        let sessions = try #require(page["sessions"] as? [[String: Any]])
        #expect(sessions.map { $0["sourceId"] as? String } == ["a1b2c3", "rollout-42"])
        let typed = try #require(sessions.first)
        #expect(typed["source"] as? String == Host.claudeCode)
        #expect(typed["path"] as? String == "-work-project/a1b2c3.jsonl")
        #expect(typed["projectKey"] as? String == "-work-project")
        #expect(typed["cwd"] as? String == Fixtures.workingFolder.path)
        #expect(typed["gitBranch"] as? String == "main")
        #expect(typed["isAutomated"] as? Bool == false)
        #expect(typed["title"] as? String == "Fix the parser")
        #expect(typed["firstPrompt"] as? String == "The parser fails")
        #expect(typed["lastPrompt"] as? String == "Run the tests")
        #expect(typed["state"] as? String == "READ")
        #expect(typed["displayText"] as? String == "Fix the parser")
        #expect(typed["displayDate"] as? String == DateTime(Fixtures.fixedDate).rfc3339)
        let automated = try #require(sessions.last)
        #expect(automated["size"] as? Double == 8_000_000_000)
        #expect(automated["isAutomated"] as? Bool == true)
        #expect(automated["state"] as? String == "FOUND")
        #expect(automated["displayText"] is NSNull)
        #expect(automated["cwd"] is NSNull)
    }

    @Test("externalSessions gives the host the source, the folder, the automated filter and the page")
    func theQueryGivesTheArgumentsToTheHost() async throws {
        let setup = Setup()

        let reply = try await setup.run(
            "{ externalSessions(source: \"codex\", folder: \"/work/other\", first: 5, after: \"page-2\") "
                + "{ sessions { sourceId } } }")

        #expect(reply.codes.isEmpty, "errors: \(reply.messages)")
        #expect(
            setup.host.queries == [
                ExternalSessionQuery(
                    source: Host.codex, folder: URL(fileURLWithPath: Self.otherFolder.path, isDirectory: true),
                    automated: false, limit: 5, cursor: "page-2")
            ])
    }

    @Test("externalSessions of a folder gives the progress of the folder, and with no folder gives none")
    func theQueryGivesTheFolderIndexState() async throws {
        let folder = ExternalSessionIndexState(filesFound: 12, filesRead: 5, isComplete: false)
        let setup = Setup(host: FakeExternalSessionHost(folderIndexState: folder))
        let selection = "{ folderIndexState { filesFound filesRead isComplete } }"

        let withFolder = try await setup.run("{ externalSessions(folder: \"/work/project\") \(selection) }")
        let withNoFolder = try await setup.run("{ externalSessions \(selection) }")

        #expect(withFolder.codes.isEmpty, "errors: \(withFolder.messages)")
        let state = try #require(try withFolder.object("externalSessions")["folderIndexState"] as? [String: Any])
        #expect(state["filesFound"] as? Int == 12)
        #expect(state["filesRead"] as? Int == 5)
        #expect(state["isComplete"] as? Bool == false)
        #expect(try withNoFolder.object("externalSessions")["folderIndexState"] is NSNull)
    }

    @Test("externalSessions with a cursor that the host refuses gives the code INVALID_CURSOR")
    func theQueryWithABadCursorGivesTheCode() async throws {
        let setup = Setup(host: FakeExternalSessionHost(invalidCursor: "bad"))

        let reply = try await setup.run("{ externalSessions(after: \"bad\") { nextCursor } }")

        #expect(reply.codes == [SessionsRefusal.Kind.invalidCursor.rawValue])
        #expect(reply.messages == [SessionsToolText.externalInvalidCursor("bad")])
    }

    @Test("externalSessions with no automated argument gives only the typed sessions")
    func theQueryWithNoAutomatedArgumentGivesTheTypedSessions() async throws {
        let setup = Setup()

        let reply = try await setup.run(Self.idsQuery)

        let sessions = try #require(try reply.object("externalSessions")["sessions"] as? [[String: Any]])
        #expect(sessions.map { $0["sourceId"] as? String } == ["a1b2c3"])
        #expect(setup.host.queries.map(\.automated) == [false])
    }

    @Test("externalSessions with folder . as the agent asks for the folder of the caller session")
    func theDotFolderOfTheAgentIsTheCallerFolder() async throws {
        let setup = Setup()

        let reply = try await setup.runAsCaller("{ externalSessions(folder: \".\") { sessions { sourceId } } }")

        #expect(reply.codes.isEmpty, "errors: \(reply.messages)")
        #expect(setup.host.queries.map(\.folder?.path) == [Fixtures.workingFolder.path])
    }

    @Test("externalSessions with folder . from a client gives INVALID_FOLDER and asks the host nothing")
    func theDotFolderOfAClientIsInvalid() async throws {
        let setup = Setup()

        let reply = try await setup.run("{ externalSessions(folder: \".\") { sessions { sourceId } } }")

        #expect(reply.codes == [SessionsRefusal.Kind.invalidFolder.rawValue])
        #expect(setup.host.queries.isEmpty)
    }

    @Test("externalSessions takes the aliases listExternalSessions and limit")
    func theQueryTakesItsAliases() async throws {
        let setup = Setup()

        let reply = try await setup.run("{ listExternalSessions(limit: 3) { items { sourceId } } }")

        #expect(reply.codes.isEmpty, "errors: \(reply.messages)")
        #expect(setup.host.queries.map(\.limit) == [3])
    }

    // MARK: - With no host and with no access

    @Test("with no host, each external session field gives EXTERNAL_SESSIONS_UNAVAILABLE with the corrective")
    func eachFieldWithNoHostIsUnavailable() async throws {
        let directory = Fixtures.directoryWithLauncher()
        let graph = SessionsGraph.endpoint(of: directory)
        let code = SessionsRefusal.Kind.externalSessionsUnavailable.rawValue

        let query = try await GraphQLReply.run(Self.idsQuery, viewer: Self.deviceViewer, on: graph)
        let mutation = try await GraphQLReply.run(Self.continueMutation, viewer: Self.deviceViewer, on: graph)
        let rebuild = try await GraphQLReply.run(Self.rebuildMutation, viewer: Self.deviceViewer, on: graph)
        let counts = try await GraphQLReply.run(Self.countsQuery, viewer: Self.deviceViewer, on: graph)
        let changes = try await Self.firstReply(
            of: graph.subscribe(
                query: Self.changesSubscription, variables: [:], operationName: nil, viewer: Self.deviceViewer))
        let updates = try await Self.firstReply(
            of: graph.subscribe(
                query: Self.updatesSubscription, variables: [:], operationName: nil, viewer: Self.deviceViewer))

        for reply in [query, mutation, rebuild, counts, changes, updates] {
            #expect(reply.codes == [code])
            #expect(reply.messages == [SessionsToolText.noExternalSessionHost])
        }
    }

    @Test("continueExternalSession of a source with no access gives NO_SOURCE_ACCESS with the Allow Access corrective")
    func theContinueOfASourceWithNoAccessGivesTheCorrective() async throws {
        let setup = Setup(host: FakeExternalSessionHost(unreadableSources: [Host.claudeCode]))

        let reply = try await setup.run(Self.continueMutation)

        #expect(reply.codes == [SessionsRefusal.Kind.noSourceAccess.rawValue])
        #expect(reply.messages == [SessionsToolText.noExternalSourceAccess(Host.claudeCode)])
        #expect(reply.messages.first?.contains("Allow Access to Claude Code Sessions…") == true)
    }

    // MARK: - externalSessionChanges

    @Test("the externalSessionChanges subscription gives a row when the index adds it")
    func theChangesSubscriptionGivesTheAddedRow() async throws {
        let setup = Setup()
        let index = ExternalSessionIndexState(filesFound: 4, filesRead: 4, isComplete: true)
        let responses = try await setup.subscribe(Self.changesSubscription)

        setup.host.add(Host.addedSession, indexState: index)
        let reply = try await Self.firstReply(of: responses)

        #expect(reply.codes.isEmpty, "errors: \(reply.messages)")
        let change = try reply.object("externalSessionChanges")
        let changed = try #require(change["changed"] as? [[String: Any]])
        #expect(changed.map { $0["sourceId"] as? String } == ["d4e5f6"])
        #expect(changed.first?["title"] as? String == "Add the cache")
        #expect((change["removed"] as? [Any])?.isEmpty == true)
        let state = try #require(change["indexState"] as? [String: Any])
        #expect(state["filesFound"] as? Int == 4)
        #expect(state["isComplete"] as? Bool == true)
        #expect(setup.host.changeFolders.map { $0?.path } == [Fixtures.workingFolder.path])
    }

    @Test("the externalSessionChanges subscription of a folder gives the progress of the folder")
    func theChangesSubscriptionGivesTheFolderIndexState() async throws {
        let setup = Setup()
        let index = ExternalSessionIndexState(filesFound: 400, filesRead: 120, isComplete: false)
        let folder = ExternalSessionIndexState(filesFound: 12, filesRead: 5, isComplete: false)
        let responses = try await setup.subscribe(
            "subscription { externalSessionChanges(folder: \"/work/project\") { folderIndexState { filesFound "
                + "filesRead isComplete } } }")

        setup.host.add(Host.addedSession, indexState: index, folderIndexState: folder)
        let reply = try await Self.firstReply(of: responses)

        #expect(reply.codes.isEmpty, "errors: \(reply.messages)")
        let state = try #require(try reply.object("externalSessionChanges")["folderIndexState"] as? [String: Any])
        #expect(state["filesFound"] as? Int == 12)
        #expect(state["filesRead"] as? Int == 5)
        #expect(state["isComplete"] as? Bool == false)
    }

    // MARK: - externalSessionUpdates

    @Test("the externalSessionUpdates subscription gives the batches in order and stops the host stream at the stop")
    func theUpdatesSubscriptionGivesTheBatchesInOrderAndStops() async throws {
        let setup = Setup(host: FakeExternalSessionHost(batches: Host.turns(2), finishesUpdates: false))
        var terminations = setup.host.updateTerminations.makeAsyncIterator()
        let responses = try await setup.subscribe(Self.updatesSubscription)
        let (received, receiver) = AsyncStream.makeStream(of: String.self)
        let client = Task {
            var iterator = responses.makeAsyncIterator()
            for _ in 0..<2 {
                if let response = try await iterator.next() {
                    receiver.yield(response)
                }
            }
            receiver.finish()
            // The client waits for a third batch, which never comes, until
            // its task stops.
            _ = try await iterator.next()
        }

        var replies: [GraphQLReply] = []
        for await response in received {
            replies.append(try GraphQLReply(json: response))
        }
        client.cancel()
        let stoppedByTheClient = await terminations.next()

        #expect(replies.flatMap(\.codes).isEmpty, "errors: \(replies.flatMap(\.messages))")
        #expect(
            try replies.map(Self.entryTexts) == [
                ["prompt 1", "thought 1", "answer 1", "Read file1.swift", "contents 1"],
                ["prompt 2", "thought 2", "answer 2", "Read file2.swift", "contents 2"],
            ])
        #expect(stoppedByTheClient == true)
        #expect(setup.host.updateSessions == [ExternalSessionID(source: Host.claudeCode, sourceID: "a1b2c3")])
    }

    @Test("the externalSessionUpdates subscription of a session that the index does not have ends with the code")
    func theUpdatesOfAnUnknownSessionEndWithTheCode() async throws {
        let setup = Setup()

        let reply = try await Self.firstReply(of: setup.subscribe(Self.unknownUpdatesSubscription))

        #expect(reply.codes == [SessionsRefusal.Kind.unknownExternalSession.rawValue])
        #expect(
            reply.messages == [
                SessionsToolText.unknownExternalSession(
                    ExternalSessionID(source: Host.claudeCode, sourceID: "no-such-session"))
            ])
    }

    // MARK: - continueExternalSession

    @Test("continueExternalSession calls the host one time with the folder and the name, and gives the new session")
    func theContinueMutationCallsTheHostOneTime() async throws {
        let setup = Setup()

        let reply = try await setup.run(Self.continueMutation)

        #expect(reply.codes.isEmpty, "errors: \(reply.messages)")
        let requests = setup.host.continueRequests
        #expect(requests.count == 1)
        #expect(requests.first?.session == ExternalSessionID(source: Host.claudeCode, sourceID: "a1b2c3"))
        #expect(requests.first?.folder?.path == Self.otherFolder.path)
        #expect(requests.first?.name == Self.newName)
        let session = try reply.object("continueExternalSession")
        #expect(session["title"] as? String == Self.newName)
        #expect(session["cwd"] as? String == Self.otherFolder.path)
    }

    @Test("continueExternalSession with no folder and no name gives the host none")
    func theContinueMutationWithNoFolderGivesNone() async throws {
        let setup = Setup()

        let reply = try await setup.run(
            "mutation { continueExternalSession(input: {source: \"claude-code\", id: \"a1b2c3\"}) { cwd } }")

        #expect(reply.codes.isEmpty, "errors: \(reply.messages)")
        #expect(
            setup.host.continueRequests == [
                ExternalSessionContinueRequest(session: ExternalSessionID(source: Host.claudeCode, sourceID: "a1b2c3"))
            ])
        #expect(try reply.object("continueExternalSession")["cwd"] as? String == Fixtures.workingFolder.path)
    }

    @Test("an external client cannot continue an external session, and the host gets no call")
    func anExternalClientCannotContinue() async throws {
        let setup = Setup()

        let reply = try await setup.run(Self.continueMutation, viewer: .external())

        #expect(reply.codes == [SessionsRefusal.Kind.untrustedClient.rawValue])
        #expect(reply.messages == [SessionsGraphText.externalContinue])
        #expect(setup.host.continueRequests.isEmpty)
    }

    @Test("continueExternalSession into a folder that the host cannot write gives FOLDER_UNAVAILABLE")
    func theContinueIntoAnUnavailableFolderGivesTheCode() async throws {
        let setup = Setup(host: FakeExternalSessionHost(unavailableFolders: [Self.otherFolder]))

        let reply = try await setup.run(Self.continueMutation)

        #expect(reply.codes == [SessionsRefusal.Kind.folderUnavailable.rawValue])
        #expect(
            reply.messages == [
                SessionsToolText.externalFolderUnavailable(URL(fileURLWithPath: Self.otherFolder.path, isDirectory: true))
            ])
    }

    // MARK: - rebuildExternalSessionIndex

    @Test("rebuildExternalSessionIndex calls the host one time with the source, and gives true")
    func theRebuildMutationCallsTheHostOneTime() async throws {
        let setup = Setup()

        let reply = try await setup.run(Self.rebuildMutation)

        #expect(reply.codes.isEmpty, "errors: \(reply.messages)")
        #expect(reply.data?["rebuildExternalSessionIndex"] as? Bool == true)
        #expect(setup.host.rebuildSources == [Host.codex])
    }

    @Test("rebuildExternalSessionIndex as the agent calls the host, and takes the aliases rebuild and agent")
    func theRebuildMutationOfTheAgentTakesTheAliases() async throws {
        let setup = Setup()

        let reply = try await setup.runAsCaller("mutation { rebuild(input: {agent: \"claude-code\"}) }")

        #expect(reply.codes.isEmpty, "errors: \(reply.messages)")
        #expect(setup.host.rebuildSources == [Host.claudeCode])
    }

    @Test("rebuildExternalSessionIndex of a source with no access gives NO_SOURCE_ACCESS with the corrective")
    func theRebuildOfASourceWithNoAccessGivesTheCode() async throws {
        let setup = Setup(host: FakeExternalSessionHost(unreadableSources: [Host.codex]))

        let reply = try await setup.run(Self.rebuildMutation)

        #expect(reply.codes == [SessionsRefusal.Kind.noSourceAccess.rawValue])
        #expect(reply.messages == [SessionsToolText.noExternalSourceAccess(Host.codex)])
    }

    @Test("an external client cannot rebuild the index, and the host gets no call")
    func anExternalClientCannotRebuild() async throws {
        let setup = Setup()

        let reply = try await setup.run(Self.rebuildMutation, viewer: .external())

        #expect(reply.codes == [SessionsRefusal.Kind.untrustedClient.rawValue])
        #expect(reply.messages == [SessionsGraphText.externalRebuild])
        #expect(setup.host.rebuildSources.isEmpty)
    }

    // MARK: - continuedSessions

    @Test("an external session gives the sessions that a continue made from it, the oldest first")
    func theSessionGivesTheContinuedSessions() async throws {
        let setup = Setup(host: FakeExternalSessionHost(sessions: [Host.continuedSession, Host.automatedSession]))

        let reply = try await setup.run(
            "{ externalSessions(automated: true) { sessions { continuedSessions { id createdAt } } } }")

        #expect(reply.codes.isEmpty, "errors: \(reply.messages)")
        let sessions = try #require(try reply.object("externalSessions")["sessions"] as? [[String: Any]])
        let continued = try #require(sessions.first?["continuedSessions"] as? [[String: Any]])
        #expect(
            continued.map { $0["id"] as? String } == [
                Host.firstContinuation.sessionID.ulidString, Host.secondContinuation.sessionID.ulidString,
            ])
        #expect(
            continued.map { $0["createdAt"] as? String } == [
                DateTime(Host.firstContinuation.createdAt).rfc3339,
                DateTime(Host.secondContinuation.createdAt).rfc3339,
            ])
        #expect((sessions.last?["continuedSessions"] as? [Any])?.isEmpty == true)
    }

    @Test("continuedSessions takes the aliases continuations and sessionId")
    func theContinuedSessionsTakeTheirAliases() async throws {
        let setup = Setup(host: FakeExternalSessionHost(sessions: [Host.continuedSession]))

        let reply = try await setup.run("{ externalSessions { sessions { continuations { sessionId } } } }")

        #expect(reply.codes.isEmpty, "errors: \(reply.messages)")
        let sessions = try #require(try reply.object("externalSessions")["sessions"] as? [[String: Any]])
        let continued = try #require(sessions.first?["continuations"] as? [[String: Any]])
        #expect(continued.count == 2)
    }

    // MARK: - filePath

    @Test("an external session gives the absolute path of its file, and null when the index has none")
    func theSessionGivesItsFilePath() async throws {
        let setup = Setup(host: FakeExternalSessionHost(sessions: [Host.filedSession, Host.automatedSession]))

        let reply = try await setup.run("{ externalSessions(automated: true) { sessions { filePath } } }")

        #expect(reply.codes.isEmpty, "errors: \(reply.messages)")
        let sessions = try #require(try reply.object("externalSessions")["sessions"] as? [[String: Any]])
        #expect(sessions.first?["filePath"] as? String == Host.sessionFile.path)
        #expect(sessions.last?["filePath"] is NSNull)
    }

    @Test("filePath takes the alias file_path")
    func theFilePathTakesItsAlias() async throws {
        let setup = Setup(host: FakeExternalSessionHost(sessions: [Host.filedSession]))

        let reply = try await setup.run("{ externalSessions { sessions { file_path } } }")

        #expect(reply.codes.isEmpty, "errors: \(reply.messages)")
        let sessions = try #require(try reply.object("externalSessions")["sessions"] as? [[String: Any]])
        #expect(sessions.first?["file_path"] as? String == Host.sessionFile.path)
    }

    // MARK: - externalSessionCounts

    @Test("externalSessionCounts gives the typed count, the automated count and the indexState")
    func theCountsQueryGivesTheCounts() async throws {
        let index = ExternalSessionIndexState(filesFound: 400, filesRead: 120, isComplete: false)
        let setup = Setup(host: FakeExternalSessionHost(indexState: index))

        let reply = try await setup.run(Self.countsQuery)

        #expect(reply.codes.isEmpty, "errors: \(reply.messages)")
        let counts = try reply.object("externalSessionCounts")
        #expect(counts["typedCount"] as? Int == 1)
        #expect(counts["automatedCount"] as? Int == 1)
        let state = try #require(counts["indexState"] as? [String: Any])
        #expect(state["filesFound"] as? Int == 400)
        #expect(state["filesRead"] as? Int == 120)
        #expect(state["isComplete"] as? Bool == false)
        #expect(setup.host.countScopes == [FakeExternalSessionHost.CountScope(source: nil, folder: nil)])
    }

    @Test("externalSessionCounts gives the host the source and the folder")
    func theCountsQueryGivesTheScopeToTheHost() async throws {
        let setup = Setup()

        let reply = try await setup.run(
            "{ externalSessionCounts(source: \"codex\", folder: \"/work/other\") { typedCount } }")

        #expect(reply.codes.isEmpty, "errors: \(reply.messages)")
        #expect(setup.host.countScopes.map(\.source) == [Host.codex])
        #expect(setup.host.countScopes.map(\.folder?.path) == [Self.otherFolder.path])
    }

    @Test("externalSessionCounts with folder . from a client gives INVALID_FOLDER and asks the host nothing")
    func theCountsQueryWithTheDotFolderOfAClientIsInvalid() async throws {
        let setup = Setup()

        let reply = try await setup.run("{ externalSessionCounts(folder: \".\") { typedCount } }")

        #expect(reply.codes == [SessionsRefusal.Kind.invalidFolder.rawValue])
        #expect(setup.host.countScopes.isEmpty)
    }

    @Test("externalSessionCounts takes the aliases countExternalSessions, agent and typed")
    func theCountsQueryTakesItsAliases() async throws {
        let setup = Setup()

        let reply = try await setup.run("{ countExternalSessions(agent: \"claude-code\") { typed } }")

        #expect(reply.codes.isEmpty, "errors: \(reply.messages)")
        #expect(try reply.object("countExternalSessions")["typed"] as? Int == 1)
        #expect(setup.host.countScopes.map(\.source) == [Host.claudeCode])
    }
}
