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

    // MARK: - Escaping / injection-safety (schema-derived text is never
    // trusted to be safe TS/JS/comment syntax before being spliced into the
    // generated declaration and doc comment)

    @Test("a tool description containing \"*/\" is escaped, not left to terminate the JSDoc block early")
    func toolDescriptionWithCommentTerminatorIsEscaped() throws {
        let descriptor = try ToolAPIRenderer.render(
            name: "tool",
            description: "Ends the doc */ then injects code.",
            parameters: StringArgument.generationSchema
        )
        #expect(descriptor.doc.contains("Ends the doc * / then injects code."), "doc was: \(descriptor.doc)")
        // Exactly one "*/" survives — the block's own closing terminator —
        // proving the embedded one was neutralized rather than merely
        // "also present somewhere".
        #expect(
            descriptor.doc.components(separatedBy: "*/").count == 2,
            "expected exactly one \"*/\" (the block's own terminator); doc was: \(descriptor.doc)"
        )
    }

    @Test("a property description containing \"*/\" in its @param clause is escaped, not left to terminate the JSDoc block early")
    func propertyDescriptionWithCommentTerminatorIsEscaped() throws {
        let descriptor = try ToolAPIRenderer.render(
            name: "tool",
            description: "A test tool.",
            parameters: CommentTerminatorArgument.generationSchema
        )
        #expect(
            descriptor.doc.contains("@param args.value — ends the doc * / then injects code."),
            "doc was: \(descriptor.doc)"
        )
        #expect(
            descriptor.doc.components(separatedBy: "*/").count == 2,
            "expected exactly one \"*/\" (the block's own terminator); doc was: \(descriptor.doc)"
        )
    }

    @Test("a tool name that isn't a legal TypeScript identifier throws, per the completeness contract")
    func illegalToolNameThrows() throws {
        #expect {
            try ToolAPIRenderer.render(
                name: "foo); malicious();//",
                description: "Can't be rendered.",
                parameters: StringArgument.generationSchema
            )
        } throws: { error in
            error is ToolAPIRendererError
        }
    }

    @Test("a tool name with a trailing newline throws, even though every individual character but the last is a legal identifier character")
    func toolNameWithTrailingNewlineThrows() throws {
        // Regression case: `NSRegularExpression`'s `$` anchor matches
        // before a trailing line terminator (not only at the true end of
        // the string), so an `^...$`-anchored `NSRegularExpression` check
        // would incorrectly accept "toolName\n" as a legal identifier.
        // `isLegalTSIdentifier` must reject it.
        #expect {
            try ToolAPIRenderer.render(
                name: "toolName\n",
                description: "Can't be rendered.",
                parameters: StringArgument.generationSchema
            )
        } throws: { error in
            error is ToolAPIRendererError
        }
    }

    @Test("a pattern guide containing an embedded \"/\" is escaped in the documented regex literal")
    func patternWithEmbeddedSlashIsEscaped() throws {
        let descriptor = try ToolAPIRenderer.render(
            name: "tool",
            description: "A test tool.",
            parameters: SlashPatternArgument.generationSchema
        )
        #expect(descriptor.doc.contains("(pattern: /a\\/b/)"), "doc was: \(descriptor.doc)")
    }

    @Test("a pattern guide ending in \"*\" is escaped so the appended closing \"/\" doesn't form a literal comment terminator")
    func patternEndingInStarIsEscaped() throws {
        // `patternClause` renders `(pattern: /\(pattern)/)` — a pattern
        // ending in `*` (a perfectly ordinary regex, e.g. `.*`) forms a
        // literal `*/` right at the join with the appended closing `/`,
        // even though `escapeForRegexLiteralDoc` (which only escapes an
        // embedded `/`, per `patternWithEmbeddedSlashIsEscaped` above)
        // leaves a bare trailing `*` untouched.
        let descriptor = try ToolAPIRenderer.render(
            name: "tool",
            description: "A test tool.",
            parameters: StarEndingPatternArgument.generationSchema
        )
        #expect(descriptor.doc.contains("(pattern: /a* /)"), "doc was: \(descriptor.doc)")
        #expect(
            descriptor.doc.components(separatedBy: "*/").count == 2,
            "expected exactly one \"*/\" (the block's own terminator); doc was: \(descriptor.doc)"
        )
    }

    @Test("a property name containing a quote is safely quoted/escaped everywhere it's spliced into example literals — top-level key, nested key, and string placeholder value")
    func propertyNameWithQuoteIsEscapedInExampleLiterals() throws {
        // A real `@Generable` struct's field name is always a legal Swift
        // (and therefore legal TS) identifier, so a quote-containing
        // property name can't come from the macro — hand-author the
        // schema directly, the same technique
        // `unidentifiableSchemaNodeCannotEvenBeConstructed` uses.
        let handAuthored = """
        {
          "type": "object",
          "title": "QuotedNames",
          "additionalProperties": false,
          "x-order": ["top\\"quote", "nested"],
          "properties": {
            "top\\"quote": { "type": "string" },
            "nested": { "$ref": "#/$defs/QuotedNamesNested" }
          },
          "required": ["top\\"quote", "nested"],
          "$defs": {
            "QuotedNamesNested": {
              "type": "object",
              "title": "QuotedNamesNested",
              "additionalProperties": false,
              "x-order": ["inner\\"quote"],
              "properties": {
                "inner\\"quote": { "type": "string" }
              },
              "required": ["inner\\"quote"]
            }
          }
        }
        """
        let schema = try JSONDecoder().decode(GenerationSchema.self, from: Data(handAuthored.utf8))
        let descriptor = try ToolAPIRenderer.render(
            name: "tool",
            description: "A test tool.",
            parameters: schema
        )
        // Top-level key (`objectKeyLiteral` in `render`'s `exampleFields`)
        // and its string-placeholder value (`escapeForJSStringLiteral` in
        // `exampleLiteral`'s `.string` case) are both escaped.
        #expect(descriptor.example.contains(#""top\"quote": "top\"quote""#), "example was: \(descriptor.example)")
        // Nested key (`objectKeyLiteral` in `exampleObjectLiteral`) is
        // likewise escaped, not left bare or unescaped.
        #expect(descriptor.example.contains(#""inner\"quote": "inner\"quote""#), "example was: \(descriptor.example)")
    }

    @Test("a returns description containing \"*/\" is escaped, not left to terminate the JSDoc block early")
    func returnsDescriptionWithCommentTerminatorIsEscaped() throws {
        let descriptor = try ToolAPIRenderer.render(ReturnsCommentTerminatorTool())
        #expect(
            descriptor.doc.contains("@returns { summary: string } — current conditions * / then injects code."),
            "doc was: \(descriptor.doc)"
        )
        // Exactly one "*/" survives — the block's own closing terminator.
        #expect(
            descriptor.doc.components(separatedBy: "*/").count == 2,
            "expected exactly one \"*/\" (the block's own terminator); doc was: \(descriptor.doc)"
        )
    }

    @Test("an enum choice containing \"*/\" or a quote is escaped everywhere it's spliced — the TS declaration, the @param \"one of\" clause, and the @example call")
    func enumChoiceWithSpecialCharactersIsEscaped() throws {
        let descriptor = try ToolAPIRenderer.render(
            name: "tool",
            description: "A test tool.",
            parameters: EnumWithSpecialCharactersArgument.generationSchema
        )
        // The raw TS declaration is real code, never inside a comment: the
        // quote is JS-string-escaped, and the embedded "*/" is left as-is
        // since it's harmless there.
        #expect(
            descriptor.declaration.contains(#"option: "*/end" | "quo\"te""#),
            "declaration was: \(descriptor.declaration)"
        )
        // The doc's "one of ..." clause and @example call both land inside
        // the JSDoc block, so their copies must have "*/" neutralized too.
        #expect(
            descriptor.doc.contains(#"one of "* /end" | "quo\"te"."#),
            "doc was: \(descriptor.doc)"
        )
        #expect(
            descriptor.doc.contains(#"@example const r = tools.tool({ option: "* /end" });"#),
            "doc was: \(descriptor.doc)"
        )
        #expect(
            descriptor.doc.components(separatedBy: "*/").count == 2,
            "expected exactly one \"*/\" (the block's own terminator); doc was: \(descriptor.doc)"
        )
    }

    @Test("a return type containing an enum choice with \"*/\" is escaped in the @returns line only, leaving the actual declared return type untouched")
    func returnsTypeWithEnumCommentTerminatorIsEscapedInDocOnly() throws {
        let descriptor = try ToolAPIRenderer.render(ReturnsEnumWithCommentTerminatorTool())
        // `declaration` is real code, never inside a comment — the embedded
        // "*/" must survive there unescaped, or the declared return type
        // would no longer match the schema.
        #expect(
            descriptor.declaration.contains(#"{ status: "*/ok" | "bad" }"#),
            "declaration was: \(descriptor.declaration)"
        )
        // The doc's @returns line uses an escaped copy, so the embedded
        // "*/" can't terminate the JSDoc block early.
        #expect(
            descriptor.doc.contains(#"@returns { status: "* /ok" | "bad" }"#),
            "doc was: \(descriptor.doc)"
        )
        #expect(
            descriptor.doc.components(separatedBy: "*/").count == 2,
            "expected exactly one \"*/\" (the block's own terminator); doc was: \(descriptor.doc)"
        )
    }

    @Test("a property name containing a quote is safely quoted/escaped in the TS declaration's object type, not just the example literal")
    func propertyNameWithQuoteIsEscapedInDeclaration() throws {
        // Same hand-authoring technique as
        // `propertyNameWithQuoteIsEscapedInExampleLiterals` — a real
        // `@Generable` struct's field name can't contain a quote.
        let handAuthored = """
        {
          "type": "object",
          "title": "QuotedNameDeclaration",
          "additionalProperties": false,
          "x-order": ["foo\\"bar"],
          "properties": {
            "foo\\"bar": { "type": "string" }
          },
          "required": ["foo\\"bar"]
        }
        """
        let schema = try JSONDecoder().decode(GenerationSchema.self, from: Data(handAuthored.utf8))
        let descriptor = try ToolAPIRenderer.render(
            name: "tool",
            description: "A test tool.",
            parameters: schema
        )
        #expect(
            descriptor.declaration.contains(#"args: { "foo\"bar": string }"#),
            "declaration was: \(descriptor.declaration)"
        )
    }

    @Test("a property name containing \"*/\" is escaped in both the @param line's args.<key> and the @example call, not left to terminate the JSDoc block early")
    func propertyNameWithCommentTerminatorIsEscapedInDocLines() throws {
        let handAuthored = """
        {
          "type": "object",
          "title": "CommentTerminatorName",
          "additionalProperties": false,
          "x-order": ["foo*/bar"],
          "properties": {
            "foo*/bar": { "type": "string" }
          },
          "required": ["foo*/bar"]
        }
        """
        let schema = try JSONDecoder().decode(GenerationSchema.self, from: Data(handAuthored.utf8))
        let descriptor = try ToolAPIRenderer.render(
            name: "tool",
            description: "A test tool.",
            parameters: schema
        )
        #expect(descriptor.doc.contains("@param args.foo* /bar"), "doc was: \(descriptor.doc)")
        #expect(
            descriptor.doc.contains(#"@example const r = tools.tool({ "foo* /bar": "foo* /bar" });"#),
            "doc was: \(descriptor.doc)"
        )
        #expect(
            descriptor.doc.components(separatedBy: "*/").count == 2,
            "expected exactly one \"*/\" (the block's own terminator); doc was: \(descriptor.doc)"
        )
    }
}
