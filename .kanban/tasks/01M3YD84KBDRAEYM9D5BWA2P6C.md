---
assignees:
- claude-code
position_column: todo
position_ordinal: '8380'
title: Give direct mode a runCode description that names the tools and does not name searchTools
---
## Problem

In direct mode (`MultiTool.Registry.directMode()`, the `--direct` option of the CLI), the registry mounts `runCode` and no `searchTools`. The description of `runCode` (`Sources/FoundationModelsMultitool/MultiTool.swift`, the text that starts "runCode is an isolated JavaScript runtime") still says: "Write one snippet calling the exact `tools.*` paths searchTools returned". No description gives the signatures of the tools of the catalog. Thus a model in direct mode has no correct source for a signature.

## Evidence

CI run 36951032341, `InBandCollectionCanaryTests.theDelayedEchoRoundTripsThroughMail` (direct mode), Router recording `FMMultitoolIntegration-882DBBF7-...`: the model reasoned "the only tool I have available is runCode ... I don't know the exact signature", called `tools.docs("echoAfterDelay")`, which does not exist, and learned the signature only from the correction of the failed snippet. The first call generated 531 tokens, and the run lost one full model turn (approximately 40 s on the runner `mini`).

## Work

- In direct mode, the description of `runCode` must not name `searchTools`.
- In direct mode, the model must get the signature of each catalog entry before its first snippet (for example, the description of `runCode` lists the declarations of the catalog, or another documented mechanism).
- Add a unit test that builds a direct-mode registry and checks the description text of `runCode`.

## Acceptance criteria

- [ ] A direct-mode `runCode` description names no `searchTools`.
- [ ] A direct-mode model can read the signature of each catalog entry with no failed snippet.
- [ ] A unit test covers both, and `swift test` passes.

Found by card `^3vtvrzg`.