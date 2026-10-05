---
assignees:
- claude-code
depends_on:
- 01M46D11GRTDDPJMYQQRXYFN65
position_column: todo
position_ordinal: '8180'
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