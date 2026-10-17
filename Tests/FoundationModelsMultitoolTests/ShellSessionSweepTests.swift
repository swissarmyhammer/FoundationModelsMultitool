import Foundation
import FoundationModels
import FoundationModelsExtras
import Testing

@testable import FoundationModelsMultitool
@testable import FoundationModelsRouter
@testable import MultitoolTestSupport

/// Coverage for the session-end sweep of a background shell run — eventplan.md:
/// *"Background runs die with the session."* Teardown does one deterministic
/// sweep of the run plane, and it processes each kind with that kind's own
/// semantics: *"Shell runs get `killpg(SIGKILL)` and post `.stopped`."*
///
/// The route this suite proves has three owners:
///
/// 1. `Execute` declares, through `BackgroundTool`, that its runs
///    are `RunKind.process` and that `ShellRunner.canceler(completionToken:)`
///    stops one. `BackgroundToolRunner` hands both to `RunPlane.start`.
/// 2. `RunPlane.sweep()` walks the background runs in the order they
///    were tracked, awaits each canceler, and answers exactly one terminal
///    event for each run.
/// 3. `RoutedSessionActor.close()` journals one terminal event for each run
///    before it returns. A run that settles by itself while the sweep waits on
///    the canceler of an earlier run reaches the journal at its own settle,
///    thus the order of the events in the journal is NOT the order of the
///    sweep, and no test here reads that order.
///
/// The tests drive step 2, which is the step that turns a session teardown into
/// a dead process group. Step 3 journals each terminal event, thus a sweep
/// that answers one terminal event for each background run and leaves the run
/// plane empty is a durable record with no hole and no orphan.
///
/// **The run plane of a session is `internal` to Router**, thus this file takes
/// `@testable import FoundationModelsRouter`. The other route to the sweep is
/// `RoutedSession.close()`, which needs a loaded model, and a unit test must
/// not need one.
///
/// Each test spawns real `sh` children, exactly as `ShellRunnerTests` and
/// `ShellExecuteTests` do: the shell is what the capability spawns itself, so
/// this stays a unit test of the wiring rather than an integration test of a
/// service. Each test kills the process group it spawned, through the sweep it
/// is testing, and every signal this file sends goes to a group this file
/// spawned and to no other.
@Suite("ShellSessionSweepTests")
struct ShellSessionSweepTests {

    /// Owns the temporary directories this test makes. Thus they go away when
    /// the test ends, and they do not collect in `$TMPDIR` run after run.
    private let scratch = TestScratch()

    /// The name prefix of the temporary directory of one test. Thus a leaked
    /// directory is traceable to this suite.
    private static let testDirectoryNamePrefix = "shellsessionsweep-tests"

    /// The name of the store folder inside the directory of one test.
    private static let shellStoreDirectoryName = ".shell"

    /// The command each background run starts.
    ///
    /// It is a process TREE and not one process: the shell starts one wait on
    /// `gate` in the background and then runs a second one. The test never
    /// releases the gate, thus the run certainly still stands on the run plane
    /// when the sweep reaches it, and what ends it is the sweep and never the
    /// command ending by itself. A sweep that signalled the leader alone would
    /// leave the background wait alive, and the wait for the end of each
    /// process of the group below would not end.
    ///
    /// - Parameter gate: The FIFO that holds both waits.
    /// - Returns: The command line.
    private static func backgroundCommand(holdingOn gate: ShellCommandGate) -> String {
        "\(gate.waitCommand) & \(gate.waitCommand)"
    }

    /// How many runs start in the tests that read one run's terminal event.
    private static let oneBackgroundRun = 1

    /// How many runs start in the tests that prove the sweep answers for each
    /// background run and not for the first one alone.
    private static let twoBackgroundRuns = 2

    /// How many terminal events one swept run gets. `RunPlane.sweep()`
    /// states the invariant: exactly one for each run, never two.
    private static let terminalEventsPerRun = 1

    /// The signal `killpg` takes to ASK whether a process group is still there.
    ///
    /// Signal 0 sends NOTHING. `killpg` performs the checks of a signal it is
    /// about to send and then sends none, thus this is the one reading that
    /// answers "does this group still hold a process" with no risk to what
    /// stands in the group.
    private static let existenceProbeSignal: Int32 = 0

    /// What `killpg` answers when it reached the group.
    private static let killpgReachedGroup: Int32 = 0

    // MARK: - The ground of one test

    /// One session whose run plane holds background shell runs, each one a
    /// live process tree this test spawned.
    private struct BackgroundSession {

