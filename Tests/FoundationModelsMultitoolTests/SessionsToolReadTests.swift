import Foundation
import FoundationModels
import FoundationModelsExtras
import Testing
import ULID

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Coverage for the read operations of ``SessionsTool`` — `list sessions`,
/// `check session` and `read inbox` — over an `InMemorySessionDirectory`.
///
/// The direct cases call ``SessionsTool/call(arguments:)`` with an `op`
/// payload, as a model does. The snippet case mounts the tool with
/// `MultiTool.Builder.withSessions(_:)` and calls each verb as
/// `tools.sessions.<verb>` in one `runCode` snippet.
///
/// A case that needs a caller session binds the context of a stub run, and
/// registers a session with the id of that run in the directory, so the
/// directory knows the caller.
@Suite("SessionsToolReadTests", .ownsTemporaryDirectories)
struct SessionsToolReadTests {
    // MARK: - Shared test constants

    /// The tag of the tagged session.
    private static let reviewTag = "review"

    /// The title of the tagged session.
    private static let reviewTitle = "Review the parser"

    /// The last summary of the checked session.
    private static let lastSummary = "The parser handles empty input now."

    /// The text of the message of the inbox cases.
    private static let messageText = "Please look at the failing test."

    /// A message text that holds a fence of its own, so the output fence must
    /// be longer than it.
    private static let fencedMessageText = "Run this:\n```\nswift test\n```"

    /// The label of the fence around each message text.
    private static let untrustedLabel = "untrusted message"

    /// The text that a list with no match gives.
    private static let noMatchText = "No sessions match."

    /// The text that an empty inbox gives.
    private static let emptyInboxText = "No unread messages."

    /// The code-mode verb name that each unknown-session corrective names.
    private static let listSessionsVerb = "listSessions"

    /// The mark of the caller session in a listing.
    private static let youMark = "(you)"

    /// A session id no session has.
    private static let absentID = ULID()

    /// A text that is not a session id.
    private static let malformedID = "not-a-session"

    // MARK: - Helpers

    /// The shared fixtures of the `sessions` tool tests.
    private typealias Fixtures = SessionsToolFixtures

    /// Sends ``messageText``, or `text`, from `sender` to `target`.
    ///
    /// - Parameters:
    ///   - text: The text of the message.
    ///   - sender: The sending session.
    ///   - target: The target session.
    ///   - directory: The directory.
    /// - Throws: What `send(_:)` throws.
    private static func send(
        _ text: String = messageText, from sender: ULID, to target: ULID, in directory: InMemorySessionDirectory
    ) async throws {
        try directory.startUserTurn(of: sender)
        _ = try await directory.send(OutgoingSessionMessage(from: .session(sender), to: .session(target), text: text))
    }

    // MARK: - list sessions

    @Test("list sessions gives one line for each session, and marks the caller with (you)")
    func listSessionsListsEachSessionAndMarksTheCaller() async throws {
        let directory = InMemorySessionDirectory()
        let other = Fixtures.summary(tags: [Self.reviewTag], title: Self.reviewTitle)
        directory.register(other)
        let tool = try SessionsTool(directory: directory)

        let (output, callerID) = try await Fixtures.asCaller(in: directory) { callerID in
            (try await tool.call(arguments: Fixtures.payload("list sessions")), callerID)
        }

        let lines = output.split(separator: "\n").map(String.init)
        let callerLine = try #require(lines.first { $0.contains(callerID.ulidString) })
        let otherLine = try #require(lines.first { $0.contains(other.id.ulidString) })
        #expect(callerLine.contains(Self.youMark))
        #expect(!otherLine.contains(Self.youMark))
        #expect(otherLine.contains(Self.reviewTitle))
        #expect(otherLine.contains(Self.reviewTag))
        #expect(otherLine.contains(Fixtures.agentID))
        #expect(otherLine.contains(Fixtures.workingFolder.path))
    }

