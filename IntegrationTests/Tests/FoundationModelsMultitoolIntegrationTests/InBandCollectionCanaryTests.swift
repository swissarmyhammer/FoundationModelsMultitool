import Testing

/// The canary over how a backgrounded run is collected on this host: the model
/// collects its own, in band, and the turn never ends with work in flight
/// (task `^xeqs138`).
///
/// **Two tests, two claims, split on task `^nhxj8hx`.** The old suite graded
/// both claims through one expensive run, and CI run `32203706380` killed that
/// run at its ceiling as the whole run's only failure. The split gives each
/// claim its own shortest run:
///
/// - **The mechanism** (`theDelayedEchoRoundTripsThroughItsHandle`): a call
///   backgrounds, hands the model a handle, and the value comes back through
///   that handle intact. It mounts a direct-mode surface — `runCode` and
///   `wait`, no `searchTools` — so the model pays for no discovery, and it
///   drives `IntegrationDelayedEchoTool`, whose result settles seconds after
///   the handle exists. That covers the path the rebuild fixture never
///   exercised: the run is still `running` when the collect starts, so `wait`
///   must really wait and be woken. The graded value is a fresh nonce; see the
///   test body for how its round trip is pinned to the collected run.
///
/// - **The teaching** (`theModelCollectsItsOwnBackgroundRun`): the prompt
///   tells the model *not* to block, so the only thing that can make it spend
///   a `wait` call is the instruction the pending envelope carries on the
///   handle. This run is the evidence for this package's "in-band teaching
///   beats upfront prose" rule, and it stays exactly as recorded: same
///   fixture, same prompt, same discovery surface. Do not delete it and do
///   not soften its prompt.
///
/// **This suite is the inversion of the one this file used to hold, and the
/// inversion is the finding.** It was written to end a turn with a run still
/// going, so that Router's `respond` drain would be the only thing that could
/// collect it — the drain's snapshot of every background run, its continuation
/// turn and its bounded re-entry at
/// `RoutedSessionActor.backgroundRunDrainRoundLimit` had never executed in any
/// scenario this target ships. The recorded run answered plainly:
///
/// ```
/// PARKED-DRAIN [parkedRunDrain] elapsed=635.2s parkedAtAnswer=[] parkedAfterRespond=[]
///   waitCalls=3 terminals=[] returned=["rebuildArchive"] groundedIn=["rebuildArchive"]
///   reply="Rebuild is underway.  Manifest code: 58204"
/// ```
///
/// That block is left exactly as the run printed it, and it is the one place in
/// this target that still spells the old vocabulary. It is a record of a run
/// that happened, from the era when the runner printed `PARKED-DRAIN` for a
/// scenario named `parkedRunDrain` — a marker mirroring Router's own
/// `parkedRunDrain` — and it carries a `terminals=` field the runner no longer
/// prints at all. Rewriting it would report words no run ever said. The runner
/// prints `IN-BAND-CANARY … backgroundRunsAtAnswer= backgroundRunsAfterRespond=`
/// today; read the line above as history, never as the shape of a fresh run.
///
/// **Router then said why no fixture could have changed it**, in
/// `RoutedSessionActorGeneration`'s "How often this drain enters its loop"
/// comment (their commit `b4c0282`, card `^466d38p`): every background run hands
/// the model a `PendingRunEnvelope` whose text tells it to collect that run with
/// a `wait` call before it answers; `BackgroundToolRunner` writes that text, and
/// `ToolContext` starts no background run of its own, so **no host can start one
/// without the instruction** — a host whose tools always advise collection is
/// every host, not an unusual one. The condition is unreachable, and it is
/// unreachable upstream of anything a fixture here controls.
///
/// **What a failure means, which is the whole point of keeping both tests.**
/// If either test fails `noBackgroundRunsAtAnswer` — if a turn really does end
/// with a run still going — then the drain has become reachable from this
/// host, and task `^xeqs138`'s original question reopens: Router's drain would
/// be running in production for the first time, and nothing in this target
/// covers it. `noBackgroundRunsAtAnswer` and `inBandCollection` failing
/// together is that reading. Do not relax either of them to make a run green;
/// file the question instead. That is also why `noBackgroundRunsAtAnswer`
/// survives in both shapes: a model that ends its turn with work still
/// outstanding fails it whatever the prompt said.
///
/// **What neither test proves.** Neither enters the drain, so neither says
/// anything about what the drain does or about its re-entry bound. Router's
/// own suite starts the runs it drains, so it proves what that loop does and
/// not how often a real model reaches it (`^466d38p`). Cite no suite here for
/// "the drain works".
///
/// **The rebuild fixture is fast, and must stay fast.** Nothing the teaching
/// test asserts is a statement about how long anything took: `runCode`
/// backgrounds every call whatever the tool does, and that backgrounding is
/// what produces the envelope, the `wait` call and the empty result alike. A
/// slow fixture buys no reading there and once cost this suite its verdict
/// outright — `IntegrationArchiveRebuildTool` records what happened. The
/// delayed echo is slow for a different, stated reason: its subject is the
/// deferred settlement itself, and `integrationDelayedEchoDelay` records why
/// its few seconds are load-bearing where the rebuild's would be waste.
///
/// Like every other suite here, this one belongs to the nested
/// `IntegrationTests` package; the root manifest declares no target for it, so
/// the root `swift test` stays green with zero downloads and zero live
/// inference, and the command that reaches this suite is
/// `swift test --package-path IntegrationTests --no-parallel`. The
/// grading rule itself is covered without a live model, on the recorded run
/// above and on its inverse, in `ScenarioGradingTests`.
@Suite(
    "Gated in-band collection canary (the model collects its own background run)",
    .serialized,
    // Sixty-two minutes, re-derived on 2026-08-19 from measurement on the
    // slowest machine that runs this suite (task `^nhxj8hx`). Three eras sit
    // below and all are load-bearing: the first measured a defect, the second
    // measured its fix, and the third measured the machine the first two
    // ignored. Read all three before changing the number.
    //
    // BEFORE THE FIX, and why no ceiling helped.
    //
    // This limit read three minutes, on the reasoning that peers finish in
    // 40-90 seconds and this scenario is one tool call plus one collect, so it
    // belongs with them. That reasoning was wrong, and its own closing line —
    // "if this suite ever legitimately needs longer, the reason is worth
    // finding rather than the ceiling worth raising" — is what found it.
    //
    // The reason is that this scenario costs an order of magnitude more model
    // generation than its peers, and costs a different amount every run.
    // Measured on 2026-08-16 against `Muse-Glimmer-30B-mxfp4`, one run per row,
    // read off the session's own recorded `response` entries:
    //
    //   limit   outcome            tokensOut   ms       collected by
    //   180s    cut off             1,733      175,126  (never reached)
    //   600s    cut off             8,379      595,581  a second runCode
    //   1200s   PASSED, grounded      ~4,000    316,700  wait, one call
    //
    // A fourth run then refuted the "it just needs more room" reading, and a
    // ceiling of fifteen minutes with it:
    //
    //   900s    cut off             9,752      895,803  nothing — it looped
    //
    // That run made FIVE `runCode` calls. Four returned the same sentence,
    // "Archive rebuild is now under way. I will send you the exact manifest
    // code as soon as the rebuild completes."; the fifth died on `Can't find
    // variable: global`. The model wrote a snippet that fires `rebuildArchive`,
    // discards its return, and answers with a prose promise — and then wrote it
    // again. Every one of those snippets was graded `outcome: "succeeded"`,
    // because returning a string is a successful snippet. Nothing in band told
    // it that it had promised a value instead of reading one, so it had no
    // reason to write a different snippet the next time.
    //
    // That is the real failure and it was never a clock. Raising the ceiling
    // only bought a longer loop: one pass in four attempts, at 180s, 600s, 900s
    // and 1200s ceilings. Eight minutes was derived from exactly that — set
    // above the one measured pass (316.7s, `waitCalls=1`, grounded) and
    // reporting a runaway in half the time fifteen minutes would.
    //
    // AFTER THE FIX, which is where the pass-time distribution comes from.
    //
    // Task `^wnfzwxg` shipped the in-band notice that names the failure above:
    // a snippet that calls `tools.*` and returns a value carrying nothing those
    // calls returned is told exactly that, in the result it reads next. Its
    // first attempt asked for a string leaf before it would report, so it
    // stayed silent on `return { started: true }` — the discard as an object
    // rather than as prose, which is the shape the model actually writes — and
    // scored one pass in three:
    //
    //   313.5s  PASSED   waitCalls=3   answered with the manifest code
    //   471.2s  FAILED   waitCalls=2   answered "now under way"
    //   480.6s  FAILED                 time limit exceeded
    //
    // Dropping the string-leaf requirement is what worked. The notice now
    // closes any run whose returned value shares no text with what its calls
    // returned, and states that fact rather than accusing the snippet of
    // narrating. Three runs of that build, commit `00a1066`, against
    // `Qwen3.8-27B-mxfp4` and Router `aff8b1b`, each run on its own:
    //
    //   run   outcome   elapsed   waitCalls
    //   1     PASSED    445.5s    2
    //   2     PASSED    327.2s    3
    //   3     PASSED    113.0s    1
    //
    // Three passes in three, against one in four before the fix and one in
    // three after the first attempt at it. The times fell as far as the pass
    // rate rose, which is the mechanism working rather than luck: a model told
    // at once that its snippet carried nothing stops writing further snippets
    // to find out.
    //
    // THE SLOWEST MACHINE, which is where sixty-two minutes comes from.
    //
    // The ten-minute ceiling this replaces was derived from the numbers above
    // — all of them measured on this dev box — with a one-third margin over
    // the worst healthy pass (445.5s x 4/3 ≈ 594s). CI run `32203706380`
    // showed what that derivation ignored: the canary was cut off at 600s as
    // that run's only failure while the other ten suites passed. The ceiling
    // was reporting the runner's hardware as a defect.
    //
    // The measurements (local per-suite times on card `^dwzkfzx`):
    //
    //   local, 2026-08-19:  canary suite 368.491s of a 950.159s whole run,
    //                       so the other ten suites cost 581.668s
    //   CI, 32203706380:    whole run 4214s with the canary cut at 600s,
    //                       so the other ten suites cost about 3614s
    //
    // The same ten suites cost 6.21 times more on that runner (3614 / 581.7).
    // Projecting the canary onto it: 368.5s x 6.21 ≈ 2289s for the latest
    // local pass, and 445.5s x 6.21 ≈ 2768s for the worst healthy pass on
    // record. The same one-third margin over the worst projection gives
    // 2768s x 4/3 ≈ 3690s: sixty-two minutes.
    //
    // This is a re-derivation, not a raise. The instrument is a hang
    // detector, and a hang detector must clear every healthy run on every
    // machine that runs it; a number below a healthy run on the slowest
    // machine measures hardware, not defects. A genuine runaway still reports
    // in about an hour, where no limit at all would wait for the CI job's own
    // timeout. The standing rule is intact: never raise a ceiling to make a
    // run green — re-derive it from the machine that failed, or remove it.
    //
    // The limit applies to each test in this suite. The mechanism test has no
    // recorded runs yet; when its times exist, derive its own tighter ceiling
    // from them rather than guessing one here.
    .timeLimit(.minutes(15))
)
struct InBandCollectionCanaryTests {
    @Test("the delayed echo's value comes back through its handle, collected in band")
    func theDelayedEchoRoundTripsThroughItsHandle() async throws {
        // The shortest sequence that still passes through the real machinery:
        // call the named tool, take the handle, collect, report. Direct mode
        // removes discovery, so no `searchTools` turn runs at all.
        //
        // The nonce is minted fresh for this run, so no prior run and no
        // training text can supply it. It does appear in the prompt — the
        // model has to pass it — so the reply alone proves nothing: the
        // `grounded` check requires the echo to have handed the value back,
        // and `inBandCollection` requires a `wait` call to have collected the
        // run that carried it. A model that parrots the prompt without
        // running anything fails both.
        let nonce = integrationDelayedEchoNonce()
        try await runInBandCollectionCanaryScenario(
            name: "delayedEchoMechanism",
            tools: { log in [IntegrationDelayedEchoTool(log: log)] },
            // Names the tool and the value, and asks for the result. It does
            // not say how to collect: the pending envelope on the handle
            // carries that instruction, as it does for every host.
            prompt: "Call the \(IntegrationDelayedEchoTool.path) tool with the value \(nonce). "
                + "Report the exact value it returns.",
            answerContainsOneOf: [nonce],
            groundedIn: IntegrationScenarioGrounding.delayedEcho,
            direct: true
        )
    }

