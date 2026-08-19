import Testing

/// The gated canary over how a backgrounded run is actually collected on this
/// host: the model collects its own, in band, and the turn never ends with work
/// in flight (task `^xeqs138`).
///
/// **This suite is the inversion of the one this file used to hold, and the
/// inversion is the finding.** It was written to end a turn with a run still
/// going, so that Router's `respond` drain would be the only thing that could
/// collect it — the drain's snapshot of every background run, its continuation
/// turn and its bounded re-entry at
/// `RoutedSessionActor.parkedRunDrainRoundLimit` had never executed in any
/// scenario this target ships. The gated run answered plainly:
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
/// The model got the right answer and got it the wrong way for that scenario: it
/// called `wait` three times and collected the run itself. Holding the fixture
/// longer only makes the model wait longer.
///
/// **Router then said why no fixture could have changed it**, in
/// `RoutedSessionActorGeneration`'s "How often this drain enters its loop"
/// comment (their commit `b4c0282`, card `^466d38p`): every background run hands
/// the model a `PendingRunEnvelope` whose text tells it to collect that run with
/// a `wait` call before it answers; `DetachingTool` writes that text, and
/// `ToolContext` starts no background run of its own, so **no host can start one
/// without the instruction** — a host whose tools always advise collection is
/// every host, not an unusual one. The condition is unreachable, and it is
/// unreachable upstream of anything a fixture here controls.
///
/// So the assertions were inverted rather than relaxed. A gated test that can
/// never pass is a liability: the next reader loosens one condition until the
/// suite goes green, and the loosened version passes vacuously forever.
///
/// **What this suite now asserts** is the path that really runs — the model
/// makes at least one `wait` call, no background run is left at the instant its
/// first turn ends and again when `respond` returns — and it asserts that
/// beside an answer carrying the rebuild's own manifest code, so a run where
/// *nothing happened* fails rather than passes.
///
/// **What its failure means, which is the whole point of keeping it.** If this
/// test ever fails — if a turn does end with a run still going — then the drain
/// has become reachable from this host, and task `^xeqs138`'s original question
/// reopens: Router's drain would be running in production for the first time,
/// and nothing in this target covers it. `noBackgroundRunsAtAnswer` and
/// `inBandCollection` failing together is that reading. Do not relax either of
/// them to make a run green; file the question instead.
///
/// **What it still does not prove.** It never enters the drain, so it says
/// nothing about what the drain does or about its re-entry bound. Router's own
/// suite starts the runs it drains, through a stub-model detaching tool or as
/// background runs directly, so it proves what that loop does and not how often
/// a real model reaches it (`^466d38p`). Cite no suite here for "the drain
/// works".
///
/// **The rebuild fixture is fast, and must stay fast.** Nothing this suite
/// asserts is a statement about how long anything took: `runCode` backgrounds
/// every call whatever the tool does, and that backgrounding is what produces
/// the envelope, the `wait` call and the empty result alike. A slow fixture
/// buys no reading here and once cost this suite its verdict outright —
/// `IntegrationArchiveRebuildTool` records what happened. Do not put a wait
/// back into it to make the timing "observable".
///
/// `.enabled(if: multitoolIntegrationEnabled)` like every other gated suite —
/// with `MULTITOOL_INTEGRATION` unset the whole thing is skipped, so ungated
/// `swift test` stays green with zero downloads and zero live inference. The
/// grading rule itself is covered ungated, on the recorded run above and on its
/// inverse, in `ScenarioGradingTests`.
@Suite(
    "Gated in-band collection canary (the model collects its own background run)",
    .serialized,
    // Ten minutes, re-derived on 2026-08-17 from post-fix measurement. Two
    // eras of runs sit below and both are load-bearing: the first measured a
    // defect and is where eight minutes came from, the second measured the fix
    // and is why the number moved. Read both before changing it.
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
    // AFTER THE FIX, which is where ten minutes comes from.
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
    // TEN MINUTES WAS NOT NEEDED TO PASS. All three runs above finished inside
    // the eight-minute ceiling this replaces, so nothing here recovers a
    // failing run, and the standing rule — never raise a ceiling to make a run
    // green — is intact. What the measurement changed is the margin. 480s
    // stands 35 seconds above the worst of the three at 445.5s, and those 35
    // seconds have to cover more than generation: `elapsed` above times
    // `respond` alone, while the limit starts when the test starts and is spent
    // on the turnstile queue and the profile load ahead of it as well
    // (`IntegrationGate`). A margin that thin fails the suite for queueing
    // rather than for a defect — the exact misattribution that file records,
    // and the one `--no-parallel` exists to keep out of the reading.
    //
    // Ten minutes clears the worst observed run by about a third, and still
    // reports a genuine runaway at ten minutes where the peer suites would take
    // thirty. Those peers finish in 40-90 seconds and keep their own tighter
    // expectations of themselves; nothing here licenses raising their ceilings.
    .timeLimit(.minutes(10)),
    .enabled(if: multitoolIntegrationEnabled)
)
struct InBandCollectionCanaryTests {
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
