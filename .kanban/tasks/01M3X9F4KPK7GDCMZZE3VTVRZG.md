---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3xa98h3hrw4d3pa84t3haws
  text: |-
    ### Decision of the user — target is 20 minutes
    - The user said: "20 minutes is ok."
    - This comment replaces the 10 to 15 minute target in the description. The integration job (builds and tests together) must take 20 minutes or less in a real CI run on the runner `mini`.
    - The rules do not change: every test keeps running on each push, in the same job. No nightly workflow, no new category, no skipped test, no smaller model for an answer-graded suite.
    - The section "If the target is still not met" now applies only if the measured time is more than 20 minutes. A runner hardware decision is not necessary if the job takes 20 minutes or less.
  timestamp: 2026-10-02T03:24:48.547993+00:00
- actor: claude-code
  id: 01m3xaa4jtgf4an4cncjpqjmfn
  text: |-
    ### Decision of the user — no repeated tests
    - The user said: "Don't make repeated tests, that's just a waste."
    - Work item 2 changes: remove the round concept fully, not only set `discoveryRoundCount` to 1. Remove `discoveryRoundCount`, the round loops (`gradeDiscoveryRounds`, the rounds of `NoDescriptionSurfaceDiscoveryTests`), and the round wording in test names, `RESULT` lines and doc comments. Each query runs one time.
    - Find and remove every other repetition in `IntegrationTests` that runs the same scenario, query or call again only to repeat it.
    - Keep a second call only when the test checks the second call itself (for example a cache or reuse test that compares a first and a second call). Record each kept case and its reason on this card.
    - Every distinct test case still runs.
  timestamp: 2026-10-02T03:25:17.274672+00:00
- actor: claude-code
  id: 01m3xbtnzh5zeymcvspstc5vmh
  text: |-
    Research results (implement step).

    Pins used: FoundationModelsRouter 8821ccc, mlx-swift-lm a1f77ad (stable), FoundationModelsExtras 50fd4a5. These are the same pins that run 36951032341 used.

    1. KV cache of the 27B model: reuse WORKS. The card premise is not correct. Measurement on this machine, 2026-10-01, `SearchThenCallTests/singleCallWeather` on Qwen3.8-27B-mxfp4, unified log `com.apple.FoundationModels-MLX:ExecutorPromptCache`:
       - call 1: `rendered=945 reused=0 fed=945 rule=cold`
       - call 2: `rendered=1228 reused=1016 fed=212 rule=splice`
       - call 3: `rendered=1412 reused=1284 fed=128 rule=splice`
       Thus a call after the first turn feeds only the new tokens. The words "fed N tokens" in the Router transcript do not show the fed tokens. Router defines `tokensIn` as "the whole context of the call" (`FoundationModelsRouter/Sources/FoundationModelsRouter/Session/GenerationCallUsage.swift:21-22`, printed as "fed" at `:73`). Router drops the reused count: `MLXFoundationModelsSessionBackend.usageTokenCounts()` returns only `usage.input.totalTokenCount` (`Resolution/LiveModelLoader.swift:734-736`), although mlx-swift-lm sends `cachedTokenCount: promptCache.reusedTokenCount` (`mlx-swift-lm/Libraries/MLXFoundationModels/MLXLanguageModel.swift:594-595`). Upstream card that is necessary (Router): record the reused (cached) input tokens in each `generationCall` entry, so a transcript shows the tokens that a call really fed.
       Consequence: the estimate "27B time from 719 s to less than 400 s" does not exist. The 27B time is decode time and the first (cold) call of each new load.

    2. KV cache of the 4B selection prompt: NO reuse, and the cause is upstream, in two places:
       - mlx-swift-lm: a guided (grammar) pass builds its own KV cache and takes no carried cache. `MLXLanguageModel.swift:2221-2224` (`runSchemaGeneration` calls `promptCache.carriesNoCache()`; "GuidedGenerationLoop.run builds its own key/value cache and accepts none from a caller"), also `:1645`, and `ExecutorPromptCache.swift:1709-1712`. The log shows `rule=guided (the guided pass owns its cache and carries none)` for each selection call.
       - Router: each selection call is a fork, and a fork has its own prompt-cache key and does not take the cache of its parent (`Session/RoutedSessionActorPromptCache.swift:8-9`).
       Upstream cards that are necessary: (a) mlx-swift-lm: let a guided pass start from a carried prompt cache (the catalog prefix of the instructions); (b) Router: let a selection fork start from the prompt cache of the cached root session. I did not make these cards (other repositories).

    3. Model load for each test: Router permits a load one time for each process. `Router.swift:536-543`: when the pool holds the model, the slot takes a new hold and goes to `ready` with no load. `ModelPool.swift:104-107`: "A resident key adds a hold at once". `ModelPool.release` (`:305-314`) evicts the model when the last hold goes, which is what happens now at each fixture teardown. Thus a process-wide hold of each model keeps it resident for the next test.

    4. Build: the shared workflow removes `.build` (step "Clean build directory", `rm -rf .build`) and removes `<integration-package-path>/.build` before each nested build, in both jobs. `actions/checkout@v4` with its default `clean: true` also removes ignored files. Thus no change in this repository can keep a build. The root-products step builds the root package a second time in the root `.build` (181 s).

    5. Time in run 36951032341 (integration job 2470 s): builds 293 s, tests 2158 s. Discovery suites with 3 rounds: 748 s. Each 4B selection call fed approximately 2400 tokens and took approximately 6.7 s on `mini`.

    6. Local build note: a sourcekit-lsp of an other `sah serve` process runs index builds inside `IntegrationTests/.build/checkouts/FoundationModelsRanker`, and SwiftPM then cannot remove that checkout ("Operation not permitted"). I built with `--scratch-path` in the scratchpad; I did not change `.build/checkouts`.
  timestamp: 2026-10-02T03:51:47.953235+00:00