    @Test("the model collects its own background run, and the turn ends with nothing still running")
    func theModelCollectsItsOwnBackgroundRun() async throws {
        try await runInBandCollectionCanaryScenario(
            name: "inBandCollection",
            tools: { log in [IntegrationArchiveRebuildTool(log: log)] },
            // Asks for the manifest code, so the answer needs the run's result;
            // and says plainly not to block for it, so the model is being asked
            // *not* to spend a `wait` call. Both halves are still load-bearing
            // after the inversion, and the second one more so: the recorded run
            // blocked anyway, three times, which is how strongly the pending
            // envelope's own instruction outweighs the request. A prompt that
            // asked the model to wait would make `inBandCollection` a test of
            // the prompt; this one makes it a test of the product.
            //
            // Phrased as a user request rather than as coaching: "start it, tell
            // me when it is running, give me the code when it lands" is how
            // someone asks for work they do not want to sit through.
            prompt: "Rebuild my archive index and tell me its exact manifest code. Do not block "
                + "waiting for it: start the rebuild, reply as soon as it is under way, and give me "
                + "the manifest code once it reaches you.",
            // The rebuild fixture always reports the same manifest code, and it
            // reaches the model only through the collected run's terminal
            // `detail` — a hallucinated answer cannot match it.
            answerContainsOneOf: integerAnswers(for: integrationArchiveRebuildManifestCode),
            groundedIn: IntegrationScenarioGrounding.archiveRebuild
        )
    }
}
