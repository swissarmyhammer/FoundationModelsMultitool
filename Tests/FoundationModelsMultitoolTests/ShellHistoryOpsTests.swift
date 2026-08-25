import Foundation
import FoundationModelsExtras
import FoundationModelsRouter
import Testing

@testable import FoundationModelsMultitool

/// Behavioral tests for the two content-plane verbs of the shell capability,
/// `tools.shell.getLines` and `tools.shell.grepHistory`.
///
/// Ported from
/// `../FoundationModelsShelltool/Tests/ShellToolTests/HistoryOpsTests.swift`.
/// The sibling drives its verbs through `OperationTool.call` with a
/// `GeneratedContent` bag; here each verb is a plain `FoundationModels.Tool`,
/// thus a test calls `call(arguments:)` with a typed value and reads a typed
/// result.
///
/// Each test makes a store in a temporary directory of its own. Thus the tests
/// are independent, and they run in parallel safely.
///
/// Each run stands under a completion token that
/// `SessionMailbox.makeCompletionToken()` mints. eventplan.md § "Consolidation
/// of the siblings" makes the `commandID` of a shell run its `correlationID`
/// and its `completionToken` — one string on two planes — thus a test mints a
/// token exactly as the elevation engine does.
@Suite("ShellHistoryOpsTests")
struct ShellHistoryOpsTests {

    /// Owns the temporary directories this test makes. Thus they go away when
    /// the test ends, and they do not collect in `$TMPDIR` run after run.
    private let scratch = TestScratch()

    /// The name prefix of the temporary directory of one test. Thus a leaked
    /// directory is traceable to this suite.
    private static let testDirectoryNamePrefix = "shellhistoryops-tests"

    /// The name of the store folder inside the directory of one test.
    private static let shellStoreDirectoryName = ".shell"

    /// The noun the two verbs render under, which is the noun
    /// `ShellCapability` gives them.
    private static let shellNoun = "shell"

    /// The rendered call path of the `getLines` verb.
    private static let getLinesPath = "shell.getLines"

    /// The rendered call path of the `grepHistory` verb.
    private static let grepHistoryPath = "shell.grepHistory"

    /// The text the still-running command writes before it goes to sleep.
    private static let liveMarker = "partial"

    /// How long the still-running command sleeps after it wrote its one line.
    /// Long enough that the read below certainly lands while the run goes on,
    /// and the test kills the run as soon as it read what it came for.
    private static let liveRunSleepSeconds = 5

    /// How long a poll waits for the first line of a run to arrive.
    private static let outputArrivalDeadline = Duration.seconds(10)

    /// The text each line of the limit test carries, thus one pattern matches
    /// every one of them.
    private static let repeatedMatch = "MARK"

    /// The number of matching lines the limit test writes.
    private static let repeatedMatchCount = 5

    /// The cap the limit test gives, which is under `repeatedMatchCount`.
    private static let grepResultCap = 2

    /// The lines the range tests store, in order.
    private static let storedLines = ["alpha", "beta", "gamma"]

    /// The first line number the bounded-range test asks for.
    private static let boundedRangeStart = 2

    /// The last line number the bounded-range test asks for.
    private static let boundedRangeEnd = 3

    /// A start line number no stored line can carry, because the store counts
    /// the lines of one command from 1.
    private static let unreadableStart = 0

    /// A pattern that does not compile as a regular expression, because its
    /// character class never closes.
    private static let uncompilablePattern = "[invalid"

    /// Output that carries the metacharacters of a character class, thus a
    /// literal search and a regular-expression search answer differently.
    private static let metacharacterLine = "error[E0001] failed"

    /// The part of `metacharacterLine` a literal search asks for.
    private static let metacharacterPattern = "error[E0001]"

    // MARK: - The store of one test

    /// Makes a store in a temporary directory this test owns.
    ///
    /// - Returns: A store that no other test shares.
    /// - Throws: When the directory or the store does not prepare.
    private func makeState() throws -> ShellState {
        let directory = try scratch.makeDirectory(prefix: Self.testDirectoryNamePrefix)
        return try ShellState(
            preferredDirectory: directory.appendingPathComponent(Self.shellStoreDirectoryName))
    }

