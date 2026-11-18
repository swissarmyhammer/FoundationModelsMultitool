import Foundation
import FoundationModels
import FoundationModelsExtras
import Testing
import ULID

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Coverage for the message operations of ``SessionsTool`` — `send message`
/// and `reply message` — over an `InMemorySessionDirectory`.
///
/// Each case reads the inbox of the target in the directory after the call, so
/// it proves the delivery and not only the text of the answer. The snippet
/// case calls each verb as `tools.sessions.<verb>` in one `runCode` snippet.
@Suite("SessionsToolMessageTests", .ownsTemporaryDirectories)
struct SessionsToolMessageTests {
    // MARK: - Shared test constants

    /// The shared fixtures of the `sessions` tool tests.
    private typealias Fixtures = SessionsToolFixtures

    /// The reason of a refusal of the test double.
    private typealias Refusal = InMemorySessionDirectory.Refusal

    /// A folder other than ``SessionsToolFixtures/workingFolder``.
    private static let otherFolder = URL(fileURLWithPath: "/work/other")

    /// The path under the home folder of the `~/path` case, with no `~`.
    private static let homeRelativePath = "work/home-project"

    /// An agent id with a capital letter, other than
    /// ``SessionsToolFixtures/agentID``: the folder name of an agent, which
    /// keeps its letter case.
    private static let reviewerAgent = "Reviewer"

    /// A tag of the tag cases.
    private static let reviewTag = "review"

    /// The text of each message the tool sends.
    private static let messageText = "Please review the parser."

    /// The text of each reply.
    private static let replyText = "The parser looks right."

    /// The text of each message that the case sends to the caller first.
    private static let questionText = "Does the parser handle comments?"

    /// A text that names no address form.
    private static let formlessAddress = "somewhere"

    /// A text that is not a ULID.
    private static let malformedID = "not-a-message"

    /// The client id of a message from the user.
    private static let userClientID = "test-client"

    /// A sends-per-turn limit that refuses each send of a session.
    private static let noSendsPerTurn = 0

    /// The outcome word of a delivered message in the answer.
    private static let deliveredWord = "Delivered"

    /// The outcome word of a queued message in the answer.
    private static let queuedWord = "Queued"

    /// The outcome word of a message that waits in the inbox of a session
    /// that is not live, in the answer.
    private static let sentWord = "Sent to"

    /// The words that say the message is not delivered yet, in the answer.
    private static let notDeliveredWords = "written to the inbox of the session and not yet delivered"

    /// The outcome word of a started session in the answer.
    private static let startedWord = "Started"

    /// The sentence of an answer in which no target took the message.
    private static let notSentSentence = "The message was not sent."

    /// The reason that the directory gives for an archived target.
    private static let archivedReason = "archived"

    /// The code-mode verb name that the corrective of an archived target
    /// names.
    private static let startSessionVerb = "startSession"

    /// The code-mode verb name that each unknown-session corrective names.
    private static let listSessionsVerb = "listSessions"

    /// The code-mode verb name that each unknown-message corrective names.
    private static let readInboxVerb = "readInbox"

    /// The words of the corrective of a reply to a message from the user.
    private static let userReplyWords = "from the user"

    /// A session id no session has.
    private static let absentID = ULID()

    /// The title of each session of the slug cases.
    private static let apiTitle = "Fix the API tests"

    /// The slug of ``apiTitle``.
    private static let apiSlug = "fix-the-api-tests"

    /// The name of an agent folder, and the title of a session in the agent
    /// cases: one namespace (D199 (e)).
    private static let travelName = "travel"

    /// The path under the home folder of the `@travel:~/trips` case, with no
    /// `~`.
    private static let tripsRelativePath = "trips"

    /// A name that no session and no agent has.
    private static let nobodyName = "nobody"

    /// The words of the corrective of a name that no session and no agent
    /// has.
    private static let noSessionOrAgentWords = "No session and no agent has the name"

    /// The words of the corrective of an ambiguous reference.
    private static let ambiguousWords = "names more than one session"

    // MARK: - Helpers

