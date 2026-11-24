// `SessionsToolExternalTests` — the `list external sessions`,
// `count external sessions`, `read external session`, `continue external session` and
// `rebuild external session index` operations of the `sessions` tool (D212, design sections 5.8 and 7).
//
// Each case uses its own `InMemorySessionDirectory` and its own fake host
// from the fixtures. Each case reads the calls of the fake after the call of
// the tool, so it proves what the tool asked the host to do. No case waits
// for a time.

import Foundation
import FoundationModels
import FoundationModelsExtras
import Testing

@testable import FoundationModelsMultitool

/// Behavioral tests for the external session operations of ``SessionsTool``.
@Suite("SessionsToolExternalTests", .ownsTemporaryDirectories)
struct SessionsToolExternalTests {

    // MARK: - Constants

    /// The shared fixtures of the `sessions` tool tests.
    private typealias Fixtures = SessionsToolFixtures

    /// The fake host type.
    private typealias Host = FakeExternalSessionHost

    /// The op string of `list external sessions`.
    private static let listOp = "list external sessions"

    /// The op string of `count external sessions`.
    private static let countOp = "count external sessions"

    /// The op string of `read external session`.
    private static let readOp = "read external session"

    /// The op string of `continue external session`.
    private static let continueOp = "continue external session"

    /// The op string of `rebuild external session index`.
    private static let rebuildOp = "rebuild external session index"

    /// The day and the time of ``Fixtures/fixedDate`` in the answers.
    private static let fixedDateText = "2027-01-15T08:00:00Z"

    /// The folder of a continue case: not the folder of the source.
    private static let otherFolder = URL(fileURLWithPath: "/work/other")

    /// The fields that name the typed session of the fake.
    private static var typedSessionFields: [(String, any ConvertibleToGeneratedContent)] {
        [("source", Host.claudeCode), ("id", Host.typedSession.sourceID)]
    }

    /// The line of the typed session of the fake.
    private static let typedLine =
        "claude-code a1b2c3 \"Fix the parser\" (/work/project) \(fixedDateText) – branch main"

    /// The text of the second time of a continuation of the fake.
    private static let laterDateText = "2027-01-15T09:00:00Z"

    /// The line of the automated session of the fake.
    private static let automatedLine = "codex rollout-42 (no text) (no folder) \(fixedDateText) – automated, found"

    /// The words of the corrective of a source with no access.
    private static let allowAccessWords = "Ask the user to run Allow Access to Claude Code Sessions… of the File menu."

    // MARK: - Helpers

    /// Calls one operation as the caller, with a tool over a new directory.
    ///
    /// - Parameters:
    ///   - op: The op string.
    ///   - fields: The fields of the operation.
    ///   - host: The external session host of the tool, or `nil` for none.
    /// - Returns: The answer of the tool.
    /// - Throws: What the tool throws.
    private static func callAsCaller(
        _ op: String, _ fields: [(String, any ConvertibleToGeneratedContent)] = [],
        host: (any ExternalSessionHost)?
    ) async throws -> String {
        let directory = Fixtures.directoryWithLauncher()
        let tool = try SessionsTool(directory: directory, externalSessionHost: host)
        return try await Fixtures.asCaller(in: directory) { _ in
            try await tool.call(arguments: Fixtures.payload(op, fields))
        }
    }

    /// The fields of a read of the typed session.
    ///
    /// - Parameter extra: The other fields.
    /// - Returns: The fields.
    private static func readFields(
        _ extra: [(String, any ConvertibleToGeneratedContent)] = []
    ) -> [(String, any ConvertibleToGeneratedContent)] {
        typedSessionFields + extra
    }

    /// The text of one turn of ``FakeExternalSessionHost/turns(_:)`` in the
    /// answer of a read: the thought does not show.
    ///
    /// - Parameter number: The number of the turn.
    /// - Returns: The text.
    private static func turnText(_ number: Int) -> String {
        """
        Turn \(number)
        user: prompt \(number)
        agent: answer \(number)
        tool: Read file\(number).swift
        tool result (completed): contents \(number)
        """
    }

    // MARK: - list external sessions

