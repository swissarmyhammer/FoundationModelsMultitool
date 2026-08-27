---
assignees:
- claude-code
position_column: todo
position_ordinal: '9680'
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