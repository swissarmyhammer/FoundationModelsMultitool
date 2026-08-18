---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0afew7gdc2e2m39m05mzy0x
  text: |-
    Picked up. First gated probe run is done — one `--filter PrefixReuse --no-parallel` run with a temporary diagnostic that dumps every `.flash`-slot recorded event.

    ```
    RESULT [prefixReuse] first=6.518s second=4.135s
    PROBE seq=0 kind=session  session=01M0AFD0N829877J1G6BRKEP9S parent=01M0AFD0N79H5F4SWNAKBPMEX1 tokensIn=nil  tokensOut=nil ms=nil    textLen=-1
    PROBE seq=1 kind=prompt   session=01M0AFD0N829877J1G6BRKEP9S parent=01M0AFD0N79H5F4SWNAKBPMEX1 tokensIn=nil  tokensOut=nil ms=nil    textLen=41
    PROBE seq=2 kind=response session=01M0AFD0N829877J1G6BRKEP9S parent=01M0AFD0N79H5F4SWNAKBPMEX1 tokensIn=1144 tokensOut=14  ms=6513  textLen=-1
    PROBE seq=3 kind=session  session=01M0AFD70WD4QZ3PBSS6S13ARX parent=01M0AFD0N79H5F4SWNAKBPMEX1 tokensIn=nil  tokensOut=nil ms=nil    textLen=-1
    PROBE seq=4 kind=prompt   session=01M0AFD70WD4QZ3PBSS6S13ARX parent=01M0AFD0N79H5F4SWNAKBPMEX1 tokensIn=nil  tokensOut=nil ms=nil    textLen=22
    PROBE seq=5 kind=response session=01M0AFD70WD4QZ3PBSS6S13ARX parent=01M0AFD0N79H5F4SWNAKBPMEX1 tokensIn=1144 tokensOut=11  ms=4133  textLen=-1
    ```

    Two facts the run establishes:

    1. The `fork()`-per-call path is real and visible. Two distinct child session ids, both with the SAME parent id — one prefix-rooted root session, one fresh child per selection call. That is the mechanism the suite drives, and it is worth keeping.
    2. `tokensIn` is recorded, and it is 1144 on BOTH calls — identical, although the two prompts are different lengths (41 vs 22 characters, so a few tokens apart). A number that does not move with the prompt cannot report what a turn prefilled.

    Tracing what `usage.input` actually counts before deciding between the card's two resolutions.
  timestamp: 2026-08-18T13:02:35.760042+00:00
