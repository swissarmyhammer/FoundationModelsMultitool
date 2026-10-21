// `SessionsGraphMutationTests` — the behavioral suite of the mutations of the
// `sessions` GraphQL endpoint (MT-10, task `^af25em5`).
//
// Each case runs its mutations on its own `InMemorySessionDirectory`, with a
// fixed clock, and reads the directory after the call. The parity cases run
// each tool op and its mutation on two fresh directories that hold the same
// sessions, and compare the two directories after the call. No case waits.

import Foundation
import FoundationModels
import FoundationModelsExtras
import GraphQL
import Testing
import ULID

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Behavioral tests for the mutations of the `sessions` GraphQL endpoint: the
/// parity of each mutation with its tool op, the sender of each viewer kind,
/// the tab rule of a start, the visibility rule of an external client, the
/// refusals, and the aliases.
@Suite("SessionsGraphMutationTests", .ownsTemporaryDirectories)
struct SessionsGraphMutationTests {

    // MARK: - Constants

    /// The shared fixtures of the `sessions` tool tests.
    private typealias Fixtures = SessionsToolFixtures

    /// The ID of a device of the user.
    private static let deviceClientId = "client-device"

    /// The ID of a client that is not a device of the user.
    private static let externalClientId = "client-external"

    /// The folder that a start names in its `cwd`.
    private static let namedFolder = URL(fileURLWithPath: "/work/other")

    /// An agent id near ``SessionsToolFixtures/agentID``, which the launcher
    /// does not know.
    private static let misspelledAgent = "codr"

    /// The first message of each start.
    private static let firstMessage = "Review the parser and report back."

    /// The text of the message that the target of a scene sends to the
    /// caller, and of each send.
    private static let messageText = "The build is green again."

    /// The text of each reply.
    private static let replyText = "Thanks, I will look at it."

    /// A tag that the target of a scene has, and that a tag case adds.
    private static let reviewTag = "review"

    /// A second tag that the target of a scene has, which an untag case
    /// removes.
    private static let keptTag = "api"

    /// The title of the rename and the start cases.
    private static let title = "Parser review"

    /// A text that is not a valid tag.
    private static let invalidTag = "not a tag!"

    /// A text that holds only space.
    private static let blank = "  "

    /// A text that is no id and no message address.
    private static let notAnID = "nowhere"

    /// A relative folder.
    private static let relativeFolder = "work/other"

    /// The code of the toolkit for a session or a message that the endpoint
    /// does not hold, or that the viewer cannot see.
    private static let notFound = "NOT_FOUND"

    /// A device of the user, which owns no session.
    private static let deviceViewer = GraphQLViewer(clientId: deviceClientId, trust: .userDevice)

    // MARK: - Scenes

    /// The sessions and the messages of one case, staged the same way in
    /// each directory. Only the message ids differ from one directory to the
    /// other.
    struct Scene: Sendable {
        /// The caller session: the session of the agent.
        let caller: ULID

        /// An idle root session with the tags ``reviewTag`` and ``keptTag``.
        let target: ULID

        /// An archived session.
        let archived: ULID

        /// The message that ``target`` sent to ``caller``.
        let original: MailID

        /// The message that the user sent to ``caller``.
        let fromUser: MailID
    }

    /// Stages a scene in `directory`, whose caller session is registered.
    ///
    /// - Parameters:
    ///   - target: The id of the target session.
    ///   - archived: The id of the archived session.
    ///   - caller: The caller session.
    ///   - directory: The directory.
    /// - Returns: The scene.
    /// - Throws: What the directory throws, or an error when a send makes no
    ///   message.
    private static func stage(
        target: ULID, archived: ULID, caller: ULID, in directory: InMemorySessionDirectory
    ) async throws -> Scene {
        directory.register(Fixtures.summary(id: target, tags: [reviewTag, keptTag]))
        directory.register(Fixtures.summary(id: archived))
        _ = try await directory.archive(archived, by: .user(clientID: deviceClientId))
        try directory.startUserTurn(of: target)
        let original = try await deliver(
            OutgoingSessionMessage(from: .session(target), to: .session(caller), text: messageText), in: directory)
        try directory.finishTurn(of: target, lastSummary: nil)
        let fromUser = try await deliver(
            OutgoingSessionMessage(from: .user(clientID: deviceClientId), to: .session(caller), text: messageText),
            in: directory)
        return Scene(caller: caller, target: target, archived: archived, original: original, fromUser: fromUser)
    }

    /// Sends one message to one session.
    ///
    /// - Parameters:
    ///   - message: The message.
    ///   - directory: The directory.
    /// - Returns: The id of the message.
    /// - Throws: What the directory throws, or an error when the send made
    ///   no message.
    private static func deliver(
        _ message: OutgoingSessionMessage, in directory: InMemorySessionDirectory
    ) async throws -> MailID {
        try #require(try await directory.send(message).first?.messageID)
    }

