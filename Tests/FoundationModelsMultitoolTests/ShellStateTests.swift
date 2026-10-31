import Foundation
import FoundationModelsRouter
import Testing

@testable import FoundationModelsMultitool

/// Behavioral tests for `ShellState` and its `.shell/log` store.
///
/// Each test makes a new `ShellState` in a temporary directory of its own.
/// Thus the tests are independent, and they run in parallel safely.
///
/// Each command here runs under a completion token that
/// `ToolContext.makeCompletionToken()` mints. eventplan.md
/// § "Consolidation of the siblings" makes the `commandID` of a shell run its
/// `correlationID` and its `completionToken` — one string on two planes — so
/// the tests mint a token exactly as the background engine does, and they never
/// write an identifier of their own.
@Suite("ShellStateTests")
struct ShellStateTests {

    /// Owns the temporary directories this test makes. Thus they go away when
    /// the test ends, and they do not collect in `$TMPDIR` run after run.
    private let scratch = TestScratch()

    /// The name prefix of the temporary directory of one test. Thus a leaked
    /// directory is traceable to this suite.
    private static let testDirectoryNamePrefix = "shellstate-tests"

    /// The name of the store folder inside the directory of one test.
    private static let shellStoreDirectoryName = ".shell"

    /// The name of the self-ignoring file the store seeds.
    private static let gitignoreFileName = ".gitignore"

    /// The one field separator of a stored log line.
    private static let logFieldSeparator: Character = ":"

    /// The number of lines the `grep` limit test writes.
    private static let manyMatchCount = 20

    /// The result cap the `grep` limit test gives.
    private static let grepResultCap = 5

    /// The line numbers of the two matching lines that the line-number test
    /// writes. Its output holds three lines, the first of which does not match,
    /// and the store counts the lines of one command from 1.
    private static let matchingLineNumbers = [2, 3]

    /// The number of lines the default-range test writes.
    private static let sequenceLineCount = 5

    /// The number of lines the start-and-end test writes.
    private static let rangeSampleCount = 10

    /// The first line number the start-and-end test asks for.
    private static let rangeStart = 3

    /// The last line number the start-and-end test asks for.
    private static let rangeEnd = 7

    /// The number of leading characters of an identifier that the
    /// prefix-leak test searches for.
    private static let identifierFragmentLength = 8

    /// The permissions of a directory that the owner cannot write.
    private static let readOnlyDirectoryMode = 0o555

    /// The permissions that make a read-only directory removable again.
    private static let writableDirectoryMode = 0o755

    /// The on-the-wire spelling of the timed-out status, which the response of
    /// each history operation carries.
    private static let timedOutWireName = "timed_out"

    // MARK: - Fixtures

    /// Makes a new, unique temporary directory for one test.
    private func makeTempDirectory() throws -> URL {
        try scratch.makeDirectory(prefix: Self.testDirectoryNamePrefix)
    }

    /// A `ShellState` with its store at `<directory>/.shell`.
    ///
    /// - Parameter directory: The temporary directory of the test.
    /// - Returns: A store rooted in that directory.
    /// - Throws: When the store directory does not prepare.
    private func makeState(in directory: URL) throws -> ShellState {
        try ShellState(
            preferredDirectory: directory.appendingPathComponent(Self.shellStoreDirectoryName))
    }

    /// A `ShellState` with its store inside a new temporary directory of its
    /// own.
    ///
    /// Each test that examines the behavior of the store, and not the place the
    /// store stands in, takes its subject from here.
    ///
    /// - Returns: A store that no other test shares.
    /// - Throws: When the directory or the store does not prepare.
    private func makeState() throws -> ShellState {
        try makeState(in: makeTempDirectory())
    }

    /// The log lines a command holds when its output is `texts`.
    ///
    /// The store numbers the lines of one command from 1, in the order it
    /// received them. Thus this function gives the expected value of each test
    /// that appends output and reads it back.
    ///
    /// - Parameter texts: The output lines, in the order the store received
    ///   them.
    /// - Returns: One `LogLine` for each text, numbered from 1.
    private func expectedLines(_ texts: [String]) -> [LogLine] {
        texts.enumerated().map { LogLine(lineNumber: $0.offset + 1, text: $0.element) }
    }

    // MARK: - Storage round trip

    @Test("A command started under a token reads back under that same token")
    func storageRoundTripWritesAndReadsBackLines() async throws {
        let state = try makeState()
        let token = ToolContext.makeCompletionToken()
        let outputs = ["hello", "world"]

        await state.startCommand("echo hello", commandID: token)
        try await state.appendLines(commandID: token, stdout: outputs)

        let lines = try await state.getLines(commandID: token)
        #expect(lines == expectedLines(outputs))
    }

