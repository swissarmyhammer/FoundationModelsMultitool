---
assignees:
- claude-code
depends_on:
- 01KZ6N0G06Q27NNK51PZFF76MX
position_column: todo
position_ordinal: '9280'
title: '[ToolAPIRenderer] Render tools.* declared return types as Promise<T>, and await examples'
---
Discovered while implementing ^zff76mx ("[MultiTool] Remove the blocking bridge; tools.* return promises"), via an adversarial double-check review.

## What
`tools.*` calls now genuinely return a JS `Promise` (the async host-function bridge onto the interpreter's promise pump — eventplan.md "Async JavaScript"). But `Sources/FoundationModelsMultitool/Surface/ToolAPIRenderer.swift` (and the `ToolDescriptor`/`APISurface.Entry` rendering it feeds) still declares each `tools.*` binding's return type as the bare `T` and renders `@example` call sites without `await`, e.g. (from `Tests/FoundationModelsMultitoolTests/Goldens/WeatherTool.ts.txt`):

```
 * @example const r = tools.weather({ city: "city" });
declare function weather(args: { city: string; units?: "c" | "f" }): { tempC: number; summary: string };
```

This text is spliced into `findAPIs` results, the registry-backed selection tier's instruction prefix, and `help()`/`docs()` output — the authoritative surface the model reads to learn how to call `tools.*`. It now contradicts `MultiTool.description`'s new async-usage line ("await each `tools.*` call...") and steers the model toward the exact anti-pattern eventplan.md calls out: `const r = tools.x(...); r.tempC` silently evaluates to `undefined` today (the Proxy trap eventplan.md describes for catching "property access on a pending result" is a separate, not-yet-implemented task — see `01KZ6NSZAGGYJ9Z3A2YWPQ0Q6D`).

## Acceptance Criteria
- [ ] Every rendered `declare function <name>(...)` return type is `Promise<T>`, not bare `T`.
- [ ] Every rendered `@example` call site awaits the call (`const r = await tools.x({...});`).
- [ ] Golden fixtures under `Tests/FoundationModelsMultitoolTests/Goldens/` updated to match.
- [ ] `ToolAPIRendererTests` (and any other test asserting on the rendered declaration/example text) updated and green.
- [ ] Full `swift test` green.

## Tests
- Update `Tests/FoundationModelsMultitoolTests/ToolAPIRendererTests.swift` and the golden fixtures to assert the `Promise<T>`/`await` shape. #phase-1