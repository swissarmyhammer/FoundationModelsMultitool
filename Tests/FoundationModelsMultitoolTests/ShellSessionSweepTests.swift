import Foundation
import FoundationModels
import FoundationModelsExtras
import Testing

@testable import FoundationModelsMultitool
@testable import FoundationModelsRouter

/// Coverage for the session-end sweep of a background shell run — eventplan.md:
/// *"Background runs die with the session."* Teardown does one deterministic
/// sweep of the mailbox, and it processes each kind with that kind's own
/// semantics: *"Shell runs get `killpg(SIGKILL)` and post `.stopped`."*
///
/// The route this suite proves has three owners:
///
/// 1. `Execute` declares, through `BackgroundTool`, that its runs
///    are `RunKind.process` and that `ShellRunner.canceler(completionToken:)`
///    stops one. `BackgroundToolRunner` hands both to `SessionMailbox.track`.
/// 2. `SessionMailbox.sweep()` walks the background runs in the order they
///    were tracked, awaits each canceler, and answers exactly one terminal
///    event for each run.
/// 3. `RoutedSessionActor.close()` journals that whole list before it returns.
///
/// The tests drive step 2, which is the step that turns a session teardown into
/// a dead process group. Step 3 journals whatever step 2 hands it, thus a sweep
/// that answers one terminal event for each background run and leaves the run
/// plane empty is a durable record with no hole and no orphan.
///
/// **`SessionMailbox.sweep()` is `internal` to Router**, thus this file takes
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

    /// How long each command of a background run sleeps. Long enough that the
    /// run certainly still stands on the run plane when the sweep reaches it,
    /// thus what ends it is the sweep and never the command ending by itself.
    private static let backgroundRunSleepSeconds = 60

    /// The command each background run starts.
    ///
    /// It is a process TREE and not one process: the shell starts one `sleep`
    /// in the background and then runs a second one. A sweep that signalled the
    /// leader alone would leave the background `sleep` alive, and the reading of
    /// the process group below would still find the group.
    private static let backgroundCommand =
        "sleep \(backgroundRunSleepSeconds) & sleep \(backgroundRunSleepSeconds)"

    /// How many runs start in the tests that read one run's terminal event.
    private static let oneBackgroundRun = 1

    /// How many runs start in the tests that prove the sweep answers for each
    /// background run and not for the first one alone.
    private static let twoBackgroundRuns = 2

    /// How many terminal events one swept run gets. `SessionMailbox.sweep()`
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
        /// the teardown: it runs the mailbox's own sweep and journals the
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
    }

    /// Starts `count` background shell runs in one session, and answers
    /// everything a test needs to tear that session down and read what the
    /// teardown did.
    ///
    /// The process-group registry is a PRIVATE `ProcessRegistry()` and never
    /// `.global`: an ordinary test must not touch the process-wide instance —
    /// see the doc comment of that property. It is also what the test of the
    /// `atexit` backstop reads.
    ///
    /// - Parameter count: How many runs to start.
    /// - Returns: The session, its background runs and their process groups.
    /// - Throws: When the store does not prepare, when the engine does not
    ///   mount, when a run does not reach the plane, or when a child of a run
    ///   registers no process group.
    private func makeBackgroundSession(runCount count: Int) async throws -> BackgroundSession {
        let directory = try scratch.makeDirectory(prefix: Self.testDirectoryNamePrefix)
        let state = try ShellState(
            preferredDirectory: directory.appendingPathComponent(Self.shellStoreDirectoryName))
        let registry = ProcessRegistry()
        let run = try await makeStubRun()
        let context = run.context
        // A caller-supplied sink: each swept run's terminal must carry that
        // run's OWN token, and the mount's own sink re-stamps onto the
        // mounting run.
        let sink = RecordingEventSink()
        let engine = ShellRunPlane.mounted(
            Execute(runner: ShellRunner(state: state, registry: registry)),
            inheriting: context, postingTo: sink)

        for _ in 0..<count {
            _ = try await engine.call(arguments: ExecuteArguments(command: Self.backgroundCommand))
        }

        let runs = try await ShellRunPlane.backgroundRuns(in: context, count: count)
        var groups: [pid_t] = []
        for run in runs {
            groups.append(try await Self.processGroup(of: run.completionToken, in: state))
        }
        return BackgroundSession(
            stub: run,
            sink: sink,
            context: context,
            state: state,
            registry: registry,
            runs: runs,
            groups: groups
        )
    }

    /// The process group of the run under `completionToken`, once its child
    /// registered one.
    ///
    /// A ``TestPoll``, because the engine tracks a run as it takes it and the
    /// child registers its pid inside the spawn, thus a read that arrives first
    /// finds nothing. `ShellState.runningProcess(commandID:)` is the plain,
    /// non-suspending reading, which is the one an observer takes.
    ///
    /// - Parameters:
    ///   - completionToken: The completion token of the run.
    ///   - state: The store the run recorded into.
    /// - Returns: The pid of the leader of the process group, which is also the
    ///   identifier of that group.
    /// - Throws: When no child registers before the deadline.
    private static func processGroup(
        of completionToken: String, in state: ShellState
    ) async throws -> pid_t {
        var registered: pid_t?
        let came = await TestPoll.holds {
            registered = await state.runningProcess(commandID: completionToken)
            return registered != nil
        }
        guard came, let registered else {
            Issue.record("The run under \(completionToken) registered no process group.")
            throw ProcessGroupAbsent()
        }
        return registered
    }

    /// The failure ``processGroup(of:in:)`` throws when no child registers.
    private struct ProcessGroupAbsent: Error {}

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
    /// declares `RunKind.process`, thus the mailbox holds the canceler that
    /// sends that signal, and the sweep sends it to each background run in
    /// turn.
    ///
    /// What this reads is the process group and never the word the sweep
    /// answered: a canceler that reported `.stopped` and signalled nothing
    /// would pass a test that read the word alone.
    ///
    /// The reading is a ``TestPoll`` and the poll is real work, not slack.
    /// `killpg` kills the tree at once, and the leader of the group then stays
    /// an unreaped child of this process until swift-subprocess reaps it. A
    /// group that still holds a zombie still answers the probe, thus the
    /// reading polls until the group holds nothing at all — which is also the
    /// proof that the child was reaped and left no orphan behind.
    @Test("session teardown kills the child process group of each background shell run")
    func sessionTeardownKillsTheProcessGroupOfEachBackgroundShellRun() async throws {
        let session = try await makeBackgroundSession(runCount: Self.twoBackgroundRuns)
        #expect(session.runs.allSatisfy { $0.kind == .process })
        for group in session.groups {
            #expect(Self.processGroupStands(group), "the process group \(group) never came up")
        }

        await session.stub.session.close()

        for group in session.groups {
            let gone = await TestPoll.holds { !Self.processGroupStands(group) }
            #expect(gone, "the sweep left the process group \(group) alive")
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
        let session = try await makeBackgroundSession(runCount: Self.oneBackgroundRun)
        let run = try #require(session.runs.first)

        // Subscribed BEFORE the sweep. `streamSessionEvents()` is live and has
        // no replay, and `close()` finishes every open subscription, so a
        // stream opened after the sweep sees nothing at all.
        // The sweep's terminal reaches the JOURNAL, not the mounted run's own
        // sink: `close()` sweeps through the mailbox, which is not the run
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

    /// eventplan.md: *"Each outcome goes into the journal before the session
    /// closes. There are no orphans and no holes in the durable record."*
    ///
    /// `RoutedSessionActor.close()` journals exactly the list the sweep answers
    /// with, and nothing else. So one terminal event for each background run,
    /// each one under that run's own completion token, is that record with no
    /// hole; and a run plane the sweep left empty is that record with no
    /// orphan, because no run is left for a later observer to find.
    @Test("each of two background shell runs gets its own terminal event, and none stays on the plane")
    func eachOfTwoBackgroundShellRunsGetsItsOwnTerminalEvent() async throws {
        let session = try await makeBackgroundSession(runCount: Self.twoBackgroundRuns)

        // Subscribed BEFORE the sweep; see the sibling test for why.
        // The sweep's terminal reaches the JOURNAL, not the mounted run's own
        // sink: `close()` sweeps through the mailbox, which is not the run
        // posting an event of its own. With a caller-supplied sink in the mount
        // there is no re-stamping layer, so the journaled terminal carries the
        // run's own token — measured.
        await session.stub.session.close()
        let terminals = await recordedOperationEvents(
            of: session.stub, ofKind: .completed,
            correlatedTo: Set(session.runs.map(\.completionToken)),
            awaiting: Self.twoBackgroundRuns)

        #expect(terminals.count == Self.twoBackgroundRuns)
        #expect(terminals.map(\.correlationID) == session.runs.map(\.completionToken))
        #expect(terminals.allSatisfy { $0.kind == .completed })
        #expect(terminals.allSatisfy { $0.outcome == .stopped })
        #expect(await session.context.backgroundRuns().isEmpty)
    }

    // MARK: - The atexit backstop of the process registry

    /// The sweep runs first, thus the `atexit` backstop of `ProcessRegistry`
    /// finds nothing left and the two never signal the same group twice.
    ///
    /// The teardown of a run deregisters its pid INSIDE the spawn closure of
    /// `ShellRunner.run`, which is before swift-subprocess reaps the child, thus
    /// no window exists in which the registry holds a pid the kernel already
    /// gave to another process. The sweep starts that teardown and does not wait
    /// for it, which is why the reading below polls.
    @Test("the sweep drains the process registry, thus the atexit backstop finds nothing to kill")
    func theSweepDrainsTheProcessRegistry() async throws {
        let session = try await makeBackgroundSession(runCount: Self.twoBackgroundRuns)
        let registry = session.registry
        #expect(registry.registeredPids == Set(session.groups))

        await session.stub.session.close()

        let drained = await TestPoll.holds { registry.registeredPids.isEmpty }
        #expect(drained, "the registry still held \(registry.registeredPids)")
    }
}