- actor: claude-code
  id: 01m0ah47v3y0ervywsjg93xxv6
  text: |-
    ## The decision: resolution 2, and the evidence that closes resolution 1

    `tokensIn` cannot distinguish a skipped prefill from a full re-prefill. Traced through the shipped build, not assumed:

    - `RoutedSessionActorTurnExecution` snapshots `backend.usageTokenCounts()` before the turn and after, and `RoutedSessionActorRecording.usageDelta(before:after:)` subtracts them. `LiveModelLoader.usageTokenCounts()` returns `(usage.input.totalTokenCount, usage.output.totalTokenCount)`.
    - `totalTokenCount` is the WHOLE rendered prompt. Upstream it is `GenerateCompletionInfo.promptTokenCount` = `inputText.tokens.size`. It counts the render whether or not a cached prefix was skipped.
    - The one figure that answers the question is `usage.input.cachedTokenCount`. `LiveModelLoader.usageTokenCounts()` reads only the two `totalTokenCount`s and **drops it**.
    - Worse: in the pinned `mlx-swift-lm` (`Package.resolved` → branch `stable`, `acc92059`) the FoundationModels executor carries **no prompt cache at all** — no `ExecutorPromptCache.swift`, no `ChatSession`/`trimToCommonPrefix`, and `cachedTokenCount: 0` is a hardcoded literal at all five `emitUsage` sites. Nothing is ever skipped on this path, so there is nothing for a count to report.
    - `TranscriptEvent` carries only `tokensIn`, `tokensOut`, `ms`. No skipped-token count, no cache-hit count, no prefill time.

    Surfacing `cachedTokenCount` would mean widening `LanguageModelSessionBackend.usageTokenCounts()` (one production conformer plus ~20 test stubs), `usageDelta`, `TranscriptEvent.Partial`, `SessionEvent.TokenUsage`, `SessionProjection` and `TokenBudget` — **and it would still read `0`** until the pin moves off `acc92059`. That is Router and upstream work, not this card.

    There is a second oddity the code does not explain, recorded so nobody chases it twice: both turns report exactly `tokensIn=1144`, across three separate runs, although the two intents tokenize 8 and 6 tokens under the model's own tokenizer. Every hop from `emitUsage` to the stamp is straight-line per-turn whole-render arithmetic, so the code predicts `X` and `X-2`. The discrepancy can only live in the closed FoundationModels hop between the executor's `updateUsage` event and `LanguageModelSession.usage`. Nothing asserts on that number.

    ## What landed

    `PrefixReuseTests.swift` → `SelectionForkPerCallTests.swift`, renamed and narrowed, not deleted. It now asserts the mechanism it actually drives, read off the recording:

    1. at least one recorded selection generation per `searchTools` call;
    2. at least one distinct child session per call — the second call forks its own, it does not reuse the first's;
    3. every generation names the root it was forked from;
    4. exactly ONE distinct root across the run — the cached root was not dropped and rebuilt.

    The timing check `second <= first` stays, stated as a warm-vs-cold timing check, with the doc saying in as many words that warm-up alone satisfies it and no reader should take it for reuse.

    Also corrected, so the doc no longer claims what the `fork()` does not do: `LiveModelLoader.makeFork(tools:)` builds a brand-new `LanguageModelSession` seeded from the parent's *transcript*. The child inherits history, not a prefilled KV cache — the old doc comment said KV cache.

    ## Gated runs

    Verification run, `--filter SelectionForkPerCall --no-parallel`:

    ```
    RESULT [selectionFork] first=5.858s second=3.590s children=2 roots=1
    RESULT [selectionFork] generation seq=2 tokensIn=1144(asserted on by nothing) tokensOut=14 ms=5854
    RESULT [selectionFork] generation seq=5 tokensIn=1144(asserted on by nothing) tokensOut=11 ms=3588
    ✔ 1 test in 1 suite passed after 13.420 seconds
    ```

    **Non-vacuity run.** The whole point of this card is that an assertion nobody watched fail is worthless, so all four new assertions were inverted and run gated. All four failed, each with the real observed number in its message:

    ```
    ✘ generations.count >= 3      — "but the .flash slot recorded 2"
    ✘ childSessionIds.count >= 3  — "but the run recorded 2"
    ✘ unforkedGenerationCount == 1 — "but 0 of 2 name no parent at all"
    ✘ rootSessionIds.count == 2   — "but the run recorded 1 distinct roots"
    ✘ 1 test in 1 suite failed with 4 issues
    ```

    Reverted, re-run, green.

    ## Prose corrected in `IntegrationGate.swift`

    - The Muse Glimmer paragraph no longer ends "so `PrefixReuseTests` had nothing left to measure". It now states plainly that no suite here ever graded the swap, and that the cache-shape argument rests on the two architectures and on `mlx-swift-lm`'s `f85fc50`.
    - The Qwen3.8 comparison paragraph gains the recorded-entries finding above.
    - The closing line no longer says "do not cite `PrefixReuseTests`"; it says no suite here can be cited, names `SelectionForkPerCallTests` as the least citable of all, and points at `f85fc50`.
    - The `--no-parallel` timing table row and the Qwen3.5-9B run record carry the new name.

    Stale names also fixed in `ScenarioRunner.swift`, `NativeTranscript.swift`, `SelectionGrammar.swift` and `plan.md` (whose "the gated `PrefixReuseTests` pins it" now says the suite holds the fork-per-call contract, and warns that no suite here can see whether a prefill was skipped). The three surviving mentions of the old name are deliberate — each says "it was called that" while correcting what it claimed.
  timestamp: 2026-08-18T13:31:44.355392+00:00
