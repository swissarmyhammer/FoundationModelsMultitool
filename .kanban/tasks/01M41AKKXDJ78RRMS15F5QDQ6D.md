---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m41kcf7xnqn3x4a18wcka31a
  text: |-
    Research and implementation notes.

    - `WebContext.init` has no default `sessionConfiguration`. Thus `LiveSearch.search` and `LiveFetch.makeContext` now give `.ephemeral` (the default of the capability). `WebRunCodeLiveTests` and `WebResearchScenarioTests` now call `withWeb(configuration: .keyless)` and use the default `.ephemeral` session.
    - Removed `LiveSearch.makeSessionConfiguration()`, `LiveSearch.requestTimeoutSeconds`, `LiveSearch.resourceTimeoutSeconds`, `webRequestTimeoutSeconds` and `webResourceTimeoutSeconds`. No caller is left.
    - `Package.swift` also named `ShortTimeoutSession` in the doc comment of `multitoolTestSupportTargetName`. The card did not list it. I removed that clause, because the type does not exist now.
    - Comments now say: the session has no timeout of its own, the fetcher sets no time limit on a request, and `IntegrationHangGuard/timeLimit` bounds each test. In `WebResearchScenarioTests`, the outer timeout of `runCode` bounds each snippet.
    - Not changed, out of scope: `ShellRunnerTests.shortTimeout`, `MetricsTests.shortCallTimeout` and `MCPTracePropagationTests.shortCallTimeout`. They are parameters of other tool paths and do not feed `ShortTimeoutSession`. `TestHangGuard.seconds` and `LoopbackHTTPServer` bound an in-process loopback, not a live web request.
    - TDD: this card only deletes code and corrects comments. It adds no behavior, thus there is no new failing test. The acceptance check is the `rg` search, which now finds nothing.
    - The build prints `warning: missing creator for mutated node: .../mlx-swift_Cmlx.bundle/Contents/MacOS`. This is a SwiftPM build-system message about the mlx-swift dependency bundle, not a compiler warning in this code. It was there before this change.
  timestamp: 2026-10-03T19:20:48.637016+00:00
- actor: claude-code
  id: 01m41kcnsz8aae94crh6wj4vh3
  text: |-
    ### implement — changed
    - evidence: 8 files. Deleted with `git rm`: Tests/Support/MultitoolTestSupport/ShortTimeoutSession.swift, Tests/FoundationModelsMultitoolTests/ShortTimeoutSessionTests.swift. Changed: IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Web/Support/LiveSearch.swift, Web/Support/LiveFetch.swift, Web/WebRunCodeLiveTests.swift, WebResearchScenarioTests.swift, Package.swift (doc comment). Root `swift build --build-tests`: Build complete. Root `swift test`: 1806 tests in 150 suites passed, 0 failures. `cd IntegrationTests && swift build --build-tests`: Build complete. Live tests not run. `rg -n "ShortTimeoutSession" Tests IntegrationTests Sources`: no match.
    - next: /review
  timestamp: 2026-10-03T19:20:55.359576+00:00
- actor: claude-code
  id: 01m41kpfs78732ydwsz00632g6
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (commit 5a9904b): 0 findings, 0 confirmed, 0 refuted; 7 files reviewed, 4 .kanban files ignored by .reviewignore. The commit renames no file, thus no file-scoped review was necessary. Hygiene rules declined only the two deleted files, which have no content.
    - next: task moved to done.
  timestamp: 2026-10-03T19:26:16.871293+00:00
- actor: claude-code
  id: 01m41kq1z4mphnt1k49nnnh8xf
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 7 files (2 deleted, 5 modified)
    - test: green — swift test 1806 tests in 150 suites passed; IntegrationTests build-tests passed
    - commit: 5a9904b
    - review: clean — 0 findings
  timestamp: 2026-10-03T19:26:35.492832+00:00
position_column: done
position_ordinal: ffffa280
title: Remove ShortTimeoutSession and the short timeouts of the live web suites
---
## What
Rule (decision of the user, final): the only timeout is the outer `runCode` tool timeout. No test support adds a second clock.

Card `^q586aqm` made `WebFetcher` copy the caller's `URLSessionConfiguration` and set `timeoutIntervalForRequest`, `timeoutIntervalForResource` and `URLRequest.timeoutInterval` to `.infinity`. Thus `ShortTimeoutSession` (`Tests/Support/MultitoolTestSupport/ShortTimeoutSession.swift`) has no effect, and the live web suites that give it short timeouts state a false bound. Remove it. Do not replace it with another clock. The integration hang guards (`IntegrationHangGuard`, `IntegrationPoll`) stay; they bound a test, not a tool call.

Subtasks:
- [x] Delete `Tests/Support/MultitoolTestSupport/ShortTimeoutSession.swift` and `Tests/FoundationModelsMultitoolTests/ShortTimeoutSessionTests.swift`.
- [x] In `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/`, remove each use and each timeout constant that fed it: `Web/Support/LiveSearch.swift` (`makeSessionConfiguration()`), `LiveFetch`, `WebRunCodeLiveTests.swift`, `WebResearchScenarioTests.swift` (find them with `rg -n "ShortTimeoutSession|shortTimeout|timeoutIntervalFor" IntegrationTests Tests`). Use a plain `URLSessionConfiguration` (or the fetcher default) in their place.
- [x] Correct each comment that says a short session timeout bounds a live web request.

## Acceptance Criteria
- [x] `rg -n "ShortTimeoutSession" Tests IntegrationTests Sources` finds nothing.
- [x] No comment in `IntegrationTests/` or `Tests/Support/` says that a short session timeout bounds a live web request.

## Tests
- [x] `swift build --build-tests` and `swift test` pass in the root package.
- [x] `cd IntegrationTests && swift build --build-tests` passes. (Do not run the live tests locally; CI runs them.)

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #timeouts #web