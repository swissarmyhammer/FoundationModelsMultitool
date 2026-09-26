---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3d0bjar33chwp88590k5e0p
  text: |-
    Research:
    - `Search`, `SearchResult`, `WebHit`, and `WebContext` are internal. The live suites use `@testable import FoundationModelsMultitool`, the same as `IntegrationTests/`. A debug build of a package dependency has testing enabled, thus this works across the package boundary.
    - The live helper makes one `WebContext` with a `URLSessionConfiguration.ephemeral` that has short request and resource timeouts, and a `WebFetchPolicy` with a short `searchTimeout`. It calls `Search(context:).call(arguments:)`, the same path as `WebVerbFixture` of the unit tests, with the real `SystemHostResolver`.
    - `BraveHTMLProvider` and `DuckDuckGoHTMLProvider` both support `.site`, thus the `site:` test applies to both.
    - The CI job for this package is task ^thvf1sz (web.yml). This task adds no workflow.
    - `Package.resolved` is git-ignored at each level (root `.gitignore`), thus the new package adds no resolved file to git.
  timestamp: 2026-09-25T19:23:27.448571+00:00
- actor: claude-code
  id: 01m3d11jgkk0wjad2cj9j60wn4
  text: |-
    Implementation landed (not committed).
    - New package `WebIntegrationTests/`: `Package.swift` (path dependency on `..`, SwiftSoup with the same URL and requirement as the root, one test target that links only `FoundationModelsMultitool`). The doc comment states the deliberate environment read and the rule of `IntegrationTests/`.
    - `Support/LiveSearch.swift` holds the shared setup: one `WebContext` with `URLSessionConfiguration.ephemeral` (request timeout 10 s, resource timeout 15 s) and `WebFetchPolicy(searchTimeout: 10)`. It also holds the two shared test bodies, thus the Brave and DuckDuckGo suites do not copy them. The host check `isHost(_:under:)` accepts the domain or a subdomain only, thus `notswift.org` does not match `swift.org`.
    - `KeylessChainLiveTests` states the two keyless names itself and does not read them from `.keyless`, thus a keyed provider in `.keyless` fails it.
    - Evidence: `swift build --build-tests --package-path WebIntegrationTests` completes. The only warnings come from third-party checkouts (mlx metal headers, the SwiftPM cache note, "missing creator" for the mlx bundle, which the root build also shows). The first `swift test --package-path WebIntegrationTests --no-parallel` passed 5 tests in 3 suites in 3.8 s. Root `swift test` passed 1790 tests in 143 suites, and no "Live:" suite ran.
    - Proof that a check can fail: with `swiftHost` set to `wift.org` for one run, the Brave query test failed at the call site and showed the hosts (`www.swift.org`, `docs.swift.org`, ...). The value was then restored.
    - Discovery: after approximately 10 DuckDuckGo requests in a few minutes, `html.duckduckgo.com` served its challenge page. `DuckDuckGoHTMLLiveTests` then failed with "duckDuckGoHTML: blocked by a challenge page.", and the block was still there after 5 minutes. Brave and the keyless chain stayed green. The provider reports this correctly. The CI risk is recorded as task ^zfah7d8. A manual `curl` probe of DuckDuckGo was refused by the shell security check, and I did not try to go around it.
  timestamp: 2026-09-25T19:35:28.531659+00:00
- actor: claude-code
  id: 01m3d11qyqat4vt2pjj21jmj5r
  text: |-
    ### implement — changed
    - evidence: 5 files — WebIntegrationTests/Package.swift, WebIntegrationTests/Tests/FoundationModelsMultitoolWebIntegrationTests/Support/LiveSearch.swift, WebIntegrationTests/Tests/FoundationModelsMultitoolWebIntegrationTests/BraveHTMLLiveTests.swift, WebIntegrationTests/Tests/FoundationModelsMultitoolWebIntegrationTests/DuckDuckGoHTMLLiveTests.swift, WebIntegrationTests/Tests/FoundationModelsMultitoolWebIntegrationTests/KeylessChainLiveTests.swift. `swift build --build-tests --package-path WebIntegrationTests` completes. First live run: 5/5 pass. Root `swift test`: 1790/1790 pass, no live suite runs.
    - next: /review. Note: later live runs on this machine hit the DuckDuckGo challenge page (2 DuckDuckGo tests red, 3 green). See ^zfah7d8.
  timestamp: 2026-09-25T19:35:34.103700+00:00
