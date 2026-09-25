---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3atq7ehs9wqvxwtz9xa160k
  text: 'Research: The copy of the site expression is at `DuckDuckGoHTMLProvider.formFields(of:)` and at `BraveAPIProvider.queryItems(of:)`. `SearchQuery.textWithSiteTerm` in `SearchProviderAdapter.swift` has the same expression. Tests that already exist cover the two adapters: `DuckDuckGoHTMLProviderTests.siteAddsTerm` and `KeyedProviderRequestTests.braveSiteAndCount`. The change does not change behavior. Thus the TDD step is a refactor while these tests stay green.'
  timestamp: 2026-09-24T23:06:29.201382+00:00
- actor: claude-code
  id: 01m3atw9ne8hbyt59txaarra8h
  text: |-
    ### implement — changed
    - evidence: 2 files — Sources/FoundationModelsMultitool/Capabilities/Web/Providers/DuckDuckGoHTMLProvider.swift, Sources/FoundationModelsMultitool/Capabilities/Web/Providers/BraveAPIProvider.swift. Each adapter now sends `query.textWithSiteTerm`, and the local `text` copy is removed. No test changed. `swift test --filter "DuckDuckGoHTMLProviderTests|KeyedProviderRequestTests"`: 31 tests in 2 suites passed before and after the change. `swift test`: 1701 tests in 134 suites passed, 0 failed. The one build warning, `missing creator for mutated node ... mlx-swift_Cmlx.bundle/Contents/MacOS`, comes from the SwiftPM bundle of the mlx-swift dependency. Earlier tasks recorded it as a warning that was there before.
    - next: /review. The task stays in `doing`. Nothing is committed.
  timestamp: 2026-09-24T23:09:15.310569+00:00
- actor: claude-code
  id: 01m3av4e3x24n2sthhm5natfr9
  text: |-
    ### test — green
    - evidence: `swift test` ran two times. The second run came after `swift package clean`. Each run shows: Test run with 1701 tests in 134 suites passed. 0 tests failed. 0 tests were skipped. Exit code 0 both times.
    - note: the build log shows 5 compiler warnings. All 5 warnings come from the `mlx-swift` dependency, under `.build/checkouts/mlx-swift`. One more warning line, "missing creator for mutated node", also names the `mlx-swift` build bundle. No warning comes from a file under `Sources/` or `Tests/` in this project. The task tells the agent not to run `swift package update`. The agent did not run it, and did not edit the `mlx-swift` dependency.
    - next: none
  timestamp: 2026-09-24T23:13:42.013691+00:00
- actor: claude-code
  id: 01m3av9sn3fjxvzjc9egz4bv0d
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit 0d64503). 0 findings, 0 confirmed, 0 refuted. 7 validator runs, 0 failed. 2 files reviewed. 4 `.kanban/` files not reviewed because `.reviewignore` excludes them.
    - next: The task moved to done. No work remains.
  timestamp: 2026-09-24T23:16:37.667179+00:00
- actor: claude-code
  id: 01m3ava2y1xte1e5yr1eben6ry
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 2 files
    - test: green — swift test, 1701 passed
    - commit: 0d64503
    - review: clean — 0 findings; the task is in done
  timestamp: 2026-09-24T23:16:47.169132+00:00
position_column: done
position_ordinal: ffd880
title: 'Web: use SearchQuery.textWithSiteTerm in DuckDuckGoHTMLProvider and BraveAPIProvider'
---
## What
`SearchQuery.textWithSiteTerm` (in `Sources/FoundationModelsMultitool/Capabilities/Web/Providers/SearchProviderAdapter.swift`) makes the query text with a `site:<host>` term. `BraveHTMLProvider` uses it. Two older adapters keep their own copy of the same expression, `query.site.map { "\(query.text) site:\($0)" } ?? query.text`:
- `DuckDuckGoHTMLProvider.formFields(of:)`
- `BraveAPIProvider.queryItems(of:)`

Replace each copy with `query.textWithSiteTerm`. Found during ^w3vpnk0.

## Acceptance Criteria
- [x] No adapter builds the `site:` term with its own expression.
- [x] The request tests of both adapters stay green with no change.

## Tests
- [x] Run `swift test --filter "DuckDuckGoHTMLProviderTests|KeyedProviderRequestTests"`, then `swift test`. #web