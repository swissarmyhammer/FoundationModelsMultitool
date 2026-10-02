import Testing

/// The background-shell-command scenario — eventplan.md's phase-2 claim that the
/// shell capability is the reference emitter, and that "its detached commands
/// prove the background path end to end."
///
/// One live turn on the shipped configuration: `MultiTool.Builder().withShell()`
/// vended through `makeSessionTools(selection:embedder:sampleSession:)` and mounted on a
/// `RoutedSession`. The model discovers `tools.shell.execute`, starts a
/// never-ending command from a `runCode` snippet, and the outer run goes to the
/// background and hands back a pending envelope. The harness then reads the run
/// plane while the command is still running, ends it, and closes the session.
///
/// What each condition proves, and where the reading comes from, is stated on
/// `shellBackgroundChecks(for:)` and on the runner in
/// `Support/ShellBackgroundRunner.swift`. Two of them are worth naming here
/// because they are the reason this suite is gated rather than a unit test:
///
/// - `cancelReportsStopped` needs a REAL child process group. `.stopped` means
///   the stop is certain, and only `killpg(SIGKILL)` on a group that exists
///   makes it certain. The reading beside it, `childProcessGone`, polls
///   `killpg(group, 0)` until the group holds nothing, so a canceler that
///   reported the word and signalled nothing would fail.
/// - `oneJournaledTerminal` needs a LOADED MODEL. It is the half task `^1hq8xny`
///   left to this card by design, recorded on both: `RoutedSessionActor.close()`
///   journals exactly what `SessionMailbox.sweep()` answers with, through
///   `SessionOutbox.journalWithoutStaging(event:)`, before it returns. That half
///   lives in Router and can only be driven through a real session, which is why
///   the unit suite proves the sweep and this one proves the journal.
///
/// Serialized exactly like the other gated suites, and unreachable from the root
/// `swift test`, which declares no target for this nested `IntegrationTests`
/// package. The command that runs it is
/// `swift test --package-path IntegrationTests --no-parallel`, and the flag is
/// not a preference — see `liveProfileTurnstile` for what the clock counts
/// without it.
@Suite(
    "A shell command on the background path (phase-2)",
    .serialized,
    // The limit is the shared hang guard, `IntegrationHangGuard.timeLimit`.
    // It stops a turn that cannot end. It does not check the speed of the
    // machine (card `^tm4x2hp`).
    //
    // The harness bounds a turn that never reaches `tools.shell.execute` with
    // the shared poll hang guard `IntegrationPoll.deadline`, after which it
    // reports what it read rather than hanging. The time limit stands above
    // that bound, so it is not the primary detector of anything.
    .timeLimit(IntegrationHangGuard.timeLimit)
)
struct ShellBackgroundTests {
    @Test("a shell command goes to the background, stands on the run plane, is read live, is stopped, and is journaled")
    func shellCommandThroughTheBackgroundPath() async throws {
        try await runShellBackgroundScenario(name: "backgroundShellCommand")
    }
}
