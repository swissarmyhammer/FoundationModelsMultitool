---
assignees:
- claude-code
depends_on:
- 01KZ6N3KMERCMS4DCMEFHR27KF
position_column: todo
position_ordinal: 8f80
title: '[MultiTool] MultiTool as host-and-emitter'
---
Repo: this repo. Basis: eventplan.md §"MultiTool is a host and an emitter".

## What
- `MultiTool` conforms to `EventEmittingTool` (Router's canonical protocol post-move): Router finds it with the same conformance cast it uses today and connects the session outbox, without change.
- `connecting(_ sink:)` returns a copy whose sink wrapper updates the session mailbox first and then sends the event upstream to the connected sink — one connection point, two consumers, no new protocol.
- At `buildRegistry()` time (`Surface/MultiToolBuilder.swift`), MultiTool finds emitters among its registered tools with the same conformance cast and connects each to its mailbox-first sink — the wiring Router does today, one level down. (Registered emitters are rare in phase 1; the wiring is the point — shell becomes the reference emitter in phase 2.)
- `ForkableTool`: decide and document whether `MultiTool` needs a real `forked()` (its precomputed registry/preamble are immutable; per-run state lives in `RunBinding`s — the default identity `forked()` is likely correct; record why in the conformance doc).

## Acceptance Criteria
- [ ] `(multiTool as? any EventEmittingTool)?.connecting(sink)` works through Router's existing cast-and-connect map with zero Router-side changes
- [ ] An event posted by a registered emitting fixture tool lands in the mailbox first, then the upstream sink (ordering observable via a recording sink)
- [ ] An event posted by the engine for an elevated inner run flows through the same wrapper (mailbox then upstream)
- [ ] `swift test` green

## Tests
- [ ] New `Tests/FoundationModelsMultitoolTests/HostAndEmitterTests.swift`: conformance cast; mailbox-then-upstream ordering; registry-level emitter wiring with a fixture `EventEmittingTool`; connecting purity (original instance unchanged)
- [ ] `swift test` green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #phase-1