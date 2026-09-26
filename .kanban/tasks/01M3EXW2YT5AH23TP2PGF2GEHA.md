---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3ey3sgs05vyn0m9vbb0p2eb
  text: |-
    ### implement — research
    - The 8 files of `WebIntegrationTests/Tests/FoundationModelsMultitoolWebIntegrationTests/` import only `Testing`, `Foundation`, `FoundationModelsMultitool` and `MultitoolTestSupport`. No file imports SwiftSoup, and no file calls `print`. The target needs only one new product: `MultitoolTestSupport`.
    - `WebIntegrationTests/Package.swift` declares SwiftSoup only so that SwiftPM resolves the same requirement. SwiftPM resolves SwiftSoup through `..` without it, and `IntegrationTests/Package.swift` builds today with no SwiftSoup line. An unused package dependency gives a SwiftPM warning, thus this card does not add it.
    - No name conflict: `IntegrationTests` has no `LiveSearch` or `LiveFetch`.
    - The rule text is in `IntegrationTests/Package.swift`, `WebResearchScenarioTests.swift` (doc comment), `web.md` (Level 2 "Why a new package", Level 3). `plan.md` already states the correct rule ("nothing reads the environment to decide which suite runs"). `ci.yml` states "No input below sets an environment variable to select a suite", which agrees with the new rule.
    - Stale `WebIntegrationTests` names: root `Package.swift` (2 comments), `MultitoolTestSupport/WebVerbCall.swift`, `RunOutput.swift`, `WebPageHead.swift`, `Tests/.../Support/WebVerbFixture.swift`, `web.md` (file list, Level 2, CI). `README.md` and `docs/SECURITY.md` do not name it. `WebDocumentationTests` checks only README and SECURITY sections, thus no checked phrase changes.
    - Discovery for the web.yml card (^ ... 01M3A34A9941ZGD8FXMTHVF1SZ): `ci.yml` runs the whole `IntegrationTests` package on `push` and `pull_request`. After this move, that job also runs `DuckDuckGoHTMLLiveTests`. The challenge page is a known issue there, thus it does not fail the job, but the "schedule only" decision needs a `--skip` in that job or a change in the shared workflow.
  timestamp: 2026-09-26T13:22:44.377612+00:00
- actor: claude-code
  id: 01m3eybx06v30r08yjzfase4m4
  text: |-
    ### implement — notes
    - The 8 files moved with `git mv` into `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Web/` (6 suites) and `Web/Support/` (`LiveSearch.swift`, `LiveFetch.swift`). The only content change in a moved file: one doc line of `LiveSearch.swift` ("of the package" is now "of the `Web/` suites"). The DuckDuckGo `withKnownIssue` rule has no change. No moved file calls `print`, thus no `reportTraceLine` change was necessary.
    - `IntegrationTests/Package.swift`: new product `MultitoolTestSupport` with a comment; new "environment rule" paragraph; the manifest summary, the `--no-parallel` paragraph and the target comment now name the model-free `Web/` suites. SwiftSoup is not added: no moved file imports it, SwiftPM resolves it through `..`, and a declared package that no target uses gives a SwiftPM warning.
    - `WebIntegrationTests/` is deleted (its `Package.swift` with `git rm`, then the untracked `.build/` and `Package.resolved`).
    - Stale names fixed: root `Package.swift` (3 comments), `MultitoolTestSupport/WebVerbCall.swift`, `RunOutput.swift`, `WebPageHead.swift`, `Tests/.../Support/WebVerbFixture.swift`, `WebResearchScenarioTests.swift` (rule text). `README.md` and `docs/SECURITY.md` did not name the package; `WebDocumentationTests` checks no changed phrase.
    - `web.md`: file list, Testing intro, Level 2 (location, the environment rule, the filtered command), the `KeyedProviderLiveTests` row (`.enabled(if:)` removed: the test always runs and fails with the variable name when the key is missing, to agree with the new rule), Level 3 bullet, CI bullet (the `ci.yml` unit job already builds `IntegrationTests`). The `KeyedFallbackLiveTests` 401/403 text and the `ExpectedProvidersTests` row are left for ^34a9941 ... the keyed card 01M3A33SMXZ93N45S1SWCZ6NMR, which owns those decisions.
    - For review: `WebResearchScenarioTests.makeShortTimeoutConfiguration()` (15 s / 30 s) and `LiveSearch.makeShortTimeoutConfiguration()` (10 s / 15 s) are now in one target. Both existed before this card; the timeouts differ on purpose.
    - For review: this change renames 8 files. A diff-scoped review can skip rules on renamed files; review the `Web/` folder file-scoped.
    - Root `Package.swift` is 637 lines before and after this card (comment edits only).
    - Posted a note on the web.yml card 01M3A34A9941ZGD8FXMTHVF1SZ: the `ci.yml` integration job now also runs `DuckDuckGoHTMLLiveTests` on push and pull request.
  timestamp: 2026-09-26T13:27:10.086169+00:00
