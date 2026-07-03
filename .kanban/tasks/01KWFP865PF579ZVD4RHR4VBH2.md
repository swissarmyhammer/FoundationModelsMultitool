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

## Review Findings (2026-07-03 11:10)

- [x] `Sources/FoundationModelsMultitool/Agent/AgentTurn.swift:53` — Enum case `findAPIs` violates casing rule: acronyms should be down-cased when they lead a lowerCamelCase name (enum cases are lowerCamelCase). Should be `findApis`. Rename `case findAPIs` to `case findApis`. This will require cascading updates to all references to this case throughout the codebase.

  **INVESTIGATED, NOT APPLIED — false positive.** Per `builtin/validators/swift/rules/casing.md` (swissarmyhammer repo): "Down-case it when it leads a `lowerCamelCase` name; up-case it when interior or leading an `UpperCamelCase` name... DO: `utf8Bytes`, `parseURL`, `deviceID`, `userID`... DON'T: `parseUrl`, `deviceId`, `userId`." In `findAPIs`, the acronym "APIs" is the *second* word — interior to the lowerCamelCase name, exactly like "URL" in `parseURL` or "ID" in `deviceID` — not leading it ("find" leads). Per the rule's own DO list, an interior acronym in a lowerCamelCase name stays uppercase; renaming to `findApis` would produce the DON'T pattern (`parseUrl`). Confirmed `findAPIs` is the established, pre-existing spelling: `grep -r findAPIs Sources/` hits 14 files across the codebase (`MultiToolAgent.swift`, `TranscriptAnalyzer.swift`, `TurnFormat.swift`, `Librarian.swift`, `FoundAPIs.swift`, `FindAPITool.swift`, `AgentSession.swift`, `MultiTool.swift`, `MultiToolBuilder.swift`, `ToolDescriptor.swift`, `AgentEvaluators.swift`, `CLIRunner.swift`, `main.swift`, plus this file), predating this task (M4b). `grep -r findApis` (down-cased) across the entire repo returns zero hits in source — only in this review-finding text. No rename applied.
