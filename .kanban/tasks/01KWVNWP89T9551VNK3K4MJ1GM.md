---
depends_on:
- 01KWVNVV79AAK6FDHRJF329QVR
position_column: todo
position_ordinal: '8680'
title: Port the gated integration suite to the LanguageModelSession-driven design, and gate old-loop deletion on it passing
---
## What
Part of the MultiToolAgent removal pivot (see board). Depends on `f329qvr` (the new canonical `LanguageModelSession`-based example must exist).

**Package.swift dependency**: same as `f329qvr` — add `.product(name: "MLXFoundationModels", package: mlxPackage)` to the `FoundationModelsMultitoolIntegrationTests` target's dependencies (it will need to construct `MLXLanguageModel`/`LanguageModelSession` directly, same as the CLI).

The existing gated integration suite (`Tests/FoundationModelsMultitoolIntegrationTests/`: `PrefixReuseTests`, `SearchThenCallTests`, `CLISmokeTests`, `AgentEvaluation.swift`, `Support/IntegrationGate.swift`, `Support/ScenarioRunner.swift`) is the *only* thing that ever empirically validated this package's real-model behavior — it's what surfaced the model-comparison data, the `.guided`-mode blank-field failure, the Router token-cap bug (since fixed upstream), and the metadata-cache bug (since fixed upstream, task `55915ac`). **Do not delete this suite as a side effect of removing `MultiToolAgent`.** Port its scenarios to the new design first, and require them to pass on real hardware before the old-loop deletion task proceeds — this is the safety gate that prevents shipping a less-tested replacement.

Port these specific scenarios, retargeted at a `LanguageModelSession(tools: [multiTool, findAPIsTool])`-driven run instead of `MultiToolAgent.respond(to:)`:
- **Prefix reuse** (`PrefixReuseTests`): confirm `findAPIsTool`'s own internal Router-backed selection tier still gets fork-inherited-prefix reuse (second `search(intent:limit:)` call not slower than the first cold-prefill call) — this scenario is about the *selection tier's* Router session, which task `4aveepp` keeps Router-backed specifically to preserve this property, so it should port with minimal change.
- **Selection accuracy / discovery-then-call composition** (`SearchThenCallTests`): the ~20-distractor scenario selecting `tripCities`+`weather` and composing a `runCode` snippet using their results — this now exercises *native* tool-calling picking `findAPIsTool` then `multiTool` in sequence, which is exactly what depends on the upstream multi-turn fix (`qp8q4h9`) — if that fix hasn't landed, this scenario is expected to fail in a specific, diagnosable way (falls through to plain text after the first tool call); document that expected-failure mode clearly if hit, rather than treating it as a mysterious regression.
- **CLI smoke test** (`CLISmokeTests`): exercises the rebuilt `multitool-cli` end to end.
- Retire `AgentEvaluation.swift`'s Apple-`Evaluations`-framework-based scoring if it was purely about the old loop's transcript format (`TranscriptAnalyzer`); if any of its metrics generalize to the new design, port them, otherwise document why they don't apply anymore.

**The gate**: this task's acceptance criteria are NOT satisfied by "ported code that builds" — they require an actual green run on real hardware, at a baseline at least as good as the old design's best-observed result (the 9B `.tolerantParse` run's 7/8 on `SearchThenCallTests`, documented on the now-archived task `exbtj1n`). Record the actual pass rate. The following task (`7840f24`, deleting `MultiToolAgent`/`TurnFormat`/etc.) must not proceed until this task reports a real, hardware-verified pass at or above that baseline — or an explicit, reasoned exception (e.g. "still blocked on `qp8q4h9`, tracked separately, old loop can be deleted anyway because X"). This go/no-go note is a human/agent judgment call recorded as a task comment, not something CI enforces — `7840f24` is written to explicitly require reading it before proceeding (see that task).

## Acceptance Criteria
- [ ] Package.swift's `FoundationModelsMultitoolIntegrationTests` target links `.product(name: "MLXFoundationModels", package: mlxPackage)`.
- [ ] Ported `PrefixReuseTests`-equivalent passes on real hardware: fork-inherited prefix reuse holds for `findAPIsTool`'s selection tier.
- [ ] Ported `SearchThenCallTests`-equivalent run on real hardware, with the actual pass rate recorded (target: ≥7/8, matching the old 9B `.tolerantParse` baseline) — if blocked by the upstream `qp8q4h9` fix not yet landing, document that explicitly as the reason for any shortfall.
- [ ] Ported `CLISmokeTests`-equivalent passes against the rebuilt `multitool-cli`.
- [ ] Plain (ungated) `swift test` remains green throughout.
- [ ] A clear go/no-go note is recorded (as a task comment) on whether the old-loop-deletion task (`7840f24`) is cleared to proceed.

## Tests
- [ ] `MULTITOOL_INTEGRATION=1 swift test --filter FoundationModelsMultitoolIntegrationTests` (or whatever the retargeted suite's filter becomes) run on real hardware, with results recorded.
- [ ] Full `swift test` (ungated) passes.

## Workflow
- Use `/tdd` for any new scaffolding/support code (a `LanguageModelSession`-based equivalent of `IntegrationGate`/`ScenarioRunner`). The scenario ports themselves are validated empirically on real hardware, not purely by unit tests — record actual run results as the evidence.
