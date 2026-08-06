---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01kzbbz9hpee20kcy201jz3bq4
  text: |-
    Picked up; research done.

    Findings:
    - `ToolAPIRenderer.render(name:description:parameters:returns:onWiden:)` builds two strings that need changing: `returnsType` (feeds both the real `declaration` and, via the escaped `docReturnsType` copy, the `@returns` doc line) and `exampleCall` (feeds both the `@example` doc line and `ToolDescriptor.example`).
    - Decision: wrap once at the single source — `returnsType = "Promise<\(resolved)>"` — so `declaration` and the `@returns` line agree by construction rather than deliberately diverging. `@returns Promise<{ tempC: number; summary: string }> — current conditions.` is standard JSDoc for an async function.
    - Decision: `await` goes inside `exampleCall`, so both the `@example` line (`const r = await tools.x({...});`) and the runnable `ToolDescriptor.example` (`await tools.x({...});`) carry it. `example` is spliced verbatim into `FindAPIsTool.format`'s `Example: …` trailer, so an un-awaited copy there would teach the exact anti-pattern. Top-level `await` is valid in that text because `JSCInterpreter.run` wraps every snippet in `(async function(){ … })`.
    - `APISurface.Entry.qualify` substitutes on the `tools.<name>(` substring only, so the `await ` prefix passes through untouched; grouped entries stay correct.
    - Consumers that derive rather than hard-code the text (`FindAPIsToolTests`, `BuilderSurfaceTests`, `ExamplesTests`, `UnknownToolHint`) need no change. Hard-coded assertions live only in `ToolAPIRendererTests` and the two goldens.
    - Docs that quote the old shape and must be corrected: `ToolDescriptor.declaration`/`example` field docs, `ToolAPIRenderer.Returns.schema`/`.text` case docs, and the `returnsType`/`exampleCall` inline comments.
  timestamp: 2026-08-06T11:05:11.990008+00:00
- actor: claude-code
  id: 01kzbc8q42vmkp64c0tr93qfg0
  text: |-
    Implementation landed (TDD: test expectations and goldens updated first, watched 13 failures across the ToolAPIRenderer suite, then made them pass).

    Renderer (`Sources/FoundationModelsMultitool/Surface/ToolAPIRenderer.swift`):
    - The `switch returns` block now produces `resolvedType`; a single new line wraps it as `returnsType = "Promise<\(resolvedType)>"`. Because `docReturnsType` is derived from `returnsType`, the `declare function` signature and the `@returns` line are the same string by construction — they cannot drift apart.
    - `exampleCall` now leads with `await`, which carries into both the `@example` doc line and the runnable `ToolDescriptor.example`.
    - `Promise` and `await` are written inline rather than as named constants: each appears exactly once, and this file's own convention (stated on `typeObject`/`typeString`/…) is to name a literal only at three or more call sites.

    Docs corrected to match: the `ToolAPIRenderer` type doc, both `Returns` cases, and `ToolDescriptor.declaration`/`.example`. Per the stale-description correction above, no new text claims the silent-undefined behavior; the new inline comment at `exampleCall` describes the current behavior — property access on a pending result raises the "did you forget `await`?" repair error.

    Two new focused tests pin the contract by name (`declaredReturnTypeIsPromiseWrapped`, `renderedExampleAwaitsTheCall`) alongside the golden-file pin.

    Verified no other consumer needed changing: `APISurface.Entry.qualify` substitutes only on the `tools.<name>(` substring, so the `await ` prefix passes through and grouped entries still render `await tools.github.createIssue(...)` (pinned by the BuilderSurface golden). `FindAPIsTool.format`, `UnknownToolHint`, `help()`/`docs()` and their tests all derive their text from the descriptor rather than hard-coding it.

    Note for the next agent: another session committed the interpreter work mid-run (f768e0c "throw did you forget await?" and a8db299 the blocking-bridge removal), so those files left my working set on their own. My working set is exactly 5 files; `eventplan.md` was already dirty on arrival and was not touched.

    ### implement — changed
    - evidence: 5 files — /Users/wballard/github/swissarmyhammer/FoundationModelsMultitool/Sources/FoundationModelsMultitool/Surface/ToolAPIRenderer.swift, /Users/wballard/github/swissarmyhammer/FoundationModelsMultitool/Sources/FoundationModelsMultitool/Surface/ToolDescriptor.swift, /Users/wballard/github/swissarmyhammer/FoundationModelsMultitool/Tests/FoundationModelsMultitoolTests/Goldens/WeatherTool.ts.txt, /Users/wballard/github/swissarmyhammer/FoundationModelsMultitool/Tests/FoundationModelsMultitoolTests/Goldens/BuilderSurface.ts.txt, /Users/wballard/github/swissarmyhammer/FoundationModelsMultitool/Tests/FoundationModelsMultitoolTests/ToolAPIRendererTests.swift
    - next: /review

    ### test — green
    - evidence: `swift build` clean (only the known pre-existing mlx-swift "missing creator for mutated node" manifest warning); `swift test` — 193 tests in 18 suites passed, 6 gated integration tests skipped as designed, 0 failures, 0 warnings.
    - next: /review
  timestamp: 2026-08-06T11:10:20.802626+00:00
