---
comments:
- actor: claude-code
  id: 01kxj1dzyqttt91a1g6f2842cw
  text: |-
    Picked up; moved to doing. Research done against the shipped code:

    - Production wiring confirmed in Sources/multitool-cli/CLIRunner.swift: Router.resolve(demoProfile) -> makeMLXLanguageModel(for: profile.standard) (MLXLanguageModel declaring .toolCalling + .guidedGeneration) -> native LanguageModelSession(model:tools:[multiTool, findAPIsTool], instructions: toolUseInstructions) -> session.respond(to:). Split pins standard=Qwen3-4B-Instruct-2507-4bit / flash=Qwen2.5-1.5B-Instruct-4bit. --direct omits findAPIsTool.
    - FindAPIsTool (Discovery/FindAPIsTool.swift): MetadataSearcher<APISurface.Entry> in .auto mode; init(registry:librarian:limit:) builds the selection tier on librarian.makeGuidedSession(grammar: idEnumGrammar(ids:), instructions:) — Router-backed RoutedSession (fork-per-call prefix reuse per SelectionConfig contract), ids-only grammar-constrained output, blocks spliced verbatim.
    - MultiToolConfiguration: maxAgentTurns/maxRepairTurns are GONE (removed with MultiToolAgent) — docs/SECURITY.md still lists both bullets plus a MultiToolAgent.respond(to:) cancellation reference and a stale SystemLanguageModel escape-hatch framing; those are the stale bits to fix (sandbox model itself untouched).
    - HardeningTests guard: readmeInjectedGlobalsListMatchesRuntime parses README's "### Injected globals" section for "- `name`" items between that heading and the next heading; must keep that exact section shape with {console, tools, help, docs}.
    - README line "drops into an Apple LanguageModelSession(tools:) or a MultiToolAgent loop" is stale too.

    Plan: README gets the session-driven worked example (mirroring CLIRunner.runDemo + ExamplesTests patterns, incl. the explicit LanguageModelSession.Response<String> annotation the demo needs) with the direct .call(arguments:) path kept as secondary; plan.md rewrite covers the Router-integration + Discovery sections plus the minimal consistency edits in the intro note, "Adding tools" step-2 snippet, "Usage: attaching to a session", and Components 1/2b/8 (which present the deleted MultiToolAgent as current); Milestones/Findings stay as the preserved historical record, with the exbtj1n history written into the Router-integration section explicitly.
  timestamp: 2026-07-15T04:44:16.727103+00:00
- actor: claude-code
  id: 01kxj2m1cdr37qj0czcmw9cjvt
  text: |-
    Implementation landed. Per-file changes:

    README.md — full rewrite around the session-driven design. New primary "Usage: register on a native LanguageModelSession" section with a worked example mirroring CLIRunner.runDemo step for step (buildRegistry -> Router resolve -> FindAPIsTool(registry:librarian: profile.flash) -> makeMLXLanguageModel(for: profile.standard) -> LanguageModelSession(model:tools:[multiTool, findAPIsTool], instructions: toolUseInstructions) -> explicitly-typed respond). Documents the split model pins (Qwen3-4B standard / Qwen2.5-1.5B flash), direct mode (--direct / registry.directMode()), and points at ExamplesTests.swift as the living-documentation suite. Direct .call(arguments:) path kept as its own "Calling runCode directly" section. "### Injected globals" section preserved byte-compatible with HardeningTests' parser (console/tools/help/docs). Removed the stale "or a MultiToolAgent loop" aside.

    plan.md — the two named sections rewritten plus minimal consistency edits where other text presented the deleted loop as current: (a) intro "Consequence" blockquote now states Router provides models/sessions never a loop, main loop is Apple's native tool-calling via MLXLanguageModel, with pointer to the history; (b) "Adding tools" snippet step 2/3 now builds the native session instead of MultiToolAgent; (c) "The agent loop is ours to build" replaced by "The main loop is Apple's native tool-calling (history: the hand-rolled loop)" — current design first, then the preserved history: original no-native-path assumption, the retired loop diagram marked RETIRED, both turn formats, exbtj1n real-hardware findings (blank kind-field under guided grammar, token-budget overruns under tolerant parse, hardcoded snippets), replacement via MLXLanguageModel FoundationModels interop, knobs deleted; (d) "Usage: attaching to a session" rewritten to the session wiring incl. direct mode and the new escape-hatch semantics; (e) Discovery section retitled "findAPIs and its prefix-cached selection tier (Router flash slot)" — MetadataSearcher .auto mode (retrieval always, ids-only grammar-constrained selection when librarian configured), fork-per-call prefix reuse as the reason the tier stays Router-backed, migration blockquote rewritten as landed history, diagram updated, assembled-prompt subsection now shows {"ids":[...]} + verbatim block splicing in FindAPIsTool.format's real output shape; (f) Components 1/2b/8 updated (2b marked retired with rationale); (g) Finding #7 and Prior art get past-tense parentheticals so research records don't read as current fact.

    Double-check (adversarial) returned REVISE with 4 findings, all fixed: (1) As-built note blockquotes added to Milestones and the Integration-tests testing strategy so M4/M6/M6.5 and the MultiToolAgent-owns-the-loop test prose are explicitly historical (shipped suite = ScenarioRunner/NativeToolCallEvaluation on native sessions); (2) "Remaining pins" final bullet marked resolved on real hardware (live path landed, fork-per-call shipped, PrefixReuseTests pins it); (3) both plan.md examples fixed to router.resolve(profile:reporting:) — the profile: label is required per the real Router signature; (4) leftover "main agent"/"librarian's prefix" terminology updated to "main session's model"/"selection tier's prefix".

    docs/SECURITY.md — stale-reference fixes only, sandbox model untouched: cancellation bullet drops MultiToolAgent.respond(to:); the maxAgentTurns/maxRepairTurns bullets (knobs deleted with the loop) replaced by a closing note that Apple's native session loop now owns turn budgeting; escape-hatch bullet rewritten — the main session already IS native LanguageModelSession(tools:), so the hatch is registering the tool directly with it (no more SystemLanguageModel-instead-of-Router framing).

    Tests: swift test --filter HardeningTests = 12/12 pass (incl. readmeInjectedGlobalsListMatchesRuntime against the new README). Full swift test = 150 tests in 17 suites passed; gated integration target (7 tests) properly skipped without MULTITOOL_INTEGRATION. Re-run green after the REVISE fixes. Awaiting the bounded double-check re-verdict.
  timestamp: 2026-07-15T05:05:03.373350+00:00
