---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m53rcwrdyxwn4bwdb14dhwm8
  text: |-
    Research done.
    - The helper rows are in Sources/FoundationModelsMultitool/MultiTool+ElicitationHelpers.swift. An ElicitationArgumentError.undecodable(reason:) becomes SandboxGlobalError.undecodableElicitationRequest(reason:usage:) in ElicitationGlobal.question(for:). Thus a new check that throws .undecodable gets the "elicit.<m>: " prefix and the usage text.
    - ElicitationHelperArguments.options() checks the type and the empty array only. It does not check duplicates.
    - ElicitationHelperSettings.countRange() checks min <= max only. It does not know the option count.
    - askNumberGlobal reads numberRange() and the integer flag. It does not check that an integer is in the range.
    - The shared test is SandboxGlobalsTests.elicitHelperArgumentErrorSendsNoRequest(argumentError:), with the rows in elicitHelperArgumentErrors. It uses elicitationArgumentErrorMessage(of:), which records an issue when the sink sees a request other than the follow-up question. A new row is the RED test for each fix.
  timestamp: 2026-10-17T01:42:36.045770+00:00
- actor: claude-code
  id: 01m53rq9r1anh6f8vpm5meb9ns
  text: |-
    Implementation landed.
    - RED: 5 new rows in elicitHelperArgumentErrors (choose ["us","us"]; chooseMany ["us","eu","us"]; chooseMany ["us"] { min: 2 }; askNumber { min: 0.2, max: 0.8, integer: true }; askNumber { min: 0.5, max: 0.5, integer: true }). The filtered run failed with "no-throw" and a sent request for each of the 5. The 16 old rows passed.
    - GREEN: ElicitationHelperArguments.options() throws "options must be different strings". countRange() became countRange(ofPicksFrom:), which throws "min is more than the count of options". numberRange() became numberSchema(), which reads the integer flag and throws "no whole number is between min and max". New static helpers checkPickable(minimum:from:) and checkHoldsWholeNumber(_:_:) use guard, as checkOrder does. The usage texts of choose, chooseMany and askNumber now state the new limits.
    - Other limits checked, no fix (not the same cause, or not decidable): chooseMany max above the option count is satisfiable; max 0 with min 0 is satisfiable (empty pick); askNumber integer with only min or only max always holds a whole number; askText pattern that matches no text (for example "a^b"), and a pattern that conflicts with format (for example format "email" with pattern "^[0-9]+$"), cannot be found without a regex emptiness check; the general elicit() form with requestedSchema is a different path (decodeRequestedSchema) and is out of the scope of this card.
  timestamp: 2026-10-17T01:48:17.025177+00:00
- actor: claude-code
  id: 01m53rqfg2the9ppq19jkmkrxe
  text: |-
    ### implement — changed
    - evidence: Sources/FoundationModelsMultitool/MultiTool+ElicitationHelpers.swift, Tests/FoundationModelsMultitoolTests/SandboxGlobalsTests.swift. RED: `swift test --filter elicitHelperArgumentErrorSendsNoRequest` exit 1, 5 new cases failed (20 issues), 16 old cases passed. GREEN: `swift test --filter 'SandboxGlobalsTests.*elicitHelper'` exit 0, 21/21 argument-error cases pass. Full `swift test` one time: exit 0, "Test run with 2437 tests in 211 suites passed".
    - next: /review
  timestamp: 2026-10-17T01:48:22.914863+00:00
- actor: claude-code
  id: 01m53rsxgzr2bjb98nagfa6qn4
  text: |-
    ### test — green
    - evidence: `swift test` ran one time. Exit code 0. Swift Testing summary: "Test run with 2437 tests in 211 suites passed after 7.367 seconds."
    - no test failed. No test was skipped.
    - one build tool line was seen: "warning: missing creator for mutated node" for the mlx-swift_Cmlx.bundle path. It comes from the build system and the mlx-swift dependency. It is not from this package code.
    - next: review.
  timestamp: 2026-10-17T01:49:42.815765+00:00
depends_on:
- 01M53FG64MDET8REKGBC9NEVN0
position_column: doing
position_ordinal: '8180'
title: 'Group D (b): throw an argument error for helper limits that no answer can satisfy'
---
Elicitation fixes from the 2026-10-16 check (elicitation-plan.md section 10), group D (b).

The elicit.* helpers accept limits that no answer can satisfy. Throw an argument error ("elicit.<m>: " plus the usage text) before the request for:
- elicit.chooseMany with min above the option count,
- elicit.askNumber({min: 0.2, max: 0.8, integer: true}) (no integer in the range),
- elicit.choose and elicit.chooseMany with duplicate options.

Each fix starts with a fixed-order test that fails before the fix (RED), then passes (GREEN). No time limit, sleep, poll or retry. One full run. #elicitation-fixes