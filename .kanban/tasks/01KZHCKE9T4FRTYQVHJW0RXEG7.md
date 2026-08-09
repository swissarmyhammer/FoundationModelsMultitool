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
position_column: doing
position_ordinal: '8380'
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