    /// Calls `send message` as the caller of the current context.
    ///
    /// - Parameters:
    ///   - address: The `to` text of the call.
    ///   - text: The `message` text of the call.
    ///   - tool: The tool.
    /// - Returns: The answer.
    /// - Throws: What the tool throws.
    private static func sendMessage(
        to address: String, _ text: String = messageText, with tool: SessionsTool
    ) async throws -> String {
        try await tool.call(arguments: Fixtures.payload("send message", [("to", address), ("message", text)]))
    }

    /// Calls `reply message` as the caller of the current context.
    ///
    /// - Parameters:
    ///   - inReplyTo: The `inReplyTo` text of the call.
    ///   - tool: The tool.
    /// - Returns: The answer.
    /// - Throws: What the tool throws.
    private static func replyMessage(to inReplyTo: String, with tool: SessionsTool) async throws -> String {
        try await tool.call(
            arguments: Fixtures.payload("reply message", [("inReplyTo", inReplyTo), ("message", replyText)]))
    }

    /// Calls `send message` to `address` as a caller that the call
    /// registers, and gives the answer and the sessions that the caller
    /// started.
    ///
    /// - Parameters:
    ///   - address: The `to` text of the call.
    ///   - directory: The directory.
    ///   - tool: The tool.
    /// - Returns: The answer, and the sessions that the caller started.
    /// - Throws: What the tool or the directory throws.
    private static func sendAsCaller(
        to address: String, in directory: InMemorySessionDirectory, with tool: SessionsTool
    ) async throws -> (output: String, started: [SessionSummary]) {
        try await Fixtures.asCaller(in: directory) { callerID in
            let output = try await sendMessage(to: address, with: tool)
            return (output, try await directory.sessions(matching: SessionQuery(startedBy: callerID)))
        }
    }

    /// The unread messages to `id`, which stay unread.
    ///
    /// - Parameters:
    ///   - id: The session id.
    ///   - directory: The directory.
    /// - Returns: The messages.
    /// - Throws: What `inbox(of:markRead:)` throws.
    private static func unread(
        to id: ULID, in directory: InMemorySessionDirectory
    ) async throws -> [SessionMessage] {
        try await directory.inbox(of: id, markRead: false)
    }

    /// Sends ``questionText`` from `sender` to `target` through the
    /// directory, and gives the id of the delivered message.
    ///
    /// - Parameters:
    ///   - sender: The sending session or user.
    ///   - target: The target session.
    ///   - directory: The directory.
    /// - Returns: The id of the message.
    /// - Throws: What `send(_:)` throws, or when the send made no message.
    private static func ask(
        from sender: SessionMessageSender, to target: ULID, in directory: InMemorySessionDirectory
    ) async throws -> MailID {
        let receipts = try await directory.send(
            OutgoingSessionMessage(from: sender, to: .session(target), text: questionText))
        return try #require(receipts.first?.messageID)
    }

    // MARK: - send message: each address form

    @Test("send message to a session id delivers the message to that idle session")
    func sendMessageToASessionIDDeliversIt() async throws {
        let directory = InMemorySessionDirectory()
        let target = Fixtures.summary()
        directory.register(target)
        let tool = try SessionsTool(directory: directory)

        let (output, callerID) = try await Fixtures.asCaller(in: directory) { callerID in
            (try await Self.sendMessage(to: target.id.ulidString, with: tool), callerID)
        }

        let message = try #require(try await Self.unread(to: target.id, in: directory).first)
        #expect(message.text == Self.messageText)
        #expect(message.from == .session(callerID))
        #expect(output.contains(Self.deliveredWord), "output was: \(output)")
        #expect(output.contains(target.id.ulidString), "output was: \(output)")
        #expect(output.contains(message.id.description), "output was: \(output)")
    }

    @Test("send message reads a session id in lower case")
    func sendMessageReadsALowerCaseSessionID() async throws {
        let directory = InMemorySessionDirectory()
        let target = Fixtures.summary()
        directory.register(target)
        let tool = try SessionsTool(directory: directory)

        _ = try await Fixtures.asCaller(in: directory) { _ in
            try await Self.sendMessage(to: target.id.ulidString.lowercased(), with: tool)
        }

        #expect(try await Self.unread(to: target.id, in: directory).count == 1)
    }

