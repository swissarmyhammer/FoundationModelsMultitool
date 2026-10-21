---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5fakdcsgd08hxs3ena4aasc
  text: |-
    Research (implement):
    - Port: `SessionDirectory.send(OutgoingSessionMessage)` -> `[SessionSendReceipt]` (outcome delivered/queued/started/refused, `reason`, `target` nil for a no-match or loop-guard refusal). Thrown: messageTooLong, invalidTag, unknownSession, noLauncher, unknownAgent — all already have correctives in `SessionsToolText.corrective(for:)`.
    - InMemorySessionDirectory: a refusal of a loop guard (chain depth, sends per turn) gives one refused receipt with no target; folder with no match is refused with "Name an agent: @agent:/path."; archived target gives refused with reason "archived" and the target id; tag over the limit gives refused "tooManyTargets" for the rest.
    - session.md 8.2: `send message` takes `to` (ULID, `@agent`, `@agent:/path`, `/path` or `~/path`, `#tag`) and `message`; `reply message` takes `inReplyTo` and `message`; the target is the sender of the original message; a reply to a user message is a corrective.
    - PORT GAP: the port has no lookup of a message by id. `inbox(of:markRead:)` gives only unread messages, and `read inbox` marks each one read, so a message id from `read inbox` cannot be resolved through the port alone. Plan: the reply looks first in the unread inbox of the caller, then in a record of the messages that `read inbox` gave the caller, kept by the tool (an actor, shared by every copy of one tool). A follow-up card asks for a port lookup in Extras so the record can go.
  timestamp: 2026-10-21T13:32:22.809627+00:00
- actor: claude-code
  id: 01m5fb1fh3z6ybz4jqr5gm8c64
  text: |-
    Implementation landed (TDD: 25 new cases in SessionsToolMessageTests, watched them fail on the missing ops, then green).
    - `send message` (verb sendMessage) and `reply message` (verb replyMessage) in new SessionsToolMessageOperations.swift; shared `SessionsToolContext.send(_:to:inReplyTo:from:)`; both go through `answer(asCallerOf:)`.
    - `SessionsToolInput.address(_:)` reads the section 9 forms: ULID (any case) -> session, `/path` or `~/path` -> folder, `#tag`, `@agent` / `@agent:/path` (agent id case kept; the last `:` before `/` or `~` splits the folder). A text in no form is a corrective that lists the forms. `messageID(_:)` reads a message id in any case.
    - Answer: one line per receipt (Delivered / Queued / Started with the new id / Refused with the reason). When every receipt is refused the answer starts "The message was not sent."; the reason "archived" adds advice that names startSession. Loop-guard refusals show the directory's reason verbatim.
    - Reply: target is the sender of the original; a message from the user is a corrective; an unknown id names readInbox and sendMessage.
    - PORT GAP handled in-tool: `SessionsToolReceivedMessages` (actor, cap 1000) records what `read inbox` gave; reply looks in the caller's unread inbox first, then the record. Follow-up card ^nv64e95 asks for a port lookup by id so the record can go. The SessionsTool doc comment now says each copy shares the record too.
    - Fixture: `SessionsToolFixtures.summary` gained `agent:` and `folder:` parameters (defaults unchanged).
  timestamp: 2026-10-21T13:40:03.747668+00:00
- actor: claude-code
  id: 01m5fb1kpyhhwsbgxtnyx2bpyj
  text: |-
    ### implement — changed
    - evidence: `swift test` — 2623 tests in 225 suites passed, 0 failures (SessionsToolMessageTests 25/25). 10 files: Sources/.../Sessions/SessionsTool.swift, SessionsToolContext.swift, SessionsToolInput.swift, SessionsToolOperations.swift, SessionsToolText.swift, SessionsToolText+Messages.swift (new), SessionsToolMessageOperations.swift (new), SessionsToolReceivedMessages.swift (new); Tests/.../SessionsToolMessageTests.swift (new), Tests/.../Fixtures/SessionsToolFixtures.swift
    - next: /review. Follow-up ^nv64e95 (port lookup of a message by id).
  timestamp: 2026-10-21T13:40:08.030716+00:00
depends_on:
- 01M5F236W9NXECHBE44PTMVYQZ
position_column: doing
position_ordinal: '80'
title: 'SessionsTool message ops: send message, reply message (MT-2)'
---
## What
In `Sources/FoundationModelsMultitool/Capabilities/Sessions/SessionsTool.swift` (design: `session.md` sections 8, 9 and 10):
- `send message` to an address: a session id, an agent, a folder or a tag (`SessionAddress`), through `SessionDirectory.send`. The receipt names delivered, queued and refused targets.
- `reply message` with `inReplyTo` (a message id from `read inbox`).
- Loop-guard refusals and `archived` refusals come back as correctives that name the reason (section 10.3).

## Acceptance Criteria
- [x] Sending to each address kind reaches the expected sessions in `InMemorySessionDirectory`
- [x] A reply records `inReplyTo`; the target's `readInbox` shows it
- [x] Sending to an archived session gives a corrective with the reason "archived"

## Tests
- [x] New `Tests/FoundationModelsMultitoolTests/SessionsToolMessageTests.swift`
- [x] `swift test --filter SessionsTool` passes

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #sessions