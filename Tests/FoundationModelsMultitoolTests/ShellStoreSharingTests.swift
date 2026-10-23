import Foundation
import FoundationModels
import FoundationModelsRouter
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Coverage for `ShellStore` — the one shell history that several capabilities
/// of one process share.
///
/// An ACP host runs several sessions in one process, and the sessions that
/// stand in one working directory share ONE shell store: one history, one log,
/// one list of command records. Each session keeps its own confinement, its own
/// live view and its own default working directory, thus those stay on the
/// capability, and only the store is shared.
///
/// Three properties carry this suite:
///
/// 1. A capability reads and lists what another capability on the same store
///    ran.
/// 2. Concurrent commands leave every stored line whole, also when two stores
///    append to one log file.
/// 3. Two stores stay separate: one store never answers for a command of the
///    other.
@Suite("ShellStoreSharingTests", .ownsTemporaryDirectories)
struct ShellStoreSharingTests {

    /// Owns the temporary directories this test makes. Thus they go away when
    /// the test ends, and they do not collect in `$TMPDIR` run after run.
    private let scratch = TestScratch()

    /// The name prefix of the temporary directory of one test. Thus a leaked
    /// directory is traceable to this suite.
    private static let testDirectoryNamePrefix = "shellstoresharing-tests"

    /// The name of the store folder inside the directory of one test.
    private static let shellStoreDirectoryName = ".shell"

    /// The text the command of capability A writes, which capability B reads.
    private static let sharedMarker = "written-by-capability-a"

    /// How many commands each store runs at the same time in the concurrency
    /// test.
    private static let concurrentCommandCount = 8

    /// How many lines each command of the concurrency test writes.
    private static let linesPerCommand = 200

    /// The padding of each line of the concurrency test. A long line makes a
    /// torn or overwritten append likely, thus the test sees one when the
    /// store makes one.
    private static let linePadding = String(repeating: "x", count: 512)

    // MARK: - The ground of one test

    /// A store directory inside a temporary directory this test owns.
    ///
    /// - Returns: A directory no other test shares.
    /// - Throws: When the temporary directory does not create.
    private func makeStoreDirectory() throws -> URL {
        try scratch.makeDirectory(prefix: Self.testDirectoryNamePrefix)
            .appendingPathComponent(Self.shellStoreDirectoryName)
    }

    /// The runner of the `execute` verb of `capability`, with a private
    /// process-group registry — see `ShellExecuteVerb.configured(in:)`.
    ///
    /// - Parameter capability: The capability to read.
    /// - Returns: The runner.
    /// - Throws: When the capability holds no `execute` verb.
    private static func runner(of capability: ShellCapability) throws -> ShellRunner {
        try ShellExecuteVerb.configured(in: capability).runner
    }

    /// The one verb of `capability` of type `Verb`.
    ///
    /// - Parameters:
    ///   - kind: The verb type to find.
    ///   - capability: The capability to read.
    /// - Returns: That verb.
    /// - Throws: When the capability holds no such verb.
    private static func verb<Verb: Tool>(
        _ kind: Verb.Type, in capability: ShellCapability
    ) throws -> Verb {
        try #require(capability.tools.compactMap { $0 as? Verb }.first)
    }

    /// Runs `command` to its end through `runner`.
    ///
    /// - Parameters:
    ///   - command: The command line.
    ///   - runner: The runner to run it with.
    /// - Returns: The completion token of the run.
    /// - Throws: What the runner throws.
    @discardableResult
    private static func run(_ command: String, with runner: ShellRunner) async throws -> String {
        let token = ToolContext.makeCompletionToken()
        let outcome = try await runner.run(.init(command: command, completionToken: token))
        #expect(outcome.status == .completed)
        #expect(outcome.exitCode == 0)
        return token
    }

    /// The command that writes ``linesPerCommand`` padded lines, each one
    /// naming `tag` and its own number.
    ///
    /// - Parameter tag: The tag of the command.
    /// - Returns: The command line.
    private static func manyLinesCommand(tag: String) -> String {
        "for i in $(seq 1 \(linesPerCommand)); do echo \"\(tag)-$i-\(linePadding)\"; done"
    }

    // MARK: - One store, several capabilities

    /// The center of the request: session B reads and lists what session A ran,
    /// because the two capabilities hold one store.
    @Test("a capability lists and reads the command another capability on the store ran")
    func aCapabilityReadsWhatAnotherCapabilityOnTheStoreRan() async throws {
        let store = try ShellStore(storeDirectory: makeStoreDirectory())
        let capabilityA = ShellCapability(store: store)
        let capabilityB = ShellCapability(store: store)

        let token = try await Self.run(
            "echo \(Self.sharedMarker)", with: Self.runner(of: capabilityA))

        let getLinesB = try Self.verb(GetLines.self, in: capabilityB)
        let read = try await getLinesB.call(arguments: GetLinesArguments(commandID: token))
        #expect(read.lines == ["1: \(Self.sharedMarker)"])
        #expect(read.correction == nil)

        let grepB = try Self.verb(GrepHistory.self, in: capabilityB)
        let found = try await grepB.call(
            arguments: GrepHistoryArguments(pattern: Self.sharedMarker, literal: true))
        #expect(found.matches.map(\.commandID) == [token])

        let listed = await getLinesB.state.listCommands().map(\.id)
        #expect(listed == [token])
    }