- actor: claude-code
  id: 01m0ah54s3hae01br2b6m7c2z1
  text: |-
    ### implement — changed
    - evidence: 7 files — Tests/FoundationModelsMultitoolIntegrationTests/SelectionForkPerCallTests.swift (new), Tests/FoundationModelsMultitoolIntegrationTests/PrefixReuseTests.swift (deleted), Tests/FoundationModelsMultitoolIntegrationTests/Support/IntegrationGate.swift, Tests/FoundationModelsMultitoolIntegrationTests/Support/NativeTranscript.swift, Tests/FoundationModelsMultitoolIntegrationTests/Support/ScenarioRunner.swift, Sources/FoundationModelsMultitool/Discovery/SelectionGrammar.swift, plan.md. Ungated `swift test`: 359 tests/30 suites and 59 tests/11 suites, zero failures, zero warnings. Gated `--filter SelectionForkPerCall --no-parallel`: 1 test/1 suite passed, `children=2 roots=1`, both turns `tokensIn=1144`. Non-vacuity run with all four assertions inverted: 4 issues, one per assertion.
    - next: ready for `/review`
  timestamp: 2026-08-18T13:32:13.987258+00:00
- actor: claude-code
  id: 01m0ahq75s1yw3dr404fwn3gys
  text: |
    ### review — findings
    - evidence: `review sha HEAD~1..HEAD` (`2df6579`) — engine fleet 7 validator passes over 6 files, 0 findings (2 `.kanban/` files excluded by `.reviewignore`). Directed fact-check of the doc comments against `.build/checkouts/` found 3 — Tests/FoundationModelsMultitoolIntegrationTests/Support/IntegrationGate.swift:340, Tests/FoundationModelsMultitoolIntegrationTests/SelectionForkPerCallTests.swift:53, Tests/FoundationModelsMultitoolIntegrationTests/SelectionForkPerCallTests.swift:68. All three are one cause: `usageTokenCounts()` and `makeFork(tools:)` are attributed to `LiveModelLoader`, but both are members of `MLXFoundationModelsSessionBackend` (LiveModelLoader.swift:237); `LiveModelLoader` is a separate public struct at :759 declaring neither. Only the file name is `LiveModelLoader.swift`.
    - verified and holding: all four substantive claims — `tokensIn` = `usage.input.totalTokenCount` = whole rendered prompt; `cachedTokenCount` dropped at that method; pin really is `acc92059` with no prompt cache in its FoundationModels executor and `cachedTokenCount: 0` literal at all five emission sites; `makeFork` seeds a new session from the parent transcript, no KV cache. No surviving prose credits the deleted suite. The other four files changed comments and prose only.
    - next: correct the owning type at every site in both files, then re-run `/review ^akpzysf`
  timestamp: 2026-08-18T13:42:06.265541+00:00
- actor: claude-code
  id: 01m0ahr9wbe9avxg1qvw0k8rwm
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 7 files; `PrefixReuseTests.swift` deleted, `SelectionForkPerCallTests.swift` added
    - test: green — ungated `swift test` 359 tests/30 suites and 59 tests/11 suites; gated `--filter SelectionForkPerCall --no-parallel` 1 test/1 suite, `children=2 roots=1`
    - commit: 2df6579
    - review: findings — the engine passed the commit clean (7 validator passes, 6 files, 0 findings). All 3 findings come from the directed fact-check, and they share one cause: the new prose names `LiveModelLoader` as the owner of `usageTokenCounts()` and `makeFork(tools:)`. Both belong to `MLXFoundationModelsSessionBackend`. Only the file name matches — `LiveModelLoader` is a separate `public struct` in the same file and declares neither method. Sites: `IntegrationGate.swift:340`, `SelectionForkPerCallTests.swift:53`, `SelectionForkPerCallTests.swift:68`
    - next: correct the attribution at every site, including this card's own "Resolved" prose, which repeats the same error

    **Everything the fact-check was aimed at held.** `tokensIn` is `usage.input.totalTokenCount`, and the review added the step the doc had left implicit: it is stamped as a delta of two cumulative snapshots, which equals the turn's own whole render only because each fork starts a fresh session at zero. `cachedTokenCount` is dropped at that method. The pin is `acc92059` and its FoundationModels executor carries no prompt cache at all — no `ChatSession`, no `cache:` argument, and `cachedTokenCount: 0` as a literal at all five emission sites. `makeFork` seeds a new session from the parent's transcript and copies no KV cache.

    So the finding is real and narrow. The reasoning the suite rests on is sound; the sentence naming who owns the method is wrong. That is worth fixing exactly because the prose is the only thing telling the next reader where to look, and it currently sends them to a struct that does not have it.
  timestamp: 2026-08-18T13:42:41.803456+00:00
