---
depends_on:
- 01KWFNRM5VSWGD37H2YJ7CMBN2
position_column: todo
position_ordinal: '8380'
title: 'M3a: ArgumentMarshaler — JSValue ⇄ GeneratedContent'
---
## What
Per plan.md M3 (marshaling half):
- `Sources/FoundationModelsMultitool/Invocation/ArgumentMarshaler.swift`
- **In:** JS argument object (`JSValue`) → `GeneratedContent(properties:id:)` built natively from key/values (no schema, no JSON string; `init(json:)` as the alternative path where natural). Handle string/number (int vs double)/bool/null/array/nested object; omitted optionals stay absent.
- **Out:** tool `Output` → JS value: structured `Output`'s `GeneratedContent.jsonString` → `JSON.parse` into a JS object; plain-text `Output` → JS string.
- **Pin (plan Finding #4):** the exact accessor for `ToolOutput` → underlying `GeneratedContent` (DocC page 404'd) — resolve against the compiled SDK; worst case render via `PromptRepresentable` text and document it.

## Acceptance Criteria
- [ ] Round-trip: a JS object marshals to `GeneratedContent` whose `properties()` match key-for-key, and back out to an equal JS value
- [ ] Int-valued numbers marshal as integers; fractional as doubles
- [ ] Omitted optional fields are absent (not null) in the marshaled content
- [ ] Structured vs text `Output` render to object vs string respectively; the `ToolOutput` accessor pin is resolved and noted in code docs

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/ArgumentMarshalerTests.swift` — round-trips for every scalar type, arrays, nesting, null/absent optionals; structured + text output rendering
- [ ] `swift test --filter ArgumentMarshalerTests` → passes

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.