- actor: claude-code
  id: 01m3eyc3ngfxkpvww97t359nsj
  text: |-
    ### implement — changed
    - evidence: 17 paths — 8 renames into IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Web/ (BraveHTMLLiveTests, DuckDuckGoHTMLLiveTests, FetchLiveTests, GuardLiveTests, KeylessChainLiveTests, WebRunCodeLiveTests, Support/LiveSearch.swift, Support/LiveFetch.swift); deleted WebIntegrationTests/Package.swift; edited IntegrationTests/Package.swift, IntegrationTests/.../WebResearchScenarioTests.swift, Package.swift, Tests/Support/MultitoolTestSupport/{WebVerbCall,RunOutput,WebPageHead}.swift, Tests/FoundationModelsMultitoolTests/Support/WebVerbFixture.swift, web.md. `swift build --build-tests --package-path IntegrationTests`: Build complete. Filtered live run: 13 tests in 6 suites passed, 2 known issues (DuckDuckGo challenge page). Root `swift test`: 1790 tests in 143 suites passed. The only warning is the vendored mlx-swift "missing creator for mutated node" build warning, outside this repository. `rg -n "WebIntegrationTests" --glob '!.kanban/**'`: no match.
    - next: /review (review the renamed `Web/` files file-scoped).
  timestamp: 2026-09-26T13:27:16.912837+00:00
- actor: claude-code
  id: 01m3eyhcnncm5vh0xykbnb9dch
  text: |-
    ### test — green
    - evidence: root `swift test` — 1790 tests, 143 suites, 0 fail, 0 warning, 0 skip.
    - evidence: `swift build --build-tests --package-path IntegrationTests` — build OK. One warning. The warning comes from the vendored mlx-swift bundle. It is outside this repo.
    - evidence: `swift test --package-path IntegrationTests --no-parallel --filter "BraveHTMLLiveTests|DuckDuckGoHTMLLiveTests|KeylessChainLiveTests|FetchLiveTests|GuardLiveTests|WebRunCodeLiveTests"` — 13 tests, 6 suites, 0 fail. 2 known issues. Both are the DuckDuckGo challenge page. The user decision of 2026-09-26 says this is not a failure.
    - next: none. All checks are clean.
  timestamp: 2026-09-26T13:30:09.973987+00:00
- actor: claude-code
  id: 01m3ezmgs6xmm1953rgmxv1fz1
  text: |-
    ### review — findings
    - evidence: `review sha HEAD~1..HEAD` (commit 748e20b) gave 0 findings. The diff review did not read the 8 renamed files, so a `review file` ran on each new `Web/` path. 6 files gave 0 findings. 2 files gave 1 finding each: `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Web/DuckDuckGoHTMLLiveTests.swift:60` (`swift/idioms`), `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Web/Support/LiveSearch.swift:84` (`reuse/reuse`). Total: 2 findings, 2 confirmed, 0 refuted.
    - next: Correct the 2 open items in the `## Review Findings` sections. Then run `/review` on this task again. The task stays in `review`.
  timestamp: 2026-09-26T13:49:21.062832+00:00
- actor: claude-code
  id: 01m3ezn5w2gvwj8sv2jbcmdzkh
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 8 renames, package removed, rule text and web.md updated
    - test: green — root 1790 passed; live web suites 13 passed, 2 known issues (DuckDuckGo challenge page)
    - commit: 748e20b
    - review: findings — IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Web/DuckDuckGoHTMLLiveTests.swift:60, IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Web/Support/LiveSearch.swift:84
  timestamp: 2026-09-26T13:49:42.658296+00:00
