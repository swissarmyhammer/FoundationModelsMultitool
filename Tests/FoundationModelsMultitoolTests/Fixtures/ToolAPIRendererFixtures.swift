import FoundationModels

// MARK: - The plan's worked `WeatherTool` example (plan.md § "ToolAPIRenderer")
//
// Used by the golden-file test to prove `ToolAPIRenderer` renders a real
// `Tool`'s public surface end to end — `name`/`description`/`parameters` in,
// a `ToolDescriptor` out — exactly as Findings #1 describes ("no source
// access" — this fixture is the *only* place these types' Swift source is
// visible, and the renderer never reads it).

/// The `Output` of `WeatherTool`, structured so its own `GenerationSchema`
/// drives the rendered `@returns` type.
@Generable(description: "current conditions.")
struct WeatherResult {
    var tempC: Double
    var summary: String
}

/// The `Arguments` of `WeatherTool` — one required `city`, one optional
/// enum-constrained `units`.
@Generable
struct WeatherArguments {
    @Guide(description: "IATA city code or city name.")
    var city: String

    @Guide(description: "temperature unit", .anyOf(["c", "f"]))
    var units: String?
}

/// A real `Tool` conformance (no `ToolAPIRenderer`-specific hooks) — proof
/// the renderer works purely off the public `Tool` surface.
struct WeatherTool: Tool {
    let name = "weather"
    let description = "Current weather for a city."

    func call(arguments: WeatherArguments) async throws -> WeatherResult {
        WeatherResult(tempC: 20, summary: "Sunny")
    }
}

// MARK: - Type-mapping / doc-mapping table corpus
//
// One small `@Generable` fixture per row (or row-pair) of plan.md's
// type-mapping and doc-mapping tables, each isolating the row(s) it exists to
// exercise. See `ToolAPIRendererTests.renderCases` for the table that drives
// assertions off these schemas.

/// `string` (row: `string` → `string`).
@Generable
struct StringArgument {
    @Guide(description: "a plain string.")
    var value: String
}

/// `number`/`Double` (row: `integer`/`number` → `number`, the float half).
@Generable
struct NumberArgument {
    @Guide(description: "a floating point measurement.")
    var measurement: Double
}

/// `integer`/`Int`, unconstrained (row: `integer` vs. float noted in the doc
/// comment, isolated from the range row below).
@Generable
struct IntegerArgument {
    @Guide(description: "an integer count.")
    var count: Int
}

/// `integer`/`Int` with a `.range` guide (row: numeric guide
/// minimum/maximum/range → `(range mn…mx)`; also exercises the `(integer)`
/// note landing alongside a range on the same property).
@Generable
struct RangedIntegerArgument {
    @Guide(description: "a score.", .range(1...10))
    var score: Int
}

/// `boolean` (row: `boolean` → `boolean`).
@Generable
struct BooleanArgument {
    @Guide(description: "whether to enable something.")
    var enabled: Bool
}

/// `enum`/choice of constants (row: `enum` → `"a" | "b" | "c"` union; doc row:
/// enum options → `@param … one of "a" | "b" | "c"`).
@Generable
struct EnumArgument {
    // No trailing period: the renderer joins a property description to an
    // enum clause with "; ", so the description reads as the lead-in to one
    // continuous sentence (matching `WeatherArguments.units`'s "temperature
    // unit; one of ...").
    @Guide(description: "the chosen size", .anyOf(["small", "medium", "large"]))
    var size: String
}

/// `array<T>` of a primitive, unconstrained (row: `array<T>` → `T[]`,
/// isolated from the count row below).
@Generable
struct ArrayArgument {
    @Guide(description: "free-form tags.")
    var tags: [String]
}

/// `array<T>` with a `.count` guide (doc row: array guide
/// minItems/maxItems/count → `@param … (n…m items)`).
@Generable
struct CountedArrayArgument {
    @Guide(description: "ratings to record.", .count(1...3))
    var ratings: [Int]
}

/// `string` with a `.pattern` guide (doc row: string guide pattern →
/// `@param … (pattern: /…/)`).
@Generable
struct PatternArgument {
    @Guide(description: "a three-letter code.", .pattern(try! Regex("[A-Z]{3}")))
    var code: String
}

