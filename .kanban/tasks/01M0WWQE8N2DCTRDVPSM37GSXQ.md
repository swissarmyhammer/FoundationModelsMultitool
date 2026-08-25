---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0xaxj4y8avgtmsez8r8aak1
  text: |-
    Research done. Findings:
    - Source `PatchParser.swift` (565 lines) is pure and IO-free. It uses only `Hashline.splitLines`, which this package already has (internal).
    - Target folder convention: types are internal, not public (`Hashline`, `PathGuard`, `CorrectiveResult` do the same). The port drops each `public` keyword.
    - Header convention: a line-comment block that names the type, the port provenance, and the eventplan section.
    - `CorrectiveResult.swift` header says the `ParseFailure: CorrectiveFailure` conformance waits for the patch parser. The sibling puts that conformance in its own `CorrectiveResult.swift`, with `correctiveMessage { description }` so the line number stays in the message. This task adds the same conformance and updates the header text.
    - The sibling has no direct test of `ParseFailure.correctiveMessage`. This port adds one test for it, because the conformance is new code in this package.
    Plan (/tdd): port `PatchParserTests.swift` first, watch the build fail, then port `PatchParser.swift`, add the conformance, and run `swift test --filter PatchParserTests` plus a full `swift build`.
  timestamp: 2026-08-25T20:48:48.286529+00:00
- actor: claude-code
  id: 01m0xb3yjff9h3yekhthmdmrj3
  text: |-
    ### implement — changed
    - evidence: 3 files — Sources/FoundationModelsMultitool/Capabilities/Files/PatchParser.swift (new port, internal visibility), Sources/FoundationModelsMultitool/Capabilities/Files/CorrectiveResult.swift (adds `ParseFailure: CorrectiveFailure`, header updated), Tests/FoundationModelsMultitoolTests/PatchParserTests.swift (new, 22 tests: the ported suite plus one conformance test). TDD order held: the test file failed first with "cannot find PatchParser in scope", then the port made it green. `swift test --filter PatchParserTests` passes (22 tests). Full `swift test` passes (826 tests, 63 suites). `swift build` succeeds with no warning from this change.
    - next: /review
  timestamp: 2026-08-25T20:52:17.615624+00:00
- actor: claude-code
  id: 01m0xb750mgcbk252x4ka7208z
  text: |-
    ### test — green
    - evidence: swift test (full recompile of Sources and Tests) — 826 tests in 63 suites, 0 failures, 0 skipped. 1 warning seen: known pre-existing mlx-swift "missing creator for mutated node" notice. No new warnings.
    - next: none
  timestamp: 2026-08-25T20:54:02.516652+00:00
- actor: claude-code
  id: 01m0xbew4ypfgwe6426k1nzjhh
  text: |-
    ### review — clean
    - evidence: review sha 5171ead~1..5171ead — 0 findings, 0 confirmed, 0 refuted, 7 attempted, 0 failed. 3 files reviewed; 4 files in .kanban/ excluded by .reviewignore.
    - next: none. The task moved to done.
  timestamp: 2026-08-25T20:58:15.582969+00:00
- actor: claude-code
  id: 01m0xbf9y3f1g9w5ftzy43tg0k
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — PatchParser.swift, PatchParserTests.swift, ParseFailure CorrectiveFailure conformance in CorrectiveResult.swift
    - test: green — swift test, 826 tests in 63 suites, 0 failed
    - commit: 5171ead
    - review: clean — review sha 5171ead~1..5171ead, 0 findings
    - task landed in done
  timestamp: 2026-08-25T20:58:29.699476+00:00
depends_on:
- 01M0WWP2KJHX313ZFGC80EVN62
- 01M0WXACC6Q0PY1QKZ6Y2TH7J4
position_column: done
position_ordinal: fe80
title: Port PatchParser into Capabilities/Files
---
## What
Port `PatchParser` from the FileTool package into this package. This is the pure parsing layer under `PatchEngine`. It has no file IO, so it ports alone.

- Source: `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool/Sources/FileTool/PatchParser.swift`
- Target: `Sources/FoundationModelsMultitool/Capabilities/Files/PatchParser.swift`

Keep the corrective posture: a patch that cannot parse comes back as a corrective description, not as a thrown error.

## Acceptance Criteria
- [x] The parser accepts and rejects the same patch texts as the source.
- [x] `swift build` succeeds.

## Tests
- [x] Port `PatchParserTests.swift` from `/Users/wballard/github/swissarmyhammer/FoundationModelsFileTool/Tests/FileToolTests/` into `Tests/FoundationModelsMultitoolTests/`.
- [x] `swift test --filter PatchParserTests` passes.

## Workflow
- Use `/tdd` — port the tests first, then port the code to make them pass. #phase-3 #eventplan