    @Test("Each stored log line carries the completion token in field 2")
    func logFileCarriesTheCompletionTokenInFieldTwo() async throws {
        let state = try makeState()
        let token = ToolContext.makeCompletionToken()
        let outputs = ["first", "second"]

        await state.startCommand("echo", commandID: token)
        try await state.appendLines(commandID: token, stdout: outputs)

        let stored = try String(contentsOf: state.logURL, encoding: .utf8)
        let lines = stored.split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.count == outputs.count)

        for (index, line) in lines.enumerated() {
            let fields = line
                .split(separator: Self.logFieldSeparator, omittingEmptySubsequences: false)
                .map(String.init)
            #expect(fields == [state.sessionID, token, String(index + 1), outputs[index]])
        }
    }

    @Test("The store seeds a self-ignoring .gitignore at first use")
    func gitignoreSelfIgnoreWrittenOnFirstUse() throws {
        let temporary = try makeTempDirectory()
        let storeDirectory = temporary.appendingPathComponent(Self.shellStoreDirectoryName)
        _ = try ShellState(preferredDirectory: storeDirectory)

        let gitignore = storeDirectory.appendingPathComponent(Self.gitignoreFileName)
        #expect(FileManager.default.fileExists(atPath: gitignore.path))

        let content = try String(contentsOf: gitignore, encoding: .utf8)
        #expect(content.contains("*"))
        #expect(content.contains("!\(Self.gitignoreFileName)"))
    }

    // MARK: - Identity and line numbering

    @Test("Each record keeps the completion token the caller gave")
    func commandRecordsKeepTheCallerSuppliedTokens() async throws {
        let state = try makeState()
        let first = ToolContext.makeCompletionToken()
        let second = ToolContext.makeCompletionToken()
        #expect(first != second)

        await state.startCommand("first", commandID: first)
        await state.startCommand("second", commandID: second)

        let commands = await state.listCommands()
        #expect(commands.map(\.id) == [first, second])
    }

    @Test("Line numbers continue from stdout into stderr")
    func lineNumbersContinueFromStdoutIntoStderr() async throws {
        let state = try makeState()
        let token = ToolContext.makeCompletionToken()
        let standardOutput = ["out1", "out2"]
        let standardError = ["err1", "err2"]

        await state.startCommand("noisy", commandID: token)
        try await state.appendLines(
            commandID: token, stdout: standardOutput, stderr: standardError)

        let lines = try await state.getLines(commandID: token)
        #expect(lines == expectedLines(standardOutput + standardError))

        let record = try #require(await state.record(commandID: token))
        #expect(record.lineCount == standardOutput.count + standardError.count)
    }

    @Test("record answers nothing for a token no command ran under")
    func recordAnswersNothingForAnUnknownToken() async throws {
        let state = try makeState()

        await state.startCommand("real", commandID: ToolContext.makeCompletionToken())

        #expect(await state.record(commandID: ToolContext.makeCompletionToken()) == nil)
    }

    // MARK: - Filtering by session

    @Test("The lines of another session are invisible")
    func linesFromAnotherSessionAreInvisible() async throws {
        let temporary = try makeTempDirectory()
        let storeDirectory = temporary.appendingPathComponent(Self.shellStoreDirectoryName)
        let first = try ShellState(preferredDirectory: storeDirectory)
        let second = try ShellState(preferredDirectory: storeDirectory)
        #expect(first.sessionID != second.sessionID)

        let firstToken = ToolContext.makeCompletionToken()
        let secondToken = ToolContext.makeCompletionToken()
        await first.startCommand("a", commandID: firstToken)
        await second.startCommand("b", commandID: secondToken)
        try await first.appendLines(commandID: firstToken, stdout: ["shared_word from A"])
        try await second.appendLines(commandID: secondToken, stdout: ["shared_word from B"])

        // `getLines` answers for one session: each store sees its own lines only.
        #expect(try await first.getLines(commandID: firstToken) == expectedLines(["shared_word from A"]))
        #expect(try await second.getLines(commandID: secondToken) == expectedLines(["shared_word from B"]))

        // `grep` answers for one session too: the pattern matches both lines on
        // disk, and the first store counts and returns its own line only.
        let matches = try await first.grep(pattern: "shared_word")
        #expect(matches.total == 1)
        #expect(matches.results.map(\.text) == ["shared_word from A"])
    }

    // MARK: - grep

    @Test("grep keeps the limit and reports the total apart from it")
    func grepRespectsLimitAndReportsTotalSeparately() async throws {
        let state = try makeState()
        let token = ToolContext.makeCompletionToken()

        await state.startCommand("many", commandID: token)
        try await state.appendLines(
            commandID: token, stdout: (1...Self.manyMatchCount).map { "match_\($0)" })

        let result = try await state.grep(pattern: "match_", limit: Self.grepResultCap)
        #expect(result.results.count == Self.grepResultCap)
        #expect(result.total == Self.manyMatchCount)
    }

    @Test("grep scoped to one token answers for that command only")
    func grepScopedToOneTokenAnswersForThatCommandOnly() async throws {
        let state = try makeState()
        let wanted = ToolContext.makeCompletionToken()
        let other = ToolContext.makeCompletionToken()

        await state.startCommand("wanted", commandID: wanted)
        await state.startCommand("other", commandID: other)
        try await state.appendLines(commandID: wanted, stdout: ["shared_word here"])
        try await state.appendLines(commandID: other, stdout: ["shared_word there"])

        let result = try await state.grep(pattern: "shared_word", commandID: wanted)
        #expect(result.total == 1)
        #expect(result.results.map(\.commandID) == [wanted])
        #expect(result.results.map(\.text) == ["shared_word here"])
    }

    /// Each `grep` result carries the number of the line it matched inside the
    /// command. The model reads that number and asks `getLines` for the
    /// neighborhood of the match, thus a wrong number sends it to the wrong
    /// lines. The number comes from field 3 of the stored line, thus a parse
    /// that reads another field, or that counts from 0, answers differently
    /// here.
    @Test("grep reports the line number of each match")
    func grepReportsTheLineNumberOfEachMatch() async throws {
        let state = try makeState()
        let token = ToolContext.makeCompletionToken()

        await state.startCommand("numbered", commandID: token)
        // The first line does not match, thus the two matches are the second
        // line and the third.
        try await state.appendLines(
            commandID: token, stdout: ["quiet line", "found it here", "found it again"])

        let result = try await state.grep(pattern: "found")
        #expect(result.results.map(\.lineNumber) == Self.matchingLineNumbers)
    }

    @Test("An invalid regular expression surfaces a recoverable error")
    func grepInvalidRegexSurfacesRecoverableError() async throws {
        let state = try makeState()
        let token = ToolContext.makeCompletionToken()

        await state.startCommand("x", commandID: token)
        try await state.appendLines(commandID: token, stdout: ["text"])

        await #expect(throws: (any Error).self) {
            _ = try await state.grep(pattern: "[unclosed")
        }
    }

    @Test("ShellStateError is Sendable across an actor boundary")
    func shellStateErrorIsSendableAcrossActorBoundaries() {
        // `ShellStateError` is thrown from `ShellState`, which is an actor, and
        // it is awaited across the actor boundary. Thus it must be `Sendable`.
        // This is a guarantee at compile time: `requireSendable` accepts a
        // `Sendable` metatype only, thus the test target does not build if the
        // conformance goes away — for example when an associated value becomes
        // a non-`Sendable` `any Error` again.
        func requireSendable<T: Sendable>(_: T.Type) {}
        requireSendable(ShellStateError.self)
    }

    @Test("The invalid-regex description holds the pattern and the message")
    func invalidRegexDescriptionIncludesPatternAndUnderlyingMessage() {
        // The `invalidRegex` case holds the failure as a plain `String`, taken
        // at the moment of the throw, thus the error stays `Sendable`. The
        // description must still read as the pattern plus that message.
        let error = ShellStateError.invalidRegex(pattern: "[bad", underlyingMessage: "boom")
        #expect(error.description == "Invalid regex pattern \"[bad\": boom")
    }

    @Test("The unknown-command description names the token")
    func unknownCommandDescriptionNamesTheToken() {
        let token = ToolContext.makeCompletionToken()
        let error = ShellStateError.unknownCommand(token)
        #expect(error.description == "Unknown command ID \(token)")
    }

    @Test("A literal grep pattern matches plain text")
    func grepLiteralTreatsPatternAsPlainText() async throws {
        let state = try makeState()
        let token = ToolContext.makeCompletionToken()

        await state.startCommand("literal", commandID: token)
        try await state.appendLines(
            commandID: token, stdout: ["a.b matches here", "axb should not match"])

        // As a literal, "a.b" matches the line that holds "a.b" only.
        let literal = try await state.grep(pattern: "a.b", literal: true)
        #expect(literal.total == 1)
        #expect(literal.results.map(\.text) == ["a.b matches here"])

        // As a regular expression, "a.b" matches both lines: the dot is a
        // wildcard.
        let expression = try await state.grep(pattern: "a.b")
        #expect(expression.total == literal.total + 1)
    }

    /// `grep` must match the text of the command output, and never the
    /// `{sessionID}:{commandID}:{lineNumber}:` framing of the store. A pattern
    /// that looks like the session id, like the token, or like the counters
    /// stands in the prefix of each stored line. Thus a regular expression that
    /// ran against the raw line would match falsely and would raise both
    /// `results` and `total`. Output that holds no such text must answer with
    /// no match.
    @Test("grep does not match the metadata prefix of a log line")
    func grepDoesNotMatchLogLineMetadataPrefix() async throws {
        let state = try makeState()
        let token = ToolContext.makeCompletionToken()

        await state.startCommand("plain", commandID: token)
        // Text with no digit, no colon, and no part of either identifier.
        try await state.appendLines(commandID: token, stdout: ["hello world", "plain output"])

        // A part of the session id stands in the prefix only, never in the text.
        let bySession = try await state.grep(
            pattern: String(state.sessionID.prefix(Self.identifierFragmentLength)))
        #expect(bySession.results.isEmpty)
        #expect(bySession.total == 0)

        // A part of the completion token stands in field 2 only.
        let byToken = try await state.grep(
            pattern: String(token.prefix(Self.identifierFragmentLength)))
        #expect(byToken.results.isEmpty)
        #expect(byToken.total == 0)

        // `\d+:` matches the counters of the prefix only.
        let byCounters = try await state.grep(pattern: "\\d+:")
        #expect(byCounters.results.isEmpty)
        #expect(byCounters.total == 0)
    }

    /// A pattern whose characters stand in the metadata prefix of EVERY stored
    /// line — here the digit `1`, which the counters carry and the identifiers
    /// usually carry too — must match the lines whose output text holds it, and
    /// no other line. Thus the regular expression reads the parsed text and not
    /// the framing. The text of the one match is the stored text exactly, with
    /// no leak of the prefix.
    @Test("grep matches the output text with no leak of the prefix")
    func grepMatchesOutputTextWithoutPrefixLeakage() async throws {
        let state = try makeState()
        let token = ToolContext.makeCompletionToken()

        await state.startCommand("find", commandID: token)
        try await state.appendLines(
            commandID: token,
            stdout: ["no digits here", "has the digit 1 inside", "also plain"])

        let result = try await state.grep(pattern: "1")
        #expect(result.total == 1)
        #expect(result.results.map(\.text) == ["has the digit 1 inside"])
    }

    // MARK: - getLines ranges and unknown tokens

    @Test("The default range of getLines answers with everything")
    func getLinesDefaultRangeReturnsEverything() async throws {
        let state = try makeState()
        let token = ToolContext.makeCompletionToken()
        let outputs = (1...Self.sequenceLineCount).map { "line\($0)" }

        await state.startCommand("seq", commandID: token)
        try await state.appendLines(commandID: token, stdout: outputs)

        #expect(try await state.getLines(commandID: token) == expectedLines(outputs))
    }

    @Test("getLines keeps the start and the end it is given")
    func getLinesHonorsStartAndEnd() async throws {
        let state = try makeState()
        let token = ToolContext.makeCompletionToken()
        let outputs = (1...Self.rangeSampleCount).map { "data\($0)" }

        await state.startCommand("seq", commandID: token)
        try await state.appendLines(commandID: token, stdout: outputs)

        let middle = try await state.getLines(
            commandID: token, start: Self.rangeStart, end: Self.rangeEnd)
        #expect(middle.map(\.lineNumber) == Array(Self.rangeStart...Self.rangeEnd))
        #expect(middle.map(\.text) == Array(outputs[(Self.rangeStart - 1)..<Self.rangeEnd]))
    }

    @Test("getLines under an unknown token throws unknownCommand")
    func getLinesUnknownCommandThrows() async throws {
        let state = try makeState()
        let unknown = ToolContext.makeCompletionToken()

        await state.startCommand("real", commandID: ToolContext.makeCompletionToken())

        await #expect {
            _ = try await state.getLines(commandID: unknown)
        } throws: { error in
            guard case ShellStateError.unknownCommand(let reported) = error else { return false }
            return reported == unknown
        }
    }

    @Test("appendLines under an unknown token throws unknownCommand")
    func appendLinesUnknownCommandThrows() async throws {
        let state = try makeState()
        let unknown = ToolContext.makeCompletionToken()

        await state.startCommand("real", commandID: ToolContext.makeCompletionToken())

        await #expect {
            try await state.appendLines(commandID: unknown, stdout: ["orphan"])
        } throws: { error in
            guard case ShellStateError.unknownCommand(let reported) = error else { return false }
            return reported == unknown
        }
    }

    // MARK: - Trailing whitespace

    /// Rust `grep` builds the text of a result with `str::trim_end()`, thus it
    /// drops the trailing whitespace of a matched line. The Swift port agrees.
    @Test("grep drops the trailing whitespace of the result text")
    func grepTrimsTrailingWhitespaceFromResultText() async throws {
        let state = try makeState()
        let token = ToolContext.makeCompletionToken()

        await state.startCommand("trailing", commandID: token)
        try await state.appendLines(commandID: token, stdout: ["match here   "])

        let result = try await state.grep(pattern: "match")
        #expect(result.results.map(\.text) == ["match here"])
    }

    /// Rust `get_lines` reads with `BufRead::lines()`, which drops a trailing
    /// `\r` of CRLF output and keeps each other trailing space. The Swift port
    /// agrees: the `\r` goes away, and the spaces stay.
    @Test("getLines drops a trailing carriage return and keeps the spaces")
    func getLinesStripsTrailingCarriageReturnButKeepsSpaces() async throws {
        let state = try makeState()
        let token = ToolContext.makeCompletionToken()

        await state.startCommand("crlf", commandID: token)
        try await state.appendLines(commandID: token, stdout: ["carriage\r", "spaces here  "])

        let lines = try await state.getLines(commandID: token)
        #expect(lines == expectedLines(["carriage", "spaces here  "]))
    }

    // MARK: - The read-only fallback

    @Test("A read-only preferred directory falls back to a temporary store")
    func readOnlyCwdFallsBackToTemporaryDirectory() throws {
        let temporary = try makeTempDirectory()
        let readOnly = temporary.appendingPathComponent("read-only", isDirectory: true)
        try FileManager.default.createDirectory(at: readOnly, withIntermediateDirectories: true)
        // Give the permissions back, thus `scratch` removes the tree. Registered
        // before the directory becomes read-only, and not after, thus a throw
        // in between cannot leave the tree unremovable. To give back
        // permissions that `setAttributes` never changed is a no-operation.
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: Self.writableDirectoryMode], ofItemAtPath: readOnly.path)
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: Self.readOnlyDirectoryMode], ofItemAtPath: readOnly.path)

        let state = try ShellState(
            preferredDirectory: readOnly.appendingPathComponent(Self.shellStoreDirectoryName))
        defer { try? FileManager.default.removeItem(at: state.logURL.deletingLastPathComponent()) }

        // It moved away from the read-only directory...
        #expect(!state.logURL.path.hasPrefix(readOnly.path))
        // ...and the fallback store is usable.
        #expect(FileManager.default.fileExists(atPath: state.logURL.path))
    }

    // MARK: - Process bookkeeping

    @Test("startCommand makes a running record under the token")
    func startCommandCreatesRunningRecord() async throws {
        let state = try makeState()
        let token = ToolContext.makeCompletionToken()
        let before = Date()

        await state.startCommand("ls -la", commandID: token)

        let record = try #require(await state.record(commandID: token))
        #expect(record.id == token)
        #expect(record.command == "ls -la")
        #expect(record.status == .running)
        #expect(record.exitCode == nil)
        #expect(record.lineCount == 0)
        #expect(record.completedAt == nil)
        #expect(record.completedAtWall == nil)
        #expect(record.startedAtWall >= before)
        #expect(record.durationMs >= 0)
    }

    @Test("completeCommand sets the status, the exit code and the end time")
    func completeCommandSetsStatusAndExitCode() async throws {
        let state = try makeState()
        let token = ToolContext.makeCompletionToken()

        await state.startCommand("echo done", commandID: token)
        await state.completeCommand(commandID: token, exitCode: 0)

        let record = try #require(await state.record(commandID: token))
        #expect(record.status == .completed)
        #expect(record.exitCode == 0)
        #expect(record.completedAt != nil)
        #expect(record.durationMs >= 0)

        let completedAtWall = try #require(record.completedAtWall)
        #expect(completedAtWall >= record.startedAtWall)
    }

    @Test("completeCommand marks a command that ran out of time")
    func completeCommandCanMarkTimedOut() async throws {
        let state = try makeState()
        let token = ToolContext.makeCompletionToken()

        await state.startCommand("sleep 999", commandID: token)
        await state.completeCommand(commandID: token, status: .timedOut, exitCode: -1)

        let record = try #require(await state.record(commandID: token))
        #expect(record.status == .timedOut)
        #expect(record.status.rawValue == Self.timedOutWireName)
        #expect(record.exitCode == -1)
        #expect(record.completedAt != nil)
    }

    /// The process group of a running command is written by `registerProcess`
    /// and read back by `runningProcess`, and it goes away when the command
    /// completes. The canceler of a run and the sweep at the end of a session
    /// each read it, thus a stale entry would send a signal to a process group
    /// that the store no longer owns.
    @Test("A registered process group reads back and goes away at completion")
    func registeredProcessReadsBackAndIsDroppedAtCompletion() async throws {
        let state = try makeState()
        let token = ToolContext.makeCompletionToken()
        // The test process is a real, running process group. Thus the store
        // holds a pid that exists, and the test spawns no child of its own.
        let group = getpid()

        await state.startCommand("sleep 60", commandID: token)
        // The signal sends nothing: this test never kills, and a kill of this
        // group would end the test process.
        await state.registerProcess(
            commandID: token, group: ProcessGroupKill(pid: group, signal: { _ in }))
        #expect(await state.runningProcess(commandID: token) == group)

        await state.completeCommand(commandID: token, exitCode: 0)
        #expect(await state.runningProcess(commandID: token) == nil)
    }

    /// `groupToCancel` gives `nil` for a command whose record is already
    /// final, and it does not wait. Before, the call waited for a
    /// `registerProcess` or a `completeCommand` that never comes after the
    /// end, thus a cancel of an ended command did not end.
    ///
    /// The order is fixed, and no run can hang. The command ends first. Then
    /// a task starts the call, and the test registers a group that sends
    /// nothing. That registration is the release signal: it ends the call in
    /// each order of the two. When the call waits, the registration resumes
    /// it with that group. When the registration comes first, the call reads
    /// that group. Thus the old code always gives the group, and the check
    /// fails. The fixed code reads the final record first and gives `nil`.
    @Test("groupToCancel gives nil for a command that already ended")
    func groupToCancelGivesNilForAnEndedCommand() async throws {
        let state = try makeState()
        let token = ToolContext.makeCompletionToken()

        await state.startCommand("echo done", commandID: token)
        await state.completeCommand(commandID: token, exitCode: 0)

        let call = Task { await state.groupToCancel(commandID: token) }
        // The signal sends nothing: a kill of this group would end the test
        // process.
        await state.registerProcess(
            commandID: token, group: ProcessGroupKill(pid: getpid(), signal: { _ in }))

        let answer = await call.value
        #expect(answer == nil)
    }

    // MARK: - The atomic completion transition

    /// `completeIfRunning` finalizes a command that still runs, in one hop of
    /// the actor.
    @Test("completeIfRunning finalizes a command that still runs")
    func completeIfRunningTransitionsARunningCommand() async throws {
        let state = try makeState()
        let token = ToolContext.makeCompletionToken()

        await state.startCommand("echo hi", commandID: token)
        await state.completeIfRunning(commandID: token, status: .completed, exitCode: 0)

        let record = try #require(await state.record(commandID: token))
        #expect(record.status == .completed)
        #expect(record.exitCode == 0)
        #expect(record.completedAt != nil)
    }

    /// `completeIfRunning` must NOT write over a command that another path
    /// already finalized — for example a cancel that made the record `.killed`.
    /// This is the guarantee the runner needs. The check and the write happen
    /// with no suspension between them, thus a cancel that runs at the same
    /// time cannot go through a gap between the check and the act.
    @Test("completeIfRunning leaves a command that a cancel already stopped")
    func completeIfRunningLeavesAnAlreadyStoppedCommandUntouched() async throws {
        let state = try makeState()
        let token = ToolContext.makeCompletionToken()

        await state.startCommand("sleep 60", commandID: token)
        await state.completeCommand(commandID: token, status: .killed, exitCode: nil)

        // The completion the runner posts after the run must do nothing now.
        await state.completeIfRunning(commandID: token, status: .completed, exitCode: 0)

        let record = try #require(await state.record(commandID: token))
        #expect(record.status == .killed)
        #expect(record.exitCode == nil)
    }
}
