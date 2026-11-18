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
- actor: claude-code
  id: 01m7qfyssgmwxrxbdkecqcxa6h
  text: |-
    Research (implement, 2026-11-18):
    - Extras pin is b87233e locally (Package.resolved). `SessionReference.resolve` filters archived and gives `.none` for a full ULID with no visible match. The reader keeps a full ULID with no match as `.session(id)`, so the current NOT_FOUND (graph, hidden session) and the directory refusals (archived) stay.
    - The agent catalog: Multitool has no catalog of its own. The directory launcher is the catalog: `.agent(id:folder:)` throws `SessionDirectoryError.unknownAgent(name, nearNames:)` for a name that no agent folder has. Thus the reader gives `.agent` for `@<name>` with no session, and the send turns `unknownAgent` into the corrective "no session and no agent has the name". No second catalog.
    - BLOCKER for one item: `extensions.rewrites` belongs to the toolkit of Extras. `GraphQLResponse` takes `rewrites` only from `RewrittenDocument.rewrites` (the name rewrite of the document), and it removes a `rewrites` key from `responseExtensions()`. `API.result(of:...)` is private. A resolver thus cannot add a rewrite report to `extensions.rewrites`. An Extras change is necessary, for example a `ResponseRewrites` collector on `GraphQLRunContext` (as `ResponseWarnings`) whose items `respond` appends to `rewritten.rewrites`.
  timestamp: 2026-11-18T14:11:17.936704+00:00
- actor: claude-code
  id: 01m7qgmv1temjzp2hcmjcdd7gc
  text: |-
    Implementation landed (not committed).
    - New `SessionsAddressReader.swift`: `SessionsVisibility.messageAddress(_:from:)` is the one reader (D100). The tool calls it through `context.sessions`; the graph calls it through `context.address(_:from:)`, which keeps the external viewer rule. The candidates are the sessions that the viewer of the call can see (`sessions(matching:)` with no limit, recorded too). The lookup folder is the working folder of a session sender; a user sender has none.
    - `SessionsToolInput.addressForm(_:)` replaces `address(_:)`: it reads only the form (folder, tag, agent alias, id, name after @, short id with no @). A text with no @ names a session only by its short id; another bare word is still INVALID_ADDRESS.
    - A full id goes to `.session(id)` with no lookup, so the current NOT_FOUND (hidden session) and the archived refusal stay.
    - New refusal code `AMBIGUOUS_REFERENCE`. `unknownAgent` from a send becomes the corrective "No session and no agent has the name" (code UNKNOWN_AGENT stays).
    - Reusable for ^zkewpex: `SessionsVisibility.session(named:lookupFolder:)` (one session, or nil; it throws the ambiguity) and `resolution(of:lookupFolder:)`.
    - Brief item 6 (aliases of `short_id`, `fromSessionId`): those names are not in the schema of this task (no `shortId` field, no `fromSession` input), so there is no alias to add here.
    - Gap: the rewrite report in `extensions.rewrites` of the graph. Extras blocks it (see the research comment). Follow-up ^gxqmxj6, with a TODO in `SessionsGraphResolver.sendMessage`. The Extras session must get the precondition text of ^gxqmxj6.

    ### implement — stuck
    - evidence: 8 files — Sources/.../Sessions/SessionsAddressReader.swift (new), SessionsToolInput.swift, SessionsToolMessageOperations.swift, SessionsGraphMutations.swift, SessionsRefusal.swift, SessionsToolText+Messages.swift, Tests/.../SessionsToolMessageTests.swift, SessionsGraphMutationTests.swift. `swift build` clean. New tests: 10 tests (13 cases) red, then green. `swift test --filter "SessionsTool|SessionsGraph"`: 180 tests in 9 suites passed. Full `swift test`: 3017 tests in 270 suites passed, 0 warnings. The golden schema did not change.
    - next: the user decides on the extensions.rewrites gap (Extras change, ^gxqmxj6). All the other work is ready for /review.
  timestamp: 2026-11-18T14:23:20.122395+00:00
- actor: claude-code
  id: 01m7qgy2yfn3dxhq627sxvrhc6
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (d3cadc2a); 1 finding (1 confirmed, 2 refuted) — Sources/FoundationModelsMultitool/Capabilities/Sessions/SessionsGraphMutations.swift:416 (completeness/public-output-contract)
    - next: implement the finding. The fix can keep the TODO(^gxqmxj6) and add a test that asserts the current output of the sendMessage endpoint for an alias. Or carry the rewrite to the endpoint receipt.
  timestamp: 2026-11-18T14:28:23.119516+00:00
- actor: claude-code
  id: 01m7qgyhfdvjhagsnp56gm00y8
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — SessionsAddressReader.swift (new), SessionsToolInput, SessionsToolMessageOperations, SessionsGraphMutations, SessionsRefusal, SessionsToolText+Messages, 2 test files; the extensions.rewrites item moved to ^gxqmxj6
    - test: green — swift test, 3017 passed (run in the implement step)
    - commit: d3cadc2a
    - review: findings — Sources/FoundationModelsMultitool/Capabilities/Sessions/SessionsGraphMutations.swift:416
  timestamp: 2026-11-18T14:28:37.997205+00:00
