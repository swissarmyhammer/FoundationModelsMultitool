---
comments:
- actor: wballard
  id: 01kwg63pvbvz8jhp1cgz0ks1wa
  text: |-
    Implemented M2 via TDD.

    Research: read plan.md's M2 section fully (type-mapping/doc-mapping tables, worked WeatherTool example, Finding #3). Since real Apple SDK access is available in this sandbox (Xcode-beta MacOSX27.0.sdk), wrote several throwaway Swift probe scripts (compiled with swiftc against the real FoundationModels.framework swiftinterface) to empirically ground the renderer in the *actual* encoded GenerationSchema JSON shape rather than plan.md's speculative Finding #3 claims. Two real divergences found and documented:
    1. Optional properties are NEVER encoded as a `["T","null"]` nullable-union type (confirmed even with `representNilExplicitlyInGeneratedContent: true`) — they are simply omitted from `"required"`, with a plain scalar `"type"`. Finding #3's claimed shape does not match the real compiled-SDK encoder.
    2. `GenerationSchema` has NO default-value concept at all — a Swift default property value never appears in the encoded JSON, and even round-tripping a hand-authored JSON Schema with an explicit `"default"` key through `GenerationSchema`'s own `Decodable` conformance silently drops it (its internal model has no slot for it). So the doc-mapping table's "default value" row is unreachable through any real `GenerationSchema`, by any mechanism.

    Also confirmed empirically: `x-order` (private key) preserves true Swift declaration order for properties (dict key order is not reliable); `$ref`/`$defs` shape for nested objects; `anyOf` shape for tagged-union enums (used as the "unrenderable -> any + logged" corpus case); self-referential arrays produce `$ref: "#"` (used for the cycle-guard test).

    Implementation:
    - Sources/FoundationModelsMultitool/Surface/ToolDescriptor.swift — name/declaration/doc/example/source struct.
    - Sources/FoundationModelsMultitool/Surface/ToolAPIRenderer.swift — encode -> decode into a private SchemaNode tree -> transliterate to TS type + JSDoc, per the plan's tables. Two entry points: `render<T: Tool>(_:onWiden:)` (derives `@returns` from `T.Output` via a dynamic `as? any Generable.Type` cast — this elegantly covers both structured Generable outputs AND plain-text String outputs through one pipeline, since String itself conforms to Generable) and the core `render(name:description:parameters:returns:onWiden:)` used directly by the corpus tests. Widen-to-`any`+log vs throw is deliberately split: unrecognized-but-identifiable schema shapes (anyOf, cyclic $ref) widen to `any` and report via an injectable `onWiden` closure (defaults to os.Logger); a schema that can't be identified at all (no "type", no anyOf) or a non-object top-level parameters schema throws `ToolAPIRendererError` (the completeness contract).

    Tests (TDD — written first, watched fail with "cannot find ToolAPIRenderer/ToolDescriptor in scope" compile errors before implementing):
    - Tests/.../Fixtures/ToolAPIRendererFixtures.swift — one @Generable fixture per type-mapping/doc-mapping table row (or row-pair), plus WeatherTool itself (a real Tool conformance) and the recursive/tagged-union edge-case fixtures.
    - Tests/.../ToolAPIRendererTests.swift — 12-case table-driven corpus test (one per table row), plus dedicated tests for any-widening+logging, cycle-guard boundedness, non-object-throws, and the golden WeatherTool byte-identical test.
    - Tests/.../AppleEncoderParityTests.swift — the Apple-encoder-parity pin, asserting the real divergences above against the compiled SDK (not assumed).
    - Tests/.../Goldens/WeatherTool.ts.txt — golden file, matched byte-identical on the first implementation run.
    - Package.swift — added `resources: [.copy("Goldens")]` to the test target (fixes an "unhandled file" build warning; test still reads the golden via #filePath directly, not Bundle.module).

    Verification: `swift build`, `swift build --build-tests` (zero warnings from our code, only a pre-existing benign mlx-swift dependency warning), and `swift test` all green — 25/25 tests across 4 suites (Scaffold, JSCInterpreter, ToolAPIRenderer, GenerationSchema Apple-encoder parity). `swift test --filter ToolAPIRendererTests` passes standalone per the task's stated verification command. Ran the really-done skill's adversarial double-check agent on the diff before calling this done.

    One documented interpretation decision: the acceptance criterion "the plan's worked WeatherTool example renders byte-identical to the golden file" is read as "the golden file we author is the pinned expected output for a WeatherTool-shaped fixture" (interpretation we control), not "literally reproduce the plan's illustrative markdown verbatim" — because the plan's own prose uses domain-specific narrative flourishes (e.g. "ATX" as an example city, `.tempC` field-chaining in the @example) that are not mechanically derivable from any real GenerationSchema (no example-value support in the schema at all), and the doc-mapping table's own literal @example row (`const r = tools.weather({ city: "ATX" });`, no field chaining) is followed instead of the more embellished worked-example prose. This is called out in code comments on the fixtures and the renderer.
  timestamp: 2026-07-02T01:11:51.915607+00:00
- actor: wballard
  id: 01kwg6tmhsn2rz1cbqzmahd8bs
  text: |-
    Adversarial double-check (via really-done) ran twice, per the bounded-loop contract.

    Round 1: REVISE, 6 findings:
    1. `tools.tool({  })` double-space when a tool has zero required properties.
    2. `.text` Returns branch (Output not Generable) rendered bare `@returns string` with no prose, contradicting plan.md's "document it in @returns prose"; also untested.
    3. The `tsType` "no type, no anyOf -> throw" branch was never exercised by a test.
    4. `numericRangeClause`/`countClause`'s one-sided (minimum-only/maximum-only/minItems-only/maxItems-only) branches were untested.
    5. `tsLiteral`'s non-string (`.number`/`.bool`) enum-literal branches were untested; asked whether they're even reachable.
    6. Only the single-type self-`"#"` cycle case was tested; a genuine two-type mutual `$ref` cycle through named `$defs` was only verified by hand-reading the code.

    All 6 fixed/addressed via TDD (failing test first where behavior changed; new coverage test first where only a gap needed closing):
    1. Fixed: `exampleArgsLiteral` special-cases empty to `"{}"`. New test `noRequiredPropertiesRendersEmptyBracesInExample`.
    2. Fixed: `.text` case now sets `returnsDescription = "plain text result."`. New fixture `PlainTextOutput`/`PlainTextTool` (a real `Tool` whose `Output` is `PromptRepresentable` but not `Generable` -- Swift permits this even though `Arguments` can't be) and test `plainTextOutputStillGetsReturnsProse`.
    3. New finding: attempting to hand-author a schema with a property missing type/const/$ref/anyOf and decode it through `GenerationSchema`'s own public `Decodable` conformance throws `DecodingError` -- Apple's own decoder rejects this shape one layer before our renderer ever sees it, so our matching throw branch is provably unreachable through any real `GenerationSchema` (same category as the Finding #3 divergences). Test `unidentifiableSchemaNodeCannotEvenBeConstructed` asserts this; renderer doc comment updated.
    4. New fixture `OneSidedBoundsArgument` (`.minimum`, `.maximum`, `.minimumCount`, `.maximumCount` each alone) + test `oneSidedBoundsRenderDistinctClauses` covering all four parenthetical forms.
    5. New finding: `GenerationGuide.anyOf(_:)` is confirmed (grepped the compiled `FoundationModels.swiftinterface`) to exist ONLY `where Value == String` -- no Int/Double/Bool overload -- so non-string enum literals are provably unreachable through any real `@Generable` type. Documented on `enumUnion`, not force-fit into a fixture.
    6. New fixtures `NodeA`/`NodeB`/`MutualRecursionArgument` (mutual two-hop cycle through named `$defs`, not just self-`"#"`) + test `mutualTwoHopCycleIsBounded`, verified to produce the hand-traced expected bounded output.

    Round 2 (bounded re-check): PASS. The reviewer independently re-verified all 6 fixes against actual code/tests (not just the round-1 description), ran `swift test` fresh itself (30/30), independently grepped the compiled swiftinterface to confirm the anyOf-is-String-only claim rather than trusting it, and hand-traced the mutual-cycle algorithm to confirm the test's expected output is actually correct.

    Final fresh verification (this session): `swift build` clean (zero warnings from our code), `swift test` 30/30 passing across 4 suites (Scaffold, JSCInterpreter, ToolAPIRenderer, GenerationSchema Apple-encoder parity), `swift test --filter ToolAPIRendererTests` 10/10 passing (the task's stated verification command).

    Leaving in `doing` for `/review` per the implement workflow -- not moving to review myself.
  timestamp: 2026-07-02T01:24:23.225268+00:00
depends_on:
- 01KWFNRM5VSWGD37H2YJ7CMBN2
position_column: doing
position_ordinal: '80'
title: 'M2: ToolAPIRenderer — GenerationSchema → TS declaration + JSDoc'
---
## What
Per plan.md M2: derive each tool's TypeScript-style declaration + JSDoc doc comment purely from its public surface.
- `Sources/FoundationModelsMultitool/Surface/ToolAPIRenderer.swift` — encode `tool.parameters: GenerationSchema` with `JSONEncoder` (encode is the read path; there is no field-enumeration API), transliterate the JSON Schema to a TS signature per the plan's type-mapping table (object/string/number/boolean/array/enum/nested/optional/`any`-widened-with-log), and render the doc comment per the doc-mapping table (`description` → summary, per-property guides → `@param`, enum/range/pattern/count/default → prose, `@returns`, auto `@example`).
- `Sources/FoundationModelsMultitool/Surface/ToolDescriptor.swift` — name, TS declaration, doc text, example, source. One generator feeds runtime binding, librarian prefix, and help()/docs().
- Object (named) parameters always — `tools.name({ field: … })`, never positional.
- Completeness contract: throw a descriptive error rather than emit a lossy stub.
- **Pin (Apple-encoder parity, plan Finding #3):** a test asserts Apple's own `GenerationSchema` encoder emits the expected JSON-Schema shape (`type/properties/required`, optional as `["T","null"]`, enum as `{"type":"string","enum":[…]}`) for fixture `@Generable` types.

## Acceptance Criteria
- [ ] The plan's worked `WeatherTool` example renders byte-identical to the golden file
- [ ] Every row of the type-mapping and doc-mapping tables is covered by at least one corpus case
- [ ] Unrenderable schema element → widened `any` + logged, or thrown per contract (per-table behavior)
- [ ] Apple-encoder parity test passes (or documents the divergence and the renderer handles it)

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/ToolAPIRendererTests.swift` — table-driven over a `GenerationSchema` corpus built from fixture `@Generable` types
- [ ] `Tests/FoundationModelsMultitoolTests/Goldens/*.ts.txt` — golden files pinning the rendered surface
- [ ] `swift test --filter ToolAPIRendererTests` → passes

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.