    /// Runs `body` as the caller, after it stages one scene in each
    /// directory, with the same session ids in each.
    ///
    /// - Parameters:
    ///   - directories: The directories.
    ///   - body: The work, given the scene of each directory, in order.
    /// - Returns: What `body` returned.
    /// - Throws: What the staging or `body` throws.
    private static func inScenes<Result>(
        _ directories: [InMemorySessionDirectory], _ body: ([Scene]) async throws -> Result
    ) async throws -> Result {
        let target = ULID()
        let archived = ULID()
        return try await withOuterRunContext { context in
            let scenes = try await directories.asyncMap { directory in
                directory.register(Fixtures.summary(id: context.sessionID))
                return try await stage(target: target, archived: archived, caller: context.sessionID, in: directory)
            }
            return try await ToolContext.$current.withValue(context) { try await body(scenes) }
        }
    }

    /// Runs one document on the endpoint of `directory`.
    ///
    /// - Parameters:
    ///   - document: The document.
    ///   - viewer: The client of the call, or `nil` for the agent.
    ///   - directory: The directory.
    /// - Returns: The response.
    /// - Throws: What the endpoint throws, or an error when the response is
    ///   not a JSON object.
    private static func run(
        _ document: String, viewer: GraphQLViewer? = nil, on directory: InMemorySessionDirectory
    ) async throws -> GraphQLReply {
        try GraphQLReply(
            json: await SessionsGraph.endpoint(of: directory).execute(
                query: document, variables: [:], operationName: nil, viewer: viewer))
    }

    /// Runs one op of the `sessions` tool on `directory`.
    ///
    /// - Parameters:
    ///   - payload: The payload of the op.
    ///   - directory: The directory.
    /// - Returns: The answer of the tool.
    /// - Throws: What the tool throws.
    private static func callTool(_ payload: GeneratedContent, on directory: InMemorySessionDirectory) async throws
        -> String
    {
        try await SessionsTool(directory: directory).call(arguments: payload)
    }

    /// The facts of a directory that a change can reach, one line for each
    /// session, sorted, with each session id that is not in `known` written
    /// as `new`, and each message id left out, so two directories compare.
    ///
    /// - Parameters:
    ///   - directory: The directory.
    ///   - known: The session ids that both directories hold.
    /// - Returns: The lines.
    /// - Throws: What the directory throws.
    private static func facts(of directory: InMemorySessionDirectory, known: Set<ULID>) async throws -> [String] {
        let name: (ULID?) -> String = { id in id.map { known.contains($0) ? $0.ulidString : "new" } ?? "none" }
        let summaries = try await directory.sessions(matching: SessionQuery(includesRecorded: true, limit: .max))
        return try await summaries.asyncMap { summary in
            try await factLine(of: summary, in: directory, naming: name)
        }
        .sorted()
    }

    /// The facts of one session that a change can reach, on one line, with
    /// each session id written by `name` and each message id left out.
    ///
    /// - Parameters:
    ///   - summary: The session.
    ///   - directory: The directory, for the inbox of the session.
    ///   - name: Writes a session id, or `nil`.
    /// - Returns: The line.
    /// - Throws: What the directory throws.
    private static func factLine(
        of summary: SessionSummary, in directory: InMemorySessionDirectory, naming name: (ULID?) -> String
    ) async throws -> String {
        let inbox = try await directory.inbox(of: summary.id, markRead: false).map { message in
            let sender: String =
                switch message.from {
                case .session(let id): name(id)
                case .user(let clientID): "user \(clientID)"
                }
            return "\(sender) \(message.text) reply \(message.inReplyTo != nil) depth \(message.chainDepth)"
        }
        return "\(name(summary.id)) \(summary.agentID) \(summary.workingDirectory.path) \(summary.title ?? "-") "
            + "\(summary.tags.sorted()) \(summary.kind) \(summary.state) \(summary.origin) "
            + "parent \(name(summary.parentID)) startedBy \(name(summary.startedBy)) live \(summary.isLive) "
            + "inbox \(inbox)"
    }

    /// The `started` event of one session in a stream.
    ///
    /// - Parameters:
    ///   - id: The id of the session, as the endpoint gives it.
    ///   - events: The stream.
    /// - Returns: The summary and the requesting client of the event, or
    ///   `nil` when the stream ends with none.
    private static func start(
        of id: String?, in events: AsyncStream<SessionDirectoryEvent>
    ) async -> (summary: SessionSummary, requestedByClient: String?)? {
        for await event in events {
            if case .started(let summary, let requestedByClient) = event, summary.id.ulidString == id {
                return (summary, requestedByClient)
            }
        }
        return nil
    }

    /// The input object of a start of ``firstMessage`` by
    /// ``SessionsToolFixtures/agentID``, in GraphQL.
    private static let startInput = "{agentId: \"\(Fixtures.agentID)\", message: \"\(firstMessage)\"}"

    // MARK: - Parity of each op and its mutation

    /// One tool op and its mutation, which do the same change.
    struct ParityCase: Sendable, CustomTestStringConvertible {
        /// The op string of the tool op.
        let op: String

        /// The payload of the tool op in a scene.
        let payload: @Sendable (Scene) -> GeneratedContent

        /// The mutation document in a scene.
        let mutation: @Sendable (Scene) -> String

        /// The name of the case in the test report.
        var testDescription: String { op }
    }

