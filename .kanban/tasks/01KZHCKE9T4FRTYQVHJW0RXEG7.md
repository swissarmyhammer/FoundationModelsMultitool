---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01kzk5ww8662y3sb34q2rbkytf
  text: |-
    Research: grepped the tree for both summary phrases before settling on the shape, as the card asks.

    `The snippet failed` / `The snippet timed out` as full phrases: exactly one test site, the one the card names. But the grep for the *fragment* found two more, and they are the same cause:

    - `Tests/FoundationModelsMultitoolTests/HardeningTests.swift:149` and `:183` — `#expect(output.contains("timed out"))`. `output` is `ResultRenderer.render(...)` text and "timed out" appears in it only inside the `.timeout` summary, so both are hand-written copies of shipped wording. They do not go stale silently the way the fixture does — they fail loudly — but criterion 1 says no test hand-writes the summary text, and these do.

    One more hit, deliberately left alone: `Tests/FoundationModelsMultitoolTests/SandboxGlobalsTests.swift:658` says "means the snippet failed and the renderer produced repairable-error text instead" in a doc comment. That is English prose describing behaviour, lowercase mid-sentence, not a literal standing in for output. It cannot go stale in the compiles-and-passes sense, and rewriting prose that happens to share words would be churn. Flagging it here so review can overrule.

    Shape that covers all three sites: the fixture cannot help HardeningTests, because those tests never know the interpreter's own message and so cannot call `render(_:)` for a whole-string comparison. So the summary got the same treatment `^esyyqjv` gave `closingLine` — one internal home the shipped renderer and both test targets read.
  timestamp: 2026-08-09T11:52:56.838100+00:00
- actor: claude-code
  id: 01kzk5xa22nb6zgwwz5w2r184n
  text: |-
    Both controls run and restored. Evidence, not assumption.

    **Control 1 — does the test still fail when `returnedValues(in:)` scrapes non-JSON?** Yes. Scratch edit to `NativeTranscript.returnedValues(in:)`: in the JSON-parse-failure `else` branch, `values.formUnion(text(of: output).split(separator: " ").map(String.init))` before the `return`. The assertion that fired is the test's only one, `ScenarioFailureModeTests.swift:322:9` — `#expect(NativeTranscript.returnedValues(in: transcript).isEmpty)` — reporting `["not", "failed:", "is", "call", "a", "the", "and", "tools.getTrip", "again.", "function\n\nFix", "runCode", "snippet", "TypeError:", "The"]`, i.e. the rendered error scraped into tokens. `swift test --filter aRepairableErrorOutputContributesNothing`: 1 test, 1 issue, failed. Scratch edit reverted; `git status` shows `NativeTranscript.swift` unmodified.

    Aside worth knowing for the next agent: `swift test --filter` matches the *function* name, not the `@Test` display name. Filtering on the display string prints "No matching test cases were run" and still exits 0 — a silent no-op that reads like a pass.

    **Control 2 — does rewording a summary keep the suite green?** Run twice.

    - Before the HardeningTests fix, with both summaries reworded to "That snippet did not run"/"That snippet ran too long": **red**, 2 issues, both `output.contains("timed out")` at `HardeningTests.swift:149` and `:183`. That is what put those two sites on the list.
    - After the fix, same reword: **green** — 309 tests / 24 suites and 49 tests / 8 suites, zero issues. Criterion 3's first branch, which is the better of the two it allows.

    Wording restored to "The snippet failed"/"The snippet timed out"; the rendered string is byte-identical to before the change.

    Flake ^9qtvkvg (`SuspendedContextTests.swift:187`) did not fire in any of the five full runs.
  timestamp: 2026-08-09T11:53:10.978696+00:00