    @Test("send message to a working session queues the message")
    func sendMessageToAWorkingSessionQueuesIt() async throws {
        let directory = InMemorySessionDirectory()
        let target = Fixtures.summary()
        directory.register(target)
        try directory.startUserTurn(of: target.id)
        let tool = try SessionsTool(directory: directory)

        let output = try await Fixtures.asCaller(in: directory) { _ in
            try await Self.sendMessage(to: target.id.ulidString, with: tool)
        }

        #expect(try await Self.unread(to: target.id, in: directory).count == 1)
        #expect(output.contains(Self.queuedWord), "output was: \(output)")
    }

    @Test("send message to @agent starts a new root session in the folder of the caller, also next to a live one")
    func sendMessageToAnAgentStartsANewSessionInTheFolderOfTheCaller() async throws {
        let directory = Fixtures.directoryWithLauncher(agentIDs: [Self.reviewerAgent])
        let elsewhere = Fixtures.summary(agent: Self.reviewerAgent, folder: Self.otherFolder)
        let live = Fixtures.summary(agent: Self.reviewerAgent)
        directory.register(elsewhere)
        directory.register(live)
        let tool = try SessionsTool(directory: directory)

        let (output, started) = try await Self.sendAsCaller(to: "@\(Self.reviewerAgent)", in: directory, with: tool)

        let session = try #require(started.first)
        #expect(started.count == 1)
        #expect(![live.id, elsewhere.id].contains(session.id))
        #expect(session.workingDirectory.path == Fixtures.workingFolder.path)
        #expect(session.origin == .message)
        #expect(output.contains(Self.startedWord), "output was: \(output)")
        #expect(output.contains(session.id.ulidString), "output was: \(output)")
        #expect(try await Self.unread(to: live.id, in: directory).isEmpty)
        #expect(try await Self.unread(to: elsewhere.id, in: directory).isEmpty)
    }

    @Test("send message to @agent:/path starts a new root session in that folder, also next to a live one")
    func sendMessageToAnAgentInAFolderStartsANewSessionThere() async throws {
        let directory = Fixtures.directoryWithLauncher(agentIDs: [Self.reviewerAgent])
        let live = Fixtures.summary(agent: Self.reviewerAgent, folder: Self.otherFolder)
        let nearby = Fixtures.summary(agent: Self.reviewerAgent)
        directory.register(live)
        directory.register(nearby)
        let tool = try SessionsTool(directory: directory)

        let (output, started) = try await Self.sendAsCaller(
            to: "@\(Self.reviewerAgent):\(Self.otherFolder.path)", in: directory, with: tool)

        let session = try #require(started.first)
        #expect(started.count == 1)
        #expect(![live.id, nearby.id].contains(session.id))
        #expect(session.workingDirectory.path == Self.otherFolder.path)
        #expect(session.origin == .message)
        #expect(output.contains(Self.startedWord), "output was: \(output)")
        #expect(try await Self.unread(to: live.id, in: directory).isEmpty)
        #expect(try await Self.unread(to: nearby.id, in: directory).isEmpty)
    }

    @Test("send message to @agent with no live session starts one, and gives its id")
    func sendMessageToAnAgentWithNoSessionStartsOne() async throws {
        let directory = Fixtures.directoryWithLauncher(agentIDs: [Self.reviewerAgent])
        let tool = try SessionsTool(directory: directory)

        let (output, started) = try await Self.sendAsCaller(to: "@\(Self.reviewerAgent)", in: directory, with: tool)

        let session = try #require(started.first)
        #expect(started.count == 1)
        #expect(session.agentID == Self.reviewerAgent)
        #expect(session.origin == .message)
        #expect(output.contains(Self.startedWord), "output was: \(output)")
        #expect(output.contains(session.id.ulidString), "output was: \(output)")
    }

    @Test("send message to an absolute folder reaches the live root session in that folder")
    func sendMessageToAFolderReachesItsSession() async throws {
        let directory = InMemorySessionDirectory()
        let target = Fixtures.summary(agent: Self.reviewerAgent, folder: Self.otherFolder)
        directory.register(target)
        let tool = try SessionsTool(directory: directory)

        _ = try await Fixtures.asCaller(in: directory) { _ in
            try await Self.sendMessage(to: Self.otherFolder.path, with: tool)
        }

        #expect(try await Self.unread(to: target.id, in: directory).count == 1)
    }

