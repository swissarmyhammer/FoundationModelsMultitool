import Foundation
import FoundationModelsExtras
import FoundationModelsRouter
import Subprocess
import Synchronization
import System
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Behavioral tests for `ShellRunner` — real `sh -c` children, each one spawned
/// into a new `ShellState` that a temporary directory roots.
///
/// These tests start genuine child processes (`echo`, trees of `sleep`,
/// `pgrep`). Each test that starts a tree cleans it up, through the group-kill
/// of the runner itself or through the canceler, thus nothing leaks from one
/// test to the next.
///
/// Each run here carries a completion token that
/// `ToolContext.makeCompletionToken()` mints. eventplan.md § "Consolidation
/// of the siblings" makes the `commandID` of a shell run its `correlationID` and
/// its `completionToken` — one string on two planes — thus the tests mint a
/// token exactly as the background engine does.
@Suite("ShellRunnerTests")
struct ShellRunnerTests {

    /// Owns the temporary directories this test makes. Thus they go away when
    /// the test ends, and they do not collect in `$TMPDIR` run after run.
    private let scratch = TestScratch()

    /// The name prefix of the temporary directory of one test. Thus a leaked
    /// directory is traceable to this suite.
    private static let testDirectoryNamePrefix = "shellrunner-tests"

    /// The name of the store folder inside the directory of one test.
    private static let shellStoreDirectoryName = ".shell"

    /// The captured-output cap the runner must default to, in bytes: 10 MiB.
    /// The test states the number on its own, thus a change of the default is a
    /// failure and not a silent drift.
    private static let expectedDefaultOutputCap = 10_485_760

    /// The exit code of the command that ends without success. It is not 0 and
    /// it is not the sentinel of a signal death, thus it proves the runner
    /// reports the code the child gave.
    private static let nonZeroExitCode = 2

    /// The exit code the runner reports when the run has none to report: a
    /// signal death, a time limit, or a spawn that never happened.
    private static let absentExitCode = -1

    /// A small captured-output cap, in bytes, for the test of truncation. It
    /// stands above the marker line of about 41 bytes, thus a few dozen short
    /// lines go past it.
    private static let smallOutputCap = 200

    /// How many lines the command of the truncation test writes. The cap cuts
    /// the capture well before the last one.
    private static let truncationLineCount = 60

    /// How many bytes the command of the binary test writes: `abc`, one null
    /// byte, then `def`.
    private static let binaryByteCount = 7

    /// How many lines the command of the interleaving test writes: two on
    /// standard output, and two on standard error.
    private static let interleavedLineCount = 4

    /// How many members the process tree of a group-kill test holds: the two
    /// `sleep` children the command starts.
    private static let treeMemberCount = 2

    /// The lowest marker a test picks for the sleep duration that makes its own
    /// process tree unique to `pgrep`.
    private static let markerLowerBound = 100_000

    /// The highest marker a test picks for that sleep duration.
    private static let markerUpperBound = 999_999

    /// The time limit the run of the group-kill test carries. The timer sleeps
    /// on a `GatedClock`, thus it fires when the test opens the clock, and
    /// never before the test saw the tree.
    private static let treeKillTimeout = Duration.seconds(2)

    /// The time limit of the test that proves a limit kills the command. The
    /// timer sleeps on a `GatedClock`, thus the value is what the test reads
    /// back from the clock, and not a wait on the wall clock.
    private static let shortTimeout = Duration.milliseconds(400)

    /// The line a tree command writes after its shell started each member of
    /// the tree. The `&` of the shell forks each member before the shell runs
    /// the next command, thus each member is a process when the line arrives.
    private static let readyMarker = "ready"

    /// The tail of a tree command: it writes ``readyMarker``, and then waits for
    /// each member of the tree, thus the leader stays alive as long as the
    /// tree does.
    private static let readyThenWait = "echo \(readyMarker); wait"

    /// A directory path no file system holds, thus `realpath(3)` resolves
    /// nothing of it and the resolver gives the input back.
    private static let absentDirectory = "/nonexistent-shellrunner-tests-directory"

    /// The same absent path carrying the trailing separator that
    /// `NSTemporaryDirectory()` carries and that a Seatbelt grant must not.
    private static let absentDirectoryWithSeparator = absentDirectory + "/"

    /// The directory a request of the fallback test names. It need not exist:
    /// `effectiveWorkingDirectory(for:defaultWorkingDirectory:)` picks a value
    /// and resolves nothing.
    private static let requestedDirectory = "/requested-shellrunner-tests-directory"

    /// The default a runner of the fallback test carries. It need not exist
    /// either, for the same reason.
    private static let defaultDirectory = "/default-shellrunner-tests-directory"

    /// The name of the directory a test gives a runner as its default.
    private static let defaultDirectoryName = "default"

    /// The name of the directory a test names in a request.
    private static let requestedDirectoryName = "requested"

    /// The name of the FIFO that holds a gated command alive. The FIFO is in
    /// the directory of one test, and the gated command runs in that
    /// directory, thus the command names no absolute path.
    private static let gateName = "gate"

    /// The permissions of the FIFO: read and write for the owner only.
    private static let gatePermissions: mode_t = 0o600

    /// A command that writes one line and then stays alive until the test
    /// opens the gate.
    ///
    /// The shell opens the FIFO as the standard input of the group BEFORE the
    /// group writes its line. Thus the arrival of the line proves that the
    /// child holds the read end. The test holds the write end from before the
    /// child starts, thus the open of the read end does not wait for a
    /// writer. `cat` then reads until the test closes the write end, and gets
    /// the end of the file. Thus the child ends only when the test lets it
    /// end, never on a timer, and no order of events can make it wait for a
    /// writer that does not come.
    private static let gatedCommand = "{ echo one; cat > /dev/null; } < \(gateName)"

    /// A `ShellRunner` over a `ShellState` that a new temporary directory roots.
    ///
    /// `scratch` owns that directory from the moment it exists, thus a throw
    /// from `ShellState.init` cannot leave behind a directory whose path no
    /// caller learned, and no caller has to remove it.
    ///
    /// - Parameters:
    ///   - registry: The process-group registry to give the runner. The
    ///     default is a new PRIVATE `ProcessRegistry()`, and never `.global`,
    ///     thus an ordinary test never touches the process-wide instance. Give
    ///     one here when a test must read the state of the registry.
    ///   - clock: The clock the timer of a time limit sleeps on. The default is
    ///     a `GatedClock` that no test opens, thus no test waits on the real
    ///     clock. A test of a time limit gives a `GatedClock` that it opens,
    ///     thus the limit fires when the test opens the clock.
    ///   - outputChunkStream: The live view of the output the runner tees into,
    ///     or `nil` — the default — for none. A test reads it to learn when the
    ///     command started its tree.
    /// - Returns: The runner, its store, and the temporary directory.
    /// - Throws: What `TestScratch.makeDirectory` or `ShellState.init` throws.
    private func makeRunner(
        registry: ProcessRegistry = ProcessRegistry(),
        clock: any Clock<Duration> = GatedClock(),
        outputChunkStream: ShellOutputChunkStream? = nil
    ) throws -> (runner: ShellRunner, state: ShellState, directory: URL) {
        let directory = try scratch.makeDirectory(prefix: Self.testDirectoryNamePrefix)
        let state = try ShellState(
            preferredDirectory: directory.appendingPathComponent(Self.shellStoreDirectoryName))
        var runner = ShellRunner(state: state, registry: registry, clock: clock)
        runner.outputChunkStream = outputChunkStream
        return (runner, state, directory)
    }

