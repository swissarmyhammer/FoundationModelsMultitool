---
comments:
- actor: wballard
  id: 01kwmbpd80rd7yt0jdpb96fg27
  text: |-
    Implemented via TDD. Summary:

    **New**: `Sources/FoundationModelsMultitool/Agent/DirectToolCall.swift` — `DirectCallSession` protocol (`respond(to:matching: jsonSchema) async throws -> JSONValue`, mirroring how `AgentSession` abstracts `RoutedSession`), `RoutedDirectCallSession` (production conformer wrapping `RoutedLLM`), `DirectToolCallError`, and `DirectToolCall.call<T: Tool>(_:task:using:)` — the encode→constrain→marshal→invoke pipeline: `ToolAPIRenderer.jsonSchemaString(for:)` (new helper, reused M2's encode path) → `session.respond(to:matching:)` → `GeneratedContent(json:)` from the re-encoded `JSONValue` → `ToolInvoker.invoke(_:content:)`.

    **Verified API choice against real Router source** (`.build/checkouts/FoundationModelsRouter/Sources/FoundationModelsRouter/Guided/GuidedGeneration.swift`): `respond(to:matching: String) -> JSONValue` is a real, distinct API declared on `RoutedModel where Container == any LoadedLLMContainer` (i.e. `RoutedLLM`, the model *handle*) — NOT on `RoutedSession`, and NOT the same as `respond(to:generating:)` (which needs a compile-time `Generable` type; a direct tool's `Arguments` type is only known via existential opening, so the dynamic-JSON shape is the only one that fits). plan.md's own text said `respond(to:generating:)`, which was wrong for this case — confirmed via source read, not assumed. README updated accordingly.

    **AgentTurn/DirectToolCall relationship**: architecturally a sibling to `AgentTurn`'s guided-generation pattern (derive a schema → constrain generation → decode into a typed step), but a genuinely different primitive: `AgentTurn` constrains a long-lived *session* to one *fixed, compile-time* schema (`GuidedTurnFormat`, `RoutedLLM.makeGuidedSession`), while `DirectToolCall` constrains a *fresh, one-shot* call to a *different runtime* schema per call (the called tool's own `parameters`) — hence the dynamic-JSON `respond(to:matching:)` shape and the separate `DirectCallSession` seam rather than reusing `AgentSession`.

    **MultiToolAgent wiring**: `MultiToolAgent(directTools: [any Tool] = [])` (both public and test-facing initializers); `AgentStep` gained `.callTool(name:task:)`; `TurnFormat.formatInstructions` gained a `supportsDirectCall` parameter (default `false`, so no other call sites needed updating) for both `TolerantParseTurnFormat` (`ACTION: callTool` / `NAME:` / `TASK:`) and `GuidedTurnFormat`/`AgentTurn` (new `.callTool` kind + `toolName` field). `dispatchCallTool` renders every failure (unknown name, no session configured, schema/guided/validation/tool failure) as repairable transcript text, never a thrown error (except `CancellationError`), mirroring `MultiTool.call`'s posture toward `runCode` failures.

    **Tests**: `Tests/FoundationModelsMultitoolTests/DirectToolCallTests.swift`, 13 tests, all passing, covering all 4 acceptance criteria plus guide-violation-in-guided-output, throwing-tool passthrough, guided-session-error passthrough, and the `.guided` turn format round-trip.

    **Verification**: `swift build` clean (0 warnings/errors). `swift test --filter DirectToolCallTests` → 13/13. `swift test --filter FoundationModelsMultitoolTests` (full main suite) → 245/245 (232 pre-existing + 13 new), run fresh after every substantive change.

    **Adversarial double-check**: ran via the `double-check` agent; verdict REVISE with two cosmetic doc-comment findings (missing summary/elaboration split on `DirectToolCallError`'s doc comment; missing doc comment on `RoutedDirectCallSession.respond(to:matching:)`). Both fixed; re-verified `swift build` + full suite green afterward (245/245).

    No blockers. Leaving in `doing` for `/review` per the implement skill's process.
  timestamp: 2026-07-03T16:06:25.280271+00:00
depends_on:
- 01KWFNT7BY92073MGCF6GRQ8NH
- 01KWFNVX4RFZZKEKY4C08F8V0Y
position_column: doing
position_ordinal: '80'
title: 'Escape hatch: guided direct tool call (schema-valid args)'
---
## What
Per plan.md "Escape hatch — keep the schema-valid-args guarantee" + Resolved #8 (finding: promised in v1 but previously untasked): a directly-placed tool whose arguments stay schema-valid without wrapping it in the snippet surface.
- `Sources/FoundationModelsMultitool/Agent/DirectToolCall.swift` — for a tool registered as *direct* (e.g. `Builder.addDirectTool(_:)` or `MultiToolAgent(directTools:)`): encode its `parameters: GenerationSchema` to a JSON Schema string (reusing M2's encode path), constrain a Router turn with `Grammar.jsonSchema` via `respond(to:matching:)`, build `GeneratedContent(json:)` from the schema-valid output, and invoke through `ToolInvoker` — arguments xgrammar-constrained end to end.
- Surface direct tools to the model as a third loop affordance (`callTool(name, args)` description string alongside runCode/findAPIs), dispatched by `MultiToolAgent`.
- Document in the README escape-hatch section (consumed by M10) that this is the schema-valid path on a Router model, and that Apple's token-level tool loop applies only in a built-in `SystemLanguageModel` session.

## Acceptance Criteria
- [x] A direct tool's derived grammar rejects out-of-schema output (validated via `Grammar` xgrammar-subset validation on the derived schema)
- [x] With a scripted fake guided session returning schema-valid args JSON, the direct call invokes the tool with correctly-typed `Arguments`
- [x] A wrapped tool and a direct tool coexist in one agent: snippet path and direct path both dispatch correctly in a scripted scenario
- [x] Unknown direct-tool name from the model → repairable error, not a crash

## Tests
- [x] `Tests/FoundationModelsMultitoolTests/DirectToolCallTests.swift` — the four criteria above with mock tools + fake seam
- [x] `swift test --filter DirectToolCallTests` → passes

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.