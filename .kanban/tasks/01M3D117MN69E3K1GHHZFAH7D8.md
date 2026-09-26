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
position_column: todo
position_ordinal: '9480'
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
- [ ] `web.md` states the decision.
- [ ] The suite and the workflow follow the decision. #web