    @Test("send message to a ~/path folder expands the home folder and reaches the session there")
    func sendMessageToAHomeFolderExpandsTheTilde() async throws {
        let directory = InMemorySessionDirectory()
        let homeFolder = FileManager.default.homeDirectoryForCurrentUser.appending(path: Self.homeRelativePath)
        let target = Fixtures.summary(folder: homeFolder)
        directory.register(target)
        let tool = try SessionsTool(directory: directory)

        _ = try await Fixtures.asCaller(in: directory) { _ in
            try await Self.sendMessage(to: "~/\(Self.homeRelativePath)", with: tool)
        }

        #expect(try await Self.unread(to: target.id, in: directory).count == 1)
    }

    @Test("send message to a folder with no live session gives a corrective with the hint to name an agent")
    func sendMessageToAnEmptyFolderNamesTheAgentForm() async throws {
        let directory = InMemorySessionDirectory()
        let tool = try SessionsTool(directory: directory)

        let output = try await Fixtures.asCaller(in: directory) { _ in
            try await Self.sendMessage(to: Self.otherFolder.path, with: tool)
        }

        #expect(output.contains(Self.notSentSentence), "output was: \(output)")
        #expect(output.contains(Refusal.noSessionInTheFolder.rawValue), "output was: \(output)")
    }

    @Test("send message to #tag reaches each live session with the tag, but not the caller")
    func sendMessageToATagReachesEachTaggedSession() async throws {
        let directory = InMemorySessionDirectory()
        let first = Fixtures.summary(tags: [Self.reviewTag])
        let second = Fixtures.summary(tags: [Self.reviewTag])
        let untagged = Fixtures.summary()
        directory.register(first)
        directory.register(second)
        directory.register(untagged)
        let tool = try SessionsTool(directory: directory)

        let callerID = try await Fixtures.asCaller(in: directory) { callerID in
            _ = try await directory.addTags([Self.reviewTag], to: callerID)
            _ = try await Self.sendMessage(to: "#\(Self.reviewTag)", with: tool)
            return callerID
        }

        #expect(try await Self.unread(to: first.id, in: directory).count == 1)
        #expect(try await Self.unread(to: second.id, in: directory).count == 1)
        #expect(try await Self.unread(to: untagged.id, in: directory).isEmpty)
        #expect(try await Self.unread(to: callerID, in: directory).isEmpty)
    }

    // MARK: - send message: the references of a session (D199)

    /// The form of a reference to one session, written from its summary.
    struct ReferenceForm: Sendable, CustomTestStringConvertible {
        /// The name of the form in the test report.
        let name: String

        /// The `to` text of the form for a session.
        let text: @Sendable (SessionSummary) -> String

        /// The name of the case in the test report.
        var testDescription: String { name }
    }

    /// Each form that names one session by its id or by its short id.
    static let referenceForms: [ReferenceForm] = [
        ReferenceForm(name: "@<short id>") { "@\($0.shortID)" },
        ReferenceForm(name: "<short id>") { $0.shortID },
        ReferenceForm(name: "@<id>") { "@\($0.id.ulidString)" },
        ReferenceForm(name: "<id>") { $0.id.ulidString },
    ]

    @Test("send message to each id form and short id form reaches that session", arguments: referenceForms)
    func sendMessageToAnIDFormReachesTheSession(_ form: ReferenceForm) async throws {
        let directory = InMemorySessionDirectory()
        let target = Fixtures.summary(folder: Self.otherFolder)
        directory.register(target)
        let tool = try SessionsTool(directory: directory)

        _ = try await Fixtures.asCaller(in: directory) { _ in
            try await Self.sendMessage(to: form.text(target), with: tool)
        }

        #expect(try await Self.unread(to: target.id, in: directory).map(\.text) == [Self.messageText])
    }

