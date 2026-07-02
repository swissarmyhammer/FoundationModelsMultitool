import Foundation
import Testing

import FoundationModels
@testable import FoundationModelsMultitool

/// M2 coverage for `ToolAPIRenderer`: encoding a tool's `parameters:
/// GenerationSchema`, transliterating it to a TypeScript-style declaration,
/// and rendering the JSDoc doc comment — table-driven over a corpus of
/// fixture `@Generable` types (see `Fixtures/ToolAPIRendererFixtures.swift`),
/// plus a golden-file pin of the plan's worked `WeatherTool` example.
@Suite("ToolAPIRenderer")
struct ToolAPIRendererTests {
    /// One row per type-mapping/doc-mapping table row (or row-pair) the
    /// corpus isolates. Asserts both the rendered TS type for the whole
    /// `args:` object and the composed `@param` line for its one property.
    struct RenderCase {
        let name: String
        let schema: GenerationSchema
        let expectedArgsType: String
        let expectedParamLine: String
    }

    static let renderCases: [RenderCase] = [
        RenderCase(
            name: "string",
            schema: StringArgument.generationSchema,
            expectedArgsType: "{ value: string }",
            expectedParamLine: "@param args.value — a plain string."
        ),
        RenderCase(
            name: "number (float)",
            schema: NumberArgument.generationSchema,
            expectedArgsType: "{ measurement: number }",
            expectedParamLine: "@param args.measurement — a floating point measurement."
        ),
        RenderCase(
            name: "integer, unconstrained",
            schema: IntegerArgument.generationSchema,
            expectedArgsType: "{ count: number }",
            expectedParamLine: "@param args.count — an integer count. (integer)"
        ),
        RenderCase(
            name: "integer with a range guide",
            schema: RangedIntegerArgument.generationSchema,
            expectedArgsType: "{ score: number }",
            expectedParamLine: "@param args.score — a score. (integer) (range 1…10)"
        ),
        RenderCase(
            name: "boolean",
            schema: BooleanArgument.generationSchema,
            expectedArgsType: "{ enabled: boolean }",
            expectedParamLine: "@param args.enabled — whether to enable something."
        ),
        RenderCase(
            name: "enum / choice of constants",
            schema: EnumArgument.generationSchema,
            expectedArgsType: "{ size: \"small\" | \"medium\" | \"large\" }",
            expectedParamLine: "@param args.size — the chosen size; one of \"small\" | \"medium\" | \"large\"."
        ),
        RenderCase(
            name: "array<string>, unconstrained",
            schema: ArrayArgument.generationSchema,
            expectedArgsType: "{ tags: string[] }",
            expectedParamLine: "@param args.tags — free-form tags."
        ),
        RenderCase(
            name: "array<integer> with a count guide",
            schema: CountedArrayArgument.generationSchema,
            expectedArgsType: "{ ratings: number[] }",
            expectedParamLine: "@param args.ratings — ratings to record. (1…3 items)"
        ),
        RenderCase(
            name: "string with a pattern guide",
            schema: PatternArgument.generationSchema,
            expectedArgsType: "{ code: string }",
            expectedParamLine: "@param args.code — a three-letter code. (pattern: /[A-Z]{3}/)"
        ),
        RenderCase(
            name: "optional property",
            schema: OptionalArgument.generationSchema,
            expectedArgsType: "{ note?: string }",
            expectedParamLine: "@param args.note — an optional note. (optional)"
        ),
        RenderCase(
            name: "nested object",
            schema: NestedArgument.generationSchema,
            expectedArgsType: "{ address: { street: string; city: string } }",
            expectedParamLine: "@param args.address — delivery address."
        ),
        RenderCase(
            name: "array of nested object",
            schema: ArrayOfNestedArgument.generationSchema,
            expectedArgsType: "{ stops: { street: string; city: string }[] }",
            expectedParamLine: "@param args.stops — route stops."
        ),
    ]

    @Test("renders the args type and @param line for every type-mapping/doc-mapping table row", arguments: renderCases)
    func rendersTableRow(_ testCase: RenderCase) throws {
        let descriptor = try ToolAPIRenderer.render(
            name: "tool",
            description: "A test tool.",
            parameters: testCase.schema
        )
        #expect(descriptor.declaration.contains("args: \(testCase.expectedArgsType)"), "declaration was: \(descriptor.declaration)")
        #expect(descriptor.doc.contains(testCase.expectedParamLine), "doc was: \(descriptor.doc)")
    }

    @Test("a tool with no required properties renders `{}` in its example, not `{  }`")
    func noRequiredPropertiesRendersEmptyBracesInExample() throws {
        let descriptor = try ToolAPIRenderer.render(
            name: "tool",
            description: "A test tool.",
            parameters: OptionalArgument.generationSchema
        )
        #expect(descriptor.example == "tools.tool({});")
        #expect(descriptor.doc.contains("@example const r = tools.tool({});"))
    }

    @Test("a tagged union (anyOf of $refs) widens to `any` and reports a warning")
    func unrenderablePropertyWidensToAnyAndWarns() throws {
        var warnings: [String] = []
        let descriptor = try ToolAPIRenderer.render(
            name: "hasShape",
            description: "Has a shape.",
            parameters: UnrenderableArgument.generationSchema,
            onWiden: { warnings.append($0) }
        )
        #expect(descriptor.declaration.contains("args: { shape: any }"), "declaration was: \(descriptor.declaration)")
        #expect(!warnings.isEmpty, "expected at least one widen warning")
    }

