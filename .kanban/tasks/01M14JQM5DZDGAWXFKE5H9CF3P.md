---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m1741pqf52v53r5b2qs613zg
  text: |-
    Research and work notes.

    The helper of the sibling file, `LoopbackHTTPServerTests.connect(to:advertising:)`, is the model. It gives the external label `advertising` and keeps the internal name `capabilities`. The helper of `ScriptedServerSelfTests` now has the same shape.

    The count on the card is correct. The file has nine calls to the helper. Two calls give the label, at the two elicitation tests (`elicitRoundTrip` and `urlElicitRoundTrip`). The other seven calls take the default value and did not move.

    The doc comment did not change. The `swift/doc-parameter-naming` rule says a `- Parameter` key names the internal name and never the external label. The internal name is still `capabilities`, so `///   - capabilities: The client capabilities to advertise.` stays correct. The sibling file has the identical line.

    The body of the helper did not change either. Line `to: scripted, over: .inMemory, clientName: Self.clientName, capabilities: capabilities` calls `MCPTestSupport.connectedServer`, which is a different function with its own label. The card does not include it.

    One note for a later card, not done here: the expression `Client.Capabilities(elicitation: .init())` is written out at both call sites. The sibling file hoists the same value to a `Self.elicitingCapabilities` constant. This card is a rename, so the two literals stay as they are.
  timestamp: 2026-08-29T16:01:08.335741+00:00
- actor: claude-code
  id: 01m1742426gadc89nkx3c93s92
  text: |-
    ### implement — changed
    - evidence: 1 file — Tests/FoundationModelsMultitoolTests/ScriptedServerSelfTests.swift. `swift build --build-tests` gave "Build complete!" with exit code 0. `swift test --filter ScriptedServerSelf` gave 11 tests in 1 suite passed, 0 failures.
    - next: /review
  timestamp: 2026-08-29T16:01:21.990669+00:00
- actor: claude-code
  id: 01m174wjagp46mspt9vt69jxtv
  text: |-
    ### commit — changed
    - evidence: 54bba0a test: rename connect capabilities label to advertising (5 files changed)
    - next: none
  timestamp: 2026-08-29T16:15:48.560530+00:00
- actor: claude-code
  id: 01m175kdfjmy8p3vb9qyhsbfcw
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit 54bba0a). 7 validators attempted, 0 failed, 0 skipped. 0 findings, 0 confirmed, 0 refuted. 1 source file read; the 4 `.kanban` files are excluded by `.reviewignore`.
    - next: the task moves to Done. No finding is open.
  timestamp: 2026-08-29T16:28:17.266976+00:00
- actor: claude-code
  id: 01m175m7ksxby5r0necewerdve
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 1 source file, `Tests/FoundationModelsMultitoolTests/ScriptedServerSelfTests.swift`. The private helper is now `connect(to:advertising:)`, the same shape as the sibling helper in `LoopbackHTTPServerTests.swift`. The two call sites that give the label moved. The seven that take the default value did not move. The doc comment key stays `- capabilities:`, because `swift/doc-parameter-naming` binds that key to the internal name, and the internal name did not change.
    - test: green — `swift test`, 1316 tests in 101 suites passed, 0 failed, 0 skipped, test time 24.299 s. A forced full rebuild with `swift build --build-tests` completed with 0 errors in 232 s. One warning came from the third-party `mlx-swift` package through `mlx-swift-lm`: "missing creator for mutated node ... mlx-swift_Cmlx.bundle". It is not from a file of this repository, 63 earlier task records hold the same text, and it is out of scope here.
    - commit: 54bba0a — "test: rename connect capabilities label to advertising", 5 files: the one source file and the board records of this card and of `^jmtpfwv`.
    - review: clean — `review sha HEAD~1..HEAD`. 0 findings, 0 confirmed, 0 refuted. Validators 7 attempted, 0 failed, 0 skipped, thus this is not the false-clean pattern. The four board files were held out by `.reviewignore`, and all 7 validators read the one source file.
    - next: none. All three criteria are checked and the card is in `done`.
  timestamp: 2026-08-29T16:28:44.025467+00:00
position_column: done
position_ordinal: ffa480
title: The connect helper of ScriptedServerSelfTests takes a bare capabilities label
---
## What

`ScriptedServerSelfTests.connect(to:capabilities:)` reads

```swift
private func connect(
    to scripted: ScriptedServer, capabilities: Client.Capabilities = .init()
) async throws -> Client
```

At the call site this is `connect(to: scripted, capabilities: Client.Capabilities(elicitation: .init()))`,
which reads aloud as "connect to scripted capabilities ..." — a bare noun
label after the base verb. The `swift/fluent-usage` rule names this shape:
DON'T `x.subviews(color: c)`, DO `x.subviews(havingColor: c)`.

## Where it came from

Found in the sweep of `swift/fluent-usage` over
`LoopbackHTTPServerTests.swift` and `LoopbackHTTPServer.swift` (task
`^ennv9e5`). The helper of `LoopbackHTTPServerTests` had the same label, and
it is now `advertising capabilities:`. The helper of
`ScriptedServerSelfTests` is a different file, so it stayed out of that card.

No review has raised it: every review of that card was scoped to the diff, and
this line did not change.

## Acceptance Criteria

- [x] `capabilities:` becomes `advertising:` in
      `Tests/FoundationModelsMultitoolTests/ScriptedServerSelfTests.swift`,
      which makes the two test helpers read the same way.
- [x] The two call sites that pass the label move with it. The seven that take
      the default do not move.
- [x] `swift build --build-tests` is clean, and `swift test` is green. This is
      a rename: add no test, no sleep and no timeout.