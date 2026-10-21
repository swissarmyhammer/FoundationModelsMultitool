import Foundation
import FoundationModels
import FoundationModelsExtras
import Testing
import ULID

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Coverage for the change operations of ``SessionsTool`` — `start session`,
/// `tag session`, `untag session`, `rename session` and `archive session` —
/// over an `InMemorySessionDirectory`.
///
/// Each case reads the state of the directory after the call, so it proves
/// the change and not only the text of the answer. The snippet case calls each
/// verb as `tools.sessions.<verb>` in one `runCode` snippet.
@Suite("SessionsToolChangeTests", .ownsTemporaryDirectories)
struct SessionsToolChangeTests {
    // MARK: - Shared test constants

    /// The shared fixtures of the `sessions` tool tests.
    private typealias Fixtures = SessionsToolFixtures

    /// The folder that a start with no folder and no starter gets.
    private static let launcherFolder = URL(fileURLWithPath: "/work/agents")

    /// The folder that a start names in its `cwd`.
    private static let namedFolder = URL(fileURLWithPath: "/work/other")

    /// An agent id near ``SessionsToolFixtures/agentID``, which the launcher
    /// does not know.
    private static let misspelledAgent = "codr"

    /// The first message of each start.
    private static let firstMessage = "Review the parser and report back."

    /// A tag of the tag cases.
    private static let reviewTag = "review"

    /// A second tag of the tag cases.
    private static let urgentTag = "urgent"

    /// A text that is not a valid tag.
    private static let invalidTag = "not a tag!"

    /// The title of the rename and the start cases.
    private static let title = "Parser review"

    /// The sentence of the answer of a start.
    private static let startSentence = "The session works in the background."

    /// The sentence of the answer of an archive.
    private static let archiveSentence = "The session is archived."

    /// The words of the corrective of a start with no launcher.
    private static let noLauncherWords = "cannot start a session"

    /// The code-mode verb name that each unknown-session corrective names.
    private static let listSessionsVerb = "listSessions"

    /// The code-mode verb name that the unknown-agent corrective names.
    private static let findAgentsVerb = "findAgents"

    /// A session id no session has.
    private static let absentID = ULID()

    // MARK: - Helpers

    /// A directory whose launcher knows ``SessionsToolFixtures/agentID`` and
    /// the default agent.
    ///
    /// - Returns: The directory.
    private static func directoryWithLauncher() -> InMemorySessionDirectory {
        InMemorySessionDirectory(
            launcher: InMemorySessionDirectory.Launcher(
                agentIDs: [Fixtures.agentID], defaultWorkingDirectory: launcherFolder))
    }

    /// The sessions that `starter` started.
    ///
    /// - Parameters:
    ///   - starter: The session that started them.
    ///   - directory: The directory.
    /// - Returns: Their summaries.
    /// - Throws: What `sessions(matching:)` throws.
    private static func sessions(
        startedBy starter: ULID, in directory: InMemorySessionDirectory
    ) async throws -> [SessionSummary] {
        try await directory.sessions(matching: SessionQuery(startedBy: starter))
    }

    /// The summary of `id`, which the case expects to exist.
    ///
    /// - Parameters:
    ///   - id: The session id.
    ///   - directory: The directory.
    /// - Returns: The summary.
    /// - Throws: When no session has the id.
    private static func summary(of id: ULID, in directory: InMemorySessionDirectory) async throws -> SessionSummary {
        try #require(try await directory.summary(of: id))
    }

    // MARK: - start session

    @Test("start session starts a root session of the agent in the folder of the caller, started by the caller")
    func startSessionStartsASessionInTheFolderOfTheCaller() async throws {
        let directory = Self.directoryWithLauncher()
        let tool = try SessionsTool(directory: directory)

        let (output, started) = try await Fixtures.asCaller(in: directory) { callerID in
            let output = try await tool.call(
                arguments: Fixtures.payload(
                    "start session", [("agent", Fixtures.agentID), ("message", Self.firstMessage)]))
            return (output, try await Self.sessions(startedBy: callerID, in: directory))
        }

        let session = try #require(started.first)
        #expect(started.count == 1)
        #expect(session.agentID == Fixtures.agentID)
        #expect(session.workingDirectory == Fixtures.workingFolder)
        #expect(session.origin == .tool)
        #expect(session.kind == .root)
        #expect(output.contains(session.id.ulidString), "output was: \(output)")
        #expect(output.contains(Self.startSentence), "output was: \(output)")
    }