    @Test("list sessions with a tag no session has gives \"No sessions match.\"")
    func listSessionsWithNoMatchSaysSo() async throws {
        let directory = InMemorySessionDirectory()
        directory.register(Fixtures.summary())
        let tool = try SessionsTool(directory: directory)

        let output = try await tool.call(arguments: Fixtures.payload("list sessions", [("tag", Self.reviewTag)]))

        #expect(output == Self.noMatchText)
    }

    @Test("list sessions with a relative cwd gives a corrective and lists nothing")
    func listSessionsWithARelativeFolderIsACorrective() async throws {
        let directory = InMemorySessionDirectory()
        let session = Fixtures.summary()
        directory.register(session)
        let tool = try SessionsTool(directory: directory)

        let output = try await tool.call(arguments: Fixtures.payload("list sessions", [("cwd", "project")]))

        #expect(output.contains("absolute"), "output was: \(output)")
        #expect(!output.contains(session.id.ulidString))
    }

    @Test("list sessions with state Archived, in any letter case, also finds the recorded sessions, with no includeRecorded")
    func listSessionsOfArchivedStateIncludesRecordedSessions() async throws {
        let directory = InMemorySessionDirectory()
        let live = Fixtures.summary()
        directory.register(live)
        let archived = Fixtures.summary()
        directory.register(archived)
        _ = try await directory.archive(archived.id, by: .user(clientID: "test"))
        let tool = try SessionsTool(directory: directory)

        let output = try await tool.call(arguments: Fixtures.payload("list sessions", [("state", "Archived")]))

        #expect(output.contains(archived.id.ulidString), "output was: \(output)")
        #expect(!output.contains(live.id.ulidString))
    }

    // MARK: - check session

    @Test("check session gives the state, the agent, the folder, the tags, the last summary and the unread count")
    func checkSessionGivesTheFactsOfTheSession() async throws {
        let directory = InMemorySessionDirectory()
        let other = Fixtures.summary(tags: [Self.reviewTag], title: Self.reviewTitle)
        directory.register(other)
        let tool = try SessionsTool(directory: directory)

        let output = try await Fixtures.asCaller(in: directory) { callerID in
            try await Self.send(from: other.id, to: callerID, in: directory)
            try directory.finishTurn(of: other.id, lastSummary: Self.lastSummary)
            return try await tool.call(arguments: Fixtures.payload("check session", [("id", other.id.ulidString)]))
        }

        #expect(output.contains(SessionState.idle.rawValue), "output was: \(output)")
        #expect(output.contains(Fixtures.agentID))
        #expect(output.contains(Fixtures.workingFolder.path))
        #expect(output.contains(Self.reviewTag))
        #expect(output.contains(Self.lastSummary))
        #expect(output.contains("Unread messages from it to you: 1"), "output was: \(output)")
    }

    @Test("check session reads a session id in lower case")
    func checkSessionReadsALowerCaseID() async throws {
        let directory = InMemorySessionDirectory()
        let session = Fixtures.summary(title: Self.reviewTitle)
        directory.register(session)
        let tool = try SessionsTool(directory: directory)

        let output = try await tool.call(
            arguments: Fixtures.payload("check session", [("id", session.id.ulidString.lowercased())]))

        #expect(output.contains(session.id.ulidString), "output was: \(output)")
        #expect(output.contains(Self.reviewTitle))
    }

    @Test("check session of an unknown id gives a corrective that names listSessions")
    func checkSessionOfAnUnknownIDNamesListSessions() async throws {
        let tool = try SessionsTool(directory: InMemorySessionDirectory())

        let output = try await tool.call(
            arguments: Fixtures.payload("check session", [("id", Self.absentID.ulidString)]))

        #expect(output.contains(Self.absentID.ulidString), "output was: \(output)")
        #expect(output.contains(Self.listSessionsVerb), "output was: \(output)")
    }

    @Test("check session of a text that is not a session id gives a corrective that names listSessions")
    func checkSessionOfAMalformedIDNamesListSessions() async throws {
        let tool = try SessionsTool(directory: InMemorySessionDirectory())

        let output = try await tool.call(arguments: Fixtures.payload("check session", [("id", Self.malformedID)]))

        #expect(output.contains(Self.malformedID), "output was: \(output)")
        #expect(output.contains(Self.listSessionsVerb), "output was: \(output)")
    }

