---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3c6r05dtrv32wazz2670wnx
  text: |-
    ### decision — 2026-09-25
    - The user decides: add `.generic-snippet .content` as the first snippet selector in `BraveHTMLProvider`. Keep the `brave.rs` rules (`.snippet-description`, then the first `<p>` with more than 20 characters) as fallbacks. Update web.md § "What we copy" to state these rules.
  timestamp: 2026-09-25T11:55:51.853135+00:00
- actor: claude-code
  id: 01m3c93k2q72d2tk0ktw8mp14k
  text: |-
    ### research and implementation
    - The recorded page has 18 `.generic-snippet` elements. The first one is before `data-pos="1"`, outside each result container (an ad). Thus it does not change a hit.
    - The snippet of the first hit in the recorded page is: "Swift is a general-purpose programming language built using a modern approach to safety, performance, and software design patterns."
    - `BraveHTMLProvider`: `snippetSelector` is now `snippetSelectors = [".generic-snippet .content", ".snippet-description"]`. `snippet(of:)` gives the first text that is not empty of these selectors, in order, then the first `<p>` with more than 20 characters. The file header states the new rule.
    - Tests (RED seen first, for the correct reason): `recordedPageGivesFirstSnippet` (the recorded page; it gave `""` before the change) and `genericSnippetComesFirst` (a hand-written container with both selectors; it gave the `.snippet-description` text before the change).
    - web.md § "What we copy" now lists the three snippet rules in order, and states that `.generic-snippet .content` is not in `brave.rs` (decided 2026-09-25).
    - `swift test --filter BraveHTMLProviderTests`: 29 tests pass. `swift test`: 1704 tests in 134 suites pass.
    - Output that is not from this change: the SwiftPM build warning "missing creator for mutated node: ... mlx-swift_Cmlx.bundle/Contents/MacOS", and two "SWIFT TASK CONTINUATION MISUSE" lines from other suites. `swift package update` was not run.
  timestamp: 2026-09-25T12:37:08.823530+00:00
- actor: claude-code
  id: 01m3c93n127zz236bd1cw0j0ss
  text: |-
    ### implement — changed
    - evidence: 3 files — Sources/FoundationModelsMultitool/Capabilities/Web/Providers/BraveHTMLProvider.swift, Tests/FoundationModelsMultitoolTests/BraveHTMLProviderTests.swift, web.md. `swift test`: 1704 tests in 134 suites pass.
    - next: /test, then /review. The task stays in `doing`. No commit.
  timestamp: 2026-09-25T12:37:10.818277+00:00
- actor: claude-code
  id: 01m3c9baa3d0y162j5x6knbaar
  text: |-
    ### test — green
    - evidence: Clean rebuild with `swift package clean` then `swift build --build-tests` shows 0 warnings in the `Sources` and `Tests` code. The build log shows 2 warnings. Both warnings come from the vendored `mlx-swift` dependency under `.build/checkouts`. This code is not part of this package. `swift test` runs 1704 tests in 134 suites. All tests pass. No test fails. No test is skipped.
    - next: none.
  timestamp: 2026-09-25T12:41:21.987445+00:00
- actor: claude-code
  id: 01m3c9g364yj3cb8xabdw3c5vw
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit 8b5dcd8): 0 findings, 0 confirmed, 0 refuted. The engine examined 2 files: `BraveHTMLProvider.swift` and `BraveHTMLProviderTests.swift`. The engine did not examine 5 files: 4 `.kanban/` files (ignore rule in `.reviewignore`), and `web.md` (no validator for this file type). The commit renames no files. The task has no prior review findings.
    - next: none. The task is in `done`.
  timestamp: 2026-09-25T12:43:58.532148+00:00
- actor: claude-code
  id: 01m3c9ghr0q8n0yw7dmmq1tzc9
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 3 files
    - test: green — swift test, 1704 passed
    - commit: 8b5dcd8
    - review: clean — 0 findings; the task is in done
  timestamp: 2026-09-25T12:44:13.440195+00:00
position_column: done
position_ordinal: ffda80
title: 'Web: read the snippet of the current Brave results markup'
---
## What
`BraveHTMLProvider` uses the snippet rules of `brave.rs`: `.snippet-description`, else the first `<p>` with more than 20 characters. The recorded page `Tests/FoundationModelsMultitoolTests/WebGoldens/brave-results.html` (recorded 2026-09-24) has no `.snippet-description` and no such `<p>` in its `[data-pos]` containers. Thus each hit of a real Brave page has an empty snippet.

The current markup holds the snippet in `.generic-snippet .content` (for example `<div class="content desktop-default-regular t-primary line-clamp-dynamic ...">Swift is <strong>a general-purpose ...</strong>.</div>`).

A person must decide: add `.generic-snippet .content` as the first snippet selector (a change from the `brave.rs` rules in web.md § "What we copy"), and update web.md to match. Found during ^w3vpnk0.

## Acceptance Criteria
- [x] The recorded page gives a non-empty snippet for its first hit.
- [x] The ported `brave.rs` snippet fixtures stay green.
- [x] web.md § "What we copy" states the snippet rules that the code uses.

## Tests
- [x] Add a snippet assertion to `BraveHTMLProviderTests` for the recorded page. Run `swift test --filter BraveHTMLProviderTests`, then `swift test`. #web