- [x] `Sources/FoundationModelsMultitool/Agent/MultiToolAgent.swift:219` — The literal "\n\n" appears 5 times in the respond(to:) method as a transcript separator between entries. This repeated literal exceeds the rule of three and should be extracted to a named constant so changes to the separator format only need to be made in one place. Extract to a private constant at the top of the respond(to:) method: `private let transcriptSeparator = "\n\n"`, then use `transcript += "\(transcriptSeparator)\(...)"` in all five locations.

  **FIXED.** Added `private static let transcriptSeparator = "\n\n"` near the top of `MultiToolAgent` (alongside `logger`) and replaced all 7 occurrences (5 in `respond(to:)`, 1 in `sessionInstructions`, 1 in `dispatchCallTool`'s error message) with `Self.transcriptSeparator`.
- [x] `Sources/FoundationModelsMultitool/Agent/MultiToolAgent.swift:297` — The "\n\n" separator literal appears a 7th time in the dispatchCallTool error message (in addition to the 6 occurrences already reported in respond(to:) and sessionInstructions), for a total of 7 occurrences in the file. All should be extracted to a single named constant. Include this occurrence in the extraction: use transcriptSeparator constant in the error message `return "callTool(\"\(name)\") failed: \(error)\(transcriptSeparator)Fix the request and call callTool again."`.

  **FIXED.** Covered by the same `transcriptSeparator` extraction above — all 7 occurrences now use `Self.transcriptSeparator`.
- [x] `Sources/FoundationModelsMultitool/Agent/MultiToolAgent.swift:312` — sessionInstructions parameter `supportsFindAPIs` violates casing rule: acronyms should be down-cased when leading lowerCamelCase. Should be `supportsFindApis`. Rename parameter from `supportsFindAPIs` to `supportsFindApis`.

  **INVESTIGATED, NOT APPLIED — false positive**, same reasoning as the `AgentTurn.swift:53` finding above: "APIs" is interior to `supportsFindAPIs` (the leading word is "supports"), so it correctly stays uppercase per the casing rule's own DO list. `supportsFindAPIs` is also the established pre-existing spelling (present before this task). No rename applied.
- [x] `Sources/FoundationModelsMultitool/Agent/TranscriptAnalyzer.swift:39` — Function name `findAPIsPrecedesRunCode` violates casing rule: the acronym APIs should be down-cased when it leads a lowerCamelCase name. Should be `findApisPrecedesRunCode`. Rename `findAPIsPrecedesRunCode` to `findApisPrecedesRunCode`.

  **INVESTIGATED, NOT APPLIED — false positive**, same reasoning: "APIs" is interior (the name leads with "find"), so it correctly stays uppercase. Pre-existing spelling, unchanged by this task. No rename applied.
- [x] `Sources/FoundationModelsMultitool/Agent/TranscriptAnalyzer.swift:184` — Function name `foundAPIs` violates casing rule: the acronym APIs should be down-cased when it leads a lowerCamelCase name. Should be `foundApis`. Rename `foundAPIs` to `foundApis`.

  **INVESTIGATED, NOT APPLIED — false positive**, same reasoning: "APIs" is interior to `foundAPIs` (leads with "found"), so it correctly stays uppercase. Pre-existing spelling. No rename applied.
- [x] `Sources/FoundationModelsMultitool/Agent/TranscriptAnalyzer.swift:221` — Property name `isFindAPIs` violates casing rule: acronym APIs should be down-cased when leading lowerCamelCase. Should be `isFindApis`. Rename property from `isFindAPIs` to `isFindApis`.

  **INVESTIGATED, NOT APPLIED — false positive**, same reasoning: "APIs" is interior to `isFindAPIs` (leads with "isFind"), so it correctly stays uppercase. Pre-existing spelling. No rename applied.
- [x] `Sources/FoundationModelsMultitool/Agent/TurnFormat.swift:105` — Static let constant `findAPIs` in ActionVerb enum violates casing rule: acronyms should be down-cased in lowerCamelCase contexts. Should be `findApis`. Rename `static let findAPIs = "findapis"` to `static let findApis = "findapis"`. Update all references to `ActionVerb.findAPIs`.

  **INVESTIGATED, NOT APPLIED — false positive**, same reasoning: "APIs" is interior to `findAPIs` (leads with "find"), so it correctly stays uppercase. Pre-existing spelling. No rename applied.
- [x] `Sources/FoundationModelsMultitool/Agent/TurnFormat.swift:176` — TolerantParseTurnFormat.formatInstructions parameter `supportsFindAPIs` violates casing rule: acronyms should be down-cased when leading lowerCamelCase. Should be `supportsFindApis`. Rename parameter from `supportsFindAPIs` to `supportsFindApis` (must match protocol definition at line 57).

  **INVESTIGATED, NOT APPLIED — false positive**, same reasoning: "APIs" is interior to `supportsFindAPIs` (leads with "supports"), so it correctly stays uppercase. Pre-existing spelling, matches the protocol definition it must agree with. No rename applied.
- [x] `Sources/FoundationModelsMultitool/Surface/ToolAPIRenderer.swift:266` — Function with two parameters must use a `- Parameters:` block. The doc comment explains the behavior but omits the required structured parameter documentation. Add a `- Parameters:` block: `/// - Parameters:\n    ///   - schema: the schema to encode and decode.\n    ///   - subject: a label for error messages.`.

  **FIXED.** Added `- Parameters:` block to `decode(_:subject:)` documenting `schema` and `subject`.
- [x] `Sources/FoundationModelsMultitool/Surface/ToolAPIRenderer.swift:407` — Function with four parameters must use a `- Parameters:` block. The doc comment explains the behavior but omits the required structured parameter documentation. Add a `- Parameters:` block documenting all four parameters with their roles.

  **FIXED.** Added `- Parameters:`/`- Returns:` block to `tsType(for:context:path:onWiden:)` documenting all four parameters.
- [x] `Sources/FoundationModelsMultitool/Surface/ToolAPIRenderer.swift:479` — Function with four parameters must use a `- Parameters:` block. The doc comment explains the behavior but omits the required structured parameter documentation. Add a `- Parameters:` block documenting all four parameters.

  **FIXED.** Added `- Parameters:`/`- Returns:` block to `renderObjectType(_:context:path:onWiden:)` documenting all four parameters.
- [x] `Sources/FoundationModelsMultitool/Surface/ToolAPIRenderer.swift:564` — Function with three parameters must use a `- Parameters:` block. The doc comment explains the behavior but omits the required structured parameter documentation. Add a `- Parameters:` block documenting all three parameters: `node`, `name`, and `context`.

  **FIXED.** Added `- Parameters:`/`- Returns:` block to `exampleLiteral(for:name:context:)` documenting `node`, `name`, and `context`.
- [x] `Sources/FoundationModelsMultitool/Surface/ToolAPIRenderer.swift:589` — Function with two parameters must use a `- Parameters:` block. The doc comment explains the behavior but omits the required structured parameter documentation. Add a `- Parameters:` block: `/// - Parameters:\n    ///   - node: the object schema to render.\n    ///   - context: the rendering context for $ref resolution.`.

  **FIXED.** Added `- Parameters:` block to `exampleObjectLiteral(_:context:)` documenting `node` and `context`.
- [x] `Sources/FoundationModelsMultitool/Surface/ToolAPIRenderer.swift:615` — Function with two parameters must use a `- Parameters:` block. The doc comment explains the behavior but omits the required structured parameter documentation. Add a `- Parameters:` block: `/// - Parameters:\n    ///   - node: the property schema node.\n    ///   - required: whether the property is required.`.

  **FIXED.** Added `- Parameters:` block to `paramClause(for:required:)` documenting `node` and `required`.
- [x] `Tests/FoundationModelsMultitoolTests/DirectToolCallTests.swift:65` — Public protocol implementation `respond(to:matching:)` lacks documentation; test fixture authors need to understand the method's contract. Add doc comment explaining the method's behavior (e.g., returns scripted responses in order).

  **FIXED.** Added a doc comment to `ScriptedDirectCallSession.respond(to:matching:)` explaining it returns scripted responses in order while recording prompt/schema, with `- Parameters:`/`- Returns:`/`- Throws:`.
- [x] `Tests/FoundationModelsMultitoolTests/DirectToolCallTests.swift:127` — Function with three parameters must use a `- Parameters:` block. The doc comment explains the function but omits the required structured parameter documentation. Add a `- Parameters:` block: `/// - Parameters:\n    ///   - keywords: the set of keywords to find.\n    ///   - node: the JSON node to search.\n    ///   - found: the set accumulating found keywords.`.

  **FIXED.** Added `- Parameters:` block to `collectKeys(_:in:into:)` documenting `keywords`, `node`, and `found`.

Note: one engine finding (`Tests/FoundationModelsMultitoolTests/Fixtures/MultiToolAgentFixtures.swift:75` — doc-comment restyling to a `- Parameters:` block) was dropped per the review skill's blanket exception: it targets a pre-existing test fixture function, and this commit only touched its doc-comment text (to mention a new parameter) without restructuring — asking for a restyle here is refactoring existing test code, which is out of scope.
