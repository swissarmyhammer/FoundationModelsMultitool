// `SessionsToolImportTests` — the `list imports` and `import session`
// operations of the `sessions` tool (D209 (l)), and the host protocol
// `SessionImporter`.
//
// Each case uses its own `InMemorySessionDirectory` and its own fake importer
// from the fixtures. The fake makes a real session in the directory, so each
// case reads the name and the short id of the new session from the
// directory. Each case reads the requests and the orders of the fake after
// the call of the tool, so it proves what the tool asked the importer to do.
// No case waits for a time.

import Foundation
import FoundationModels
import FoundationModelsExtras
import Testing
import ULID

@testable import FoundationModelsMultitool

/// Behavioral tests for the import operations of ``SessionsTool``.
@Suite("SessionsToolImportTests", .ownsTemporaryDirectories)
struct SessionsToolImportTests {

    // MARK: - Constants

    /// The shared fixtures of the `sessions` tool tests.
    private typealias Fixtures = SessionsToolFixtures

    /// The op string of `list imports`.
    private static let listOp = "list imports"

    /// The op string of `import session`.
    private static let importOp = "import session"

    /// The source agent of ``titledSource``.
    private static let claudeCode = "claude-code"

    /// The source agent of ``untitledSource``.
    private static let codex = "codex"

    /// The folder of ``untitledSource``: not the folder of the caller.
    private static let otherFolder = URL(fileURLWithPath: "/work/other")

    /// The day and the time of ``Fixtures/fixedDate`` in the answers.
    private static let fixedDateText = "2027-01-15T08:00:00Z"

    /// A source session of Claude Code in the folder of the caller, with a
    /// title.
    private static let titledSource = RecordingSessionImporter.source(
        agent: claudeCode, sourceID: "a1b2c3", title: "Fix the parser", folder: Fixtures.workingFolder, turnCount: 12)

    /// A source session of Codex in a different folder, with no title.
    private static let untitledSource = RecordingSessionImporter.source(
        agent: codex, sourceID: "rollout-42", title: nil, folder: otherFolder, turnCount: 4)

    /// The fields of `import session` that name ``titledSource``.
    private static var titledSourceFields: [(String, any ConvertibleToGeneratedContent)] {
        [("agent", claudeCode), ("source", titledSource.sourceID)]
    }

    /// The text of the failure of a source that the fake does not have.
    private static let unknownSourceID = "no-such-source"

    /// The words of the corrective of a server with no importer.
    private static let noImporterWords = "no session importer"

    /// The name of the UI command that each access corrective names.
    private static let importUICommand = "Import Sessions…"

    // MARK: - Helpers

    /// A fake importer of ``titledSource`` and ``untitledSource`` over
    /// `directory`.
    ///
    /// - Parameters:
    ///   - directory: The directory that gets the new sessions.
    ///   - unreadableSources: The agents whose sessions the fake cannot read.
    ///   - unavailableFolders: The folders in which the fake cannot make a
    ///     session.
    /// - Returns: The importer.
    private static func importer(
        over directory: InMemorySessionDirectory, unreadableSources: [String] = [], unavailableFolders: [URL] = []
    ) -> RecordingSessionImporter {
        RecordingSessionImporter(
            directory: directory, sources: [titledSource, untitledSource], unreadableSources: unreadableSources,
            unavailableFolders: unavailableFolders)
    }

    /// Calls operations one after the other as the caller, with a tool over
    /// `directory`.
    ///
    /// - Parameters:
    ///   - calls: The op string and the fields of each call.
    ///   - importer: The importer of the tool, or `nil` for none.
    ///   - directory: The directory of the tool.
    /// - Returns: The answer of each call, in the order of the calls.
    /// - Throws: What the tool throws.
    private static func callAsCaller(
        _ calls: [(String, [(String, any ConvertibleToGeneratedContent)])],
        importer: (any SessionImporter)?,
        in directory: InMemorySessionDirectory
    ) async throws -> [String] {
        let tool = try SessionsTool(directory: directory, importer: importer)
        return try await Fixtures.asCaller(in: directory) { _ in
            var outputs: [String] = []
            // A loop and not a `map`: each call awaits the tool, in order.
            for (op, fields) in calls {
                outputs.append(try await tool.call(arguments: Fixtures.payload(op, fields)))
            }
            return outputs
        }
    }