    @Test("start session with a cwd, tags and a title starts the session with them")
    func startSessionTakesTheFolderTheTagsAndTheTitle() async throws {
        let directory = Self.directoryWithLauncher()
        let tool = try SessionsTool(directory: directory)

        let started = try await Fixtures.asCaller(in: directory) { callerID in
            _ = try await tool.call(
                arguments: Fixtures.payload(
                    "start session",
                    [
                        ("agent", Fixtures.agentID), ("cwd", Self.namedFolder.path), ("message", Self.firstMessage),
                        ("tags", [Self.reviewTag]), ("title", Self.title),
                    ]))
            return try await Self.sessions(startedBy: callerID, in: directory)
        }

        let session = try #require(started.first)
        #expect(session.workingDirectory.path == Self.namedFolder.path)
        #expect(session.tags == [Self.reviewTag])
        #expect(session.title == Self.title)
    }

    @Test("start session reads an agent id written as @agent with space around it")
    func startSessionReadsAnAgentAddress() async throws {
        let directory = Self.directoryWithLauncher()
        let tool = try SessionsTool(directory: directory)

        let started = try await Fixtures.asCaller(in: directory) { callerID in
            _ = try await tool.call(
                arguments: Fixtures.payload(
                    "start session", [("agent", " @\(Fixtures.agentID) "), ("message", Self.firstMessage)]))
            return try await Self.sessions(startedBy: callerID, in: directory)
        }

        #expect(started.map(\.agentID) == [Fixtures.agentID])
    }

    @Test("start session with no launcher gives a corrective, not a thrown error, and starts nothing")
    func startSessionWithNoLauncherIsACorrective() async throws {
        let directory = InMemorySessionDirectory()
        let tool = try SessionsTool(directory: directory)

        let (output, started) = try await Fixtures.asCaller(in: directory) { callerID in
            let output = try await tool.call(arguments: Fixtures.payload("start session", [("message", Self.firstMessage)]))
            return (output, try await Self.sessions(startedBy: callerID, in: directory))
        }

        #expect(output.contains(Self.noLauncherWords), "output was: \(output)")
        #expect(started.isEmpty)
    }

    @Test("start session of an unknown agent gives a corrective with the near names and findAgents")
    func startSessionOfAnUnknownAgentNamesTheNearNames() async throws {
        let directory = Self.directoryWithLauncher()
        let tool = try SessionsTool(directory: directory)

        let output = try await Fixtures.asCaller(in: directory) { _ in
            try await tool.call(
                arguments: Fixtures.payload(
                    "start session", [("agent", Self.misspelledAgent), ("message", Self.firstMessage)]))
        }

        #expect(output.contains(Self.misspelledAgent), "output was: \(output)")
        #expect(output.contains(Fixtures.agentID), "output was: \(output)")
        #expect(output.contains(Self.findAgentsVerb), "output was: \(output)")
    }

    @Test("start session with a blank first message gives a corrective and starts nothing")
    func startSessionWithABlankMessageIsACorrective() async throws {
        let directory = Self.directoryWithLauncher()
        let tool = try SessionsTool(directory: directory)

        let (output, started) = try await Fixtures.asCaller(in: directory) { callerID in
            let output = try await tool.call(arguments: Fixtures.payload("start session", [("message", "  ")]))
            return (output, try await Self.sessions(startedBy: callerID, in: directory))
        }

        #expect(output.contains("message"), "output was: \(output)")
        #expect(started.isEmpty)
    }