/// Optional property (row: optional → `?` on the property, dropped from
/// `required`; doc row: required vs. optional → `(optional)`).
@Generable
struct OptionalArgument {
    @Guide(description: "an optional note.")
    var note: String?
}

/// A plain nested `@Generable` type, referenced by both `NestedArgument` and
/// `ArrayOfNestedArgument` below.
@Generable
struct NestedPayload {
    var street: String
    var city: String
}

/// Nested `object` property (row: nested object → inline `{ … }`).
@Generable
struct NestedArgument {
    @Guide(description: "delivery address.")
    var address: NestedPayload
}

/// `array<T>` of a nested `object` (combines the `array<T>` and nested-object
/// rows in one property).
@Generable
struct ArrayOfNestedArgument {
    @Guide(description: "route stops.")
    var stops: [NestedPayload]
}

/// Self-referential via `[TreeArgument]` (Swift structs can't cycle directly;
/// the array indirection is what makes this legal *and* is exactly the shape
/// a real recursive tool schema takes). Exercises the renderer's cycle guard:
/// without it, inlining this type would recurse forever.
@Generable
struct TreeArgument {
    var label: String
    var children: [TreeArgument]
}

/// A tagged union (`enum` with associated values) — `@Generable` renders
/// this as `anyOf` of `$ref`s, which is outside every row of the
/// type-mapping table (`enum`/choice-of-*constants* is a different shape).
/// Exercises "anything the schema can't express to us → `any` (widened)".
@Generable
enum Shape {
    case circle(radius: Double)
    case square(side: Double)
}

@Generable
struct UnrenderableArgument {
    @Guide(description: "a shape.")
    var shape: Shape
}

/// Isolates the *one-sided* forms of the numeric-range and array-count
/// guides — `.minimum`/`.maximum` alone, and `.minimumCount`/`.maximumCount`
/// alone — which a `.range`/`.count` guide (paired bounds, already covered
/// by `RangedIntegerArgument`/`CountedArrayArgument`) never exercises.
@Generable
struct OneSidedBoundsArgument {
    @Guide(description: "at least five.", .minimum(5))
    var atLeast: Int

    @Guide(description: "at most five.", .maximum(5))
    var atMost: Int

    @Guide(description: "at least one tag.", .minimumCount(1))
    var atLeastTags: [String]

    @Guide(description: "at most three tags.", .maximumCount(3))
    var atMostTags: [String]
}

/// Two `@Generable` types that reference each other (not just themselves) —
/// `NodeA.children: [NodeB]`, `NodeB.children: [NodeA]`. Exercises the
/// renderer's cycle guard on a genuine mutual/two-hop `$ref` cycle through
/// named `$defs`, distinct from `TreeArgument`'s single-type self-`"#"` case.
@Generable
struct NodeA {
    var label: String
    var children: [NodeB]
}

@Generable
struct NodeB {
    var label: String
    var children: [NodeA]
}

@Generable
struct MutualRecursionArgument {
    var root: NodeA
}

// MARK: - Plain-text `Output` (doc row: a non-structured `Output` still gets
// `@returns` prose, per plan.md's Return-type handling)
//
// `Tool.Output` is only bound to `PromptRepresentable`, not `Generable` — so
// unlike `Arguments` (which the `Tool` extension only vends `parameters` for
// when `Arguments: Generable`), a real `Output` type genuinely can be
// `PromptRepresentable` without being `Generable`. This fixture is that case,
// used to exercise `ToolAPIRenderer.Returns.text` end to end through a real
// `Tool` conformance (not just the core `render(...)` entry point's default).

struct PlainTextOutput: PromptRepresentable {
    let text: String
    var promptRepresentation: Prompt { Prompt(text) }
}

struct PlainTextTool: Tool {
    let name = "echo"
    let description = "Echoes text back."

    func call(arguments: StringArgument) async throws -> PlainTextOutput {
        PlainTextOutput(text: arguments.value)
    }
}

// MARK: - Apple-encoder-parity fixtures (plan.md Finding #3 pin)

/// A Swift default property value. Used to confirm — empirically, against
/// the real compiled `FoundationModels` SDK — that `GenerationSchema` has no
/// representation for default values at all (see
/// `AppleEncoderParityTests.defaultValuesAreNeverEncoded`).
@Generable
struct DefaultedArgument {
    var units: String = "c"
}
