---
comments:
- actor: claude-code
  id: 01kwvwxsdyqskw3xanvbvv5zd0
  text: |-
    **Review addendum — deletion list corrections (verified against the repo 2026-07-06):**

    Add to the deletion list:
    - `Tests/FoundationModelsMultitoolTests/TurnFormatTests.swift` — a separate file from the already-listed `GuidedTurnFormatTests.swift`; tests `TolerantParseTurnFormat` and goes with `TurnFormat.swift`.
    - `Tests/FoundationModelsMultitoolTests/EvaluatorGateTests.swift` — the ungated mirror of `AgentEvaluation.swift`; imports `Evaluations` and tests the `AgentEvaluators.swift` conformers (`SearchedThenCalledEvaluator`/`CalledExpectedToolsEvaluator`/`RepairedWithinNEvaluator`) against fixture transcripts. Breaks the moment `AgentEvaluators.swift` is deleted. Same retire-or-port judgment as `AgentEvaluation.swift` applies (see `k4mj1gm`).
    - `Tests/FoundationModelsMultitoolTests/Goldens/SearchThenCallTranscript.jsonl` and `Goldens/RepairTranscript.jsonl` — checked-in old-loop turn-format transcript fixtures used by `TranscriptAssertionTests`/`EvaluatorGateTests`. NOTE: the grep acceptance criterion will NOT catch these (JSONL bodies don't contain the symbol names) — delete them explicitly. The other two goldens (`BuilderSurface.ts.txt`, `WeatherTool.ts.txt`) are renderer goldens unrelated to the loop and MUST stay.

    Correction: the listed `Fixtures/LibrarianFixtures.swift` does not exist in the repo (no such file) — the only agent fixture file is `Fixtures/MultiToolAgentFixtures.swift`; ignore that entry.

    Also check `Package.swift` for the `Evaluations` dependency once `EvaluatorGateTests`/`AgentEvaluation` are gone — if nothing else imports it, trim it.
  timestamp: 2026-07-06T14:22:13.950652+00:00
- actor: claude-code
  id: 01kxgmp19wvq90a5fxmechpxdf
  text: '/finish scoped-batch pass: skipping this task despite kanban showing it #READY. Its own gate-check acceptance criterion requires reading k4mj1gm''s go/no-go comment before any deletion — k4mj1gm recorded an explicit, well-evidenced NO-GO (real hardware, 3 independent runs, upstream-fix excuses ruled out via git merge-base verification). Per this task''s own instructions, treating it as blocked and not proceeding. Will remain untouched until a human either resolves the underlying model/prefix-reuse regression (tracked as 9hchxj6) or explicitly overrides the gate.'
  timestamp: 2026-07-14T15:42:14.332815+00:00
depends_on:
- 01KWVNWP89T9551VNK3K4MJ1GM
- 01KWVNV1NZ157PW3Y1GH6RQZ4V
- 01KWVNTEAPVS13BB8H04AVEEPP
position_column: todo
position_ordinal: '8780'
title: Delete MultiToolAgent and the old ReAct-loop machinery (TurnFormat, AgentTurn, TranscriptAnalyzer, AgentEvaluators)
---
## What
Part of the MultiToolAgent removal pivot (see board). Depends on `h6rqz4v` (callTool/DirectToolCall already retired, `MultiToolAgent` already updated to compile without it) and `4aveepp` (findAPIs already extracted, `MultiToolAgent` already updated to compile without the old `FindAPITool` shape) having landed.

**Gate check — do this FIRST, before deleting anything**: read `k4mj1gm`'s recorded go/no-go comment on the kanban board (`op: "list comments", task_id: "<k4mj1gm's id>"`). Do NOT proceed with any deletion unless that comment records either (a) a real, hardware-verified pass at or above the documented baseline (≥7/8 on the ported `SearchThenCallTests`-equivalent), or (b) an explicit, reasoned exception for proceeding anyway. If neither is present, STOP and treat this task as blocked — do not delete on the assumption that "the task is marked done in kanban" is sufficient; the gate is this comment's content, not the task's board state.

Delete:
- `Sources/FoundationModelsMultitool/Agent/MultiToolAgent.swift`
- `Sources/FoundationModelsMultitool/Agent/TurnFormat.swift` (`TolerantParseTurnFormat`, `GuidedTurnFormat`)
- `Sources/FoundationModelsMultitool/Agent/AgentTurn.swift`
- `Sources/FoundationModelsMultitool/Agent/TranscriptAnalyzer.swift`
- `Sources/FoundationModelsMultitool/Agent/AgentEvaluators.swift`
- The (by now empty, or near-empty) `Sources/FoundationModelsMultitool/Agent/` directory itself, if nothing legitimately remains in it.
- Corresponding unit tests: `Tests/FoundationModelsMultitoolTests/MultiToolAgentTests.swift`, `GuidedTurnFormatTests.swift`, `TranscriptAssertionTests.swift`, and any fixtures in `Fixtures/MultiToolAgentFixtures.swift`/`Fixtures/LibrarianFixtures.swift` that only existed to support these (check for reuse by the extracted `findAPIsTool`'s own tests from task `4aveepp` first — don't delete a fixture task `4aveepp` still needs).
- The old gated integration suite's now-superseded files, once task `k4mj1gm`'s port is confirmed complete and the old versions are no longer needed as a reference.

Trim `Sources/FoundationModelsMultitool/MultiToolConfiguration.swift`: remove `maxAgentTurns`/`maxRepairTurns` (both existed solely for `MultiToolAgent`'s loop and `TolerantParseTurnFormat`'s repair budget) — **this is a public API break**; note it as such (e.g. in a changelog or release note if this package has one, or at minimum flag it prominently in the PR/commit this task produces). Keep whatever `runCode`-sandbox-level knobs remain relevant (execution time limit, result/console caps).

Update `Sources/FoundationModelsMultitool/MultiTool.swift`/`Sources/FoundationModelsMultitool/Surface/APISurface.swift`'s doc comments that reference `MultiToolAgent`/the ReAct loop/the "librarian prefix" framing, to describe the new `LanguageModelSession`-driven design instead (or point at `findAPIsTool`'s own documentation).

## Acceptance Criteria
- [ ] `k4mj1gm`'s go/no-go comment was read and confirmed to authorize proceeding, before any file was deleted (record this confirmation as a comment on this task).
- [ ] All listed files are deleted; no remaining references to `MultiToolAgent`/`TurnFormat`/`AgentTurn`/`AgentStep`/`TranscriptAnalyzer`/`AgentEvaluators` anywhere in `Sources/`/`Tests/` (grep confirms).
- [ ] `MultiToolConfiguration`'s public surface no longer has `maxAgentTurns`/`maxRepairTurns`.
- [ ] `Package.swift`: if the library target (`FoundationModelsMultitool`) no longer needs `FoundationModelsRouter` directly (check whether `findAPIsTool`'s selection-tier backing, from task `4aveepp`, still requires it at the library level, or only at the CLI/test-target level) — trim the dependency accordingly. Likely still needed for `RoutedSession`/`RoutedLLM` types the selection tier's backing closure references; verify rather than assume.
- [ ] `swift build` and full `swift test` remain green.

## Tests
- [ ] Full `swift test` passes with no regressions.
- [ ] `grep -rn "MultiToolAgent\|TurnFormat\|AgentTurn\|TranscriptAnalyzer\|AgentEvaluators" Sources/ Tests/` returns nothing (or only historical prose explicitly marked as such).

## Workflow
- This is primarily a deletion/cleanup task — verify the full suite stays green after each file removed, rather than deleting everything in one pass and debugging a large break at the end.