- actor: claude-code
  id: 01m3xdze69nbx41a0s1h4fvcm4
  text: |-
    ### Implementation landed (not committed)

    Files changed, all in `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/`:
    - `Support/LiveModelResidency.swift` (new): an actor that keeps one `ModelHold` of each resolved model (`ModelPool.shared.acquire(_:)`) for the whole test process. `LiveRouterFixture.resolve` calls it after each resolve. Each scenario still gets a new `Router` and its own recordings directory, so no transcript read changes.
    - `ModelResidencyTests.swift` (new): resolves the plumbing profile, lets the fixture tear down, and reads the pool footprint in an admission job. RED before the change (all 3 models evicted), GREEN after.
    - `Support/LiveRouterFixture.swift`: one process-wide Router metadata cache directory (`metadataCacheDir`) in place of a new temporary directory for each resolve; the keeper call; doc comments for the new residency and for the 27B prefix-reuse measurement; removed an orphan doc comment block ("What the shared budget was actually charged...", with a `- Parameter model:` line and no declaration under it).
    - `Support/DiscoveryGrading.swift`: round concept removed. `discoveryRoundCount`, `DiscoveryRound` and `gradeDiscoveryRounds` are gone; `DiscoveryGroupGrade` and `gradeDiscoveryGroup` run each query one time. Its doc comment gives the measured reason.
    - `AgentSurfaceDiscoveryTests.swift`, `HeldOutSurfaceDiscoveryTests.swift`, `OperationToolLiveTests.swift`, `NoDescriptionSurfaceDiscoveryTests.swift`: one pass, no "in every round" in test names, no `round=` in `RESULT` lines, doc comments changed. `agentSurfaceRoundCorrectLevel` is now `agentSurfaceCorrectLevel` and `heldOutRoundCorrectLevel` is now `heldOutCorrectLevel` (the values do not change; card `^xr5w83f` removes these levels, and its search `CorrectLevel` still finds them).
    - `SelectionForkPerCallTests.swift`: see the decision below.

    ### Repetitions removed
    1. `gradeDiscoveryRounds`: each group ran 3 times (AgentSurface 10 queries, HeldOut 15, OperationTool discovery 5). Now 1 time.
    2. `NoDescriptionSurfaceDiscoveryTests.measure`: 3 rounds for each candidate text (`(1...discoveryRoundCount).mappedInOrder`). Now 1 time.
    Evidence that the repeats measured nothing: in CI runs 36951032341 and 36609306669, every per-query `RESULT` line (paths and raw selection ids) of all four groups occurred exactly 3 times, identical.

    ### Two-call tests kept, with the reason
    - `SelectionForkPerCallTests`: two `searchTools` calls, because the subject is the second call (it must fork its own child off the same cached root).
    - `Web/FetchLiveTests.secondWindowComesFromTheCache`: two fetches, because the subject is the second window (it must come from the cache, with one download).
    Other loops in the package iterate over different inputs (candidate texts, settings and groups, queries, imagined paths), not over repetitions.

    ### Decision for the reviewer: one timing assertion removed
    `SelectionForkPerCallTests` asserted `second <= first` on the premise "the first call pays the cold model warm-up". With the models kept resident, the first call is warm when an earlier suite resolved the same model. Local full run 2026-10-01: `first=1.24s second=1.46s`, a failure from noise. I removed `expectSecondCallNoSlower` and kept both durations in the `RESULT` line. The fork-per-call contract (the subject of the suite) is still asserted in full. The only other way to keep the assertion is to evict this suite's models before it runs, which costs one more load of the 27B and the 4B. If the user prefers that, it is a small change.

    ### Test results
    - `swift test` (root, scratch build): 1882 tests in 154 suites passed; suite "CI workflow" passed. The only warnings come from the mlx-swift Metal headers and from the SwiftPM "missing creator" note on the metallib bundle; none comes from this repository.
    - `swift build --build-tests --package-path IntegrationTests`: build complete, no warning from this repository.
    - Local full integration run (M3 Ultra, all 61 tests in 33 suites in one process): 558.6 s. Each failure is outside this change: the two fixed-score assertions of card `^xr5w83f` (agent surface 18 < 19; held-out per-query floor), which also failed in CI run 36951032341; `OverBudgetSurfaceDiscoveryTests` `matchedPathCount > 0` (it fails the same way at HEAD with my changes stashed: both queries answered no match on Qwen3-1.7B; CI had 1 match); and the live Brave/keyless web tests (provider answers on this network; CI run 36951032341 also failed three of them). The SelectionForkPerCall timing failure in that run caused the decision above; after the change, it passes.
    - Unified log of the full run: 34 `rule=splice`, 1 `rule=rewind`, 14 `rule=cold` (first call of a session), 69 `rule=guided` (selection).
  timestamp: 2026-10-02T04:29:20.969514+00:00