- actor: claude-code
  id: 01m0aj3qetwpkbe1y9v5wmscsd
  text: |-
    Picked the card back up from `review` and worked the three findings. They are one cause, and the cause was removed everywhere, not only at the three flagged lines.

    ## The owning type, checked in the pinned checkout

    `.build/checkouts/FoundationModelsRouter/Sources/FoundationModelsRouter/Resolution/LiveModelLoader.swift` declares, in order: `MLXFoundationModelsContainer` (`:117`), `MLXFoundationModelsSessionBackend` (`:237`), `LiveEmbeddingContainer` (`:668`), `ModelLoaderError` (`:728`), `LiveModelLoader` (`:759`), `UnconfiguredModelLoader` (`:1016`). Both `makeFork(tools:)` (`:573`) and `usageTokenCounts()` (`:648`) sit inside the `:237`-`:667` class. The `LiveModelLoader` struct declares neither.

    ## Every `LiveModelLoader` mention audited, not only the flagged ones

    Eleven mentions survive outside `.build`. Each was checked against the source:

    - **Wrong, and fixed** — `IntegrationGate.swift` (the `cachedTokenCount` paragraph, now `MLXFoundationModelsSessionBackend.usageTokenCounts()`), `SelectionForkPerCallTests.swift` (both the `usageTokenCounts()` and the `makeFork(tools:)` sentences).
    - **Wrong for the same reason, found by the sweep and not in any finding** — `IntegrationGate.swift`'s Qwen3.5-2B paragraph said "`LiveModelLoader`'s `defaultMaxTokens`". It is a file-private constant at `LiveModelLoader.swift:42`, applied by `MLXFoundationModelsSessionBackend`'s respond and stream paths (`:342`, `:414`) when a caller passes no `maxTokens`. The prose now says that.
    - **Wrong for the same reason, found by the sweep** — `CLIRunner.swift`'s import note said `MLXVLM` "is imported by Router's own `LiveModelLoader`". The import is file-scoped (`LiveModelLoader.swift:16`, marked load-bearing although the file names no `MLXVLM` symbol). The note now names the file.
    - **Correct, left alone** — `IntegrationGate.swift:462`/`:487` and `CLIRunner.swift:400` really do construct the struct; `Package.swift`'s five mentions all describe products the constructed struct needs. `Package.swift` was not edited, per the card.
    - **`plan.md` carries no `LiveModelLoader` mention at all** — checked by grep for the type, `usageTokenCounts`, `makeFork` and `MLXFoundationModelsSessionBackend`. Nothing to correct there.

    ## The refinement the review supplied is now in the prose, and the protocol confirms it

    Both doc comments now state the step they had left implicit: `tokensIn` is stamped as the delta of two *cumulative* snapshots, and it equals the turn's own whole render only because every fork on this path is a fresh session starting at zero. Independent confirmation from the protocol's own documentation — `LanguageModelSessionBackend.swift:200-202` declares `usageTokenCounts()` returning "The backend's cumulative `(input, output)` token counts so far". The suite doc's reference to the protocol (`LanguageModelSessionBackend.usageTokenCounts()`, for what Router calls through) is correct and stays; only the sentence naming the live conformer was wrong.

    ## No gated run

    This iteration changed doc comments only — no assertion, no executable line, no signature. `git diff` is 3 source files, all comment lines. A twenty-minute `MULTITOOL_INTEGRATION` run cannot grade a comment, so none was spent. The gated numbers already on this card still stand.
  timestamp: 2026-08-18T13:48:56.154691+00:00
