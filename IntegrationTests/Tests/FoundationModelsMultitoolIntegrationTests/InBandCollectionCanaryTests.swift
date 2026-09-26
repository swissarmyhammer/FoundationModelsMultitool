import Testing

import ScenarioGrading

/// The canary over how a backgrounded run comes back to the model on this
/// host: the model ends its answer while the run is still going, the settled
/// run comes back to the session as mail, and the model answers the mail.
///
/// **Two tests, two claims, split on task `^nhxj8hx`.** The old suite graded
/// both claims through one expensive run, and CI run `32203706380` killed that
/// run at its ceiling as the whole run's only failure. The split gives each
/// claim its own shortest run:
///
/// - **The mechanism** (`theDelayedEchoRoundTripsThroughMail`): a call
///   backgrounds, hands the model a handle, and the value comes back intact
///   in the mail answer. It mounts a direct-mode surface — `runCode`, no
///   `searchTools` — so the model pays for no discovery, and it drives
///   `IntegrationDelayedEchoTool`, whose result settles seconds after the
///   handle exists. The graded value is a fresh nonce; see the test body for
///   how its round trip is pinned to the settled run.
///
/// - **The teaching** (`theSettledRunComesBackAsMail`): the prompt tells the
///   model *not* to block, so it ends its answer with the rebuild still going.
///   Same fixture, same prompt and same discovery surface as the run this
///   suite was first measured on. Do not soften its prompt.
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
/// `MAIL-CANARY … answers= mailAnswers= backgroundRunsAtLastAnswer=` today.
///
/// **What a failure means.** `mailCollection` failing alone means no answer
/// started from mail: the model held its answer open until the run settled,
/// or the run settled inside the inline settle grace and needed no mail.
/// `noBackgroundRunsAtLastAnswer` failing means a run was still going when the
/// mail answer ended. Do not relax either of them to make a run green; file
/// the question instead.
///
/// **The rebuild fixture must outlast the inline settle grace, and no more.**
/// A `runCode` snippet that settles inside `runCode`'s inline settle grace
/// gives its result inline, and no mail comes. Thus a fixture that settles at
/// once lets a correct model fail `mailCollection`.
/// `integrationArchiveRebuildDelay` holds the rebuild a few seconds past the
/// grace, so the model always gets the pending envelope. A long stall once
/// cost this suite its verdict outright — `IntegrationArchiveRebuildTool`
/// records what happened — so the delay stays short. The delayed echo is slow
/// for a different reason: its subject is the deferred settlement itself, and
/// `integrationDelayedEchoDelay` records why.
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
    // Fifteen minutes for each test. The limit is a hang detector, and it has
    // to clear every healthy run on the slowest machine that runs this suite.
    //
    // The history of the number, which is still the measurement it rests on
    // (task `^nhxj8hx`, card `^dwzkfzx`): on the old contract the canary
    // scenario passed in 113.0s, 327.2s and 445.5s on this dev box, against
    // `Qwen3.8-27B-mxfp4`. CI run `32203706380` ran the same suites 6.21 times
    // slower than this dev box and cut the canary at a ten-minute ceiling.
    //
    // On the mail contract, the runner stops at `mailAnswerDeadline`, twelve
    // minutes after the turn starts, and grades what it read. So a run that
    // gets no mail answer fails with a reading, inside this limit. The limit
    // itself only has to catch a turn that never ends.
    //
    // The standing rule is intact: never raise a ceiling to make a run
    // green — re-derive it from the machine that failed, or remove it.
    .timeLimit(.minutes(15))
)
struct InBandCollectionCanaryTests {
    @Test("the delayed echo's value comes back through mail, and the mail answer reports it")
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
            // Names the tool and the value, and asks for the result. It does
            // not say how the result comes back: the pending envelope on the
            // handle carries that, as it does for every host.
            prompt: "Call the \(IntegrationDelayedEchoTool.path) tool with the value \(nonce). "
                + "Report the exact value it returns.",
            answerContainsOneOf: [nonce],
            groundedIn: IntegrationScenarioGrounding.delayedEcho,
            direct: true
        )
    }

    @Test("the settled rebuild comes back as mail, and the mail answer carries the manifest code")
    func theSettledRunComesBackAsMail() async throws {
        try await runInBandCollectionCanaryScenario(
            name: "mailCollection",
            tools: { log in [IntegrationArchiveRebuildTool(log: log)] },
            // Asks for the manifest code, so the answer needs the run's result;
            // and says plainly not to block for it, so the model ends its
            // answer while the rebuild is still going. The manifest code then
            // reaches the model only through the mail.
            //
            // Phrased as a user request rather than as coaching: "start it, tell
            // me when it is running, give me the code when it lands" is how
            // someone asks for work they do not want to sit through.
            prompt: "Rebuild my archive index and tell me its exact manifest code. Do not block "
                + "waiting for it: start the rebuild, reply as soon as it is under way, and give me "
                + "the manifest code once it reaches you.",
            // The rebuild fixture always reports the same manifest code, and it
            // reaches the model only through the settled run's terminal
            // `detail` — a hallucinated answer cannot match it.
            answerContainsOneOf: integerAnswers(for: integrationArchiveRebuildManifestCode),
            groundedIn: IntegrationScenarioGrounding.archiveRebuild
        )
    }
}