- actor: claude-code
  id: 01kzk5xn2nmx4tq0m4a5ddjsww
  text: |-
    ### implement — changed
    - evidence: 3 files — Sources/FoundationModelsMultitool/Rendering/ResultRenderer.swift, Tests/FoundationModelsMultitoolIntegrationTests/ScenarioFailureModeTests.swift, Tests/FoundationModelsMultitoolTests/HardeningTests.swift. `swift build --build-tests` clean; `swift test` (ungated) 309 tests / 24 suites + 49 tests / 8 suites, zero failures. Only warning is SwiftPM's pre-existing "missing creator for mutated node" on the mlx-swift bundle, present on the untouched tree. No MULTITOOL_INTEGRATION run. eventplan.md untouched at ae2085ac841495d46c03b81d11c068975fa727b2.
    - what changed: `ScenarioFailureModeTests`'s synthetic segment now renders — `ResultRenderer.render(InterpreterError(kind: .exception, message: "TypeError: tools.getTrip is not a function"))` — dropping the summary copy, the `": "`/`"\n\n"` separators and the closing-line interpolation together. The summary switch moved out of `render(_:hint:directive:)` into `InterpreterError.Kind.repairableErrorSummary`, internal, documented on the same terms as `RepairDirective.closingLine`; `render` reads it, and both `HardeningTests` sites read it instead of copying `"timed out"`. The rendered text is byte-identical, so no shipped behaviour change. The `closingLine` doc comment lost its now-false sentence about the fixture hand-writing the `.exception` summary and framing.
    - all four acceptance criteria checked, each verified rather than assumed — see the two comments above.
    - next: /review
  timestamp: 2026-08-09T11:53:22.261733+00:00
