---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m46g4n7qz5etnc4j4tqma1ht
  text: |-
    Research done.
    - The correction is made in `WebSearchChain.search(_:)` from `correctionLead` and `SkippedProvider.failure`. After ^rxyfn65, the chain runs the relaxed query only when one or more providers gave `.noResults`. When the relaxed run fails, the chain returns the correction of the exact query. Thus a correction that holds a `no results.` part can come after a relaxed run, and a correction with no `no results.` part never comes after a relaxed run.
    - Unit tests that read the full text: `ProviderFallbackTests` (5 tests) and `WebVerbArgumentTests.failedSearchIsCorrected`. The other files that the card names (`ScenarioFailureModeTests`, `WebCapabilityTests`, `BraveHTMLProviderTests`, `DuckDuckGoHTMLProviderTests`) do not read the correction text now.
    - Important: `IntegrationTests/.../Web/Support/BlockedProviderRule.swift` parses the correction. The reason of the last provider "runs to the end of the correction". A next step at the end breaks that parse: the reason of the last provider then holds the step, and each live block fails as `notABlock`. The rule must remove the step first. `BlockedProviderRuleTests.correction(_:)` builds the text from `correctionLead`, and must add the step.
    - `web.md` gives the text in § "Corrections, not throws", § "Fallback", and § "Testing" (the blocked provider rule and the `BlockedProviderRuleTests` row).
  timestamp: 2026-10-05T17:00:19.063148+00:00
- actor: claude-code
  id: 01m46ghtcc7pw8m9nt2kmyav2d
  text: |-
    Implementation landed (TDD: RED 9 failures in the unit tests, RED 10 failures in BlockedProviderRuleTests, then GREEN).
    - `WebSearchChain`: two new constants, `correctionNextStep` ("Search again with fewer words, with no quote marks and no names of persons.") and `correctionWaitStep` ("Wait, then search again."). The private `nextStep(after:)` puts one of them at the end of each correction. `correctionLead` stays the first sentence.
    - Decision (written in the doc comment of `correctionWaitStep`): the fewer-words step when one or more providers gave `.noResults`; else the wait step. This is wider than the example on the card ("every failure is a block"): a server error, a network failure, an unreadable response, or a key problem also gets the wait step, because no provider found nothing for the query, thus a different query does not help. A mix of a block and `.noResults` gets the fewer-words step, because the query is the cause that the model can change. After a relaxed run that fails too, the correction always holds a `no results.` part, thus it ends with the fewer-words step. That step stays correct, because the relaxed text keeps each word.
    - Integration: `BlockedProviderRule` now removes the next step before it reads the reason of the last provider. Without that, each live block failed as `notABlock`. A correction with no next step is the new failure `.nextStepMissing`. Two new offline tests: a block then no results (the step is not in the reason), and a correction with no next step.
    - Docs: `web.md` (§ "Corrections, not throws", § "Fallback" with the decision and two examples, § "Testing" rule text and the `ProviderFallbackTests` and `BlockedProviderRuleTests` rows) and the `IntegrationTests/Package.swift` doc comment.
    - What did not work: a `@Test` display name built with `+` does not compile (`expect a compile-time constant literal`). Keep test names as one literal.
  timestamp: 2026-10-05T17:07:30.316315+00:00
- actor: claude-code
  id: 01m46ghxsdxw2068kd5va0df9f
  text: |-
    ### implement — changed
    - evidence: 7 files — Sources/FoundationModelsMultitool/Capabilities/Web/WebSearchChain.swift, Tests/FoundationModelsMultitoolTests/ProviderFallbackTests.swift, Tests/FoundationModelsMultitoolTests/WebVerbArgumentTests.swift, IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Web/Support/BlockedProviderRule.swift, IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Web/BlockedProviderRuleTests.swift, IntegrationTests/Package.swift, web.md. `swift build --build-tests` clean; `swift test` 1832 tests in 152 suites passed, 0 warnings; `cd IntegrationTests && swift test --filter BlockedProviderRuleTests` 17/17 passed; `cd IntegrationTests && swift build --build-tests` complete, 0 warnings.
    - next: /review
  timestamp: 2026-10-05T17:07:33.805995+00:00
- actor: claude-code
  id: 01m46gn4wbj2zn59t8p11zkync
  text: |-
    ### test — green
    - evidence: swift test (unit) — 1832 tests in 152 suites passed, 0 failed, 0 skipped; IntegrationTests swift build --build-tests — complete; swift test --filter BlockedProviderRuleTests — 17 tests in 1 suite passed. Only warning: mlx-swift_Cmlx.bundle "missing creator for mutated node" (dependency, not our code).
    - next: review
  timestamp: 2026-10-05T17:09:19.371942+00:00
- actor: claude-code
  id: 01m46gp15axebbp35sztjcz0ht
  text: |-
    ### commit — changed
    - evidence: one local commit "fix: tell the model what to do after a web search correction" (sha is in the step record of the final reply; the sha cannot be in this comment because the comment is part of the commit)
    - files: WebSearchChain.swift, ProviderFallbackTests.swift, WebVerbArgumentTests.swift, BlockedProviderRule.swift, BlockedProviderRuleTests.swift, IntegrationTests/Package.swift, web.md, all .kanban changes (ledger of ^rxyfn65 included)
    - next: review
  timestamp: 2026-10-05T17:09:48.330613+00:00
depends_on:
- 01M46D11GRTDDPJMYQQRXYFN65
position_column: doing
position_ordinal: '80'
title: 'Web search: the correction tells the model what to do'
---
## Problem

When no provider gives hits, `WebSearchChain` returns one correction. The correction says only what failed, for example:

`No search provider gave results. braveHTML: blocked (HTTP 429). duckDuckGoHTML: no results.`

In the SWE-bench run (reported by the FoundationModelsACPAgent session), the model read this correction and stopped searching. It did not make the query wider. The correction must also give the next step.

## Where

- `Sources/FoundationModelsMultitool/Capabilities/Web/WebSearchChain.swift`:
  - `static let correctionLead` (line 29).
  - `search(_:)`, line 82: `([Self.correctionLead] + skipped.map(\.failure)).joined(separator: " ")`.
- Tests that read `correctionLead` or the full correction text: `ProviderFallbackTests.swift`, `ScenarioFailureModeTests.swift`, `WebCapabilityTests.swift`, `BraveHTMLProviderTests.swift`, `DuckDuckGoHTMLProviderTests.swift`, and the integration tests under `IntegrationTests/.../Web/` (for example `KeylessChainLiveTests.swift`, `BlockedProviderRuleTests.swift`). Find each with a search for `correctionLead`.
- `web.md` § "Fallback" gives the text of the correction. Update it.

## Fix

1. Add a new constant, for example `static let correctionNextStep`, with the text: `Search again with fewer words, with no quote marks and no names of persons.`
2. Put it at the end of the correction, after the failure of each provider. Keep `correctionLead` as the first sentence, thus a test that reads the start of the text stays correct.
3. Give the next step for each correction, also when no failure is `.noResults`. Optional: when every failure is a block (HTTP 429, challenge page) and none is `.noResults`, a different step can be better, for example "Wait, then search again." Decide, and write the decision in the doc comment.
4. This task comes after the relaxed-query task (`01M46D11GRTDDPJMYQQRXYFN65`). After that task, a correction means the relaxed query also failed. The text must stay correct for that case.

## Tests

- Test the full correction text for one `.noResults` case and for one block-only case. Use the constants in the expected text; do not copy the words in the test.
- Update each test that reads the old full text.

## Acceptance

- `swift build` and `swift test` pass with no new warnings.
- `web.md` shows the new text. #web #defect