    /// Records one command that already ended, with the lines it wrote.
    ///
    /// - Parameters:
    ///   - state: The store to write into.
    ///   - lines: The standard-output lines of the command.
    /// - Returns: The completion token of the recorded run.
    /// - Throws: What `ShellState.appendLines` throws.
    private func recordCompletedCommand(
        in state: ShellState, lines: [String]
    ) async throws -> String {
        let token = SessionMailbox.makeCompletionToken()
        await state.startCommand(Self.storedLines.joined(separator: " "), commandID: token)
        try await state.appendLines(commandID: token, stdout: lines)
        await state.completeCommand(commandID: token)
        return token
    }

    /// Starts a command that writes one line and then sleeps for a long time.
    ///
    /// Thus a read that lands after the line arrived certainly lands while the
    /// run is still going, and the test never races the end of the run.
    ///
    /// - Parameter state: The store the run records into.
    /// - Returns: The completion token of the run, and the task that runs it.
    private func startLiveRun(
        in state: ShellState
    ) -> (token: String, run: Task<ShellRunner.Outcome, Error>) {
        let runner = ShellRunner(state: state, registry: ProcessRegistry())
        let token = SessionMailbox.makeCompletionToken()
        let run = Task {
            try await runner.run(
                .init(
                    command: "echo \(Self.liveMarker); sleep \(Self.liveRunSleepSeconds)",
                    completionToken: token))
        }
        return (token, run)
    }

    /// Kills a live run and waits for its child to go away, thus nothing of
    /// this test outlives it.
    ///
    /// - Parameter run: The task that runs the command.
    private func stop(_ run: Task<ShellRunner.Outcome, Error>) async {
        run.cancel()
        _ = try? await run.value
    }

    /// Reads again and again until the answer satisfies `isReady`, or until
    /// the deadline elapses.
    ///
    /// The read goes through the verb under test, because what a live test
    /// proves is that the VERB answers for a run that still goes.
    ///
    /// - Parameters:
    ///   - read: How to read one answer.
    ///   - isReady: What the answer must satisfy.
    /// - Returns: The last answer the poll read.
    /// - Throws: What `read` throws.
    private func poll<Answer>(
        read: () async throws -> Answer, until isReady: (Answer) -> Bool
    ) async throws -> Answer {
        let clock = ContinuousClock()
        let start = clock.now
        var answer = try await read()
        while !isReady(answer), clock.now - start < Self.outputArrivalDeadline {
            try? await Task.sleep(for: TestPoll.interval)
            answer = try await read()
        }
        return answer
    }

    // MARK: - The rendered surface