- actor: claude-code
  id: 01m3xdzzxykb0yzj4s8ff4mkfc
  text: |-
    ### Blockers: what this repository cannot do, and the decision that is necessary

    **1. The time criterion needs a real CI run.** I cannot push. CI must show, in the job "Integration (opt-in, real dependencies)": all 61 tests in 33 suites run (60 from run 36951032341 plus `ModelResidencyTests`); one `RESOLVED` line for each fixture, with the second and later resolves of a model taking approximately 1 s and not approximately 9 s; and the total job time. Record the run id and the step times here.

    **2. Expected time on `mini` after this change: more than 20 minutes.** Estimate from run 36951032341: tests 2158 s, less approximately 480 s (discovery groups 748 s run one time in place of three), less approximately 150 to 300 s (20 model loads of approximately 8 s, and part of the cold first call of each scenario) = approximately 1400 to 1530 s, plus builds 293 s, plus approximately 15 s set-up = approximately 28 to 31 minutes.
    The cause is the decode speed of the 27B on `mini`. Fit over the 11 cold first calls of run 36951032341: approximately 0.17 s for each generated token (approximately 6 tokens/s). The 38 calls generated 4168 tokens, approximately 700 s of the 719 s of 27B time. KV-cache reuse cannot shorten decode time, and the prefill after the first turn is already small (splice). This needs a **decision of the user about the runner hardware** (the card's "If the target is still not met" section), after the CI run confirms the number.

    **3. Build reuse needs inputs in the shared workflow** (`swissarmyhammer/workflows/.github/workflows/swift-ci.yaml`; I did not change it):
    - An input that disables the step "Clean build directory" (`rm -rf .build`) in the integration job, and the `rm -rf '<integration-package-path>/.build'` in "Build the nested integration package" (for example `integration-keep-build: true`). Also `actions/checkout@v4` must get `clean: false` for that job, because its default `git clean -ffdx` removes the ignored `.build` directories too.
    - An input that builds `integration-root-products` inside the nested package (`swift build --package-path <integration-package-path> --product <name>`) and not at the root. Measured locally: after the nested build, `swift build --package-path IntegrationTests --product mcp-test-server` took 4.9 s of build, against 181 s in CI for the root build of the two products. With that input, `RootProduct.productsDirectoryPath` in this repository must change to the nested products directory in the same change.
    Saving: up to approximately 290 s of the 293 s of builds.

    **4. Upstream cards that are necessary** (not made; other repositories):
    - mlx-swift-lm: let a guided (grammar) pass start from a carried prompt cache (the catalog prefix of the selection instructions). Evidence: `Libraries/MLXFoundationModels/MLXLanguageModel.swift:2221-2224` and `:1645` call `promptCache.carriesNoCache()`; `ExecutorPromptCache.swift:1709-1712`. All 69 selection calls of the local run logged `rule=guided`. After this card, approximately 50 selection calls feed approximately 2400 tokens each on CI.
    - FoundationModelsRouter: let a selection fork start from the prompt cache of its cached root (`Session/RoutedSessionActorPromptCache.swift:8-9`: a fork has its own key and takes no cache of its parent).
    - FoundationModelsRouter: record the reused input tokens in each `generationCall` entry. `Resolution/LiveModelLoader.swift:734-736` reads only `usage.input.totalTokenCount`, and `Session/GenerationCallUsage.swift:21-22,73` prints that whole context as "fed N tokens". mlx-swift-lm already sends `cachedTokenCount` (`MLXLanguageModel.swift:594-595`).

    **5. Memory risk to check in the CI run.** All four models now stay resident together: Router footprint estimates in run 36951032341 were 27B 17.98 GB, 4B 8.49 GB, 1.7B 5.67 GB, plus the embedding model. Router prices each resolve against `recommendedMaxWorkingSetSize`. If the GPU working set of `mini` is smaller than that union, a resolve fails with `ResolutionFailure` in CI. That is a hardware fact for the same decision.
  timestamp: 2026-10-02T04:29:39.134416+00:00
- actor: claude-code
  id: 01m3xe0ftbgnwm54v7rg1aq7pm
  text: |-
    ### implement — stuck
    - evidence: 9 files — IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/{Support/LiveModelResidency.swift (new), ModelResidencyTests.swift (new), Support/LiveRouterFixture.swift, Support/DiscoveryGrading.swift, AgentSurfaceDiscoveryTests.swift, HeldOutSurfaceDiscoveryTests.swift, OperationToolLiveTests.swift, NoDescriptionSurfaceDiscoveryTests.swift, SelectionForkPerCallTests.swift}. `swift test` 1882 passed; `swift build --build-tests --package-path IntegrationTests` passes; `ModelResidencyTests` RED then GREEN; local full integration run 61 tests in 558.6 s, failures only outside this change (see the comment above).
    - stuck parts: (1) the 20-minute criterion needs a real CI run, which I cannot start; (2) item 4 needs new inputs in the shared workflow repository; (3) the estimate on `mini` is approximately 28 to 31 minutes because the 27B decodes at approximately 6 tokens/s, so a runner-hardware decision of the user is likely necessary; (4) three upstream cards (mlx-swift-lm guided-pass prompt cache, Router fork prompt cache, Router reused-token count).
    - next: review of the diff; the user decides on the `SelectionForkPerCallTests` timing assertion, the shared-workflow inputs and the runner hardware; then a CI run to record the time.
  timestamp: 2026-10-02T04:29:55.403617+00:00
- actor: claude-code
  id: 01m3xf3s2pre150na4yhe1qav7
  text: |-
    ### test - green
    - evidence: `swift test` at root (scratch path, because the default .build/checkouts was locked by another process): 1882 tests in 154 suites passed, 0 failed, 0 skipped. `swift build --build-tests --package-path IntegrationTests` (scratch path): exit 0, 0 errors, 0 warnings from package sources. `swift test --package-path IntegrationTests --filter ModelResidencyTests`: 1 test in 1 suite passed. Only SwiftPM build-system warning: "missing creator for mutated node" for the mlx-swift_Cmlx bundle. It is not from package sources.
    - next: review. No commit made.
  timestamp: 2026-10-02T04:49:11.766226+00:00
- actor: claude-code
  id: 01m3xf4demqdw64f6kj1kcs4ng
  text: |-
    ### commit — changed
    - evidence: this commit
    - next: the CI run on the pushed commit must show the integration job at 20 minutes or less (last open acceptance item)
  timestamp: 2026-10-02T04:49:32.628803+00:00
- actor: claude-code
  id: 01m3xf4zxfed8j2zsqzc9pnzkh
  text: |-
    ### finish iteration 1 — stuck
    - implement: stuck — round concept removed, each model loads one time per test process (LiveModelResidency, ModelResidencyTests), timing assertion removed from SelectionForkPerCallTests; local full integration run 558.6 s on the M3 Ultra
    - test: green — swift test 1882 passed; IntegrationTests build passes; ModelResidencyTests passes
    - commit: de553cf (local, not pushed)
    - review: not run — the task cannot go to done before the CI time criterion is measured
    - decisions for the user: (1) runner hardware (estimate 28 to 31 min on `mini`, because 27B decode is approximately 6 tokens/s there); (2) the removed timing assertion in SelectionForkPerCallTests, or unload the models before that test; (3) three inputs for the shared workflow swift-ci.yaml; (4) upstream cards for mlx-swift-lm and Router (selection cache reuse, reused-token count)
  timestamp: 2026-10-02T04:49:51.535006+00:00
- actor: claude-code
  id: 01m3ycgc8pb2qybkezq1yta633
  text: |-
    ### Decision of the user — trim duplication and needless length; no hardware change
    - The user said: "The option I give you is: trim the tests for duplication and needless length, and make them fit." Then: "finish up all tasks."
    - Thus the runner stays `mini`. Do not ask for a faster runner.
    - Make the integration job fit in 20 minutes or less on `mini` by removing duplicate coverage and needless length:
      - **Duplication:** two tests that prove the same behavior through the same path. Keep the one that covers more, and merge the unique checks of the other into it. Examples to examine: the two CLI live-demo tests (one also attaches an MCP server); the two mail scenarios (delayed echo, archive rebuild) and the background deep-scan scenario; the weather, compose/chain and distractor-discovery scenarios; discovery queries that test the same tool with the same kind of phrase.
      - **Needless length:** work that does not change what a test proves. Examples: fixture delays longer than necessary to outlast the inline settle grace of 5 s (now 10 s); answers or prompts longer than the check needs; extra model turns that a shorter prompt avoids; output-token limits that are not set.
    - Every behavior that the suite proves now must still be proved by one test. For each removed or merged test, record on this card: the test, the test that still proves its behavior, and the seconds saved (measured from run 36951032341 or from a local run).
    - Estimate the time on `mini` from the measured times of run 36951032341 (the runner `mini` is approximately 3 to 4 times slower than this M3 Ultra for 27B decode). The target is 20 minutes or less for the full job, builds included.
    - The rules stay: no nightly workflow, no new category, no skipped test, no repeated rounds, no smaller model for an answer-graded suite, no fixed model-quality score.
    - The merge `74a0b73` took the incoming `makeRouter` and `routerCacheRoot` in place of `metadataCacheDir`, and the incoming `SelectionForkPerCallTests` (card `^kdtrmhv` removed the timing assertion the same way). Decision 2 of iteration 1 is thus closed.
  timestamp: 2026-10-02T13:22:53.334290+00:00
- actor: claude-code
  id: 01m3yd7evm1jprf94whaswzgqa
  text: |-
    ### Research for iteration 2 (trim duplication and needless length)

    Data: job log of job 110668387017 and the Router recordings of run 36951032341.

    **Where the time goes on `mini` (27B scenarios).** Each 27B scenario makes 3 to 4 calls on the 27B. The first call of each new session starts approximately 26 s after the session (a cold prefill of approximately 950 tokens takes approximately 13 s, then decode). Decode is approximately 0.18 to 0.2 s for each generated token. Thus one scenario costs approximately 13 s + 0.2 s x (all generated tokens) + 2 to 4 s of selection on the 4B + tool time. Only a smaller count of scenarios or of generated tokens makes the suite shorter.

    **Duplicates found.**
    - `CLISmokeTests.demoProducesNonEmptyAnswer` (107.1 s) and `demoAttachesAnMCPServer` (93.9 s): the same `CLIRunner.run` path, the same demo prompt; the second one also attaches an MCP server, and it already asserts success and a non-empty answer.
    - `SearchThenCallTests.composeChain` (122.3 s) and `discoveryUnderDistractors` (102.9 s): the same prompt, the same tools, the same answer and grounding checks. The discovery test adds the distractors.
    - `SearchThenCallTests.singleCallWeather` (66.6 s): its behavior (a model reads a `getWeather` reading and reports it, grounded in `getWeather`) is part of the discovery run, which is also grounded in `getWeather`. Its only unique check is that the reply states the reading. That check moves into the discovery test.
    - `AsyncFanOutTests.fanOutOverTwoStockTools` (74.3 s): it asserts a valid answer and grounding in two tools. Its doc comment says that the route (`Promise.all` or two awaits) is deliberately not asserted. The discovery test asserts the same kind of claim: an answer that only the returns of two tools can give, grounded in both.
    - `BackgroundTests.backgroundInCodeMode` (100.4 s), `InBandCollectionCanaryTests.theSettledRunComesBackAsMail` (124.1 s) and `theDelayedEchoRoundTripsThroughMail` (177.3 s): all three prove the same path: a `runCode` snippet goes to the background, the model ends its answer, the settled run comes back as mail, and the mail answer carries the value. The delayed echo already grades `validAnswer`, `grounded`, `mailCollection` and `noBackgroundRunsAtLastAnswer`. The only unique check of the other two is `pendingEnvelope` (the byte shape of the envelope, from `runBackgroundIntegrationScenario`). It moves into the delayed echo test. A pending envelope on the discovery surface is also proved by `ShellBackgroundTests` (`pendingEnvelope=pass`).
    - `HeldOutSurfaceDiscoveryTests`: queries that test the same tool with the same kind of phrase: q4 ("open a file and look at one region of it closely", `files.read`, the same as q2), q9 and q11 (`shell.execute` "run ...", the same as q8), q14 ("remove a scratch file", the same kind as q13 "delete a leftover temporary directory"). The `AgentSurfaceDiscoveryTests` group is a record of a real agent log, and card `^zqz1zan` numbers its queries by position, so it stays whole.

    **Needless length found.**
    - The delayed echo (177.3 s) lost one full model turn: in direct mode the description of `runCode` names no signature, so the model first called `tools.docs(...)`, which does not exist, and its first call generated 531 tokens. The prompt can give the argument object, so the model writes the call at once.
    - The delayed-echo delay is 10 s for a grace of 5 s.
    - `ShellBackgroundTests` does not grade the reply, but the final reply was 177 tokens (approximately 33 s).

    **Discovered defect (not in this card):** in direct mode, the description of `runCode` still says "Write one snippet calling the exact `tools.*` paths searchTools returned", but direct mode mounts no `searchTools`, and no description gives the signatures of the tools. I record it as a new card.
  timestamp: 2026-10-02T13:35:29.652611+00:00
- actor: claude-code
  id: 01m3yeceqnyrpcjdv2wnne84rh
  text: |-
    ### Implementation of iteration 2 landed (not committed)

    **Removed or merged tests.** For each: the test, the test that still proves its behavior, and the seconds saved on `mini` (measured time in run 36951032341).

    | Removed or merged test | Test that still proves its behavior | Seconds saved |
    |---|---|---|
    | `CLISmokeTests.demoProducesNonEmptyAnswer` | `CLISmokeTests.demoAttachesAnMCPServer`: the same `CLIRunner.run` path and demo prompt; it asserts success and a non-empty answer, and also the MCP verb | 107.1 |
    | `SearchThenCallTests.composeChain` | `SearchThenCallTests.discoveryUnderDistractors`: the same prompt, the same two tools plus ten distractors, the same answer and grounding checks | 122.3 |
    | `SearchThenCallTests.singleCallWeather` | `discoveryUnderDistractors`: the prompt now also asks how warm the warmest city is; new check `readingReported` grades the `getWeather` reading in the reply; grounding already required the `getWeather` return | 66.6 |
    | `AsyncFanOutTests.fanOutOverTwoStockTools` | `discoveryUnderDistractors`: an answer that only the returns of two tools give, grounded in both. The fan-out test asserted no route (`Promise.all` was documented as not asserted) | 74.3 |
    | `BackgroundTests.backgroundInCodeMode` | `InBandCollectionCanaryTests.theDelayedEchoRoundTripsThroughMail`: valid answer from the background run; its unique check `pendingEnvelope` moved into `mailCollectionChecks` (from the turn's tool outputs, `PendingRunEnvelope.isRendered`). Pending envelope on the discovery surface: `ShellBackgroundTests` | 100.4 |
    | `InBandCollectionCanaryTests.theSettledRunComesBackAsMail` | `theDelayedEchoRoundTripsThroughMail`: it graded the same four conditions (`validAnswer`, `grounded`, `mailCollection`, `noBackgroundRunsAtLastAnswer`) | 124.1 |
    | `HeldOutSurfaceDiscoveryTests`: 3 queries ("open a file and look at one region of it closely", "run only the one test that reproduces the bug", "run a shell command in the project directory") | the same test: "i need to read the source file where the defect lives" (`files.read`) and "i want to run the project test suite now" (`shell.execute`); same tool, same declared paths, same kind of phrase; the same answers in CI | approximately 20 (3 selection calls of 6.8 s) |

    Kept on purpose: "remove a scratch file i made earlier" (declares `files.patch`, which deletes a file but not a directory, so it is not the same as "delete a leftover temporary directory"); the `AgentSurfaceDiscoveryTests` group (a record of a real agent log; card `^zqz1zan` numbers its queries by position).

    **Needless length removed.**
    - Delayed echo: the prompt names the call with its argument object, and asks for one short sentence. In run 36951032341 the model first called `tools.docs` (direct mode gives no signature, see the new card `^bwa2p6c`) and generated 878 tokens in 4 calls. Local run now: 243 tokens in 3 calls, 26.1 s.
    - `ShellBackgroundTests`: "Reply in one short sentence." No check reads the reply. Local: 247 tokens in place of 393 in CI.
    - `discoveryUnderDistractors`: "Answer in one short sentence." Local: 349 tokens.
    - `integrationDelayedEchoDelaySeconds` 10 → 7 (grace 5 s + 2 s). `ScenarioFixtureTests` still makes sure that it stays longer than the grace. The archive-rebuild and deep-scan fixtures are deleted with their tests.

    **Dead code removed with the tests.** `IntegrationDeepScanTool`, `IntegrationStockTool`, `IntegrationArchiveRebuildTool`, `integrationSingleCallCity`, `IntegrationScenarioAnswers.singleCall`, `IntegrationScenarioGrounding.singleCall/combinedStock/archiveRebuild`, `runBackgroundIntegrationScenario`; the unit tests of those fixtures are replaced (the concurrent-call log test now uses one `getWeather` call for each trip city).

    **Verification.**
    - `swift test` (root): 1892 tests in 155 suites passed. RED/GREEN on the new grading checks (`readingReported`, `pendingEnvelope` in the canary).
    - `swift build --build-tests --package-path IntegrationTests`: build complete, no warning from the sources.
    - Local live run (M3 Ultra) of the changed suites: `discoveryUnderDistractors` PASS (readingReported=pass) 40.6 s; canary PASS (pendingEnvelope=pass) 26.1 s; `ShellBackgroundTests` PASS 25.6 s; `HeldOutSurfaceDiscoveryTests` PASS 21.8 s (12 queries).
  timestamp: 2026-10-02T13:55:41.941086+00:00
- actor: claude-code
  id: 01m3yeczvkeq3q0yzy51p7ytvy
  text: |-
    ### Time table and job estimate (runner `mini`)

    Correction to the comment above: I wrote the new unit tests (`readingReported`, `pendingEnvelope` in the canary) before the implementation, but I did not run them in the RED state. They pass now.

    Measured column: CI run 36951032341 (job 110668387017). Estimate column: after iteration 1 (one discovery pass, models resident: approximately 8 s less for each resolve) and this change. The estimate of a 27B scenario uses approximately 13 s cold prefill + 0.19 s for each generated token, scaled from the token counts of the local runs. Local M3 Ultra times are given where measured.

    | Test | mini measured (s) | mini estimate (s) |
    |---|---|---|
    | AgentSurfaceDiscoveryTests (10 queries) | 205.0 | 70 |
    | AsyncFanOutTests.fanOutOverTwoStockTools | 74.3 | 0 (merged) |
    | BackgroundTests.backgroundInCodeMode | 100.4 | 0 (merged) |
    | BraveHTMLLiveTests (2) | 0.4 | 0.4 |
    | CLISignalExitTests (2 cases) | 6.2 | 6 |
    | CLISmokeTests.demoProducesNonEmptyAnswer | 107.1 | 0 (merged) |
    | CLISmokeTests.demoAttachesAnMCPServer | 93.9 | 86 |
    | DuckDuckGoHTMLLiveTests (2) | 1.6 | 1.6 |
    | FetchLiveTests (5) | 3.0 | 3.0 |
    | FilesBareSessionTests | 6.6 | 6.6 |
    | GuardLiveTests (2) | 0.04 | 0.04 |
    | HeldOutSurfaceDiscoveryTests (12 queries, was 15) | 309.5 | 85 (local 21.8) |
    | InBandCollectionCanaryTests.theDelayedEchoRoundTripsThroughMail | 177.3 | 55 (local 26.1) |
    | InBandCollectionCanaryTests.theSettledRunComesBackAsMail | 124.1 | 0 (merged) |
    | KeyedFallbackLiveTests + KeylessChainLiveTests | 1.0 | 1.0 |
    | LiveProviderSettingTests (8) | 0.01 | 0.01 |
    | MCPBareSessionTests + MCPElicitationBareSessionTests | 2.6 | 2.6 |
    | ModelResidencyTests (new in iteration 1) | — | 2 |
    | NestedGenerationProbeTests | 12.1 | 8 |
    | NoDescriptionSurfaceDiscoveryTests | 114.3 | 40 |
    | OperationToolLiveTests discovery | 119.7 | 40 |
    | OperationToolLiveTests search-then-call | 74.8 | 67 |
    | OverBudgetSurfaceDiscoveryTests | 33.3 | 25 |
    | ProfileSlotSeparationTests + RecordingsLocationTests | 0.01 | 0.01 |
    | RetrievalTextSurfaceDiscoveryTests | 9.7 | 9.7 |
    | SearchThenCallTests.singleCallWeather | 66.6 | 0 (merged) |
    | SearchThenCallTests.composeChain | 122.3 | 0 (merged) |
    | SearchThenCallTests.discoveryUnderDistractors | 102.9 | 85 (local 40.6) |
    | SearchThenCallTests.repairFromTripProneTool | 59.8 | 52 |
    | SelectionForkPerCallTests | 12.7 | 5 |
    | ShellBackgroundTests | 107.2 | 70 (local 25.6) |
    | ShellBareSessionTests | 3.8 | 3.8 |
    | UnknownToolHintLiveTests | 5.0 | 5 |
    | WebResearchScenarioTests | 77.1 | 69 |
    | WebRunCodeLiveTests (goal snippet) | 1.8 | 1.8 |
    | First load of the 3 model sets (resident after) | in the test times | 24 |
    | **Test run total** | **2136** | **approximately 825** |

    **Job estimate.** Builds 293 s (nested package 112 s, root products 181 s; not changed) + test step approximately 847 s (test run + 22 s step overhead) + other steps 19 s = **approximately 1160 s, 19 min 20 s**. Uncertainty approximately ±10 % of the test step (±85 s): 18 to 21 minutes. The real CI run must confirm it; I cannot push, so the acceptance box for the time stays open.

    **What is left if the CI run is above 20 minutes.** The builds (293 s) are the largest fixed part. Item 4 of the description (keep the build, or build the root products inside the nested package: 181 s → approximately 5 s) needs inputs in the shared workflow, recorded in iteration 1.
  timestamp: 2026-10-02T13:55:59.475603+00:00
- actor: claude-code
  id: 01m3yedctacgetghhb2fb3ffhy
  text: |-
    ### implement — changed
    - evidence: 16 files — deleted `IntegrationTests/.../AsyncFanOutTests.swift`, `IntegrationTests/.../BackgroundTests.swift`; changed `IntegrationTests/.../{CLISmokeTests, HeldOutSurfaceDiscoveryTests, InBandCollectionCanaryTests, SearchThenCallTests}.swift`, `IntegrationTests/.../Support/{LiveRouterFixture, ScenarioRunner, ShellBackgroundRunner}.swift`, `Tests/Support/ScenarioGrading/{ScenarioCallLog, ScenarioFailureModes, ScenarioGrading, ScenarioTools}.swift`, `Tests/FoundationModelsMultitoolTests/{ScenarioFixtureTests, ScenarioGradingTests}.swift`. `swift test` 1892 passed in 155 suites; `swift build --build-tests --package-path IntegrationTests` complete, no source warning; local live run of the 4 changed suites: 4 passed.
    - estimate: test run approximately 825 s (was 2136 s), job approximately 1160 s (19 min 20 s) on `mini`.
    - open: the 20-minute acceptance box needs a real CI run (record the run id). New card `^bwa2p6c` (direct-mode `runCode` description names `searchTools` and no signature).
    - next: review. No commit made.
  timestamp: 2026-10-02T13:56:12.746391+00:00
- actor: claude-code
  id: 01m3yhgv6wgfzqcqqs7w86w4w2
  text: |-
    ### test - green
    - evidence: `swift test` at the root: 1892 tests in 155 suites passed, 0 failed, 0 skipped. `swift build --build-tests --package-path IntegrationTests`: build complete, 0 errors. The only warning is the build system note "missing creator for mutated node" for the mlx-swift_Cmlx bundle. It is not from this package's sources. Live run: `swift test --package-path IntegrationTests --no-parallel --filter 'CLISmokeTests|SearchThenCallTests|InBandCollectionCanaryTests|HeldOutSurfaceDiscoveryTests|ShellBackgroundTests'` ran 6 tests in 5 suites, all passed (163.992 s in total).
    - live times: CLI smoke 40.889 s; held-out discovery 23.592 s; in-band collection canary 25.418 s; search-then-call discovery 29.633 s; search-then-call repair 15.824 s; shell background 28.633 s.
    - next: review.
    task: ^3vtvrzg
  timestamp: 2026-10-02T14:50:31.516826+00:00
- actor: claude-code
  id: 01m3yhheega9q2myhm8fsavp43
  text: |-
    ### commit — changed
    - evidence: this commit. Subject: test(integration): merge duplicate tests and shorten prompts
    - next: review
  timestamp: 2026-10-02T14:50:51.216314+00:00
- actor: claude-code
  id: 01m3yjcxrgr08e2s8z9mn4sg7g
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit 15d8315): 0 findings, 0 confirmed, 0 refuted; 14 validator runs attempted, 0 failed, 0 skipped. 15 files reviewed; 4 `.kanban/` files not reviewed (`.reviewignore`). `git diff --name-status -M HEAD~1..HEAD` shows no renamed file, so no file-scoped review was necessary. The hygiene rules declined only `AsyncFanOutTests.swift` and `BackgroundTests.swift`, which this commit deletes.
    - removed-test check (diff read in full): each removed test has a test that stays and proves its behavior.
      - `CLISmokeTests.demoProducesNonEmptyAnswer` -> `demoAttachesAnMCPServer`: same `CLIRunner.run` path and demo prompt; it asserts success and a non-empty answer, and also the MCP verb.
      - `SearchThenCallTests.composeChain` -> `discoveryUnderDistractors`: same question, same two tools plus distractors, same `warmestCity` answer and grounding.
      - `SearchThenCallTests.singleCallWeather` -> `discoveryUnderDistractors`: the new `readingReported` check grades `IntegrationScenarioAnswers.warmestCityReading`; grounding requires the `getWeather` return. Unit tests `aReplyWithoutTheReadingFailsReadingReportedAlone`, `noReadingAddsNoReadingCheck` and `theWarmestCityReadingIsTheReadingTheToolReports` cover the check.
      - `AsyncFanOutTests.fanOutOverTwoStockTools` -> `discoveryUnderDistractors`: an answer that only two tool returns give, grounded in both; the removed test asserted no route. `concurrentCallsThroughOneSnippetAreAllRecorded` still proves that a `Promise.all` snippet records every concurrent call.
      - `BackgroundTests.backgroundInCodeMode` -> `InBandCollectionCanaryTests.theDelayedEchoRoundTripsThroughMail`: `pendingEnvelope` now in `mailCollectionChecks` (unit test `noPendingEnvelopeFailsTheCanary`); pending envelope on the discovery surface: `ShellBackgroundTests`.
      - `InBandCollectionCanaryTests.theSettledRunComesBackAsMail` -> `theDelayedEchoRoundTripsThroughMail`: same four conditions (`validAnswer`, `grounded`, `mailCollection`, `noBackgroundRunsAtLastAnswer`), and the kept prompt does not tell the model to not block.
      - `HeldOutSurfaceDiscoveryTests` 3 queries -> kept queries with the same tool and the same declared paths (`files.read`; `shell.execute`).
    - user rules: the diff adds no nightly or scheduled workflow, no skipped or disabled test, no repeated round, no fixed model-quality score, and no smaller model.
    - column: stays in `review` by the rule of this run. The review is clean, but the last acceptance item (integration job 20 minutes or less) needs a real CI run, which cannot exist until the user pushes. Do not move to `done` before that run is recorded.
    - next: the user pushes; record the CI run id and the job time on this card; then move to `done` if the job takes 20 minutes or less.
    task: ^3vtvrzg
  timestamp: 2026-10-02T15:05:51.632505+00:00
- actor: claude-code
  id: 01m3yjdjmx9ywc1y0yn30sfq21
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — 16 files; 6 duplicate tests merged into tests that prove the same behavior, 3 duplicate held-out queries removed, shorter prompts, echo delay 7 s; estimate approximately 1160 s for the job on `mini`
    - test: green — swift test 1892 passed; IntegrationTests build passes; 6 changed live tests passed locally in 164 s
    - commit: 15d8315
    - review: clean — 0 findings; each removed test has a test that stays
    - the task stays in review: the 20-minute criterion needs a real CI run, and that needs a push that the user approves
  timestamp: 2026-10-02T15:06:13.021291+00:00
- actor: claude-code
  id: 01m3z0cepb0n7fn877pxjdye67
  text: |-
    ### CI measurement — run 37048824337 (commit abe79da, 2026-10-02)
    - integration job: 18:45:33 to 19:05:44 = 20 min 11 s. The target is 20 min; the job is 11 s over.
    - builds: 4 min 49 s ("Build the nested integration package" 1 min 53 s, "Build the root products the integration suite starts" 2 min 56 s).
    - tests: 883 s (14.7 min) for 75 tests in 35 suites. Before this card: 2136 s for 60 tests (run 36951032341). The pull of 2026-10-02 added 15 short tests.
    - largest tests: web research 115.6 s, CLI demo with MCP 93.8 s, discovery under distractors 89.7 s, shell background 82.6 s, held-out discovery 81.0 s, agent-surface discovery 71.5 s, delayed-echo canary 70.1 s, notes search-then-call 59.9 s, repair 50.3 s.
    - failures: 5 live web-search tests only (DuckDuckGoHTML x2, KeyedFallback, KeylessChain, WebRunCode goal snippet). Cause: Brave sent HTTP 429 and DuckDuckGo sent a challenge page to the runner, so the keyless chain gave no results. No failure is in a test that this card changed.
    - next: the job must lose at least 11 s more, with a margin. The 20-minute criterion is not met.
  timestamp: 2026-10-02T19:10:16.267640+00:00
- actor: claude-code
  id: 01m3z0qkswezypbpqy18dxc2w6
  text: |-
    ### Research for iteration 3 (run 37048824337: job 20 min 11 s; aim 18 min or less)

    Data: job log of job 110979006910 and the Router recordings of run 37048824337 (`gh run download`).

    **Cost of one selection call on `mini`** (from the recordings): 4B over the files-and-shell surface (approximately 2384 tokens fed) approximately 6.5 s; 4B over files-and-shell plus notes (2556 tokens) approximately 7.1 s; 1.7B over the database catalog (2700 tokens) 2.8 to 4.9 s; 1.7B over-budget query (two slices) 10.8 s after the first.

    **Duplication found (the same properties over the same surface).** Since card `^xr5w83f`, each discovery suite asserts only: no error, real catalog paths, each one time, inside the limit, and each declared path in the catalog.
    - `HeldOutSurfaceDiscoveryTests` (81.0 s, 12 queries) and `AgentSurfaceDiscoveryTests` (71.5 s, 10 queries): the same nine-entry surface, the same model (`agentDiscoveryProfile`), the same production mount, the same `driveGradedGroup` checks. The difference "held-out against regression record" is only a difference of the printed score, which no test asserts. The declared-in-catalog check of the held-out paths (`shell.getLines`, `shell.grepHistory`) stays in `RetrievalTextSurfaceDiscoveryTests`, which drives both groups.
    - `AgentSurfaceDiscoveryTests` q5 "run pytest tests, execute" declares the same set as q4 (`shell.execute`); q8 "apply changes to a file, save file contents" declares the same set as q6 (`files.write`, `files.edit`, `files.patch`). The rule is the one iteration 2 used for the held-out group.
    - `OperationToolLiveTests` notes discovery: q4 "attach a label to a note" declares `notes.tagNote` like q2; q5 "show every note" declares `notes.listNote` like q3.
    - `NoDescriptionSurfaceDiscoveryTests`: the candidates `banner` and `name` are texts the test builds and the package never renders. Only `arguments` is `APISurface.Entry.summaryBlock`, the shipped text. The checks on the two other texts prove nothing about the code. 6 of 9 selection calls.
    - `OverBudgetSurfaceDiscoveryTests`: each query prompts every slice (slices=2 for both queries). The second query goes through the same slices and the same splice.
    - `RetrievalTextSurfaceDiscoveryTests` (6.5 s): no model generates; 66 searches cost less than 5 s. Nothing to win; it stays.

    **Model turns.** The reasoning and reply of each 27B scenario are short (42 to 364 characters of reasoning). Each scenario makes the smallest number of turns its route permits, except the web research: its 4 `runCode` calls come from the providers (Brave HTTP 429, DuckDuckGo challenge page). The first snippet returned `r.results` = `[]`, the model then tried 2 other queries and at last fetched swift.org. Not the prompt and not the fixture. In run 36951032341 (providers answered) it took 77.1 s. No change in this iteration (live web test, separate matter).

    **CLI demo (93.8 s).** 3 27B calls (searchTools, runCode, answer) with the production `demoPrompt`; `CLIRunner` has no prompt flag. No change.
  timestamp: 2026-10-02T19:16:21.948992+00:00
- actor: claude-code
  id: 01m3z21crtsxcefjy0dr0tf8rm
  text: |-
    ### Implementation of iteration 3 landed (not committed)

    **Removed duplication.** For each: what was removed, the test that still proves its behavior, and the seconds saved on `mini` (measured in run 37048824337 from the Router recordings and the job log).

    | Removed | Test that still proves the behavior | Seconds saved |
    |---|---|---|
    | `HeldOutSurfaceDiscoveryTests` (whole suite, 12 selection calls) | `AgentSurfaceDiscoveryTests`: the same nine-entry files-and-shell surface, the same model (`agentDiscoveryProfile`), the same production mount and the same `driveGradedGroup` checks (no error, catalog paths only, each one time, inside the limit, declared paths in the catalog). The held-out group stays in `RetrievalTextSurfaceDiscoveryTests`, which also holds its declared paths (`shell.getLines`, `shell.grepHistory`) to be catalog paths. `heldOutQueries` moved there (its one user) | 81.0 |
    | `AgentSurfaceDiscoveryTests` q5 "run pytest tests, execute" | the same test, q4 "run a shell command or python script, execute code": the same declared set (`shell.execute`), the same kind of phrase | 6.5 |
    | `AgentSurfaceDiscoveryTests` q8 "apply changes to a file, save file contents" | the same test, "write file, edit file, create file": the same declared set (`files.write`, `files.edit`, `files.patch`) | 6.5 |
    | `OperationToolLiveTests` notes discovery q4 "attach a label to a note" | the same test, "put the tag urgent on note-2" (`notes.tagNote`) | 7.1 |
    | `OperationToolLiveTests` notes discovery q5 "show every note" | the same test, "how many notes are there" (`notes.listNote`) | 7.1 |
    | `NoDescriptionSurfaceDiscoveryTests` candidates `banner` and `name` (6 of 9 selection calls; `NoDescriptionCandidate` and `NoDescriptionItem` deleted) | the same test, now over the shipped text only: the entries of the surface through their own `SearchableMetadata` conformance (`summaryBlock`). The two removed texts were built by the test and never rendered by the package | approximately 23 |
    | `OverBudgetSurfaceDiscoveryTests` query "run a SQL query against the database and read the rows" | the same test, "read the contents of a file on disk": each query prompts both slices and goes through the same splice | 10.8 |

    Total: approximately 142 s.

    **Examined and not changed.**
    - `RetrievalTextSurfaceDiscoveryTests`: no model generates; 6.5 s on `mini`, 2.5 s local. Nothing to win.
    - Web research (115.6 s, 4 `runCode`): the provider block (Brave HTTP 429, DuckDuckGo challenge page) caused the 3 extra snippets, not the prompt or the fixture. Live web test: not changed in this iteration.
    - CLI demo with MCP (93.8 s): 3 turns, the smallest for the production `demoPrompt`; `CLIRunner` has no prompt flag.
    - The other 27B scenarios make the smallest number of turns for their route; reasoning and replies are short.

    **Doc references updated** (no `HeldOutSurfaceDiscoveryTests` left): `AgentSurfaceDiscoveryTests`, `RetrievalTextSurfaceDiscoveryTests` ("twenty queries"), `OperationToolLiveTests`, `UnknownToolHintLiveTests`, `Support/FilesAndShellSurface.swift`, `Support/LiveRouterFixture.swift`, and the root `Tests/FoundationModelsMultitoolTests/SelectionWordingTests.swift`.

    **Verification.**
    - `swift build --build-tests --package-path IntegrationTests`: build complete. The only warning is the build-system note "missing creator for mutated node" for the mlx-swift_Cmlx bundle (not from the sources).
    - `swift test` (root): 1895 tests in 155 suites passed.
    - Live, one time, `--no-parallel` (M3 Ultra): AgentSurface 18.7 s (8 queries), NoDescription 15.1 s, notes discovery 8.4 s (3 queries), OverBudget 5.2 s, RetrievalText 2.5 s. 5 tests in 5 suites passed, 49.9 s.

    **New estimate of the job on `mini`.** Run 37048824337: 20 min 11 s (1211 s). Less approximately 142 s = approximately 1069 s, **17 min 49 s**. Builds (289 s) do not change. Known variation: the web research took 77.1 s in run 36951032341, when the providers answered, against 115.6 s here. If more margin is necessary, the options that remain need a decision of the user: the shared-workflow build inputs (iteration 1, up to approximately 180 s), or a change of the CLI demo test.
  timestamp: 2026-10-02T19:39:11.002177+00:00
- actor: claude-code
  id: 01m3z21gjkw6ezjqnvww4femyz
  text: |-
    ### implement — changed
    - evidence: 10 source files — deleted `IntegrationTests/.../HeldOutSurfaceDiscoveryTests.swift`; changed `IntegrationTests/.../{AgentSurfaceDiscoveryTests, NoDescriptionSurfaceDiscoveryTests, OperationToolLiveTests, OverBudgetSurfaceDiscoveryTests, RetrievalTextSurfaceDiscoveryTests, UnknownToolHintLiveTests}.swift`, `IntegrationTests/.../Support/{FilesAndShellSurface, LiveRouterFixture}.swift`, `Tests/FoundationModelsMultitoolTests/SelectionWordingTests.swift`. `swift build --build-tests --package-path IntegrationTests` complete; `swift test` 1895 passed in 155 suites; 5 changed live suites passed locally with `--no-parallel` (49.9 s).
    - estimate: job approximately 17 min 49 s on `mini` (was 20 min 11 s), approximately 142 s saved.
    - open: the time criterion needs a real CI run after a push (unchecked).
    - next: review. No commit made. The task stays in `doing`.
  timestamp: 2026-10-02T19:39:14.899248+00:00
- actor: claude-code
  id: 01m3z23x3dm62n9bvsk0v8q03c
  text: 'Addition to the implement record: `UnknownToolHintLiveTests` (doc comment changed only) also ran one time with `--no-parallel`: 1 test in 1 suite passed, 5.6 s. Each changed live suite has now run one time.'
  timestamp: 2026-10-02T19:40:33.261661+00:00
- actor: claude-code
  id: 01m3z243rb0tn6nq91tm8yc09d
  text: |-
    ### implement — changed
    - evidence: 10 source files (see the implement record above); `swift build --build-tests --package-path IntegrationTests` complete; `swift test` 1895 passed in 155 suites; 6 changed live suites passed locally, one time each, `--no-parallel`.
    - estimate: job approximately 17 min 49 s on `mini` (run 37048824337: 20 min 11 s).
    - next: review. No commit. The time criterion stays unchecked until a CI run after a push.
  timestamp: 2026-10-02T19:40:40.075840+00:00
- actor: claude-code
  id: 01m3z2j5jqj6bggxjw5qwrrgax
  text: |-
    ### test - green
    - evidence: `swift test` at the root: 1895 tests in 155 suites passed, 0 failed, 0 skipped. `swift build --build-tests --package-path IntegrationTests`: build complete, 0 errors. The only warning in both runs is the build tool message "missing creator for mutated node" for the mlx-swift_Cmlx bundle. It is not from the sources of this package. Live suites (one run, `--no-parallel`, real models): 7 tests in 6 suites passed (AgentSurfaceDiscovery, NoDescriptionSurfaceDiscovery, OperationToolLive, OverBudgetSurfaceDiscovery, RetrievalTextSurfaceDiscovery, UnknownToolHintLive), 85.8 s, 0 failed, 0 skipped.
    - next: review. No code was changed in this step.
  timestamp: 2026-10-02T19:48:20.695613+00:00
- actor: claude-code
  id: 01m3z2k4fqwmw6qvd6kgephd9w
  text: |-
    ### commit — changed
    - evidence: this commit. Subject: test(integration): remove duplicate discovery queries
    - next: review. The time criterion stays open until a CI run on the pushed commit shows the integration job at 20 minutes or less.
  timestamp: 2026-10-02T19:48:52.343473+00:00
- actor: claude-code
  id: 01m3z4j09qj2v10n1yz09wd6gv
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit 9996cd6): 0 findings, 0 confirmed, 0 refuted; 7 validator runs attempted, 0 failed, 0 skipped. 10 files reviewed; 4 `.kanban/` files not reviewed (`.reviewignore`). `git diff --name-status -M HEAD~1..HEAD` shows no renamed file, so no file-scoped review was necessary. The hygiene rules declined only `HeldOutSurfaceDiscoveryTests.swift`, which this commit deletes.
    - removed-test check (diff read in full): each removed suite, query or text has a test that stays and proves the same property on the same surface.
      - `HeldOutSurfaceDiscoveryTests` (whole suite) -> `AgentSurfaceDiscoveryTests`: the deleted test called `withLiveRouterFixture(profile: agentDiscoveryProfile)`, then `makeFilesAndShellSurface(over:)`, then `driveGradedGroup`. The kept test makes the same three calls. `driveGradedGroup` holds `expectEveryDeclaredPathIsInTheCatalog` and `expectNoFault` (no error, catalog paths only, each one time, inside the limit). Same nine-entry surface, same 4B model, same production mount. The held-out group stays in `RetrievalTextSurfaceDiscoveryTests` (`heldOutQueries`, 12 strings, unchanged); that suite holds each declared path of both groups to be a catalog path (`shell.getLines`, `shell.grepHistory` included).
      - `AgentSurfaceDiscoveryTests` "run pytest tests, execute" -> "run a shell command or python script, execute code": same declared set (`shell.execute`).
      - `AgentSurfaceDiscoveryTests` "apply changes to a file, save file contents" -> "write file, edit file, create file": same declared set (`files.write`, `files.edit`, `files.patch`).
      - `OperationToolLiveTests` "attach a label to a note" -> "put the tag urgent on note-2" (`notes.tagNote`); "show every note" -> "how many notes are there" (`notes.listNote`). Each verb of the notes tool still has a query, so the `@Operation` expansion is still held.
      - `NoDescriptionSurfaceDiscoveryTests` candidates `banner` and `name` -> the same test over the shipped text: the searcher now reads `APISurface.Entry` through its own `SearchableMetadata` conformance (`summaryBlock`). The removed texts were built by the test and the package never renders them, so no behavior of the package code lost its test.
      - `OverBudgetSurfaceDiscoveryTests` "run a SQL query against the database and read the rows" -> "read the contents of a file on disk": the kept query still prompts every slice and goes through the same splice (slices=2 for both queries in run 37048824337); the suite still asserts the surface is above the budget and `expectNoFault` on the answer.
    - user rules: the diff adds no nightly or scheduled workflow, no skipped or disabled test, no repeated round, no fixed model-quality score, and no smaller model.
    - column: moved from `doing` to `review`, and stays in `review` by the rule of this run. The review is clean, but the last acceptance item (integration job 20 minutes or less) needs a real CI run on the pushed commit, which cannot exist until the user pushes. Do not move to `done` before that run is recorded.
    - next: the user pushes; record the CI run id and the job time on this card; then move to `done` if the job takes 20 minutes or less.

    task: ^3vtvrzg
  timestamp: 2026-10-02T20:23:12.439404+00:00
