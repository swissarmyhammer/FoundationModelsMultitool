---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m7ty07k961j31pryfh2hcde8
  text: |-
    Decision (from testudoapp-9a, 2026-11-19): every share change must be in the change feed. No directory fact.
    1. The app's UI also calls the endpoint mutations; it does not write CloudKit itself. So the endpoint records a `changed` entry for the session after each share mutation (`shareSession`, `updateSessionShare`, `stopSharingSession`) that succeeds.
    2. Outside changes (the owner stops sharing on another device, CloudKit deletes the zone, a participant leaves): ^y8m7yvr adds `SessionSharer.shareChanges() -> AsyncStream<ULID>` (default: a stream that finishes at once). The endpoint subscribes to the stream of its sharer and records a `changed` entry for each id.
    Find how the change log of `SessionsGraphChanges.swift` can take an entry that does not come from a directory event (an endpoint-side append, with the anchor chain of the session and the same visibility filter). The tool operations must record the entry too, because the tool and the endpoint share one sharer and one change log.
  timestamp: 2026-11-19T22:14:28.201832+00:00
depends_on:
- 01M7TXXYXSTM71VFGJAY8M7YVR
position_column: todo
position_ordinal: '8180'
title: The share field and the share mutations of the sessions endpoint (D208)
---
Decision: D208 (d), (f), (k) in TestudoApp/features/decisions.md (commit d803f1a). Brief: /Users/wballard/github/swissarmyhammer/.briefs/share/mt-brief.md, item 5.

Precondition: ^y8m7yvr (the protocol, the host API, and the share steps of the operations; reuse them, do not copy them).

## Work

- The field `share` on `Session`: the `SessionShare` type of the endpoint (url, anyoneWithLink, the options, updatedAt), or null. It reads `share(of:)` of the sharer.
- The mutations `shareSession(input: {id, options})`, `updateSessionShare(input: {id, keepUpdated})` and `stopSharingSession(input: {id})`, with the visibility and actor rules of the other mutations. The tool/endpoint parity test (MT-10) stays green: the same codes `SHARING_UNAVAILABLE` and `NOT_SHARED`.
- A change of the share is an event of the change feed of the session. The directory does not know about a share, so find how the endpoint can give a `changed` entry after a share mutation (for example, a change recorded by the endpoint itself, or a fact that the host writes through the directory). If no way fits the change feed design, stop and ask the TestudoApp session (`testudoapp-9a`) before you invent one.
- Follow D115 (EXTRAS-9) and keep the EXTRAS-11 kit green. Aliases (D86). Re-record the golden schema; the diff only adds lines.

## Tests

- [ ] The `share` field with and without a share.
- [ ] Each mutation with a fake sharer; `SHARING_UNAVAILABLE`; `NOT_SHARED`.
- [ ] A share mutation gives a `changed` entry for the session.
- [ ] An external viewer cannot share a session that it does not own. #sessions #share #graphql