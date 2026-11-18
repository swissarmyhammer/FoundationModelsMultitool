---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m7qv890ja68vw61qay506v48
  text: 'Note (2026-11-18): Extras D205 task ^xpaa2h9 sends the fork sha to this session. The test fixture `ForwardingSessionDirectory` conforms to `SessionDirectory`. If Extras adds `fork(_:)` to the protocol with no default, that fixture does not compile: then do this task first, add `fork(_:)` to the fixture, and push at once, as for ^ka7byh8.'
  timestamp: 2026-11-18T17:28:42.770560+00:00
- actor: claude-code
  id: 01m7qw65ctne773hy95vbxfspg
  text: |-
    Extras landed (from foundationmodelsextras-9e, 2026-11-18): origin/main ec528ec (code commit 912d9b0, it also has D204). Run `swift package update FoundationModelsExtras` first.
    - New: `SessionForkCut`, `SessionForkRequest`, `SessionDirectory.fork(_:)`. The default throws `forkUnsupported`, so `ForwardingSessionDirectory` compiles, but it must forward `fork` for the fork tests. No build break: this task is not urgent.
    - Errors: `archivedSession(ULID)` (map to ARCHIVED_SESSION), `forkCutOutOfRange(SessionForkCut)`, `forkUnsupported` (map to the new FORK_UNSUPPORTED). `SessionName.fork(sourceName:usedNames:)`.
    - `InMemorySessionDirectory.fork(_:)` works with no launcher. Cut rule: `.lastCompletedTurn` always works; `.callingToolCall` needs a working source, else `forkCutOutOfRange`; `.historyPosition(n)` needs n >= 0. The test hook `forkRequest(of:)` gives the recorded request.
    - No new event: a fork sends `started` with kind `fork` and the parent, so the change feed already gives an `added` entry.
    - A "directory that cannot fork" test can use a directory whose `fork` keeps the default (`forkUnsupported`).
  timestamp: 2026-11-18T17:45:02.106355+00:00
position_column: todo
position_ordinal: '8480'
title: fork session and the forkSession mutation (D205)
---
Decision: D205 in TestudoApp/features/decisions.md (commit 483664d). Brief: /Users/wballard/github/swissarmyhammer/.briefs/fork/mt-brief.md, items 1, 2 and 3.

Precondition: the Extras sha with `SessionDirectory.fork(_:)`, `SessionForkRequest` and `SessionForkCut`. Examine origin/main of ../FoundationModelsExtras, and run `swift package update FoundationModelsExtras`. The tests use the in-memory directory of Extras, so this task does not wait for the Router. If Extras adds `fork(_:)` to the protocol with no default and a Multitool type or test fake conforms to `SessionDirectory`, Multitool main does not compile until this task lands: then do this task first and push at once.

## Work

- Add the operation `fork session` (`forkSession` in code mode) to the `sessions` tool (`Capabilities/Sessions/SessionsToolChangeOperations.swift`), with `id` (optional) and `message` (optional).
- No `id`: the source is the caller session, and the cut is `.callingToolCall` (the fork gets the history up to this call, not the call). No caller and no `id`: the corrective of a call with no caller session.
- An `id`: `<id>`, `@<id>`, `<short id>`, `@<short id>`, `@<slug>` through the one resolver (`SessionsAddressReader.swift`), and the cut is `.lastCompletedTurn`.
- `message` is the first prompt of the fork (`firstPrompt` of the request).
- The answer gives the id, the short id and the name of the fork, and says that the fork works alone and that a message to it uses `send message`.
- An archived source: `ARCHIVED_SESSION`. A directory that cannot fork: a new corrective `FORK_UNSUPPORTED`.
- Add the mutation `forkSession(input: {id, message})`: the cut is `.lastCompletedTurn`, and it gives the new `Session`. The visibility rule of the other mutations. The tool/endpoint parity test (MT-10) stays green.
- The `changes` feed shows the fork as the start of a session of kind `FORK` (check the event that Extras sends).
- The tool description and the code-mode verbs: one line "fork session forks a session from here: the fork has the history up to this call and then works alone".
- Aliases (D86). Re-record the golden schema; the diff must only add lines.
- After the push, send the commit sha to the peer sessions `foundationmodelsacpagent-9e` and `testudoapp-9a`.

## Tests

- [ ] `fork session` with no `id` from inside a tool call: the in-memory directory gets `sourceID` = caller and `.callingToolCall`; the answer names the fork.
- [ ] `fork session` with `@<slug>` of another session: `.lastCompletedTurn`.
- [ ] `fork session` with `message`: the request has `firstPrompt`.
- [ ] No caller and no `id`; an archived source; a directory with no fork: the correctives.
- [ ] `forkSession`: the new session has `kind: FORK` and `parent` = the source; the `changes` feed has the start.
- [ ] The tool text names `fork session`. #sessions #fork #graphql