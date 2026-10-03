---
assignees:
- claude-code
position_column: todo
position_ordinal: 8b80
title: Remove ShortTimeoutSession and the short timeouts of the live web suites
---
## What
Rule (decision of the user, final): the only timeout is the outer `runCode` tool timeout. No test support adds a second clock.

Card `^q586aqm` made `WebFetcher` copy the caller's `URLSessionConfiguration` and set `timeoutIntervalForRequest`, `timeoutIntervalForResource` and `URLRequest.timeoutInterval` to `.infinity`. Thus `ShortTimeoutSession` (`Tests/Support/MultitoolTestSupport/ShortTimeoutSession.swift`) has no effect, and the live web suites that give it short timeouts state a false bound. Remove it. Do not replace it with another clock. The integration hang guards (`IntegrationHangGuard`, `IntegrationPoll`) stay; they bound a test, not a tool call.

Subtasks:
- [ ] Delete `Tests/Support/MultitoolTestSupport/ShortTimeoutSession.swift` and `Tests/FoundationModelsMultitoolTests/ShortTimeoutSessionTests.swift`.
- [ ] In `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/`, remove each use and each timeout constant that fed it: `Web/Support/LiveSearch.swift` (`makeSessionConfiguration()`), `LiveFetch`, `WebRunCodeLiveTests.swift`, `WebResearchScenarioTests.swift` (find them with `rg -n "ShortTimeoutSession|shortTimeout|timeoutIntervalFor" IntegrationTests Tests`). Use a plain `URLSessionConfiguration` (or the fetcher default) in their place.
- [ ] Correct each comment that says a short session timeout bounds a live web request.

## Acceptance Criteria
- [ ] `rg -n "ShortTimeoutSession" Tests IntegrationTests Sources` finds nothing.
- [ ] No comment in `IntegrationTests/` or `Tests/Support/` says that a short session timeout bounds a live web request.

## Tests
- [ ] `swift build --build-tests` and `swift test` pass in the root package.
- [ ] `cd IntegrationTests && swift build --build-tests` passes. (Do not run the live tests locally; CI runs them.)

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #timeouts #web