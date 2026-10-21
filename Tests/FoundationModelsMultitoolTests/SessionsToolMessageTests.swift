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

    @Test("send message to @agent reaches the live root session of the agent in the folder of the caller")
    func sendMessageToAnAgentReachesItsSessionInTheFolderOfTheCaller() async throws {
        let directory = InMemorySessionDirectory()
        let elsewhere = Fixtures.summary(agent: Self.reviewerAgent, folder: Self.otherFolder)
        let target = Fixtures.summary(agent: Self.reviewerAgent)
        directory.register(elsewhere)
        directory.register(target)
        let tool = try SessionsTool(directory: directory)

        _ = try await Fixtures.asCaller(in: directory) { _ in
            try await Self.sendMessage(to: "@\(Self.reviewerAgent)", with: tool)
        }

        #expect(try await Self.unread(to: target.id, in: directory).count == 1)
        #expect(try await Self.unread(to: elsewhere.id, in: directory).isEmpty)
    }

    @Test("send message to @agent:/path reaches the live root session of the agent in that folder")
    func sendMessageToAnAgentInAFolderReachesItsSessionThere() async throws {
        let directory = InMemorySessionDirectory()
        let target = Fixtures.summary(agent: Self.reviewerAgent, folder: Self.otherFolder)
        let nearby = Fixtures.summary(agent: Self.reviewerAgent)
        directory.register(target)
        directory.register(nearby)
        let tool = try SessionsTool(directory: directory)

        _ = try await Fixtures.asCaller(in: directory) { _ in
            try await Self.sendMessage(to: "@\(Self.reviewerAgent):\(Self.otherFolder.path)", with: tool)
        }

        #expect(try await Self.unread(to: target.id, in: directory).count == 1)
        #expect(try await Self.unread(to: nearby.id, in: directory).isEmpty)
    }

    @Test("send message to @agent with no live session starts one, and gives its id")
    func sendMessageToAnAgentWithNoSessionStartsOne() async throws {
        let directory = Fixtures.directoryWithLauncher(agentIDs: [Self.reviewerAgent])
        let tool = try SessionsTool(directory: directory)

        let (output, started) = try await Fixtures.asCaller(in: directory) { callerID in
            let output = try await Self.sendMessage(to: "@\(Self.reviewerAgent)", with: tool)
            return (output, try await directory.sessions(matching: SessionQuery(startedBy: callerID)))
        }

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
        let multiTool = MultiTool(registry: try MultiTool.Builder().withSessions(tool).buildRegistry())

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
        #expect(messages.map(\.text) == [Self.messageText, Self.replyText], "sent: \(report.sent), replied: \(report.replied)")
        #expect(messages.last?.inReplyTo == questionID)
    }
}