- actor: claude-code
  id: 01kzk7344ycptr926fbm6sq6wc
  text: |-
    ### review — findings
    - evidence: 3 findings — Sources/FoundationModelsMultitool/Rendering/ResultRenderer.swift:118, :134, :141. Engine `review sha HEAD~1..HEAD` returned 1 confirmed finding (:141), 1 refuted, 9 attempted, 0 failed. Two added by reviewer verification of the four questions the caller asked to be judged. Ungated only: `swift build` clean; `swift test` green — 309 tests / 24 suites and 49 tests / 8 suites, zero failures. Gated suites skipped as expected, no MULTITOOL_INTEGRATION run. Flake ^9qtvkvg did not fire. eventplan.md untouched at ae2085ac841495d46c03b81d11c068975fa727b2.

    **Q1 — is `repairableErrorSummary` the right home, correctly scoped?** Yes, except for its doc comment (finding :134). `InterpreterError.Kind` is `public` (`Interpreter/Interpreter.swift:201`) and the new member is `internal`, so the shipped surface did not grow. Mixed public-type/internal-member is already the prevailing pattern in the receiving file — `RepairDirective.closingLine` (:118) and `ResultRendererLimits.defaultReturnValueCharacterLimit`/`defaultConsoleCharacterLimit` (:42/:51) — and :37-41 already documents that rationale. The extension sits in `Rendering/`, so `Interpreter.swift` does not acquire a rendering concern. A test-only extension was **not** the better shape: `FoundationModelsMultitoolTests` and `FoundationModelsMultitoolIntegrationTests` are separate, mutually independent modules (`Package.swift:187`, `:214`) and there is no test-support target and no `*TestSupport*`/`*Fixture*` file under `Sources/`, so a test-only extension would have to be written once per target — reintroducing the duplication this card exists to remove. Observation, not a finding: this is the repo's first cross-layer extension of an interpreter type from the rendering layer, and the one cross-directory extension precedent (`Surface/APISurface+SearchableMetadata.swift:20`) uses a `Type+Protocol.swift` filename.

    **Q2 — did the sweep close the cause or only three instances?** It closed the cause. The remaining list is empty, proven by command rather than by reading. Enumerated every string literal `ResultRenderer.swift` can emit, then fixed-string-searched `Tests/` for each:

    ```
    for s in "The snippet failed" "The snippet timed out" "snippet failed" "timed out" \
             "Fix the snippet and call runCode again." \
             "Call findAPIs to get the real function names" \
             "then write the snippet against those paths." \
             "Console output:" "[truncated:" "exceeding the" "showing the first" "-character cap"
    do rg -n -F -e "$s" Tests/; done
    ```

    Every pattern returns no hits except two, and neither is a literal standing in for output: `SandboxGlobalsTests.swift:658` (see Q3) and `Console output:` at `Support/NativeTranscript.swift:121` (a `///` doc comment) and `ResultRendererTests.swift:86` (a `// MARK: -` section header). Separators are covered too — `rg -n -F 'failed: ' Tests/` returns nothing, and the only synthetic transcript that built a frame now calls `ResultRenderer.render(...)` (`ScenarioFailureModeTests.swift:309`). Cross-check on the other direction: all seven `closingLine` references in `Tests/` read the shipped constant, and both `repairableErrorSummary` references read the shipped member.

    **Q3 — `SandboxGlobalsTests.swift:658`.** Confirmed, not overruled. It is a `- Throws:` clause in the doc comment of the private test helper `decode(_:from:)`, whose entire body is `try JSONDecoder().decode(type, from: Data(output.utf8))` — there is no string comparison anywhere in it. "means the snippet failed" is lowercase mid-sentence English describing the failure mode, not a copy of the shipped `.exception` summary, and it stays accurate under any reword. Independently, the review skill's blanket exception drops any finding whose subject is re-docstringing test code that already existed.

    **Q4 — the deleted `closingLine` doc sentence.** Deletion correct. The removed text asserted that `ScenarioFailureModeTests`'s synthetic segment hand-writes the `.exception` summary and the `": "`/`"\n\n"` framing; this commit removed exactly that, so the sentence became false and keeping it would have described the tree as it no longer is. Every remaining sentence of that doc comment holds: "the only place the text is written" — `rg` finds both closing-line literals only at `:121` and `:123-124`; "Both test targets read it here" — true for `closingLine`, seven call sites across both targets; `internal` rationale — `closingLine` has exactly one non-doc reference in `Sources/`, at `:217` inside `render(_:hint:directive:)`, and none from the `multitool-cli` module. The one nuance: "every synthetic transcript that stands in for a rendered error" is now satisfied transitively, since the fixture reaches `closingLine` through `render(...)` rather than reading the member — the claim stays true, so it is not recorded as a finding. The parallel sentence copied onto the new member is a different matter and is finding :134.

    Byte-identical output independently verified: `InterpreterError.Kind` has exactly two cases, both map to the same strings before and after, neither switch has a `default:`, and Swift `String` `+` at the `"\n\n"` boundary concatenates without a separator.

    Note for the next agent: `{"op": "check sha"}` diagnostics report two phantom errors — "Value of type 'InterpreterError.Kind' has no member 'repairableErrorSummary'" at `HardeningTests.swift:148`/`:182`. They are stale-index artifacts; sourcekit-lsp is not installed in this workspace and both targets compile and run green. Do not chase them.

    - next: /implement ^w0rxeg7 to close the three findings, then /review ^w0rxeg7 again.
  timestamp: 2026-08-09T12:13:50.110407+00:00