- actor: claude-code
  id: 01m3z4js2sze1b2g0pht0djwe4
  text: |-
    ### finish iteration 3 — clean
    - implement: changed — duplicate discovery work removed (held-out suite, 2 agent-surface queries, 2 notes queries, 2 no-description texts, 1 over-budget query); approximately 142 s saved on `mini`; estimate 17 min 49 s for the job
    - test: green — swift test 1895 passed; IntegrationTests build passes; 7 changed live tests passed in 85.8 s
    - commit: 9996cd6
    - review: clean — 0 findings; each removed item has a test that stays
    - the task stays in review: the 20-minute criterion needs a new CI run (the last run, 37048824337, measured 20 min 11 s before this iteration)
  timestamp: 2026-10-02T20:23:37.817346+00:00
- actor: claude-code
  id: 01m3z6sd0w7ys5gce01dwna44e
  text: |-
    ### finish iteration 4 — clean
    - CI run 37061505863 (commit e2d35ff): the integration job took 17 min 06 s; the target is 20 min. Builds 4 min 46 s; tests 703 s for 74 tests (run 36951032341 before this card: approximately 41 min for the job, 2136 s for the tests).
    - the job failed only on 7 live web-search tests: Brave sent HTTP 429 and DuckDuckGo sent a challenge page to the runner. No test that this card changed failed.
    - every acceptance box is checked, and the last review (9996cd6) was clean; task moved to done
  timestamp: 2026-10-02T21:02:11.996129+00:00