    /// Reads `live` until the output of the run holds ``readyMarker``, and then
    /// ends the view.
    ///
    /// The wait is for an event of the run, and not for a time: the line
    /// arrives when the command wrote it, and the completion marker of the run
    /// ends the wait when the command ends with no such line. Thus no
    /// deadline can expire under machine load.
    ///
    /// - Parameter live: The live view of the output of the run.
    /// - Returns: `true` when the line arrived, or `false` when the run ended
    ///   first.
    private static func waitForReadiness(on live: ShellOutputChunkStream) async -> Bool {
        defer { live.finish() }
        var output = ""
        for await event in live {
            switch event.kind {
            case .output(_, let bytes):
                output += String(decoding: bytes, as: UTF8.self)
                if output.contains(readyMarker) {
                    return true
                }
            case .gap:
                continue
            case .completed:
                return false
            }
        }
        return false
    }

    /// A sleep duration no other test uses, thus `pgrep -f` on it matches the
    /// process tree of one test only.
    ///
    /// - Returns: The marker, in whole seconds.
    private static func makeMarker() -> Int {
        Int.random(in: markerLowerBound...markerUpperBound)
    }

    /// The pids of the live processes whose whole command line matches
    /// `pattern`, through `pgrep -f`.
    ///
    /// `Subprocess.run` reads the output and waits for the exit with no
    /// blocked thread, thus the test holds no thread of the Swift
    /// cooperative pool while `pgrep` runs.
    ///
    /// - Parameter pattern: The pattern `pgrep -f` reads.
    /// - Returns: The pids, and an empty list when `pgrep` finds none.
    private func processIDs(matching pattern: String) async -> [pid_t] {
        let result = try? await Subprocess.run(
            .path(FilePath("/usr/bin/pgrep")),
            arguments: Arguments(["-f", pattern]),
            input: .none,
            output: .string(limit: .max),
            error: .discarded
        )
        let text = result?.standardOutput ?? ""
        return text.split(separator: "\n").compactMap { pid_t($0) }
    }

    /// Waits until each process of `members` exited, and counts the waits
    /// that ended.
    ///
    /// Each member is a grandchild of this process, thus this process cannot
    /// reap it, and the system reaps it at a time this process does not
    /// control. The wait is on the exit event of the kernel for each member
    /// (``ProcessExitWait/waitUntilGone(_:)``), and not on time. The end of
    /// each wait is the result, thus no state is read again after the waits:
    /// a second read can see a member in the exit window as live, or see a
    /// new process that took the pid again. A member that the kill missed
    /// never exits, and that wait is the failure of the test.
    ///
    /// - Parameter members: The pids of the tree, read while the tree ran.
    /// - Returns: The count of the members whose wait ended. It is equal to
    ///   the count of `members` when this call returns.
    private func exitedCount(of members: [pid_t]) async -> Int {
        var exited = 0
        for member in members {
            await ProcessExitWait.waitUntilGone(member)
            exited += 1
        }
        return exited
    }

    /// Waits until the store holds a line of `commandID`, and reads the lines.
    ///
    /// The wait is for an event: `ShellState.waitForStoredLines` ends when the
    /// store wrote the first line. Each caller runs a gated command, which
    /// cannot end before the test opens its gate, thus the line arrives while
    /// the command still runs, however slow the machine is.
    ///
    /// - Parameters:
    ///   - state: The store to read.
    ///   - commandID: The completion token of the run.
    /// - Returns: The lines of the run.
    /// - Throws: What `ShellState.getLines` throws.
    private func waitForLines(in state: ShellState, commandID: String) async throws -> [LogLine] {
        await state.waitForStoredLines(commandID: commandID, atLeast: 1)
        return try await state.getLines(commandID: commandID)
    }

    /// Reads `events` until the output of the run holds `marker`.
    ///
    /// The wait is for an event of the run, and not for a time. The iterator
    /// stays with the caller, thus a test can wait for several markers of one
    /// run, one after the other.
    ///
    /// - Parameters:
    ///   - marker: The text to wait for.
    ///   - events: The iterator of the live view of the output of the run.
    /// - Returns: `true` when the marker arrived, or `false` when the run or
    ///   the stream ended first.
    private static func waitForOutput(
        containing marker: String, from events: inout ShellOutputChunkStream.Iterator
    ) async -> Bool {
        var output = ""
        while let event = await events.next() {
            switch event.kind {
            case .output(_, let bytes):
                output += String(decoding: bytes, as: UTF8.self)
                if output.contains(marker) {
                    return true
                }
            case .gap:
                continue
            case .completed:
                return false
            }
        }
        return false
    }

    /// Releases `gate` for the command of the run under `token`. The release
    /// also ends when the process of that command exits before it reads the
    /// line.
    ///
    /// The pid of the command is the pid that the store holds for the run.
    /// The caller calls this only after an event that the command made while
    /// it ran (a line of its output), thus the child registered its pid
    /// before. The release then ends on the first of two events: the command
    /// opens the gate, or the process of the command exits. When the command
    /// is gone, the test records an issue with the result of the run, and no
    /// wait stays open.
    ///
    /// - Parameters:
    ///   - gate: The gate the command waits on.
    ///   - token: The completion token of the run.
    ///   - state: The store of the run.
    ///   - run: The task of the run, which gives the result for the issue.
    /// - Returns: `true` when the command got the line.
    /// - Throws: What ``ShellCommandGate/release(whileAlive:)`` throws.
    private static func release(
        _ gate: ShellCommandGate, forCommandOf token: String, in state: ShellState,
        run: Task<ShellRunner.Outcome, any Error>
    ) async throws -> Bool {
        if let pid = await state.runningProcess(commandID: token),
            try await gate.release(whileAlive: pid) == .reached
        {
            return true
        }
        let result = await run.result
        Issue.record("the command ended before the gate released it; the run gave \(result)")
        return false
    }

    /// Makes a directory named `name` inside the directory of one test, thus a
    /// test has a working directory that is not the current directory of this
    /// process.
    ///
    /// - Parameters:
    ///   - name: The name of the new directory.
    ///   - directory: The directory of the test that holds it.
    /// - Returns: The new directory.
    /// - Throws: What `FileManager.createDirectory` throws.
    private func makeWorkDirectory(named name: String, in directory: URL) throws -> URL {
        let workDirectory = directory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(
            at: workDirectory, withIntermediateDirectories: true)
        return workDirectory
    }