- actor: claude-code
  id: 01kzk74ezfstrccz32v0hq9njd
  text: |-
    ### finish iteration 1 — findings

    - implement: changed — 3 files (ResultRenderer.swift, ScenarioFailureModeTests.swift, HardeningTests.swift)
    - test: green — ungated `swift test` run 3× independently; each 309 tests / 24 suites + 49 tests / 8 suites, zero failures; flake ^9qtvkvg did not fire in any run
    - commit: 688dd0b
    - review: findings — Sources/FoundationModelsMultitool/Rendering/ResultRenderer.swift:118, :134, :141

    Two distinct causes in the findings, and they should be closed as causes rather than as three lines:

    1. **Switch over a known enum set whose arms differ only in string constants** — `:141` (`repairableErrorSummary`) is the engine's instance, `:118` (`RepairDirective.closingLine`) is the same shape in the same file. Both want a data table.
    2. **A doc comment claiming more than the code supports** — `:134` says "Both test targets read it here through `@testable import`". Only one does (`HardeningTests.swift:149`, `:183`); the integration target has no reference to `repairableErrorSummary` and reaches the wording through the public `render(_:)`. The sentence was copied from `closingLine`, where it is true, into a place where it is not.

    Worth stating plainly: iteration 1 **deleted one false doc sentence and introduced another**. That is the same class that ran `^hkd0w0c` to seven review passes, where a fix repeatedly planted the next finding. The lesson recorded there applies here — do not spot-fix the cited line. Audit every `///` in `ResultRenderer.swift` against "says only what the code guarantees", and every switch in the file against the data-table rule, and close both lists in one commit.

    Review also confirmed the parts that are right: rendered output is provably byte-identical (two enum cases, same strings both sides, no `default:`); `internal` on a `public` type matches the file's prevailing pattern and did not grow the shipped surface; a test-only extension would have been worse, since the two test targets are independent modules with no shared support target and would each need their own copy. The `SandboxGlobalsTests.swift:658` judgement was confirmed, not overruled — it is a `- Throws:` clause on a helper that does no string comparison.

    Caution for the next agent: `check sha` reports two phantom "no member 'repairableErrorSummary'" errors at `HardeningTests.swift:148`/`:182`. Stale-index artifacts — sourcekit-lsp is not installed here and both targets compile green. Do not chase them.
  timestamp: 2026-08-09T12:14:33.967285+00:00
- actor: claude-code
  id: 01kzk7b5vddbjfjb67v8e5p28v
  text: |-
    ### BLOCKER — conflict on findings :118 and :141, not resolved by me

    Per the `/finish` scope rule, a true conflict is recorded on the task and left for a human. I am not resolving it, not editing the validator, and not closing the card.

    **The findings.** Both ask that a `switch` over a known enum set whose arms differ only in string constants become a data table — `static let errorSummaries: [Kind: String] = [...]`, read as `Self.errorSummaries[self]`. The two sites are `RepairDirective.closingLine` (:118) and `InterpreterError.Kind.repairableErrorSummary` (:141). That list is complete and grep-provable: `grep -n "switch " ResultRenderer.swift` returns exactly `:119` and `:142`, and they are the only pure constant-mapping switches in `Sources/` (the one at `MultiTool+SandboxGlobals.swift:725` binds associated values and could not be a dictionary regardless).

    **Why I did not make the change.** A dictionary subscript returns `String?`. Both enums — `InterpreterError.Kind` at `Interpreter.swift:201` and `RepairDirective` at `ResultRenderer.swift:100` — are `public`, neither is `CaseIterable`, neither has a raw value. So:

    - **Today:** adding a third case to either public enum is a **compile error** at both sites until the new text is supplied. The switch has no `default:`, so the compiler enforces totality.
    - **After the change:** adding a case compiles clean. `Self.errorSummaries[newCase]` returns `nil`, and the accessor must either force-unwrap (crash at render time) or fall back to a default (ship empty or placeholder repair text to the model).

    The text in question is model-facing repair wording. Silent drift between the wording and what the product emits is the exact defect class this card was filed to remove. Converting to a dictionary would reintroduce that class through a different door, and it collides with the standing constraint that assertions and safety are never weakened — a retarget, never a relaxation.

    **Why this is a rule conflict and not my preference.** In Swift, an exhaustive `switch` with expression-bodied arms IS the compiler-checked data table; there is no control flow in it to remove. The generic "data table over control flow" heuristic is right in languages without exhaustive enum matching. Note also what the findings section already records: `tool rule 'code-hygiene/dead-code-swift' is unavailable (tool missing: exited with exit status: 1); prompt rule 'dead-code' ran instead` — the language-aware rule did not run, and the generic fallback did.

    **What a human needs to rule on.** Either (a) the rule should exempt exhaustive Swift enum switches whose arms are constant expressions, or (b) the conversion is wanted anyway and the loss of compile-time totality is acceptable — in which case say which fallback is wanted for the unreachable branch. I will implement whichever is chosen. I have not touched the validator.

    **State.** Finding :134 is fixed and closed in `90603d7`, with the whole doc-comment class swept rather than the cited line. Findings :118 and :141 remain open, so the card stays in `review`. Ungated suite green, 309/24 + 49/8, on two consecutive runs.
  timestamp: 2026-08-09T12:18:13.997046+00:00