- actor: claude-code
  id: 01m0aj7knm89w068t2t1ca5eaj
  text: |-
    Validator rules were read whole before the edits (54 rules, 7 validators: code-hygiene, code-security, completeness, duplication, reuse, swift, test-integrity). Recorded so the next agent does not re-read 10,777 lines for the same answer:

    - No rule in the set governs comment prose style, tone, hedging, dates, versions, or line-number references, and no rule constrains what a comment may claim about another type. The correction was permitted, not mandated by a rule; it is mandated by the review findings.
    - The only Swift doc-comment structure rule is `swift/doc-parameter-naming`. It binds a `- Parameter <name>:` key to the internal parameter name and leaves double-backtick DocC links on external argument labels. No `- Parameter` key was touched here.
    - Three mechanical traps checked against the three edited files, all clear: no `// swiftlint:disable:next` or `// periphery:ignore` marker sits near an inserted line; the type name is spelled exactly as declared (`MLXFoundationModelsSessionBackend`); no round-trip vocabulary was added to a one-direction test doc.
    - Worth knowing for the next review pass: `missing-docs-swift`, `magic-numbers-swift` and `function-length-swift` are file-scoped, so a changed file is re-read whole. Both test files hold no `public`/`open` declaration, so `missing-docs-swift` has nothing to report on them.

    ### implement — changed
    - evidence: 3 files — Tests/FoundationModelsMultitoolIntegrationTests/SelectionForkPerCallTests.swift, Tests/FoundationModelsMultitoolIntegrationTests/Support/IntegrationGate.swift, Sources/multitool-cli/CLIRunner.swift. Doc comments only: `git diff` touches no executable line, no assertion, no signature. All three review findings fixed, plus two more sites of the same cause the sweep found (`IntegrationGate.swift`'s `defaultMaxTokens` sentence, `CLIRunner.swift`'s `MLXVLM` import note). The card's own "Resolved" prose was corrected too, and the three findings are checked. `Package.swift` untouched. `swift test`: 359 tests/30 suites and 59 tests/11 suites, zero failures. The one `warning:` in the output is SwiftPM's "missing creator for mutated node" for the `mlx-swift_Cmlx.bundle` directory — it also prints on a no-op `swift build --build-tests` that compiles nothing, so it is a build-system message and not a compiler warning about this source.
    - no gated run: a doc comment cannot be graded by a twenty-minute `MULTITOOL_INTEGRATION` run. The gated numbers already on this card stand.
    - next: ready for `/review`
  timestamp: 2026-08-18T13:51:03.348222+00:00
position_column: doing
position_ordinal: '8380'
title: PrefixReuseTests pins nothing — its assertion is satisfied by model warm-up alone
---
`PrefixReuseTests` is named a pin and asserts one thing:

    Tests/FoundationModelsMultitoolIntegrationTests/PrefixReuseTests.swift:96
        secondElapsed <= firstElapsed

Two `searchTools` calls are timed, and the second must not be slower than the first.

## Why that measures nothing

The first call pays model warm-up that the second never pays. That alone satisfies the assertion, with zero prefix reuse anywhere in the stack. A run where the second call re-prefilled the entire selection prefix from scratch would still pass, provided warm-up cost more than the re-prefill saved.

Measured on 2026-08-16, both models pass and neither passes decisively:

    Muse-Glimmer-30B-mxfp4   first=7.75s  second=3.31s
    Qwen3.8-27B-mxfp4        first=5.81s  second=3.58s

A second call that genuinely skipped a prefill and one that merely followed a warmed model produce the same verdict here.

## Why this matters more than a weak test usually would

The suite is cited as evidence. `IntegrationGate.swift` records that the pin moved to Muse Glimmer *because* Qwen3.5/3.6's non-trimmable `MambaCache` "left `PrefixReuseTests` nothing to measure" — a model choice justified by a suite that cannot measure the thing. The comment has since been corrected to say so, but the suite is still there under a name that claims otherwise.

