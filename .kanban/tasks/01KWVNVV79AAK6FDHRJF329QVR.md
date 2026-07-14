---
comments:
- actor: claude-code
  id: 01kwvwqz51nawgak49c5kvbf3s
  text: '**Review note — guard against reintroducing an agent loop.** The description says "don''t design around the bug permanently" re: the upstream `qp8q4h9` single-tool-call-per-turn limitation. To be explicit: this must NOT be worked around with a temporary hand-rolled continuation loop either (e.g. detecting a fall-through-to-text after a tool result and calling `session.respond` again with re-injected context, or any turn-parsing/re-prompt machinery). The whole point of this pivot is that `LanguageModelSession` owns the tool-calling loop. If the upstream fix hasn''t landed, the accepted interim state is: one native tool call per turn, with the gated `SearchThenCallTests` port (`k4mj1gm`) documenting the shortfall as an expected, upstream-attributed failure. Exactly one `session.respond(to:)` call per user prompt in the demo — no loop of any kind in this package.'
  timestamp: 2026-07-06T14:19:03.201949+00:00
- actor: claude-code
  id: 01kxekt4apnv9f5s7bfs5r79nk
  text: |-
    Implementation complete. Rewrote `Sources/multitool-cli/CLIRunner.swift`'s `runDemo` to build the canonical Router + LanguageModelSession + MultiTool example:

    - Resolves `demoProfile` via Router as before.
    - Builds `MultiTool.Registry` via `MultiTool.Builder` (unchanged); `MultiTool(registry:)` wraps it as a real `Tool`.
    - New private `makeMLXLanguageModel(for:)` wraps the resolved `profile.standard` (`RoutedLLM`) as a fresh `MLXLanguageModel(configuration:capabilities:[.guidedGeneration, .toolCalling]:weightsLocation:load:)`, using `ModelConfiguration(id: routedLLM.chosen.repo, revision: ...)` — same model id the Router already loaded. `MLXLanguageModel` caches its `ModelContainer` in a process-global `ModelCache` keyed by model id (see `mlx-swift-lm`'s `MLXLanguageModel.swift`), so this reuses the already-resident weights without re-downloading/re-resolving. Declares `.toolCalling` (which Router's own internal model does not) so the session can register real `Tool`s.
    - Builds `LanguageModelSession(model: mlxModel, tools: [multiTool] + (direct ? [] : [findAPIsTool]), instructions:)` and calls `session.respond(to: demoPrompt)` exactly once — no hand-rolled loop, no re-prompt/continuation logic anywhere in this file.
    - `--direct` now means "omit `findAPIsTool` from the session's tools" (multiTool only), matching the task's decision.
    - `findAPIsTool` (when included) is still backed by its own separate Router-resolved `profile.flash` session via `FindAPIsTool(registry:librarian:)` (task 4aveepp's work) — the "librarian on flash" split is preserved, independent of the main session's `mlxModel`.
    - Deleted `traceLines`/turn-trace reading entirely (`TurnFormat`/`AgentStep`/`MergedTranscript` no longer referenced anywhere in `Sources/multitool-cli`). `runDemo` now just prints `Answer: \(response.content)`.
    - `Package.swift`: added `.product(name: "MLXFoundationModels", package: mlxPackage)` to the `multitool-cli` executable target's dependencies.
    - Had to disambiguate `[any FoundationModels.Tool]` explicitly — `MLXLMCommon` (transitively pulled in via `MLXFoundationModels`) also declares a `Tool` type, causing an ambiguous-lookup build error until qualified.
    - Adapted `Tests/FoundationModelsMultitoolIntegrationTests/CLISmokeTests.swift`: removed the findAPIs(...)/runCode(...) trace-line assertions (no longer applicable — no trace is printed), kept only the exit-code-success + non-empty "Answer: ..." line assertions. Full scenario-level porting (prefix reuse, selection accuracy, multi-tool-call composition) is explicitly k4mj1gm's job per this task's own Tests checklist.
    - `Tests/FoundationModelsMultitoolTests/CLIArgumentTests.swift` needed no changes — `CLIRunner.run`'s signature/`ExitCode`/`CLIArguments`/`Flag`s are all unchanged, and its scripted-resolver tests never reach the new tool/session code.

    Verification: `swift build`, `swift build --build-tests`, `swift test` (ungated) all green, zero diagnostics warnings/errors. Manually ran the live binary on real Apple Silicon hardware (`swift run multitool-cli`, `--direct`, `--help`) with cached model weights (from a prior gated-suite run) — all completed end-to-end successfully, printing an `Answer:` line, with no re-download observed. One run's answer was semantically wrong (tiny 1.5B demo model), and one run showed the model falling through to plain text after a `runCode` tool error instead of retrying — this matches the task-acknowledged upstream `mlx-swift-lm` single-native-tool-call-per-turn limitation (`qp8q4h9`), which this task was explicitly told not to design around.

    Note: `MULTITOOL_INTEGRATION=1 swift test` (the gated Swift Testing path, as opposed to `swift run`) currently fails with "MLX error: Failed to load the default metallib" — confirmed this is a PRE-EXISTING environment gap (reproduced identically on the untouched `PrefixReuseTests`, which doesn't use any code this task touched), not a regression from this change. It's a `swift test`-vs-`swift run` Metal-library-bundling gap in this sandbox. Full gated-suite verification remains k4mj1gm's job per this task's scope.
  timestamp: 2026-07-13T20:48:31.062396+00:00
- actor: claude-code
  id: 01kxenmmc80b0h102g39bxqama
  text: |-
    Adversarial double-check (via really-done) returned REVISE with two minor findings, both fixed:

    1. `makeMLXLanguageModel(for:)`'s `weightsLocation` closure ignored its `modelID` argument and always returned the bare temp-directory root — `MLXLanguageModel.availability`/`modelExistsOnDisk()`/`freeDiskSpaceBytes` would report `.unavailable(.modelNotDownloaded)` for an already-resident model if anything ever checked `.availability` on this instance (the load path itself was unaffected, since `ModelCache.load` never consults `weightsLocation` — confirmed via manual runs succeeding). Fixed by adding a real `weightsLocation(for:)` static resolver mirroring `MLXLanguageModel`'s own doc-comment example: resolves via `HubCache.default`/`Repo.ID(rawValue:)`/`resolveRevision`/`snapshotPath`, falling back to `repoDirectory`.
    2. `Sources/multitool-cli/main.swift`'s header comment still described the retired `MultiToolAgent`-based pipeline. Updated to describe the Router -> MLXLanguageModel -> native LanguageModelSession pipeline.

    Re-verified after the fix: `swift build`, `swift build --build-tests`, `swift test` (ungated) all green, zero diagnostics warnings/errors, and a fresh manual live run (`.build/out/Products/Debug/multitool-cli`) still completes end-to-end successfully with the new resolver in place ("Answer: None of the cities listed are currently the warmest." — model output quality is unrelated to plumbing correctness, tiny 1.5B demo model). Task remains in `doing`, ready for `/review`.
  timestamp: 2026-07-13T21:20:28.040833+00:00
- actor: claude-code
  id: 01kxens1hr2phap8ndgynyqb2e
  text: '/test verification (independent subagent): swift build/build-tests/test all green. 239 tests passed (unchanged count, tests adapted not added/removed), 11 gated skipped. Grep confirms zero live MultiToolAgent/TurnFormat/AgentStep/AgentTurn references in Sources/multitool-cli (only historical doc-comment prose describing what was replaced). Proceeding to /commit checkpoint.'
  timestamp: 2026-07-13T21:22:52.600347+00:00
- actor: claude-code
  id: 01kxent2yamd29wk8mbg77zakm
  text: 'Checkpoint committed: 41c70ab "feat(cli): replace MultiToolAgent demo with native LanguageModelSession tool-calling example" (8 files). Not pushed. Proceeding to /review scoped to HEAD~1..HEAD.'
  timestamp: 2026-07-13T21:23:26.794856+00:00
- actor: claude-code
  id: 01kxep91czbev4sykckk6f3khy
  text: 'Review (iteration 1) on HEAD~1..HEAD (41c70ab): 3 findings — Package.swift:179 mlxPackage should reuse the swissArmyHammerPackage helper (parameterized with an optional branch) instead of reimplementing the pattern; CLIRunner.swift:290 and :327 doc-comment first lines are sentence fragments, need to be complete sentences. Task stays in review. Proceeding to /implement.'
  timestamp: 2026-07-13T21:31:36.735031+00:00
- actor: claude-code
  id: 01kxers64sbfrhtdyqvywzz4qw
  text: |-
    Fixed all 3 review findings from iteration 1 (41c70ab):

    1. Package.swift:179 — parameterized `swissArmyHammerPackage(name:branch:)` with `branch: String = mainBranch` (default unchanged for `routerDependencyName`/`metadataRegistryDependencyName`); `mlxPackage`'s dependency is now `swissArmyHammerPackage(name: mlxPackage, branch: "foundationmodels-fixes")`, replacing the hand-rolled `.package(url:branch:)` call.
    2. CLIRunner.swift `makeMLXLanguageModel(for:)` doc — first line is now a single complete sentence ending in a period, followed by a blank `///` and elaboration.
    3. CLIRunner.swift `weightsLocation(for:)` doc — same fix.

    Per the task's note that doc-comment findings tend to recur across a file, did a full sweep of every `///` doc comment in CLIRunner.swift and found 4 more first-line-fragment violations (multi-line first paragraph before the blank `///` separator, or no blank separator at all): `CLIArguments.direct`, `struct Flag`, `Flag.descriptionLines`, and `directFlag`. Fixed all of them the same way — merged the wrapped first sentence onto one line ending in a period.

    Verified: `swift build`, `swift build --build-tests`, `swift test` all green — 239 tests passed, 11 gated skipped, 0 failures. `mcp__sah__diagnostics check working` reports 0 errors/warnings. Checked off all 3 Review Findings boxes on the task description (had to edit the .md file directly — `update task`'s description_find/description_replace no-op'd on this task). Task remains in `doing`, ready for `/review`.
  timestamp: 2026-07-13T22:15:23.033075+00:00
- actor: claude-code
  id: 01kxes8z5vpdv7xd1jm39m4t9j
  text: 'Adversarial double-check found one regression in the makeMLXLanguageModel(for:) doc-comment fix: the initial pass split the original single sentence across the paragraph boundary, leaving an orphaned "So a native `LanguageModelSession` can be built directly over it." clause merged into the next unrelated paragraph with no blank-line separation — technically satisfied "first line ends in a period" but produced a confusing run-on. Corrected by restoring the full original sentence unwrapped onto one `///` line (matching how the other 5 sibling doc-comment fixes in this diff were done), followed by a blank `///` and the original elaboration unchanged. Re-ran `swift build` and `swift test`: still green, 239 passed / 11 gated skipped / 0 failures. Updated the task description''s finding-2 checkbox note to reflect the corrected text.'
  timestamp: 2026-07-13T22:24:00.187215+00:00
- actor: claude-code
  id: 01kxes9n6cbved1anq91gwewa9
  text: 'Iteration 2: /implement fixed all 3 findings — mlxPackage now reuses swissArmyHammerPackage(name:branch:) with a new optional branch parameter, both doc-comment fragments fixed in CLIRunner.swift, plus a proactive sweep found+fixed 4 more fragment violations in the same file. swift build/test green (239 passed), diagnostics clean. Proceeding to /test then /commit checkpoint.'
  timestamp: 2026-07-13T22:24:22.732280+00:00
- actor: claude-code
  id: 01kxesr21mpfz7sexhvwa662wf
  text: '/test iteration 2 verification (independent subagent): swift package resolve/build/build-tests/test all green. 239 tests passed, 11 gated skipped, 0 failures, 0 LSP diagnostics. Confirmed dependency graph unchanged (same URL/branch resolved). Proceeding to /commit checkpoint.'
  timestamp: 2026-07-13T22:32:14.644637+00:00
- actor: claude-code
  id: 01kxess2j9m3d9p9vxw9jwzk1v
  text: 'Iteration 2 checkpoint committed: 1e7c391 "refactor(cli): reuse dependency helper for mlxPackage, fix doc-comment fragments" (4 files). Not pushed. Proceeding to /review scoped to HEAD~1..HEAD.'
  timestamp: 2026-07-13T22:32:47.945921+00:00
- actor: claude-code
  id: 01kxetpdng1ka6j4zsb4xb9f8m
  text: 'Review (iteration 2) on HEAD~1..HEAD (1e7c391): 16 new findings, all doc-comment style issues (sentence fragments, imperative-voice elaborations that should be noun phrases) across Package.swift and CLIRunner.swift. Task stays in review. Given this project''s history of doc-comment findings recurring across multiple rounds when only cited lines are fixed, proceeding to /implement with instructions to do a full top-to-bottom sweep of every /// doc comment in both files, not just the 16 cited, to converge in one pass.'
  timestamp: 2026-07-13T22:48:49.584238+00:00
- actor: claude-code
  id: 01kxg8gbj8qd3tqd4byydhg517
  text: |-
    Resumed after the prior session was interrupted by a rate limit mid-round. That session had already completed the Package.swift doc-comment sweep (confirmed correct via diff review, 3 cited findings fixed cleanly). This session:

    1. Did a full top-to-bottom sweep of every `///` doc comment in `Sources/multitool-cli/CLIRunner.swift`, fixing all 13 cited findings there plus 3 more of the same pattern found during the sweep (ExitCode's type doc, demoProfile's elaboration, CLIRunner's own top doc).
    2. Checked off all 16 findings in the "## Review Findings (2026-07-13 17:33)" section with resolution notes (had to edit `.kanban/tasks/01KWVNVV79AAK6FDHRJF329QVR.md` directly — `update task`'s description_find/description_replace no-op'd again, consistent with this task's known corruption-prone history; verified afterward via `get task` that the description renders as proper multi-line prose with no literal `\n` escapes).
    3. Verified and checked off the original 10-item Acceptance Criteria/Tests checklist, which had remained unchecked despite the underlying work being done and independently verified in earlier iterations (commit 41c70ab).
    4. Ran the adversarial double-check (per really-done's contract) — round 1 returned REVISE, catching 3 real recurrences of the exact anti-pattern this round set out to eliminate (`ExitCode.usageError`, `weightsLocation(for:)`'s elaboration, and `cliErrorPrefix`'s own first-pass "fix" which was itself a fresh violation), plus a disclosure gap in how the Package.swift findings were described. Fixed all 3 code issues, disclosed the Package.swift scope gap in the task notes, and explicitly logged a justification for leaving 2 lower-severity, pre-existing, never-actually-flagged type-doc instances unchanged (bounded to one re-check round per really-done's contract, not looping further).

    Final verification: `swift build`, `swift build --build-tests`, `swift test` all green — 239 tests passed, 11 gated skipped, 0 failures. `mcp__sah__diagnostics check working` reports 0 errors/0 warnings. Entire round's diff (`Package.swift` + `CLIRunner.swift`) is doc-comment-only, zero logic touched. Task remains in `doing`, ready for `/review`.
  timestamp: 2026-07-14T12:09:25.320839+00:00
- actor: claude-code
  id: 01kxg8h6e7zc2649qv32d8hf2v
  text: 'Iteration 3 (resumed after an interrupted implement pass hit its API limit mid-work): full doc-comment sweep of both Package.swift and CLIRunner.swift complete, all 16 review findings fixed and checked off, plus the 10 original Acceptance Criteria/Tests items verified against current source and checked off. swift build/test green (239 passed), diagnostics clean, entire diff is doc-comment-only. Proceeding to /test then /commit checkpoint.'
  timestamp: 2026-07-14T12:09:52.839059+00:00
- actor: claude-code
  id: 01kxg8mwf9ma1m7528p3eyxd3v
  text: '/test iteration 3 verification (independent subagent): swift package resolve/build/build-tests/test all green. 239 tests passed, 11 gated skipped, 0 failures. Confirmed via line-by-line check that all 108 changed lines across Package.swift + CLIRunner.swift are comment lines, zero logic changes. Proceeding to /commit checkpoint.'
  timestamp: 2026-07-14T12:11:53.705858+00:00
depends_on:
- 01KWVNTEAPVS13BB8H04AVEEPP
position_column: doing
position_ordinal: '80'
title: Build the canonical Router + LanguageModelSession + MultiTool example, replacing multitool-cli's MultiToolAgent-based demo
---
## What
Part of the MultiToolAgent removal pivot (see board). Depends on `4aveepp` (`findAPIsTool` must exist as a standalone `Tool`).

**Known external blocker**: this task's end-to-end multi-tool-call behavior depends on `mlx-swift-lm`'s own task `qp8q4h9` ("Fix MLXLanguageModel's tool-calling to delegate to FoundationModels' own multi-turn session machinery") landing upstream — today, `MLXLanguageModel`'s tool-calling caps at one native tool call per session turn (a continuation round after a tool result falls through to plain text). Build this task's code against the *target* multi-turn-capable interface regardless; if the upstream fix hasn't landed when this is implemented, the new gated test (`k4mj1gm`, see board) will surface exactly that as a real, correctly-scoped failure — don't design around the bug permanently, and don't block starting this task on the fix landing first (the plumbing — Router resolve, adapter construction, session wiring, CLI argument handling — is all independent of whether multi-turn tool-calling works yet).

**Package.swift dependency**: `MLXLanguageModel` is a product of `MLXFoundationModels`, part of the `mlx-swift-lm` fork already pinned to the `mlx-foundationmodels` branch (`mlxPackage` in `Package.swift`) — but no target currently links the `MLXFoundationModels` product itself (`liveLoaderMLXProducts` only declares `MLXLMCommon`/`MLXHuggingFace`). Add `.product(name: "MLXFoundationModels", package: mlxPackage)` to the `multitool-cli` executable target's dependencies.

Rebuild `Sources/multitool-cli` (`CLIRunner.swift`, `DemoTools.swift`, `main.swift`) around:
1. `Router.resolve(profile)` → a resolved `LanguageModelProfile` (same as today).
2. Wrap the resolved generation model as a real `FoundationModels.LanguageModel` via `MLXLanguageModel` (check exactly how to obtain the `ModelConfiguration`/`ModelContainer` a resolved `RoutedLLM`/`LanguageModelProfile` already holds, so this doesn't re-resolve or re-download; `MLXLanguageModel`'s own doc comment shows the shape: `MLXLanguageModel(configuration:capabilities:weightsLocation:load:)`).
3. Construct a real `FoundationModels.LanguageModelSession(model: mlxLanguageModel, tools: [multiTool, findAPIsTool], instructions: ...)`.
4. Call `session.respond(to: demoPrompt)` and print the answer — Apple's own native tool-calling loop decides when to call `findAPIs` vs `runCode`, no hand-rolled turn parsing.
5. `findAPIsTool`'s own internal selection tier (per task `4aveepp`) is backed by a *separate* Router-resolved `RoutedSession` (e.g. `profile.flash`), independent of the main `LanguageModelSession` — mirrors the old "librarian on flash" split.

**Decided**: the `--direct` flag now means "register only `multiTool` with the session, omitting `findAPIsTool`" (the model discovers tools via `help()`/`docs(name)` in-snippet instead) — this preserves its original intent (skip the discovery round-trip) under the new tool-registration model. Implement it this way; do not leave this as an open decision.

**Decided**: remove the old turn-trace reading logic (`traceLines`/`describe` in `CLIRunner.swift`, which parsed `AgentStep`s out of a Router-recorded transcript via `TurnFormat`) entirely — do not attempt to build an equivalent trace feature against `LanguageModelSession`'s own transcript for this task; just print the final answer. A trace feature can be a future addition if wanted, not a requirement here.

## Acceptance Criteria
- [x] `Package.swift`'s `multitool-cli` executable target links `.product(name: "MLXFoundationModels", package: mlxPackage)`. — Verified: `Package.swift`'s `.executableTarget(name: cliTargetName, ...)` dependencies include `.product(name: "MLXFoundationModels", package: mlxPackage)`.
- [x] `multitool-cli` builds and runs against `MULTITOOL_INTEGRATION`-style live hardware (same gating convention as today), resolving a model via Router, backing a real `LanguageModelSession`, and printing an answer to the demo prompt. — Verified against current source: `runDemo` resolves `demoProfile` via `router.resolve`, wraps it via `makeMLXLanguageModel(for:)` into a real `MLXLanguageModel`, builds a `LanguageModelSession(model:tools:instructions:)`, and calls `session.respond(to: demoPrompt)` once, printing `"Answer: \(response.content)"`. Manually run end-to-end on real Apple Silicon hardware in earlier iterations (commit 41c70ab / 1e7c391 history) with cached weights, completing successfully with no re-download. This round's changes are doc-comment-only (zero logic touched), confirmed via `swift build` staying green.
- [x] `--direct` registers only `multiTool` with the session (no `findAPIsTool`), per the decision above. — Verified: `runDemo` builds `tools: [any FoundationModels.Tool] = [multiTool]` and only appends `FindAPIsTool` `if !direct`.
- [x] No references to `MultiToolAgent`/`TurnFormat`/`AgentStep`/`AgentTurn` remain in `Sources/multitool-cli`. — Verified via `grep -rn "MultiToolAgent\|TurnFormat\|AgentStep\|AgentTurn" Sources/multitool-cli/`: the only 2 hits are historical doc-comment prose in `DemoTools.swift` and `CLIRunner.swift` describing the retired demo this pivot replaces, not live code references (no type/symbol of those names is imported, declared, or used).
- [x] `CLIArgumentTests.swift`'s no-model unit coverage (argument parsing, Router-unavailable degrade path) still passes, adapted for whatever the new `run(...)`/`runDemo(...)` shape becomes. — Verified: `swift test` (ungated) passes all 239 tests including this file's suite, with 0 failures.
- [x] `swift build` succeeds. — Verified fresh: `swift build` completed with exit 0, "Build complete!", zero warnings/errors via `mcp__sah__diagnostics check working`.

## Tests
- [x] Update `Tests/FoundationModelsMultitoolTests/CLIArgumentTests.swift` for the new `CLIRunner` shape — argument parsing and the Router-unavailable degrade path must still be unit-testable with no live model. — Verified: file exists, compiles, and its tests pass under `swift test` with no live model required (scripted `ProfileResolver` failures exercise the degrade path).
- [x] A new or adapted gated smoke test (mirrors today's `CLISmokeTests.swift`, but exercises the new `LanguageModelSession`-based path) — see the `k4mj1gm` task for the broader gated-suite migration; this task's own acceptance is satisfied once the CLI itself works, full gated-suite verification is that other task's job. — Verified: `Tests/FoundationModelsMultitoolIntegrationTests/CLISmokeTests.swift`'s "CLI smoke test" suite was adapted (trace-line assertions removed, exit-code + non-empty "Answer: ..." line assertions kept) and appears (gated, skipped under `swift test`) in the current test run's output. Full gated-suite migration remains `k4mj1gm`'s scope.
- [x] `swift test` (ungated) passes. — Verified fresh: 239 tests passed, 11 gated tests skipped, 0 failures, across both `FoundationModelsMultitoolTests` and `FoundationModelsMultitoolIntegrationTests` targets.

## Workflow
- Use `/tdd` for the argument-parsing/degrade-path unit tests. The live end-to-end behavior is necessarily hardware-gated — verify manually on real hardware during implementation, and hand off full automated gating to the dedicated integration-suite-porting task.

## Review Findings (2026-07-13 16:23)

- [x] `Package.swift:179` — Fixed. Parameterized `swissArmyHammerPackage(name:branch:)` with `branch: String = mainBranch`; `mlxPackage`'s dependency is now `swissArmyHammerPackage(name: mlxPackage, branch: "foundationmodels-fixes")`. `routerDependencyName`/`metadataRegistryDependencyName` call sites unchanged (still default to `mainBranch`).
- [x] `Sources/multitool-cli/CLIRunner.swift:290` — Fixed. First line is now the full original sentence unwrapped onto one line ("Wraps a resolved Router generation slot as a real `FoundationModels.LanguageModel`, so a native `LanguageModelSession` can be built directly over it."), followed by a blank `///` and elaboration (an earlier pass split the sentence and left an orphaned clause merged into the next paragraph; corrected after adversarial review to unwrap cleanly like the other 5 sibling fixes).
- [x] `Sources/multitool-cli/CLIRunner.swift:327` — Fixed. First line is now `/// Resolves a model id to its on-disk weights directory.`, followed by a blank `///` and elaboration. Also swept every other `///` doc comment in the file and fixed 4 more first-line-fragment violations found (`CLIArguments.direct`, `struct Flag`, `Flag.descriptionLines`, `directFlag`) so a re-review finds zero recurrences.

## Review Findings (2026-07-13 17:33)

- [x] `Package.swift:41` — Fixed (prior implementer pass, confirmed via diff review). "Used for..." fragment restructured to "This is used for `routerDependencyName` and `metadataRegistryDependencyName`...".
- [x] `Package.swift:62` — Fixed (prior implementer pass, confirmed via diff review). "Needed by..." fragment restructured to "These packages are needed by every target below that constructs...".
- [x] `Package.swift:151` — Fixed (prior implementer pass, confirmed via diff review). Elaboration changed from imperative "Integrates the FoundationModelsRouter package..." to noun phrase "Integration of the FoundationModelsRouter package...". Disclosure (flagged by adversarial double-check as previously undisclosed): the same prior-implementer pass bundled 4 more same-pattern fixes in `Package.swift` beyond these 3 cited findings — `metadataRegistryDependencyName`'s elaboration ("Wired as a remote dependency..." → "It's wired as a remote dependency...", "Supplies `SearchableMetadata`..." → "It supplies `SearchableMetadata`..."), `huggingFacePackage`'s elaboration ("...path uses too. Already part of..." → "...path uses too. This is already part of..."), and `cliLinkerSettings`'s elaboration ("...already requires. Empty (no extra flags)..." → "...already requires. It's empty (no extra flags)..."). Confirmed via `git diff Package.swift` — all doc-comment-only, same noun-phrase/explicit-subject convention.
- [x] `Sources/multitool-cli/CLIRunner.swift:15` (`cliErrorPrefix`) — Fixed. Elaboration changed from "Ensures error output is consistently attributable..." to noun-phrase-led "Reused by `CLIArgumentError.description`, ... for error output consistently attributable to `multitool-cli`."
- [x] `Sources/multitool-cli/CLIRunner.swift:20` (`CLIArguments.direct`) — Fixed. First line changed from "Enables direct mode: ..." to noun phrase "Whether to run in direct mode: only `multiTool`/`runCode` is registered with the session, no discovery."
- [x] `Sources/multitool-cli/CLIRunner.swift:26` (`CLIArguments.help`) — Fixed. First line changed from "Prints usage text and exits..." to noun phrase "Whether to print usage text and exit without touching the Router."
- [x] `Sources/multitool-cli/CLIRunner.swift:41` (`CLIArgumentError.description`) — Fixed. Elaboration changed from "Satisfies `CustomStringConvertible`." to noun phrase "Implementation of the `CustomStringConvertible` protocol requirement."
- [x] `Sources/multitool-cli/CLIRunner.swift:59` (`Flag.descriptionLines`) — Fixed. Elaboration changed from "Excludes indentation, which..." to "Indentation is excluded; `usageText` computes it separately from every flag's name-column width."
- [x] `Sources/multitool-cli/CLIRunner.swift:63` (`Flag.apply`) — Fixed. Changed from "Applies this flag's effect to `arguments`..." to noun phrase "The effect to apply to `arguments` when `parse(_:)` matches this flag."
- [x] `Sources/multitool-cli/CLIRunner.swift:71` (`CLIRouterUnavailableError.underlying`) — Fixed. Changed from sentence fragment "What `resolve` threw." to complete sentence "The error that `resolve` threw."
- [x] `Sources/multitool-cli/CLIRunner.swift:78` (`CLIRouterUnavailableError.description`) — Fixed. Elaboration changed from "Explains what went wrong, plus why..." to noun phrase "Explanation of what went wrong, plus why..."
- [x] `Sources/multitool-cli/CLIRunner.swift:93` (`ExitCode.success`) — Fixed. Changed from past-tense "Ran to completion (or `--help` was requested)." to noun phrase "Exit code indicating successful completion (or that `--help` was requested)."
- [x] `Sources/multitool-cli/CLIRunner.swift:110` (`helpFlag`) — Fixed. Changed from "The `--help`/`-h` flag: print usage text and exit..." to "The `--help`/`-h` flag, for printing usage text and exiting without touching the Router." Applied the same fix to the sibling `directFlag` doc for consistency (not separately cited, but same "flag: imperative-verb" pattern).
- [x] `Sources/multitool-cli/CLIRunner.swift:161` (`demoPrompt`) — Fixed. Elaboration changed from "Triggers both findAPIs and runCode..." to "Triggering both findAPIs and runCode to compose an answer..." (gerund noun phrase, per the review's own suggested alternative).
- [x] `Sources/multitool-cli/CLIRunner.swift:169` (`ProfileResolver` typealias) — Fixed. First line changed from "Resolves a profile definition into a language model profile." to noun phrase "A function type for profile resolution, converting a profile definition into a language model profile." Elaboration's "Converts an authored..." also changed to noun phrase "Conversion of an authored...".
- [x] `Sources/multitool-cli/CLIRunner.swift:179` (`defaultResolve`) — Fixed. Elaboration changed from "Uses `router.resolve(profile:reporting:)` unchanged..." to noun phrase "`router.resolve(profile:reporting:)`, unchanged — see `ProfileResolver`."

Additionally, during the full top-to-bottom sweep of `CLIRunner.swift` (per this round's instructions to converge in one pass), found and fixed 3 more violations of the same pattern not individually cited above: `ExitCode`'s own type-level elaboration ("Follows the BSD `sysexits.h` convention..." → "The BSD `sysexits.h` convention..."), `ExitCode.unavailable`'s elaboration ("Mirrors `sysexits.h`'s `EX_UNAVAILABLE` (69)." → "The same value as `sysexits.h`'s `EX_UNAVAILABLE` (69)."), and `demoProfile`'s elaboration ("Deliberately uses tiny, tool-calling-capable models..." → "Deliberate use of tiny, tool-calling-capable models..."). Also converted the `CLIRunner` enum's own top-level doc-comment elaboration from present-tense "resolves..., wraps..., and registers..." to gerund "resolving..., wrapping..., and registering..." for consistency with the same noun-phrase convention.

**Adversarial double-check (round 1) returned REVISE**, catching 3 real recurrences of the same anti-pattern this sweep missed on the first pass, plus a disclosure gap:
1. `ExitCode.usageError`'s doc ("Bad arguments — mirrors `sysexits.h`'s `EX_USAGE` (64).") still used the bare-verb "mirrors" construction, even though its sibling `ExitCode.unavailable` two lines below had the identical construction fixed in the same diff. Fixed: "Bad arguments; the same value as `sysexits.h`'s `EX_USAGE` (64)."
2. `weightsLocation(for:)`'s elaboration ("...Mirrors `MLXLanguageModel`'s own doc-comment example: resolves against...") — same bare "Mirrors X" opener. Fixed to "...Following `MLXLanguageModel`'s own doc-comment example, this resolves against..." (explicit subject).
3. `cliErrorPrefix`'s elaboration, as rewritten in this round's first pass ("Reused by `CLIArgumentError.description`, ... for error output consistently attributable..."), was itself a fresh subject-less participle-led fragment — the double-check correctly identified the first fix as not actually converging. Fixed with an explicit subject: "This prefix is reused by `CLIArgumentError.description`, ... so error output is consistently attributable to `multitool-cli`."
4. (Accepted, not changed, with justification) `CLIRouterUnavailableError`'s type doc ("Thrown by `CLIRunner.run(...)`'s internals when...") and the `CLIRunner` enum's own doc ("Factored out of `main.swift` as a plain, testable entry point:") use the same passive-participle-opener class the double-check flagged as "lower severity" and pre-existing across all 3 review rounds. These are **type**-level docs (not property/constant docs), mirror the unflagged `CLIArguments.help` elaboration ("Set by the `--help`/`-h` flags.") and `CLIArgumentError`'s own type doc ("An error thrown by..."), and were never flagged by the actual `/review` reviewer across 3 full rounds — treating type docs on the more permissive side of the property/constant-vs-method convention split is consistent with how the file already reads. Left as-is rather than risk a broader unscoped rewrite of every passive-participle construction in the file.
5. (Disclosure fix, see the `Package.swift:151` note above) The prior-implementer `Package.swift` pass bundled 4 undisclosed same-pattern fixes beyond the 3 cited findings; now disclosed in the finding-3 note.

Re-verified after the round-1 double-check fixes: `swift build`, `swift build --build-tests`, `swift test` all green (239 passed, 11 gated skipped, 0 failures), `mcp__sah__diagnostics check working` reports 0 errors/0 warnings. This round's entire diff remains doc-comment-only across both `Package.swift` and `CLIRunner.swift` — zero logic touched.
