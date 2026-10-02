import Testing

import ScenarioGrading

/// The canary over how a backgrounded run comes back to the model on this
/// host: a `runCode` call hands the model a pending envelope, the model ends
/// its answer while the run is still going, the settled run comes back to the
/// session as mail, and the model answers the mail.
///
/// **One test for the whole background path.** Until card `^3vtvrzg` three
/// tests drove this same path on the 27B model:
///
/// - `BackgroundTests.backgroundInCodeMode` (100 s on the CI runner `mini`,
///   run `36951032341`): a deep scan on the discovery surface; it graded a
///   valid answer and that a pending envelope appeared.
/// - `theSettledRunComesBackAsMail` (124 s): an archive rebuild on the
///   discovery surface, with a prompt that told the model not to block; it
///   graded a valid, grounded answer, an answer that mail started, and no run
///   left at the last answer.
/// - `theDelayedEchoRoundTripsThroughMail` (177 s): the delayed echo on the
///   direct-mode surface; it graded the same four conditions as the rebuild,
///   on a fresh nonce.
///
/// The delayed echo already graded every condition of the other two but one,
/// the pending envelope, and the runner now grades that one too
/// (`runInBandCollectionCanaryScenario`). A pending envelope on the discovery
/// surface is graded by `ShellBackgroundTests`, and mail delivery does not
/// depend on the surface that started the run. The test that stays is the
/// shortest: direct mode, so the model pays for no discovery.
///
/// **The prompt gives the call.** The direct-mode description of `runCode`
/// names no signature (card `^bwa2p6c`), so in CI run `36951032341` the model
/// first called `tools.docs(...)`, which does not exist, and generated 531
/// tokens before its first real call: one full model turn of approximately
/// 40 s on `mini` that the subject of this test does not need. The prompt
/// therefore names the call with its argument object. It still does not say
/// how the result comes back: the pending envelope on the handle carries
/// that, as it does for every host.
///
/// **What changed on the work-queue Router, and why this suite stays.** The
/// old Router drained the background runs of a turn inside `respond(to:)`, and
/// the old surface mounted a `wait` tool that the model called to collect a
/// run in band. This suite then graded in-band collection: a `wait` call, and
/// nothing still running at the answer. The work-queue Router removed the
/// drain and the `wait` tool. A run that settles after the answer ends now
/// sends its result to the session as mail, and the session starts a new
/// answer for it (`SubmissionStart.cause == .mail`). The runner therefore
/// waits for that mail answer and grades it, through `mailCollectionChecks`.
///
/// The recorded run of the old contract, kept as history:
///
/// ```
/// PARKED-DRAIN [parkedRunDrain] elapsed=635.2s parkedAtAnswer=[] parkedAfterRespond=[]
///   waitCalls=3 terminals=[] returned=["rebuildArchive"] groundedIn=["rebuildArchive"]
///   reply="Rebuild is underway.  Manifest code: 58204"
/// ```
///
/// That block is left exactly as the run printed it. It is a record of a run
/// that happened, in words no fresh run prints: the runner prints
/// `MAIL-CANARY … pendingEnvelopes= answers= mailAnswers= backgroundRunsAtLastAnswer=`
/// today.
///
/// **What a failure means.** `pendingEnvelope` failing means no `runCode`
/// output was the rendered envelope: the echo settled inside the inline settle
/// grace, or the model never called it. `mailCollection` failing alone means
/// no answer started from mail: the model held its answer open until the run
/// settled, or the run settled inside the inline settle grace and needed no
/// mail. `noBackgroundRunsAtLastAnswer` failing means a run was still going
/// when the mail answer ended. Do not relax any of them to make a run green;
/// file the question instead.
///
/// Like every other suite here, this one belongs to the nested
/// `IntegrationTests` package; the root manifest declares no target for it, so
/// the root `swift test` stays green with zero downloads and zero live
/// inference, and the command that reaches this suite is
/// `swift test --package-path IntegrationTests --no-parallel`. The
/// grading rule itself is covered without a live model, on a passing run and
/// on its inverses, in `ScenarioGradingTests`.
@Suite(
    "Gated mail collection canary (a settled background run comes back as mail)",
    .serialized,
    // The limit is the shared hang guard, `IntegrationHangGuard.timeLimit`.
    // It stops a turn that cannot end. It does not check the speed of the
    // machine (card `^tm4x2hp`).
    //
    // On the mail contract, the runner stops at the shared poll hang guard
    // `IntegrationPoll.deadline`, and grades what it read. So a run that gets
    // no mail answer fails with a reading, inside the hang guard.
    .timeLimit(IntegrationHangGuard.timeLimit)
)
struct InBandCollectionCanaryTests {
    @Test("a backgrounded echo hands back a pending envelope, its value comes back through mail, and the mail answer reports it")
    func theDelayedEchoRoundTripsThroughMail() async throws {
        // The shortest sequence that still passes through the real machinery:
        // call the named tool, take the handle, end the answer, get the mail,
        // report. Direct mode removes discovery, so no `searchTools` turn runs
        // at all.
        //
        // The nonce is minted fresh for this run, so no prior run and no
        // training text can supply it. It does appear in the prompt — the
        // model has to pass it — so the reply alone proves nothing: the
        // `grounded` check requires the echo to have handed the value back,
        // and `mailCollection` requires an answer that mail started. A model
        // that parrots the prompt without running anything fails both.
        let nonce = integrationDelayedEchoNonce()
        try await runInBandCollectionCanaryScenario(
            name: "delayedEchoMechanism",
            tools: { log in [IntegrationDelayedEchoTool(log: log)] },
            // Names the call and its argument object, and asks for the
            // result. It does not say how the result comes back: the pending
            // envelope on the handle carries that, as it does for every host.
            // "One short sentence" keeps the mail answer as long as the check
            // needs: a local run on 2026-10-02 wrote 204 tokens for it, a
            // JSON block and an explanation of the echo.
            prompt: "Call tools.\(IntegrationDelayedEchoTool.path)({ value: \"\(nonce)\" }). "
                + "Report the exact value it returns, in one short sentence.",
            answerContainsOneOf: [nonce],
            groundedIn: IntegrationScenarioGrounding.delayedEcho
        )
    }
}