    /// eventplan.md § "Registration of capabilities: noun/verb" fixes the
    /// grammar of the surface, and `ToolAPIRenderer` synthesizes the runnable
    /// example from the arguments of each verb. Thus the two verbs render at
    /// `tools.shell.getLines` and `tools.shell.grepHistory`, each with an
    /// `@example` line that names its own qualified path.
    @Test("Each verb renders under the shell noun with a runnable example")
    func eachVerbRendersUnderTheShellNounWithARunnableExample() throws {
        let state = try makeState()
        let surface = try MultiTool.Builder()
            .addGroup(named: Self.shellNoun, [GetLines(state: state), GrepHistory(state: state)])
            .build()

        #expect(surface.entries.map(\.path) == [Self.getLinesPath, Self.grepHistoryPath])

        for path in [Self.getLinesPath, Self.grepHistoryPath] {
            let entry = try #require(surface.entries.first { $0.path == path })
            #expect(entry.qualifiedExample.hasPrefix("await tools.\(path)("))
            #expect(
                entry.block.contains("@example const r = await tools.\(path)("),
                "block was: \(entry.block)")
        }
    }

    // MARK: - getLines

    /// eventplan.md § "Consolidation of the siblings": the content plane
    /// answers "to a live detached run (`OutputBuffer` reads while the child
    /// runs)". The runner writes each line the buffer completes into the store
    /// as the chunks arrive, thus the verb reads the output of a run that has
    /// not ended.
    @Test("getLines answers with the output a run wrote before it ended")
    func getLinesAnswersWithTheOutputARunWroteBeforeItEnded() async throws {
        let state = try makeState()
        let verb = GetLines(state: state)
        let live = startLiveRun(in: state)
        defer { live.run.cancel() }

        let result = try await poll(
            read: { try await verb.call(arguments: GetLinesArguments(commandID: live.token)) },
            until: { !$0.lines.isEmpty })

        #expect(result.lines == ["1: \(Self.liveMarker)"])
        #expect(result.status == CommandStatus.running.rawValue)
        #expect(result.correction == nil)

        await stop(live.run)
    }

    @Test("getLines answers with the stored output of a run that ended")
    func getLinesAnswersWithTheStoredOutputOfARunThatEnded() async throws {
        let state = try makeState()
        let token = try await recordCompletedCommand(in: state, lines: Self.storedLines)

        let result = try await GetLines(state: state)
            .call(arguments: GetLinesArguments(commandID: token))

        #expect(result.commandID == token)
        #expect(result.lines == ["1: alpha", "2: beta", "3: gamma"])
        #expect(result.first == 1)
        #expect(result.last == Self.storedLines.count)
        #expect(result.status == CommandStatus.completed.rawValue)
        #expect(result.correction == nil)
    }

    @Test("getLines keeps the start and the end it is given")
    func getLinesKeepsTheStartAndTheEndItIsGiven() async throws {
        let state = try makeState()
        let token = try await recordCompletedCommand(in: state, lines: Self.storedLines)

        let result = try await GetLines(state: state).call(
            arguments: GetLinesArguments(
                commandID: token, start: Self.boundedRangeStart, end: Self.boundedRangeEnd))

        #expect(result.lines == ["2: beta", "3: gamma"])
        #expect(result.first == Self.boundedRangeStart)
        #expect(result.last == Self.boundedRangeEnd)
    }

    /// A token no command of this session ran under is a mistake the model can
    /// correct inside the turn. Thus the verb answers with a correction in
    /// band, and it never throws.
    @Test("getLines corrects a token no command of this session ran under")
    func getLinesCorrectsATokenNoCommandRanUnder() async throws {
        let state = try makeState()
        _ = try await recordCompletedCommand(in: state, lines: Self.storedLines)
        let unknown = SessionMailbox.makeCompletionToken()

        let result = try await GetLines(state: state)
            .call(arguments: GetLinesArguments(commandID: unknown))

        let correction = try #require(result.correction)
        #expect(correction.contains(unknown))
        #expect(result.lines.isEmpty)
        #expect(result.status == nil)
    }

    @Test("getLines corrects a line range it cannot read")
    func getLinesCorrectsALineRangeItCannotRead() async throws {
        let state = try makeState()
        let token = try await recordCompletedCommand(in: state, lines: Self.storedLines)

        let belowFirst = try await GetLines(state: state).call(
            arguments: GetLinesArguments(commandID: token, start: Self.unreadableStart))
        let endBeforeStart = try await GetLines(state: state).call(
            arguments: GetLinesArguments(
                commandID: token, start: Self.boundedRangeEnd, end: Self.boundedRangeStart))

        #expect(belowFirst.correction != nil)
        #expect(belowFirst.lines.isEmpty)
        #expect(endBeforeStart.correction != nil)
        #expect(endBeforeStart.lines.isEmpty)
    }

    // MARK: - grepHistory

    @Test("grepHistory finds a line in the history of the session")
    func grepHistoryFindsALineInTheHistoryOfTheSession() async throws {
        let state = try makeState()
        let token = try await recordCompletedCommand(in: state, lines: Self.storedLines)

        let result = try await GrepHistory(state: state)
            .call(arguments: GrepHistoryArguments(pattern: "beta"))

        #expect(result.total == 1)
        #expect(result.shown == 1)
        #expect(result.matches.map(\.text) == ["beta"])
        #expect(result.matches.map(\.commandID) == [token])
        #expect(result.matches.map(\.lineNumber) == [Self.boundedRangeStart])
        #expect(result.correction == nil)
    }

    /// The content plane answers for a run that is still going, and the two
    /// verbs read the same store, thus `grepHistory` finds a line before the
    /// run that wrote it ended.
    @Test("grepHistory finds the output a run wrote before it ended")
    func grepHistoryFindsTheOutputARunWroteBeforeItEnded() async throws {
        let state = try makeState()
        let verb = GrepHistory(state: state)
        let live = startLiveRun(in: state)
        defer { live.run.cancel() }

        let result = try await poll(
            read: { try await verb.call(arguments: GrepHistoryArguments(pattern: Self.liveMarker)) },
            until: { $0.total > 0 })

        #expect(result.total == 1)
        #expect(result.matches.map(\.text) == [Self.liveMarker])
        #expect(result.matches.map(\.commandID) == [live.token])
        #expect(result.correction == nil)

        await stop(live.run)
    }

    /// The `limit`/`total` split is the point of the verb: `limit` caps how
    /// many matches come back, and `total` always reports every match, thus
    /// the model knows to raise `limit` when it was cut short.
    @Test("grepHistory keeps the limit and reports the total apart from it")
    func grepHistoryKeepsTheLimitAndReportsTheTotalApartFromIt() async throws {
        let state = try makeState()
        let lines = Array(repeating: Self.repeatedMatch, count: Self.repeatedMatchCount)
        _ = try await recordCompletedCommand(in: state, lines: lines)

        let result = try await GrepHistory(state: state).call(
            arguments: GrepHistoryArguments(
                pattern: Self.repeatedMatch, limit: Self.grepResultCap))

        #expect(result.shown == Self.grepResultCap)
        #expect(result.matches.count == Self.grepResultCap)
        #expect(result.total == Self.repeatedMatchCount)
    }

    @Test("grepHistory matches exact text when the caller asks for a literal")
    func grepHistoryMatchesExactTextWhenTheCallerAsksForALiteral() async throws {
        let state = try makeState()
        _ = try await recordCompletedCommand(in: state, lines: [Self.metacharacterLine])
        let verb = GrepHistory(state: state)

        let literal = try await verb.call(
            arguments: GrepHistoryArguments(pattern: Self.metacharacterPattern, literal: true))
        let asPattern = try await verb.call(
            arguments: GrepHistoryArguments(pattern: Self.metacharacterPattern))

        #expect(literal.total == 1)
        #expect(literal.matches.map(\.text) == [Self.metacharacterLine])
        // As a regular expression `[E0001]` is a character class, thus the
        // bracketed text itself is not there to be found.
        #expect(asPattern.total == 0)
    }

    @Test("grepHistory scopes to the token it is given")
    func grepHistoryScopesToTheTokenItIsGiven() async throws {
        let state = try makeState()
        let wanted = try await recordCompletedCommand(in: state, lines: [Self.repeatedMatch])
        _ = try await recordCompletedCommand(
            in: state, lines: [Self.repeatedMatch, Self.repeatedMatch])

        let result = try await GrepHistory(state: state).call(
            arguments: GrepHistoryArguments(pattern: Self.repeatedMatch, commandID: wanted))

        #expect(result.total == 1)
        #expect(result.matches.map(\.commandID) == [wanted])
    }

    /// A pattern that does not compile is an expected failure the model can
    /// recover from inside the turn, because it can rephrase the pattern.
    /// Thus the verb answers with a correction in band, and it never throws.
    @Test("grepHistory corrects a pattern that does not compile")
    func grepHistoryCorrectsAPatternThatDoesNotCompile() async throws {
        let state = try makeState()
        _ = try await recordCompletedCommand(in: state, lines: Self.storedLines)

        let result = try await GrepHistory(state: state)
            .call(arguments: GrepHistoryArguments(pattern: Self.uncompilablePattern))

        let correction = try #require(result.correction)
        #expect(correction.contains(Self.uncompilablePattern))
        #expect(result.matches.isEmpty)
        #expect(result.total == 0)
    }

    @Test("grepHistory corrects a token no command of this session ran under")
    func grepHistoryCorrectsATokenNoCommandRanUnder() async throws {
        let state = try makeState()
        _ = try await recordCompletedCommand(in: state, lines: Self.storedLines)
        let unknown = SessionMailbox.makeCompletionToken()

        let result = try await GrepHistory(state: state).call(
            arguments: GrepHistoryArguments(pattern: "beta", commandID: unknown))

        let correction = try #require(result.correction)
        #expect(correction.contains(unknown))
        #expect(result.matches.isEmpty)
        #expect(result.total == 0)
    }
}