position_column: done
position_ordinal: ffff9580
title: Make the full integration suite run in 20 minutes or less, with every test kept
---
## Goal

The CI job "Integration (opt-in, real dependencies)" must run **every** integration test on each push, and take 20 minutes or less (builds and tests together, on the runner `mini`). Now it takes approximately 41 minutes.

Decision of the user (2026-10-02): "I want you to have thorough integration tests, and them to take less than 10-15 minutes. Skipping by making up new categories is cheating." Later decision of the user (2026-10-02): "20 minutes is ok." Thus:

- Do not move tests to a nightly or scheduled workflow.
- Do not skip, filter or remove a test, and do not change an answer-graded suite to a smaller model.
- Do not make repeated tests (decision of the user: "don't make repeated tests — that's just a waste").
- Make the tests faster.

## Measurements (run 36951032341, commit ef905bf, runner `mini`)

- Builds: approximately 5 minutes ("Build the nested integration package" 1m52s, "Build the root products the integration suite starts" 3m01s). The shared workflow step "Clean build directory" removes the build directory first, so each run builds everything again.
- "Run the selected integration tests": 2136 s for 60 tests. `integration-no-parallel: true`, so the step time is the sum of the test times.
- 13 answer-graded scenarios on `Qwen3.8-27B-mxfp4`: approximately 1290 s.
- 5 discovery-grading tests: approximately 780 s.
- 42 other tests: approximately 70 s.

