---
depends_on:
- 01KWVNXETKHH9TK9GR27840F24
position_column: todo
position_ordinal: '8880'
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
