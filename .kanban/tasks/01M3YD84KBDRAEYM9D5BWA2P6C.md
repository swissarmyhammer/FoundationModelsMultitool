---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3yn4pbk3jkq15g11r6nnafd
  text: |-
    Research:
    - `MultiTool.description` is a stored `let` with one text for the two modes. The mode is `holder.current.registry.isDirectMode`. The holder can swap the registry at a submission boundary, so the direct-mode text must be computed from the current bundle, not stored at init.
    - Each catalog entry has `descriptor.declaration` (`declare function name(args: ...): Promise<...>;`) and a private `banner` (`// tools.<path>`). `APISurface.Entry.block` is banner + full JSDoc + declaration; `docs("<path>")` in a snippet returns that block.
    - The `@Guide` of `RunCodeArguments.code` also says "Call the exact paths searchTools returned". The macro makes this text at compile time, so it cannot change with the mode. The model reads it in the argument schema in direct mode too.
    - In the CI run the model called `tools.docs("echoAfterDelay")`. `docs` is a global, not a `tools.*` path.
    Plan: compose the description from one function with the mode-specific clauses as arguments; the discovery wording stays the same. Direct mode appends the banner + declaration of each catalog entry. Make the `@Guide` text mode-neutral.
  timestamp: 2026-10-02T15:53:47.635996+00:00
- actor: claude-code
  id: 01m3ynkmsbkscr0btexxwyhymc
  text: |-
    Implementation landed (TDD).
    - RED: two new tests in `MultiToolExecutionTests` (`directModeRunCodeNamesNoSearchTools`, `directModeRunCodeDeclaresEachCatalogEntry`) failed for the right reason: the description and the argument schema held "searchTools", and no declaration was in the description.
    - Change: `MultiTool.description` is now a computed property in the new file `MultiTool+Description.swift`. It reads the mode of the current registry from the holder at each read, so a staged registry swap changes the text too. Discovery mode gives the same words as before (one shared template; the only byte change is a line break that became a space before "never appear in searchTools"). Direct mode says "the exact `tools.*` paths declared below", points at `docs("globals")` and `docs("<path>")`, and appends "The functions under `tools.*`:" with a `// tools.<path>` banner and the `declare function` line of each catalog entry (`APISurface.Entry.declarationBlock`, `APISurface.declarations`).
    - Discovery-mode change, and why: the `@Guide` of `RunCodeArguments.code` said "Call the exact paths searchTools returned". The macro makes that schema one time for the two modes, so it cannot change with the mode, and the model reads it in direct mode too. It now says "Call only the exact `tools.*` paths this session gave you." The discovery-mode description text is unchanged.
    - GREEN: the two tests pass. Full `swift test`: 1895 tests in 155 suites passed, 0 failures. The only warning is the build-system line "missing creator for mutated node ... mlx-swift_Cmlx.bundle", which also shows on the RED run before the change and does not come from source code.
    - `swift build --build-tests --package-path IntegrationTests`: Build complete.
    - Live canary, `swift test --package-path IntegrationTests --no-parallel --filter InBandCollectionCanaryTests`: 1 test passed in 38.8 s. The first and only snippet was `tools.echoAfterDelay({ value: "BFBB59068C9F" })`. The model called no tool that does not exist and had no failed snippet (recording `FMMultitoolIntegration-22AB867E-4A39-43C9-94F9-46F0D3F44324`).
    - Note: `ARCHITECTURE.md` does not exist; no update is necessary.
  timestamp: 2026-10-02T16:01:57.547781+00:00
- actor: claude-code
  id: 01m3ynkshcnazeyn9990j4vc02
  text: |-
    ### implement — changed
    - evidence: 4 files — Sources/FoundationModelsMultitool/MultiTool+Description.swift (new), Sources/FoundationModelsMultitool/MultiTool.swift, Sources/FoundationModelsMultitool/Surface/APISurface.swift, Tests/FoundationModelsMultitoolTests/MultiToolExecutionTests.swift. `swift test`: 1895 passed, 0 failed. IntegrationTests build: complete. Live InBandCollectionCanaryTests: passed, no call to a tool that does not exist.
    - next: /review
  timestamp: 2026-10-02T16:02:02.412932+00:00
- actor: claude-code
  id: 01m3ynvqh62nmhg2gq764evqy4
  text: |-
    ### test — green
    - evidence: `swift test` at root: 1895 tests in 155 suites passed, 0 failed, 0 skipped, no warning from package sources. The one warning is the build tool note "missing creator for mutated node" for the mlx-swift_Cmlx bundle (a dependency, not this package).
    - evidence: `swift build --build-tests --package-path IntegrationTests`: build complete, 0 errors, 0 warnings from IntegrationTests sources (same dependency note only).
    - evidence: `swift test --package-path IntegrationTests --no-parallel --filter 'InBandCollectionCanaryTests|SearchThenCallTests|ShellBackgroundTests'` on the real models, one run: 4 tests in 3 suites passed. Direct mode: InBandCollectionCanaryTests (delayed echo, 28 s). Discovery mode: SearchThenCallTests (2 tests) and ShellBackgroundTests (1 test).
    - next: review, then commit.
  timestamp: 2026-10-02T16:06:22.502794+00:00
- actor: claude-code
  id: 01m3ynw9xaf60fvpc99eh01y8w
  text: |-
    ### commit — changed
    - evidence: this commit: feat(root): list the tool declarations in the direct mode runCode description
    - next: review
  timestamp: 2026-10-02T16:06:41.322460+00:00
position_column: doing
position_ordinal: '8180'
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

- [x] A direct-mode `runCode` description names no `searchTools`.
- [x] A direct-mode model can read the signature of each catalog entry with no failed snippet.
- [x] A unit test covers both, and `swift test` passes.

Found by card `^3vtvrzg`.