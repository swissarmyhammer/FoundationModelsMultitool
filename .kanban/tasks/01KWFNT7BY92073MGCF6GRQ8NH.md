---
comments:
- actor: wballard
  id: 01kwgghjgawp7mtexf0jtpw625
  text: |-
    Implemented via TDD:
    - Sources/FoundationModelsMultitool/Invocation/ToolInvoker.swift — `ToolInvoker.invoke<T: Tool>(_:content:)` invokes an `any Tool` via SE-0352 implicit existential opening. Pipeline: (1) own lightweight top-level schema-guide validation (decodes `tool.parameters`'s encoded GenerationSchema into a private `ArgumentPropertySchema`/`ArgumentsSchema`, checking required-field presence, top-level type match, and enum/range/count guide violations — deliberately scoped to the Arguments struct's immediate top-level properties only, not recursing into nested `@Generable` fields, unlike `ToolAPIRenderer.SchemaNode`'s full `$ref`-resolving walk) → (2) `T.Arguments(content)`'s own throwing init as a second line of defense → (3) `await tool.call(arguments:)`, whose thrown error is never wrapped (propagates with message intact).
    - `ToolInvokerError` (kind: missingRequiredField / typeMismatch / guideViolation / invalidArguments, field, message) — pre-call-only; tool's own errors pass through unchanged.
    - Tests/FoundationModelsMultitoolTests/ToolInvokerTests.swift (10 tests) + Fixtures/ToolInvokerFixtures.swift (RecordingTool w/ OSAllocatedUnfairLock capture matching JSCInterpreterTests' pattern, ThrowingTool, RangedTool/CountedTool wrapping the existing RangedIntegerArgument/CountedArrayArgument fixtures from ToolAPIRendererFixtures.swift — reused rather than re-declared).

    TDD: watched all 10 new tests fail (cannot find ToolInvoker/ToolInvokerError in scope) before writing ToolInvoker.swift; full implementation passed all 10 on first attempt, no iteration needed.

    `swift build`: clean, 0 warnings from new code. `swift test`: 74/74 passing (was 64/64 before this task; +10 new ToolInvokerTests).

    Dispatched double-check adversarial review before handoff; will record its verdict here.
  timestamp: 2026-07-02T04:14:11.978547+00:00
- actor: wballard
  id: 01kwgh2gxtvnhp0absg14maeqr
  text: |-
    Double-check adversarial review (round 1): REVISE. Genuine gap found — a required top-level argument with an explicit JSON `null` value silently skipped both type and guide validation (deferring entirely to `T.Arguments(content)`'s own decoding, whose resulting `.invalidArguments` error never set `field`, undermining AC2's "names the offending field"). Also flagged zero test coverage for the `.invalidArguments` Kind case.

    Fixed: `validate` now only bypasses type/guide checks for a null value on an *optional* field (`if value.kind == .null, !required.contains(field) { continue }`); a required field's explicit null now flows into `validateType`, which reports `.typeMismatch` naming the field (no schema type ever matches `.null`, so this is a clean, deterministic catch — no new error kind needed). Added two tests: `explicitNullForRequiredFieldFailsBeforeCallNamingField` and `nestedElementTypeMismatchCaughtByArgumentsDecoding` (the latter genuinely exercises the `.invalidArguments` fallback layer via CountedTool's `[Int]` decode rejecting a string element that the top-level array-count guide can't see).

    Double-check round 2 (re-check, bounded per really-done contract): PASS. Confirmed fix logic, doc-comment accuracy, non-vacuous new tests, and a fresh `swift test` run.

    Final verification: `swift test` → 76/76 passing (was 64/64 before this task started). Clean `swift build`, no new warnings.

    All 4 acceptance criteria met and test-covered; all "Tests" checklist items done. Leaving in `doing` for /review per the implement workflow.
  timestamp: 2026-07-02T04:23:27.418087+00:00
depends_on:
- 01KWFNSWN5AN993YRNR6HDY71E
position_column: doing
position_ordinal: '80'
title: 'M3b: ToolInvoker — existential-opening native call into any Tool'
---
## What
Per plan.md M3 (invocation half):
- `Sources/FoundationModelsMultitool/Invocation/ToolInvoker.swift` — the generic invoker: `func invoke<T: Tool>(_ tool: T, content: GeneratedContent) async throws -> T.Output` reached through SE-0352 implicit existential opening from an `any Tool`.
- Pipeline: marshal (via ArgumentMarshaler) → validate — `T.Arguments(content)` throws on type/shape mismatch (free validation), plus guide checks (enum membership, numeric range, array count) for precise pre-call errors → `await tool.call(arguments:)` → render `Output` to a JS-ready value.
- Validation/call errors carry a precise, model-repairable message (consumed later by ResultRenderer).

## Acceptance Criteria
- [x] An `any Tool` (concrete type unnamed at the call site) is invoked successfully via existential opening
- [x] A shape-mismatched argument object fails BEFORE `call` with an error naming the offending field
- [x] A guide violation (bad enum value / out-of-range number) fails with a message quoting the constraint
- [x] A throwing tool's error propagates with its message intact

## Tests
- [x] `Tests/FoundationModelsMultitoolTests/ToolInvokerTests.swift` — a mock `Tool` (fixture, `@Generable` Arguments) that records the `GeneratedContent` it received; assert field values; validation pass/fail cases; error-message content
- [x] `swift test --filter ToolInvokerTests` → passes

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.