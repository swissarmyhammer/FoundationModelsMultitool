---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0anq7rjaxp9yp7t9thw1q6m
  text: |-
    Closed as part of one sweep over `^yzhpjab`, `^523qwcy` and `^mxjt7y5`. Both options the card offered were used, and applied consistently.

    **Corrected, not merely annotated**, at both `makeMLXLanguageModel(for:)` sites and at every passage that stated the CLI's wiring:

    - The M9 "Current design" paragraph now says a host never wraps a slot by hand: it calls `profile.standard.makeSession(tools: try registry.makeSessionTools(librarian: profile.flash))` and drains `streamEvents(to:)`, and it records why the session type is part of the contract (only a `RoutedSession` mounts under `DetachConfiguration.nativeSessionMount`).
    - The "Usage: attaching to a session" section is now "Usage: mounting the vended tools on a session", and its worked example is the shipped call plus a drain loop. Its direct-mode example is corrected too — it vends `runCode` and `wait`, and `directMode().makeSessionTools(librarian: nil)` is a real call.
    - The Router-integration bullet said `RoutedSession` has "**No `tools:` parameter, no automatic tool loop.**" That premise is what every retired passage rested on, so it is now stated as false and dated: the parameter exists, it mounts each tool, and it did not exist when the paragraphs below were written.
    - Also fixed: the preamble blockquote, the ASCII flow diagram, Components 1/2b/8, the Milestones as-built note, the Testing-strategy as-built note, and Findings #7.
    - `NativeToolCallEvaluation` was named twice as the thing the gated suite grades with. That type exists nowhere in the repository. Both sites now describe what `ScenarioRunner` really grades.

    **Marked as superseded** where the text is a period record: a new "Status of this document" section at the top states plainly that this is the plan and the milestone record, not the shipped reference; gives the host contract in one sentence so no passage below can misdirect; and names the two symbols that no longer exist.

    `findAPIs`/`FindAPIsTool` was the second deleted name and was renamed to `searchTools`/`SearchToolsTool` throughout the design sections — 25 sites. It is kept, deliberately and by a rule the banner states, in exactly three places, each a record of what was written at the time: the RETIRED `MultiToolAgent` pseudocode and its turn formats, the Milestones list, and Findings (research). `FindAPITool`/`FoundAPIs` survive only in the M6 milestone bullet and never shipped under any name; the banner says so.

    `README.md`'s pointer was updated to match: it now tells a reader that `plan.md` is a historical record and to read its status note first.

    Note for review, so the first criterion is checkable rather than taken on trust: `rg 'findAPI|FindAPI|FoundAPIs' plan.md` returns 14 lines — 1 in the banner's own name map, 4 in the RETIRED pseudocode block and its turn-format sentence, 1 in the retired-loop component entry, 4 in the M6 milestone and the as-built note above it, 3 in Findings #7, 1 in a Prior-art note. Every one sits under text that says it is retired or that it is the record as written. Nothing sends a reader looking for code that is not there.

    ### implement — changed
    - evidence: `swift test` green — 359 tests in 30 suites, 59 tests in 11 suites. plan.md, README.md
    - next: review
  timestamp: 2026-08-18T14:52:01.170283+00:00
position_column: doing
position_ordinal: '8580'
title: plan.md M9 still teaches the bare LanguageModelSession wiring the host contract does not name
---
`^260yggp` moved the shipped CLI onto the host contract — vended tools mounted on a `RoutedSession`, one turn drained through `streamEvents(to:)` — and updated `README.md`, which the card named. `plan.md` was not in that card's scope and still teaches the retired wiring:

    plan.md:344   (`makeMLXLanguageModel(for:)` + `runDemo`, which passes no session
    plan.md:403   let mlxModel = makeMLXLanguageModel(for: profile.standard)   // MLXLanguageModel: .toolCalling over the resident weights

`makeMLXLanguageModel(for:)` no longer exists. `README.md` points a reader at `plan.md` for "full design and milestone-by-milestone rationale", so a reader who follows that pointer lands on the exact wiring the contract rules out — the failure `^260yggp` was filed against, one document over.

## What to decide

`plan.md` is a historical milestone record, so the fix is not automatically "rewrite it". Either:

- correct the M9 sections so the plan states the shipped design, or
- mark the passage as superseded, naming what replaced it.

Pick one and apply it consistently to both sites.

## Acceptance Criteria

- [x] `plan.md` names no symbol that does not exist
- [x] A reader following `README.md` to `plan.md` gets the `RoutedSession` + `streamEvents(to:)` contract, or an explicit note that the passage is superseded
- [x] Ungated `swift test` green (documentation-only change)