- actor: claude-code
  id: 01m3d18hpr7h274jmdskzjwnhb
  text: |-
    ### test — stuck
    - evidence: `swift test` at the root: 1790 tests passed, 0 failed, 0 skipped. No warning in our code. (1 warning about the vendored mlx-swift `Cmlx` bundle — out of scope, per instruction.) `swift build --build-tests --package-path IntegrationTests`: build complete, no warning in our code (same mlx-swift bundle warning only). `swift test --package-path WebIntegrationTests`: 3 tests passed, 2 tests failed. The 2 failed tests are in `DuckDuckGoHTMLLiveTests`. Each failed with: "duckDuckGoHTML: blocked by a challenge page." I ran this suite two times. Both times gave the same failure. `BraveHTMLLiveTests` and `KeylessChainLiveTests` stayed green both times.
    - blocker: this is a true conflict. It is not a code defect. The provider code finds the challenge page and reports it. This is correct work, by design. `web.md` forbids a retry for this suite. The open task ^zfah7d8 (01M3D117MN69E3K1GHHZFAH7D8) already records this same conflict. That task asks a human to decide: is a challenge page a failure of this suite, or a known condition with its own clear report? I cannot make that decision. I made no code change for this failure.
    - next: a human must decide ^zfah7d8 first. Then run `/test` again.
  timestamp: 2026-09-25T19:39:17.080771+00:00
- actor: claude-code
  id: 01m3esffgqkkkkbe1pr789brh8
  text: |-
    ### finish iteration 1 — stuck
    - implement: changed — 5 files (new WebIntegrationTests package)
    - test: stuck — root swift test 1790 passed; IntegrationTests build passes; WebIntegrationTests 3 passed, 2 failed (DuckDuckGo challenge page after many requests)
    - commit: none yet
    - review: not run
    ### decision — 2026-09-26
    The user decides: a DuckDuckGo challenge page is a known condition. `DuckDuckGoHTMLLiveTests` records it with `withKnownIssue` and a clear message; any other correction (markup change, empty result) still fails. No retry. Iteration 2 makes this change. Task ^zfah7d8 records the decision in web.md and the CI rule (DuckDuckGo suite on the daily schedule only).
  timestamp: 2026-09-26T12:01:44.471042+00:00
- actor: claude-code
  id: 01m3esxw6pyz7azea042ceq25e
  text: |-
    Iteration 2 landed (not committed). This applies the decision of 2026-09-26.
    - `DuckDuckGoHTMLLiveTests`: each test runs its body in `withChallengePageAsKnownIssue`. That helper calls `withKnownIssue(challengeComment, isIntermittent: true)` with a `matching:` filter. The filter accepts only an issue whose comment is exactly "the search gave a correction: No search provider gave results. duckDuckGoHTML: blocked by a challenge page." The known-issue comment is "DuckDuckGo served its challenge page and not the results. This is a known condition of the live service." No retry.
    - `Support/LiveSearch.swift`: new `expectHits(of:sourceLocation:_:)`. A correction records one issue with the comment `correctionComment(_:)`, and the checks of the hits do not run. Thus the challenge gives exactly one issue, and the filter can match it. Before this change, a correction also gave the count and host failures, and those could not match. `expectNoCorrection` (keyless suite) uses the same comment text.
    - Brave: the suite file did not change. A correction still fails a Brave test. The one change is the count of issues on a correction: one issue, not three.
    - Discovery: in Testing 2084, `withKnownIssue` with an async body is `rethrows`. A thrown error that does not match comes back to the caller, thus the helper is `async rethrows` and the tests are `async throws`.
    - Proof (temporary tests, then removed): a synthetic challenge correction passed with 1 known issue; a synthetic "duckDuckGoHTML: no results." correction failed; a failed `#require` (no hits) failed.
    - Evidence: `swift test --package-path WebIntegrationTests`: 5 tests in 3 suites passed, with 2 known issues. DuckDuckGo was blocked in this run, and both DuckDuckGo tests recorded the challenge as a known issue. A run one minute before, with the old code, passed with no block. Root `swift test`: 1790 tests in 143 suites passed, no "Live:" suite ran. The only warning is the third-party mlx `Cmlx` bundle "missing creator" note.
  timestamp: 2026-09-26T12:09:36.214832+00:00