        /// The stub run the runs are tracked on. `RoutedSession.close()` is
        /// the teardown: it runs the sweep of the run plane and journals the
        /// terminal events, and a consumer cannot call that sweep directly.
        let stub: StubRun

        /// The sink each mounted run posts to, unstamped.
        let sink: RecordingEventSink

        /// The ambient context of the outer run, which reports the run plane.
        let context: ToolContext

        /// The store each run recorded into.
        let state: ShellState

        /// The process-group registry of the runner, private to this test.
        let registry: ProcessRegistry

        /// The background runs, in the order they were tracked.
        let runs: [BackgroundRun]

        /// The process group of each background run, in the order of ``runs``.
        let groups: [pid_t]

        /// The FIFO that holds the command of each run. It must live until
        /// the sweep killed each run, thus the session keeps it.
        let gate: ShellCommandGate
    }

    /// Starts `count` background shell runs in one session, gives `body`
    /// everything a test needs to tear that session down and read what the
    /// teardown did, and closes the session on every path.
    ///
    /// The session is closed when the setup throws, when `body` throws, and
    /// when `body` returns. A test can close the session itself at the point
    /// that its assertions need: `RoutedSession.close()` is idempotent.
    ///
    /// The process-group registry is a PRIVATE `ProcessRegistry()` and never
    /// `.global`: an ordinary test must not touch the process-wide instance —
    /// see the doc comment of that property. It is also what the test of the
    /// `atexit` backstop reads.
    ///
    /// - Parameters:
    ///   - count: How many runs to start.
    ///   - body: The work that uses the session, its background runs and their
    ///     process groups.
    /// - Returns: What `body` returned.
    /// - Throws: When the store does not prepare, when the engine does not
    ///   mount, when a run does not reach the plane, when a child of a run
    ///   registers no process group, or what `body` threw.
    private func withBackgroundSession<Result>(
        runCount count: Int, _ body: (BackgroundSession) async throws -> Result
    ) async throws -> Result {
        let directory = try scratch.makeDirectory(prefix: Self.testDirectoryNamePrefix)
        let state = try ShellState(
            preferredDirectory: directory.appendingPathComponent(Self.shellStoreDirectoryName))
        let registry = ProcessRegistry()
        // The run clock of the session. Each call goes to the background when
        // the test moves this clock past the settle period, and no real time
        // passes.
        let clock = ManualRunClock()
        return try await withStubRun(runClock: clock) { run in
            let context = run.context
            // A caller-supplied sink: each swept run's terminal must carry that
            // run's OWN token, and the mount's own sink re-stamps onto the
            // mounting run.
            let sink = RecordingEventSink()
            let engine = ShellRunPlane.mounted(
                Execute(runner: ShellRunner(state: state, registry: registry)),
                inheriting: context, postingTo: sink)
            let gate = try ShellCommandGate()

            // The gate holds each command, thus each call answers with its pending
            // envelope only when the clock moves past the settle period.
            let arguments = ExecuteArguments(command: Self.backgroundCommand(holdingOn: gate))
            for _ in 0..<count {
                _ = try await callPastSettlePeriod(
                    on: clock, grace: context.inlineSettleGrace, timers: settlePeriodTimers
                ) {
                    try await engine.call(arguments: arguments)
                }
            }

            let runs = try await ShellRunPlane.backgroundRuns(in: context, count: count)
            var groups: [pid_t] = []
            for backgroundRun in runs {
                groups.append(try await Self.processGroup(of: backgroundRun.completionToken, in: state))
            }
            return try await body(
                BackgroundSession(
                    stub: run,
                    sink: sink,
                    context: context,
                    state: state,
                    registry: registry,
                    runs: runs,
                    groups: groups,
                    gate: gate
                ))
        }
    }

    /// The process group of the run under `completionToken`, once its child
    /// registered one.
    ///
    /// The engine tracks a run as it takes it, and the child registers its pid
    /// inside the spawn, thus a plain read that arrives first finds nothing.
    /// `ShellState.groupToCancel(commandID:)` is the event: it returns when the
    /// child registered its group, or `nil` when the command ended with no group.
    ///
    /// - Parameters:
    ///   - completionToken: The completion token of the run.
    ///   - state: The store the run recorded into.
    /// - Returns: The pid of the leader of the process group, which is also the
    ///   identifier of that group.
    /// - Throws: When the command ended and no child registered.
    private static func processGroup(
        of completionToken: String, in state: ShellState
    ) async throws -> pid_t {
        guard let registered = await state.groupToCancel(commandID: completionToken) else {
            Issue.record("The run under \(completionToken) registered no process group.")
            throw ProcessGroupAbsent()
        }
        return registered.pid
    }

