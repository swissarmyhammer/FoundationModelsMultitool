---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5f66ypptpxv5wjyf7jc01wt
  text: 'Per-package record — skills: DONE. FoundationModelsSkills origin/main d694b08 (3bf828d graph, f0f7244 tool conformance, 9711ce2 changes/cursor). Conformance passes with codes: [] and exceptions: [] against Extras 9c47e10. 690 tests green.'
  timestamp: 2026-10-21T12:15:40.246830+00:00
- actor: claude-code
  id: 01m5f691yb717mcjft77pb5csj
  text: 'ACPAgent owns the end-to-end check as ^y673pyv: a composed session''s top-level tools give the settings and snapshots endpoints (name, version, scope). It lands with ACPAgent''s Extras+Multitool update. The default snapshots resolver (session id = session key) fits: ACPAgent''s snapshot key is the ACP session id raw value (AgentHooks.swift:115, SessionLifecycle.swift:64).'
  timestamp: 2026-10-21T12:16:49.099412+00:00
- actor: claude-code
  id: 01m5fcdnbj65h1eefzv7n389px
  text: 'Per-package record — agents: DONE. FoundationModelsAgents origin/main 712bcbb (AG-8a 0579ae2/d700d4c, AG-8b cec9897/5a3706e, AG-8c pushed after the user overrode a review rule that asked for `private` on cross-type members). Conformance passes with no exceptions. 664 tests green.'
  timestamp: 2026-10-21T14:04:11.506484+00:00
- actor: claude-code
  id: 01m5g2ntx5z3fbhjwk4pt7f22t
  text: 'skills: the subscription alias probe cleanup is done (Skills 325045e, test b9270e9). The conformance check covers both the query and the subscription alias probes and reports no problems, with no exceptions.'
  timestamp: 2026-10-21T20:33:08.005230+00:00
- actor: claude-code
  id: 01m5hk9h1swbqjn2n0hhhs4b09
  text: |-
    Conformance checklist (2026-10-22). Each line is the commit where the endpoint's conformance passes with exceptions: [].
    - [x] skills: Skills d694b08, with the subscription probe added in 325045e
    - [x] agents: Agents 712bcbb
    - [x] kanban: Kanban bd01871 (endpoint v2, EndpointConventionTests exceptions: [])
    - [x] sessions: Multitool 64f159f, ownership fields in f39b153
    - [x] snapshots: Multitool 31943bf (the rule-9 exception was removed), latest is 94c992c
    - [ ] settings: waiting for the ACPAgent sha

    HOOKS-1/2 are owned and done (Hooks 226bb35, 80e0250). EXTRAS-10/11 are done. D115 is agreed (TestudoApp 75e32b3).
  timestamp: 2026-10-22T10:42:44.921753+00:00
- actor: claude-code
  id: 01m5hkkbs5644pkshvhrt79p5e
  text: |-
    Checklist update, 2026-10-22:
    - [x] settings: ACPAgent 88bcfa0 passes conformance with no exceptions, with query and subscription probes (`settingsChanges` → `changes`).
    - [x] agents: 712bcbb plus later commits; probes cover both a query (agentNameProbe) and a subscription (changes).
    - [ ] kanban: bd01871 has no exceptions, but it probes only a mutation alias (`createTask` → `addTask`). It has no subscription alias probe, and possibly no `kanbanChanges` alias. The Kanban session is gone, so this needs an owner (asked the user).
  timestamp: 2026-10-22T10:48:07.205506+00:00
- actor: claude-code
  id: 01m5hm6navswsbk2mt8jcmqz8c
  text: |-
    Final checklist, 2026-10-22. All six endpoints pass conformance with no exceptions, and each has both a query/mutation alias probe and a subscription alias probe:
    - [x] skills: Skills d694b08 / 325045e
    - [x] agents: Agents 712bcbb
    - [x] kanban: Kanban 577850d (kanbanChanges → changes; Extras pinned at 34b7783)
    - [x] settings: ACPAgent 88bcfa0 (settingsChanges → changes)
    - [x] sessions: Multitool 64f159f (sessionChanges), ownership fields in f39b153
    - [x] snapshots: Multitool 31943bf (snapshotChanges), latest 94c992c

    Note from Kanban: `swift package update FoundationModelsExtras` fails there with "swift-case-paths unresolved" (a trait-disabled dependency of swift-parsing), so Kanban pinned Package.resolved by hand. Other packages may hit the same error.
  timestamp: 2026-10-22T10:58:39.579598+00:00
position_column: done
position_ordinal: ffffffbc80
title: 'Coordinate: GraphQL endpoint conventions across the family (EXTRAS-9, D115)'
---
## What
A standing coordination card for this session. The user asked the Multitool session to keep settings, snapshots, sessions, agents, skills and kanban consistent as they conform to `GraphQLEndpointTool`, so TestudoApp (APP-16) can read them with one client model. The rules: EXTRAS-9/10/11 in `../TestudoApp/features/packages/foundationmodels-extras.md` and D115 in `../TestudoApp/features/decisions.md`.

MT-11 FilesGraph is deferred: not in the user's list of six; it reuses the MultiTool endpoint plumbing of 01M5F200PV1QFFH82EK6197PXX when scheduled.

Owners and peer cards:
- settings: foundationmodelsacpagent (`^hfw2eqh` mutations, `^sn3pz3s` changes; `^2b2eccw` ACPA-13 viewer, blocked on ACPA-5 agreement)
- skills: foundationmodelsskills (`01M5F230NX5CY90TNJP53Y1QD6`, `01M5F237DGF69WGB5QSTBWVZ2F`, `01M5F23EYC7GEW1B2BZHPT8953`)
- kanban: foundationmodelskanban (`jk3fc4g`, `d7sgpaz`, `esc56vk`, `5pf8w1x`, `e60e9sx`)
- agents: foundationmodelsagents (`^b8w613y`, `^wk71647`, `^20mv6d3`)
- sessions directory: foundationmodelsrouter (asked to own EXTRAS-3/4; no reply yet)
- snapshots, sessions graph, MultiTool endpoints: this board
- No owner yet: EXTRAS-10, EXTRAS-11 (Extras), HOOKS-1, HOOKS-2 (Hooks), APP-16 server registry (TestudoApp)

Steps:
- [ ] Fold peer feedback into EXTRAS-9 and broadcast each rule change to every owner
- [ ] Get owners for EXTRAS-10/11 and HOOKS-1/2 (ask the user)
- [ ] When EXTRAS-11 lands: every endpoint's conformance test passes, or lists exceptions with card ids
- [ ] Move EXTRAS-9/10/11 and D115 from proposed to agreed when the user approves; commit the TestudoApp doc changes

Per-package conformance record (commit sha where the conformance test passes with no exceptions):
- settings: pending
- snapshots: pending
- sessions: pending
- agents: pending
- skills: pending
- kanban: pending

## Acceptance Criteria
- [ ] This repo's snapshots and sessions graph tests pass with `swift test`
- [ ] A per-package checklist in this card records, for each of the six endpoints, the commit sha where its conformance test passes with no exceptions

## Tests
- [ ] `swift test` passes in this repo

#graphql #coordination