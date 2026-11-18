---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m7nqprvchzmyqtrh55akrvzd
  text: 'Extras API (from the Extras session, 2026-11-17): `SessionSummary.shortID` and `slug`; `SessionReference.resolve(_:sourceFolder:among:)` gives `.session`, `.ambiguous` or `.none`; `sourceSession` is on `OutgoingSessionMessage` and on `SessionMessage`. There is no new event: `messageDelivered(SessionMessage)` carries the sender. Also, the Extras in-memory directory puts a message for a recorded target in its inbox and does not restore the target through the launcher. After the Extras pin moves, run the tests of the sessions tool and the sessions endpoint. When a test expects a restore of a recorded target on send, change the test to expect the inbox.'
  timestamp: 2026-11-17T21:48:14.572872+00:00
- actor: claude-code
  id: 01m7qbmcv4f9gctgyg79tr7vch
  text: |-
    ### finish — skipped (blocked-external)
    - evidence: 2026-11-18, `git fetch` of ../FoundationModelsExtras: origin/main is 1c69b4f and has no `SessionReference.resolve` or `slug`. The local Extras tree has the work in progress.
    - next: start when the Extras change is on origin/main.
  timestamp: 2026-11-18T12:55:42.692140+00:00
- actor: claude-code
  id: 01m7qe9xktb7tm5jjfypkba60g
  text: |-
    Extras landed (from foundationmodelsextras-9e, 2026-11-18): origin/main b87233ec474a0a5fe41f288d10a186cf983dd22a.
    - `SessionReference.resolve(_ text: String, sourceFolder: URL?, among: [SessionSummary]) -> SessionReferenceResolution` (`.session(SessionSummary)`, `.ambiguous([SessionSummary])`, `.none`). Order: full ULID, then short id, then slug. For each kind, the source folder first, then all. A short id in another folder wins over a slug in the source folder. An archived session never matches. A leading `@` is optional.
    - InMemorySessionDirectory changes that break current tests: an `.agent` address always starts a new root session (origin `.message`). These tests expect the old rule and must change: `Tests/FoundationModelsMultitoolTests/SessionsToolMessageTests.swift:208` and `:225`.
    - A message to a recorded session goes to its inbox with the receipt `sent`: no restore, no turn, no `messageDelivered` event.
    - A new session with no title gets a default name (`claude-code`, `claude-code-2`).
    - The note says both "with no launcher, it throws noLauncher" and "Refusal.noLauncher is removed". Read the Extras code to find the true refusal.
  timestamp: 2026-11-18T13:42:25.146846+00:00
- actor: claude-code
  id: 01m7qeanek4e521v36vjfm4vsn
  text: 'Answer from foundationmodelsextras-9e (2026-11-18): an `.agent` address with no launcher gives no `refused` receipt. `send` throws `SessionDirectoryError.noLauncher` (`InMemorySessionDirectoryState.swift:115`, called from `InMemorySessionDirectoryState+Messages.swift:162`). `InMemorySessionDirectory.Refusal.noLauncher` was only the reason text of a refused receipt for a recorded target, and it is removed, because a recorded target now gets `sent`. To keep the tests at `SessionsToolMessageTests.swift:208` and `:225` as delivery tests, give the directory a launcher. Then each send gives `.started` with a new session id.'
  timestamp: 2026-11-18T13:42:49.555482+00:00
position_column: todo
position_ordinal: '8180'
title: One async address reader for send in the tool and in the endpoint (D199)
---
Decision: D199 (c), (d), (e) in TestudoApp/features/decisions.md. Brief: /Users/wballard/github/swissarmyhammer/.briefs/at-sessions/mt-brief-at-sessions.md, item 1, item 2 and item 6.

Precondition: FoundationModelsExtras gives `SessionReference.resolve` and `SessionSummary.slug` on origin/main. Before you start, examine origin/main of ../FoundationModelsExtras. When it does not have them, the task stays blocked.

Main rule: an agent IS a session. There is one namespace. `@agent:/path` and a folder path are only aliases (D86 style).

## Current behavior

- `SessionsToolInput.address(_:)` (`Capabilities/Sessions/SessionsToolInput.swift:97-112`) is synchronous and does not read the directory. It accepts a full ULID, a path, the tag form and `@agent[:/path]`. It cannot read a short id or a slug.
- The `send message` operation (`SessionsToolMessageOperations.swift:29-60`) and `Mutation.sendMessage` (`SessionsGraphMutations.swift:404-416`, with `context.address(_:)` at `:252-262`) each read the address.

## Work

- Make one async reader, for example `SessionsToolContext.address(_ text: String, from sender: SessionMessageSender, sourceFolder: URL?) async throws -> SessionAddress`. The tool and the graph both call it (D100).
- `@<id>`, `<id>`, `@<short id>`, `<short id>` and `@<slug>`: `SessionReference.resolve` over `directory.sessions(matching: SessionQuery(includesRecorded: true, ...))`, filtered by the visibility of the caller. One match gives `.session(id)`. An ambiguous result gives a corrective with the id, the name and the folder of each match, and sends nothing.
- No match for `@<name>`, and an agent folder has the name (agent catalog, D61, D71): `.agent(id: name, folder: lookupFolder)`. The Router starts a new root session of that agent. No agent has the name: the corrective "no session and no agent has the name".
- Alias `@agent:/path`: rewrite it to `@agent` with `/path` as the lookup folder. Report the rewrite in the tool answer and in `extensions.rewrites` (D86).
- Alias of a folder path alone: `.folder(url)` as today, with the rewrite report.
- The tag form: as today. It names a group, not one target.
- The external viewer rule of `context.address` stays: a resolved session that the viewer does not own gives a REFUSED receipt.
- Tool text: the `@Guide` of the address (`SessionsToolMessageOperations.swift:38-42`), the description of `send message` and `SessionsToolText.notAnAddress` name the new forms.

## Tests

- [ ] Tool: send to `@<slug>` in the folder of the caller.
- [ ] Tool: send to `@<short id>`, and to a full id with and without `@`.
- [ ] Tool: an ambiguous slug gives a corrective with each match and sends nothing.
- [ ] Tool: `@travel` with a session whose slug is `travel` goes to that session.
- [ ] Tool: `@travel` with no such session and an agent folder `travel` starts one (receipt `started`).
- [ ] Tool: `@travel:~/trips` looks in `~/trips` first and reports the rewrite.
- [ ] Tool: `@nobody` gives the corrective.
- [ ] Graph: `sendMessage(input: {to: "@<slug>", ...})` gives the same answer as the tool.
- [ ] Graph: an external viewer with a slug of a session that it does not own gets a REFUSED receipt. #sessions #at-sessions #graphql #blocked-external