- actor: claude-code
  id: 01kzk7bggc52d7msyzn1w4yhs8
  text: |-
    ### finish iteration 2 — stuck

    - implement: changed — 1 file (Sources/FoundationModelsMultitool/Rendering/ResultRenderer.swift), doc comment only
    - test: green — ungated `swift test` on two consecutive runs, each 309 tests / 24 suites + 49 tests / 8 suites, zero failures; flake ^9qtvkvg did not fire
    - commit: 90603d7
    - review: not run this iteration — two findings remain open by design, see the BLOCKER comment above

    Closed: `:134`, and the whole doc-comment class with it. Every verifiable claim in the file was checked against a grep rather than re-read — `closingLine`'s "both test targets" claim (TRUE, 5 unit + 2 integration) and all four "only place the text is written" claims (TRUE, each literal appears exactly once across `Sources/` and `Tests/`) were confirmed and left alone.

    Open: `:118` and `:141`, recorded as a **conflict** rather than worked. Converting either exhaustive `switch` to a `[Kind: String]` data table trades a compile error for a runtime `nil` on both `public` enums, which would let a future case ship empty or placeholder repair text to the model. That is the defect class this card exists to remove. A human rules; I have not edited the validator and have not closed the card.

    Card stays in `review`. Loop stopped here rather than at the 3-round guardrail — a conflict is stopped on sight, not iterated against.
  timestamp: 2026-08-09T12:18:24.908159+00:00
- actor: claude-code
  id: 01kzk7c8j52ewretzywazz63hf
  text: |-
    ### review — sweep addendum (hint-text axis)

    Supplements the Q2 evidence in the previous comment. An independent exhaustive sweep reached the same verdict — **zero remaining sites where a hand-written literal stands in for `ResultRenderer` output** — and additionally covered one axis the first sweep did not: the `UnknownToolHint` text that `render(_:hint:directive:)` splices in through its `hint:` parameter (`MultiTool.swift:555-557`). Recording the result so a later pass does not re-open it.

    `UnknownToolHint` literals (`UnknownToolHint.swift:238-261`) ARE hand-copied in pre-existing tests:

    - `Tests/FoundationModelsMultitoolTests/UnknownToolHintTests.swift:69`, `:87`, `:132`, `:152`, `:193`, `:216` — `output.contains("tools.<x> does not exist")`
    - `Tests/FoundationModelsMultitoolTests/UnknownToolHintTests.swift:248`, `:375` — `!output.contains("does not exist")`
    - `Tests/FoundationModelsMultitoolTests/SampleSnippetTests.swift:149` — `prompts[1].contains("does not exist")`
    - `Tests/FoundationModelsMultitoolTests/SuspendedContextTests.swift:158` — `refused.contains("Too many runCode snippets are running at once")`, a copy of `MultiTool+Elevation.swift:144`'s `liveContextCapError`

    **No finding is recorded for any of these, for three independent reasons.** First, the review skill's blanket exception forbids raising, recording, or relaying any finding whose subject is changing test code that already existed; every one of these files is pre-existing and untouched by `688dd0b`. Second, none is `ResultRenderer`'s own wording — the hint is owned by `UnknownToolHint` and the cap message by `MultiTool+Elevation`, both outside this card's subject. Third, and unlike the defect this card exists to remove, the positive assertions sit on real product output, so a reword fails them loudly instead of leaving them compiling and passing against text nothing emits. The two negative assertions (`UnknownToolHintTests.swift:248`, `:375`) would pass hollowly after a reword, but they are still pre-existing test code and still not `ResultRenderer` wording.

    Two corrections to the record while it is in front of us. `HardeningTests.swift` lives only in the unit target at `Tests/FoundationModelsMultitoolTests/HardeningTests.swift`; there is no copy under `Tests/FoundationModelsMultitoolIntegrationTests/`. And `rg -n -F -- "call runCode again" Tests/` does return one hit, `MultiToolExecutionTests.swift:295`, but it asserts against the runCode **tool description** (`MultiTool.swift:361`, "and call runCode again immediately"), not renderer output — a different shipped string that merely shares a phrase with `closingLine`.

    Also confirmed independently: `rg -n -F '\n\n' Tests/` returns no matches, so no test hand-builds the renderer's separator framing.

    - next: unchanged — /implement ^w0rxeg7 to close the three findings at ResultRenderer.swift:118, :134, :141.
  timestamp: 2026-08-09T12:18:49.541065+00:00