    /// One case for each tool op that changes the directory.
    static let parityCases: [ParityCase] = [
        ParityCase(
            op: "start session",
            payload: { _ in
                Fixtures.payload(
                    "start session",
                    [
                        ("agent", Fixtures.agentID), ("cwd", namedFolder.path), ("message", firstMessage),
                        ("tags", [reviewTag]), ("title", title),
                    ])
            },
            mutation: { _ in
                "mutation { startSession(input: {agentId: \"\(Fixtures.agentID)\", cwd: \"\(namedFolder.path)\", "
                    + "message: \"\(firstMessage)\", tags: [\"\(reviewTag)\"], title: \"\(title)\"}) { id } }"
            }),
        ParityCase(
            op: "tag session",
            payload: { scene in
                Fixtures.payload("tag session", [("id", scene.caller.ulidString), ("tags", [reviewTag])])
            },
            mutation: { scene in
                "mutation { tagSession(input: {id: \"\(scene.caller.ulidString)\", tags: [\"\(reviewTag)\"]}) { id } }"
            }),
        ParityCase(
            op: "untag session",
            payload: { scene in
                Fixtures.payload("untag session", [("id", scene.target.ulidString), ("tags", [keptTag])])
            },
            mutation: { scene in
                "mutation { untagSession(input: {id: \"\(scene.target.ulidString)\", tags: [\"\(keptTag)\"]}) { id } }"
            }),
        ParityCase(
            op: "rename session",
            payload: { scene in
                Fixtures.payload("rename session", [("id", scene.target.ulidString), ("title", title)])
            },
            mutation: { scene in
                "mutation { renameSession(input: {id: \"\(scene.target.ulidString)\", title: \"\(title)\"}) { id } }"
            }),
        ParityCase(
            op: "archive session",
            payload: { scene in Fixtures.payload("archive session", [("id", scene.target.ulidString)]) },
            mutation: { scene in "mutation { archiveSession(input: {id: \"\(scene.target.ulidString)\"}) { id } }" }),
        ParityCase(
            op: "send message",
            payload: { scene in
                Fixtures.payload("send message", [("to", scene.target.ulidString), ("message", messageText)])
            },
            mutation: { scene in
                "mutation { sendMessage(input: {to: \"\(scene.target.ulidString)\", message: \"\(messageText)\"}) "
                    + "{ outcome } }"
            }),
        ParityCase(
            op: "reply message",
            payload: { scene in
                Fixtures.payload("reply message", [("inReplyTo", "\(scene.original)"), ("message", replyText)])
            },
            mutation: { scene in
                "mutation { replyMessage(input: {sessionId: \"\(scene.caller.ulidString)\", "
                    + "inReplyTo: \"\(scene.original)\", message: \"\(replyText)\"}) { outcome } }"
            }),
    ]

    /// The tool op and its mutation, called by the agent, change two fresh
    /// directories that hold the same sessions the same way.
    @Test("each mutation changes the directory as its tool op does", arguments: parityCases)
    func eachMutationChangesTheDirectoryAsItsOpDoes(_ parity: ParityCase) async throws {
        let byTool = Fixtures.directoryWithLauncher()
        let byGraph = Fixtures.directoryWithLauncher()

        let (reply, staged, known) = try await Self.inScenes([byTool, byGraph]) { scenes in
            let known: Set<ULID> = [scenes[0].caller, scenes[0].target, scenes[0].archived]
            let staged = try await Self.facts(of: byTool, known: known)
            _ = try await Self.callTool(parity.payload(scenes[0]), on: byTool)
            let reply = try await Self.run(parity.mutation(scenes[1]), on: byGraph)
            return (reply, staged, known)
        }
        let changedByTool = try await Self.facts(of: byTool, known: known)

        #expect(reply.codes.isEmpty, "errors: \(reply.messages)")
        #expect(changedByTool != staged)
        #expect(try await Self.facts(of: byGraph, known: known) == changedByTool)
    }

    // MARK: - Refusals

    /// One call that the tool op and its mutation refuse with the same text.
    struct RefusalCase: Sendable, CustomTestStringConvertible {
        /// The code that the endpoint gives.
        let code: String

        /// What the call does wrong.
        let fault: String

        /// The payload of the tool op in a scene.
        let payload: @Sendable (Scene) -> GeneratedContent

        /// The mutation document in a scene.
        let mutation: @Sendable (Scene) -> String

        /// The name of the case in the test report.
        var testDescription: String { "\(code): \(fault)" }
    }

    /// One case for each refusal that the tool and the endpoint share.
    static let refusalCases: [RefusalCase] = [
        RefusalCase(
            code: "BLANK_TEXT", fault: "a rename to a blank title",
            payload: { scene in
                Fixtures.payload("rename session", [("id", scene.target.ulidString), ("title", blank)])
            },
            mutation: { scene in
                "mutation { renameSession(input: {id: \"\(scene.target.ulidString)\", title: \"\(blank)\"}) { id } }"
            }),
        RefusalCase(
            code: "INVALID_TAG", fault: "a tag that is not valid",
            payload: { scene in
                Fixtures.payload("tag session", [("id", scene.target.ulidString), ("tags", [invalidTag])])
            },
            mutation: { scene in
                "mutation { tagSession(input: {id: \"\(scene.target.ulidString)\", tags: [\"\(invalidTag)\"]}) { id } }"
            }),
        RefusalCase(
            code: "MISSING_TAGS", fault: "a tag call with no tag",
            payload: { scene in Fixtures.payload("tag session", [("id", scene.target.ulidString), ("tags", [blank])]) },
            mutation: { scene in
                "mutation { tagSession(input: {id: \"\(scene.target.ulidString)\", tags: [\"\(blank)\"]}) { id } }"
            }),
        RefusalCase(
            code: "INVALID_SESSION_ID", fault: "an id that is not a session id",
            payload: { _ in Fixtures.payload("tag session", [("id", notAnID), ("tags", [reviewTag])]) },
            mutation: { _ in "mutation { tagSession(input: {id: \"\(notAnID)\", tags: [\"\(reviewTag)\"]}) { id } }" }),
        RefusalCase(
            code: "INVALID_ADDRESS", fault: "an address in no form",
            payload: { _ in Fixtures.payload("send message", [("to", notAnID), ("message", messageText)]) },
            mutation: { _ in
                "mutation { sendMessage(input: {to: \"\(notAnID)\", message: \"\(messageText)\"}) { outcome } }"
            }),
        RefusalCase(
            code: "UNKNOWN_AGENT", fault: "a start of an agent that the launcher does not know",
            payload: { _ in
                Fixtures.payload("start session", [("agent", misspelledAgent), ("message", firstMessage)])
            },
            mutation: { _ in
                "mutation { startSession(input: {agentId: \"\(misspelledAgent)\", message: \"\(firstMessage)\"}) "
                    + "{ id } }"
            }),
        RefusalCase(
            code: "INVALID_FOLDER", fault: "a start in a relative folder",
            payload: { _ in Fixtures.payload("start session", [("cwd", relativeFolder), ("message", firstMessage)]) },
            mutation: { _ in
                "mutation { startSession(input: {cwd: \"\(relativeFolder)\", message: \"\(firstMessage)\"}) { id } }"
            }),
        RefusalCase(
            code: "ARCHIVED_SESSION", fault: "an archive of an archived session",
            payload: { scene in Fixtures.payload("archive session", [("id", scene.archived.ulidString)]) },
            mutation: { scene in "mutation { archiveSession(input: {id: \"\(scene.archived.ulidString)\"}) { id } }" }),
        RefusalCase(
            code: "USER_MESSAGE", fault: "a reply to a message from the user",
            payload: { scene in
                Fixtures.payload("reply message", [("inReplyTo", "\(scene.fromUser)"), ("message", replyText)])
            },
            mutation: { scene in
                "mutation { replyMessage(input: {sessionId: \"\(scene.caller.ulidString)\", "
                    + "inReplyTo: \"\(scene.fromUser)\", message: \"\(replyText)\"}) { outcome } }"
            }),
        RefusalCase(
            code: "INVALID_MESSAGE_ID", fault: "a reply to a text that is not a message id",
            payload: { _ in Fixtures.payload("reply message", [("inReplyTo", notAnID), ("message", replyText)]) },
            mutation: { scene in
                "mutation { replyMessage(input: {sessionId: \"\(scene.caller.ulidString)\", inReplyTo: \"\(notAnID)\", "
                    + "message: \"\(replyText)\"}) { outcome } }"
            }),
    ]

    /// The mutation refuses what the tool op refuses, with the corrective of
    /// the tool as the message of its coded error, and changes nothing.
    @Test("each mutation refuses with the corrective of its tool op", arguments: refusalCases)
    func eachMutationRefusesWithTheCorrectiveOfItsOp(_ refusal: RefusalCase) async throws {
        let directory = Fixtures.directoryWithLauncher()

        let (answer, reply, staged, known) = try await Self.inScenes([directory]) { scenes in
            let known: Set<ULID> = [scenes[0].caller, scenes[0].target, scenes[0].archived]
            let staged = try await Self.facts(of: directory, known: known)
            let answer = try await Self.callTool(refusal.payload(scenes[0]), on: directory)
            let reply = try await Self.run(refusal.mutation(scenes[0]), on: directory)
            return (answer, reply, staged, known)
        }

        #expect(reply.codes == [refusal.code])
        #expect(reply.messages == [answer])
        #expect(try await Self.facts(of: directory, known: known) == staged)
    }

    /// The agent, a call with no viewer, acts as its own session, so a call
    /// with no caller session gets `MISSING_CALLER` with the corrective of
    /// the tool, and starts nothing.
    @Test("a start by the agent with no caller session gives MISSING_CALLER with the corrective of the tool")
    func aStartWithNoCallerGivesMissingCaller() async throws {
        let directory = Fixtures.directoryWithLauncher()

        let answer = try await Self.callTool(
            Fixtures.payload("start session", [("message", Self.firstMessage)]), on: directory)
        let reply = try await Self.run("mutation { startSession(input: \(Self.startInput)) { id } }", on: directory)

        #expect(reply.codes == ["MISSING_CALLER"])
        #expect(reply.messages == [answer])
        #expect(try await directory.sessions(matching: SessionQuery(includesRecorded: true)).isEmpty)
    }

    /// A mutation by the agent on an id that no session has gives the
    /// `NOT_FOUND` of the toolkit.
    @Test("a mutation on an unknown session gives NOT_FOUND")
    func anUnknownSessionGivesNotFound() async throws {
        let directory = Fixtures.directoryWithLauncher()

        let reply = try await Self.inScenes([directory]) { _ in
            try await Self.run(
                "mutation { renameSession(input: {id: \"\(ULID().ulidString)\", title: \"\(Self.title)\"}) { id } }",
                on: directory)
        }

        #expect(reply.codes == [Self.notFound])
    }