    @Test("start session with no ToolContext gives a corrective and starts nothing")
    func startSessionWithNoCallerIsACorrective() async throws {
        let directory = Self.directoryWithLauncher()
        let tool = try SessionsTool(directory: directory)

        let output = try await tool.call(arguments: Fixtures.payload("start session", [("message", Self.firstMessage)]))

        #expect(output.contains("session"), "output was: \(output)")
        #expect(try await directory.sessions(matching: SessionQuery(includesRecorded: true)).isEmpty)
    }

    // MARK: - tag session and untag session

    @Test("tag session adds the tags to the session and gives the new tag set")
    func tagSessionAddsTheTags() async throws {
        let directory = InMemorySessionDirectory()
        let other = Fixtures.summary(tags: [Self.urgentTag])
        directory.register(other)
        let tool = try SessionsTool(directory: directory)

        let output = try await Fixtures.asCaller(in: directory) { _ in
            try await tool.call(
                arguments: Fixtures.payload("tag session", [("id", other.id.ulidString), ("tags", [Self.reviewTag])]))
        }

        #expect(try await Self.summary(of: other.id, in: directory).tags == [Self.reviewTag, Self.urgentTag])
        #expect(output.contains(Self.reviewTag), "output was: \(output)")
        #expect(output.contains(Self.urgentTag), "output was: \(output)")
    }

    @Test("tag session with no id tags the caller session")
    func tagSessionWithNoIDTagsTheCaller() async throws {
        let directory = InMemorySessionDirectory()
        let tool = try SessionsTool(directory: directory)

        let callerID = try await Fixtures.asCaller(in: directory) { callerID in
            _ = try await tool.call(arguments: Fixtures.payload("tag session", [("tags", [Self.reviewTag])]))
            return callerID
        }

        #expect(try await Self.summary(of: callerID, in: directory).tags == [Self.reviewTag])
    }

    @Test("tag session reads a tag written as #tag with space around it")
    func tagSessionReadsAHashTag() async throws {
        let directory = InMemorySessionDirectory()
        let tool = try SessionsTool(directory: directory)

        let callerID = try await Fixtures.asCaller(in: directory) { callerID in
            _ = try await tool.call(arguments: Fixtures.payload("tag session", [("tags", [" #\(Self.reviewTag) "])]))
            return callerID
        }

        #expect(try await Self.summary(of: callerID, in: directory).tags == [Self.reviewTag])
    }

    @Test("tag session with an invalid tag gives a corrective and changes no tag")
    func tagSessionWithAnInvalidTagIsACorrective() async throws {
        let directory = InMemorySessionDirectory()
        let tool = try SessionsTool(directory: directory)

        let (output, callerID) = try await Fixtures.asCaller(in: directory) { callerID in
            (try await tool.call(arguments: Fixtures.payload("tag session", [("tags", [Self.invalidTag])])), callerID)
        }

        #expect(output.contains(Self.invalidTag), "output was: \(output)")
        #expect(try await Self.summary(of: callerID, in: directory).tags.isEmpty)
    }

    @Test("tag session with no tag gives a corrective")
    func tagSessionWithNoTagIsACorrective() async throws {
        let directory = InMemorySessionDirectory()
        let tool = try SessionsTool(directory: directory)

        let output = try await Fixtures.asCaller(in: directory) { _ in
            try await tool.call(arguments: Fixtures.payload("tag session", [("tags", ["  "])]))
        }

        #expect(output.contains("tag"), "output was: \(output)")
    }

    @Test("tag session with no ToolContext gives a corrective and changes no tag")
    func tagSessionWithNoCallerIsACorrective() async throws {
        let directory = InMemorySessionDirectory()
        let other = Fixtures.summary()
        directory.register(other)
        let tool = try SessionsTool(directory: directory)

        let output = try await tool.call(
            arguments: Fixtures.payload("tag session", [("id", other.id.ulidString), ("tags", [Self.reviewTag])]))

        #expect(output.contains("session"), "output was: \(output)")
        #expect(try await Self.summary(of: other.id, in: directory).tags.isEmpty)
    }