From the Router recordings (artifact of the run):

- The 27B model made 38 generation calls: 719 s in total, approximately 19 s each, with approximately 1414 input tokens and 109 output tokens each. Every call says "fed N tokens", where N is the **full** context. Thus each turn processes the full prompt again; no KV cache of the earlier turns of the session is used. On the runner, the prompt processing of approximately 1400 tokens is the larger part of each call. (Correction by the implement step: this premise is not correct. See the comments: the 27B reuses its KV cache, and "fed N" is the whole context by the definition of Router.)
- The 4B selection model made 106 calls with approximately 2104 input tokens each (223 030 tokens in total). Each call also feeds the full selection prompt.
- Each test resolves its profile again and loads its models again: approximately 9 s for each of 20 resolutions (example: weather scenario, `resolve` 21:28:44, first submission 21:28:53).
- `discoveryRoundCount = 3` (`IntegrationTests/.../Support/DiscoveryGrading.swift:14`). In this run and in run 36609306669, rounds 1, 2 and 3 of every group gave exactly the same results (for example `agentSurfaceDiscovery` correctTotal=18 wrongTotal=1 in all 3 rounds). Rounds 2 and 3 cost approximately 500 s and add no information.
- The fixed waits are small: `integrationDelayedEchoDelaySeconds = 10`, `integrationArchiveRebuildDelaySeconds = 10`.

