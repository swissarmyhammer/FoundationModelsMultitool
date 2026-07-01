---
depends_on:
- 01KWFNRM5VSWGD37H2YJ7CMBN2
position_column: todo
position_ordinal: '8280'
title: 'M2: ToolAPIRenderer — GenerationSchema → TS declaration + JSDoc'
---
## What
Per plan.md M2: derive each tool's TypeScript-style declaration + JSDoc doc comment purely from its public surface.
- `Sources/FoundationModelsMultitool/Surface/ToolAPIRenderer.swift` — encode `tool.parameters: GenerationSchema` with `JSONEncoder` (encode is the read path; there is no field-enumeration API), transliterate the JSON Schema to a TS signature per the plan's type-mapping table (object/string/number/boolean/array/enum/nested/optional/`any`-widened-with-log), and render the doc comment per the doc-mapping table (`description` → summary, per-property guides → `@param`, enum/range/pattern/count/default → prose, `@returns`, auto `@example`).
- `Sources/FoundationModelsMultitool/Surface/ToolDescriptor.swift` — name, TS declaration, doc text, example, source. One generator feeds runtime binding, librarian prefix, and help()/docs().
- Object (named) parameters always — `tools.name({ field: … })`, never positional.
- Completeness contract: throw a descriptive error rather than emit a lossy stub.
- **Pin (Apple-encoder parity, plan Finding #3):** a test asserts Apple's own `GenerationSchema` encoder emits the expected JSON-Schema shape (`type/properties/required`, optional as `["T","null"]`, enum as `{"type":"string","enum":[…]}`) for fixture `@Generable` types.

## Acceptance Criteria
- [ ] The plan's worked `WeatherTool` example renders byte-identical to the golden file
- [ ] Every row of the type-mapping and doc-mapping tables is covered by at least one corpus case
- [ ] Unrenderable schema element → widened `any` + logged, or thrown per contract (per-table behavior)
- [ ] Apple-encoder parity test passes (or documents the divergence and the renderer handles it)

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/ToolAPIRendererTests.swift` — table-driven over a `GenerationSchema` corpus built from fixture `@Generable` types
- [ ] `Tests/FoundationModelsMultitoolTests/Goldens/*.ts.txt` — golden files pinning the rendered surface
- [ ] `swift test --filter ToolAPIRendererTests` → passes

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.