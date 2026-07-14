---
assignees:
- claude-code
depends_on:
- 01KXGJESWPV9TASZFGG9HCHXJ6
position_column: todo
position_ordinal: '8980'
title: Bound SelectionTier.idEnumGrammar's ids array with maxItems to prevent runaway guided-generation on off-topic findAPIs queries
---
## What

Root-caused while investigating task `9hchxj6` (native tool-calling reliability / fork() prefix-reuse regression). `SelectionTier.idEnumGrammar(ids:)` (in the `FoundationModelsMetadataRegistry` dependency, `Sources/FoundationModelsMetadataRegistry/Selection/SelectionTier.swift`) derives the xgrammar JSON Schema constraining the selection tier's guided `Selection { ids: [String] }` output. It injects an `enum` (the current candidate id set) and `uniqueItems: true` into the `ids` array's schema, but never sets `maxItems`.

`FoundationModelsRouter`'s `RuntimeJSONSchemaConverter` (the code that actually compiles the JSON Schema into an xgrammar constraint) supports `minItems`/`maxItems` when present in the schema, but does **not** read or enforce `uniqueItems` at all (confirmed: zero references to `uniqueItems` anywhere in `FoundationModelsRouter`'s `Guided/` sources). So the injected `uniqueItems: true` is silently dropped — it has no effect on the compiled grammar — and with no `maxItems` cap either, the compiled grammar permits an **unbounded-length** array of (possibly repeated) enum-member id strings.

## Evidence

Reproduced deterministically on real M3 Ultra hardware (`mlx-community/Qwen2.5-1.5B-Instruct-4bit`), 2 independent runs, identical result both times: `PrefixReuseTests`' second `findAPIs` call — task "convert 100 USD to EUR" against a ~20-tool registry with no matching tool — generated **6150 tokens** (vs. the first call's 13 tokens for a genuine match), producing a ~104-106x wall-clock slowdown. Added temporary diagnostic instrumentation directly into the local `mlx-swift-lm` `PromptCache`/`Executor` checkout (reverted, never committed) and confirmed prefix-reuse itself worked correctly (95% of tokens served from `PromptCache`, only 73 fresh tokens fed) — the slowdown is caused entirely by the generation call itself running away, not by any caching defect. This is the actual root cause of what looked like a `fork()`/`PromptCache` regression on task `9hchxj6` — it isn't one.

## Fix

In `SelectionTier.idEnumGrammar(ids:)`, also inject a `maxItems` bound on `ids` — e.g. `ids.count` (never more selections than there are candidates) or `config.candidateLimit`-scoped for the over-budget path — so the compiled grammar structurally caps how long a degenerate/off-topic selection can run, closing off the runaway-generation failure mode regardless of whether `uniqueItems` support is ever added to `RuntimeJSONSchemaConverter`.

Also consider (separately, lower priority): teach `RuntimeJSONSchemaConverter` to actually enforce `uniqueItems` for arrays, since it's currently a schema property with zero effect — either support it or stop injecting it so the schema doesn't claim a guarantee the grammar doesn't provide.

## Scope

This fix lives in the `FoundationModelsMetadataRegistry` dependency (pulled via `Package.swift` from `https://github.com/swissarmyhammer/FoundationModelsMetadataRegistry` on `main`), not in this repo's own `Sources/` — implementing it requires working in that repo (or its local checkout under `.build/checkouts/FoundationModelsMetadataRegistry`), then bumping the pinned resolution here once merged.

## Acceptance Criteria
- [ ] `idEnumGrammar(ids:)` (or its equivalent) sets a `maxItems` bound on the `ids` array.
- [ ] A unit test (in `FoundationModelsMetadataRegistryTests`) confirms the compiled grammar structurally rejects an id array longer than the bound.
- [ ] Re-run `PrefixReuseTests` on real hardware with this fix in place; confirm the second `findAPIs` call for an off-topic/no-match task no longer runs away to thousands of tokens.
- [ ] Full `swift test` in both repos remains green.