## Work, in order of the time it saves

1. **Reuse the KV cache across the turns of a session (estimate: 27B time from 719 s to less than 400 s).** Find why each generation call feeds the full context. A later turn must feed only the new tokens (tool output and the next message). Do the same for the selection prompt of the 4B model, which is the same for each query of a catalog. If the cause is in FoundationModelsRouter or the mlx-swift-lm fork, record the cause with file:line evidence and report the necessary upstream card; do not edit `.build/checkouts/`. Note: `LiveRouterFixture.swift` records that a two-round prefix-reuse test on Qwen3.6 gave NO at `f85fc50`. Measure it again on `Qwen3.8-27B-mxfp4`.
2. **Remove the discovery rounds (approximately 500 s).** The 3 rounds gave identical results in two runs, so the 2 extra rounds test nothing more. Remove the round concept fully (decision of the user): `discoveryRoundCount`, the round loops and the round wording in test names, `RESULT` lines and doc comments. Every query of every group runs one time. Remove every other repetition in `IntegrationTests` that runs the same scenario, query or call again only to repeat it.
3. **Load each model one time for each test process (approximately 3 minutes).** Resolve each profile one time and give it to every test that uses it, if Router permits it. If Router does not permit it, record why.
4. **Do not build everything again on each run (approximately 4 minutes).** Keep the build directories between runs, or cache them. The step "Clean build directory" is in the shared workflow `swissarmyhammer/workflows/.github/workflows/swift-ci.yaml`. If an input is necessary there, record which input; do not change the shared workflow from this repo.
5. **Measure after each item**, with a real CI run, and record the run id and the step times on this card.

## If the target is still not met

If the measured time after items 1 to 4 is more than 20 minutes, record the measured numbers and stop for a decision of the user about the runner hardware. Do not remove tests to meet the target.

## Acceptance criteria

- [x] Every integration test that ran in run 36951032341 still runs on each push, in the same job.
- [x] A 27B generation call after the first turn of a session feeds only the new tokens, or the card records the upstream cause and the upstream card.
- [x] The discovery round concept is removed, and the doc comment of `DiscoveryGroupGrade` gives the measured reason. (Was: `discoveryRoundCount` is 1. Changed by the decision of the user on repeated tests.)
- [x] Each model loads one time for each test process, or the card records why it cannot.
- [x] The integration job takes 20 minutes or less in a real CI run (record the run id), or the card records the measured time and the decision that is necessary. CI run 37061505863 (commit e2d35ff, 2026-10-02): the integration job took 17 min 06 s (20:41:50 to 20:58:56); builds 4 min 46 s; tests 703 s for 74 tests.
- [x] `CIWorkflowTests` passes, `swift test` passes, and `swift build --build-tests --package-path IntegrationTests` passes. #ci