---
assignees:
- claude-code
position_column: todo
position_ordinal: '9880'
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

- [ ] `capabilities:` becomes `advertising:` in
      `Tests/FoundationModelsMultitoolTests/ScriptedServerSelfTests.swift`,
      which makes the two test helpers read the same way.
- [ ] The two call sites that pass the label move with it. The seven that take
      the default do not move.
- [ ] `swift build --build-tests` is clean, and `swift test` is green. This is
      a rename: add no test, no sleep and no timeout.