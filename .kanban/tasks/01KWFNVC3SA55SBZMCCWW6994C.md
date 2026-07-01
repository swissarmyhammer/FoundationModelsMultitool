---
depends_on:
- 01KWFNS1CDSSQ3NJXAPV1PX1XJ
- 01KWFNT7BY92073MGCF6GRQ8NH
- 01KWFNTK6Y5PAQBFECXDHPST6P
- 01KWFNTYPAEZ6Y2VPH7G0369BW
position_column: todo
position_ordinal: '8780'
title: 'M4a: MultiTool runCode execution — tools.* installed in the sandbox'
---
## What
Per plan.md M4 (execution half — no model needed):
- `Sources/FoundationModelsMultitool/MultiTool.swift` — the `runCode` core, conforming to `FoundationModels.Tool` (so it can also drop into an Apple built-in session): holds the built catalog + wrapped `[any Tool]`; per call builds a fresh interpreter, installs each tool as `tools.<name>` / `tools.<group>.<name>` closures that bridge into `ToolInvoker`, runs the snippet, renders via `ResultRenderer`.
- The v1 async bridge (plan Resolved #1): interpreter runs off the main thread; each `tools.X()` blocks the JS thread on a semaphore while the async `tool.call` runs on the cooperative pool.
- `registry.directMode()` flag on the built artifact (runCode-only surface; discovery skipped).

## Acceptance Criteria
- [ ] A snippet composing two mock tools (`map` over one's array output, calling the other per element) returns only the final value — intermediates absent from the rendered output
- [ ] `tools.github.<name>` grouped calls dispatch to the right tool
- [ ] An async (delayed) mock tool's result arrives correctly through the blocking bridge, off the main thread
- [ ] A mis-called tool surfaces ResultRenderer's repairable error text as the runCode result (not a crash)
- [ ] `registry.directMode()` produces a runCode-only surface: it reports no findAPIs affordance and its rendered surface metadata says so — asserted in MultiToolExecutionTests

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/MultiToolExecutionTests.swift` — two-mock-tool composition, grouping dispatch, async bridge (tool that `Task.sleep`s), error path, directMode surface assertion
- [ ] `swift test --filter MultiToolExecutionTests` → passes

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.