- actor: claude-code
  id: 01kxj2qq005be9ts0x9mb2eqzv
  text: 'Double-check re-verdict: PASS — all four REVISE findings confirmed fixed; no regressions (markdown fences balance, no test parses plan.md, As-built note claims verified against real files). Final verification evidence: swift test --filter HardeningTests 12/12 pass (incl. readmeInjectedGlobalsListMatchesRuntime); full swift test 150 tests / 17 suites pass, gated target skipped as expected. All acceptance criteria met. Leaving in doing, green, for /review per the workflow — no commit made.'
  timestamp: 2026-07-15T05:07:03.808745+00:00
depends_on:
- 01KWVNXETKHH9TK9GR27840F24
position_column: done
position_ordinal: a780
title: Rewrite README.md/plan.md/docs/SECURITY.md for the LanguageModelSession-driven design
---
## What
Part of the MultiToolAgent removal pivot (see board). Depends on `7840f24` (old code actually deleted) so the docs describe what's really there, not a still-in-flight design.

- `README.md`: its usage example currently shows the direct `.call(arguments:)` path (still accurate, keep) and a brief "drops into an Apple `LanguageModelSession(tools:)`... the same way any other tool would" aside — promote this to the primary documented integration pattern, with a real worked example showing `multiTool` + `findAPIsTool` both registered with a `LanguageModelSession`, backed by a Router-resolved model via `MLXLanguageModel` (mirroring whatever the rebuilt `multitool-cli` demo — task `f329qvr` — actually does, so the README's example and the real demo never drift).
- `plan.md`: the "Router integration" and "Discovery: a prefix-cached 'librarian' agent" sections describe `MultiToolAgent`'s now-deleted ReAct loop in detail — rewrite to describe the new design: Router provides models/sessions (never a tool-calling loop itself), `findAPIsTool`'s own selection tier uses a Router-backed `RoutedSession` for fork-per-call prefix reuse, and the *main* loop is Apple's real native tool-calling via `LanguageModelSession` (backed by a Router-resolved model through `MLXLanguageModel`). Note the historical record: this package originally built a hand-rolled ReAct loop because it assumed Router had no path to native tool-calling; real-hardware testing (documented on the archived task `exbtj1n`) showed that loop was unreliable regardless of model size, and `MLXLanguageModel`'s FoundationModels interop (once `qp8q4h9`'s multi-turn fix lands upstream) provides a better-founded mechanism. Keep this history rather than silently erasing it — it's genuinely useful context for why the design looks the way it does.
- `docs/SECURITY.md`: update any references to `help()`/`docs()`'s description of "the librarian"/discovery mechanism to describe `findAPIsTool` instead; the sandbox/injected-globals security model itself (unrelated to the agent-loop pivot) is unaffected and should not be rewritten.

## Acceptance Criteria
- [ ] README's primary usage example demonstrates `LanguageModelSession(tools: [multiTool, findAPIsTool])`, matching the real `multitool-cli` demo's actual code (not a hypothetical simplification that drifts from reality).
- [ ] plan.md's Router-integration and discovery sections accurately describe the new design, with the historical ReAct-loop rationale preserved as context, not deleted.
- [ ] `docs/SECURITY.md` has no stale references to the deleted `Librarian`/`MultiToolAgent`/ReAct-loop discovery framing.
- [ ] `HardeningTests`' README/SECURITY.md machine-checked sync tests (`readmeInjectedGlobalsListMatchesRuntime` and friends) still pass — this rewrite must not reintroduce the README/SECURITY.md drift bug fixed in kanban task `1pn8764`.

## Tests
- [ ] `swift test --filter HardeningTests` passes (confirms the README/SECURITY.md machine-checked sections stay in sync).
- [ ] Full `swift test` passes.

## Workflow
- Use `/tdd` where applicable (the `HardeningTests` sync check is the automated guard here); this is primarily a documentation task, verified by that existing test suite rather than new tests.
