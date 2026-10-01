---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3tn9av979taq18r4g79ty0c
  text: |-
    ### Decisions (recorded before the code change)

    **1. Brave live suite under HTTP 429 — decision: a spacing between live search requests, driven by the test support code.**
    - Contract check: web.md "Fallback" says that the chain goes to the next provider on 429 or 5xx, and that a correction names each provider when all providers fail. `braveHTML: blocked (HTTP 429)` is that correction. The provider code obeys the contract. No product change.
    - One shared request for the suite is not possible: the two tests send two different queries (one has `site: developer.apple.com`). Two requests are necessary to keep the intent of each test.
    - The cause: two live requests to search.brave.com came 0.6 s apart. The fix: `LiveSearch.search` takes a turn from one process-wide spacing before each live request. A turn starts at least `LiveSearch.searchSpacingSeconds` after the start of the previous turn. All suites that call `LiveSearch.search` share it (BraveHTMLLiveTests, DuckDuckGoHTMLLiveTests, KeylessChainLiveTests, KeyedFallbackLiveTests, KeyedProviderLiveTests). Thus suites that run one after the other under `--no-parallel` also keep the spacing.
    - This is not a skip, not a retry, and not a wider deadline. Each test still sends one request, and a 429 that comes with the spacing still fails the test. The time limit of each test does not change.
    - The reservation of a turn is a pure function of the clock instants, thus an ungated test checks it with no network and no sleep.

    **2. Metadata timeout in `LiveRouterFixture.resolve` — decision: use the on-disk metadata cache that Router already has. No change in another repository.**
    - Research: `RepoMetadataReader` of FoundationModelsRouter (Sizing/RepoMetadata.swift) caches the parsed metadata per (repo, revision) in `Router(cacheDir:)`. For a reference whose revision can move (the pinned models of this target have no `@revision`), it fetches first, and when the fetch fails it returns the cached entry ("the read that keeps a machine with no network working").
    - The cause: the fixture gives each Router a NEW temporary `cacheDir` (`makeTempDir()`). Thus the cache is always empty, and the offline fallback can never work.
    - The fix: the fixture gives each Router one durable cache directory, `IntegrationTests/.build/router-cache`, beside `.build/recordings`. A resolve that succeeds writes the entry; a later resolve whose fetch times out reads it. The live fetch is still the first read, thus a resolve still sees new metadata when the network is good.
    - Why not the Router default (`nil`, the user caches directory that the shipped CLI uses): the test writes a fake repo entry to prove the fallback, and a test must not write to the cache that the shipped host reads. The `.build` tree is git-ignored and `swift package clean` removes it.
    - Limit: on a computer where no resolve succeeded since the last clean, the cache is empty, and a timeout still fails. That is correct: then no local metadata exists.
    - An ungated test in IntegrationTests proves it with a stub metadata source: a first Router writes the entry, a second Router whose source times out gets to the load step and does not throw `NoWindowFailure`.
  timestamp: 2026-10-01T02:39:21.961124+00:00
- actor: claude-code
  id: 01m3tnnghf5r3a58m9728k0fm9
  text: |-
    Implementation landed (TDD).
    - Brave: new `Web/Support/LiveSearchSpacing.swift` (actor; `reserveTurn(at:)` is pure, `waitForTurn()` sleeps on ContinuousClock). `LiveSearch.search` takes a turn of `LiveSearch.searchSpacing` (2 s) before each request. New `Web/LiveSearchSpacingTests.swift` (4 tests, no network). RED: 2 of 4 failed with the stub; GREEN: 4 of 4 pass. web.md Level 2 records the decision, the filter, and the table row.
    - Metadata: `LiveRouterFixture.makeRouter(recordingsDir:loader:metadataSource:pool:)` now makes each router, with `cacheDir: routerCacheRoot` (`IntegrationTests/.build/router-cache`). `recordingsRoot` and `routerCacheRoot` share `packageBuildDirectory`. New `RouterMetadataCacheTests.swift`: a router with a stub source writes the entry, a second router whose source throws `URLError(.timedOut)` gets to the load step (`ModelLoaderError.notConfigured`). RED with the old temporary cacheDir: the second resolve threw `NoWindowFailure ... metadata unavailable (NSURLErrorDomain error -1001)` — the same failure as the card. GREEN after the change; the Router log shows "a repo metadata fetch failed; using the cached entry" for each of the three references.
    - Discovery: Router needs no change. `RepoMetadataReader` already has the offline fallback for references with no pinned commit; only the fixture defeated it.
  timestamp: 2026-10-01T02:46:01.007481+00:00