- actor: claude-code
  id: 01m3f019tn07tgegmszms6aqqq
  text: |-
    ### implement — notes (review findings, round 2)
    - Finding `swift/idioms` (DuckDuckGoHTMLLiveTests.swift): the literal change `() async throws` does not compile. A Swift function type must have a `->` clause. Thus the fix removes the cause and not only the text: no `Web/` file now declares a closure parameter of a `Void` type. `DuckDuckGoHTMLLiveTests` calls `withKnownIssue(... isIntermittent: true) { ... } matching: { Self.isChallengePage($0) }` directly in each test; the new `isChallengePage(_:)` holds the exact-comment match. The DuckDuckGo `withKnownIssue` rule has no change (user decision 2026-09-26). The same cause was in `LiveSearch.expectHits(of:sourceLocation:_:)` (`(SearchResult) throws -> Void`); it is now `LiveSearch.hasHits(_:sourceLocation:) -> Bool`, and each caller does `guard hasHits(...) else { return }`. `rg` finds no `-> Void` and no `-> ()` in `Web/`.
    - Finding `reuse/reuse` (LiveSearch.swift): new `ShortTimeoutSession.makeConfiguration(requestTimeout:resourceTimeout:)` in `Tests/Support/MultitoolTestSupport/ShortTimeoutSession.swift`. The timeouts are parameters, because the two callers use different values on purpose (Web/ 10 s / 15 s, WebResearchScenarioTests 15 s / 30 s). `WebResearchScenarioTests` lost its private copy and now imports `MultitoolTestSupport`. `LiveSearch.makeShortTimeoutConfiguration()` is now `LiveSearch.makeSessionConfiguration()`, a one-line call of the shared function with the Web/ timeouts; `LiveFetch` and `WebRunCodeLiveTests` use it.
    - TDD: new unit suite `Tests/FoundationModelsMultitoolTests/ShortTimeoutSessionTests.swift` (3 tests). RED: it did not compile ("cannot find 'ShortTimeoutSession' in scope"). GREEN after the new file.
    - The root `Package.swift` doc comment of `multitoolTestSupportTargetName` now names `ShortTimeoutSession` in its list of helpers.
    - Live run: the challenge page came on both DuckDuckGo tests, and `isChallengePage` matched it as a known issue. Thus the new matcher path ran.
  timestamp: 2026-09-26T13:56:19.925202+00:00
- actor: claude-code
  id: 01m3f01dndhm4t3amzx9agqc94
  text: |-
    ### implement — changed
    - evidence: 9 files — IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Web/DuckDuckGoHTMLLiveTests.swift, Web/Support/LiveSearch.swift, Web/Support/LiveFetch.swift, Web/WebRunCodeLiveTests.swift, IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/WebResearchScenarioTests.swift, Tests/Support/MultitoolTestSupport/ShortTimeoutSession.swift (new), Tests/FoundationModelsMultitoolTests/ShortTimeoutSessionTests.swift (new), Package.swift (comment), task card (2 findings checked). `swift build --build-tests --package-path IntegrationTests`: Build complete. Filtered live run: 13 tests in 6 suites passed, 2 known issues (DuckDuckGo challenge page). Root `swift test`: 1793 tests in 144 suites passed. The only warning is the vendored mlx-swift "missing creator for mutated node" build warning, outside this repository.
    - next: /test, then /review (file-scoped on the `Web/` files and the new `MultitoolTestSupport` file).
  timestamp: 2026-09-26T13:56:23.853913+00:00
- actor: claude-code
  id: 01m3f0gqwj6hsyz79430a4vptw
  text: |-
    ### test — green
    - evidence: `swift test` (root) — 1793 tests passed, 0 failed, 0 skipped, 0 warnings. `swift build --build-tests --package-path IntegrationTests` (clean build) — build complete, 0 errors, 0 warnings in this repository. It found 5 warnings in the vendored `mlx-swift` dependency under `.build/checkouts`. That code is not part of this repository. `swift test --package-path IntegrationTests --no-parallel --filter "BraveHTMLLiveTests|DuckDuckGoHTMLLiveTests|KeylessChainLiveTests|FetchLiveTests|GuardLiveTests|WebRunCodeLiveTests"` — 13 tests passed in 6 suites, with 2 known issues (the DuckDuckGo challenge page). The user's decision of 2026-09-26 says this known issue is not a failure.
    - next: none. The build is clean.
  timestamp: 2026-09-26T14:04:45.842774+00:00
