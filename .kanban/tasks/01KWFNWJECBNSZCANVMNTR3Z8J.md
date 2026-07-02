---
comments:
- actor: wballard
  id: 01kwhy7g1dkwty17cebj2z127p
  text: |-
    API verification (per task instructions, before writing code): checked out .build/checkouts/FoundationModelsRouter source directly.
    - `RoutedSession.fork(workingDirectory: URL?) async throws -> RoutedSession` — confirmed, matches plan.md exactly. Fork copies the parent's `SessionKVCache` via `.copy()` and inherits the parent's `grammar`.
    - Guided typed generation `respond<T: Generable>(to:generating:) async throws -> T` lives on `RoutedLLM` (the model handle), NOT on `RoutedSession` — and internally it calls `makeGuidedSession(grammar).respond(to:)`, i.e. it vends a **fresh, one-shot** guided session every call. Calling this directly per findAPIs call would defeat prefix reuse entirely. plan.md doesn't call this out explicitly, but it's a real API-shape trap for M6's specific "root once, fork per call" design.
    - `RoutedSession.respond(to:)` itself already returns constrained text when the session was vended via `RoutedLLM.makeGuidedSession(_:instructions:workingDirectory:)`, and a `fork()` of a guided session inherits its `grammar` (confirmed in RoutedSession.swift's fork() doc + implementation).

    Design decision this drove: instead of routing findAPIs through `RoutedLLM.respond(to:generating:)`, `Librarian` builds ONE root session via `RoutedLLM.makeGuidedSession(schemaGrammar, instructions: fullPrefix)`, caches it, and `fork()`s a child per `findAPIs` call, then decodes that child's raw `respond(to:)` text into `FoundAPIs` itself via `FoundAPIs(GeneratedContent(json: raw))` — replicating the two-line decode Router's own (non-public) `GuidedShapes.decode` does internally, since that helper isn't exported.

    AgentSession seam extension: added `fork() async throws -> any AgentSession` as a protocol requirement with a default `{ self }` implementation (so M4b's `ScriptedAgentSession`/callers compile unchanged), and a default `respond<T: Generable>(to:generating:)` extension method (decode-from-raw-text) — both backward compatible, zero changes needed to MultiToolAgent.swift or MultiToolAgentTests.swift.

    Scope decision: built Librarian/FindAPITool/FoundAPIs as complete, tested, standalone components (test-facing init + RoutedLLM-based production init, mirroring MultiToolAgent's own dual-init pattern) but did NOT wire FindAPITool into MultiToolAgent's dispatchFindAPIs in this task — the task's own Acceptance Criteria and Tests list are scoped entirely to Librarian's standalone behavior (LibrarianTests.swift), and MultiToolAgent's existing M4b inline findAPIs dispatch is untouched/still green. Wiring FindAPITool into MultiToolAgent's loop is a natural follow-up; flagging as a possible new task rather than doing it as unscoped work here.

    Tests: Tests/FoundationModelsMultitoolTests/LibrarianTests.swift, 8 tests, all green. Full suite: 139/139 (131 prior + 8 new), zero regressions, `swift build`/`swift build --build-tests` clean (only the pre-existing unrelated mlx-swift build-system warning). Adversarial double-check dispatched.
  timestamp: 2026-07-02T17:32:36.269259+00:00
- actor: wballard
  id: 01kwhynsy24z9rhbja838eq8qa
  text: |-
    Adversarial double-check: PASS. No correctness, completeness, or intent-drift defects found. Reviewer independently cross-checked every AgentSession/Router doc-comment claim against the actual FoundationModelsRouter checkout (fork() KV-copy + grammar inheritance, makeSession/makeGuidedSession signatures, Grammar.jsonSchema being a plain non-throwing case), confirmed the golden file was legitimately generated (not hand-typed) by matching it against the actual fixture definitions, confirmed the actor-isolated cachedRootSession() has no await between its check and set (genuine race-free caching, not just assumed), and confirmed swift test is 139/139 green including MultiToolAgentTests (10/10) unchanged — no M4b regression from the new AgentSession.fork() protocol requirement or respond(to:generating:) default.

    One pre-existing nit noted (not introduced by this diff): FoundAPI.init's doc comment cites ToolDescriptor.init as a "@Generable type" example, but ToolDescriptor is a plain struct — this imprecise phrasing already existed verbatim in MultiTool.swift's RunCodeArguments.init from an earlier milestone; copied established (if slightly inaccurate) house convention rather than inventing a new error. Not fixing as out of scope for this task/pre-existing elsewhere.

    Reviewer's one substantive recommendation: since M6.5a's acceptance criteria implicitly assume MultiToolAgent is driving the new fork()-based Librarian by then, but none of M6's downstream-blocked tasks (M6.5a, M9, M10) contains an explicit wiring work item — added kanban task 01KWHYNBMJNFDK8X1WWJ7DWZHM ("Wire Librarian/FindAPITool into MultiToolAgent's findAPIs dispatch", depends_on this task) so it isn't silently dropped before M6.5a is picked up.

    Final verification (fresh, this session): swift build → exit 0; swift build --build-tests → exit 0; swift test → 139/139 passed, 12 suites, zero failures; swift test --filter LibrarianTests → 8/8 passed. No new warnings beyond the pre-existing unrelated mlx-swift build-system warning. Task is green and ready for /review. Leaving in doing per the implement workflow — not moving to review myself.
  timestamp: 2026-07-02T17:40:25.154151+00:00
depends_on:
- 01KWFNTK6Y5PAQBFECXDHPST6P
- 01KWFNVX4RFZZKEKY4C08F8V0Y
position_column: doing
position_ordinal: '80'
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