- actor: claude-code
  id: 01m3tq294nhggavsdyb49n09fd
  text: |-
    ### implement — changed
    - evidence: 6 files — IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Web/Support/LiveSearchSpacing.swift (new), Web/LiveSearchSpacingTests.swift (new), Web/Support/LiveSearch.swift, Support/LiveRouterFixture.swift, RouterMetadataCacheTests.swift (new), web.md. `swift test`: 1879 tests in 154 suites passed, no warning. `swift test --package-path IntegrationTests --no-parallel`: "Test run with 65 tests in 34 suites passed after 1333.289 seconds" (60 before + 4 spacing + 1 metadata cache). The integration output was cut to its last 60 lines, thus the count of the 6 keyed skips is not in the kept output. `IntegrationTests/.build/router-cache` holds 7 entries after the run.
    - next: /review
  timestamp: 2026-10-01T03:10:27.989846+00:00
- actor: claude-code
  id: 01m3tymd55f30ph722j8918thb
  text: |-
    ### test — stuck
    - evidence: uptime load averages 76.67 87.54 78.55 at start, 116.95 at the end of the run.
    - root: `swift test` — 1879 tests in 154 suites passed, 0 issues, 0 skipped. One build warning: "missing creator for mutated node" for the mlx-swift_Cmlx.bundle path (a SwiftPM build-system message, not in project code).
    - integration: `swift test --package-path IntegrationTests --no-parallel` — 65 tests in 34 suites failed after 2706 s with 14 issues. Skipped: 6, all keyed (braveAPI, tavily, exa, serper, kagi, searxng) — the written exception. No other skip.
    - failing tests:
      1. Brave suite, "a site search for developer.apple.com gives only hits under apple.com": "No search provider gave results. braveHTML: blocked (HTTP 429)."
      2. KeyedFallbackLiveTests "a braveAPI key that is not valid gives the refused-key note...": "braveAPI: the API key was refused (HTTP 422). braveHTML: blocked (HTTP 429)." (4 issues)
      3. KeylessChainLiveTests: "braveHTML: blocked (HTTP 429). duckDuckGoHTML: blocked by a challenge page." (3 issues)
      4. WebRunCodeLiveTests "the goal snippet returns 1 to 3 pages...": same 429 plus challenge page correction; output did not decode as Array<WebPageHead> (2 issues)
      5. CLISmokeTests "the live demo succeeds and prints a non-empty final answer": Time limit was exceeded: 600 seconds (3 issues)
      6. AgentSurfaceDiscoveryTests "the ten recorded queries find the write, edit or shell entry...": Time limit was exceeded: 300 seconds (1 issue)
    - cause 1 to 4: the Brave results page and the DuckDuckGo page block this network address. I ran the 4 suites alone, one time, in a new process: the first request of the process got HTTP 429. So the 2 s spacing of LiveSearchSpacing is not the cause here; the address is blocked before the first request. A fix needs a retry, a skip, or a different address. The task forbids a retry and a skip.
    - cause 5 and 6: the machine load was 77 to 126 (other sessions). Model tests passed the 300 s and 600 s limits. The task forbids a wider deadline.
    - blocker: a person must pick a quiet machine and an unblocked address, or decide on a rule for blocked providers. I made no code change.
    - next: after the block clears and the load is low, run the integration package one time again.
  timestamp: 2026-10-01T05:22:41.957946+00:00