    @Test("list external sessions gives one line for each typed session, and the advice")
    func theListGivesOneLineForEachTypedSession() async throws {
        let output = try await Self.callAsCaller(Self.listOp, host: Host())

        #expect(
            output == """
                \(Self.typedLine)
                \(SessionsToolText.externalListAdvice)
                """)
    }

    @Test("list external sessions gives each session that a continue made from a session, the oldest first")
    func theListGivesTheContinuedSessions() async throws {
        let output = try await Self.callAsCaller(Self.listOp, host: Host(sessions: [Host.continuedSession]))

        let first = Host.firstContinuation.sessionID.ulidString
        let second = Host.secondContinuation.sessionID.ulidString
        #expect(
            output == """
                \(Self.typedLine), continued \(Self.fixedDateText) as \(first), continued \(Self.laterDateText) as \(second)
                \(SessionsToolText.externalListAdvice)
                """)
    }

    @Test("list external sessions with automated true also gives the automated sessions")
    func theListWithAutomatedGivesTheAutomatedSessions() async throws {
        let output = try await Self.callAsCaller(Self.listOp, [("automated", true)], host: Host())

        #expect(
            output == """
                \(Self.typedLine)
                \(Self.automatedLine)
                \(SessionsToolText.externalListAdvice)
                """)
    }

    @Test("list external sessions with no argument asks the host for 20 typed sessions of each source and folder")
    func theListWithNoArgumentAsksForTheDefaults() async throws {
        let host = Host()

        _ = try await Self.callAsCaller(Self.listOp, host: host)

        #expect(host.queries == [ExternalSessionQuery(limit: 20)])
    }

    @Test("list external sessions with folder . asks for the sessions of the folder of the caller")
    func theListWithTheDotFolderAsksForTheCallerFolder() async throws {
        let host = Host()

        _ = try await Self.callAsCaller(Self.listOp, [("folder", ".")], host: host)

        #expect(host.queries.map(\.folder?.path) == [Fixtures.workingFolder.path])
    }

    @Test("list external sessions gives the source and the limit to the host")
    func theListGivesTheSourceAndTheLimit() async throws {
        let host = Host()

        _ = try await Self.callAsCaller(Self.listOp, [("source", Host.codex), ("limit", 5)], host: host)

        #expect(host.queries == [ExternalSessionQuery(source: Host.codex, limit: 5)])
    }

    @Test("list external sessions gives the index state in one line when the index is not complete")
    func theListGivesTheIndexStateWhenTheIndexIsNotComplete() async throws {
        let index = ExternalSessionIndexState(filesFound: 400, filesRead: 120, isComplete: false)

        let output = try await Self.callAsCaller(Self.listOp, host: Host(indexState: index))

        #expect(
            output == """
                \(Self.typedLine)
                \(SessionsToolText.incompleteIndexLine(index))
                \(SessionsToolText.externalListAdvice)
                """)
        #expect(SessionsToolText.incompleteIndexLine(index).contains("it read 120 of 400 session files"))
    }

    @Test("list external sessions of a folder gives the progress of that folder, not of each root")
    func theListOfAFolderGivesTheFolderIndexState() async throws {
        let index = ExternalSessionIndexState(filesFound: 400, filesRead: 120, isComplete: false)
        let folder = ExternalSessionIndexState(filesFound: 12, filesRead: 5, isComplete: false)

        let output = try await Self.callAsCaller(
            Self.listOp, [("folder", ".")], host: Host(indexState: index, folderIndexState: folder))

        #expect(output.contains(SessionsToolText.incompleteIndexLine(folder)), "\(output)")
        #expect(!output.contains(SessionsToolText.incompleteIndexLine(index)), "\(output)")
    }

    @Test("list external sessions gives the Allow Access corrective for each source with no access")
    func theListGivesTheAccessLineOfEachUnreadableSource() async throws {
        let output = try await Self.callAsCaller(Self.listOp, host: Host(unreadableSources: [Host.claudeCode]))

        #expect(
            output == """
                \(Self.typedLine)
                \(SessionsToolText.noExternalSourceAccess(Host.claudeCode))
                \(SessionsToolText.externalListAdvice)
                """)
        #expect(output.contains(Self.allowAccessWords))
    }

    @Test("list external sessions with a relative folder gives the corrective and asks the host nothing")
    func theListWithARelativeFolderGivesTheCorrective() async throws {
        let host = Host()

        let output = try await Self.callAsCaller(Self.listOp, [("folder", "work/project")], host: host)

        #expect(output.contains("work/project"))
        #expect(host.queries.isEmpty)
    }

    // MARK: - count external sessions

    @Test("count external sessions with no argument counts each source and each folder")
    func theCountWithNoArgumentCountsEachScope() async throws {
        let host = Host()

        let output = try await Self.callAsCaller(Self.countOp, host: host)

        #expect(output == "Sessions in the index: 1 typed, 1 automated.")
        #expect(host.countScopes == [Host.CountScope(source: nil, folder: nil)])
    }

    @Test("count external sessions gives the source and the folder of the caller for folder .")
    func theCountGivesTheSourceAndTheDotFolder() async throws {
        let host = Host()

        let output = try await Self.callAsCaller(
            Self.countOp, [("agent", Host.claudeCode), ("folder", ".")], host: host)

        #expect(output == "Sessions in the index of claude-code in /work/project: 1 typed, 0 automated.")
        #expect(host.countScopes.map(\.source) == [Host.claudeCode])
        #expect(host.countScopes.map(\.folder?.path) == [Fixtures.workingFolder.path])
    }

    @Test("count external sessions gives the progress of the scope when the index is not complete")
    func theCountGivesTheProgressWhenTheIndexIsNotComplete() async throws {
        let folder = ExternalSessionIndexState(filesFound: 12, filesRead: 5, isComplete: false)

        let output = try await Self.callAsCaller(
            Self.countOp, [("folder", ".")], host: Host(folderIndexState: folder))

        #expect(
            output == """
                Sessions in the index in /work/project: 1 typed, 0 automated.
                \(SessionsToolText.incompleteIndexLine(folder))
                """)
    }

    @Test("count external sessions with a relative folder gives the corrective and asks the host nothing")
    func theCountWithARelativeFolderGivesTheCorrective() async throws {
        let host = Host()

        let output = try await Self.callAsCaller(Self.countOp, [("folder", "work/project")], host: host)

        #expect(output.contains("work/project"))
        #expect(host.countScopes.isEmpty)
    }

    // MARK: - read external session

    @Test("read external session gives the first 10 turns, and stops the host stream after the range")
    func theReadGivesTheFirstTurnsAndStopsTheHostStream() async throws {
        let host = Host(batches: Host.turns(12), finishesUpdates: false)
        var terminations = host.updateTerminations.makeAsyncIterator()

        let output = try await Self.callAsCaller(Self.readOp, Self.readFields(), host: host)
        let stoppedByTheRead = await terminations.next()

        #expect(
            output
                == (["The session a1b2c3 of claude-code: turns 1 to 10."] + (1...10).map(Self.turnText) + [
                    "More turns follow. To read more, use read external session with fromTurn 11."
                ]).joined(separator: "\n\n"))
        #expect(stoppedByTheRead == true)
        #expect(host.updateSessions == [Host.typedSession.id])
    }

    @Test("read external session gives each session that a continue made from it, after the first line")
    func theReadGivesTheContinuedSessions() async throws {
        let host = Host(sessions: [Host.continuedSession], batches: Host.turns(1))

        let output = try await Self.callAsCaller(Self.readOp, Self.readFields(), host: host)

        let first = Host.firstContinuation.sessionID.ulidString
        let second = Host.secondContinuation.sessionID.ulidString
        #expect(
            output
                == [
                    "The session a1b2c3 of claude-code: turns 1 to 1.",
                    """
                    Continued \(Self.fixedDateText) as the session \(first).
                    Continued \(Self.laterDateText) as the session \(second).
                    """,
                    Self.turnText(1), "This is the last turn of the session.",
                ].joined(separator: "\n\n"))
        #expect(host.queries == [ExternalSessionQuery(source: Host.claudeCode, automated: true, limit: 50)])
    }

    @Test("read external session gives the absolute path of the file after the first line")
    func theReadGivesTheFilePath() async throws {
        let output = try await Self.callAsCaller(
            Self.readOp, Self.readFields(), host: Host(sessions: [Host.filedSession], batches: Host.turns(1)))

        #expect(
            output
                == [
                    "The session a1b2c3 of claude-code: turns 1 to 1.",
                    "The file of the session is /Users/user/.claude/projects/-work-project/a1b2c3.jsonl.",
                    Self.turnText(1), "This is the last turn of the session.",
                ].joined(separator: "\n\n"))
    }

    @Test("read external session after the last turn also gives the sessions that a continue made")
    func theReadAfterTheLastTurnGivesTheContinuedSessions() async throws {
        let output = try await Self.callAsCaller(
            Self.readOp, Self.readFields([("fromTurn", 9)]),
            host: Host(sessions: [Host.continuedSession], batches: Host.turns(3)))

        #expect(
            output.hasPrefix(
                "The session a1b2c3 of claude-code has 3 turns. Give a fromTurn from 1 to 3.\n\nContinued "))
    }

    @Test("read external session reads each page of the index one time, also when the cursor does not change")
    func theReadStopsAtACursorThatRepeats() async throws {
        let host = Host(sessions: [Host.typedSession], nextCursor: "page-2", batches: Host.turns(1))

        let output = try await Self.callAsCaller(Self.readOp, Self.readFields(), host: host)

        #expect(output.hasPrefix("The session a1b2c3 of claude-code: turns 1 to 1.\n\nTurn 1"))
        #expect(host.queries.count == 1)
    }

    @Test("read external session gives the range of fromTurn and turns, and tells the last turn")
    func theReadGivesTheRangeOfTheArguments() async throws {
        let host = Host(batches: Host.turns(3))

        let output = try await Self.callAsCaller(
            Self.readOp, Self.readFields([("fromTurn", 2), ("turns", 5)]), host: host)

        #expect(
            output
                == [
                    "The session a1b2c3 of claude-code: turns 2 to 3.", Self.turnText(2), Self.turnText(3),
                    "This is the last turn of the session.",
                ].joined(separator: "\n\n"))
    }

    @Test("read external session after the last turn tells the number of turns")
    func theReadAfterTheLastTurnTellsTheCount() async throws {
        let output = try await Self.callAsCaller(
            Self.readOp, Self.readFields([("fromTurn", 9)]), host: Host(batches: Host.turns(3)))

        #expect(output == "The session a1b2c3 of claude-code has 3 turns. Give a fromTurn from 1 to 3.")
    }

    @Test("read external session gives a turn of the range whose entries the text does not show")
    func theReadGivesATurnWithNoShownEntry() async throws {
        let batches = [
            ExternalSessionUpdateBatch(entries: [
                Host.entry("agent_thought_chunk", text: "a thought before the first prompt"),
                Host.entry("user_message_chunk", text: "prompt 2"),
                Host.entry("agent_message_chunk", text: "answer 2"),
            ])
        ]

        let output = try await Self.callAsCaller(
            Self.readOp, Self.readFields([("turns", 1)]), host: Host(batches: batches))

        #expect(
            output
                == [
                    "The session a1b2c3 of claude-code: turns 1 to 1.", "Turn 1",
                    "More turns follow. To read more, use read external session with fromTurn 2.",
                ].joined(separator: "\n\n"))
    }

    @Test("read external session cuts the text at the size limit, and tells the next turn")
    func theReadCutsTheTextAtTheSizeLimit() async throws {
        let longAnswer = String(repeating: "a", count: SessionsToolContext.maximumExternalReadLength * 2)
        let batches = [
            ExternalSessionUpdateBatch(entries: [
                Host.entry("user_message_chunk", text: "prompt 1"),
                Host.entry("agent_message_chunk", text: longAnswer),
            ])
        ] + Host.turns(2)

        let output = try await Self.callAsCaller(Self.readOp, Self.readFields(), host: Host(batches: batches))

        #expect(output.count < SessionsToolContext.maximumExternalReadLength + 400)
        #expect(output.hasPrefix("The session a1b2c3 of claude-code: turns 1 to 1.\n\nTurn 1\nuser: prompt 1\nagent: aaa"))
        #expect(
            output.hasSuffix(
                "The text was cut at the size limit. To read more, use read external session with fromTurn 2."))
    }

    @Test("read external session cuts the text of a long tool result")
    func theReadCutsALongToolResult() async throws {
        let longResult = String(repeating: "r", count: SessionsToolContext.maximumExternalToolTextLength * 3)
        let batches = [
            ExternalSessionUpdateBatch(entries: [
                Host.entry("user_message_chunk", text: "prompt 1"),
                Host.entry("tool_call_update", text: longResult, status: "completed"),
            ])
        ]

        let output = try await Self.callAsCaller(Self.readOp, Self.readFields(), host: Host(batches: batches))

        let cutResult = String(repeating: "r", count: SessionsToolContext.maximumExternalToolTextLength) + "…"
        #expect(output.contains("tool result (completed): \(cutResult)\n"))
    }

    @Test("read external session of a source with no access gives the Allow Access corrective")
    func theReadOfASourceWithNoAccessGivesTheCorrective() async throws {
        let output = try await Self.callAsCaller(
            Self.readOp, Self.readFields(), host: Host(unreadableSources: [Host.claudeCode]))

        #expect(output == SessionsToolText.noExternalSourceAccess(Host.claudeCode))
        #expect(output.contains(Self.allowAccessWords))
    }

    @Test("read external session of a session that the index does not have gives the corrective")
    func theReadOfAnUnknownSessionGivesTheCorrective() async throws {
        let output = try await Self.callAsCaller(
            Self.readOp, [("source", Host.claudeCode), ("id", "no-such-session")], host: Host())

        #expect(
            output
                == SessionsToolText.unknownExternalSession(
                    ExternalSessionID(source: Host.claudeCode, sourceID: "no-such-session")))
    }

    // MARK: - continue external session

    @Test("continue external session calls the host one time with the folder and the name")
    func theContinueCallsTheHostOneTime() async throws {
        let host = Host()

        let output = try await Self.callAsCaller(
            Self.continueOp, Self.typedSessionFields + [("folder", Self.otherFolder.path), ("name", "parser-fix")],
            host: host)

        let requests = host.continueRequests
        #expect(requests.count == 1)
        #expect(requests.first?.session == Host.typedSession.id)
        #expect(requests.first?.folder?.path == Self.otherFolder.path)
        #expect(requests.first?.name == "parser-fix")
        #expect(output.hasPrefix("Continued the session a1b2c3 of claude-code as the new session @"))
        #expect(output.contains("\"parser-fix\""))
        #expect(output.hasSuffix("in /work/other. The source did not change."))
    }

    @Test("continue external session with folder . makes the session in the folder of the caller")
    func theContinueWithTheDotFolderUsesTheCallerFolder() async throws {
        let host = Host()

        _ = try await Self.callAsCaller(Self.continueOp, Self.typedSessionFields + [("folder", ".")], host: host)

        #expect(host.continueRequests.map(\.folder?.path) == [Fixtures.workingFolder.path])
    }

    @Test("continue external session of a source with no access gives the Allow Access corrective")
    func theContinueOfASourceWithNoAccessGivesTheCorrective() async throws {
        let output = try await Self.callAsCaller(
            Self.continueOp, Self.typedSessionFields, host: Host(unreadableSources: [Host.claudeCode]))

        #expect(output == SessionsToolText.noExternalSourceAccess(Host.claudeCode))
        #expect(output.contains(Self.allowAccessWords))
    }

    @Test("continue external session with a blank id gives the corrective and calls the host no time")
    func theContinueWithABlankIDGivesTheCorrective() async throws {
        let host = Host()

        let output = try await Self.callAsCaller(
            Self.continueOp, [("source", Host.claudeCode), ("id", "  ")], host: host)

        #expect(output == SessionsToolText.blankText(SessionsToolText.externalIDParameter))
        #expect(host.continueRequests.isEmpty)
    }

    // MARK: - rebuild external session index

    @Test("rebuild external session index calls the host one time with the source, and tells that the read continues")
    func theRebuildCallsTheHostOneTime() async throws {
        let host = Host()

        let output = try await Self.callAsCaller(Self.rebuildOp, [("source", " \(Host.codex) ")], host: host)

        #expect(host.rebuildSources == [Host.codex])
        #expect(output == SessionsToolText.startedExternalIndexRebuild(Host.codex))
        #expect(output.hasPrefix("The rebuild of the index of the sessions of codex started."))
    }

    @Test("rebuild external session index takes the alias agent for the source")
    func theRebuildTakesTheAgentAlias() async throws {
        let host = Host()

        _ = try await Self.callAsCaller(Self.rebuildOp, [("agent", Host.claudeCode)], host: host)

        #expect(host.rebuildSources == [Host.claudeCode])
    }

    @Test("rebuild external session index of a source with no access gives the Allow Access corrective")
    func theRebuildOfASourceWithNoAccessGivesTheCorrective() async throws {
        let output = try await Self.callAsCaller(
            Self.rebuildOp, [("source", Host.claudeCode)], host: Host(unreadableSources: [Host.claudeCode]))

        #expect(output == SessionsToolText.noExternalSourceAccess(Host.claudeCode))
        #expect(output.contains(Self.allowAccessWords))
    }

    @Test("rebuild external session index of a source that the host does not know gives the access corrective")
    func theRebuildOfAnUnknownSourceGivesTheCorrective() async throws {
        let output = try await Self.callAsCaller(Self.rebuildOp, [("source", "gemini")], host: Host())

        #expect(output == SessionsToolText.noExternalSourceAccess("gemini"))
    }

    @Test("rebuild external session index with a blank source gives the corrective and calls the host no time")
    func theRebuildWithABlankSourceGivesTheCorrective() async throws {
        let host = Host()

        let output = try await Self.callAsCaller(Self.rebuildOp, [("source", "  ")], host: host)

        #expect(output == SessionsToolText.blankText(SessionsToolText.externalSourceParameter))
        #expect(host.rebuildSources.isEmpty)
    }

    // MARK: - With no host

    @Test(
        "with no host, each external session operation gives the corrective",
        arguments: [listOp, countOp, readOp, continueOp, rebuildOp])
    func eachOperationWithNoHostGivesTheCorrective(op: String) async throws {
        let output = try await Self.callAsCaller(op, Self.typedSessionFields, host: nil)

        #expect(output == SessionsToolText.noExternalSessionHost)
    }
}