The rigorous instrument exists and is not ours: `mlx-swift-lm`'s `f85fc50` measures two-round reuse on real weights through `MLXLMCommon.ChatSession`, comparing rendered token counts and prefill time against a cold control. Its verdict on Qwen3.6 was NO on two independent counts — the second render was not a prefix extension of the first (4,703 of 4,705 tokens shared and still not an extension, because round 1 ends with a `<think>` priming block where round 2 writes the reply), and round 2 fed all 4,748 tokens, skipped none, and spent 11.59s on prefill against a cold control's 11.60s.

So the honest state is: **we have no evidence prefix reuse works on any model we ship**, and a suite whose name implies we do.

## What a fix has to decide

Either make it measure, or stop claiming it does. Both are legitimate; guessing between them is not.

- **Make it measure.** The selection tier's sessions are Router-vended and therefore recorded. `tokensIn` on the second call's `response` entry, against the first's, is the number that says whether a prefill was skipped — the same arithmetic that established ~10-14 tokens a second elsewhere in this target. That is a real assertion and it needs no new machinery.
- **Or rename and narrow it.** If the recorded entries cannot distinguish reuse either, say so in the suite, assert only what the timings can support, and delete the word "pin". A test that honestly measures "the second call is not slower" is fine; one that implies it measured reuse is not.

Do not delete the suite to make the problem go away — the `fork()`-per-call path it drives is real and worth exercising even if the reuse claim goes.

## Resolved: the second branch, on measured evidence

`tokensIn` cannot distinguish a skipped prefill from a full re-prefill, so the first branch is closed. Router stamps it as the delta of two cumulative `usage.input.totalTokenCount` snapshots (upstream `promptTokenCount` = `inputText.tokens.size`), and that delta is the turn's own whole render only because every fork on this path is a fresh session starting at zero. Either way the number counts the render whether or not a prefix was skipped. The one figure that would answer the question, `usage.input.cachedTokenCount`, is dropped by Router's live conformer, `MLXFoundationModelsSessionBackend.usageTokenCounts()` — the class declared in `LiveModelLoader.swift`, which is NOT the `LiveModelLoader` struct further down that same file. In the pinned `mlx-swift-lm` (`acc92059`) the FoundationModels executor carries no prompt cache at all, so `cachedTokenCount` is a hardcoded `0`. See the comment thread for the full trace and the gated numbers.

The suite is now `SelectionForkPerCallTests`. It asserts the cached-root, `fork()`-per-call contract off the recording, keeps the timing check stated as a timing check, and documents what it cannot see.

## Acceptance Criteria

- [x] The suite either asserts something only genuine prefix reuse can satisfy, or states plainly in its own documentation what it cannot see
- [x] The name and doc comment match what it actually establishes — no "pin" over a timing comparison that warm-up satisfies
- [x] Whatever it can no longer claim is removed from `IntegrationGate.swift`'s model-history prose, so no future model choice is justified by it
- [x] `mlx-swift-lm`'s `f85fc50` is named as the rigorous instrument, so the next reader knows where the real measurement lives

## Tests

- [x] Ungated `swift test` green — 359 tests/30 suites and 59 tests/11 suites
- [x] One gated run of the suite, with the numbers recorded on this card — including `tokensIn` for both calls if the new assertion uses them

## Review Findings (2026-08-18 08:41)

> Scope: `review sha HEAD~1..HEAD` (`2df6579`) — reviewed the diffs only — lines this change added or modified. The engine fleet ran 7 validator passes over 6 files and returned 0 findings. The items below come from the directed fact-check of the doc comments' claims about `FoundationModelsRouter` and `mlx-swift-lm` internals, checked against `.build/checkouts/`.