- actor: claude-code
  id: 01kzbcm3fcz6xswgjfvb7qk558
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit 75d2606) — 0 findings, 0 confirmed, 0 refuted; 9 validators attempted, 0 failed, 0 skipped
    - next: task moved to done; all 5 acceptance criteria checked, no prior review findings outstanding
  timestamp: 2026-08-06T11:16:33.900340+00:00
- actor: claude-code
  id: 01kzbcmtq4g3bgmy3scyhqxa54
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 5 files. ToolAPIRenderer wraps the resolved type once as `Promise<T>` (so the `declare function` signature and the `@returns` doc line derive from one string and cannot drift) and emits `await tools.<name>(...)` at the single source backing both the `@example` doc line and the runnable `ToolDescriptor.example`. Goldens WeatherTool.ts.txt + BuilderSurface.ts.txt updated; ToolAPIRendererTests updated with two new contract tests (declaredReturnTypeIsPromiseWrapped, renderedExampleAwaitsTheCall). Also corrected the card's stale claim that unawaited property access silently yields `undefined` — ^wpq0q6d landed, so it now throws the "did you forget `await`?" repair error.
    - test: green — swift build clean, swift test 193/193 passed in 18 suites, 0 failures, 0 warnings (6 MULTITOOL_INTEGRATION-gated tests correctly skipped)
    - commit: 75d2606 fix(surface): render tools.* return types as Promise<T> and await examples
    - review: clean — `review sha HEAD~1..HEAD`, 0 findings, 9 validators attempted, 0 failed
    - outcome: task moved to done
  timestamp: 2026-08-06T11:16:57.700393+00:00
depends_on:
- 01KZ6N0G06Q27NNK51PZFF76MX
position_column: done
position_ordinal: ab80
title: '[ToolAPIRenderer] Render tools.* declared return types as Promise<T>, and await examples'
---
Discovered while implementing ^zff76mx ("[MultiTool] Remove the blocking bridge; tools.* return promises"), via an adversarial double-check review.

## What
`tools.*` calls now genuinely return a JS `Promise` (the async host-function bridge onto the interpreter's promise pump — eventplan.md "Async JavaScript"). But `Sources/FoundationModelsMultitool/Surface/ToolAPIRenderer.swift` (and the `ToolDescriptor`/`APISurface.Entry` rendering it feeds) still declares each `tools.*` binding's return type as the bare `T` and renders `@example` call sites without `await`, e.g. (from `Tests/FoundationModelsMultitoolTests/Goldens/WeatherTool.ts.txt`):

```
 * @example const r = tools.weather({ city: "city" });
declare function weather(args: { city: string; units?: "c" | "f" }): { tempC: number; summary: string };
```

This text is spliced into `findAPIs` results, the registry-backed selection tier's instruction prefix, and `help()`/`docs()` output — the authoritative surface the model reads to learn how to call `tools.*`. It now contradicts `MultiTool.description`'s new async-usage line ("await each `tools.*` call...") and steers the model toward the exact anti-pattern eventplan.md calls out: writing `const r = tools.x(...); r.tempC`.

**Correction (2026-08-06):** this card originally said `r.tempC` "silently evaluates to `undefined` today", with the Proxy trap deferred to `01KZ6NSZAGGYJ9Z3A2YWPQ0Q6D` (^wpq0q6d). That task is now DONE and merged (commit f768e0c), so the current behavior is that property access on a pending result throws a precise, model-repairable "did you forget `await`?" error. The rendered surface must not teach a call shape whose only outcome is that repair error.

## Acceptance Criteria
- [x] Every rendered `declare function <name>(...)` return type is `Promise<T>`, not bare `T`.
- [x] Every rendered `@example` call site awaits the call (`const r = await tools.x({...});`).
- [x] Golden fixtures under `Tests/FoundationModelsMultitoolTests/Goldens/` updated to match.
- [x] `ToolAPIRendererTests` (and any other test asserting on the rendered declaration/example text) updated and green.
- [x] Full `swift test` green.

## Tests
- Update `Tests/FoundationModelsMultitoolTests/ToolAPIRendererTests.swift` and the golden fixtures to assert the `Promise<T>`/`await` shape. #phase-1