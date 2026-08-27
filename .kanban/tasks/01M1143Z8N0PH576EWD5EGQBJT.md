---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m129efchjkzawbmvk7rhzxtk
  text: |-
    ### stub — done
    - evidence: Router task 01M1142266PPAYQ22X4GHKGSSD is in done and on origin/main (Router HEAD 760ae89): `Hosting/LostRunError.swift`, and the `.lost` branch at `ToolRun.swift:205`. A probe `func f(_ e: any LostRunError)` in this package builds: `swift build` — Build complete.
    - next: none. The call-path task ^w7vk7sv is unblocked by this.
  timestamp: 2026-08-27T18:59:17.521517+00:00
position_column: done
position_ordinal: ff9680
title: 'Tracking stub: Router LostRunError → .lost (Router task 01M1142266PPAYQ22X4GHKGSSD)'
---
## What
This is a tracking stub. The work is on the **FoundationModelsRouter** board: task `01M1142266PPAYQ22X4GHKGSSD` (`ghkgssd`), "Map a transport-drop error to OperationOutcome.lost (LostRunError)". An agent in `/Users/wballard/github/swissarmyhammer/FoundationModelsRouter` implements it.

This stub holds the dependency edge for "Rewrite MCPServer.call onto the run plane" (`01M112CTS4HSY5R312NW7VK7SV`) on this board. Do not implement anything here.

## Acceptance Criteria
- [ ] The Router task is done and its commit is on Router `main`.
- [ ] `LostRunError` resolves in this package after `swift package update FoundationModelsRouter`.

## Tests
- [ ] `swift build` in this package succeeds against the updated Router.

## Workflow
- A human moves this stub to done after the Router task lands. Tagged `stuck` so `/finish` does not pick it up. #eventplan #phase-4 #router-first #stuck