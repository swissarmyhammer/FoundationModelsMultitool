---
assignees:
- claude-code
depends_on:
- 01M5F236W9NXECHBE44PTMVYQZ
position_column: todo
position_ordinal: '8680'
title: 'SessionsTool message ops: send message, reply message (MT-2)'
---
## What
In `Sources/FoundationModelsMultitool/Capabilities/Sessions/SessionsTool.swift` (design: `session.md` sections 8, 9 and 10):
- `send message` to an address: a session id, an agent, a folder or a tag (`SessionAddress`), through `SessionDirectory.send`. The receipt names delivered, queued and refused targets.
- `reply message` with `inReplyTo` (a message id from `read inbox`).
- Loop-guard refusals and `archived` refusals come back as correctives that name the reason (section 10.3).

## Acceptance Criteria
- [ ] Sending to each address kind reaches the expected sessions in `InMemorySessionDirectory`
- [ ] A reply records `inReplyTo`; the target's `readInbox` shows it
- [ ] Sending to an archived session gives a corrective with the reason "archived"

## Tests
- [ ] New `Tests/FoundationModelsMultitoolTests/SessionsToolMessageTests.swift`
- [ ] `swift test --filter SessionsTool` passes

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #sessions