    /// Makes the FIFO that `gatedCommand` reads in `directory`, opens its
    /// write end, and then starts `gatedCommand` through `runner` in that
    /// directory, on a new task.
    ///
    /// The test holds the write end BEFORE the child starts. Thus the child
    /// opens the read end at once, and it stays alive until the caller gives
    /// the write end to `openGate(_:)`. A check that needs a live child thus
    /// does not depend on a timer. When a test stops before it opens the gate,
    /// the release of the handle closes the write end, and the child ends.
    ///
    /// - Parameters:
    ///   - runner: The runner that starts the command.
    ///   - token: The completion token of the run.
    ///   - directory: The directory of the test.
    ///   - timeout: The time limit of the run, or `nil` — the default — for
    ///     none.
    /// - Returns: The task of the run, and the write end of the FIFO that
    ///   lets it end.
    /// - Throws: The `POSIXError` of `mkfifo(2)` or `open(2)` when it fails.
    private func startGatedRun(
        of runner: ShellRunner, token: String, in directory: URL, timeout: Duration? = nil
    ) throws -> (run: Task<ShellRunner.Outcome, any Error>, gate: FileHandle) {
        let path = directory.appendingPathComponent(Self.gateName, isDirectory: false).path
        guard mkfifo(path, Self.gatePermissions) == 0 else {
            throw Self.lastPOSIXError()
        }
        let gate = try Self.openWriteEnd(ofFIFOAt: path)
        let run = Task {
            try await runner.run(
                .init(
                    command: Self.gatedCommand, completionToken: token,
                    workingDirectory: directory.path, timeout: timeout))
        }
        return (run, gate)
    }

    /// Opens the write end of the FIFO at `path`, with no wait for a reader.
    ///
    /// An `open(2)` of the write end with `O_NONBLOCK` fails with `ENXIO` when
    /// no reader holds the FIFO. Thus the function first opens a read end with
    /// `O_NONBLOCK`, which never waits, then opens the write end, and then
    /// closes its own read end. Each descriptor carries `O_CLOEXEC`, thus no
    /// child of this process gets a copy of the write end, and the close of
    /// the handle is the one close that the gated command waits for.
    ///
    /// - Parameter path: The path of the FIFO.
    /// - Returns: A handle on the write end, which closes the descriptor when
    ///   it is released.
    /// - Throws: The `POSIXError` of `open(2)` when it fails.
    private static func openWriteEnd(ofFIFOAt path: String) throws -> FileHandle {
        let readEnd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard readEnd >= 0 else { throw lastPOSIXError() }
        defer { close(readEnd) }
        let writeEnd = open(path, O_WRONLY | O_NONBLOCK | O_CLOEXEC)
        guard writeEnd >= 0 else { throw lastPOSIXError() }
        return FileHandle(fileDescriptor: writeEnd, closeOnDealloc: true)
    }

    /// The `POSIXError` that the current `errno` names.
    ///
    /// - Returns: The error of `errno`, or `EIO` when `errno` names no code
    ///   that `POSIXErrorCode` knows.
    private static func lastPOSIXError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    /// Lets a gated command end: closes the write end of the FIFO. `cat` then
    /// reads the end of the file, and the command ends.
    ///
    /// The close never waits. The gated command opens the read end before it
    /// writes its first line, thus call this only after that line arrived.
    ///
    /// - Parameter gate: The write end that `startGatedRun(of:token:in:)`
    ///   opened.
    /// - Throws: What `FileHandle.close()` throws.
    private func openGate(_ gate: FileHandle) throws {
        try gate.close()
    }

    /// Runs `/bin/pwd` through `runner` and gives back the directory it printed.
    ///
    /// `/bin/pwd` prints the physical directory (`/var` becomes `/private/var`
    /// on macOS), thus a caller compares the result against
    /// `ShellRunner.resolvedDirectory(path:)` of the directory it expects — the
    /// one directory resolver, and never a second spelling of that step.
    ///
    /// - Parameters:
    ///   - runner: The runner that starts the command.
    ///   - state: The store the runner writes the output into.
    ///   - workingDirectory: The directory the request names, or `nil` for a
    ///     request that names none.
    /// - Returns: The one line the command printed.
    /// - Throws: What `ShellRunner.run` or `ShellState.getLines` throws, or a
    ///   failed `#require` when the command printed nothing.
    private func printedWorkingDirectory(
        of runner: ShellRunner, in state: ShellState, workingDirectory: String?
    ) async throws -> String {
        let token = ToolContext.makeCompletionToken()
        _ = try await runner.run(
            .init(
                command: "/bin/pwd", completionToken: token,
                workingDirectory: workingDirectory))
        let lines = try await state.getLines(commandID: token)
        return try #require(lines.first?.text, "pwd printed nothing")
    }

    // MARK: - The kill of a process group takes down the whole tree

    /// The load-bearing test: a `sh -c 'sleep N & sleep N & …'` tree that the
    /// own-process-group spawn of the runner started must die whole when the
    /// time limit fires the group kill. No `sleep` survives.
    ///
    /// The timer of the limit sleeps on a `GatedClock`. The test opens the
    /// clock only after the tree reported that it runs, thus the kill always
    /// finds the whole tree, whatever the load of the machine.
    @Test("the group kill at the time limit leaves no survivor in the process tree")
    func timeoutGroupKillLeavesNoSurvivorsInProcessTree() async throws {
        let clock = GatedClock()
        let live = ShellOutputChunkStream()
        let (runner, _, _) = try makeRunner(clock: clock, outputChunkStream: live)
        let token = ToolContext.makeCompletionToken()

        let marker = Self.makeMarker()
        let pattern = "sleep \(marker)"

        let runTask = Task {
            try await runner.run(
                .init(
                    command: "sleep \(marker) & sleep \(marker) & \(Self.readyThenWait)",
                    completionToken: token, timeout: Self.treeKillTimeout))
        }
        defer { runTask.cancel() }

        #expect(await Self.waitForReadiness(on: live), "the sleep tree never reported that it runs")
        let members = await processIDs(matching: pattern)
        #expect(members.count >= Self.treeMemberCount, "expected the sleep tree to run, saw \(members.count)")

        clock.open()
        let outcome = try await runTask.value
        #expect(outcome.status == .timedOut)
        #expect(outcome.exitCode == Self.absentExitCode)
        #expect(clock.recordedSleeps == [Self.treeKillTimeout])

        let exited = await exitedCount(of: members)
        #expect(exited == members.count, "the group kill left \(members.count - exited) survivor(s)")
    }

    // MARK: - The default captured-output cap

    @Test("the default captured-output cap is 10 MiB")
    func defaultOutputCapIsTenMiB() {
        #expect(ShellRunner.defaultMaxOutputSize == Self.expectedDefaultOutputCap)
    }

