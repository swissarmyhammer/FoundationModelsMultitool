---
depends_on:
- 01KWFNT7BY92073MGCF6GRQ8NH
- 01KWFNVX4RFZZKEKY4C08F8V0Y
position_column: todo
position_ordinal: '9080'
title: 'Escape hatch: guided direct tool call (schema-valid args)'
---
## What
Per plan.md "Escape hatch — keep the schema-valid-args guarantee" + Resolved #8 (finding: promised in v1 but previously untasked): a directly-placed tool whose arguments stay schema-valid without wrapping it in the snippet surface.
- `Sources/FoundationModelsMultitool/Agent/DirectToolCall.swift` — for a tool registered as *direct* (e.g. `Builder.addDirectTool(_:)` or `MultiToolAgent(directTools:)`): encode its `parameters: GenerationSchema` to a JSON Schema string (reusing M2's encode path), constrain a Router turn with `Grammar.jsonSchema` via `respond(to:matching:)`, build `GeneratedContent(json:)` from the schema-valid output, and invoke through `ToolInvoker` — arguments xgrammar-constrained end to end.
- Surface direct tools to the model as a third loop affordance (`callTool(name, args)` description string alongside runCode/findAPIs), dispatched by `MultiToolAgent`.
- Document in the README escape-hatch section (consumed by M10) that this is the schema-valid path on a Router model, and that Apple's token-level tool loop applies only in a built-in `SystemLanguageModel` session.

## Acceptance Criteria
- [ ] A direct tool's derived grammar rejects out-of-schema output (validated via `Grammar` xgrammar-subset validation on the derived schema)
- [ ] With a scripted fake guided session returning schema-valid args JSON, the direct call invokes the tool with correctly-typed `Arguments`
- [ ] A wrapped tool and a direct tool coexist in one agent: snippet path and direct path both dispatch correctly in a scripted scenario
- [ ] Unknown direct-tool name from the model → repairable error, not a crash

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/DirectToolCallTests.swift` — the four criteria above with mock tools + fake seam
- [ ] `swift test --filter DirectToolCallTests` → passes

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.