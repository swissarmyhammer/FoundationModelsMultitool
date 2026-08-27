import Foundation
import FoundationModels
import MCP
import Testing

@testable import FoundationModelsMultitool

/// Round-trip and outbound-conversion tests for ``GeneratedContentCodec``,
/// covering every leaf/branch shape `Value` and `GeneratedContent` share:
/// null, bool, string (incl. unicode/escaping), integer, fractional number,
/// array, and (nested) object.
///
/// A port of the sibling `FoundationModelsMCP` suite `CodecTests`, renamed so
/// that `swift test --filter GeneratedContentCodecTests` selects it.
///
/// `GeneratedContent.Kind.number` wraps only a `Double` — there is no
/// separate integer case — so integer-vs-double fidelity is recovered by
/// whether the `Double` has a fractional part (`Int(exactly:)`). Round-trip
/// coverage below therefore uses whole numbers to exercise the integer path
/// and numbers with a genuine fractional part to exercise the double path,
/// since a whole-number `Double` (e.g. `5.0`) is indistinguishable from the
/// integer `5` once inside `GeneratedContent` — that distinction does not
/// exist to preserve.
@Suite("GeneratedContentCodecTests")
struct GeneratedContentCodecTests {

    // MARK: - The values the round trips carry

    /// Whole numbers that exercise the integer path, at each sign and at the
    /// edges of `Int32`.
    private static let roundTripIntegers = [0, 1, -1, 42, -1000, 123_456, Int(Int32.max), Int(Int32.min)]

    /// `2^53` — the last integer a `Double` holds exactly.
    private static let doublePrecisionBoundary = 9_007_199_254_740_992

    /// `2^53 + 1` — the first integer a `Double` cannot hold exactly. Its
    /// `Double` rounds to a different `Int` on the way back.
    private static let beyondDoublePrecision = 9_007_199_254_740_993

    /// Numbers with a genuine fractional part, which exercise the double path.
    private static let roundTripDoubles = [0.5, -3.25, 3.14159, 1e10 + 0.5, -0.001]

    /// Strings that carry unicode and escaping, which the bridge must keep.
    private static let roundTripStrings = [
        "",
        "hello",
        "line1\nline2",
        "quote: \"quoted\"",
        "unicode: héllo wörld",
        "emoji: 👋🎉🚀",
        "tab\tand\\backslash",
        "日本語のテキスト",
    ]

    /// An array of one value of each scalar shape.
    private static let mixedScalars: Value = .array([.int(1), .double(2.5), .string("three"), .bool(true), .null])

    /// The `limit` argument ``argumentsExtractsProperties()`` reads back.
    private static let limitArgument = 10

    // MARK: - Round-trip: Value -> GeneratedContent -> Value

    @Test("null value round-trips through GeneratedContent")
    func nullRoundTrips() throws {
        try assertRoundTrips(.null)
    }

    @Test("bool value round-trips through GeneratedContent", arguments: [true, false])
    func boolRoundTrips(_ value: Bool) throws {
        try assertRoundTrips(.bool(value))
    }

    @Test("integer value round-trips through GeneratedContent", arguments: roundTripIntegers)
    func integerRoundTrips(_ value: Int) throws {
        try assertRoundTrips(.int(value))
    }

    @Test("integer at exactly 2^53 (Double's last exactly-representable integer) round-trips losslessly")
    func integerAtDoublePrecisionBoundaryRoundTrips() throws {
        try assertRoundTrips(.int(Self.doublePrecisionBoundary))
        try assertRoundTrips(.int(-Self.doublePrecisionBoundary))
    }