    // MARK: - Who acts

    /// A start from a device of the user is a start of the user on that
    /// client: the origin is `CLIENT`, no session started it, and the
    /// `started` event names that client, so only that client opens a tab
    /// (D90).
    @Test("a start from a device opens a tab only for that client")
    func aDeviceStartOpensATabOnlyForThatClient() async throws {
        let directory = Fixtures.directoryWithLauncher()
        let events = directory.events()

        let reply = try await Self.run(
            "mutation { startSession(input: \(Self.startInput)) { id origin startedBy { id } } }",
            viewer: Self.deviceViewer, on: directory)
        directory.finishEventStreams()
        let session = try reply.object("startSession")
        let started = try #require(await Self.start(of: session["id"] as? String, in: events))

        #expect(session["origin"] as? String == "CLIENT")
        #expect(session["startedBy"] is NSNull)
        #expect(started.requestedByClient == Self.deviceClientId)
        #expect(started.summary.workingDirectory.path == Fixtures.launcherFolder.path)
    }

    /// A start by the agent is a start of a model: the origin is `TOOL`, the
    /// caller started it, and the `started` event names no client, so no
    /// client opens a tab (D90).
    @Test("a start by the agent opens no tab")
    func anAgentStartOpensNoTab() async throws {
        let directory = Fixtures.directoryWithLauncher()
        let events = directory.events()

        let (reply, callerID) = try await Fixtures.asCaller(in: directory) { callerID in
            let document = "mutation { startSession(input: \(Self.startInput)) { id origin } }"
            return (try await Self.run(document, on: directory), callerID)
        }
        directory.finishEventStreams()
        let session = try reply.object("startSession")
        let started = try #require(await Self.start(of: session["id"] as? String, in: events))

        #expect(session["origin"] as? String == "TOOL")
        #expect(started.summary.startedBy == callerID)
        #expect(started.requestedByClient == nil)
    }

    /// A send from a device of the user is input of the user: the target gets
    /// the message from the user on that client, at depth 1.
    @Test("a send from a device comes from the user on that client")
    func aDeviceSendComesFromTheUser() async throws {
        let directory = Fixtures.directoryWithLauncher()
        let target = Fixtures.summary()
        directory.register(target)

        let reply = try await Self.run(
            "mutation { sendMessage(input: {to: \"\(target.id.ulidString)\", message: \"\(Self.messageText)\"}) "
                + "{ outcome target { id } } }",
            viewer: Self.deviceViewer, on: directory)
        let inbox = try await directory.inbox(of: target.id, markRead: false)

        let receipts = try reply.list("sendMessage")
        #expect(receipts.map { $0["outcome"] as? String } == ["DELIVERED"])
        #expect(receipts.map { ($0["target"] as? [String: Any])?["id"] as? String } == [target.id.ulidString])
        #expect(inbox.map(\.from) == [.user(clientID: Self.deviceClientId)])
        #expect(inbox.map(\.text) == [Self.messageText])
    }

    /// A reply from a device of the user answers a message that a session got:
    /// the reply goes to the sender of that message, from the user, with
    /// the id of the message that it answers.
    @Test("a reply from a device goes to the sender of the message, from the user")
    func aDeviceReplyGoesToTheSender() async throws {
        let directory = Fixtures.directoryWithLauncher()
        let sender = Fixtures.summary()
        let recipient = Fixtures.summary()
        directory.register(sender)
        directory.register(recipient)
        try directory.startUserTurn(of: sender.id)
        let original = try await Self.deliver(
            OutgoingSessionMessage(from: .session(sender.id), to: .session(recipient.id), text: Self.messageText),
            in: directory)
        try directory.finishTurn(of: sender.id, lastSummary: nil)

        let reply = try await Self.run(
            "mutation { replyMessage(input: {sessionId: \"\(recipient.id.ulidString)\", inReplyTo: \"\(original)\", "
                + "message: \"\(Self.replyText)\"}) { outcome } }",
            viewer: Self.deviceViewer, on: directory)
        let inbox = try await directory.inbox(of: sender.id, markRead: false)

        #expect(reply.codes.isEmpty, "errors: \(reply.messages)")
        #expect(inbox.map(\.from) == [.user(clientID: Self.deviceClientId)])
        #expect(inbox.map(\.inReplyTo) == [original])
        #expect(inbox.map(\.text) == [Self.replyText])
    }

    // MARK: - An external client

    /// The sessions of the external cases: a session that the external client
    /// owns, a stranger with no link to it, and a message from the stranger
    /// to each.
    struct ExternalScene: Sendable {
        /// The session that the external client owns.
        let owned: ULID

        /// A session with no link to ``owned``.
        let stranger: ULID

        /// The message that ``stranger`` sent to ``owned``.
        let toOwned: MailID

        /// The message that ``owned`` sent to ``stranger``.
        let toStranger: MailID

        /// A subagent of ``owned``: the external client sees it, but does
        /// not own it.
        let subagent: ULID

        /// The message that ``subagent`` sent to ``owned``.
        let fromSubagent: MailID

        /// The external client that owns ``owned``.
        var viewer: GraphQLViewer {
            GraphQLViewer(clientId: externalClientId, trust: .external, ownedSessions: [owned.ulidString])
        }
    }

