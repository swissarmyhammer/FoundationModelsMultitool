---
assignees:
- claude-code
depends_on: []
position_column: todo
position_ordinal: '8880'
title: '[Router] RoutedSession elicitation replies: respond and complete'
---
Repo: ../FoundationModelsRouter. Basis: eventplan.md §"The ambient context" (host verb paragraph) and §"The elicitation envelope" (URL-mode two-step).

## What
The inbound answer route: app host → Router → mailbox → resume parked continuation. Add to the `RoutedSession` surface (protocol extension conveniences at RoutedSession.swift:529-664 are the natural home, alongside `awaitingUser`):
- `respond(elicitationId: String, response: ElicitationResponse) async` — look up the pending elicitation in the session's `SessionMailbox` and resume it. Answers address the elicitation, never the run — one run can hold several pending elicitations. Unknown or already-completed ids are safe no-ops per the MCP spec.
- `complete(elicitationId: String) async` — URL-mode second step: the accept only meant the user agreed to open the URL; completion arrives separately. The mailbox holds a URL-mode elicitation open past the accept until this arrives. Duplicates and unknown ids are safe no-ops.
- Semantics: a form-mode `accept` resumes with `content`; `decline` and `cancel` resume with those actions — a declined elicitation is not a cancelled run; the tool decides what to do.
- The route uses no task locals: `respond`/`complete` → `RoutedSessionActor` → that session's mailbox → the entry → its continuation. References the whole way; two sessions sharing a registry can never cross-route.
- Documentation: Router's `plan.md` asserts in SEVERAL places that Router does not implement elicitation ("elicitation lives in FoundationModelsACPAgent" at lines ~850-854; "elicitation itself — it owns no user channel; the coordinator lives in …" at ~1181; a related statement near ~815 — grep `plan.md` for "elicit" and update every such paragraph). This task reverses that decision per eventplan.md: record that Router carries the typed envelope and the resume plumbing while the presenting UI stays the host app's. No remaining `plan.md` sentence may deny Router's elicitation ownership.

## Acceptance Criteria
- [ ] A parked `ToolContext.elicit` on a session resumes when `respond(elicitationId:response:)` is called on that session, with the exact response passed through
- [ ] URL-mode: after `respond(.accept)` the run is still parked; it resumes only on `complete(elicitationId:)`; a duplicate `complete` is a no-op
- [ ] Two pending elicitations on one run resolve independently; responding to one leaves the other parked
- [ ] Unknown-id `respond`/`complete` are no-ops
- [ ] `grep -i elicit ../FoundationModelsRouter/plan.md` shows no remaining sentence denying Router's elicitation ownership (all occurrences updated: ~850-854, ~1181, ~815)
- [ ] `cd ../FoundationModelsRouter && swift test` green

## Tests
- [ ] Extend `Tests/FoundationModelsRouterTests/SessionMailboxTests.swift` / new `ElicitationRoutingTests.swift`: form round trip through a real `RoutedSession`-level call; URL two-step; double-elicit independence; unknown-id and duplicate no-ops; cross-session isolation (respond on session A never resumes session B's elicitation)
- [ ] `cd ../FoundationModelsRouter && swift test` green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #phase-1 #router-first