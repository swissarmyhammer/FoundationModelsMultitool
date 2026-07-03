---
position_column: todo
position_ordinal: '9380'
title: 'MultiToolAgent.swift: dispatchCallTool error message regressed back to transcriptSeparator, contradicting an already-fixed review finding'
---
## What

`Sources/FoundationModelsMultitool/Agent/MultiToolAgent.swift`'s `dispatchCallTool` catch block (currently around line 511) reads:

```swift
return "callTool(\"\(name)\") failed: \(error)\(Self.transcriptSeparator)Fix the request and call callTool again."
```

This uses `Self.transcriptSeparator` (`"\n\n"`), but a review finding on kanban task `01KWFP865PF579ZVD4RHR4VBH2` (short_id `hr4vbh2`, "Escape hatch: guided direct tool call") — dated 2026-07-03 15:19 — explicitly flagged this as inconsistent with the single-newline pattern the sibling in-message feedback functions use (`discoveryUnavailableMessage`, the `findAPIs(...) found:\n...` success line, etc., none of which use `transcriptSeparator`). The finding was fixed correctly: the task's own recorded history says *"FIXED. Replaced `\(Self.transcriptSeparator)` with `\n` in the callTool error message."*

That fix was subsequently, accidentally reverted: a follow-up `/test` verification pass (in a later `/finish` iteration on the same task) misidentified the deliberate `\n` change as an unintended "functional regression" during what was meant to be a doc-comment-only pass, and "fixed" it by reverting to `Self.transcriptSeparator` — undoing the correct, already-reviewed change. This reverted state was then committed and shipped in `902b5f4`, and the final review pass on that commit did not re-flag this specific line (it only re-examined pre-existing casing identifiers, which were correctly refuted as false positives, and didn't independently re-derive the separator-consistency question).

## Fix

Change line ~511 back to a plain `\n` (matching the sibling message pattern), per the original finding's intent:

```swift
return "callTool(\"\(name)\") failed: \(error)\nFix the request and call callTool again."
```

Confirm no other `dispatchCallTool`-adjacent messages (`unknownDirectToolMessage`, `directCallUnavailableMessage`) need the same treatment — they don't currently use `transcriptSeparator` and appear untouched.

## Acceptance Criteria
- [ ] `dispatchCallTool`'s error message uses a single `\n`, not `Self.transcriptSeparator`, matching the sibling in-message feedback pattern in the same file
- [ ] `swift test` still green, no regressions
- [ ] If `DirectToolCallTests.swift` or `MultiToolAgentTests.swift` assert on the exact separator in this message, update them to match

## Workflow
Small, targeted fix — TDD optional given the tiny scope, but add/update a test asserting the message uses `\n` not `\n\n` if one doesn't already cover this.