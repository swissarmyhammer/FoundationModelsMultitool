import Testing

/// The background-in-code-mode scenario — eventplan.md's phase-1 exit
/// proof that the two surfaces really do meet on real hardware: a snippet that
/// goes to the background hands the model a pending envelope,
/// and the model collects the background run through the background-run globals
/// and still answers.
///
/// **Why this suite does not use `runNativeIntegrationScenario`.** Not the
/// session: both runners build the same `RoutedSession` from
/// `profile.standard.makeSession(tools:discoveryPriming:)`, so both mount
/// `runCode` under `ToolMount.synchronous`. It is the
/// assertion. `runBackgroundIntegrationScenario` also requires that a pending
/// envelope really appeared on the way to the answer, which is the whole
/// claim of this suite and which the native runner does not check. See
/// `Support/ScenarioRunner.swift` for both runners and what each asserts.
///
/// Serialized exactly like `SearchThenCallTests`. Its time limit is its own,
/// derived from measurement; the trait comment below holds the derivation.
/// It is unreachable from the root `swift test`, which declares no target for
/// this nested `IntegrationTests` package, so the root suite downloads nothing
/// and runs no live inference; the command that does run this suite is
/// `swift test --package-path IntegrationTests --no-parallel`.
@Suite(
    "Background-in-code-mode scenario (phase-1 exit)",
    .serialized,
    // Ten minutes, derived on 2026-08-21 from measurement, by the method of
    // task `^nhxj8hx` (task `^4qcf1v9`). Read this before you change the number.
    //
    // THE LIMIT IS THE DETECTOR. This suite exists to show that the model
    // collects one pending run and answers. The failure it must catch is a
    // chain: each round mints a new token, and the model waits on the newest
    // one. A chain is reported by this limit, not by an assertion. So the
    // ceiling must stand close above a healthy run, and below a chain.
    //
    // WHAT THE CHAIN COST. Before the fix in `^4qcf1v9`, the envelope text told
    // the model to wait inside a new `runCode` snippet. Measured:
    //
    //   CI run 32392350928:  1785.670s, 23 tool calls (21 rounds of chase)
    //   dev box, `^hht0009`:  643.687s, 24 tool calls
    //
    // Each round cost one generation on the 27B model. The 30-minute ceiling
    // this replaces let the CI chain pass with 14 seconds to spare.
    //
    // WHAT A HEALTHY RUN COSTS. Each row is one suite run on this dev box, with
    // no chain. The two rows from 2026-08-21 are the re-measurement after the
    // fix: the envelope now names the `wait` tool and the original token, and
    // the model calls it one time.
    //
    //   date        suite time   tool calls   note
    //   2026-08-16   39.8s       --           Qwen3.8, serialized run
    //   2026-08-16   64.2s       --           `--no-parallel`
    //   2026-08-19   51.79s      --           task `^dwzkfzx`
    //   2026-08-21   67.053s     3            Router f1dd39e text, one round
    //   2026-08-21   53.701s     3            fix in place, one round
    //
    // The worst healthy run is 67.053s. The shape is constant: searchTools,
    // runCode, wait. The answer carries the report code.
    //
    // THE DERIVATION. `^nhxj8hx` measured the CI runner at 6.21 times this dev
    // box over ten suites (3614s / 581.7s). Project the worst healthy run onto
    // that runner: 67.053s x 6.21 ≈ 416s. Apply the same one-third margin:
    // 416s x 4/3 ≈ 555s. Round up to whole minutes: ten minutes, 600s.
    //
    // THE MARGIN. 600s stands 44 percent above the projected worst healthy CI
    // run (416s), and 8.9 times above the worst healthy dev-box run (67.053s).
    // Both chain runs above (643.687s and 1785.670s) exceed it, so a chain is
    // reported in ten minutes, not thirty. No retry and no sampling tweak is
    // part of this: a run that reaches the limit is a defect to fix.
    //
    // Nothing here raises a ceiling. This lowers one, on measurement. Do not
    // raise it to make a run green. Re-derive it from the machine that failed,
    // or remove it.
    .timeLimit(.minutes(10))
)
struct BackgroundTests {
    @Test("a snippet that goes to the background hands back a pending envelope and the model still answers the deep scan's report code")
    func backgroundInCodeMode() async throws {
        try await runBackgroundIntegrationScenario(
            name: "backgroundInCodeMode",
            tools: { log in [IntegrationDeepScanTool(log: log)] },
            // The whole job in one request, the way a user would ask for it.
            // Two weaker phrasings were tried on real hardware and are worse:
            // a bare "Start the deep scan of my archive." made the model
            // announce it had started the scan without ever calling `runCode`,
            // and adding "give me the number in this reply" made it skip the
            // scan and invent a number. Asking it to wait for the result is
            // what actually gets the snippet run — and every `runCode` call
            // goes to the background, so this is the turn that hands the model
            // a pending envelope.
            prompt: "Start the deep scan of my archive, wait for it to finish, and tell me the exact "
                + "report code it returns.",
            // The deep-scan fixture always returns the same report code, and it
            // reaches the model only through the collected run's terminal
            // `detail` — a hallucinated answer cannot match it.
            answerContainsOneOf: integerAnswers(for: integrationDeepScanReportCode)
        )
    }
}