    /// Stages an external scene in `directory`.
    ///
    /// - Parameter directory: The directory.
    /// - Returns: The scene.
    /// - Throws: What the directory throws.
    private static func stageExternal(in directory: InMemorySessionDirectory) async throws -> ExternalScene {
        let owned = Fixtures.summary(tags: [keptTag])
        let stranger = Fixtures.summary(tags: [keptTag])
        let subagent = Fixtures.summary(tags: [keptTag], kind: .subagent, parentID: owned.id)
        directory.register(owned)
        directory.register(stranger)
        directory.register(subagent)
        try directory.startUserTurn(of: subagent.id)
        let fromSubagent = try await deliver(
            OutgoingSessionMessage(from: .session(subagent.id), to: .session(owned.id), text: messageText),
            in: directory)
        try directory.finishTurn(of: subagent.id, lastSummary: nil)
        try directory.finishTurn(of: owned.id, lastSummary: nil)
        try directory.startUserTurn(of: stranger.id)
        let toOwned = try await deliver(
            OutgoingSessionMessage(from: .session(stranger.id), to: .session(owned.id), text: messageText),
            in: directory)
        try directory.finishTurn(of: stranger.id, lastSummary: nil)
        try directory.startUserTurn(of: owned.id)
        let toStranger = try await deliver(
            OutgoingSessionMessage(from: .session(owned.id), to: .session(stranger.id), text: messageText),
            in: directory)
        try directory.finishTurn(of: owned.id, lastSummary: nil)
        return ExternalScene(
            owned: owned.id, stranger: stranger.id, toOwned: toOwned, toStranger: toStranger, subagent: subagent.id,
            fromSubagent: fromSubagent)
    }

    /// One mutation of an external client that reaches a session it cannot
    /// see.
    struct HiddenCase: Sendable, CustomTestStringConvertible {
        /// What the mutation does.
        let action: String

        /// The mutation document in a scene.
        let mutation: @Sendable (ExternalScene) -> String

        /// The name of the case in the test report.
        var testDescription: String { action }
    }

    /// One case for each mutation that names a session.
    static let hiddenCases: [HiddenCase] = [
        HiddenCase(action: "tag a hidden session") { scene in
            "mutation { tagSession(input: {id: \"\(scene.stranger.ulidString)\", tags: [\"\(reviewTag)\"]}) { id } }"
        },
        HiddenCase(action: "untag a hidden session") { scene in
            "mutation { untagSession(input: {id: \"\(scene.stranger.ulidString)\", tags: [\"\(keptTag)\"]}) { id } }"
        },
        HiddenCase(action: "rename a hidden session") { scene in
            "mutation { renameSession(input: {id: \"\(scene.stranger.ulidString)\", title: \"\(title)\"}) { id } }"
        },
        HiddenCase(action: "archive a hidden session") { scene in
            "mutation { archiveSession(input: {id: \"\(scene.stranger.ulidString)\"}) { id } }"
        },
        HiddenCase(action: "send to a hidden session") { scene in
            "mutation { sendMessage(input: {to: \"\(scene.stranger.ulidString)\", message: \"\(messageText)\"}) "
                + "{ outcome } }"
        },
        HiddenCase(action: "reply for a hidden session") { scene in
            "mutation { replyMessage(input: {sessionId: \"\(scene.stranger.ulidString)\", "
                + "inReplyTo: \"\(scene.toStranger)\", message: \"\(replyText)\"}) { outcome } }"
        },
        HiddenCase(action: "reply to a hidden sender") { scene in
            "mutation { replyMessage(input: {sessionId: \"\(scene.owned.ulidString)\", "
                + "inReplyTo: \"\(scene.toOwned)\", message: \"\(replyText)\"}) { outcome } }"
        },
    ]

    /// An external client gets `NOT_FOUND` for a session that it cannot see,
    /// so the response does not tell that the session exists, and the
    /// mutation changes nothing.
    @Test("an external viewer gets NOT_FOUND for a session it cannot see", arguments: hiddenCases)
    func anExternalViewerGetsNotFoundForAHiddenSession(_ hidden: HiddenCase) async throws {
        let directory = Fixtures.directoryWithLauncher()
        let scene = try await Self.stageExternal(in: directory)
        let known: Set<ULID> = [scene.owned, scene.stranger]
        let staged = try await Self.facts(of: directory, known: known)

        let reply = try await Self.run(hidden.mutation(scene), viewer: scene.viewer, on: directory)

        #expect(reply.codes == [Self.notFound])
        #expect(try await Self.facts(of: directory, known: known) == staged)
    }

    /// An external client changes a session that it can see.
    @Test("an external viewer tags a session that it owns")
    func anExternalViewerTagsItsSession() async throws {
        let directory = Fixtures.directoryWithLauncher()
        let scene = try await Self.stageExternal(in: directory)

        let reply = try await Self.run(
            "mutation { tagSession(input: {id: \"\(scene.owned.ulidString)\", tags: [\"\(Self.reviewTag)\"]}) "
                + "{ tags } }",
            viewer: scene.viewer, on: directory)

        #expect(try reply.object("tagSession")["tags"] as? [String] == [Self.keptTag, Self.reviewTag])
    }