    /// The store, and not the capability, is what is shared: each capability
    /// keeps its own default working directory.
    @Test("capabilities on one store keep their own default working directory")
    func capabilitiesOnOneStoreKeepTheirOwnDefaultWorkingDirectory() throws {
        let store = try ShellStore(storeDirectory: makeStoreDirectory())
        let rootA = try scratch.makeDirectory(prefix: Self.testDirectoryNamePrefix)
        let rootB = try scratch.makeDirectory(prefix: Self.testDirectoryNamePrefix)

        let runnerA = try Self.runner(
            of: ShellCapability(store: store, defaultWorkingDirectory: rootA))
        let runnerB = try Self.runner(
            of: ShellCapability(store: store, defaultWorkingDirectory: rootB))

        #expect(runnerA.state === runnerB.state)
        #expect(runnerA.defaultWorkingDirectory == rootA.path)
        #expect(runnerB.defaultWorkingDirectory == rootB.path)
    }

    /// `withShell(store:...)` is the short form of
    /// `withCapability(ShellCapability(store:...))`.
    @Test("withShell(store:) registers a capability over the given store")
    func withShellStoreRegistersOverTheGivenStore() throws {
        let store = try ShellStore(storeDirectory: makeStoreDirectory())

        let registry = try MultiTool.Builder().withShell(store: store).buildRegistry()

        let execute = try #require(registry.tools["shell.execute"] as? Execute)
        #expect(execute.runner.state === store.state)
    }

    // MARK: - Whole lines under concurrency

    /// Two capabilities on one store run commands at the same time. Every line
    /// each command wrote is in the log once, whole, and in its own command.
    @Test("concurrent commands on one store leave every line whole")
    func concurrentCommandsOnOneStoreLeaveEveryLineWhole() async throws {
        let store = try ShellStore(storeDirectory: makeStoreDirectory())
        let runners = try [ShellCapability(store: store), ShellCapability(store: store)]
            .map(Self.runner(of:))

        let tokens = try await Self.runConcurrently(on: runners)

        for (tag, token) in tokens {
            try await Self.expectWholeLines(of: token, tag: tag, in: store.state)
        }
    }

    /// Two stores — two processes, or two hosts — that append to one log file
    /// at the same time. Each append opens the log for appending, thus no store
    /// writes over a line of the other.
    @Test("two stores on one log file leave every line whole")
    func twoStoresOnOneLogFileLeaveEveryLineWhole() async throws {
        let directory = try makeStoreDirectory()
        let storeA = try ShellStore(storeDirectory: directory)
        let storeB = try ShellStore(storeDirectory: directory)
        let runnerA = try Self.runner(of: ShellCapability(store: storeA))
        let runnerB = try Self.runner(of: ShellCapability(store: storeB))

        let tokens = try await Self.runConcurrently(on: [runnerA, runnerB])

        for (tag, token) in tokens {
            let state = tag.hasPrefix("r0") ? storeA.state : storeB.state
            try await Self.expectWholeLines(of: token, tag: tag, in: state)
        }

        let log = try Data(contentsOf: storeA.state.logURL)
        let stored = ShellState.splitLogLines(log)
        let expected = 2 * Self.concurrentCommandCount * Self.linesPerCommand
        #expect(stored.count == expected)
    }

    /// Runs ``concurrentCommandCount`` many-line commands on each runner at
    /// the same time.
    ///
    /// - Parameter runners: The runners.
    /// - Returns: The tag and the completion token of each command.
    /// - Throws: What a runner throws.
    private static func runConcurrently(on runners: [ShellRunner]) async throws -> [(String, String)] {
        try await withThrowingTaskGroup(of: (String, String).self) { group in
            for (r, runner) in runners.enumerated() {
                for c in 0..<concurrentCommandCount {
                    let tag = "r\(r)c\(c)"
                    group.addTask {
                        (tag, try await run(manyLinesCommand(tag: tag), with: runner))
                    }
                }
            }
            var tokens: [(String, String)] = []
            for try await entry in group { tokens.append(entry) }
            return tokens
        }
    }

    /// Expects the command under `token` to hold exactly its lines, in order,
    /// each one whole.
    ///
    /// - Parameters:
    ///   - token: The completion token of the command.
    ///   - tag: The tag the command wrote into each line.
    ///   - state: The store to read.
    /// - Throws: When the store does not read.
    private static func expectWholeLines(of token: String, tag: String, in state: ShellState)
        async throws
    {
        let lines = try await state.getLines(commandID: token)
        let expected = (1...linesPerCommand).map {
            LogLine(lineNumber: $0, text: "\(tag)-\($0)-\(linePadding)")
        }
        #expect(lines == expected, "command \(tag) stored \(lines.count) lines")
    }

