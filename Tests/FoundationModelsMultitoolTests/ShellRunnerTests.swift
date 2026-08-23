import Foundation
import FoundationModelsRouter
import Synchronization
import Testing

@testable import FoundationModelsMultitool

/// Behavioral tests for `ShellRunner` — real `sh -c` children, each one spawned
/// into a new `ShellState` that a temporary directory roots.
///
/// These tests start genuine child processes (`echo`, trees of `sleep`,
/// `pgrep`). Each test that starts a tree cleans it up, through the group-kill
/// of the runner itself or through the canceler, thus nothing leaks from one
/// test to the next.
///
/// Each run here carries a completion token that
/// `SessionMailbox.makeCompletionToken()` mints. eventplan.md § "Consolidation
/// of the siblings" makes the `commandID` of a shell run its `correlationID` and
/// its `completionToken` — one string on two planes — thus the tests mint a
/// token exactly as the elevation engine does.
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

    /// How long a poll of the process table or of the log waits between reads.
    private static let pollInterval = Duration.milliseconds(25)

    /// How long a test waits for a process tree to come up.
    private static let treeStartDeadline = Duration.seconds(2)

    /// How long a test waits for a process tree to go away after a kill.
    private static let treeExitDeadline = Duration.seconds(5)

    /// How long a test waits for a line of output to reach the store.
    private static let outputArrivalDeadline = Duration.seconds(3)

    /// The time limit the run of the group-kill test carries. It is short, thus
    /// the timer fires long before the sleeps end.
    private static let treeKillTimeout = Duration.seconds(2)

    /// The time limit of the test that proves a limit kills the command.
    private static let shortTimeout = Duration.milliseconds(400)

    /// The longest a run under `shortTimeout` may take. It stands far below the
    /// sleep the command asks for, thus a run that reaches it proves the limit
    /// fired.
    private static let timeoutUpperBound = Duration.seconds(3)

    /// The shortest a `sleep 1` with no time limit may take. A run below it
    /// proves a limit fired that nobody asked for.
    private static let unlimitedSleepLowerBound = Duration.milliseconds(900)

    /// A `ShellRunner` over a `ShellState` that a new temporary directory roots.
    ///
    /// `scratch` owns that directory from the moment it exists, thus a throw
    /// from `ShellState.init` cannot leave behind a directory whose path no
    /// caller learned, and no caller has to remove it.
    ///
    /// - Parameter registry: The process-group registry to give the runner. The
    ///   default is a new PRIVATE `ProcessRegistry()`, and never `.global`, thus
    ///   an ordinary test never touches the process-wide instance. Give one
    ///   here when a test must read the state of the registry.
    /// - Returns: The runner, its store, and the temporary directory.
    /// - Throws: What `TestScratch.makeDirectory` or `ShellState.init` throws.
    private func makeRunner(
        registry: ProcessRegistry = ProcessRegistry()
    ) throws -> (runner: ShellRunner, state: ShellState, directory: URL) {
        let directory = try scratch.makeDirectory(prefix: Self.testDirectoryNamePrefix)
        let state = try ShellState(
            preferredDirectory: directory.appendingPathComponent(Self.shellStoreDirectoryName))
        return (ShellRunner(state: state, registry: registry), state, directory)
    }

    /// A sleep duration no other test uses, thus `pgrep -f` on it matches the
    /// process tree of one test only.
    ///
    /// - Returns: The marker, in whole seconds.
    private static func makeMarker() -> Int {
        Int.random(in: markerLowerBound...markerUpperBound)
    }

    /// Counts the live processes whose whole command line matches `pattern`,
    /// through `pgrep -f`.
    ///
    /// - Parameter pattern: The pattern `pgrep -f` reads.
    /// - Returns: The number of matches, and 0 when `pgrep` finds none.
    private func processCount(matching pattern: String) -> Int {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-f", pattern]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return 0
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        return text.split(separator: "\n").filter { !$0.isEmpty }.count
    }

    /// Polls `processCount(matching:)` until `predicate` accepts the count, or
    /// until `deadline` passes.
    ///
    /// - Parameters:
    ///   - pattern: The pattern `pgrep -f` reads.
    ///   - deadline: How long to keep polling.
    ///   - predicate: What the count must satisfy.
    /// - Returns: The last count the poll read.
    private func waitForProcessCount(
        matching pattern: String,
        deadline: Duration,
        until predicate: (Int) -> Bool
    ) async -> Int {
        let clock = ContinuousClock()
        let start = clock.now
        var count = processCount(matching: pattern)
        while !predicate(count), clock.now - start < deadline {
            try? await Task.sleep(for: Self.pollInterval)
            count = processCount(matching: pattern)
        }
        return count
    }

    /// Polls the log of `commandID` until it holds a line, or until the arrival
    /// deadline passes.
    ///
    /// - Parameters:
    ///   - state: The store to read.
    ///   - commandID: The completion token of the run.
    /// - Returns: The lines the last read gave, which is empty when none
    ///   arrived.
    /// - Throws: What `ShellState.getLines` throws.
    private func waitForLines(in state: ShellState, commandID: String) async throws -> [LogLine] {
        let clock = ContinuousClock()
        let start = clock.now
        var lines = try await linesOnceStarted(in: state, commandID: commandID)
        while lines.isEmpty, clock.now - start < Self.outputArrivalDeadline {
            try? await Task.sleep(for: Self.pollInterval)
            lines = try await linesOnceStarted(in: state, commandID: commandID)
        }
        return lines
    }

    /// The lines of `commandID`, and an empty array while no command started
    /// under that token yet.
    ///
    /// `run(_:)` makes the record of a run inside the task that a test starts,
    /// thus a poll of the store can arrive BEFORE that task ran at all. The
    /// window is real, and it is the ordinary case: a test creates the task and
    /// then reaches the store at once, thus the read wins the race against a
    /// task that the runtime did not schedule yet. `getLines` reports an unknown
    /// token in that window, and "the run did not start yet" is exactly "no line
    /// yet" to a poll.
    ///
    /// The guard reads the record first, and the record is what `startCommand`
    /// makes, thus a token that has a record cannot make `getLines` report an
    /// unknown token. Each other failure of the store still travels up, thus a
    /// log that does not read still fails the test.
    ///
    /// - Parameters:
    ///   - state: The store to read.
    ///   - commandID: The completion token of the run.
    /// - Returns: The lines of the run, or an empty array while it did not start.
    /// - Throws: What `ShellState.getLines` throws.
    private func linesOnceStarted(
        in state: ShellState, commandID: String
    ) async throws -> [LogLine] {
        guard await state.record(commandID: commandID) != nil else { return [] }
        return try await state.getLines(commandID: commandID)
    }

    // MARK: - The kill of a process group takes down the whole tree

    /// The load-bearing test: a `sh -c 'sleep N & sleep N'` tree that the
    /// own-process-group spawn of the runner started must die whole when the
    /// time limit fires the group kill. No `sleep` survives.
    @Test("the group kill at the time limit leaves no survivor in the process tree")
    func timeoutGroupKillLeavesNoSurvivorsInProcessTree() async throws {
        let (runner, _, _) = try makeRunner()
        let token = SessionMailbox.makeCompletionToken()

        let marker = Self.makeMarker()
        let pattern = "sleep \(marker)"

        let runTask = Task {
            try await runner.run(
                .init(
                    command: "sleep \(marker) & sleep \(marker)", completionToken: token,
                    timeout: Self.treeKillTimeout))
        }
        defer { runTask.cancel() }

        let alive = await waitForProcessCount(
            matching: pattern, deadline: Self.treeStartDeadline,
            until: { $0 >= Self.treeMemberCount })
        #expect(alive >= Self.treeMemberCount, "expected the sleep tree to run, saw \(alive)")

        let outcome = try await runTask.value
        #expect(outcome.status == .timedOut)
        #expect(outcome.exitCode == Self.absentExitCode)

        let survivors = await waitForProcessCount(
            matching: pattern, deadline: Self.treeExitDeadline, until: { $0 == 0 })
        #expect(survivors == 0, "the group kill left \(survivors) survivor(s)")
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
        let token = SessionMailbox.makeCompletionToken()

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
        let token = SessionMailbox.makeCompletionToken()

        let outcome = try await runner.run(.init(command: "exit 0", completionToken: token))
        #expect(outcome.status == .completed)
        #expect(outcome.exitCode == 0)
    }

    @Test("an exit code that is not zero is reported, and it is not a thrown error")
    func nonZeroExitIsReportedAndNotAThrownError() async throws {
        let (runner, _, _) = try makeRunner()
        let token = SessionMailbox.makeCompletionToken()

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
        let token = SessionMailbox.makeCompletionToken()

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
        let token = SessionMailbox.makeCompletionToken()

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
        let token = SessionMailbox.makeCompletionToken()
        let workDirectory = directory.appendingPathComponent("work", isDirectory: true)
        try FileManager.default.createDirectory(
            at: workDirectory, withIntermediateDirectories: true)

        _ = try await runner.run(
            .init(
                command: "/bin/pwd", completionToken: token,
                workingDirectory: workDirectory.path))

        let lines = try await state.getLines(commandID: token)
        let printed = lines.first?.text ?? "<none>"
        // `/bin/pwd` prints the physical directory (`/var` becomes
        // `/private/var` on macOS), thus the two sides compare resolved.
        let expected = workDirectory.resolvingSymlinksInPath().path
        let actual = URL(fileURLWithPath: printed).resolvingSymlinksInPath().path
        #expect(actual == expected, "pwd printed \(printed); expected \(expected)")
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
        let token = SessionMailbox.makeCompletionToken()

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
        let token = SessionMailbox.makeCompletionToken()

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
    @Test("standard output and standard error each keep their own write order")
    func stdoutAndStderrEachStayInWriteOrderWithAlternatingWrites() async throws {
        let (runner, state, _) = try makeRunner()
        let token = SessionMailbox.makeCompletionToken()

        let command = """
            printf 'out1\\n'; sleep 0.05
            printf 'err1\\n' >&2; sleep 0.05
            printf 'out2\\n'; sleep 0.05
            printf 'err2\\n' >&2
            """
        _ = try await runner.run(.init(command: command, completionToken: token))
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
        let (runner, state, _) = try makeRunner()
        let token = SessionMailbox.makeCompletionToken()

        let runTask = Task {
            try await runner.run(.init(command: "echo one; sleep 5", completionToken: token))
        }
        defer { runTask.cancel() }

        let lines = try await waitForLines(in: state, commandID: token)
        #expect(lines == [LogLine(lineNumber: 1, text: "one")])

        // The record must still read `running`: the line landed well before the
        // child ends.
        let record = try #require(await state.record(commandID: token))
        #expect(record.status == .running)

        _ = await runner.canceler(completionToken: token)()
        _ = try? await runTask.value
    }

    // MARK: - The canceler

    /// The canceler stops a long command and reports `.stopped`.
    ///
    /// `killpg(SIGKILL)` on the own process group of the child is
    /// authoritative, thus the honest outcome is `.stopped` and never
    /// `.cancelled` — the contract of `RunKind.process`.
    @Test("the canceler stops a long command, reports .stopped, and leaves no child")
    func cancelerStopsALongCommandAndReportsStopped() async throws {
        let (runner, state, _) = try makeRunner()
        let token = SessionMailbox.makeCompletionToken()
        let marker = Self.makeMarker()
        let pattern = "sleep \(marker)"

        let runTask = Task {
            try await runner.run(.init(command: "sleep \(marker)", completionToken: token))
        }
        defer { runTask.cancel() }

        let alive = await waitForProcessCount(
            matching: pattern, deadline: Self.treeStartDeadline, until: { $0 >= 1 })
        #expect(alive >= 1, "expected the command to run, saw \(alive)")

        let outcome = await runner.canceler(completionToken: token)()
        #expect(outcome == .stopped)

        let survivors = await waitForProcessCount(
            matching: pattern, deadline: Self.treeExitDeadline, until: { $0 == 0 })
        #expect(survivors == 0, "the canceler left \(survivors) survivor(s)")

        _ = try? await runTask.value
        let record = try #require(await state.record(commandID: token))
        #expect(record.status == .killed)
    }

    /// The canceler signals the whole process group, and not the leader alone:
    /// a command that put a child in the background dies with its tree.
    @Test("the canceler kills the whole process group, and not the leader alone")
    func cancelerKillsTheWholeProcessGroupAndNotTheLeaderAlone() async throws {
        let (runner, _, _) = try makeRunner()
        let token = SessionMailbox.makeCompletionToken()
        let marker = Self.makeMarker()
        let pattern = "sleep \(marker)"

        let runTask = Task {
            try await runner.run(
                .init(
                    command: "sleep \(marker) & sleep \(marker)", completionToken: token))
        }
        defer { runTask.cancel() }

        let alive = await waitForProcessCount(
            matching: pattern, deadline: Self.treeStartDeadline,
            until: { $0 >= Self.treeMemberCount })
        #expect(alive >= Self.treeMemberCount, "expected the sleep tree to run, saw \(alive)")

        let outcome = await runner.canceler(completionToken: token)()
        #expect(outcome == .stopped)

        let survivors = await waitForProcessCount(
            matching: pattern, deadline: Self.treeExitDeadline, until: { $0 == 0 })
        #expect(survivors == 0, "the canceler left \(survivors) member(s) of the group alive")

        _ = try? await runTask.value
    }

    // MARK: - The wall clock of the time limit, and the default of no limit

    @Test("the requested time limit kills well before the command would end")
    func requestedTimeoutKillsWellBeforeTheCommandWouldFinish() async throws {
        let (runner, _, _) = try makeRunner()
        let token = SessionMailbox.makeCompletionToken()

        let clock = ContinuousClock()
        let start = clock.now
        let outcome = try await runner.run(
            .init(command: "sleep 30", completionToken: token, timeout: Self.shortTimeout))
        let elapsed = clock.now - start

        #expect(outcome.status == .timedOut)
        #expect(outcome.exitCode == Self.absentExitCode)
        #expect(
            elapsed < Self.timeoutUpperBound,
            "the time limit took \(elapsed), expected well under the 30 second sleep")
    }

    @Test("no time limit applies when the request asks for none")
    func noTimeoutIsAppliedWhenNoneRequested() async throws {
        let (runner, _, _) = try makeRunner()
        let token = SessionMailbox.makeCompletionToken()

        // With no limit the command runs to its own end. A limit short enough
        // to kill it would have to stand below one second, and there is none.
        let clock = ContinuousClock()
        let start = clock.now
        let outcome = try await runner.run(.init(command: "sleep 1", completionToken: token))
        let elapsed = clock.now - start

        #expect(outcome.status == .completed)
        #expect(outcome.exitCode == 0)
        #expect(
            elapsed >= Self.unlimitedSleepLowerBound,
            "sleep 1 ended suspiciously early (\(elapsed))")
    }

    // MARK: - The registry across one run

    /// `run(_:)` registers the pid of the child right after
    /// `state.registerProcess` — thus it is visible in the registry while the
    /// command still runs — and it deregisters the pid on the teardown, thus a
    /// run that ended leaves a private registry empty again.
    @Test("a run registers its child while it runs, and deregisters it at the end")
    func runRegistersTheChildDuringExecutionAndDeregistersAfterCompletion() async throws {
        let registry = ProcessRegistry()
        let (runner, state, _) = try makeRunner(registry: registry)
        let token = SessionMailbox.makeCompletionToken()

        let runTask = Task {
            try await runner.run(.init(command: "echo one; sleep 0.3", completionToken: token))
        }
        defer { runTask.cancel() }

        // The line arrives only after the child started, thus the registry
        // certainly holds the pid at this point.
        _ = try await waitForLines(in: state, commandID: token)
        #expect(
            !registry.registeredPids.isEmpty,
            "expected the pid of the child to be registered while it runs")

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
        let token = SessionMailbox.makeCompletionToken()
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
        let token = SessionMailbox.makeCompletionToken()

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
        let token = SessionMailbox.makeCompletionToken()

        _ = try await runner.run(
            .init(command: "echo hi", completionToken: token, workingDirectory: "/tmp"))

        let call = try #require(sandbox.calls.first)
        // The expected form goes through `resolvedPath`, the one resolver of the
        // module and the one the runner itself calls. A second copy of that step
        // here could name a path the confinement does not enforce, and nothing
        // would report the disagreement.
        let resolvedTemporary = resolvedPath(NSTemporaryDirectory())
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
        let token = SessionMailbox.makeCompletionToken()

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
        let token = SessionMailbox.makeCompletionToken()

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
        let token = SessionMailbox.makeCompletionToken()

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
        let token = SessionMailbox.makeCompletionToken()

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
        let token = SessionMailbox.makeCompletionToken()
        let directories = ShellRunner.resolvedSandboxDirectories(
            request: .init(
                command: "echo hi", completionToken: token, workingDirectory: "/tmp"))

        let resolvedTemporary = resolvedPath(NSTemporaryDirectory())
        #expect(directories.work == "/private/tmp")
        #expect(directories.tmp == resolvedTemporary)
        #expect(
            directories.tmp.hasPrefix("/private/"),
            "the temporary directory stayed unresolved: \(directories.tmp)")
        #expect(!directories.tmp.hasSuffix("/"))
    }

    /// With no working directory in the request, the command runs in the current
    /// directory of this process, thus that is what the sandbox must be told
    /// about — put through the same resolution the named case takes, thus both
    /// branches meet the path precondition of `CommandSandbox`.
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
        let token = SessionMailbox.makeCompletionToken()
        let directories = ShellRunner.resolvedSandboxDirectories(
            request: .init(command: "echo hi", completionToken: token))

        let resolvedCurrent = resolvedPath(FileManager.default.currentDirectoryPath)
        #expect(directories.work == resolvedCurrent)
        #expect(!directories.work.hasSuffix("/"))
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