    @Test("send message to @<slug> reaches the session with the slug in the folder of the caller")
    func sendMessageToASlugPrefersTheFolderOfTheCaller() async throws {
        let directory = InMemorySessionDirectory()
        let elsewhere = Fixtures.summary(title: Self.apiTitle, folder: Self.otherFolder)
        let local = Fixtures.summary(title: Self.apiTitle)
        directory.register(elsewhere)
        directory.register(local)
        let tool = try SessionsTool(directory: directory)

        _ = try await Fixtures.asCaller(in: directory) { _ in
            try await Self.sendMessage(to: "@\(Self.apiSlug)", with: tool)
        }

        #expect(try await Self.unread(to: local.id, in: directory).count == 1)
        #expect(try await Self.unread(to: elsewhere.id, in: directory).isEmpty)
    }

    @Test("send message to an ambiguous slug gives a corrective with the id, the name and the folder of each match")
    func sendMessageToAnAmbiguousSlugListsEachMatch() async throws {
        let directory = InMemorySessionDirectory()
        let first = Fixtures.summary(title: Self.apiTitle, folder: Self.otherFolder)
        let second = Fixtures.summary(
            title: Self.apiTitle, folder: FileManager.default.homeDirectoryForCurrentUser)
        directory.register(first)
        directory.register(second)
        let tool = try SessionsTool(directory: directory)

        let output = try await Fixtures.asCaller(in: directory) { _ in
            try await Self.sendMessage(to: "@\(Self.apiSlug)", with: tool)
        }

        #expect(output.contains(Self.ambiguousWords), "output was: \(output)")
        for match in [first, second] {
            #expect(output.contains(match.id.ulidString), "output was: \(output)")
            #expect(output.contains(match.workingDirectory.path), "output was: \(output)")
            #expect(try await Self.unread(to: match.id, in: directory).isEmpty)
        }
        #expect(output.contains(Self.apiTitle), "output was: \(output)")
    }

    @Test("send message to @travel reaches the session whose slug is travel, and starts no agent")
    func sendMessageToANameReachesTheSessionWithThatSlug() async throws {
        let directory = Fixtures.directoryWithLauncher(agentIDs: [Self.travelName])
        let session = Fixtures.summary(title: Self.travelName, folder: Self.otherFolder)
        directory.register(session)
        let tool = try SessionsTool(directory: directory)

        let (_, started) = try await Self.sendAsCaller(to: "@\(Self.travelName)", in: directory, with: tool)

        #expect(try await Self.unread(to: session.id, in: directory).count == 1)
        #expect(started.isEmpty)
    }

    @Test("send message to @travel with no such session and an agent folder travel starts that agent")
    func sendMessageToAnAgentNameWithNoSessionStartsTheAgent() async throws {
        let directory = Fixtures.directoryWithLauncher(agentIDs: [Self.travelName])
        let tool = try SessionsTool(directory: directory)

        let (output, started) = try await Self.sendAsCaller(to: "@\(Self.travelName)", in: directory, with: tool)

        let session = try #require(started.first)
        #expect(session.agentID == Self.travelName)
        #expect(output.contains(Self.startedWord), "output was: \(output)")
    }

