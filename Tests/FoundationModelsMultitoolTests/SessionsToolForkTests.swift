import Foundation
import FoundationModels
import FoundationModelsExtras
import GraphQL
import Testing
import ULID

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Coverage for `fork session` of ``SessionsTool`` and the `forkSession`
/// mutation of the `sessions` endpoint (D205), over an
/// `InMemorySessionDirectory`.
///
/// Each case reads the fork request that the directory recorded, or the
/// sessions of the directory after the call, so it proves the fork and not
/// only the text of the answer.
@Suite("SessionsToolForkTests", .ownsTemporaryDirectories)
struct SessionsToolForkTests {
    // MARK: - Shared test constants

    /// The shared fixtures of the `sessions` tool tests.
    private typealias Fixtures = SessionsToolFixtures

    /// The op string of the operation.
    private static let forkOp = "fork session"

    /// The title of the other session, which a fork names by its slug.
    private static let otherTitle = "Fix the API tests"

    /// The slug of ``otherTitle``.
    private static let otherSlug = "fix-the-api-tests"

    /// The first prompt of a fork.
    private static let firstPrompt = "Try the other approach."

    /// The op that sends a message to the fork, which the answer names.
    private static let sendMessageOp = "send message"

    /// The words of the answer that say that the fork works alone.
    private static let worksAloneWords = "works alone"

    /// The words of the corrective of a call with no caller session.
    private static let noCallerWords = "runs in no session"

    /// The words of the corrective of an archived source.
    private static let archivedWords = "is archived"

    /// The words of the corrective of a directory that cannot fork.
    private static let cannotForkWords = "cannot fork a session"

    /// The kind that the endpoint gives for a fork.
    private static let forkKind = "FORK"

    /// A device of the user.
    private static let deviceViewer = GraphQLViewer(clientId: "client-device", trust: .userDevice)

    // MARK: - Helpers

    /// The forks of `source` in `directory`.
    ///
    /// - Parameters:
    ///   - source: The source session.
    ///   - directory: The directory.
    /// - Returns: Their summaries.
    /// - Throws: What `sessions(matching:)` throws.
    private static func forks(of source: ULID, in directory: InMemorySessionDirectory) async throws
        -> [SessionSummary]
    {
        try await directory.sessions(matching: SessionQuery(kind: .fork, parentID: source))
    }

    /// Calls `fork session` as the caller, while the caller works in a turn,
    /// as a tool call does.
    ///
    /// - Parameters:
    ///   - fields: The fields of the call.
    ///   - directory: The directory.
    /// - Returns: The answer, the caller id and the one fork of the source.
    /// - Throws: What the call throws, or an error when the call made no fork.
    private static func forkFromATurn(
        _ fields: [(String, any ConvertibleToGeneratedContent)], in directory: InMemorySessionDirectory
    ) async throws -> (output: String, callerID: ULID, fork: SessionSummary) {
        try await Fixtures.asCaller(in: directory) { callerID in
            try directory.startUserTurn(of: callerID)
            let output = try await SessionsTool(directory: directory).call(
                arguments: Fixtures.payload(forkOp, fields))
            let fork = try #require(try await forks(of: callerID, in: directory).first)
            return (output, callerID, fork)
        }
    }

    // MARK: - fork session

    @Test("fork session with no id forks the caller session at the calling tool call")
    func forkSessionWithNoIDForksTheCallerAtTheToolCall() async throws {
        let directory = Fixtures.directoryWithLauncher()

        let (_, callerID, fork) = try await Self.forkFromATurn([], in: directory)

        let request = try #require(directory.forkRequest(of: fork.id))
        #expect(request.sourceID == callerID)
        #expect(request.cut == .callingToolCall)
    }

