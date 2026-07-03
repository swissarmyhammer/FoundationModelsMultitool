---
comments:
- actor: wballard
  id: 01kwkwx3efxyaes043j3mnbq4f
  text: |-
    Implementation complete via TDD.

    Research/verification before coding:
    - Read plan.md's Router integration section + M4c description in full.
    - Read TurnFormat.swift, MultiToolAgent.swift, AgentSession.swift, Librarian.swift to understand the existing seam and M4b's tolerant-parse conformer pattern.
    - Verified the real (not assumed) FoundationModelsRouter API: Grammar.jsonSchema(_:), RoutedLLM.makeGuidedSession(_:instructions:workingDirectory:), and Grammar's xgrammar-subset validation (Grammar.swift / GuidedGeneration.swift in .build/checkouts/FoundationModelsRouter). Confirmed `validateForXGrammar()` and `unsupportedSchemaKeywords` ($ref/allOf/format) are internal to the Router module — not callable from this package — so the acceptance criterion's "fixture check" alternative is the only viable path; implemented a local recursive JSON-tree walk in the test instead.
    - Verified against the real compiled Apple FoundationModels SDK (Xcode-beta MacOSX27.0 SDK) via a throwaway scratch SwiftPM package that `@Generable enum Kind: String` (payload-less) DOES compile and encodes to a plain `{"type":"string","enum":[...]}` — same shape as this codebase's existing `.anyOf` String-property convention (see ToolAPIRenderer's own documented finding that `GenerationGuide.anyOf` is String-only). Confirmed empirically that a Swift enum-with-associated-values sum type has no path to a GenerationSchema at all, which is why AgentTurn is a flat struct with a `kind` discriminant field per the task's explicit design, not a Swift enum-with-payload.
    - Verified JSON round-trip decode (`AgentTurn(GeneratedContent(json:))`) tolerates omitted optional keys, matching the established FoundAPIs/Librarian test-fixture pattern.

    Implementation:
    - New Sources/FoundationModelsMultitool/Agent/AgentTurn.swift: `@Generable struct AgentTurn` (kind: Kind enum, optional task/code/text), `asAgentStep()` cross-field validation, cached `jsonSchemaSource`, and `GuidedTurnFormat: TurnFormat` + `.guided(maxRepairTurns:)`.
    - TurnFormat.swift: added `var grammar: Grammar? { get }` protocol requirement with a `nil` default in an extension, so TolerantParseTurnFormat needed zero changes.
    - MultiToolAgent.swift: production init now branches on `resolvedTurnFormat.grammar` to build the main session via `model.makeGuidedSession(grammar, instructions:)` vs. the existing `model.makeSession(instructions:)` — the only change; `respond(to:)`'s loop body (dispatch/max-turns/error-feedback) is untouched, shared verbatim between both strategies.
    - New Tests/FoundationModelsMultitoolTests/GuidedTurnFormatTests.swift (23 tests): AgentTurn/asAgentStep unit coverage, GuidedTurnFormat parse/format/grammar/maxRepairTurns coverage, a schema-subset fixture assertion, and end-to-end scenarios on ScriptedAgentSession (findAPIs→runCode→final with zero repair turns, malformed-JSON repair-turn recovery, max-turns termination, and a .tolerantParse vs .guided strategy-switch-equivalence test).

    Verification: `swift build` exit 0; `swift test` 187/187 passed (164 prior + 23 new), zero failures, zero warnings from new code. Adversarial double-check review in progress.
  timestamp: 2026-07-03T11:47:55.983423+00:00
- actor: wballard
  id: 01kwkx7950he3e4bcwb12revat
  text: |-
    Adversarial double-check (round 1) found a real bug: AgentTurn.asAgentStep() trimmed whitespace only for the `code` field's blank-check, not `task`/`text`, so a whitespace-only findAPIs task or final answer would incorrectly pass validation (inconsistent with TolerantParseTurnFormat, which always trims). Also flagged minor duplication of the `(error as? TurnParseError)?.message ?? String(describing: error)` ternary between the two repairInstruction(for:) implementations.

    Fixed via TDD: added two new failing tests (findAPIsWithWhitespaceOnlyTaskThrows, finalWithWhitespaceOnlyTextThrows), confirmed RED, added a private `AgentTurn.isNonBlank(_:)` helper applied uniformly across all three asAgentStep() branches, confirmed GREEN. Extracted the duplicated reason-extraction ternary into `TurnParseError.reason(for:)` (TurnFormat.swift), used by both TolerantParseTurnFormat and GuidedTurnFormat's repairInstruction(for:).

    Round 2 double-check verdict: PASS — confirmed both fixes correctly applied, no new issues, fresh swift build/test run independently by the reviewer.

    Final verification (this session): swift build exit 0; swift test 189/189 passed in 15 suites (was 164 before this task, +23 GuidedTurnFormatTests initially, +2 more for the whitespace fix = 189). Zero failures, zero warnings.

    Task is done and green. Leaving in `doing` for /review per the implement workflow.
  timestamp: 2026-07-03T11:53:29.504466+00:00
depends_on:
- 01KWFNVX4RFZZKEKY4C08F8V0Y
position_column: done
position_ordinal: 8d80
title: 'M4c: Guided turn format — @Generable union via respond(to:generating:)'
---
## What
The second of the two turn formats from plan.md "Router integration" (split out of M4b, which ships the loop + tolerant parse):
- `Sources/FoundationModelsMultitool/Agent/AgentTurn.swift` — a `@Generable` union type `{ findAPIs(task) | runCode(code) | final(text) }` (discriminated by a `kind` enum field, since Generable has no sum types) that Router guided generation can constrain to.
- Wire it as the selectable `guided` turn strategy in `MultiToolAgent`: each turn goes through the `AgentSession` seam's guided path (backed by Router `respond(to:generating:)` / `.jsonSchema` grammar), so every step is parseable by construction — no repair turn needed for format errors (tool-arg errors still repair via ResultRenderer).
- Strategy selection: `MultiToolAgent(turnFormat: .guided | .tolerantParse)`; default stays `.tolerantParse` until M6.5 settles the empirical winner.

## Acceptance Criteria
- [x] With a scripted fake guided session, a full findAPIs → runCode → final scenario runs under `.guided` with zero repair turns
- [x] The derived JSON schema for `AgentTurn` stays within Router's xgrammar subset (no `$ref`/`allOf`/`format`) — asserted via `Grammar.jsonSchema` validation logic or a fixture check
- [x] Switching `turnFormat` changes only the turn strategy; loop semantics (dispatch, max-turns, error feedback) are shared code with M4b

## Tests
- [x] `Tests/FoundationModelsMultitoolTests/GuidedTurnFormatTests.swift` — guided scenario end-to-end on the fake seam, schema-subset assertion, strategy-switch equivalence
- [x] `swift test --filter GuidedTurnFormatTests` → passes

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.