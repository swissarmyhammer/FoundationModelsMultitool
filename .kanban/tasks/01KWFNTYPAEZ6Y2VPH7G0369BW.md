---
depends_on:
- 01KWFNS1CDSSQ3NJXAPV1PX1XJ
position_column: todo
position_ordinal: '8680'
title: 'M5: ResultRenderer — caps, truncation, repairable errors'
---
## What
Per plan.md "Output: intermediates stay in the sandbox" + M5:
- `Sources/FoundationModelsMultitool/Rendering/ResultRenderer.swift` — turn an `InterpreterResult` into the text handed back to the model:
  - serialize the snippet's `return` value (JSON) under a configurable size cap, appending an explicit truncation note when cut;
  - append captured `console.log` output under its own cap;
  - on failure, render the JS/validation exception as a **repairable error** — what failed, the exact message (field/constraint from ToolInvoker), and an instruction to fix the snippet and retry.

Note (plan-M5 scope map): the *other* half of plan.md M5 — "verify the model fixes a bad tool call from the error" — is discharged by M4b (repair-loop mechanics, scripted) and M6.5a scenario 4 (real model). There is intentionally no M5b.

## Acceptance Criteria
- [ ] A return value over the cap is truncated AND carries a visible truncation note
- [ ] Console output is included, capped independently
- [ ] A ToolInvoker validation error renders with the field/constraint text intact
- [ ] A clean run renders return-value-only (no error scaffolding)

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/ResultRendererTests.swift` — cap boundary cases (under/at/over), truncation note presence, console cap, exception rendering fidelity
- [ ] `swift test --filter ResultRendererTests` → passes

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.