    @Test("fork session gives the id, the short id and the name of the fork")
    func forkSessionNamesTheFork() async throws {
        let directory = Fixtures.directoryWithLauncher()

        let (output, _, fork) = try await Self.forkFromATurn([], in: directory)

        #expect(output.contains(fork.id.ulidString), "output was: \(output)")
        #expect(output.contains(fork.shortID), "output was: \(output)")
        #expect(output.contains(fork.slug), "output was: \(output)")
    }

    @Test("fork session says that the fork works alone and that send message reaches it")
    func forkSessionSaysTheForkWorksAlone() async throws {
        let directory = Fixtures.directoryWithLauncher()

        let (output, _, _) = try await Self.forkFromATurn([], in: directory)

        #expect(output.contains(Self.worksAloneWords), "output was: \(output)")
        #expect(output.contains(Self.sendMessageOp), "output was: \(output)")
    }

    @Test("fork session with the @slug of another session forks it at its last completed turn")
    func forkSessionOfASlugForksAtTheLastCompletedTurn() async throws {
        let directory = Fixtures.directoryWithLauncher()
        let other = Fixtures.summary(title: Self.otherTitle)
        directory.register(other)

        try await Fixtures.asCaller(in: directory) { _ in
            _ = try await SessionsTool(directory: directory).call(
                arguments: Fixtures.payload(Self.forkOp, [("id", "@\(Self.otherSlug)")]))
        }

        let fork = try #require(try await Self.forks(of: other.id, in: directory).first)
        let request = try #require(directory.forkRequest(of: fork.id))
        #expect(request.cut == .lastCompletedTurn)
    }

    @Test("fork session with a message gives the message to the fork as its first prompt")
    func forkSessionWithAMessageGivesTheFirstPrompt() async throws {
        let directory = Fixtures.directoryWithLauncher()

        let (_, _, fork) = try await Self.forkFromATurn([("message", Self.firstPrompt)], in: directory)

        #expect(directory.forkRequest(of: fork.id)?.firstPrompt == Self.firstPrompt)
    }

    @Test("fork session takes prompt as an alias of message")
    func forkSessionTakesThePromptAlias() async throws {
        let directory = Fixtures.directoryWithLauncher()

        let (_, _, fork) = try await Self.forkFromATurn([("prompt", Self.firstPrompt)], in: directory)

        #expect(directory.forkRequest(of: fork.id)?.firstPrompt == Self.firstPrompt)
    }

    @Test("branch session is an alias of fork session")
    func branchSessionIsAnAliasOfForkSession() async throws {
        let directory = Fixtures.directoryWithLauncher()

        let forks = try await Fixtures.asCaller(in: directory) { callerID in
            try directory.startUserTurn(of: callerID)
            _ = try await SessionsTool(directory: directory).call(arguments: Fixtures.payload("branch session"))
            return try await Self.forks(of: callerID, in: directory)
        }

        #expect(forks.count == 1)
    }

    @Test("fork session with no ToolContext and no id gives the corrective of a call with no caller")
    func forkSessionWithNoCallerIsACorrective() async throws {
        let directory = Fixtures.directoryWithLauncher()

        let output = try await SessionsTool(directory: directory).call(arguments: Fixtures.payload(Self.forkOp))

        #expect(output.contains(Self.noCallerWords), "output was: \(output)")
    }

    @Test("fork session of an archived session gives the corrective of an archived session")
    func forkSessionOfAnArchivedSessionIsACorrective() async throws {
        let directory = Fixtures.directoryWithLauncher()
        let archived = Fixtures.summary()
        directory.register(archived)
        _ = try await directory.archive(archived.id, by: .user(clientID: Self.deviceViewer.clientId))

        let output = try await Fixtures.asCaller(in: directory) { _ in
            try await SessionsTool(directory: directory).call(
                arguments: Fixtures.payload(Self.forkOp, [("id", archived.id.ulidString)]))
        }

        #expect(output.contains(Self.archivedWords), "output was: \(output)")
    }

