import Testing

/// The background-shell-command scenario — eventplan.md's phase-2 claim that the
/// shell capability is the reference emitter, and that "its background commands
/// prove the elevation path end to end."
///
/// One live turn on the shipped configuration: `MultiTool.Builder().withShell()`
/// vended through `makeSessionTools(librarian:)` and mounted on a
/// `RoutedSession`. The model discovers `tools.shell.execute`, starts a
/// never-ending command from a `runCode` snippet, and the outer run elevates and
/// hands back a pending envelope. The harness then reads the run plane while the
/// command is still running, ends it, and closes the session.
///
/// What each condition proves, and where the reading comes from, is stated on
/// `shellElevationChecks(for:)` and on the runner in
/// `Support/ShellElevationRunner.swift`. Two of them are worth naming here
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
/// not a preference — see `LiveProfileTurnstile` for what the clock counts
/// without it.
@Suite(
    "Background shell command through the elevation path (phase-2)",
    .serialized,
    // Fifteen minutes, derived by the method `ElevationTests` states, applied to
    // this scenario's own costs. Read that suite's derivation before changing
    // this number.
    //
    // THE LIMIT IS THE DETECTOR, exactly as it is there. This suite exists to
    // show that one background shell command travels the whole elevation path. The
    // failure the limit must catch is a turn that never reaches
    // `tools.shell.execute` at all — and the harness already bounds that with
    // `shellRunArrivalDeadline`, eight minutes, after which it reports what it
    // read rather than hanging. So the ceiling stands above a healthy run plus
    // that bound, and it is not the primary detector of anything.
    //
    // WHAT A HEALTHY RUN COSTS. Measured on this dev box on 2026-08-25, two
    // runs of this suite against `Qwen3.8-27B-mxfp4`, the shipped pin:
    //
    //   date        suite time   tool calls   note
    //   2026-08-25   42.123s      2           searchTools, runCode
    //   2026-08-25   59.471s      2           searchTools, runCode
    //
    // The shape is constant: searchTools, then one `runCode` whose snippet calls
    // `tools.shell.execute` with `wait: false`. The worst healthy run is 59.471s.
    //
    // Both runs took the `wait: false` path, so neither paid `Execute`'s own
    // 30-second block window. A run whose model omits that argument does pay it,
    // and the limit has to hold that run too, so the number carried forward is
    // 59.471s + 30s ≈ 90s. The two polls beside it — the live `getLines` read and
    // the process-group probe — each cost about one `IntegrationPoll.interval`,
    // because the command writes its first line at once and `killpg` kills the
    // tree at once.
    //
    // THE DERIVATION. Task `^nhxj8hx` measured the CI runner at 6.21 times this
    // dev box over ten suites (3614s / 581.7s). Project the worst healthy run
    // onto that runner: 90s x 6.21 ≈ 559s. Apply the same one-third margin:
    // 559s x 4/3 ≈ 745s. Round up to whole minutes: thirteen. Round once more to
    // fifteen, because this scenario's arrival bound is itself eight minutes and
    // a run that spends the whole of it and then reports must land inside the
    // limit rather than be killed by it.
    //
    // Nothing here is a retry gate and nothing here is a sampling gate. A run
    // that reaches this limit is a defect to fix. Re-derive it from the machine
    // that failed, or remove it.
    .timeLimit(.minutes(15))
)
struct ShellElevationTests {
    @Test("a background shell command elevates, stands on the run plane, is read live, is stopped, and is journaled")
    func backgroundShellCommandThroughTheElevationPath() async throws {
        try await runShellElevationScenario(name: "backgroundShellCommand")
    }
}