- actor: claude-code
  id: 01kzk9dnfb8ppgdgcq3h6kf5qe
  text: |-
    ### RULING (human, 2026-08-09) — the switch is correct, the rule was wrong

    The conflict recorded above is resolved in favour of the code. Findings `:118` and `:141` are overruled, and the rule that produced them has been corrected rather than worked around. No code changed in this repo for either finding.

    **Rule corrected:** `/Users/wballard/.validators/code-hygiene/rules/data-driven.md`, a new fourth carve-out:

    > **A match the compiler already checks for exhaustiveness.** Where the language verifies at compile time that a match over a closed type covers every case — a Swift `switch` over an enum with no `default:`, a Rust `match` over an enum with no `_` arm, an exhaustive Kotlin `when` over a sealed class — the match *is* the table, and the compiler enforces that every row exists. A map keyed by that type is not an improvement: its lookup returns an optional, so adding a case compiles clean and produces a missing row at runtime instead of failing the build. Flagging here trades a compile error for a silent hole. Flag only when the replacement lookup can be made total without one — the type carries a raw value, or the map is built through a constructor the compiler checks covers every case.

    Written to match the rule set's existing convention that a carve-out is a structural fact readable off the definition, not a judgement the reviewer makes.

    **Verified, not assumed.** `review file Sources/FoundationModelsMultitool/Rendering/ResultRenderer.swift --validators code-hygiene` after the edit: **0 findings, 2 refuted, 9 attempted, 0 failed**. The same two sites that were confirmed findings before the edit are now refuted by the carve-out. The rule still runs; it just no longer fires here.

    The carve-out is deliberately language-general rather than a `data-driven-swift` variant, because Rust `match`, Kotlin sealed `when` and Scala sealed traits have the identical property. The rule directory does contain per-language variants (`magic-numbers-swift`, `complexity-swift`, …), but those exist to bind a language-specific *tool*; this is a property of exhaustiveness checking itself.

    **Two things to know about the change.** `/Users/wballard/.validators` is **not** a git repository, so this edit is live and unversioned — there is no history or rollback for it. And it sits in the `user` source layer, so it applies to every repo on this machine, not only this one.

    **Card state.** All three findings are now closed: `:134` fixed in `90603d7`, `:118` and `:141` overruled here. Zero unchecked items remain. Ungated suite green, 309/24 + 49/8.
  timestamp: 2026-08-09T12:54:32.683347+00:00
position_column: done
position_ordinal: b980
title: '[Multitool] ResultRenderer''s "The snippet failed" summary is hand-copied into the synthetic transcript fixture'
---
Discovered while implementing `^esyyqjv`, which deduplicated `RepairDirective.repairSnippet.closingLine` out of nine test literals. The same fixture carries a second copy of shipped wording that the card did not cover.

`ResultRenderer.render(_:hint:directive:)` builds a repairable error as `"<summary>: <description>\n\n<hint><closingLine>"`, where `summary` comes from a `switch` on `error.kind`:

```
Sources/FoundationModelsMultitool/Rendering/ResultRenderer.swift
case .exception: "The snippet failed"
case .timeout: "The snippet timed out"
```

