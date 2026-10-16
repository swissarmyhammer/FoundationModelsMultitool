---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m51aeas0a8jveq0cshf65c5y
  text: |-
    ### implement — changed
    - Source: `renderElicitationResponse` (MultiTool+SandboxGlobals.swift) now returns `{ action, content, reason }`. `reason` is `response.reason` or `null`. The doc comments of `renderElicitationResponse` and `raiseElicitation` tell the three keys.
    - docs("globals"): `declare type ElicitationAnswer = { action: "accept" | "decline" | "cancel"; content: object | null; reason: string | null };`. The elicit `@returns` tells what `reason` holds. The two example reasons are spliced from `RunPlane.runCancelledReason` and `ElicitationRequestedSchema.invalidAnswerReasonPrefix` (FoundationModelsExtras), so that the text and the source cannot drift apart. The rendered text is the same as the plan text.
    - `declaredFields(of:in:)` reads the literal union correctly. Proof: the parity test "the globals page declares the exact fields an elicitation answer really carries" passes with the new type. No change to the parser.
    - Tests (SandboxGlobalsTests.swift): a parameterized test "a decline or a cancel with a reason gives that reason to the snippet" (decline "not now", cancel "run cancelled") and "an accepted elicitation gives a null reason to the snippet". Each snippet returns the sorted keys and the three fields. Fixed order with ScriptedElicitationSink. No time wait.
    - Discovery: with the parameter type `ElicitationResponse` and the label `_`, the @Test macro expansion did not compile ("expected member name or initializer call after type name"). Router has `typealias ElicitationResponse`. The type `FoundationModelsExtras.ElicitationResponse` with a labeled parameter compiles.
    - RED (source not changed, one filtered run): 3 issues, all `Expectation failed: answer == expected`, no hang. decline got keys [action, content], reason nil; cancel the same; accept got keys [action, content] (it also fails, on the key set).
    - GREEN (one filtered run, new tests + parity test): 3 tests passed.
    - Full run (one): `swift test` exit 0, "Test run with 2404 tests in 210 suites passed". Only warning line: the known SwiftPM note "missing creator for mutated node … mlx-swift_Cmlx.bundle". No compiler warning.
  timestamp: 2026-10-16T03:00:14.240309+00:00
position_column: done
position_ordinal: fffff880
title: Return reason to the snippet from renderElicitationResponse (elicitation-plan task 44)
---
`renderElicitationResponse` (MultiTool+SandboxGlobals.swift, about line 657) returns only `{ action, content }`. The plan (section 2, "Result shape") says: all forms and helpers return `{ action, content, reason }`.

Do:
- Return `{ action, content, reason }`. `reason` is `null` when the response has no reason.
- Update the elicit docs and the type `ElicitationAnswer` in docs("globals").
- A fixed-order test shows that a decline and a cancel with a reason give the reason to the snippet, and that an accept gives `reason: null`. The test fails on the old code as a check.
- One full run. Push when green.

#elicitation-phase-3