    @Test("send message to @travel:~/trips looks in ~/trips first and reports the rewrite of the alias")
    func sendMessageToAnAgentAliasLooksInItsFolderFirst() async throws {
        let directory = Fixtures.directoryWithLauncher(agentIDs: [Self.travelName])
        let trips = FileManager.default.homeDirectoryForCurrentUser.appending(path: Self.tripsRelativePath)
        let local = Fixtures.summary(title: Self.travelName)
        let inTrips = Fixtures.summary(title: Self.travelName, folder: trips)
        directory.register(local)
        directory.register(inTrips)
        let tool = try SessionsTool(directory: directory)
        let alias = "@\(Self.travelName):~/\(Self.tripsRelativePath)"

        let output = try await Fixtures.asCaller(in: directory) { _ in
            try await Self.sendMessage(to: alias, with: tool)
        }

        #expect(try await Self.unread(to: inTrips.id, in: directory).count == 1)
        #expect(try await Self.unread(to: local.id, in: directory).isEmpty)
        #expect(
            output.contains(SessionsToolText.agentAliasRewrite(alias, name: Self.travelName, folder: trips)),
            "output was: \(output)")
    }

    @Test("send message to a folder path reports the rewrite of the alias")
    func sendMessageToAFolderReportsTheRewrite() async throws {
        let directory = InMemorySessionDirectory()
        let target = Fixtures.summary(folder: Self.otherFolder)
        directory.register(target)
        let tool = try SessionsTool(directory: directory)

        let output = try await Fixtures.asCaller(in: directory) { _ in
            try await Self.sendMessage(to: Self.otherFolder.path, with: tool)
        }

        #expect(
            output.contains(SessionsToolText.folderAliasRewrite(Self.otherFolder.path, folder: Self.otherFolder)),
            "output was: \(output)")
    }

    @Test("send message to @nobody gives the corrective that no session and no agent has the name")
    func sendMessageToAnUnknownNameIsACorrective() async throws {
        let directory = Fixtures.directoryWithLauncher()
        let tool = try SessionsTool(directory: directory)

        let (output, started) = try await Self.sendAsCaller(to: "@\(Self.nobodyName)", in: directory, with: tool)

        #expect(output.contains(Self.noSessionOrAgentWords), "output was: \(output)")
        #expect(output.contains(Self.nobodyName), "output was: \(output)")
        #expect(started.isEmpty)
    }

    // MARK: - send message: refusals and correctives

    @Test("send message to an archived session gives a corrective with the reason archived, which names startSession")
    func sendMessageToAnArchivedSessionIsACorrective() async throws {
        let directory = InMemorySessionDirectory()
        let target = Fixtures.summary()
        directory.register(target)
        _ = try await directory.archive(target.id, by: .user(clientID: Self.userClientID))
        let tool = try SessionsTool(directory: directory)

        let output = try await Fixtures.asCaller(in: directory) { _ in
            try await Self.sendMessage(to: target.id.ulidString, with: tool)
        }

        #expect(try await Self.unread(to: target.id, in: directory).isEmpty)
        #expect(output.contains(Self.notSentSentence), "output was: \(output)")
        #expect(output.contains(Self.archivedReason), "output was: \(output)")
        #expect(output.contains(target.id.ulidString), "output was: \(output)")
        #expect(output.contains(Self.startSessionVerb), "output was: \(output)")
    }

    @Test("send message that a loop guard refuses gives a corrective that names the reason")
    func sendMessageThatALoopGuardRefusesNamesTheReason() async throws {
        let directory = InMemorySessionDirectory(
            loopGuards: InMemorySessionDirectory.LoopGuards(sendsPerTurnLimit: Self.noSendsPerTurn))
        let target = Fixtures.summary()
        directory.register(target)
        let tool = try SessionsTool(directory: directory)

        let output = try await Fixtures.asCaller(in: directory) { _ in
            try await Self.sendMessage(to: target.id.ulidString, with: tool)
        }

        #expect(try await Self.unread(to: target.id, in: directory).isEmpty)
        #expect(output.contains(Self.notSentSentence), "output was: \(output)")
        #expect(output.contains(Refusal.tooManySends.rawValue), "output was: \(output)")
    }

    @Test("send message to a text that names no address form gives a corrective that lists the forms")
    func sendMessageToAFormlessAddressListsTheForms() async throws {
        let directory = InMemorySessionDirectory()
        let tool = try SessionsTool(directory: directory)

        let output = try await Fixtures.asCaller(in: directory) { _ in
            try await Self.sendMessage(to: Self.formlessAddress, with: tool)
        }

        #expect(output.contains(Self.formlessAddress), "output was: \(output)")
        #expect(output.contains("@agent"), "output was: \(output)")
        #expect(output.contains("#tag"), "output was: \(output)")
    }

    @Test("send message to an unknown session id gives a corrective that names listSessions")
    func sendMessageToAnUnknownSessionNamesListSessions() async throws {
        let directory = InMemorySessionDirectory()
        let tool = try SessionsTool(directory: directory)

        let output = try await Fixtures.asCaller(in: directory) { _ in
            try await Self.sendMessage(to: Self.absentID.ulidString, with: tool)
        }

        #expect(output.contains(Self.absentID.ulidString), "output was: \(output)")
        #expect(output.contains(Self.listSessionsVerb), "output was: \(output)")
    }

    @Test("send message with a blank message gives a corrective and sends nothing")
    func sendMessageWithABlankMessageIsACorrective() async throws {
        let directory = InMemorySessionDirectory()
        let target = Fixtures.summary()
        directory.register(target)
        let tool = try SessionsTool(directory: directory)

        let output = try await Fixtures.asCaller(in: directory) { _ in
            try await Self.sendMessage(to: target.id.ulidString, "  ", with: tool)
        }

        #expect(output.contains(SessionsToolText.messageParameter), "output was: \(output)")
        #expect(try await Self.unread(to: target.id, in: directory).isEmpty)
    }

    @Test("send message with no ToolContext gives a corrective and sends nothing")
    func sendMessageWithNoCallerIsACorrective() async throws {
        let directory = InMemorySessionDirectory()
        let target = Fixtures.summary()
        directory.register(target)
        let tool = try SessionsTool(directory: directory)

        let output = try await Self.sendMessage(to: target.id.ulidString, with: tool)

        #expect(output.contains("send message"), "output was: \(output)")
        #expect(try await Self.unread(to: target.id, in: directory).isEmpty)
    }

    // MARK: - reply message

    @Test("reply message to a message that read inbox gave goes to its sender, whose readInbox shows inReplyTo")
    func replyMessageRecordsInReplyToForTheSender() async throws {
        let directory = InMemorySessionDirectory()
        let tool = try SessionsTool(directory: directory)

        let (questionID, senderInbox) = try await Fixtures.asCaller(in: directory) { senderID in
            let questionID = try await Fixtures.asCaller(in: directory) { callerID in
                let questionID = try await Self.ask(from: .session(senderID), to: callerID, in: directory)
                _ = try await tool.call(arguments: Fixtures.payload("read inbox"))
                _ = try await Self.replyMessage(to: questionID.description, with: tool)
                return questionID
            }
            return (questionID, try await tool.call(arguments: Fixtures.payload("read inbox")))
        }

        #expect(senderInbox.contains(Self.replyText), "inbox was: \(senderInbox)")
        #expect(senderInbox.contains("in reply to \(questionID)"), "inbox was: \(senderInbox)")
    }

    @Test("reply message from a new SessionsTool to a message that an earlier one's read inbox gave reaches its sender")
    func replyMessageFromANewToolToAReadMessageReachesTheSender() async throws {
        let directory = InMemorySessionDirectory()
        let sender = Fixtures.summary()
        directory.register(sender)
        let readingTool = try SessionsTool(directory: directory)
        let replyingTool = try SessionsTool(directory: directory)

        let (questionID, output) = try await Fixtures.asCaller(in: directory) { callerID in
            let questionID = try await Self.ask(from: .session(sender.id), to: callerID, in: directory)
            _ = try await readingTool.call(arguments: Fixtures.payload("read inbox"))
            return (questionID, try await Self.replyMessage(to: questionID.description, with: replyingTool))
        }

        let reply = try #require(try await Self.unread(to: sender.id, in: directory).first, "output was: \(output)")
        #expect(reply.inReplyTo == questionID)
        #expect(reply.text == Self.replyText)
        #expect(output.contains(Self.deliveredWord), "output was: \(output)")
    }

    @Test("reply message to an unread message goes to its sender with inReplyTo")
    func replyMessageToAnUnreadMessageReachesTheSender() async throws {
        let directory = InMemorySessionDirectory()
        let sender = Fixtures.summary()
        directory.register(sender)
        let tool = try SessionsTool(directory: directory)

        let (questionID, output) = try await Fixtures.asCaller(in: directory) { callerID in
            let questionID = try await Self.ask(from: .session(sender.id), to: callerID, in: directory)
            return (questionID, try await Self.replyMessage(to: questionID.description.lowercased(), with: tool))
        }

        let reply = try #require(try await Self.unread(to: sender.id, in: directory).first)
        #expect(reply.inReplyTo == questionID)
        #expect(reply.text == Self.replyText)
        #expect(output.contains(Self.deliveredWord), "output was: \(output)")
    }

    @Test("reply message to a message from the user gives a corrective and sends nothing")
    func replyMessageToAUserMessageIsACorrective() async throws {
        let directory = InMemorySessionDirectory()
        let tool = try SessionsTool(directory: directory)

        let output = try await Fixtures.asCaller(in: directory) { callerID in
            let questionID = try await Self.ask(
                from: .user(clientID: Self.userClientID), to: callerID, in: directory)
            return try await Self.replyMessage(to: questionID.description, with: tool)
        }

        #expect(output.contains(Self.userReplyWords), "output was: \(output)")
        #expect(!output.contains(Self.deliveredWord), "output was: \(output)")
    }

    @Test("reply message to an id that no message to the caller has gives a corrective that names readInbox")
    func replyMessageToAnUnknownMessageNamesReadInbox() async throws {
        let directory = InMemorySessionDirectory()
        let tool = try SessionsTool(directory: directory)

        let output = try await Fixtures.asCaller(in: directory) { _ in
            try await Self.replyMessage(to: Self.absentID.ulidString, with: tool)
        }

        #expect(output.contains(Self.absentID.ulidString), "output was: \(output)")
        #expect(output.contains(Self.readInboxVerb), "output was: \(output)")
    }

    @Test("reply message to a text that is not a message id gives a corrective that names readInbox")
    func replyMessageToAMalformedIDNamesReadInbox() async throws {
        let directory = InMemorySessionDirectory()
        let tool = try SessionsTool(directory: directory)

        let output = try await Fixtures.asCaller(in: directory) { _ in
            try await Self.replyMessage(to: Self.malformedID, with: tool)
        }

        #expect(output.contains(Self.malformedID), "output was: \(output)")
        #expect(output.contains(Self.readInboxVerb), "output was: \(output)")
    }

    @Test("reply message with no ToolContext gives a corrective")
    func replyMessageWithNoCallerIsACorrective() async throws {
        let directory = InMemorySessionDirectory()
        let tool = try SessionsTool(directory: directory)

        let output = try await Self.replyMessage(to: Self.absentID.ulidString, with: tool)

        #expect(output.contains("reply message"), "output was: \(output)")
    }

    // MARK: - The snippet through withSessions

    /// What the snippet reports about the two verbs.
    private struct SnippetReport: Decodable {
        /// What `sendMessage` gave.
        let sent: String

        /// What `replyMessage` gave.
        let replied: String
    }

    @Test("tools.sessions.sendMessage and replyMessage deliver messages in one runCode snippet")
    func theMessageVerbsWorkInASnippet() async throws {
        let directory = InMemorySessionDirectory()
        let other = Fixtures.summary()
        directory.register(other)
        let tool = try SessionsTool(directory: directory)
        let multiTool = MultiTool(registry: try MultiTool.Builder(mode: .open).withSessions(tool).buildRegistry())

        let (output, questionID) = try await Fixtures.asCaller(in: directory) { callerID in
            let questionID = try await Self.ask(from: .session(other.id), to: callerID, in: directory)
            let output = try await multiTool.call(
                arguments: RunCodeArguments(
                    code: """
                        const sent = await tools.sessions.sendMessage({ to: "\(other.id.ulidString)", message: "\(Self.messageText)" });
                        const replied = await tools.sessions.replyMessage({ inReplyTo: "\(questionID)", message: "\(Self.replyText)" });
                        return { sent, replied };
                        """))
            return (output, questionID)
        }

        let report = try RunOutput.decoded(SnippetReport.self, from: output)
        let messages = try await Self.unread(to: other.id, in: directory)
        #expect(
            messages.map(\.text) == [Self.messageText, Self.replyText],
            "sent: \(report.sent), replied: \(report.replied)")
        #expect(messages.last?.inReplyTo == questionID)
    }

    @Test("a receipt with the outcome sent says the message is in the inbox of the session and not yet delivered")
    func aSentReceiptSaysTheMessageIsNotYetDelivered() {
        let target = ULID.generate()
        let messageID = MailID()
        let receipt = SessionSendReceipt(messageID: messageID, target: target, outcome: .sent)

        let output = SessionsToolText.receipts([receipt])

        #expect(output.contains(Self.sentWord), "output was: \(output)")
        #expect(output.contains(Self.notDeliveredWords), "output was: \(output)")
        #expect(output.contains("\(messageID)"), "output was: \(output)")
    }

    @Test("the SendOutcome enum maps the outcome sent of the directory to SENT")
    func theSendOutcomeEnumMapsSent() {
        #expect(SessionsGraphOutcome(.sent) == .sent)
        #expect(SessionsGraphOutcome.sent.rawValue == "SENT")
    }
}