The synthetic transcript in `Tests/FoundationModelsMultitoolIntegrationTests/ScenarioFailureModeTests.swift` (`aRepairableErrorOutputContributesNothing`) hand-writes that prefix:

```swift
content: "The snippet failed: TypeError: tools.getTrip is not a "
    + "function\n\n\(RepairDirective.repairSnippet.closingLine)"
```

The closing line is now interpolated, so it follows a reword. `"The snippet failed: "` does not. This is the same silent-staleness shape `^esyyqjv` removed: the fixture stands in for what `ResultRenderer` emits, so a reword of the `.exception` summary leaves it compiling and passing while it no longer resembles any output the product produces.

## What

Stop hand-writing the frame. The strongest fix is to build the fixture text from the renderer itself — construct an `InterpreterError(kind: .exception, message:)` and call `ResultRenderer.render(_:)` — which removes the summary copy, the `": "`/`"\n\n"` separators and the closing-line interpolation in one move, and makes the fixture the real output rather than a stand-in for it. The test's claim is unchanged: a rendered repairable error parses as no JSON, so `NativeTranscript.returnedValues(in:)` collects nothing from it.

Check whether any other test hand-writes `The snippet failed` or `The snippet timed out` before settling on the shape.

## Acceptance Criteria

- [x] No test hand-writes `ResultRenderer`'s `.exception`/`.timeout` summary text
- [x] `aRepairableErrorOutputContributesNothing` still fails when `returnedValues(in:)` starts scraping non-JSON output — verify with that control, do not assume
- [x] Rewording either summary in `ResultRenderer` leaves the ungated suite green, or fails it for a reason a reader can name
- [x] No weakened assertion, no shipped behaviour change

#phase-1

## Review Findings (2026-08-09 07:03)

> tool rule 'code-hygiene/dead-code-swift' is unavailable (tool missing: exited with exit status: 1); prompt rule 'dead-code' ran instead.

- [x] `Sources/FoundationModelsMultitool/Rendering/ResultRenderer.swift:141` — Switch statement over a known enum set (InterpreterError.Kind) with arms differing only in string constants should be expressed as a data table rather than control flow. Express this as a static dictionary: `static let errorSummaries: [Kind: String] = [.exception: "The snippet failed", .timeout: "The snippet timed out"]`, then use `Self.errorSummaries[self]` in the computed property. **— OVERRULED by human ruling 2026-08-09: the switch is correct. The `data-driven` rule was wrong to fire and has been corrected; see the ruling comment.**
- [x] `Sources/FoundationModelsMultitool/Rendering/ResultRenderer.swift:118` — Same cause as the finding above, second instance in the same file: `RepairDirective.closingLine` is a switch over a known enum set (`.repairSnippet`/`.discoverFunctions`) whose arms differ only in string constants. The finding at :141 shows one example of the cause; close it across the whole file in one pass rather than leaving this site for a later round. **— OVERRULED by human ruling 2026-08-09: the switch is correct. The `data-driven` rule was wrong to fire and has been corrected; see the ruling comment.**
- [x] `Sources/FoundationModelsMultitool/Rendering/ResultRenderer.swift:134` — The doc comment on `repairableErrorSummary` states "Both test targets read it here through `@testable import` rather than restating it". That is false for this member. `rg -n 'repairableErrorSummary' Tests/` returns exactly two references, both in the `FoundationModelsMultitoolTests` target (`HardeningTests.swift:149`, `HardeningTests.swift:183`); `FoundationModelsMultitoolIntegrationTests` contains no reference to it and reaches the wording through the public `ResultRenderer.render(_:)` instead. The sentence was copied from ``RepairDirective/closingLine``, where it is true (that member is read by both targets: `ScenarioFixtureTests.swift:88`/`:306` in the integration target and `MultiToolExecutionTests.swift:215`, `JSCInterpreterTests.swift:1023`, `UnknownToolHintTests.swift:25`/`:34`, `SuspendedContextTests.swift:159` in the unit target). State what the code guarantees for this member instead of inheriting the sibling's claim.