    /// One case for each change of a session that the external client sees
    /// but does not own: the subagent of its session (section 11.3).
    static let unownedChanges: [HiddenCase] = [
        HiddenCase(action: "tag a subagent of its session") { scene in
            "mutation { tagSession(input: {id: \"\(scene.subagent.ulidString)\", tags: [\"\(reviewTag)\"]}) { id } }"
        },
        HiddenCase(action: "untag a subagent of its session") { scene in
            "mutation { untagSession(input: {id: \"\(scene.subagent.ulidString)\", tags: [\"\(keptTag)\"]}) { id } }"
        },
        HiddenCase(action: "rename a subagent of its session") { scene in
            "mutation { renameSession(input: {id: \"\(scene.subagent.ulidString)\", title: \"\(title)\"}) { id } }"
        },
    ]

    /// An external client sees the subagent of its session, but tags,
    /// untags and renames only the sessions that it owns: a session that it
    /// does not own is `NOT_FOUND`, and nothing changes.
    @Test("an external viewer gets NOT_FOUND for a change of a session it sees but does not own", arguments: unownedChanges)
    func anExternalViewerChangesOnlyOwnedSessions(_ unowned: HiddenCase) async throws {
        let directory = Fixtures.directoryWithLauncher()
        let scene = try await Self.stageExternal(in: directory)
        let known: Set<ULID> = [scene.owned, scene.stranger, scene.subagent]
        let staged = try await Self.facts(of: directory, known: known)

        let seen = try await Self.run(
            "{ session(id: \"\(scene.subagent.ulidString)\") { id } }", viewer: scene.viewer, on: directory)
        let reply = try await Self.run(unowned.mutation(scene), viewer: scene.viewer, on: directory)

        #expect(try seen.object("session")["id"] as? String == scene.subagent.ulidString)
        #expect(reply.codes == [Self.notFound])
        #expect(try await Self.facts(of: directory, known: known) == staged)
    }

    /// One case for each message of the external client to a session that
    /// it sees but does not own: the subagent of its session.
    static let unownedMessages: [HiddenCase] = [
        HiddenCase(action: "send to a subagent of its session") { scene in
            "mutation { sendMessage(input: {to: \"\(scene.subagent.ulidString)\", message: \"\(messageText)\"}) "
                + "{ outcome reason target { id } } }"
        },
        HiddenCase(action: "reply to a subagent of its session") { scene in
            "mutation { sendMessage: replyMessage(input: {sessionId: \"\(scene.owned.ulidString)\", "
                + "inReplyTo: \"\(scene.fromSubagent)\", message: \"\(replyText)\"}) { outcome reason target { id } } }"
        },
    ]

    /// An external client sends and replies only to the sessions that it
    /// owns: a message to a session that it sees but does not own gives a
    /// refused receipt, and no message goes.
    @Test("an external viewer's message to a session it sees but does not own is refused", arguments: unownedMessages)
    func anExternalViewerMessagesOnlyOwnedSessions(_ unowned: HiddenCase) async throws {
        let directory = Fixtures.directoryWithLauncher()
        let scene = try await Self.stageExternal(in: directory)
        let known: Set<ULID> = [scene.owned, scene.stranger, scene.subagent]
        let staged = try await Self.facts(of: directory, known: known)

        let reply = try await Self.run(unowned.mutation(scene), viewer: scene.viewer, on: directory)

        let receipts = try reply.list("sendMessage")
        #expect(reply.codes.isEmpty, "errors: \(reply.messages)")
        #expect(receipts.map { $0["outcome"] as? String } == ["REFUSED"])
        #expect(receipts.map { $0["reason"] as? String } == [SessionsGraphText.notOwnedReason])
        #expect(receipts.map { ($0["target"] as? [String: Any])?["id"] as? String } == [scene.subagent.ulidString])
        #expect(try await Self.facts(of: directory, known: known) == staged)
    }

    /// An external client sends to a session that it owns.
    @Test("an external viewer sends to a session that it owns")
    func anExternalViewerSendsToItsSession() async throws {
        let directory = Fixtures.directoryWithLauncher()
        let scene = try await Self.stageExternal(in: directory)

        let reply = try await Self.run(
            "mutation { sendMessage(input: {to: \"\(scene.owned.ulidString)\", message: \"\(Self.messageText)\"}) "
                + "{ outcome } }",
            viewer: scene.viewer, on: directory)
        let inbox = try await directory.inbox(of: scene.owned, markRead: false)

        #expect(try reply.list("sendMessage").map { $0["outcome"] as? String } == ["DELIVERED"])
        #expect(inbox.last?.from == .user(clientID: Self.externalClientId))
    }

    /// An external client cannot start a session: only a device of the user
    /// starts one (section 11.3). It gets `UNTRUSTED_CLIENT`, and nothing
    /// starts.
    @Test("an external viewer cannot start a session")
    func anExternalViewerCannotStart() async throws {
        let directory = Fixtures.directoryWithLauncher()
        let viewer = GraphQLViewer(clientId: Self.externalClientId, trust: .external)

        let reply = try await Self.run(
            "mutation { startSession(input: \(Self.startInput)) { id } }", viewer: viewer, on: directory)

        #expect(reply.codes == ["UNTRUSTED_CLIENT"])
        #expect(try await directory.sessions(matching: SessionQuery(includesRecorded: true)).isEmpty)
    }

