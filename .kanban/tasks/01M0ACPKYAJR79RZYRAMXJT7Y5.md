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
- actor: claude-code
  id: 01m0apc0fkpp2p9q5tw3hhrcm3
  text: |
    ### review — findings
    - evidence: `review sha HEAD~1..HEAD` (commit `8668d90`) — engine fleet 0 findings over 7 validators. Directed verification of the `findAPIs` split found 2 on this card: plan.md:879, plan.md:26. M9's milestone bullet was renamed `findAPIs` → `searchTools` inside the Milestones list, which both the new status banner and the Milestones as-built note declare a period record kept as originally planned, and which M6 (`plan.md:866-868`) still follows. The banner also says "Three places keep the old spelling on purpose" and enumerates three, but the retired Component 2b entry (`plan.md:805`) is a fourth.
    - verified true, no finding: the kept sites are 13 lines / 15 occurrences, every one under retired or period-record framing (the card comment's tally of 14 lines does not match the file); the corrections under Findings (research) (`:1032`) and Prior art (`:1096, :1119`) are right, because each is a present-tense clause about what runs today; no executable line moved.
    - next: restore `findAPIs` at M9 or state the exception, and correct the banner's count and list. Task stays in `review`.
  timestamp: 2026-08-18T15:03:21.843979+00:00
- actor: claude-code
  id: 01m0b6nyb1gqz88qn4ptgzp58w
  text: |-
    ## Both findings closed — the Milestones list is uniformly the record as written

    **`plan.md:879`.** The M9 bullet is back to `findAPIs`. The as-built note one section above says the milestones are kept as originally planned, and M6 keeps `findAPIs`/`FindAPITool`/`FoundAPIs` under that rule, so the whole list is now one thing rather than a list with one swept bullet. I checked the whole Milestones list against the banner's rule, not this bullet alone: `grep -n "makeMLXLanguageModel\|searchTools\|SearchToolsTool" plan.md` over lines 829-882 returned only this one bullet, so it was the single exception.

    **`plan.md:26`.** The count is now four, and the list names the retired **`MultiToolAgent`** entry under **Components** that the banner omitted. The count is derived from the file, not from either earlier tally. `grep -n "findAPIs\|FindAPI\|FoundAPIs" plan.md` gives 13 lines, which group into exactly the banner's four places plus the banner's own name map:

    - name map: `:23, :30, :31`
    - retired `MultiToolAgent` pseudocode and turn formats: `:403, :404, :411`
    - retired Component 2b: `:806`
    - Milestones (as-built note + M6 + M9): `:837, :867, :868, :869, :880`
    - Findings (research): `:1028, :1029`

    Ungated `swift test` green (59 tests / 11 suites) — the change is documentation only.
  timestamp: 2026-08-18T19:48:24.545784+00:00
position_column: doing
position_ordinal: '8680'
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

## Review Findings (2026-08-18 09:56)

> Scope: `review sha HEAD~1..HEAD` (commit `8668d90`) — reviewed the diffs only. The engine validator fleet returned 0 findings over 7 validators. The items below come from the directed verification of the `findAPIs` historical/design split, which the generic validators do not grade.

- [x] `plan.md:879` `docs/claim-accuracy` — the M9 milestone bullet was corrected to the shipped name inside a section the commit declares a period record. **Restored to `findAPIs`**, so the Milestones list is uniformly the record as written. The whole list was checked against the banner's rule, not this bullet alone: over lines 829-882, `grep -n "makeMLXLanguageModel\|searchTools\|SearchToolsTool" plan.md` returns only this bullet, so it was the single exception.
- [x] `plan.md:26` `docs/claim-accuracy` — "Three places keep the old spelling on purpose" undercounted; there are four. **The banner now says four and names the retired `MultiToolAgent` entry under Components** alongside the pseudocode, the Milestones list and Findings (research). The count is derived from the file: the 13 `findAPIs`/`FindAPI`/`FoundAPIs` lines group into exactly those four places plus the banner's own name map (`:23, :30, :31`).

### Verified true, no finding

- The kept `findAPIs` family sites are 13 lines, all under retired or period-record framing: the banner's own name map, the history-titled pseudocode, retired Component 2b, Milestones + as-built note, and Findings (research). None sends a reader looking for code that is not there.
- The corrected sites under `## Findings (research)` and `## Prior art` are right to use the shipped name: each is a present-tense clause about what runs today, not a record of what was written.
- No executable line moved anywhere in the commit.
