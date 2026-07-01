---
depends_on:
- 01KWFNVC3SA55SBZMCCWW6994C
position_column: todo
position_ordinal: '8880'
title: 'M4b: MultiToolAgent loop — AgentSession seam + tolerant parse'
---
## What
Per plan.md "Router integration / The agent loop is ours to build" + M4: the tool loop the Router does not provide. (The guided turn format is split out to M4c; this task ships the loop with the tolerant-parse strategy.)
- `Sources/FoundationModelsMultitool/Agent/MultiToolAgent.swift` — `MultiToolAgent(registry, model: RoutedLLM, librarian: RoutedLLM?, instructions: String)`; `respond(to:) async throws -> String` runs the loop: session turn → parse `findAPIs(task)` / `runCode(code)` / final answer → dispatch → feed the result back → repeat, under a bounded max-turn count. Turn strategy is pluggable (`turnFormat`), with `.tolerantParse` implemented here and `.guided` arriving in M4c.
- `Sources/FoundationModelsMultitool/Agent/AgentSession.swift` — a minimal internal seam (protocol) the agent drives, satisfied by Router's `RoutedSession` (plain + guided paths), so unit tests use a scripted fake with zero GPU.
- Tolerant parse: ReAct-style prompted convention + lenient extractor; a parse failure triggers a bounded number of repair turns (configurable, default 1 — the knob lands in M10's `MultiToolConfiguration`) before failing the loop.
- `runCode`/`findAPIs` fixed description strings (the plan's "two tools as the main model sees them") live here as the loop's instruction block; honor `directMode()` (no findAPIs).
- Feed ResultRenderer's repairable errors back as the next turn (M5 repair loop mechanics).

## Acceptance Criteria
- [ ] With a scripted fake session emitting findAPIs → runCode → final, the agent dispatches each correctly and returns the final text
- [ ] A malformed turn triggers the configured number of repair turns (default 1) before failing the loop
- [ ] A runCode error result is fed back and a corrected second snippet succeeds (scripted)
- [ ] The loop terminates at max-turns with a typed error, never spins
- [ ] directMode: findAPIs from the model is rejected with an instructive message
- [ ] The turn-strategy seam compiles with a second strategy slot (M4c plugs in without touching loop semantics)

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/MultiToolAgentTests.swift` — scripted-fake-session scenarios above under `.tolerantParse`
- [ ] `swift test --filter MultiToolAgentTests` → passes

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.