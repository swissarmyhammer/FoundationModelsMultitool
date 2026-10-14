import Testing

/// The background-shell-command scenario — eventplan.md's phase-2 claim that the
/// shell capability is the reference emitter, and that "its detached commands
/// prove the background path end to end."
///
/// One live message and its answer on the shipped configuration: `MultiTool.Builder().withShell()`
/// vended through `makeSessionTools(selection:embedder:sampleModel:)` and mounted on a
/// `RoutedSession`. The model discovers `tools.shell.execute` and starts a
/// never-ending command from a `runCode` snippet. Under the settle-period rule
/// (card `^38j4bbn`) the outer `runCode` call goes to the background, and the
/// inner execute run runs to completion inside the snippet (card `^6nnykct`).
/// The harness takes the execute run's completion token from the run's own
/// context, reads the run plane while the command is still running, cancels
/// the snippet, and closes the session.
///
/// What each condition proves, and where the reading comes from, is stated on
/// `shellBackgroundChecks(for:)` and on the runner in
/// `Support/ShellBackgroundRunner.swift`. Two of them are worth naming here
/// because they are the reason this suite is gated rather than a unit test:
///
/// - `childProcessGone` needs a REAL child process group. After the cancel of
///   the snippet, it waits on the exit event of the kernel for each process of
///   the group (`ProcessExitWait`), so a cancel that did not reach the inner
///   shell run would fail.
/// - `oneJournaledTerminal` needs a LOADED MODEL. It is the half task `^1hq8xny`
///   left to this card by design, recorded on both: `RoutedSessionActor.close()`
///   journals exactly what `RunPlane.sweep()` answers with, through
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
    .serialized
    // No test checks the speed of the machine (card `^tm4x2hp`).
    //
    // No step waits on time. When the answer never gets to
    // `tools.shell.execute`, the watcher stops on the event that the answer
    // ended. Then the harness reports what it read.
)
struct ShellBackgroundTests {
    @Test("a shell command goes to the background, stands on the run plane, is read live, is stopped, and is journaled")
    func shellCommandThroughTheBackgroundPath() async throws {
        try await runShellBackgroundScenario(name: "backgroundShellCommand")
    }
}
