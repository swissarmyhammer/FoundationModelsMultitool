import Testing

import ScenarioGrading

/// The background-in-code-mode scenario — eventplan.md's phase-1 exit
/// proof that the two surfaces really do meet on real hardware: a snippet that
/// goes to the background hands the model a pending envelope, the settled run
/// comes back to the session as mail, and the answer that mail starts carries
/// the value.
///
/// **Why this suite does not use `runNativeIntegrationScenario`.** Not the
/// session: both runners build the same `RoutedSession` from
/// `profile.standard.makeSession(tools:discoveryPriming:)`, so `runCode` goes
/// to the background on both. It is the
/// assertion. `runBackgroundIntegrationScenario` also requires that a pending
/// envelope really appeared on the way to the answer, which is the whole
/// claim of this suite and which the native runner does not check. See
/// `Support/ScenarioRunner.swift` for both runners and what each asserts.
///
/// Serialized exactly like `SearchThenCallTests`. Its time limit is the shared
/// hang guard; the trait comment below says what it stops.
/// It is unreachable from the root `swift test`, which declares no target for
/// this nested `IntegrationTests` package, so the root suite downloads nothing
/// and runs no live inference; the command that does run this suite is
/// `swift test --package-path IntegrationTests --no-parallel`.
@Suite(
    "Background-in-code-mode scenario (phase-1 exit)",
    .serialized,
    // The limit is the shared hang guard, `IntegrationHangGuard.timeLimit`.
    // It stops a turn that cannot end. It does not check the speed of the
    // machine (card `^tm4x2hp`).
    //
    // This suite shows that the model collects one pending run and answers.
    // A chain is the failure that the hang guard must stop: each round mints
    // a new token, and the model waits on the newest one. Before the fix in
    // task `^4qcf1v9`, the envelope text told the model to wait inside a new
    // `runCode` snippet, and a CI run chased the token for 23 tool calls.
    // The fix names the `wait` tool and the original token, and the model
    // calls it one time.
    .timeLimit(IntegrationHangGuard.timeLimit)
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