    @Test("untag session removes the tags from the session and gives the tags that stay")
    func untagSessionRemovesTheTags() async throws {
        let directory = InMemorySessionDirectory()
        let other = Fixtures.summary(tags: [Self.reviewTag, Self.urgentTag])
        directory.register(other)
        let tool = try SessionsTool(directory: directory)

        let output = try await Fixtures.asCaller(in: directory) { _ in
            try await tool.call(
                arguments: Fixtures.payload("untag session", [("id", other.id.ulidString), ("tags", [Self.urgentTag])]))
        }

        #expect(try await Self.summary(of: other.id, in: directory).tags == [Self.reviewTag])
        #expect(output.contains(Self.reviewTag), "output was: \(output)")
        #expect(!output.contains(Self.urgentTag), "output was: \(output)")
    }

    @Test("untag session of the last tag says that the session has no tags")
    func untagSessionOfTheLastTagSaysNoTags() async throws {
        let directory = InMemorySessionDirectory()
        let other = Fixtures.summary(tags: [Self.reviewTag])
        directory.register(other)
        let tool = try SessionsTool(directory: directory)

        let output = try await Fixtures.asCaller(in: directory) { _ in
            try await tool.call(
                arguments: Fixtures.payload("untag session", [("id", other.id.ulidString), ("tags", [Self.reviewTag])]))
        }

        #expect(try await Self.summary(of: other.id, in: directory).tags.isEmpty)
        #expect(output.contains("no tags"), "output was: \(output)")
    }

    // MARK: - rename session

    @Test("rename session sets the title of the session")
    func renameSessionSetsTheTitle() async throws {
        let directory = InMemorySessionDirectory()
        let other = Fixtures.summary()
        directory.register(other)
        let tool = try SessionsTool(directory: directory)

        let output = try await Fixtures.asCaller(in: directory) { _ in
            try await tool.call(
                arguments: Fixtures.payload("rename session", [("id", other.id.ulidString), ("title", Self.title)]))
        }

        #expect(try await Self.summary(of: other.id, in: directory).title == Self.title)
        #expect(output.contains(Self.title), "output was: \(output)")
    }

    @Test("rename session with no id renames the caller session, and trims the title")
    func renameSessionWithNoIDRenamesTheCaller() async throws {
        let directory = InMemorySessionDirectory()
        let tool = try SessionsTool(directory: directory)

        let callerID = try await Fixtures.asCaller(in: directory) { callerID in
            _ = try await tool.call(arguments: Fixtures.payload("rename session", [("title", "  \(Self.title)\n")]))
            return callerID
        }

        #expect(try await Self.summary(of: callerID, in: directory).title == Self.title)
    }

    @Test("rename session with a blank title gives a corrective and keeps the title")
    func renameSessionWithABlankTitleIsACorrective() async throws {
        let directory = InMemorySessionDirectory()
        let other = Fixtures.summary(title: Self.title)
        directory.register(other)
        let tool = try SessionsTool(directory: directory)

        let output = try await Fixtures.asCaller(in: directory) { _ in
            try await tool.call(arguments: Fixtures.payload("rename session", [("id", other.id.ulidString), ("title", " ")]))
        }

        #expect(output.contains("title"), "output was: \(output)")
        #expect(try await Self.summary(of: other.id, in: directory).title == Self.title)
    }

    // MARK: - archive session

    @Test("archive session archives the session and gives its id, agent, folder and the archive sentence")
    func archiveSessionArchivesTheSession() async throws {
        let directory = InMemorySessionDirectory()
        let other = Fixtures.summary()
        directory.register(other)
        let tool = try SessionsTool(directory: directory)

        let output = try await Fixtures.asCaller(in: directory) { _ in
            try await tool.call(arguments: Fixtures.payload("archive session", [("id", other.id.ulidString)]))
        }

        let archived = try await Self.summary(of: other.id, in: directory)
        #expect(archived.state == .archived)
        #expect(!archived.isLive)
        #expect(output.contains(other.id.ulidString), "output was: \(output)")
        #expect(output.contains(Fixtures.agentID), "output was: \(output)")
        #expect(output.contains(Fixtures.workingFolder.path), "output was: \(output)")
        #expect(output.contains(Self.archiveSentence), "output was: \(output)")
    }

