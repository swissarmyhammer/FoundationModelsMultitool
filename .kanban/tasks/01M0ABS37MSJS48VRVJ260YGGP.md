---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0ac4dwfqf76brgac1xnsy76
  text: |-
    Picked up. Research before editing:

    - `CLIRunner.runDemo` builds `LanguageModelSession(model: Self.makeMLXLanguageModel(for: profile.standard), tools: tools)` and calls `respond(to:)`.
    - The working reference is `ScenarioRunner.runNativeIntegrationScenario` / `runElevationIntegrationScenario`: `fixture.profile.standard.makeSession(tools:discoveryPriming:)` (a `RoutedSession`), drained by `streamTurn(of:prompt:)` over `await session.streamEvents(to: prompt)`.
    - `RoutedLLM.makeSession(...)` needs no `await`; `streamEvents(to:)` is awaited. Router's own `LiveModelLoader` declares `capabilities: [.guidedGeneration, .toolCalling, .reasoning]`, so a Router-vended session drives native tool calling — which is the only thing `makeMLXLanguageModel(for:)` was added for.
    - Callers of `makeMLXLanguageModel(for:)`: **none** outside `runDemo`. Every other mention is a doc comment (`ScenarioRunner.swift`, `IntegrationGate.swift`, `ExamplesTests.swift`, `README.md`, `Package.swift`); the gated suite stopped calling it when it moved to `makeSession`. So it goes, together with its only helper `weightsLocation(for:)`.
    - `SessionEvent` has 12 cases; the drain must switch over all of them.

    Plan: add an ungated, model-free unit test over a new `CLIRunner.drainTurn(_:output:)` that takes an `AsyncThrowingStream<SessionEvent, Error>`, so the streaming drain is testable with a synthetic stream; then wire `runDemo` to `profile.standard.makeSession(tools:)` + `streamEvents(to:)`.

    Constraint noted: `Package.swift` must not be edited, and two of its comments name `CLIRunner.makeMLXLanguageModel(for:)`. That drift will be filed as its own card.
  timestamp: 2026-08-18T12:04:27.663825+00:00
- actor: claude-code
  id: 01m0acs3cas6f0skz6cs76cdrx
  text: |-
    Implementation landed. What was done, and why each part is shaped the way it is:

    **The wiring.** `runDemo` now builds `profile.standard.makeSession(tools: tools)` and drives one turn through a new `CLIRunner.drainTurn(_:output:)` over `await session.streamEvents(to: demoPrompt)`. The mount site states, in the code, that no run of this demo will ever show a detachment because `DemoTripTool`/`DemoWeatherTool` answer instantly — the wiring carries the design, the fixtures only keep the demo quick — and points at the gated elevation scenario as the place a slow tool proves it. The `respond(to:)` self-drain (Router `^nmpejc5`) is named at the call site as the road not taken, with the reason: only the stream can report a tool while that tool is still working.

    **The drain is a named function on purpose.** `drainTurn` takes an `AsyncThrowingStream<SessionEvent, Error>` rather than a session, so the whole streaming behaviour is testable with no model, no Router and no network. `Tests/FoundationModelsMultitoolTests/CLITurnDrainTests.swift` (new, 7 tests) drives it over scripted event streams: text accumulation, `.textReset` dropping the superseded answer, the tool-call line, a still-running tool's progress line, a failed call's line, the stall report, and error propagation. Written test-first — the first six failed with "type 'CLIRunner' has no member 'drainTurn'", and the stall test was watched failing on its own before the `.generationStalled` case was added.

    **`makeMLXLanguageModel(for:)` is deleted**, with its only helper `weightsLocation(for:)`. Nothing called it once the session came from the profile: every other mention in the tree was a doc comment. Router's own `LiveModelLoader` declares `[.guidedGeneration, .toolCalling, .reasoning]`, so a Router-vended session drives native tool calling — which was the only reason that factory existed.

    **Imports: three had to come back.** Removing `HuggingFace`, `MLXLMCommon` and `Tokenizers` broke the build *inside* the `#hubDownloader()`/`#huggingFaceTokenizerLoader()` macro expansions ("cannot find 'HubClient' in scope", "cannot find type 'MLXLMCommon'", "cannot find 'Tokenizers'"): a macro expands at the call site and resolves against that file's imports. The import block now records this so the next reader does not repeat the experiment. `MLXFoundationModels` and `MLXVLM` are gone — Router imports what the load path needs, and `Package.swift` links it.

    **Doc comments that named the deleted symbol** were corrected in `ScenarioRunner.swift`, `IntegrationGate.swift`, `ExamplesTests.swift`, `CLISmokeTests.swift` and `main.swift`. Two of them were already stale before this card: `IntegrationGate` claimed "the main session itself is never Router-vended, so it is never recorded here", which stopped being true when the scenarios moved to `makeSession`.

    **README** now leads with the `RoutedSession` contract, states what a bare session costs, and its example ends by draining `streamEvents(to:)` instead of calling `respond`.

    Filed rather than fixed here:
    - `^yzhpjab` — `Package.swift` comments name the deleted symbol and justify an `MLXFoundationModels` dependency no target uses. This card was told not to edit `Package.swift`.
    - `^mxjt7y5` — `plan.md` M9 still teaches the bare-session wiring, and README points readers at it.
    - `^523qwcy` — README names `Muse-Glimmer-30B-4bit` where `CLIRunner.generationModel` is `Qwen3.8-27B-mxfp4`. Left alone deliberately: a model pin is a separate decision from this card's wiring.
  timestamp: 2026-08-18T12:15:45.034715+00:00