    // MARK: - read inbox

    @Test("read inbox gives each unread message in an untrusted fence, and a second read gives none")
    func readInboxMarksTheMessagesRead() async throws {
        let directory = InMemorySessionDirectory()
        let sender = Fixtures.summary(title: Self.reviewTitle)
        directory.register(sender)
        let tool = try SessionsTool(directory: directory)

        let (first, second) = try await Fixtures.asCaller(in: directory) { callerID in
            try await Self.send(from: sender.id, to: callerID, in: directory)
            let first = try await tool.call(arguments: Fixtures.payload("read inbox"))
            let second = try await tool.call(arguments: Fixtures.payload("read inbox"))
            return (first, second)
        }

        #expect(first.contains(Self.messageText), "output was: \(first)")
        #expect(first.contains(Self.untrustedLabel))
        #expect(first.contains(sender.id.ulidString))
        #expect(first.contains(Self.reviewTitle))
        #expect(second == Self.emptyInboxText)
    }

    @Test("read inbox fences a message that holds a fence of its own with a longer fence")
    func readInboxFenceOutlastsTheFenceOfTheMessage() async throws {
        let directory = InMemorySessionDirectory()
        let sender = Fixtures.summary()
        directory.register(sender)
        let tool = try SessionsTool(directory: directory)

        let output = try await Fixtures.asCaller(in: directory) { callerID in
            try await Self.send(Self.fencedMessageText, from: sender.id, to: callerID, in: directory)
            return try await tool.call(arguments: Fixtures.payload("read inbox"))
        }

        #expect(output.contains("````\(Self.untrustedLabel)\n\(Self.fencedMessageText)\n````"), "output was: \(output)")
    }

    @Test("read inbox with no ToolContext gives a corrective, because it has no caller session")
    func readInboxWithNoCallerIsACorrective() async throws {
        let tool = try SessionsTool(directory: InMemorySessionDirectory())

        let output = try await tool.call(arguments: Fixtures.payload("read inbox"))

        #expect(output != Self.emptyInboxText)
        #expect(output.contains("session"), "output was: \(output)")
    }

    // MARK: - The snippet through withSessions

    /// What the snippet reports about the three verbs.
    private struct SnippetReport: Decodable {
        /// What `listSessions` gave.
        let listed: String

        /// What `checkSession` gave.
        let checked: String

        /// What the first `readInbox` gave.
        let firstRead: String

        /// What the second `readInbox` gave.
        let secondRead: String
    }

    @Test("tools.sessions.listSessions, checkSession and readInbox work in one runCode snippet through withSessions")
    func theReadVerbsWorkInASnippet() async throws {
        let directory = InMemorySessionDirectory()
        let sender = Fixtures.summary(title: Self.reviewTitle)
        directory.register(sender)
        let tool = try SessionsTool(directory: directory)
        let multiTool = MultiTool(registry: try MultiTool.Builder().withSessions(tool).buildRegistry())

        let output = try await Fixtures.asCaller(in: directory) { callerID in
            try await Self.send(from: sender.id, to: callerID, in: directory)
            return try await multiTool.call(
                arguments: RunCodeArguments(
                    code: """
                        const listed = await tools.sessions.listSessions({});
                        const checked = await tools.sessions.checkSession({ id: "\(sender.id.ulidString)" });
                        const firstRead = await tools.sessions.readInbox({});
                        const secondRead = await tools.sessions.readInbox({});
                        return { listed, checked, firstRead, secondRead };
                        """))
        }

        let report = try RunOutput.decoded(SnippetReport.self, from: output)
        #expect(report.listed.contains(sender.id.ulidString), "listed was: \(report.listed)")
        #expect(report.checked.contains(Self.reviewTitle), "checked was: \(report.checked)")
        #expect(report.firstRead.contains(Self.messageText), "firstRead was: \(report.firstRead)")
        #expect(report.secondRead == Self.emptyInboxText)
    }
}
