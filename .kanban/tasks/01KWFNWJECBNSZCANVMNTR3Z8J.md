---
depends_on:
- 01KWFNTK6Y5PAQBFECXDHPST6P
- 01KWFNVX4RFZZKEKY4C08F8V0Y
position_column: todo
position_ordinal: '8980'
title: 'M6: FindAPITool + Librarian on the flash slot'
---
## What
Per plan.md "Discovery: a prefix-cached librarian" + M6:
- `Sources/FoundationModelsMultitool/Agent/Librarian.swift` — a long-lived session over `librarian: RoutedLLM` (typically `profile.flash`) whose instructions are the full `APISurface` prefix (selection guidance + every rendered block, per the plan's "assembled prompt" example); answers a task with guided `respond(to: task, generating: FoundAPIs.self)`.
- `Sources/FoundationModelsMultitool/Agent/FoundAPIs.swift` — `@Generable struct FoundAPIs { var functions: [FoundAPI] }` / `FoundAPI { name, signature, doc, example }`.
- `Sources/FoundationModelsMultitool/Agent/FindAPITool.swift` — forwards the agent-loop `findAPIs(task)` to the librarian; splices returned blocks into the next main turn.
- Prefix reuse via the same `AgentSession` seam: root a librarian session on the prefix, `fork()` per findAPIs call (Router copies the KV cache) so the prefix is prefilled once. Verify actual KV reuse behavior in M6.5 on real hardware (plan Finding #6).
- Capacity fallback (plan Resolved #6): when the surface exceeds the librarian model's context budget, lexically pre-filter candidate blocks and LOG the cut.

## Acceptance Criteria
- [ ] The assembled librarian prefix for a fixture surface matches a golden file (guidance + all blocks, plan format)
- [ ] With a fake guided session returning a canned FoundAPIs, findAPIs results splice into the agent turn verbatim (signature/doc/example)
- [ ] Over-budget surface → pre-filter applied and the cut logged; selected relevant block survives the filter for a matching task string
- [ ] Each findAPIs call goes through a `fork()` of the prefix-rooted session (asserted via the seam)

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/LibrarianTests.swift` — prefix golden, splice-through, pre-filter + logging, fork-per-call
- [ ] `swift test --filter LibrarianTests` → passes

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.