- actor: claude-code
  id: 01m3esxyrj89msjegxv1pvtbjm
  text: |-
    ### implement — changed
    - evidence: 2 files — WebIntegrationTests/Tests/FoundationModelsMultitoolWebIntegrationTests/DuckDuckGoHTMLLiveTests.swift, WebIntegrationTests/Tests/FoundationModelsMultitoolWebIntegrationTests/Support/LiveSearch.swift. `swift test --package-path WebIntegrationTests`: 5/5 pass, 2 known issues (DuckDuckGo challenge page). Root `swift test`: 1790/1790 pass, no live suite runs.
    - next: /test, then /review. web.md and the CI rule stay with ^zfah7d8.
  timestamp: 2026-09-26T12:09:38.834310+00:00
- actor: claude-code
  id: 01m3et28sbdtwc6gs76rchk709
  text: |-
    ### test — green
    - evidence: `swift test` — 1790 tests, 143 suites, 0 failures; `swift build --build-tests --package-path IntegrationTests` — build OK; `swift test --package-path WebIntegrationTests` — 5 tests, 3 suites, 0 failures, 2 known issues (DuckDuckGo challenge page, per the 2026-09-26 decision — counted as passing)
    - note: one warning found: `missing creator for mutated node (...mlx-swift_Cmlx.bundle/Contents/MacOS)`. This comes from the vendored mlx-swift package build step, not from this repository's code. It is reported, not treated as red.
    - next: none. The build is clean.
  timestamp: 2026-09-26T12:12:00.171324+00:00
- actor: claude-code
  id: 01m3etc8wdjj04w1wpen0n0nnk
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit e725bc5). 0 findings, 0 confirmed, 1 refuted. 5 files reviewed. 6 `.kanban/` files not reviewed (excluded by `.reviewignore`). The task has no prior `## Review Findings` section.
    - next: none. The task moved to done.
  timestamp: 2026-09-26T12:17:27.949949+00:00
- actor: claude-code
  id: 01m3etckct6b5d6gbv2vfadmsr
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — 2 files (DuckDuckGo challenge page recorded as a known issue, narrow match)
    - test: green — root swift test 1790 passed; IntegrationTests build passes; WebIntegrationTests 5 passed, 2 known issues (challenge page)
    - commit: e725bc5
    - review: clean — 0 findings (1 refuted); the task is in done
  timestamp: 2026-09-26T12:17:38.714510+00:00
depends_on:
- 01M3A32XTTF1JWYSA9GPDZP3KQ
position_column: done
position_ordinal: ffe480
title: 'Web: create the WebIntegrationTests package with keyless live search tests'
---
## What
Add the live test package that searches the real web, with no model. Design: `web.md` § "Testing / Level 2" (why a separate package, the assertion rule, the suite table). The next task adds the live fetch, guard, and runCode suites to this package.

- Create `WebIntegrationTests/Package.swift`, modelled on `IntegrationTests/Package.swift`: `platforms: [.macOS("27.0")]`, `.package(path: "..")`, and the SwiftSoup dependency with the same URL and requirement as the root `Package.swift`. One test target `FoundationModelsMultitoolWebIntegrationTests` that links only `FoundationModelsMultitool` (no MLX, no Router live wiring). A doc comment states that this package reads the environment on purpose, because the keyed tests test that feature, and that `IntegrationTests/` keeps its rule of no environment read.
- Create these suites under `WebIntegrationTests/Tests/FoundationModelsMultitoolWebIntegrationTests/`, each `.serialized` with `.timeLimit(.minutes(1))`:
  - `BraveHTMLLiveTests`: `[.braveHTML]` only; query `swift programming language` gives at least 3 hits, each `https`, and a host that is `swift.org` or ends in `.swift.org`; `site: "developer.apple.com"` gives hosts that end in `apple.com`.
  - `DuckDuckGoHTMLLiveTests`: the same two tests with `[.duckDuckGoHTML]`.
  - `KeylessChainLiveTests`: `.keyless` gives hits from one of the two keyless providers.
- No test retries. A test asserts only the stable facts above.

## Acceptance Criteria
- [x] `swift build --package-path WebIntegrationTests --build-tests` succeeds.
- [x] `swift test --package-path WebIntegrationTests --no-parallel` passes on a machine with network access.
- [x] The root `swift test` does not compile or run any of these suites.

## Tests
- [x] The three suites above.
- [x] Run `swift test --package-path WebIntegrationTests --no-parallel`. All pass.
- [x] Run `swift test` at the root. All pass, and no web live suite runs.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #web