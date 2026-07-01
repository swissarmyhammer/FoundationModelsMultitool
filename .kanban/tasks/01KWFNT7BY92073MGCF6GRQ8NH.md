---
depends_on:
- 01KWFNSWN5AN993YRNR6HDY71E
position_column: todo
position_ordinal: '8480'
title: 'M3b: ToolInvoker — existential-opening native call into any Tool'
---
## What
Per plan.md M3 (invocation half):
- `Sources/FoundationModelsMultitool/Invocation/ToolInvoker.swift` — the generic invoker: `func invoke<T: Tool>(_ tool: T, content: GeneratedContent) async throws -> T.Output` reached through SE-0352 implicit existential opening from an `any Tool`.
- Pipeline: marshal (via ArgumentMarshaler) → validate — `T.Arguments(content)` throws on type/shape mismatch (free validation), plus guide checks (enum membership, numeric range, array count) for precise pre-call errors → `await tool.call(arguments:)` → render `Output` to a JS-ready value.
- Validation/call errors carry a precise, model-repairable message (consumed later by ResultRenderer).

## Acceptance Criteria
- [ ] An `any Tool` (concrete type unnamed at the call site) is invoked successfully via existential opening
- [ ] A shape-mismatched argument object fails BEFORE `call` with an error naming the offending field
- [ ] A guide violation (bad enum value / out-of-range number) fails with a message quoting the constraint
- [ ] A throwing tool's error propagates with its message intact

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/ToolInvokerTests.swift` — a mock `Tool` (fixture, `@Generable` Arguments) that records the `GeneratedContent` it received; assert field values; validation pass/fail cases; error-message content
- [ ] `swift test --filter ToolInvokerTests` → passes

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.