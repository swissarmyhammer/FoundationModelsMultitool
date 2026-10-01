---
assignees:
- claude-code
position_column: todo
position_ordinal: '8580'
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

## Acceptance Criteria
- [ ] A rate limit from the Brave results page does not fail the live Brave suite, or the card records why it must fail.
- [ ] A metadata timeout for a downloaded model does not fail `LiveRouterFixture.resolve`, or the card records why it must fail.

## Tests
- [ ] `swift test --package-path IntegrationTests --no-parallel` passes.