position_column: doing
position_ordinal: '80'
title: 'Web: merge the live web tests into IntegrationTests and remove WebIntegrationTests'
---
## What
The user decided on 2026-09-26: all live web tests go in the existing `IntegrationTests/` package, and the separate `WebIntegrationTests/` package goes away. The rule "nothing here reads the environment" of `IntegrationTests` changes: an API key from the environment is allowed as configuration for a test that always runs.

- Move each suite and helper from `WebIntegrationTests/Tests/FoundationModelsMultitoolWebIntegrationTests/` into `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/` (for example a `Web/` subfolder): BraveHTMLLiveTests, DuckDuckGoHTMLLiveTests (keep the `withKnownIssue` rule for the challenge page), KeylessChainLiveTests, FetchLiveTests, GuardLiveTests, WebRunCodeLiveTests, `Support/LiveSearch.swift`, `Support/LiveFetch.swift`. Keep the git history with `git mv` where possible.
- Add the dependencies that the moved tests need to `IntegrationTests/Package.swift` (for example the `MultitoolTestSupport` product and SwiftSoup, as `WebIntegrationTests/Package.swift` has them).
- Delete `WebIntegrationTests/` (Package.swift and all sources).
- Change the no-environment rule in `IntegrationTests/Package.swift` (the doc comment near the top) and anywhere else the repository states or checks it (search for "reads the environment", `ProcessInfo.processInfo.environment` checks, and the `rg` check in `WebResearchScenarioTests` or its card). New rule: a test may read an API key variable as configuration; a test never reads the environment to decide if it runs.
- Update `web.md` (§ "Testing" Level 2, the file list, the CI section) and `README.md` / `docs/SECURITY.md` where they name `WebIntegrationTests`.

## Acceptance Criteria
- [x] `WebIntegrationTests/` does not exist.
- [x] `swift build --build-tests --package-path IntegrationTests` passes, and `swift test --package-path IntegrationTests --no-parallel --filter "BraveHTMLLiveTests|DuckDuckGoHTMLLiveTests|KeylessChainLiveTests|FetchLiveTests|GuardLiveTests|WebRunCodeLiveTests"` passes (a DuckDuckGo challenge page is a known issue).
- [x] The rule text in `IntegrationTests/Package.swift` and `web.md` states the new rule.
- [x] `rg -n "WebIntegrationTests" --glob '!.kanban/**'` finds no stale reference.

## Tests
- [x] Run the filtered IntegrationTests command above once.
- [x] Run root `swift test`. All pass.

## Workflow
- Use `/tdd` where behavior changes.

## Review Findings (2026-09-26 08:31)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 24 file(s) reviewed, 9 not reviewed.

> 8 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 8 file(s)

> 1 file(s) not reviewed — no validator matched:
> - `web.md` — no validator matches this file

> Note: the hygiene rules `disallowed-constructs-swift`, `function-length-swift`, `idioms-swift`, `magic-numbers-swift` and `missing-docs-swift` found no file at the old `WebIntegrationTests/` paths of the 8 renamed files and of the deleted `WebIntegrationTests/Package.swift`. A file-scoped review of each of the 8 new `Web/` paths follows.

## Review Findings (2026-09-26 08:36)

> Scope: `review file IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Web/DuckDuckGoHTMLLiveTests.swift` — reviewed the whole of each named file. 1 file(s) reviewed, 0 not reviewed.

- [x] `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Web/DuckDuckGoHTMLLiveTests.swift:60` `swift/idioms` — Closure parameter type explicitly declares `-> Void` return type, which should be omitted. The idiom is to drop `Void` from function and closure return types entirely. Change the closure parameter type from `() async throws -> Void` to `() async throws`.

## Review Findings (2026-09-26 08:45)

> Scope: `review file IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Web/Support/LiveSearch.swift` — reviewed the whole of each named file. 1 file(s) reviewed, 0 not reviewed.

- [x] `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Web/Support/LiveSearch.swift:84` `reuse/reuse` — makeShortTimeoutConfiguration reimplements code that already exists elsewhere at near-identical form. The file comments indicate this function is meant to be shared across multiple test suites (line 80-81: 'The live fetch suites and the live `runCode` suite also use it'), yet it is being defined locally here and also in WebResearchScenarioTests.swift, creating duplication. Extract makeShortTimeoutConfiguration to MultitoolTestSupport (where WebVerbCall.search is already shared per line 7 and 17) and import it from both LiveSearch.swift and WebResearchScenarioTests.swift. This keeps one canonical implementation used by all Web/ test suites. #web