    @Test("archive session of a session that is archived already gives a corrective that says so")
    func archiveSessionOfAnArchivedSessionIsACorrective() async throws {
        let directory = InMemorySessionDirectory()
        let other = Fixtures.summary()
        directory.register(other)
        _ = try await directory.archive(other.id, by: .user(clientID: "test"))
        let tool = try SessionsTool(directory: directory)

        let output = try await Fixtures.asCaller(in: directory) { _ in
            try await tool.call(arguments: Fixtures.payload("archive session", [("id", other.id.ulidString)]))
        }

        #expect(output.contains("archived already"), "output was: \(output)")
        #expect(!output.contains(Self.archiveSentence), "output was: \(output)")
    }

    @Test("archive session of an unknown id gives a corrective that names listSessions")
    func archiveSessionOfAnUnknownIDNamesListSessions() async throws {
        let directory = InMemorySessionDirectory()
        let tool = try SessionsTool(directory: directory)

        let output = try await Fixtures.asCaller(in: directory) { _ in
            try await tool.call(arguments: Fixtures.payload("archive session", [("id", Self.absentID.ulidString)]))
        }

        #expect(output.contains(Self.absentID.ulidString), "output was: \(output)")
        #expect(output.contains(Self.listSessionsVerb), "output was: \(output)")
    }

    @Test("archive session with no ToolContext gives a corrective and archives nothing")
    func archiveSessionWithNoCallerIsACorrective() async throws {
        let directory = InMemorySessionDirectory()
        let other = Fixtures.summary()
        directory.register(other)
        let tool = try SessionsTool(directory: directory)

        let output = try await tool.call(arguments: Fixtures.payload("archive session", [("id", other.id.ulidString)]))

        #expect(output.contains("session"), "output was: \(output)")
        #expect(try await Self.summary(of: other.id, in: directory).state == .idle)
    }

    // MARK: - The snippet through withSessions

    /// What the snippet reports about the five verbs.
    private struct SnippetReport: Decodable {
        /// What `startSession` gave.
        let started: String

        /// What `tagSession` gave.
        let tagged: String

        /// What `untagSession` gave.
        let untagged: String

        /// What `renameSession` gave.
        let renamed: String

        /// What `archiveSession` gave.
        let archived: String
    }

    @Test(
        "tools.sessions.startSession, tagSession, untagSession, renameSession and archiveSession change the directory in one runCode snippet"
    )
    func theChangeVerbsWorkInASnippet() async throws {
        let directory = Self.directoryWithLauncher()
        let other = Fixtures.summary(tags: [Self.urgentTag])
        directory.register(other)
        let tool = try SessionsTool(directory: directory)
        let multiTool = MultiTool(registry: try MultiTool.Builder().withSessions(tool).buildRegistry())
        let id = other.id.ulidString

        let (output, started) = try await Fixtures.asCaller(in: directory) { callerID in
            let output = try await multiTool.call(
                arguments: RunCodeArguments(
                    code: """
                        const started = await tools.sessions.startSession({ agent: "\(Fixtures.agentID)", message: "\(Self.firstMessage)" });
                        const tagged = await tools.sessions.tagSession({ id: "\(id)", tags: ["\(Self.reviewTag)"] });
                        const untagged = await tools.sessions.untagSession({ id: "\(id)", tags: ["\(Self.urgentTag)"] });
                        const renamed = await tools.sessions.renameSession({ id: "\(id)", title: "\(Self.title)" });
                        const archived = await tools.sessions.archiveSession({ id: "\(id)" });
                        return { started, tagged, untagged, renamed, archived };
                        """))
            return (output, try await Self.sessions(startedBy: callerID, in: directory))
        }

        let report = try RunOutput.decoded(SnippetReport.self, from: output)
        let changed = try await Self.summary(of: other.id, in: directory)
        #expect(started.count == 1, "started was: \(report.started)")
        #expect(changed.tags == [Self.reviewTag], "tagged was: \(report.tagged), untagged was: \(report.untagged)")
        #expect(changed.title == Self.title, "renamed was: \(report.renamed)")
        #expect(changed.state == .archived, "archived was: \(report.archived)")
    }
}