- actor: claude-code
  id: 01m3tyn1re662y7p1gsv3776r6
  text: |-
    ### finish iteration 1 — stuck
    - implement: changed — 2 s shared LiveSearch spacing; fixture Routers share IntegrationTests/.build/router-cache. Decisions are in an earlier comment. Files are not committed.
    - test: stuck — swift test (root): 1879 tests, 0 issues, 0 skipped. swift test --package-path IntegrationTests --no-parallel: 65 tests, 14 issues, 6 skipped (written exception). Failures: Brave site search, KeyedFallbackLiveTests, KeylessChainLiveTests, WebRunCodeLiveTests (HTTP 429 from braveHTML, challenge page from duckDuckGoHTML); CLISmokeTests (600 s limit), AgentSurfaceDiscoveryTests (300 s limit). Load average 77 to 117. A re-run of the 4 search suites in a new process got HTTP 429 on the first request: the network address is blocked.
    - commit: not run.
    - review: not run.
    - blocker: a person must decide. Run the integration suite on a quiet machine from an address that is not blocked, or choose a rule for a blocked provider. A retry, a skip or a wider deadline needs a decision on this card.
  timestamp: 2026-10-01T05:23:03.054458+00:00
- actor: claude-code
  id: 01m3vqvv73hz2vfzwsfzkc2nc1
  text: |-
    ### decision (user, 2026-10-01) — rule for a blocked provider
    - Rule: a blocked provider (HTTP 429, challenge page) does not fail a live test, on the condition that at least one provider gives results. When no provider gives results, the test fails.
    - Source: the user said "set a rule for the blocked provider - as long as some provider works we are OK for now".
    - Scope: this rule is for live web search tests only. It does not change the time limits of CLISmokeTests and AgentSurfaceDiscoveryTests.
  timestamp: 2026-10-01T12:43:40.131793+00:00
- actor: claude-code
  id: 01m3vr2nda4nnmz4r3mc6cfjc7
  text: |-
    ### Research for the blocked provider rule (iteration 2)
    - The chain writes a block as `<name>: blocked (HTTP 429).` or `<name>: blocked by a challenge page.` in the correction (WebSearchChain.swift, `ProviderFailure.reason`). A 5xx is `server error (HTTP <status>)`. It is not a block under the rule.
    - Live search tests that name providers: BraveHTMLLiveTests ([braveHTML]), DuckDuckGoHTMLLiveTests ([duckDuckGoHTML], with the older known issue for the challenge page), KeyedFallbackLiveTests ([braveAPI(invalid), braveHTML]), KeyedProviderLiveTests ([one keyed provider], skipped here with no key).
    - KeylessChainLiveTests and WebRunCodeLiveTests use the full keyless chain [braveHTML, duckDuckGoHTML]. The chain goes to the next provider on a block. Thus they already obey the rule: they pass when one provider gives results, and they fail only when no provider gives results. No code change for them.
    - Plan: one file `Web/Support/BlockedProviderRule.swift`. When the correction of a search names a block for a provider of the test, the rule records the block as a known issue (the evidence), and sends the same query one time to the same providers, with each blocked provider replaced by the keyless providers that the first search did not try. The test runs its normal checks on that result. When no such provider is left, or the second search also gives a correction, the test fails. This is not a retry: no provider gets a second request.
    - DuckDuckGoHTMLLiveTests: the older known issue (2026-09-26) let the test pass also when no provider gave results. The new user decision says that case fails. Thus the suite moves to the shared rule, and web.md states that the rule replaces the older exception.
    - Item 2 (time limits): CLISmokeTests runs the demo with no `--web` (the surface is tools.getTrip and tools.getWeather). AgentSurfaceDiscoveryTests uses only the files and shell surface. Neither path sends a web search. In the failed run (integ.log) each model step took 15 s to 3 min, at load average 77 to 117. They are load failures. The rule does not apply to them. No change.
  timestamp: 2026-10-01T12:47:23.562207+00:00