    /// An external client sends only to a session id that it can see: a tag
    /// address could reach sessions that it cannot see, so it gets
    /// `INVALID_ADDRESS`, and no message goes.
    @Test("an external viewer cannot send to a tag")
    func anExternalViewerCannotSendToATag() async throws {
        let directory = Fixtures.directoryWithLauncher()
        let scene = try await Self.stageExternal(in: directory)
        let known: Set<ULID> = [scene.owned, scene.stranger]
        let staged = try await Self.facts(of: directory, known: known)

        let reply = try await Self.run(
            "mutation { sendMessage(input: {to: \"#\(Self.keptTag)\", message: \"\(Self.messageText)\"}) { outcome } }",
            viewer: scene.viewer, on: directory)

        #expect(reply.codes == ["INVALID_ADDRESS"])
        #expect(try await Self.facts(of: directory, known: known) == staged)
    }

    // MARK: - Aliases

    /// One bare verb of session.md section 14 and the mutation it names.
    struct AliasCase: Sendable, CustomTestStringConvertible {
        /// The bare verb.
        let verb: String

        /// The mutation of the schema.
        let mutation: String

        /// The input object of the call in a scene, in GraphQL.
        let input: @Sendable (Scene) -> String

        /// The selection of the call.
        let selection: String

        /// The name of the case in the test report.
        var testDescription: String { "\(verb) → \(mutation)" }
    }

    /// One case for each bare verb.
    static let aliasCases: [AliasCase] = [
        AliasCase(verb: "start", mutation: "startSession", input: { _ in startInput }, selection: "id"),
        AliasCase(
            verb: "tag", mutation: "tagSession",
            input: { scene in "{id: \"\(scene.caller.ulidString)\", tags: [\"\(reviewTag)\"]}" }, selection: "id"),
        AliasCase(
            verb: "untag", mutation: "untagSession",
            input: { scene in "{id: \"\(scene.target.ulidString)\", tags: [\"\(keptTag)\"]}" }, selection: "id"),
        AliasCase(
            verb: "rename", mutation: "renameSession",
            input: { scene in "{id: \"\(scene.target.ulidString)\", title: \"\(title)\"}" }, selection: "id"),
        AliasCase(
            verb: "archive", mutation: "archiveSession", input: { scene in "{id: \"\(scene.target.ulidString)\"}" },
            selection: "id"),
        AliasCase(
            verb: "send", mutation: "sendMessage",
            input: { scene in "{to: \"\(scene.target.ulidString)\", message: \"\(messageText)\"}" },
            selection: "outcome"),
        AliasCase(
            verb: "reply", mutation: "replyMessage",
            input: { scene in
                "{sessionId: \"\(scene.caller.ulidString)\", inReplyTo: \"\(scene.original)\", "
                    + "message: \"\(replyText)\"}"
            },
            selection: "outcome"),
    ]

    /// Each bare verb names its mutation, and the response tells the rewrite
    /// in `extensions.rewrites`.
    @Test("each bare verb works and shows in extensions.rewrites", arguments: aliasCases)
    func eachBareVerbWorks(_ alias: AliasCase) async throws {
        let directory = Fixtures.directoryWithLauncher()

        let reply = try await Self.inScenes([directory]) { scenes in
            try await Self.run(
                "mutation { \(alias.verb)(input: \(alias.input(scenes[0]))) { \(alias.selection) } }", on: directory)
        }

        #expect(reply.codes.isEmpty, "errors: \(reply.messages)")
        #expect(reply.data?[alias.verb] != nil)
        #expect(reply.rewrote(alias.verb, to: alias.mutation))
    }

    /// The input of a start takes the names of the arguments of the tool op:
    /// `agent`, `folder` and `prompt`.
    @Test("the input of startSession takes the aliases of the tool op")
    func theStartInputTakesTheAliasesOfTheOp() async throws {
        let directory = Fixtures.directoryWithLauncher()

        let reply = try await Self.run(
            "mutation { startSession(input: {agent: \"\(Fixtures.agentID)\", folder: \"\(Self.namedFolder.path)\", "
                + "prompt: \"\(Self.firstMessage)\"}) { agentId cwd } }",
            viewer: Self.deviceViewer, on: directory)

        let session = try reply.object("startSession")
        #expect(session["agentId"] as? String == Fixtures.agentID)
        #expect(session["cwd"] as? String == Self.namedFolder.path)
        #expect(reply.rewrote("agent", to: "agentId"))
        #expect(reply.rewrote("folder", to: "cwd"))
        #expect(reply.rewrote("prompt", to: "message"))
    }

    /// The input of a send takes the names of the arguments of the tool op:
    /// `address` and `text`.
    @Test("the input of sendMessage takes the aliases of the tool op")
    func theSendInputTakesTheAliasesOfTheOp() async throws {
        let directory = Fixtures.directoryWithLauncher()
        let target = Fixtures.summary()
        directory.register(target)

        let reply = try await Self.run(
            "mutation { sendMessage(input: {address: \"\(target.id.ulidString)\", text: \"\(Self.messageText)\"}) "
                + "{ outcome } }",
            viewer: Self.deviceViewer, on: directory)

        #expect(try reply.list("sendMessage").map { $0["outcome"] as? String } == ["DELIVERED"])
        #expect(reply.rewrote("address", to: "to"))
        #expect(reply.rewrote("text", to: "message"))
    }
}