    @Test("fork session on a directory that cannot fork gives the corrective of FORK_UNSUPPORTED")
    func forkSessionOnADirectoryWithNoForkIsACorrective() async throws {
        let backing = Fixtures.directoryWithLauncher()
        let tool = try SessionsTool(directory: ForwardingSessionDirectory(backing: backing, canFork: false))

        let output = try await Fixtures.asCaller(in: backing) { callerID in
            try backing.startUserTurn(of: callerID)
            return try await tool.call(arguments: Fixtures.payload(Self.forkOp))
        }

        #expect(output.contains(Self.cannotForkWords), "output was: \(output)")
    }

    @Test("a forwarding directory forwards fork session to its backing directory")
    func aForwardingDirectoryForwardsTheFork() async throws {
        let backing = Fixtures.directoryWithLauncher()
        let tool = try SessionsTool(directory: ForwardingSessionDirectory(backing: backing))

        let forks = try await Fixtures.asCaller(in: backing) { callerID in
            try backing.startUserTurn(of: callerID)
            _ = try await tool.call(arguments: Fixtures.payload(Self.forkOp))
            return try await Self.forks(of: callerID, in: backing)
        }

        #expect(forks.count == 1)
    }

    @Test("the tool description names fork session")
    func theToolDescriptionNamesForkSession() throws {
        let tool = try SessionsTool(directory: InMemorySessionDirectory())

        #expect(tool.description.contains(Self.forkOp))
    }

    @Test("the code-mode verbs of the tool include forkSession")
    func theCodeModeVerbsIncludeForkSession() throws {
        let tool = try SessionsTool(directory: InMemorySessionDirectory())

        #expect(tool.operationDescriptors.contains { $0.opString == Self.forkOp })
    }

    // MARK: - forkSession

    @Test("forkSession gives a new session of the kind FORK whose parent is the source")
    func forkSessionGivesAForkWithTheSourceAsParent() async throws {
        let directory = Fixtures.directoryWithLauncher()
        let source = Fixtures.summary()
        directory.register(source)

        let reply = try await GraphQLReply.run(
            "mutation { forkSession(input: {id: \"\(source.id.ulidString)\"}) { kind parent { id } } }",
            viewer: Self.deviceViewer, on: SessionsGraph.endpoint(of: directory))

        let fork = try reply.object("forkSession")
        #expect(fork["kind"] as? String == Self.forkKind)
        #expect((fork["parent"] as? [String: Any])?["id"] as? String == source.id.ulidString)
    }

    @Test("forkSession forks the source at its last completed turn with the message as the first prompt")
    func forkSessionForksAtTheLastCompletedTurn() async throws {
        let directory = Fixtures.directoryWithLauncher()
        let source = Fixtures.summary()
        directory.register(source)

        _ = try await GraphQLReply.run(
            "mutation { forkSession(input: {id: \"\(source.id.ulidString)\", message: \"\(Self.firstPrompt)\"}) "
                + "{ id } }", viewer: Self.deviceViewer, on: SessionsGraph.endpoint(of: directory))

        let fork = try #require(try await Self.forks(of: source.id, in: directory).first)
        let request = try #require(directory.forkRequest(of: fork.id))
        #expect(request.cut == .lastCompletedTurn)
        #expect(request.firstPrompt == Self.firstPrompt)
    }

    @Test("forkSession from a device opens a tab only for that client")
    func forkSessionFromADeviceNamesTheClient() async throws {
        let directory = Fixtures.directoryWithLauncher()
        let source = Fixtures.summary()
        directory.register(source)

        _ = try await GraphQLReply.run(
            "mutation { forkSession(input: {id: \"\(source.id.ulidString)\"}) { id } }", viewer: Self.deviceViewer,
            on: SessionsGraph.endpoint(of: directory))

        let fork = try #require(try await Self.forks(of: source.id, in: directory).first)
        #expect(directory.forkRequest(of: fork.id)?.requestedByClient == Self.deviceViewer.clientId)
    }
}