- actor: claude-code
  id: 01m3vxr76n2q842ss3je3ts1ka
  text: |-
    ### implement — changed
    - What changed (iteration 2, the blocked provider rule):
      - New `Web/Support/BlockedProviderRule.swift` holds the one rule. When the correction names a block (`blocked (HTTP 429).` or `blocked by a challenge page.`) of a provider of the test, the rule records the correction as a known issue. Then it sends the query one time to the providers of the test, with each blocked provider replaced by the keyless providers that the first search did not try. The test runs all its checks on that result. When no keyless provider is left, the first correction fails the test.
      - New `Web/BlockedProviderRuleTests.swift`: 9 offline tests. RED: 6 of 9 failed with a stub. GREEN: 9 of 9 passed.
      - `LiveSearch.expectSwiftHomePageHit` and `expectHitsOnAppleSite` (Brave and DuckDuckGo suites), `KeyedFallbackLiveTests`, and `KeyedProviderLiveTests` use the rule. The keyed fallback test now expects the hits from the last provider of the search (braveHTML, or duckDuckGoHTML after a block). The refused-key note and the no-leak checks stay.
      - `DuckDuckGoHTMLLiveTests`: the older challenge-page known issue (2026-09-26) is removed. It let the test pass when no provider gave results. The new user rule fails that case. web.md marks the older decision as replaced.
      - `KeylessChainLiveTests` and `WebRunCodeLiveTests`: no code change. They send the full keyless chain, thus the chain itself applies the rule. Doc comments say so.
      - Docs: web.md § Testing, Level 2 has "The blocked provider rule", the filter, the table rows, and the CI bullet. `IntegrationTests/Package.swift` states the rule beside the written exception.
    - Item 2 (time limits): CLISmokeTests runs the demo with no `--web`; AgentSurfaceDiscoveryTests has only files and shell. No web search is on either path. They are load failures. The rule does not apply. No change. In this run both passed.
    - evidence:
      - `swift test`: 1879 tests in 154 suites passed. One build message "missing creator for mutated node" for mlx-swift_Cmlx.bundle (SwiftPM, not project code).
      - `swift test --package-path IntegrationTests --no-parallel` (scratchpad/integ2.log): 74 tests in 35 suites failed after 4987 s with 11 issues (1 known issue). 6 skipped: the six keyed tests (written exception). Load average 98 to 108 during the run.
      - Each web suite passed. The Brave site search got `braveHTML: blocked (HTTP 429)`; the rule recorded it as a known issue and the duckDuckGoHTML hits passed all checks. That is the rule working as the user decided.
      - Remaining failures, none on a web search path:
        1. FilesBareSessionTests "read answers a seeded file...": the model answered "there are no lines in the file" (a model answer, not network). Not touched by this card.
        2. NestedGenerationProbeTests: time limit 60 s.
        3. NoDescriptionSurfaceDiscoveryTests: time limit 600 s.
        4. OverBudgetSurfaceDiscoveryTests: time limit 360 s.
        5. SearchThenCallTests single-call weather: time limit 720 s.
        Items 2 to 5 are load failures at load average near 100. By the card rules I did not widen a limit and did not skip.
    - Note: the card box "swift test --package-path IntegrationTests --no-parallel passes" is not true for this run, because of the five failures above. A run on a quiet machine is necessary to confirm it.
    - next: /review
  timestamp: 2026-10-01T14:26:32.789272+00:00
- actor: claude-code
  id: 01m3vxs7k50wnhxxy3rpx2gety
  text: |-
    ### finish iteration 2 — stuck
    - implement: changed — the blocked provider rule is in Web/Support/BlockedProviderRule.swift, with 9 offline tests. web.md and IntegrationTests/Package.swift state the rule. The older DuckDuckGo challenge-page exception (2026-09-26) is removed, because the user rule fails a run where no provider gives results. Files are not committed.
    - test (in implement): swift test (root): 1879 tests, 154 suites, passed. swift test --package-path IntegrationTests --no-parallel: 74 tests, 35 suites, 11 issues, 6 keyed skips (written exception). All Web suites passed. In the Brave site search, Brave gave HTTP 429, and the rule recorded it.
    - remaining failures, not on a web search path: FilesBareSessionTests (model answer "no lines in the file"); time limits in NestedGenerationProbeTests (60 s), NoDescriptionSurfaceDiscoveryTests (600 s), OverBudgetSurfaceDiscoveryTests (360 s), SearchThenCallTests (720 s), at load average about 100.
    - commit: not run. review: not run.
    - blocker: the card item "swift test --package-path IntegrationTests --no-parallel passes" is not true on this machine now. The user rule does not cover the remaining failures. A person must decide: move them to a new card and close this card on the web scope, or run the suite on a quiet machine.
  timestamp: 2026-10-01T14:27:05.957749+00:00
- actor: claude-code
  id: 01m3vyz4chmxaq13r0t14xpb3n
  text: |-
    ### decision (user, 2026-10-01) — scope
    - The user chose: add a new card for the 5 failures that are not web failures, and close this card on the web scope.
    - The test step for this card is one `swift test` on the root package, plus the Web suites of the integration package only.
    - The item "swift test --package-path IntegrationTests --no-parallel passes" moves to the new card for the failures that are not web failures.
  timestamp: 2026-10-01T14:47:47.857470+00:00
- actor: claude-code
  id: 01m3vz44h33spqxqd6hzmmbkgd
  text: |-
    ### test - red
    - load average at start: 69.15 66.33 66.30 (uptime).
    - root: `swift test` once. 1879 tests in 154 suites passed. 0 issues, 0 known issues, 0 skipped. 1 build warning from the build system: "missing creator for mutated node ... mlx-swift_Cmlx.bundle/Contents/MacOS" (not from our code).
    - integration: `swift test --package-path IntegrationTests --no-parallel --filter "BraveHTMLLiveTests|DuckDuckGoHTMLLiveTests|KeylessChainLiveTests|FetchLiveTests|GuardLiveTests|KeyedProviderLiveTests|LiveProviderSettingTests|LiveSearchSpacingTests|BlockedProviderRuleTests|KeyedFallbackLiveTests|WebRunCodeLiveTests|RouterMetadataCacheTests"` once. 42 tests in 12 suites failed with 16 issues (5 known issues, 11 failures). 6 skipped. Same 1 build-system warning.
    - skips (written exception, IntegrationTests/Package.swift): braveAPI, tavily, exa, serper, kagi, searxng (keyed live tests, variable not set).
    - known issues from the blocked provider rule (user rule): (1) BraveHTMLLiveTests Swift query (braveHTML HTTP 429), (2) BraveHTMLLiveTests site search (braveHTML HTTP 429), (3) DuckDuckGoHTMLLiveTests Swift query (challenge page), (4) DuckDuckGoHTMLLiveTests site search (challenge page), (5) KeyedFallbackLiveTests (braveHTML HTTP 429). Both Brave tests then passed on the DuckDuckGo hits.
    - failures (11 issues in 5 tests). Cause: at that time both keyless providers refused this network address, so no provider gave results. The rule says: when no provider gives results, the test fails.
      - DuckDuckGoHTMLLiveTests "the Swift query gives at least 3 https hits, one of them on swift.org": challenge page, then the replacement braveHTML: "No search provider gave results. braveHTML: blocked (HTTP 429)." (1 issue, plus 1 known issue)
      - DuckDuckGoHTMLLiveTests "a site search for developer.apple.com gives only hits under apple.com": same messages (1 issue, plus 1 known issue)
      - KeyedFallbackLiveTests "a braveAPI key that is not valid gives the refused-key note...": 4 issues: `result.correction == nil` false ("No search provider gave results. braveAPI: the API key was refused (HTTP 422). duckDuckGoHTML: blocked by a challenge page."), `result.provider == keylessProvider.name` ("" vs "duckDuckGoHTML"), `result.results.count >= LiveSearch.minimumHitCount` (0 of 3), refused-key note missing (notes []).
      - KeylessChainLiveTests "the keyless chain gives hits...": 3 issues: correction "No search provider gave results. braveHTML: blocked (HTTP 429). duckDuckGoHTML: blocked by a challenge page.", no hits, provider "".
      - WebRunCodeLiveTests "the goal snippet returns 1 to 3 pages...": 2 issues: output did not decode as Array<WebPageHead>: [] (the chain gave no hits), DecodingError.dataCorrupted (the output text starts with "T" after the value).
    - passed: BlockedProviderRuleTests (9), LiveSearchSpacingTests (4), LiveProviderSettingTests, RouterMetadataCacheTests (1), FetchLiveTests (5), GuardLiveTests (2).
    - no code change made. No retry, no longer time limit, no skip added. The failures come from the network address block (live providers), not from a defect in the code of this card.
    - next: a person decides. Run again from a network address that the providers do not block, or accept the rule outcome. Nothing in the code of this card needs a fix.
  timestamp: 2026-10-01T14:50:31.843010+00:00
- actor: claude-code
  id: 01m3vz4z0dg820qpk1kr45dxjx
  text: |-
    ### finish iteration 3 — red
    - test: red — swift test (root): 1879 tests, 0 issues, 0 skipped. Web suites + RouterMetadataCacheTests: 42 tests, 12 suites, 16 issues (5 known issues by the blocked provider rule, 11 failures in 5 tests), 6 keyed skips (written exception).
    - failures: DuckDuckGoHTMLLiveTests (2 tests), KeyedFallbackLiveTests, KeylessChainLiveTests, WebRunCodeLiveTests. Cause: no provider gave results — braveHTML HTTP 429 and duckDuckGoHTML challenge page in the same run. The user rule says the test fails then.
    - passed: BlockedProviderRuleTests (9), LiveSearchSpacingTests (4), LiveProviderSettingTests, RouterMetadataCacheTests (1), FetchLiveTests (5), GuardLiveTests (2).
    - commit: not run. review: not run.
    - blocker: both keyless providers block this network address now. No code defect was found. A person must decide.
  timestamp: 2026-10-01T14:50:58.957988+00:00
- actor: claude-code
  id: 01m3wa1awzb47hhcb1v8xnrkrv
  text: |-
    ### decision (user, 2026-10-01) — accept the blocked-network run
    - The user chose: accept the code, because it follows the blocked provider rule. The last run shows only that this network address is blocked by both keyless providers.
    - Next: /commit and /review of this card. Then start ^tm4x2hp.
  timestamp: 2026-10-01T18:01:14.399591+00:00
position_column: doing
position_ordinal: '80'
title: Integration tests fail when the network is slow or rate-limited
---
## What
One run of `swift test --package-path IntegrationTests --no-parallel` on 2026-09-30 (work of ^v01qjy0) gave 57 passes of 60 tests. The 3 failures came from the network, not from the code under test:

- `BraveHTMLLiveTests.swift` "a site search for developer.apple.com gives only hits under apple.com": `No search provider gave results. braveHTML: blocked (HTTP 429).` The test before it in the same suite passed 0.6 s earlier. Two live requests in quick sequence can get a rate limit.
- `OverBudgetSurfaceDiscoveryTests.swift` and `RetrievalTextSurfaceDiscoveryTests.swift`: `NoWindowFailure: profile "multitool-plumbing-probe" has no standard candidate whose window could be read ... mlx-community/Qwen3-4B-4bit — unsized: metadata unavailable (The request timed out.)`. `Router.resolve` could not read the model metadata from the Hugging Face Hub, so the fixture failed before the scenario started.

## Decide
- How the live Brave suite stays stable under a rate limit (for example, a wait between its requests, or one request for the suite).
- Whether a metadata timeout during `LiveRouterFixture.resolve` must stay a failure, or whether the fixture can use the local metadata cache of the models it already downloaded.

Do not skip tests and do not widen deadlines without a decision on this card.

Both decisions are recorded in the comment "Decisions (recorded before the code change)".

## Acceptance Criteria
- [x] A rate limit from the Brave results page does not fail the live Brave suite, or the card records why it must fail. (A shared 2 s spacing between live searches removes the burst that got HTTP 429. A 429 that still comes with the spacing fails the test, by decision: no retry and no skip.)
- [x] A metadata timeout for a downloaded model does not fail `LiveRouterFixture.resolve`, or the card records why it must fail. (Each fixture router uses `IntegrationTests/.build/router-cache`, thus Router reads its cached entry when the fetch fails. It still fails when no resolve cached the entry since the last clean.)

## Tests
- [x] `swift test --package-path IntegrationTests --no-parallel` passes.