    // MARK: - The session that ran each command

    /// The session ID of capability A in the attribution tests.
    private static let sessionA = "session-a"

    /// The session ID of capability B in the attribution tests.
    private static let sessionB = "session-b"

    /// On a shared store, each result says which session ran the command:
    /// the record, the execute report, `getLines`, and each `grepHistory`
    /// match — read through the OTHER session.
    @Test("each shell result names the session that ran the command")
    func eachResultNamesTheSessionThatRanTheCommand() async throws {
        let store = try ShellStore(storeDirectory: makeStoreDirectory())
        let capabilityA = ShellCapability(store: store, sessionID: Self.sessionA)
        let capabilityB = ShellCapability(store: store, sessionID: Self.sessionB)

        let token = try await Self.run(
            "echo \(Self.sharedMarker)", with: Self.runner(of: capabilityA))

        #expect(await store.state.listCommands().map(\.owner) == [Self.sessionA])

        let report = await Execute.reportFields(of: token, in: store.state)
        #expect(report["sessionID"] == .string(Self.sessionA))

        let read = try await Self.verb(GetLines.self, in: capabilityB)
            .call(arguments: GetLinesArguments(commandID: token))
        #expect(read.sessionID == Self.sessionA)

        let found = try await Self.verb(GrepHistory.self, in: capabilityB)
            .call(arguments: GrepHistoryArguments(pattern: Self.sharedMarker, literal: true))
        #expect(found.matches.map(\.sessionID) == [Self.sessionA])
    }

    /// A capability made with no session ID records no owner, and its results
    /// carry no `sessionID`.
    @Test("a capability with no session ID names no session")
    func aCapabilityWithNoSessionIDNamesNoSession() async throws {
        let store = try ShellStore(storeDirectory: makeStoreDirectory())
        let capability = ShellCapability(store: store)

        let token = try await Self.run("echo \(Self.sharedMarker)", with: Self.runner(of: capability))

        #expect(await store.state.listCommands().map(\.owner) == [nil])
        #expect(await Execute.reportFields(of: token, in: store.state)["sessionID"] == nil)
        let read = try await Self.verb(GetLines.self, in: capability)
            .call(arguments: GetLinesArguments(commandID: token))
        #expect(read.sessionID == nil)
    }

    /// `withShell(store:sessionID:)` gives the session ID to the runner.
    @Test("withShell(store:sessionID:) gives the session ID to the runner")
    func withShellStoreSessionIDReachesTheRunner() throws {
        let store = try ShellStore(storeDirectory: makeStoreDirectory())

        let registry = try MultiTool.Builder().withShell(store: store, sessionID: Self.sessionA).buildRegistry()

        let execute = try #require(registry.tools["shell.execute"] as? Execute)
        #expect(execute.runner.sessionID == Self.sessionA)
    }

    // MARK: - Separate stores

    /// Two stores in two directories never answer for each other.
    @Test("two stores stay separate")
    func twoStoresStaySeparate() async throws {
        let storeA = try ShellStore(storeDirectory: makeStoreDirectory())
        let storeB = try ShellStore(storeDirectory: makeStoreDirectory())
        let capabilityA = ShellCapability(store: storeA)
        let capabilityB = ShellCapability(store: storeB)

        let token = try await Self.run(
            "echo \(Self.sharedMarker)", with: Self.runner(of: capabilityA))

        let getLinesB = try Self.verb(GetLines.self, in: capabilityB)
        let read = try await getLinesB.call(arguments: GetLinesArguments(commandID: token))
        #expect(read.lines.isEmpty)
        #expect(read.correction != nil)

        let grepB = try Self.verb(GrepHistory.self, in: capabilityB)
        let found = try await grepB.call(
            arguments: GrepHistoryArguments(pattern: Self.sharedMarker, literal: true))
        #expect(found.matches.isEmpty)
        #expect(await getLinesB.state.listCommands().isEmpty)
    }

    /// Two stores on ONE directory share the log file and still stay separate:
    /// each one reads the lines of its own session only.
    @Test("two stores on one directory stay separate")
    func twoStoresOnOneDirectoryStaySeparate() async throws {
        let directory = try makeStoreDirectory()
        let storeA = try ShellStore(storeDirectory: directory)
        let storeB = try ShellStore(storeDirectory: directory)

        try await Self.run(
            "echo \(Self.sharedMarker)", with: Self.runner(of: ShellCapability(store: storeA)))

        let grepB = try Self.verb(GrepHistory.self, in: ShellCapability(store: storeB))
        let found = try await grepB.call(
            arguments: GrepHistoryArguments(pattern: Self.sharedMarker, literal: true))
        #expect(found.matches.isEmpty)
    }
}
