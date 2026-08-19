import Testing

/// The gated elevation-in-code-mode scenario — eventplan.md's phase-1 exit
/// proof that the two surfaces really do meet on real hardware: a snippet whose
/// work outlives the mount's wait clock hands the model a pending envelope,
/// and the model collects the background run through the background-run globals
/// and still answers.
///
/// **Why this suite does not use `runNativeIntegrationScenario`.** Not the
/// session: both runners build the same `RoutedSession` from
/// `profile.standard.makeSession(tools:discoveryPriming:)`, so both mount
/// `runCode` under `DetachConfiguration.nativeSessionMount`. It is the
/// assertion. `runElevationIntegrationScenario` also requires that a pending
/// envelope really appeared on the way to the answer, which is the whole
/// claim of this suite and which the native runner does not check. See
/// `Support/ScenarioRunner.swift` for both runners and what each asserts.
///
/// Gated, serialized, and time-limited exactly like `SearchThenCallTests`:
/// with `MULTITOOL_INTEGRATION` unset the whole suite is skipped, so ungated
/// `swift test` stays green with zero downloads and zero live inference.
@Suite(
    "Gated elevation-in-code-mode scenario (phase-1 exit)",
    .serialized,
    .timeLimit(.minutes(30)),
    .enabled(if: multitoolIntegrationEnabled)
)
struct ElevationTests {
    @Test("an elevating snippet hands back a pending envelope and the model still answers the deep scan's report code")
    func elevationInCodeMode() async throws {
        try await runElevationIntegrationScenario(
            name: "elevationInCodeMode",
            tools: { log in [IntegrationDeepScanTool(log: log)] },
            // The whole job in one request, the way a user would ask for it.
            // Two weaker phrasings were tried on real hardware and are worse:
            // a bare "Start the deep scan of my archive." made the model
            // announce it had started the scan without ever calling `runCode`,
            // and adding "give me the number in this reply" made it skip the
            // scan and invent a number. Asking it to wait for the result is
            // what actually gets the snippet run — and a snippet that awaits
            // this fixture always outlives the mount's wait window, so this is
            // the turn that elevates.
            prompt: "Start the deep scan of my archive, wait for it to finish, and tell me the exact "
                + "report code it returns.",
            // The deep-scan fixture always returns the same report code, and it
            // reaches the model only through the collected run's terminal
            // `detail` — a hallucinated answer cannot match it.
            answerContainsOneOf: integerAnswers(for: integrationDeepScanReportCode)
        )
    }
}