- [x] `Tests/FoundationModelsMultitoolIntegrationTests/Support/IntegrationGate.swift:340` `fact-check/doc-accuracy` — the prose attributes `usageTokenCounts()` to `LiveModelLoader`, but that method is a member of `MLXFoundationModelsSessionBackend` (`.build/checkouts/FoundationModelsRouter/Sources/FoundationModelsRouter/Resolution/LiveModelLoader.swift:237`, method at `:648`). `LiveModelLoader` is a separate `public struct` at `:759` and declares no `usageTokenCounts()`; only the file name is `LiveModelLoader.swift`. Name the owning type `MLXFoundationModelsSessionBackend.usageTokenCounts()`.
- [x] `Tests/FoundationModelsMultitoolIntegrationTests/SelectionForkPerCallTests.swift:53` `fact-check/doc-accuracy` — same wrong owning type: the suite doc says `LiveModelLoader.usageTokenCounts()` reads only the two `totalTokenCount`s. The reading is correct; the type is not. It is `MLXFoundationModelsSessionBackend.usageTokenCounts()`.
- [x] `Tests/FoundationModelsMultitoolIntegrationTests/SelectionForkPerCallTests.swift:68` `fact-check/doc-accuracy` — the suite doc says `LiveModelLoader.makeFork(tools:)` builds a brand-new `LanguageModelSession` seeded from the parent's transcript. The behaviour is correct; the owning type is not. `makeFork(tools:)` is declared on `MLXFoundationModelsSessionBackend` (`LiveModelLoader.swift:573`). Correct every site in the file, not only this line.

### Verified and holding — no finding

Checked against the pinned sources, so the next reader need not re-derive them:

- `tokensIn` does come from `usage.input.totalTokenCount`, and it is the whole rendered prompt of the turn, not a newly-prefilled count. Router stamps a delta of two cumulative snapshots (`RoutedSessionActorRecording.swift:54`, `:164`; `RoutedSessionActorTurnExecution.swift:495`), and on the fork-per-call path each fork is a fresh session starting at zero, so the delta equals that turn's own whole render. Upstream the number is `promptTokenCount` (`mlx-swift-lm` `MLXLanguageModel.swift:1793`, `:2003`).
- `usage.input.cachedTokenCount` is dropped: the method returns only the two totals, and `cachedTokenCount` appears in that file solely inside a doc comment.
- The pin really is `acc92059` (`Package.resolved`, branch `stable`), and its FoundationModels executor carries no prompt cache — no `ChatSession` and no `cache:` argument anywhere in `Libraries/MLXFoundationModels/`, generation running through cache-free `MLXLMCommon.generate` overloads. `cachedTokenCount: 0` is a literal at all five emission sites (`MLXLanguageModel.swift:1428`, `:1654`, `:1744`, `:1793`, `:2003`).
- `makeFork(tools:)` builds a new `LanguageModelSession` from the parent's transcript; no cache is carried (`LiveModelLoader.swift:573-581` into `:83-98`).
- `SelectionTier.search` does `cachedRootSession().fork()` then `child.respond(to:generating:)` (`FoundationModelsRanker/.../SelectionTier.swift:136`, `:142`, `:143`).
- `TranscriptEvent` meters `tokensIn`, `tokensOut`, `ms` and nothing else — no skipped-token count, no cache-hit count, no prefill time.
- No surviving prose credits the deleted suite or justifies the Muse Glimmer pin with it. The three remaining `PrefixReuse` mentions (`SelectionForkPerCallTests.swift:31`, `IntegrationGate.swift:241`, `:323`) each name the old suite only to retract what it claimed.
- `plan.md`, `ScenarioRunner.swift`, `NativeTranscript.swift` and `SelectionGrammar.swift` changed comment and prose lines only. No executable behaviour moved in any of the four.
- The four new assertions are not vacuous, and they assert what their messages claim: each reads a distinct projection of the recording (`generations.count`, `childSessionIds.count`, `unforkedGenerationCount`, `rootSessionIds.count`), and the root-count assertion is the one that would catch a dropped-and-rebuilt cached root.

Not checkable from this tree, and correctly asserted on by nothing: the numeric figures quoted from `mlx-swift-lm`'s `f85fc50` (that commit is on another branch, not the pinned `acc92059`), the `tokensIn=1144` anomaly, and the recorded wall-clock timings.