    @Test(
        "integer beyond Double's exact-representation range throws instead of silently corrupting",
        arguments: [beyondDoublePrecision, -beyondDoublePrecision]
    )
    func integerBeyondDoublePrecisionThrows(_ value: Int) {
        #expect(throws: GeneratedContentCodecError.self) {
            try GeneratedContentCodec.generatedContent(from: .int(value))
        }
    }

    @Test("fractional double value round-trips through GeneratedContent", arguments: roundTripDoubles)
    func fractionalDoubleRoundTrips(_ value: Double) throws {
        try assertRoundTrips(.double(value))
    }

    @Test(
        "string value round-trips through GeneratedContent, including unicode and escaping",
        arguments: roundTripStrings
    )
    func stringRoundTrips(_ value: String) throws {
        try assertRoundTrips(.string(value))
    }

    @Test("empty array round-trips through GeneratedContent")
    func emptyArrayRoundTrips() throws {
        try assertRoundTrips(.array([]))
    }

    @Test("array of mixed scalar values round-trips through GeneratedContent")
    func arrayOfMixedScalarsRoundTrips() throws {
        try assertRoundTrips(Self.mixedScalars)
    }

    @Test("empty object round-trips through GeneratedContent")
    func emptyObjectRoundTrips() throws {
        try assertRoundTrips(.object([:]))
    }

    @Test("object with nested object and array round-trips through GeneratedContent")
    func nestedObjectRoundTrips() throws {
        let value: Value = .object([
            "name": .string("Alice"),
            "age": .int(30),
            "score": .double(98.6),
            "active": .bool(true),
            "address": .object([
                "street": .string("123 Main St"),
                "unit": .null,
            ]),
            "tags": .array([.string("a"), .string("b"), .string("unicode: 日本語")]),
        ])
        try assertRoundTrips(value)
    }

    @Test("deeply nested value tree round-trips through GeneratedContent")
    func deeplyNestedRoundTrips() throws {
        let value: Value = .object([
            "level1": .object([
                "level2": .object([
                    "level3": .array([
                        .object(["leaf": .int(7)]),
                        .object(["leaf": .double(7.5)]),
                        .array([.null, .bool(false), .string("deep")]),
                    ])
                ])
            ])
        ])
        try assertRoundTrips(value)
    }

    // MARK: - arguments(from:) — outbound tool-call arguments

    @Test("arguments(from:) extracts a structure's properties as a String-keyed dictionary")
    func argumentsExtractsProperties() throws {
        let content = GeneratedContent(properties: [
            "path": "docs/readme.md",
            "recursive": true,
            "limit": Self.limitArgument,
        ])
        let arguments = try GeneratedContentCodec.arguments(from: content)
        #expect(arguments["path"] == .string("docs/readme.md"))
        #expect(arguments["recursive"] == .bool(true))
        #expect(arguments["limit"] == .int(Self.limitArgument))
    }

    @Test("arguments(from:) recovers nested objects and arrays as Value trees")
    func argumentsRecoversNestedShapes() throws {
        let inner = GeneratedContent(properties: ["city": "Springfield"])
        let content = GeneratedContent(properties: [
            "address": inner,
        ] as KeyValuePairs<String, any ConvertibleToGeneratedContent>)
        let arguments = try GeneratedContentCodec.arguments(from: content)
        #expect(arguments["address"] == .object(["city": .string("Springfield")]))
    }

    @Test("arguments(from:) throws when the content is not an object")
    func argumentsThrowsForNonObject() {
        let content = GeneratedContent("just a string")
        #expect(throws: GeneratedContentCodecError.self) {
            try GeneratedContentCodec.arguments(from: content)
        }
    }

    // MARK: - Unsupported Value.data

    @Test("Value.data has no GeneratedContent equivalent and throws")
    func dataValueThrows() {
        let value = Value.data(mimeType: "text/plain", Data("hello".utf8))
        #expect(throws: GeneratedContentCodecError.self) {
            try GeneratedContentCodec.generatedContent(from: value)
        }
    }

    // MARK: - Helpers

    /// Converts `value` to `GeneratedContent` and back, and expects the result
    /// to equal `value`.
    ///
    /// - Parameter value: The value to send through the bridge in both
    ///   directions.
    /// - Throws: What `GeneratedContentCodec.generatedContent(from:)` throws.
    private func assertRoundTrips(_ value: Value) throws {
        let content = try GeneratedContentCodec.generatedContent(from: value)
        let roundTripped = GeneratedContentCodec.value(from: content)
        #expect(roundTripped == value)
    }
}