    // MARK: - The round trip of one echo

    @Test("an echo round trip captures one line and exits zero")
    func echoRoundTripCapturesOneLineAndExitsZero() async throws {
        let (runner, state, _) = try makeRunner()
        let token = ToolContext.makeCompletionToken()

        let outcome = try await runner.run(.init(command: "echo hi", completionToken: token))
        #expect(outcome.status == .completed)
        #expect(outcome.exitCode == 0)

        let lines = try await state.getLines(commandID: token)
        #expect(lines == [LogLine(lineNumber: 1, text: "hi")])
    }

    // MARK: - An exit code is data, and not an error of the tool

    @Test("an exit code of zero is reported and successful")
    func zeroExitIsReportedAndSuccessful() async throws {
        let (runner, _, _) = try makeRunner()
        let token = ToolContext.makeCompletionToken()

        let outcome = try await runner.run(.init(command: "exit 0", completionToken: token))
        #expect(outcome.status == .completed)
        #expect(outcome.exitCode == 0)
    }

    @Test("an exit code that is not zero is reported, and it is not a thrown error")
    func nonZeroExitIsReportedAndNotAThrownError() async throws {
        let (runner, _, _) = try makeRunner()
        let token = ToolContext.makeCompletionToken()

        // A run that ends without success is a call that WORKED, and it reports
        // the code the child gave.
        let outcome = try await runner.run(
            .init(command: "exit \(Self.nonZeroExitCode)", completionToken: token))
        #expect(outcome.status == .completed)
        #expect(outcome.exitCode == Self.nonZeroExitCode)
    }

    @Test("a death by signal reports the absent exit code")
    func signalDeathReportsTheAbsentExitCode() async throws {
        let (runner, _, _) = try makeRunner()
        let token = ToolContext.makeCompletionToken()

        // The shell kills itself. A death by signal has no exit code to report,
        // and it is not a time limit.
        let outcome = try await runner.run(.init(command: "kill -KILL $$", completionToken: token))
        #expect(outcome.status == .completed)
        #expect(outcome.exitCode == Self.absentExitCode)
    }

    // MARK: - The environment stands on top of the inherited environment

    @Test("the requested environment stands on top of the inherited environment")
    func requestedEnvironmentIsAddedOnTopOfTheInheritedOne() async throws {
        let (runner, state, _) = try makeRunner()
        let token = ToolContext.makeCompletionToken()

        // SHELLRUNNER_TEST comes from the request. HOME is inherited, and it
        // must survive.
        let outcome = try await runner.run(
            .init(
                command: #"printf '%s|%s' "$SHELLRUNNER_TEST" "${HOME:+haveHOME}""#,
                completionToken: token,
                environment: ["SHELLRUNNER_TEST": "present"]))
        #expect(outcome.status == .completed)

        let lines = try await state.getLines(commandID: token)
        #expect(lines == [LogLine(lineNumber: 1, text: "present|haveHOME")])
    }

    // MARK: - The working directory

    @Test("the command runs in the requested working directory")
    func runsInRequestedWorkingDirectory() async throws {
        let (runner, state, directory) = try makeRunner()
        let requested = try makeWorkDirectory(named: Self.requestedDirectoryName, in: directory)

        let printed = try await printedWorkingDirectory(
            of: runner, in: state, workingDirectory: requested.path)

        let expected = ShellRunner.resolvedDirectory(path: requested.path)
        #expect(printed == expected, "pwd printed \(printed); expected \(expected)")
    }

    /// The composition supplies the default: a request that names no directory
    /// runs in `defaultWorkingDirectory`, and not in the current directory of
    /// this process. The default is a temporary directory, thus it cannot be
    /// the process directory by accident.
    @Test("a request with no directory runs in the runner default")
    func aRequestWithNoDirectoryRunsInTheRunnerDefault() async throws {
        var (runner, state, directory) = try makeRunner()
        let fallback = try makeWorkDirectory(named: Self.defaultDirectoryName, in: directory)
        runner.defaultWorkingDirectory = fallback.path

        let printed = try await printedWorkingDirectory(
            of: runner, in: state, workingDirectory: nil)

        let expected = ShellRunner.resolvedDirectory(path: fallback.path)
        #expect(printed == expected, "pwd printed \(printed); expected \(expected)")
    }

    /// A directory the request names wins over the default of the runner.
    @Test("a request directory wins over the runner default")
    func aRequestDirectoryWinsOverTheRunnerDefault() async throws {
        var (runner, state, directory) = try makeRunner()
        let fallback = try makeWorkDirectory(named: Self.defaultDirectoryName, in: directory)
        let requested = try makeWorkDirectory(named: Self.requestedDirectoryName, in: directory)
        runner.defaultWorkingDirectory = fallback.path

        let printed = try await printedWorkingDirectory(
            of: runner, in: state, workingDirectory: requested.path)

        let expected = ShellRunner.resolvedDirectory(path: requested.path)
        #expect(printed == expected, "pwd printed \(printed); expected \(expected)")
    }

    // MARK: - The cap cuts at a line boundary, and it marks the cut

    @Test("output just past the cap is cut at a line boundary, with the marker")
    func outputJustOverCapTruncatesAtLineBoundaryWithMarker() async throws {
        let directory = try scratch.makeDirectory(prefix: Self.testDirectoryNamePrefix)
        let state = try ShellState(
            preferredDirectory: directory.appendingPathComponent(Self.shellStoreDirectoryName))
        // A small cap that still stands above the marker line, thus a few dozen
        // short lines go past it. `OutputBufferTests` covers the logic of the
        // cap itself; this test proves the runner carries truncation and the
        // marker through to the log.
        let runner = ShellRunner(
            state: state, maxOutputSize: Self.smallOutputCap, registry: ProcessRegistry())
        let token = ToolContext.makeCompletionToken()

        let outcome = try await runner.run(
            .init(
                command: "for i in $(seq 1 \(Self.truncationLineCount)); do echo \"line$i\"; done",
                completionToken: token))
        #expect(outcome.status == .completed)
        #expect(outcome.exitCode == 0)

        let lines = try await state.getLines(commandID: token)
        // The cut falls on a line boundary — no part line — and the marker is
        // last.
        #expect(lines.first?.text == "line1")
        #expect(!lines.map(\.text).contains("line\(Self.truncationLineCount)"))
        #expect(lines.last?.text == "[Output truncated - exceeded size limit]")
    }

    // MARK: - The placeholder of binary content