    /// The failure ``processGroup(of:in:)`` throws when no child registers.
    private struct ProcessGroupAbsent: Error {}

    /// The pids of each process that the kernel holds in the process group
    /// `group`, read through `sysctl` with `CTL_KERN, KERN_PROC, KERN_PROC_PGRP`.
    ///
    /// - Parameter group: The identifier of the process group to read.
    /// - Returns: The pids. An empty list when the group holds no process, or
    ///   when the read fails.
    private static func processes(inGroup group: pid_t) -> [pid_t] {
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PGRP, group]
        var size = 0
        let sized = name.withUnsafeMutableBufferPointer { buffer in
            sysctl(buffer.baseAddress, u_int(buffer.count), nil, &size, nil, 0)
        }
        guard sized == 0, size > 0 else { return [] }
        var entries = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride)
        let read = name.withUnsafeMutableBufferPointer { buffer in
            entries.withUnsafeMutableBytes { bytes in
                sysctl(buffer.baseAddress, u_int(buffer.count), bytes.baseAddress, &size, nil, 0)
            }
        }
        guard read == 0 else { return [] }
        return entries.prefix(size / MemoryLayout<kinfo_proc>.stride).map(\.kp_proc.p_pid)
    }

    /// Whether any process still stands in the process group that `group`
    /// leads.
    ///
    /// Every group this is asked about is one this suite spawned itself.
    ///
    /// - Parameter group: The identifier of the process group to ask about.
    /// - Returns: `true` while the group still holds a process.
    private static func processGroupStands(_ group: pid_t) -> Bool {
        killpg(group, existenceProbeSignal) == killpgReachedGroup
    }

    // MARK: - The sweep kills the process group of each background run

    /// eventplan.md: *"Shell runs get `killpg(SIGKILL)`."* The background run
    /// declares `RunKind.process`, thus the run plane holds the canceler that
    /// sends that signal, and the sweep sends it to each background run in
    /// turn.
    ///
    /// What this reads is the process group and never the word the sweep
    /// answered: a canceler that reported `.stopped` and signalled nothing
    /// would pass a test that read the word alone.
    ///
    /// No reading here waits on time. `close()` waits until the body of each
    /// run ended (`RunPlane.joinRunBodies()`), and the body ends only after
    /// swift-subprocess reaped the leader of its group. Thus the leader is
    /// gone when `close()` returns. Each other process of a group is a
    /// grandchild that this process cannot reap: the system reaps it at a
    /// time this process does not control. The test reads each process that
    /// the group still holds after `close()`, and waits on the exit event of
    /// the kernel for each one (``ProcessExitWait/waitUntilGone(_:)``). A
    /// process that the sweep did not kill never exits, and that wait is the
    /// failure of the test.
    @Test("session teardown kills the child process group of each background shell run")
    func sessionTeardownKillsTheProcessGroupOfEachBackgroundShellRun() async throws {
        try await withBackgroundSession(runCount: Self.twoBackgroundRuns) { session in
            #expect(session.runs.allSatisfy { $0.kind == .process })
            for group in session.groups {
                #expect(Self.processGroupStands(group), "the process group \(group) never came up")
            }

            await session.stub.session.close()

            for group in session.groups {
                #expect(ProcessLiveness.isGone(group), "the sweep left the leader of the group \(group) unreaped")
                // The end of each wait is the result, thus no state is read
                // again after it. A process that the sweep did not kill never
                // exits, and that wait is the failure of the test.
                for member in Self.processes(inGroup: group) {
                    await ProcessExitWait.waitUntilGone(member)
                }
            }
        }
    }

    // MARK: - The terminal event of a swept run

    /// eventplan.md: *"Shell runs get `killpg(SIGKILL)` and post `.stopped`."*
    /// It is `.stopped` and never `.cancelled`, because `killpg` on the own
    /// process group of the child is authoritative: the work is over, and that
    /// is certain.
    ///
    /// The record of the store carries the same answer from the other side. The
    /// canceler writes `.killed` there, and `CommandStatus.killed` is the one
    /// status a cancel reaches, thus the run plane and the store agree on how
    /// this run ended.
    @Test("the terminal event of a swept shell run carries the outcome .stopped")
    func theTerminalEventOfASweptShellRunCarriesStopped() async throws {
        try await withBackgroundSession(runCount: Self.oneBackgroundRun) { session in
            let run = try #require(session.runs.first)

            // Subscribed BEFORE the sweep. `streamSessionEvents()` is live and has
            // no replay, and `close()` finishes every open subscription, so a
            // stream opened after the sweep sees nothing at all.
            // The sweep's terminal reaches the JOURNAL, not the mounted run's own
            // sink: `close()` sweeps through the run plane, which is not the run
            // posting an event of its own. With a caller-supplied sink in the mount
            // there is no re-stamping layer, so the journaled terminal carries the
            // run's own token — measured.
            await session.stub.session.close()
            let terminals = await recordedOperationEvents(
                of: session.stub, ofKind: .completed,
                correlatedTo: Set(session.runs.map(\.completionToken)),
                awaiting: Self.terminalEventsPerRun)
            #expect(terminals.count == Self.terminalEventsPerRun)
            let terminal = try #require(terminals.first)
            #expect(terminal.correlationID == run.completionToken)
            #expect(terminal.kind == .completed)
            #expect(terminal.outcome == .stopped)
            #expect(await session.state.record(commandID: run.completionToken)?.status == .killed)
        }
    }

    /// eventplan.md: *"Each outcome goes into the journal before the session
    /// closes. There are no orphans and no holes in the durable record."*
    ///
    /// `RoutedSessionActor.close()` journals one terminal event for each
    /// background run, and a second write for one run is refused. So one
    /// terminal event for each background run, each one under that run's own
    /// completion token, is that record with no hole; and a run plane the
    /// sweep left empty is that record with no orphan, because no run is left
    /// for a later observer to find.
    ///
    /// The test compares the completion tokens as a SET and never as a list.
    /// `RunPlane.sweep()` returns its events in the order the runs were
    /// tracked, but a run that settles by itself while the sweep waits on the
    /// canceler of the other run reaches the journal at that settle, before the
    /// events of the sweep. Thus the journal order of the two events is not
    /// fixed, and no contract promises it.
    @Test("each of two background shell runs gets its own terminal event, and none stays on the plane")
    func eachOfTwoBackgroundShellRunsGetsItsOwnTerminalEvent() async throws {
        try await withBackgroundSession(runCount: Self.twoBackgroundRuns) { session in
            // Subscribed BEFORE the sweep; see the sibling test for why.
            // The sweep's terminal reaches the JOURNAL, not the mounted run's own
            // sink: `close()` sweeps through the run plane, which is not the run
            // posting an event of its own. With a caller-supplied sink in the mount
            // there is no re-stamping layer, so the journaled terminal carries the
            // run's own token — measured.
            await session.stub.session.close()
            let terminals = await recordedOperationEvents(
                of: session.stub, ofKind: .completed,
                correlatedTo: Set(session.runs.map(\.completionToken)),
                awaiting: Self.twoBackgroundRuns)

            #expect(terminals.count == Self.twoBackgroundRuns)
            #expect(Set(terminals.map(\.correlationID)) == Set(session.runs.map(\.completionToken)))
            #expect(terminals.allSatisfy { $0.kind == .completed })
            #expect(terminals.allSatisfy { $0.outcome == .stopped })
            #expect(await session.context.backgroundRuns().isEmpty)
        }
    }

    // MARK: - The atexit backstop of the process registry

    /// The sweep runs first, thus the `atexit` backstop of `ProcessRegistry`
    /// finds nothing left and the two never signal the same group twice.
    ///
    /// The teardown of a run deregisters its pid INSIDE the spawn closure of
    /// `ShellRunner.run`, which is before swift-subprocess reaps the child, thus
    /// no window exists in which the registry holds a pid the kernel already
    /// gave to another process. The sweep starts that teardown and does not wait
    /// for it. But `close()` then waits until the body of each run ended
    /// (`RunPlane.joinRunBodies()`), and the body ends after the spawn closure
    /// deregistered its pid. Thus one reading after `close()` is the check, in
    /// the order that the product makes.
    @Test("the sweep drains the process registry, thus the atexit backstop finds nothing to kill")
    func theSweepDrainsTheProcessRegistry() async throws {
        try await withBackgroundSession(runCount: Self.twoBackgroundRuns) { session in
            let registry = session.registry
            #expect(registry.registeredPids == Set(session.groups))

            await session.stub.session.close()

            #expect(registry.registeredPids.isEmpty, "the registry still held \(registry.registeredPids)")
        }
    }
}