- actor: claude-code
  id: 01m7qh3406khtmkzj9pryzcad8
  text: |-
    Review finding (SessionsGraphMutations.swift `sendMessage`, completeness/public-output-contract): fixed with the second fix, by decision of the coordinator. The TODO(^gxqmxj6) stays. The receipt type does not change.
    - New test in SessionsGraphMutationTests: "sendMessage to an alias delivers but gives no rewrite in extensions.rewrites yet (^gxqmxj6)" (`aSendToAnAliasGivesNoRewriteReportYet`), with 2 cases: `@travel:/work/trips` (a session with slug `travel` in the working folder and one in /work/trips; the receipt goes to the one in /work/trips) and the folder path `/work/other`. A device viewer sends. The test asserts no error, outcome DELIVERED, reason null, the target id, and `reply.rewrites.isEmpty`. A doc comment and a comment at the last assertion tell ^gxqmxj6 to change that assertion to expect the rewrite of the alias.
    - The test records the current behavior, so it passed on its first run. That is the purpose: it records the gap, and it fails when the endpoint output for an alias changes.
    - Same cause in the rest of SessionsGraphMutations.swift: none. `sendMessage` is the only mutation that reads a message address through `messageAddress`. The other mutations (start, tag, untag, rename, pin, unpin, archive, reply) take a session id, not an address alias. Their input-name aliases already show in `extensions.rewrites` (the bare verb and input alias tests). In the tool, `SessionsToolText.receipts(_:rewrite:)` of `send message` is the only output that carries a rewrite report.
    - `swift test --filter SessionsGraphMutationTests`: 23 tests in 1 suite passed. One build-system line, "warning: missing creator for mutated node" for the mlx-swift_Cmlx.bundle in .build, is from SwiftPM and not from the code.

    ### implement — changed
    - evidence: 1 file — Tests/FoundationModelsMultitoolTests/SessionsGraphMutationTests.swift; `swift test --filter SessionsGraphMutationTests`: 23 tests in 1 suite passed (the new test with 2 cases)
    - next: /review
  timestamp: 2026-11-18T14:31:08.038071+00:00
position_column: doing
position_ordinal: '80'
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

## Checklist of the work

- [x] One async reader: `SessionsVisibility.messageAddress(_:from:)` (`SessionsAddressReader.swift`). The `send message` operation and `Mutation.sendMessage` both call it.
- [x] Resolve `@<id>`, `<id>`, `@<short id>`, `<short id>` and `@<slug>` with `SessionReference.resolve` over the sessions that the caller can see.
- [x] Ambiguous reference: corrective `AMBIGUOUS_REFERENCE` with id, name and folder of each match; nothing is sent.
- [x] `@<name>` with no session: `.agent(id: name, folder: lookupFolder)`. The launcher is the agent catalog; `unknownAgent` becomes the corrective "No session and no agent has the name".
- [x] Alias `@agent:/path` and a folder path: the rewrite report in the tool answer.
- [x] MOVED to ^gxqmxj6: alias rewrite report in `extensions.rewrites` of `sendMessage`. Extras gives a resolver no way to add a rewrite. Follow-up ^gxqmxj6.
- [x] The tag form stays. The external viewer rule stays (REFUSED receipt for an unowned session).
- [x] Reusable resolve-to-one part for ^zkewpex: `SessionsVisibility.session(named:lookupFolder:)` and `resolution(of:lookupFolder:)`.
- [x] Text: `@Guide` of `to`, the description of `send message`, `SessionsToolText.addressForms` / `notAnAddress`, `SessionsGraphText.externalAddress`.

## Tests

- [x] Tool: send to `@<slug>` in the folder of the caller.
- [x] Tool: send to `@<short id>`, and to a full id with and without `@`.
- [x] Tool: an ambiguous slug gives a corrective with each match and sends nothing.
- [x] Tool: `@travel` with a session whose slug is `travel` goes to that session.
- [x] Tool: `@travel` with no such session and an agent folder `travel` starts one (receipt `started`).
- [x] Tool: `@travel:~/trips` looks in `~/trips` first and reports the rewrite.
- [x] Tool: `@nobody` gives the corrective.
- [x] Graph: `sendMessage(input: {to: "@<slug>", ...})` gives the same answer as the tool.
- [x] Graph: an external viewer with a slug of a session that it does not own gets a REFUSED receipt. #sessions #at-sessions #graphql

## Review Findings (2026-11-18 08:24)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 8 file(s) reviewed, 6 not reviewed.

> 6 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 6 file(s)

- [x] `Sources/FoundationModelsMultitool/Capabilities/Sessions/SessionsGraphMutations.swift:416` `completeness/public-output-contract` — The `sendMessage` endpoint reads the address with `.address` and drops the rewrite report from `SessionsAddressReading`. The `send message` tool reports the rewrite of an `@agent:/path` or folder alias, so the same send gives different output on the two surfaces. The endpoint's result is silently missing the rewrite line that the tool gives. Carry `rewrite` through to the endpoint receipt, or keep the TODO but add a test that asserts the current endpoint output for an alias, so the gap is recorded and cannot widen unnoticed.