    @Test("a self-referential schema is bounded by the cycle guard, not inlined infinitely")
    func recursiveSchemaIsBoundedByCycleGuard() throws {
        var warnings: [String] = []
        let descriptor = try ToolAPIRenderer.render(
            name: "tree",
            description: "A labeled tree.",
            parameters: TreeArgument.generationSchema,
            onWiden: { warnings.append($0) }
        )
        // One level of real inline expansion, then `any` for the recursive tail.
        #expect(
            descriptor.declaration.contains(
                "args: { label: string; children: { label: string; children: any[] }[] }"
            ),
            "declaration was: \(descriptor.declaration)"
        )
        #expect(!warnings.isEmpty, "expected the cycle guard to report a widen warning")
    }

    @Test("a top-level parameters schema that isn't an object throws, per the completeness contract")
    func nonObjectTopLevelSchemaThrows() throws {
        #expect {
            try ToolAPIRenderer.render(
                name: "broken",
                description: "Can't be rendered.",
                // `Shape.generationSchema` is a bare `anyOf`, not an object —
                // real @Generable enums with associated values produce this;
                // it can never legally back a `Tool.Arguments` (Apple's own
                // `Tool` extension only vends `parameters` for `Arguments:
                // Generable` struct types), but the core renderer entry
                // point takes any `GenerationSchema`, so this exercises the
                // completeness-contract throw directly.
                parameters: Shape.generationSchema
            )
        } throws: { error in
            error is ToolAPIRendererError
        }
    }

    @Test("GenerationSchema's own decoder rejects a property with none of type/const/$ref/anyOf — ToolAPIRenderer's matching throw branch is unreachable through any real schema")
    func unidentifiableSchemaNodeCannotEvenBeConstructed() throws {
        // `tsType` has a throw branch for exactly this shape — a node with
        // no "type" and no "anyOf", which it can't identify at all (distinct
        // from the "anyOf → widen to any" branch covered by
        // `unrenderablePropertyWidensToAnyAndWarns`, and from the
        // "non-object top level" throw covered by
        // `nonObjectTopLevelSchemaThrows`). Attempting to reach it — via
        // `GenerationSchema`'s own public `Decodable` conformance, the same
        // technique `AppleEncoderParityTests` uses to probe shapes the
        // macro can't produce — proves it unreachable one level earlier
        // than expected: `GenerationSchema.init(from:)` itself validates
        // every property node and rejects one lacking all of
        // "type"/"const"/"$ref"/"anyOf", so no `GenerationSchema` value
        // exhibiting this shape can exist at all. This mirrors the
        // default-value and nullable-union findings in
        // `AppleEncoderParityTests`: the renderer's throw branch stays as
        // defensive completeness (never a lossy stub, even for a shape
        // outside what Apple's own model permits), not dead weight — Apple's
        // decoder enforcing the same invariant one layer up is a second,
        // independent line of defense.
        let handAuthored = """
        {
          "type": "object",
          "title": "Broken",
          "additionalProperties": false,
          "x-order": ["mystery"],
          "properties": {
            "mystery": { "description": "has no type, const, $ref, or anyOf" }
          },
          "required": ["mystery"]
        }
        """
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(GenerationSchema.self, from: Data(handAuthored.utf8))
        }
    }

    @Test("one-sided numeric range and array count guides render their own parenthetical, distinct from the paired-bounds form")
    func oneSidedBoundsRenderDistinctClauses() throws {
        let descriptor = try ToolAPIRenderer.render(
            name: "tool",
            description: "A test tool.",
            parameters: OneSidedBoundsArgument.generationSchema
        )
        #expect(descriptor.doc.contains("@param args.atLeast — at least five. (integer) (minimum 5)"), "doc was: \(descriptor.doc)")
        #expect(descriptor.doc.contains("@param args.atMost — at most five. (integer) (maximum 5)"), "doc was: \(descriptor.doc)")
        #expect(descriptor.doc.contains("@param args.atLeastTags — at least one tag. (1+ items)"), "doc was: \(descriptor.doc)")
        #expect(descriptor.doc.contains("@param args.atMostTags — at most three tags. (up to 3 items)"), "doc was: \(descriptor.doc)")
    }

    @Test("a mutual two-hop $ref cycle through named $defs is bounded, not just the single-type self-\"#\" case")
    func mutualTwoHopCycleIsBounded() throws {
        var warnings: [String] = []
        let descriptor = try ToolAPIRenderer.render(
            name: "tool",
            description: "A test tool.",
            parameters: MutualRecursionArgument.generationSchema,
            onWiden: { warnings.append($0) }
        )
        // One real hop each way (NodeA -> NodeB -> NodeA), then `any` for
        // the tail — proves the guard tracks the ref path across named
        // `$defs`, not just a single self-referencing type.
        #expect(
            descriptor.declaration.contains(
                "args: { root: { label: string; children: { label: string; children: any[] }[] } }"
            ),
            "declaration was: \(descriptor.declaration)"
        )
        #expect(!warnings.isEmpty, "expected the cycle guard to report a widen warning")
    }

    @Test("a Tool whose Output is only PromptRepresentable (not Generable) still gets @returns prose")
    func plainTextOutputStillGetsReturnsProse() throws {
        let descriptor = try ToolAPIRenderer.render(PlainTextTool())
        #expect(descriptor.declaration.contains("): string;"), "declaration was: \(descriptor.declaration)")
        #expect(descriptor.doc.contains("@returns string —"), "doc was: \(descriptor.doc)")
    }

    @Test("the plan's worked WeatherTool example renders byte-identical to the golden file")
    func weatherToolMatchesGoldenFile() throws {
        let descriptor = try ToolAPIRenderer.render(WeatherTool())

        let goldenURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Goldens/WeatherTool.ts.txt")
        let golden = try String(contentsOf: goldenURL, encoding: .utf8)
            .trimmingCharacters(in: .newlines)

        #expect(descriptor.name == "weather")
        #expect(descriptor.source.trimmingCharacters(in: .newlines) == golden)
    }
}