    /// Calls one operation as the caller, with a tool over `directory`.
    ///
    /// - Parameters:
    ///   - op: The op string.
    ///   - fields: The fields of the operation.
    ///   - importer: The importer of the tool, or `nil` for none.
    ///   - directory: The directory of the tool.
    /// - Returns: The answer of the tool.
    /// - Throws: What the tool throws.
    private static func callAsCaller(
        _ op: String,
        _ fields: [(String, any ConvertibleToGeneratedContent)] = [],
        importer: (any SessionImporter)?,
        in directory: InMemorySessionDirectory = Fixtures.directoryWithLauncher()
    ) async throws -> String {
        try #require(try await callAsCaller([(op, fields)], importer: importer, in: directory).first)
    }

    /// The imported sessions of a directory. The fixed clock gives each
    /// session the same time, so the order is the order of the ids.
    ///
    /// - Parameter directory: The directory.
    /// - Returns: Each session with a provenance.
    private static func importedSessions(in directory: InMemorySessionDirectory) async throws -> [SessionSummary] {
        try await directory.sessions(matching: SessionQuery(includesRecorded: true))
            .filter { $0.importedFrom != nil }
            .sorted { $0.id.ulidString < $1.id.ulidString }
    }

    // MARK: - list imports

    @Test("list imports gives one line for each source session, and the import advice")
    func listImportsGivesOneLineForEachSource() async throws {
        let directory = Fixtures.directoryWithLauncher()

        let output = try await Self.callAsCaller(Self.listOp, importer: Self.importer(over: directory), in: directory)

        #expect(
            output == """
                claude-code a1b2c3 "Fix the parser" (/work/project) \(Self.fixedDateText) – 12 turns
                codex rollout-42 (no title) (/work/other) \(Self.fixedDateText) – 4 turns
                \(SessionsToolText.importAdvice)
                """)
    }

    @Test("list imports names each earlier import of a source as information")
    func listImportsNamesEachEarlierImport() async throws {
        let directory = Fixtures.directoryWithLauncher()
        let importer = Self.importer(over: directory)

        let outputs = try await Self.callAsCaller(
            [(Self.importOp, Self.titledSourceFields), (Self.listOp, [("agent", Self.claudeCode)])],
            importer: importer, in: directory)
        let copy = try #require(try await Self.importedSessions(in: directory).first)

        #expect(
            outputs.last == """
                claude-code a1b2c3 "Fix the parser" (/work/project) \(Self.fixedDateText) – 12 turns, imported \
                \(Self.fixedDateText) as @\(copy.shortID)
                \(SessionsToolText.importAdvice)
                """)
    }

    @Test("list imports with no argument asks for 20 sessions of each agent, with the caller folder first")
    func listImportsWithNoArgumentAsksForTheDefaults() async throws {
        let directory = Fixtures.directoryWithLauncher()
        let importer = Self.importer(over: directory)

        _ = try await Self.callAsCaller(Self.listOp, importer: importer, in: directory)

        #expect(
            await importer.requests == [
                ImportableSessionsRequest(
                    agent: nil, folder: nil, preferredFolder: Fixtures.workingFolder, limit: 20, cursor: nil)
            ])
    }

    @Test("list imports with folder . asks for the sessions of the caller folder")
    func listImportsWithTheDotFolderAsksForTheCallerFolder() async throws {
        let directory = Fixtures.directoryWithLauncher()
        let importer = Self.importer(over: directory)

        _ = try await Self.callAsCaller(Self.listOp, [("folder", ".")], importer: importer, in: directory)

        #expect(await importer.requests.map(\.folder) == [Fixtures.workingFolder])
    }

    @Test("list imports gives the agent and the limit to the importer")
    func listImportsGivesTheAgentAndTheLimit() async throws {
        let directory = Fixtures.directoryWithLauncher()
        let importer = Self.importer(over: directory)

        _ = try await Self.callAsCaller(
            Self.listOp, [("agent", Self.codex), ("limit", 5)], importer: importer, in: directory)

        #expect(await importer.requests.map { [$0.agent ?? "", String($0.limit)] } == [[Self.codex, "5"]])
    }

    @Test("list imports with a relative folder gives the corrective of the folder and asks the importer nothing")
    func listImportsWithARelativeFolderGivesACorrective() async throws {
        let directory = Fixtures.directoryWithLauncher()
        let importer = Self.importer(over: directory)

        let output = try await Self.callAsCaller(
            Self.listOp, [("folder", "work/project")], importer: importer, in: directory)

        #expect(output == SessionsToolText.relativeFolder("work/project"))
        #expect(await importer.requests == [])
    }

    @Test("list imports names each agent with no access, and tells the agent to ask the user")
    func listImportsNamesEachAgentWithNoAccess() async throws {
        let directory = Fixtures.directoryWithLauncher()

        let output = try await Self.callAsCaller(
            Self.listOp, [("agent", Self.claudeCode)],
            importer: Self.importer(over: directory, unreadableSources: [Self.codex]), in: directory)

        #expect(output.contains(SessionsToolText.noSourceAccess(Self.codex)), "output was: \(output)")
    }

    @Test("the access corrective names the agent and the UI command")
    func theAccessCorrectiveNamesTheAgentAndTheCommand() {
        let text = SessionsToolText.noSourceAccess(Self.codex)

        #expect(
            text.hasPrefix("No access to the sessions of codex. Ask the user to run \(Self.importUICommand)"),
            "text was: \(text)")
    }

    @Test("list imports with an importer that fails gives the error")
    func listImportsWithAFailingImporterGivesTheError() async throws {
        let output = try await Self.callAsCaller(
            Self.listOp,
            importer: FailingSessionImporter(failure: SessionImporterFailure(description: Self.unknownSourceID)))

        #expect(output.contains(Self.unknownSourceID), "output was: \(output)")
    }

    // MARK: - import session

    @Test("import session gives the short id, the name, the id, the folder and the skipped records")
    func importSessionGivesTheNewSession() async throws {
        let directory = Fixtures.directoryWithLauncher()

        let output = try await Self.callAsCaller(
            Self.importOp, Self.titledSourceFields, importer: Self.importer(over: directory), in: directory)
        let copy = try #require(try await Self.importedSessions(in: directory).first)

        #expect(
            output == """
                Imported the session a1b2c3 of claude-code as the new session @\(copy.shortID) "Fix the parser" \
                (id \(copy.id.ulidString)) in /work/project. The import did not read 3 records of the source. The \
                source did not change.
                """)
    }

    @Test("import session reads the name of the new session from the directory")
    func importSessionReadsTheNameFromTheDirectory() async throws {
        let directory = Fixtures.directoryWithLauncher()

        let output = try await Self.callAsCaller(
            Self.importOp, [("agent", Self.codex), ("source", Self.untitledSource.sourceID)],
            importer: Self.importer(over: directory), in: directory)

        #expect(output.contains("\"codex-import\""), "output was: \(output)")
    }

    @Test("a second import of the same source gives a second session")
    func aSecondImportGivesASecondSession() async throws {
        let directory = Fixtures.directoryWithLauncher()

        _ = try await Self.callAsCaller(
            [(Self.importOp, Self.titledSourceFields), (Self.importOp, Self.titledSourceFields)],
            importer: Self.importer(over: directory), in: directory)

        #expect(Set(try await Self.importedSessions(in: directory).map(\.id)).count == 2)
    }

    @Test("each import of the same source answers its own new session")
    func eachImportAnswersItsOwnSession() async throws {
        let directory = Fixtures.directoryWithLauncher()

        let outputs = try await Self.callAsCaller(
            [(Self.importOp, Self.titledSourceFields), (Self.importOp, Self.titledSourceFields)],
            importer: Self.importer(over: directory), in: directory)
        let copies = try await Self.importedSessions(in: directory)
        let answered = copies.map { copy in outputs.firstIndex { $0.contains("@\(copy.shortID)") } }

        #expect(Set(answered) == [0, 1], "outputs were: \(outputs)")
    }

    @Test("import session gives the agent, the source, the folder and the name to the importer")
    func importSessionGivesTheOrder() async throws {
        let directory = Fixtures.directoryWithLauncher()
        let importer = Self.importer(over: directory)

        _ = try await Self.callAsCaller(
            Self.importOp, Self.titledSourceFields + [("folder", "/work/elsewhere"), ("name", "parser-copy")],
            importer: importer, in: directory)

        #expect(
            await importer.orders == [
                SessionImportOrder(
                    agent: Self.claudeCode, source: Self.titledSource.sourceID,
                    folder: URL(fileURLWithPath: "/work/elsewhere", isDirectory: true), name: "parser-copy")
            ])
    }

    @Test("import session with folder . imports into the caller folder")
    func importSessionWithTheDotFolderUsesTheCallerFolder() async throws {
        let directory = Fixtures.directoryWithLauncher()
        let importer = Self.importer(over: directory)

        _ = try await Self.callAsCaller(
            Self.importOp, [("agent", Self.codex), ("source", Self.untitledSource.sourceID), ("folder", ".")],
            importer: importer, in: directory)

        #expect(await importer.orders.map(\.folder) == [Fixtures.workingFolder])
    }

    @Test("import session with no folder leaves the folder to the importer")
    func importSessionWithNoFolderLeavesTheFolderToTheImporter() async throws {
        let directory = Fixtures.directoryWithLauncher()
        let importer = Self.importer(over: directory)

        _ = try await Self.callAsCaller(Self.importOp, Self.titledSourceFields, importer: importer, in: directory)

        #expect(await importer.orders.map(\.folder) == [nil])
    }

    @Test("import session with the aliases from, id, cwd and title gives the same order")
    func importSessionTakesTheAliases() async throws {
        let directory = Fixtures.directoryWithLauncher()
        let importer = Self.importer(over: directory)

        _ = try await Self.callAsCaller(
            Self.importOp,
            [("from", Self.claudeCode), ("sourceId", Self.titledSource.sourceID), ("cwd", "."), ("title", "copy")],
            importer: importer, in: directory)

        #expect(
            await importer.orders == [
                SessionImportOrder(
                    agent: Self.claudeCode, source: Self.titledSource.sourceID, folder: Fixtures.workingFolder,
                    name: "copy")
            ])
    }

    @Test("the verb copy names import session")
    func theVerbCopyNamesImportSession() async throws {
        let directory = Fixtures.directoryWithLauncher()
        let importer = Self.importer(over: directory)

        _ = try await Self.callAsCaller("copy session", Self.titledSourceFields, importer: importer, in: directory)

        #expect(await importer.orders.count == 1)
    }

    @Test("import session with a blank source gives a corrective and asks the importer nothing")
    func importSessionWithABlankSourceGivesACorrective() async throws {
        let directory = Fixtures.directoryWithLauncher()
        let importer = Self.importer(over: directory)

        let output = try await Self.callAsCaller(
            Self.importOp, [("agent", Self.claudeCode), ("source", " ")], importer: importer, in: directory)

        #expect(output.contains("source"), "output was: \(output)")
        #expect(await importer.orders == [])
    }

    @Test("import session with an importer that fails gives the error")
    func importSessionWithAFailingImporterGivesTheError() async throws {
        let directory = Fixtures.directoryWithLauncher()

        let output = try await Self.callAsCaller(
            Self.importOp, [("agent", Self.claudeCode), ("source", Self.unknownSourceID)],
            importer: Self.importer(over: directory), in: directory)

        #expect(output.contains(Self.unknownSourceID), "output was: \(output)")
    }

    // MARK: - The correctives

    @Test("list imports with no importer gives the corrective")
    func listImportsWithNoImporterGivesTheCorrective() async throws {
        let output = try await Self.callAsCaller(Self.listOp, importer: nil)

        #expect(output == SessionsToolText.noImporter)
    }

    @Test("import session with no importer gives the corrective")
    func importSessionWithNoImporterGivesTheCorrective() async throws {
        let output = try await Self.callAsCaller(Self.importOp, Self.titledSourceFields, importer: nil)

        #expect(output == SessionsToolText.noImporter)
    }

    @Test("the corrective of no importer says why and names the UI command")
    func theNoImporterCorrectiveSaysWhy() {
        #expect(SessionsToolText.noImporter.contains(Self.noImporterWords))
        #expect(SessionsToolText.noImporter.contains(Self.importUICommand))
    }

    @Test("import session with no access to the agent gives the access corrective of list imports")
    func importSessionWithNoAccessGivesTheAccessCorrective() async throws {
        let directory = Fixtures.directoryWithLauncher()

        let output = try await Self.callAsCaller(
            Self.importOp, Self.titledSourceFields,
            importer: Self.importer(over: directory, unreadableSources: [Self.claudeCode]), in: directory)

        #expect(output.hasPrefix(SessionsToolText.noSourceAccess(Self.claudeCode)), "output was: \(output)")
    }

    @Test("import session into a folder with no access gives a corrective that names the folder argument")
    func importSessionIntoAnUnavailableFolderNamesTheFolderArgument() async throws {
        let directory = Fixtures.directoryWithLauncher()

        let output = try await Self.callAsCaller(
            Self.importOp, Self.titledSourceFields,
            importer: Self.importer(over: directory, unavailableFolders: [Fixtures.workingFolder]), in: directory)

        #expect(output == SessionsToolText.importFolderUnavailable(Fixtures.workingFolder))
    }

    @Test("the corrective of a folder with no access names the path and the folder argument")
    func theFolderCorrectiveNamesThePathAndTheArgument() {
        let text = SessionsToolText.importFolderUnavailable(Fixtures.workingFolder)

        #expect(text.contains("/work/project") && text.contains("`folder`"), "text was: \(text)")
    }

    @Test("import session with no access or no folder makes no session")
    func aRefusedImportMakesNoSession() async throws {
        let directory = Fixtures.directoryWithLauncher()

        _ = try await Self.callAsCaller(
            [(Self.importOp, Self.titledSourceFields)],
            importer: Self.importer(
                over: directory, unreadableSources: [Self.claudeCode], unavailableFolders: [Fixtures.workingFolder]),
            in: directory)

        #expect(try await Self.importedSessions(in: directory) == [])
    }
}
