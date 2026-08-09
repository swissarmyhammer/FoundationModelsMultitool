---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
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

- [ ] No test hand-writes `ResultRenderer`'s `.exception`/`.timeout` summary text
- [ ] `aRepairableErrorOutputContributesNothing` still fails when `returnedValues(in:)` starts scraping non-JSON output — verify with that control, do not assume
- [ ] Rewording either summary in `ResultRenderer` leaves the ungated suite green, or fails it for a reason a reader can name
- [ ] No weakened assertion, no shipped behaviour change

#phase-1