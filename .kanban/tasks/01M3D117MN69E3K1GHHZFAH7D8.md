---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3esfczbjdhat6ja28a4j34t
  text: |-
    ### decision — 2026-09-26
    The user decides:
    - A DuckDuckGo challenge page is a KNOWN condition, not a failure. `DuckDuckGoHTMLLiveTests` records it with `withKnownIssue` and a clear message. A change of markup, an empty result, or any other correction still fails the test. No retry.
    - In CI, the DuckDuckGo live suite runs ONLY on the daily schedule, not on each push or pull request.
    Work split: task ^2majyvs changes the suite (iteration 2). This task records the decision in web.md § "Testing", Level 2, and adds the daily-only rule to the acceptance criteria of the workflow task ^thvf1sz.
  timestamp: 2026-09-26T12:01:41.867289+00:00
- actor: claude-code
  id: 01m3etgm8txzgph9kd5ma031v1
  text: |-
    ### implement — research and work
    - The suite change is in commit e725bc5 (task ^2majyvs). `DuckDuckGoHTMLLiveTests` uses `withKnownIssue(isIntermittent: true)`, and the match is the exact comment of the challenge correction. This task made no change to the suite.
    - No test in `Tests/` reads `web.md`. `WebDocumentationTests` reads only `README.md` and `docs/SECURITY.md`. It stays green.
    - `web.md` § "Testing", Level 2: added the paragraph "The DuckDuckGo challenge page. (Decided, 2026-09-26.)". It states: a challenge page is a known condition, recorded with `withKnownIssue` and a narrow match; each other correction fails; no retry; in CI the DuckDuckGo live suite runs only on the daily `schedule` trigger, not on `push` or `pull_request`. The `DuckDuckGoHTMLLiveTests` table row points to that paragraph.
    - `web.md` § "Testing" / "CI": added a bullet with the same schedule-only rule, because the CI part said that all of Level 2 runs on each push and pull request.
    - Task ^thvf1sz: added one acceptance criterion and one test item for the schedule-only rule. The tag `web` stays. All other text stays.
    - Open item: the second acceptance criterion of this task ("the workflow follows the decision") is not complete yet, because `.github/workflows/web.yml` does not exist. Task ^thvf1sz now carries that rule as a requirement.
  timestamp: 2026-09-26T12:19:50.682103+00:00
- actor: claude-code
  id: 01m3etgpp0hhk8n7nt82wjrbd3
  text: |-
    ### implement — changed
    - evidence: 1 file — web.md (§ "Testing", Level 2 and CI); kanban text of ^thvf1sz (1 acceptance criterion, 1 test item) and ^zfah7d8 (first criterion checked). `swift test --filter WebDocumentationTests`: 2 tests, 18 cases, passed.
    - next: /review. The workflow part of the second criterion is done when ^thvf1sz is done.
  timestamp: 2026-09-26T12:19:53.152790+00:00
- actor: claude-code
  id: 01m3etpxa612e2gm2bansfkgge
  text: |-
    ### test — green
    - evidence: `swift test` at repo root — 1790 tests, 143 suites, 0 failures, 0 skipped. Forced a full rebuild of own sources (root, IntegrationTests, WebIntegrationTests packages) with `swift build --build-tests` — 0 warnings in repository code.
    - one warning is present: "missing creator for mutated node: (.../mlx-swift_Cmlx.bundle/Contents/MacOS)". This warning comes from the vendored mlx-swift dependency build product. It is outside this repository. It does not change the outcome.
    - no disabled or skipped tests found in the code.
    - next: none. The suite is clean.
  timestamp: 2026-09-26T12:23:16.550834+00:00
position_column: doing
position_ordinal: '80'
title: 'Web: decide how the Level 2 suite handles the DuckDuckGo challenge page'
---
## What
Found during ^2majyvs. The first run of `swift test --package-path WebIntegrationTests --no-parallel` passed all 5 tests. After approximately 10 DuckDuckGo requests in a few minutes from one machine, `html.duckduckgo.com` served its challenge page (anomaly form). `DuckDuckGoHTMLLiveTests` then failed with the correction "duckDuckGoHTML: blocked by a challenge page." The block was still there after a wait of 5 minutes. `BraveHTMLLiveTests` and `KeylessChainLiveTests` stayed green.

The provider code is correct: it finds the challenge page and reports it. The risk is in CI. The `web-integration` job of ^thvf1sz runs on each push, each pull request, and a daily schedule, from one runner address. A challenge page then makes the job red for a reason that is not markup drift.

Decide, and record in `web.md` § "Testing", Level 2:
- Is a challenge page a failure of `DuckDuckGoHTMLLiveTests` (the current behavior), or a known condition with its own clear report?
- Must the CI job limit how often it sends DuckDuckGo requests (for example, the DuckDuckGo suite on the daily schedule only)?

Do not add a retry. The assertion rule of web.md forbids it.

## Acceptance Criteria
- [x] `web.md` states the decision.
- [ ] The suite and the workflow follow the decision. #web