    @Test("a null byte in the output gives the binary placeholder")
    func nullByteInOutputYieldsBinaryPlaceholder() async throws {
        let (runner, state, _) = try makeRunner()
        let token = ToolContext.makeCompletionToken()

        // Seven bytes: a b c NUL d e f. The null starts the binary detection.
        _ = try await runner.run(.init(command: #"printf 'abc\000def'"#, completionToken: token))

        let lines = try await state.getLines(commandID: token)
        #expect(
            lines == [LogLine(lineNumber: 1, text: "[Binary content: \(Self.binaryByteCount) bytes]")]
        )
    }

    // MARK: - Each stream keeps its own write order

    /// `ShellRunner` reads standard output and standard error on two reader
    /// tasks that the runtime schedules on their own, and both funnel their
    /// chunks into one shared stream. One consumer then flushes what it takes
    /// off that queue, in the order it takes it.
    ///
    /// That order is NOT the wall-clock write order of the child: when both
    /// readers hold a chunk, ordinary task scheduling picks which one comes
    /// first, and under load one reader can wait long enough that a later chunk
    /// of the OTHER stream lands first.
    ///
    /// What the package DOES guarantee, because one reader task drains each
    /// stream in sequence, is that the lines of a single stream land in the
    /// order the child wrote them, and that no line of either stream goes away
    /// or arrives twice. This test states that guarantee, and no more.
    ///
    /// The writes alternate in fixed steps, and no step waits on time. The
    /// command waits on its own `ShellCommandGate` after each write: one gate
    /// for each wait. The test reads the write on the live view, and only then
    /// releases the gate of that step. One gate for all the waits is not
    /// correct: a release closes its write end only after the write, and in
    /// that interval the shell can open the same FIFO for the next wait. That
    /// open ends at once on the write end of the step before, and the close of
    /// that write end gives the next `read` the end of the file. The shell then
    /// goes past the next wait with no release.
    ///
    /// When the shell exits before it reads a release — a kill from outside,
    /// for example — the release ends on the exit event of the shell, and the
    /// test records the result of the run. Thus that fault is a failure of
    /// the test, and never a wait with no end.
    @Test("standard output and standard error each keep their own write order")
    func stdoutAndStderrEachStayInWriteOrderWithAlternatingWrites() async throws {
        let live = ShellOutputChunkStream()
        let (runner, state, _) = try makeRunner(outputChunkStream: live)
        let token = ToolContext.makeCompletionToken()
        let afterOut1 = try ShellCommandGate()
        let afterErr1 = try ShellCommandGate()
        let afterOut2 = try ShellCommandGate()
        var events = live.makeAsyncIterator()
        defer { live.finish() }

        let command = """
            printf 'out1\\n'; \(afterOut1.waitCommand)
            printf 'err1\\n' >&2; \(afterErr1.waitCommand)
            printf 'out2\\n'; \(afterOut2.waitCommand)
            printf 'err2\\n' >&2
            """
        let runTask = Task { try await runner.run(.init(command: command, completionToken: token)) }
        defer { runTask.cancel() }
        for (step, gate) in [("out1", afterOut1), ("err1", afterErr1), ("out2", afterOut2)] {
            guard await Self.waitForOutput(containing: step, from: &events) else {
                let result = await runTask.result
                Issue.record("the step \(step) never wrote; the run gave \(result)")
                return
            }
            guard try await Self.release(gate, forCommandOf: token, in: state, run: runTask) else {
                return
            }
        }
        _ = try await runTask.value
        let lines = try await state.getLines(commandID: token)

        // Each line arrived exactly one time — none went away, and none came
        // twice — whatever order the two streams happened to take.
        #expect(lines.count == Self.interleavedLineCount)
        #expect(Set(lines.map(\.text)) == ["out1", "out2", "err1", "err2"])

        // The lines of one stream stand in write order.
        #expect(lines.filter { $0.text.hasPrefix("out") }.map(\.text) == ["out1", "out2"])
        #expect(lines.filter { $0.text.hasPrefix("err") }.map(\.text) == ["err1", "err2"])
    }

    // MARK: - The output reaches the store while the command still runs

    @Test("lines are visible in the store while the command still runs")
    func linesAreVisibleInShellStateWhileTheCommandIsStillRunning() async throws {
        let (runner, state, directory) = try makeRunner()
        let token = ToolContext.makeCompletionToken()
        let (runTask, gate) = try startGatedRun(of: runner, token: token, in: directory)
        defer { runTask.cancel() }

        let lines = try await waitForLines(in: state, commandID: token)
        #expect(lines == [LogLine(lineNumber: 1, text: "one")])

        // The record must still read `running`: the child stays alive until
        // the test opens the gate below.
        let record = await state.record(commandID: token)
        #expect(record?.status == .running)

        try openGate(gate)
        let outcome = try await runTask.value
        #expect(outcome.status == .completed)
    }

    // MARK: - The canceler

    /// The canceler stops a long command and reports `.stopped`.
    ///
    /// `killpg(SIGKILL)` on the own process group of the child is
    /// authoritative, thus the honest outcome is `.stopped` and never
    /// `.cancelled` — the contract of `RunKind.process`.
    @Test("the canceler stops a long command, reports .stopped, and leaves no child")
    func cancelerStopsALongCommandAndReportsStopped() async throws {
        let live = ShellOutputChunkStream()
        let (runner, state, _) = try makeRunner(outputChunkStream: live)
        let token = ToolContext.makeCompletionToken()
        let marker = Self.makeMarker()
        let pattern = "sleep \(marker)"

        let runTask = Task {
            try await runner.run(
                .init(command: "sleep \(marker) & \(Self.readyThenWait)", completionToken: token))
        }
        defer { runTask.cancel() }

        #expect(await Self.waitForReadiness(on: live), "the command never reported that it runs")
        let members = await processIDs(matching: pattern)
        #expect(members.count >= 1, "expected the command to run, saw \(members.count)")

        let outcome = await runner.canceler(completionToken: token)()
        #expect(outcome == .stopped)

        let exited = await exitedCount(of: members)
        #expect(exited == members.count, "the canceler left \(members.count - exited) survivor(s)")

        _ = try? await runTask.value
        let record = try #require(await state.record(commandID: token))
        #expect(record.status == .killed)
    }

    /// The canceler never sends a kill after the run reaped its child.
    ///
    /// After the reap, the kernel can give the pid of the child to a new
    /// process, and that process can lead its own group. A late `killpg` with
    /// the old pid can thus kill an unrelated process — in a parallel run, the
    /// shell of another test.
    ///
    /// The test drives the late path in a fixed order, with no real pid reuse:
    /// a recorder stands in for the kill, and the hook
    /// `cancelerWillSignal` holds the canceler after it took the process group
    /// and before it sends its kill. While the canceler waits there, the test
    /// lets the child end and waits until the run returned, thus until
    /// `Subprocess.run` reaped the child. Only then does the canceler go on.
    /// The kills the recorder holds at the end must be the kills it held when
    /// the run returned.
    @Test("the canceler sends no kill after the run reaped its child")
    func cancelerSendsNoKillAfterTheRunReapedItsChild() async throws {
        let kills = KillRecorder()
        var (runner, state, directory) = try makeRunner()
        let (entered, enteredContinuation) = AsyncStream<Void>.makeStream()
        let (released, releasedContinuation) = AsyncStream<Void>.makeStream()
        runner.signalProcessGroup = { pid in kills.record(pid) }
        runner.cancelerWillSignal = {
            enteredContinuation.yield()
            enteredContinuation.finish()
            for await _ in released {}
        }
        let token = ToolContext.makeCompletionToken()
        let (runTask, gate) = try startGatedRun(of: runner, token: token, in: directory)
        defer { runTask.cancel() }
        defer { releasedContinuation.finish() }

        // The first line is stored inside the body, after the registration of
        // the process group, thus the canceler finds a group to kill.
        _ = try await waitForLines(in: state, commandID: token)
        let canceler = runner.canceler(completionToken: token)
        let cancel = Task { await canceler() }
        for await _ in entered {}

        try openGate(gate)
        _ = try await runTask.value
        let killsAtReap = kills.count

        releasedContinuation.finish()
        #expect(await cancel.value == .stopped)
        #expect(
            kills.count == killsAtReap,
            "the canceler sent \(kills.count - killsAtReap) kill(s) after the run reaped its child")
    }

    /// The canceler signals the whole process group, and not the leader alone:
    /// a command that put a child in the background dies with its tree.
    @Test("the canceler kills the whole process group, and not the leader alone")
    func cancelerKillsTheWholeProcessGroupAndNotTheLeaderAlone() async throws {
        let live = ShellOutputChunkStream()
        let (runner, _, _) = try makeRunner(outputChunkStream: live)
        let token = ToolContext.makeCompletionToken()
        let marker = Self.makeMarker()
        let pattern = "sleep \(marker)"

        let runTask = Task {
            try await runner.run(
                .init(
                    command: "sleep \(marker) & sleep \(marker) & \(Self.readyThenWait)",
                    completionToken: token))
        }
        defer { runTask.cancel() }

        #expect(await Self.waitForReadiness(on: live), "the sleep tree never reported that it runs")
        let members = await processIDs(matching: pattern)
        #expect(members.count >= Self.treeMemberCount, "expected the sleep tree to run, saw \(members.count)")

        let outcome = await runner.canceler(completionToken: token)()
        #expect(outcome == .stopped)

        let exited = await exitedCount(of: members)
        #expect(exited == members.count, "the canceler left \(members.count - exited) member(s) of the group alive")

        _ = try? await runTask.value
    }

    // MARK: - The wall clock of the time limit, and the default of no limit

    /// The gated command cannot end by itself: it ends only when the test
    /// opens its gate, and the test holds the gate shut until the run ended.
    /// Thus a run that ends proves that the limit killed the command, and the
    /// clock proves that the limit the request named is the one that fired.
    @Test("the requested time limit kills well before the command would end")
    func requestedTimeoutKillsWellBeforeTheCommandWouldFinish() async throws {
        let clock = GatedClock()
        let (runner, _, directory) = try makeRunner(clock: clock)
        let token = ToolContext.makeCompletionToken()
        let (runTask, gate) = try startGatedRun(
            of: runner, token: token, in: directory, timeout: Self.shortTimeout)
        defer { runTask.cancel() }

        clock.open()
        let outcome = try await runTask.value

        #expect(outcome.status == .timedOut)
        #expect(outcome.exitCode == Self.absentExitCode)
        #expect(clock.recordedSleeps == [Self.shortTimeout])
        try openGate(gate)
    }

    /// With no limit the command runs to its own end. The command writes one
    /// line and then waits on a `ShellCommandGate`, thus it cannot end before
    /// the test releases it. The test waits until the store holds that line,
    /// thus the child registered its pid. The release returns only after the
    /// command opened the FIFO, or after the command exited, thus no wait
    /// stays open. The command then ends by itself. The timer of a limit
    /// sleeps on the `GatedClock` of the runner. A clock that recorded no
    /// sleep proves that the runner started no timer at all.
    @Test("no time limit applies when the request asks for none")
    func noTimeoutIsAppliedWhenNoneRequested() async throws {
        let clock = GatedClock()
        let (runner, state, _) = try makeRunner(clock: clock)
        let token = ToolContext.makeCompletionToken()
        let gate = try ShellCommandGate()

        let runTask = Task {
            try await runner.run(
                .init(command: "printf 'ready\\n'; \(gate.waitCommand)", completionToken: token))
        }
        defer { runTask.cancel() }
        await state.waitForStoredLines(commandID: token, atLeast: 1)
        guard try await Self.release(gate, forCommandOf: token, in: state, run: runTask) else {
            return
        }
        let outcome = try await runTask.value

        #expect(outcome.status == .completed)
        #expect(outcome.exitCode == 0)
        #expect(clock.recordedSleeps.isEmpty, "a run with no limit slept on its clock: \(clock.recordedSleeps)")
    }

    // MARK: - The registry across one run

    /// `run(_:)` registers the pid of the child right after
    /// `state.registerProcess` — thus it is visible in the registry while the
    /// command still runs — and it deregisters the pid on the teardown, thus a
    /// run that ended leaves a private registry empty again.
    @Test("a run registers its child while it runs, and deregisters it at the end")
    func runRegistersTheChildDuringExecutionAndDeregistersAfterCompletion() async throws {
        let registry = ProcessRegistry()
        let (runner, state, directory) = try makeRunner(registry: registry)
        let token = ToolContext.makeCompletionToken()
        let (runTask, gate) = try startGatedRun(of: runner, token: token, in: directory)
        defer { runTask.cancel() }

        // The line arrives only after the child started, and the child stays
        // alive until the test opens the gate. Thus the registry certainly
        // holds the pid at this point.
        _ = try await waitForLines(in: state, commandID: token)
        #expect(
            !registry.registeredPids.isEmpty,
            "expected the pid of the child to be registered while it runs")

        try openGate(gate)
        _ = try await runTask.value

        #expect(
            registry.registeredPids.isEmpty,
            "expected the registry to be empty once the run ended")
    }

    // MARK: - The record is finalized when the body throws

    /// The child never spawns — the working directory does not exist — thus the
    /// spawn throws before the body of the run ever starts. The record that
    /// `startCommand` made must not stay `running` for ever.
    @Test("a working directory that is absent finalizes the record instead of leaving it running")
    func nonExistentWorkingDirectoryFinalizesTheRecordInsteadOfLeavingItRunning() async throws {
        let (runner, state, directory) = try makeRunner()
        let token = ToolContext.makeCompletionToken()
        let missing = directory.appendingPathComponent("does-not-exist", isDirectory: true)

        await #expect(throws: (any Error).self) {
            _ = try await runner.run(
                .init(command: "echo hi", completionToken: token, workingDirectory: missing.path))
        }

        let record = try #require(await state.record(commandID: token))
        #expect(record.status != .running)
        #expect(record.completedAt != nil)
    }

    /// The child spawns and writes output, but the output pipeline itself throws
    /// while the run goes on — here `state.appendLines` fails, because the log
    /// file it writes to is gone. That is the "died after a failed log write"
    /// path, which differs from a failed spawn and needs the same finalize
    /// before the rethrow.
    @Test("a failed log write finalizes the record instead of leaving it running")
    func appendLinesFailureMidRunFinalizesTheRecordInsteadOfLeavingItRunning() async throws {
        let (runner, state, _) = try makeRunner()
        let token = ToolContext.makeCompletionToken()

        // `ShellState.init` makes the log file. Removing it makes the next
        // `FileHandle(forWritingTo:)` of `appendLines` throw.
        try FileManager.default.removeItem(at: state.logURL)

        await #expect(throws: (any Error).self) {
            _ = try await runner.run(.init(command: "echo hi", completionToken: token))
        }

        let record = try #require(await state.record(commandID: token))
        #expect(record.status != .running)
        #expect(record.completedAt != nil)
    }

    // MARK: - The spawn goes through `CommandSandbox`

    /// Seatbelt matches the path of the vnode that the kernel resolved, thus the
    /// runner owes `wrap` directories with each symbolic link followed: `/tmp`
    /// must arrive as `/private/tmp`, and `$TMPDIR` in its
    /// `/private/var/folders/…` form with no trailing separator.
    @Test("the runner gives the sandbox resolved directories")
    func runnerPassesResolvedDirectoriesToSandbox() async throws {
        var (runner, _, _) = try makeRunner()
        let sandbox = RecordingSandbox()
        runner.sandbox = sandbox
        let token = ToolContext.makeCompletionToken()

        _ = try await runner.run(
            .init(command: "echo hi", completionToken: token, workingDirectory: "/tmp"))

        let call = try #require(sandbox.calls.first)
        // The expected form goes through `ShellRunner.resolvedDirectory(path:)`,
        // the one directory resolver and the one the runner itself calls. It
        // carries BOTH steps — the trailing separator that
        // `NSTemporaryDirectory()` holds comes off, then `resolvedPath` follows
        // each symbolic link — thus a test that reached past it to `resolvedPath`
        // alone would state a path the runner never hands over, and nothing
        // would report the disagreement.
        let resolvedTemporary = ShellRunner.resolvedDirectory(path: NSTemporaryDirectory())
        #expect(call.shellPath == "/bin/sh")
        #expect(call.shellArguments == ["-c", "echo hi"])
        #expect(call.workingDirectory == "/private/tmp")
        #expect(call.temporaryDirectory == resolvedTemporary)
        #expect(
            call.temporaryDirectory.hasPrefix("/private/"),
            "the temporary directory reached the sandbox unresolved: \(call.temporaryDirectory)")
        #expect(!call.temporaryDirectory.hasSuffix("/"))
    }

    /// What `wrap` gives back is what spawns: the fake replaces the argv of the
    /// request, thus the recorded output of the command proves the decorated
    /// invocation — and not `request.command` — reached the spawn.
    @Test("the runner spawns the decorated invocation")
    func runnerSpawnsDecoratedInvocation() async throws {
        var (runner, state, _) = try makeRunner()
        runner.sandbox = RecordingSandbox(
            returning: SandboxedInvocation(
                executable: "/bin/sh", arguments: ["-c", "echo decorated"]))
        let token = ToolContext.makeCompletionToken()

        let outcome = try await runner.run(.init(command: "echo hi", completionToken: token))

        #expect(outcome.status == .completed)
        #expect(outcome.exitCode == 0)
        let lines = try await state.getLines(commandID: token)
        #expect(lines.map(\.text) == ["decorated"])
    }

    /// The default path — no sandbox — spawns `/bin/sh -c command` exactly as it
    /// always has, with no new code between the request and the child.
    @Test("no sandbox spawns the shell directly")
    func nilSandboxSpawnsShellDirectly() async throws {
        let (runner, state, _) = try makeRunner()
        #expect(runner.sandbox == nil)
        let token = ToolContext.makeCompletionToken()

        let outcome = try await runner.run(.init(command: "echo plain", completionToken: token))

        #expect(outcome.status == .completed)
        #expect(outcome.exitCode == 0)
        let lines = try await state.getLines(commandID: token)
        #expect(lines.map(\.text) == ["plain"])
    }

    /// A sandbox that cannot build its confinement must stop the command dead:
    /// the error reaches the caller, and nothing runs unconfined. The command
    /// would make a marker file if it ever spawned, thus the absence of that
    /// file proves no child ran.
    @Test("a sandbox that throws fails closed")
    func throwingSandboxFailsClosed() async throws {
        var (runner, _, directory) = try makeRunner()
        let sandbox = RecordingSandbox(throwing: .refused)
        runner.sandbox = sandbox
        let marker = directory.appendingPathComponent("spawned.marker")
        let token = ToolContext.makeCompletionToken()

        await #expect(throws: RecordingSandboxError.refused) {
            _ = try await runner.run(
                .init(command: "/usr/bin/touch \(marker.path)", completionToken: token))
        }

        #expect(sandbox.calls.count == 1)
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    /// A `wrap` that throws must happen inside the same `do`/`catch` that
    /// finalizes a failed spawn, or the record `startCommand` made stays
    /// `running` for ever and the run plane reports a command that never
    /// existed.
    @Test("a sandbox that throws finalizes the record")
    func throwingSandboxFinalizesRecord() async throws {
        var (runner, state, _) = try makeRunner()
        runner.sandbox = RecordingSandbox(throwing: .refused)
        let token = ToolContext.makeCompletionToken()

        await #expect(throws: RecordingSandboxError.refused) {
            _ = try await runner.run(.init(command: "echo hi", completionToken: token))
        }

        let record = try #require(await state.record(commandID: token))
        #expect(record.status == .completed)
        #expect(record.exitCode == Self.absentExitCode)
        #expect(record.completedAt != nil)
    }

    /// The resolution step on its own, with no spawn: `/tmp` is a symbolic link
    /// to `/private/tmp` on macOS, and a grant for the unresolved form denies
    /// silently.
    @Test("the resolved sandbox directories follow symbolic links")
    func resolvedSandboxDirectoriesResolvesSymlinks() {
        let token = ToolContext.makeCompletionToken()
        let directories = ShellRunner.resolvedSandboxDirectories(
            request: .init(
                command: "echo hi", completionToken: token, workingDirectory: "/tmp"),
            defaultWorkingDirectory: nil)

        // The one directory resolver again, and never `resolvedPath` alone: the
        // trim of the trailing separator belongs to that step, thus a test that
        // skipped it would state a `$TMPDIR` the runner never hands over.
        let resolvedTemporary = ShellRunner.resolvedDirectory(path: NSTemporaryDirectory())
        #expect(directories.work == "/private/tmp")
        #expect(directories.tmp == resolvedTemporary)
        #expect(
            directories.tmp.hasPrefix("/private/"),
            "the temporary directory stayed unresolved: \(directories.tmp)")
        #expect(!directories.tmp.hasSuffix("/"))
    }

    /// The default of the runner goes through the same resolution the named
    /// case takes: a default that is a symbolic link reaches the sandbox in its
    /// resolved form, thus the grant matches the vnode the kernel sees.
    @Test("the resolved sandbox directories take the runner default when the request names none")
    func resolvedSandboxDirectoriesTakesTheRunnerDefault() {
        let token = ToolContext.makeCompletionToken()
        let directories = ShellRunner.resolvedSandboxDirectories(
            request: .init(command: "echo hi", completionToken: token),
            defaultWorkingDirectory: "/tmp")

        #expect(directories.work == "/private/tmp")
    }

    /// The one place that spells the fallback, proved with no runner and no
    /// spawn: the request first, then the default of the runner, then the
    /// current directory of this process. No path here is resolved, thus none
    /// of them has to exist.
    @Test("the effective working directory prefers the request, then the default, then the process directory")
    func effectiveWorkingDirectoryPrefersTheRequestThenTheDefault() {
        let token = ToolContext.makeCompletionToken()
        let named = ShellRunner.Request(
            command: "echo hi", completionToken: token,
            workingDirectory: Self.requestedDirectory)
        let unnamed = ShellRunner.Request(command: "echo hi", completionToken: token)

        #expect(
            ShellRunner.effectiveWorkingDirectory(
                for: named, defaultWorkingDirectory: Self.defaultDirectory)
                == Self.requestedDirectory)
        #expect(
            ShellRunner.effectiveWorkingDirectory(
                for: unnamed, defaultWorkingDirectory: Self.defaultDirectory)
                == Self.defaultDirectory)
        #expect(
            ShellRunner.effectiveWorkingDirectory(for: unnamed, defaultWorkingDirectory: nil)
                == FileManager.default.currentDirectoryPath)
    }

    /// With no working directory in the request and no default on the runner,
    /// the command runs in the current directory of this process, thus that is
    /// what the sandbox must be told about — put through the same resolution
    /// the named case takes, thus both branches meet the path precondition of
    /// `CommandSandbox`.
    ///
    /// The test states the resolved form, and the absence of a trailing
    /// separator, and it does not compare against the raw
    /// `currentDirectoryPath`. The two spellings are in fact always equal here,
    /// and that is a property of the input and not of the code under test:
    /// `currentDirectoryPath` comes from `getcwd(3)`, which gives the physical
    /// path with each symbolic link already followed. Thus no assertion on this
    /// branch can tell a resolver that ran from one that was skipped;
    /// `resolvedSandboxDirectoriesResolvesSymlinks` pins that behavior on an
    /// input that can carry a symbolic link. What this case pins is the contract
    /// at the boundary.
    @Test("the resolved sandbox directories fall back to the current directory")
    func resolvedSandboxDirectoriesFallsBackToCurrentDirectory() {
        let token = ToolContext.makeCompletionToken()
        let directories = ShellRunner.resolvedSandboxDirectories(
            request: .init(command: "echo hi", completionToken: token),
            defaultWorkingDirectory: nil)

        let resolvedCurrent = ShellRunner.resolvedDirectory(
            path: FileManager.default.currentDirectoryPath)
        #expect(directories.work == resolvedCurrent)
        #expect(!directories.work.hasSuffix("/"))
    }

    /// The trailing separator comes off even when the path resolves to nothing.
    ///
    /// `realpath(3)` drops a trailing separator of a path that IS there, thus
    /// every other case of this suite stays green with the trim taken out. A
    /// path that is not there is the one input that tells the two apart: the
    /// resolver gives the input back, and a Seatbelt grant must not carry the
    /// separator.
    @Test("the resolved directory drops a trailing separator it cannot resolve")
    func resolvedDirectoryDropsTheTrailingSeparatorOfAnAbsentPath() {
        let resolved = ShellRunner.resolvedDirectory(path: Self.absentDirectoryWithSeparator)

        #expect(resolved == Self.absentDirectory)
    }
}

/// The failure a `RecordingSandbox` raises when it is set to refuse.
///
/// A case of its own, thus a test can state that the RUNNER carried the error of
/// the sandbox up, and not some other failure of the spawn.
enum RecordingSandboxError: Error, Equatable, Sendable {

    /// The fake was asked to fail closed, and to give back no invocation.
    case refused
}

/// A `CommandSandbox` that records each `wrap` call, and that gives back an
/// invocation the test chose — or throws the failure the test chose.
///
/// A reference type, thus the test reads the calls that the copy of the runner
/// made. A runner is a value, and it is copied.
final class RecordingSandbox: CommandSandbox {

    /// The inputs of one recorded `wrap` call, in the order `CommandSandbox`
    /// states them.
    struct Call: Equatable, Sendable {
        /// The absolute path of the shell the runner asked to confine.
        let shellPath: String
        /// The arguments of that shell.
        let shellArguments: [String]
        /// The working directory the runner gave, resolved.
        let workingDirectory: String
        /// The temporary directory the runner gave, resolved.
        let temporaryDirectory: String
    }

    /// The invocation each successful `wrap` gives back.
    private let invocation: SandboxedInvocation?

    /// The failure each `wrap` throws, or `nil` to give back an invocation.
    private let failure: RecordingSandboxError?

    /// Each `wrap` call so far, in call order.
    private let recorded = Mutex<[Call]>([])

    /// Makes a fake sandbox.
    ///
    /// - Parameters:
    ///   - invocation: The invocation `wrap` gives back, or `nil` to give back
    ///     the shell invocation it received.
    ///   - failure: The failure `wrap` throws, or `nil` to give back an
    ///     invocation.
    init(
        returning invocation: SandboxedInvocation? = nil,
        throwing failure: RecordingSandboxError? = nil
    ) {
        self.invocation = invocation
        self.failure = failure
    }

    /// Each `wrap` call so far, in call order.
    var calls: [Call] {
        recorded.withLock { $0 }
    }

    /// Records the call, then gives back the chosen invocation or throws the
    /// chosen failure.
    ///
    /// - Parameters:
    ///   - shellPath: The absolute path of the shell to run.
    ///   - shellArguments: The arguments of that shell.
    ///   - workingDirectory: The absolute working directory, resolved.
    ///   - temporaryDirectory: The absolute temporary directory, resolved.
    /// - Returns: The chosen invocation, or the shell invocation as it came in.
    /// - Throws: The `RecordingSandboxError` this fake was made with, if any.
    func wrap(
        shellPath: String,
        shellArguments: [String],
        workingDirectory: String,
        temporaryDirectory: String
    ) throws -> SandboxedInvocation {
        recorded.withLock {
            $0.append(
                Call(
                    shellPath: shellPath, shellArguments: shellArguments,
                    workingDirectory: workingDirectory, temporaryDirectory: temporaryDirectory))
        }
        if let failure {
            throw failure
        }
        return invocation ?? SandboxedInvocation(
            executable: shellPath, arguments: shellArguments)
    }
}