- actor: claude-code
  id: 01m0acs9sa0pagnnhz9t03mstq
  text: |-
    ### implement — changed
    - evidence: 8 files — Sources/multitool-cli/CLIRunner.swift, Sources/multitool-cli/main.swift, Tests/FoundationModelsMultitoolTests/CLITurnDrainTests.swift (new), Tests/FoundationModelsMultitoolTests/ExamplesTests.swift, Tests/FoundationModelsMultitoolIntegrationTests/CLISmokeTests.swift, Tests/FoundationModelsMultitoolIntegrationTests/Support/ScenarioRunner.swift, Tests/FoundationModelsMultitoolIntegrationTests/Support/IntegrationGate.swift, README.md. `swift test`: 359 tests / 30 suites and 59 tests / 11 suites, all passed, zero warnings. `swift build --build-tests` clean.
    - next: /review. Then one gated `MULTITOOL_INTEGRATION` run for the two unchecked test boxes — the GPU was promised to another session during this one.
  timestamp: 2026-08-18T12:15:51.594601+00:00
position_column: doing
position_ordinal: '8380'
title: The shipped CLI builds a bare LanguageModelSession, so the one runnable demo cannot detach at all
---
`CLIRunner.runDemo` — the package's only runnable demonstration, and the reference host its own documentation names — builds a bare `FoundationModels.LanguageModelSession` and calls `respond(to:)`:

    Sources/multitool-cli/CLIRunner.swift:458   let session = LanguageModelSession(model: mlxModel, tools: tools)
    Sources/multitool-cli/CLIRunner.swift:468   let response: ... = try await session.respond(to: demoPrompt)

## Why that is wrong

`MultiTool.Registry.makeSessionTools`' own doc comment states the host contract: mount what it returns **on a `RoutedSession`**, and drive that session by draining `streamEvents(to:)`. The CLI does neither.

The session type is not a detail. A `RoutedSession` mounts each tool under `DetachConfiguration.nativeSessionMount`, which is what makes a slow `runCode` park and answer with a pending envelope the model collects with `wait`. On a bare `LanguageModelSession` none of that machinery exists: the snippet simply blocks, no envelope is ever written, and the `wait` tool the registry mounts has nothing to join.

So the demo we ship exercises `searchTools` and `runCode` as plain blocking calls. Detachment, elevation, pending envelopes and in-band collection — the design this package is *for* — are absent from it. It reads correctly only because `DemoTripTool` and `DemoWeatherTool` return instantly.

`ScenarioRunner.swift` says the same thing from the other side: on that path "a slow snippet simply blocks and a pending envelope can never appear."

## What this costs

- **`CLISmokeTests` grades a configuration the contract does not describe.** It is our only end-to-end check of the shipped binary, and it passes without touching the detachment path.
- **A reader copying the README's reference host gets the non-detaching wiring.** The README points at `CLIRunner.runDemo` as the canonical example.
- **`^tkrdwb8` recorded this as a divergence** and closed around it: the harness was corrected to the contract while the reference host was left behind. The criterion "the harness must match the reference host" was satisfied backwards — the harness is right and the host is wrong.

## What the fix is

Build the session the way the gated suite already does, which is the wiring the contract names:

    profile.standard.makeSession(tools: ...)      // a RoutedSession
    ... drained via streamEvents(to:)

`ScenarioRunner.makeScenarioSurface` / `streamTurn` are the working reference. Note `RoutedSession.respond(to:)` now self-drains the run plane (Router `^nmpejc5`), so `respond` is defensible for a one-shot demo — but `streamEvents` is what the contract states and what every scenario drives, and a demo that shows the streaming path is worth more than one that hides it.

Check whether `makeMLXLanguageModel(for:)` is still needed once the session comes from the profile, and whether the gated target still depends on it, before deleting anything.

## Acceptance Criteria

- [x] `CLIRunner.runDemo` drives a `RoutedSession` obtained from the resolved profile, not a bare `LanguageModelSession`
- [x] The turn is driven the way the host contract states, and the doc comment recording this divergence is removed because it is no longer true
- [x] A slow tool in the demo would park and produce a pending envelope rather than block — stated in the code where a reader will meet it, since the fast fixtures mean no run will demonstrate it
- [x] `makeMLXLanguageModel(for:)` is kept, deleted or narrowed on the basis of who still calls it, not left dangling
- [x] The README's claim that `CLIRunner.runDemo` is the canonical example is true again

## Tests

- [x] Ungated `swift test` green
- [ ] Gated `CLISmokeTests` passes against the new wiring — this is the check that actually changes meaning, because it will now exercise the mounted detachment path
- [ ] The full gated suite still passes, since `ScenarioRunner` reuses `CLIRunner`'s production wiring

**The two gated boxes are unrun, not failed.** The implementing session was told the GPU was promised to another session, so no `MULTITOOL_INTEGRATION` run was started. Both need one gated run before this card is done.