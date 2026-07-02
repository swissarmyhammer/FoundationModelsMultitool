import FoundationModels
import Testing

@testable import FoundationModelsMultitool

/// M3a coverage for `ArgumentMarshaler`: JS argument objects marshaling
/// natively into `GeneratedContent` (every scalar kind, arrays, nesting,
/// explicit `null` vs. an omitted key), and a tool `Output` rendering back
/// out to a JS-ready `InterpreterValue` (structured vs. plain text). No
/// model is needed for any of this — it's pure value conversion.
@Suite("ArgumentMarshaler")
struct ArgumentMarshalerTests {
    // MARK: - In: JS argument object -> GeneratedContent

    @Test("a string property marshals to a GeneratedContent string value")
    func stringPropertyMarshals() throws {
        let content = try ArgumentMarshaler.marshalArguments(.object(["city": .string("ATX")]))
        #expect(try content.value(String.self, forProperty: "city") == "ATX")
    }

    @Test("an integer-valued number marshals and reads back as an Int")
    func integerValuedNumberReadsBackAsInt() throws {
        let content = try ArgumentMarshaler.marshalArguments(.object(["count": .number(3)]))
        #expect(try content.value(Int.self, forProperty: "count") == 3)
    }

    @Test("a fractional number marshals and reads back as a Double, not an Int")
    func fractionalNumberReadsBackAsDoubleNotInt() throws {
        let content = try ArgumentMarshaler.marshalArguments(.object(["price": .number(19.5)]))
        #expect(try content.value(Double.self, forProperty: "price") == 19.5)
        #expect(throws: (any Error).self) {
            _ = try content.value(Int.self, forProperty: "price")
        }
    }

    @Test("a bool property marshals to a GeneratedContent bool value")
    func boolPropertyMarshals() throws {
        let content = try ArgumentMarshaler.marshalArguments(.object(["enabled": .bool(true)]))
        #expect(try content.value(Bool.self, forProperty: "enabled") == true)
    }

    @Test("an array property marshals to a GeneratedContent array")
    func arrayPropertyMarshals() throws {
        let content = try ArgumentMarshaler.marshalArguments(
            .object(["tags": .array([.string("a"), .string("b")])])
        )
        #expect(try content.value([String].self, forProperty: "tags") == ["a", "b"])
    }

    @Test("a nested object property marshals to a nested GeneratedContent structure")
    func nestedObjectPropertyMarshals() throws {
        let content = try ArgumentMarshaler.marshalArguments(
            .object(["address": .object(["street": .string("Main St"), "city": .string("Austin")])])
        )
        let nested = try content.value(GeneratedContent.self, forProperty: "address")
        #expect(try nested.value(String.self, forProperty: "street") == "Main St")
        #expect(try nested.value(String.self, forProperty: "city") == "Austin")
    }

    @Test("an array of nested objects marshals to an array of GeneratedContent structures")
    func arrayOfNestedObjectsMarshals() throws {
        let content = try ArgumentMarshaler.marshalArguments(
            .object(["stops": .array([.object(["city": .string("ATX")]), .object(["city": .string("SFO")])])])
        )
        let stops = try content.value([GeneratedContent].self, forProperty: "stops")
        #expect(stops.count == 2)
        #expect(try stops[0].value(String.self, forProperty: "city") == "ATX")
        #expect(try stops[1].value(String.self, forProperty: "city") == "SFO")
    }

    @Test("an explicit null property is present in the structure, not absent")
    func explicitNullPropertyIsPresent() throws {
        let content = try ArgumentMarshaler.marshalArguments(.object(["note": .null]))
        guard case .structure(let properties, _) = content.kind else {
            Issue.record("expected a structure kind")
            return
        }
        #expect(properties["note"]?.kind == .null)
    }

    @Test("an omitted optional field is absent from the structure, not present as null")
    func omittedOptionalFieldIsAbsent() throws {
        let content = try ArgumentMarshaler.marshalArguments(.object([:]))
        guard case .structure(let properties, let orderedKeys) = content.kind else {
            Issue.record("expected a structure kind")
            return
        }
        #expect(properties["note"] == nil)
        #expect(!orderedKeys.contains("note"))
    }

    @Test("an empty array property marshals to an empty GeneratedContent array")
    func emptyArrayPropertyMarshals() throws {
        let content = try ArgumentMarshaler.marshalArguments(.object(["tags": .array([])]))
        #expect(try content.value([String].self, forProperty: "tags") == [])
    }

    @Test("a number at the Double 2^53 integer-precision boundary round-trips exactly")
    func largeIntegerPrecisionBoundaryRoundTrips() throws {
        let content = try ArgumentMarshaler.marshalArguments(.object(["big": .number(9_007_199_254_740_992)]))
        #expect(try content.value(Double.self, forProperty: "big") == 9_007_199_254_740_992)
    }

    // `GeneratedContent.jsonString` does not throw for a non-finite `Double`
    // (`.nan`/`.infinity`) anywhere in its tree — it traps the process (an
    // internal `try!` around `JSONEncoder`, confirmed by direct execution
    // against the compiled OS-27 SDK). So a non-finite number must never
    // reach a `GeneratedContent`'s `.number` kind in the first place;
    // `content(from:)` degrades it to `.null` instead, mirroring
    // `InterpreterValue.encode`'s existing precedent for the identical
    // problem. These two cases only inspect `.kind` directly (never
    // `.jsonString`), so they're safe to run even before that guard exists
    // — unlike the symmetric `renderOutput` case below, which cannot be
    // exercised pre-fix without crashing the test process itself.

    @Test("an Infinity number argument marshals to a null property, not a crash")
    func infiniteNumberArgumentMarshalsToNull() throws {
        let content = try ArgumentMarshaler.marshalArguments(.object(["x": .number(.infinity)]))
        guard case .structure(let properties, _) = content.kind else {
            Issue.record("expected a structure kind")
            return
        }
        #expect(properties["x"]?.kind == .null)
    }

    @Test("a NaN number argument marshals to a null property, not a crash")
    func nanNumberArgumentMarshalsToNull() throws {
        let content = try ArgumentMarshaler.marshalArguments(.object(["x": .number(.nan)]))
        guard case .structure(let properties, _) = content.kind else {
            Issue.record("expected a structure kind")
            return
        }
        #expect(properties["x"]?.kind == .null)
    }

    @Test("a non-finite number nested inside an array and a nested object both marshal to null, not a crash")
    func nonFiniteNumberNestedInArrayAndObjectMarshalsToNull() throws {
        let content = try ArgumentMarshaler.marshalArguments(
            .object([
                "readings": .array([.number(.infinity), .number(1)]),
                "detail": .object(["delta": .number(.nan)]),
            ])
        )
        guard case .structure(let properties, _) = content.kind else {
            Issue.record("expected a structure kind")
            return
        }
        guard case .array(let readings) = properties["readings"]?.kind else {
            Issue.record("expected readings to be an array")
            return
        }
        #expect(readings.map(\.kind) == [.null, .number(1)])
        guard case .structure(let detailProperties, _) = properties["detail"]?.kind else {
            Issue.record("expected detail to be a structure")
            return
        }
        #expect(detailProperties["delta"]?.kind == .null)
    }

    @Test("marshaling a non-object argument throws ArgumentMarshalerError")
    func nonObjectArgumentThrows() throws {
        #expect {
            try ArgumentMarshaler.marshalArguments(.string("not an object"))
        } throws: { error in
            (error as? ArgumentMarshalerError)?.kind == .argumentsNotAnObject
        }
    }

    @Test("round trip: an object's keys and values marshal in and render back out equal")
    func roundTripPreservesKeysAndValues() throws {
        let original = InterpreterValue.object([
            "name": .string("Ada"),
            "age": .number(36),
            "active": .bool(true),
            "score": .number(19.5),
            "tags": .array([.string("x"), .string("y")]),
            "address": .object(["city": .string("Austin")]),
        ])
        let content = try ArgumentMarshaler.marshalArguments(original)
        let rendered = try ArgumentMarshaler.renderOutput(content)
        #expect(rendered == original)
    }

    // MARK: - Out: tool Output -> JS-ready InterpreterValue

    @Test("a structured Generable Output renders as a JS object")
    func structuredOutputRendersAsObject() throws {
        let output = WeatherResult(tempC: 20, summary: "Sunny")
        let rendered = try ArgumentMarshaler.renderOutput(output)
        #expect(rendered == .object(["tempC": .number(20), "summary": .string("Sunny")]))
    }

    @Test("a plain String Output renders as a JS string")
    func plainStringOutputRendersAsString() throws {
        let rendered = try ArgumentMarshaler.renderOutput("hello")
        #expect(rendered == .string("hello"))
    }

    @Test("an array-of-Generable Output renders as a JS array of objects")
    func arrayOfGenerableOutputRendersAsArray() throws {
        let output = [WeatherResult(tempC: 20, summary: "Sunny"), WeatherResult(tempC: 5, summary: "Cold")]
        let rendered = try ArgumentMarshaler.renderOutput(output)
        #expect(
            rendered == .array([
                .object(["tempC": .number(20), "summary": .string("Sunny")]),
                .object(["tempC": .number(5), "summary": .string("Cold")]),
            ])
        )
    }

    @Test("a non-Generable PromptRepresentable-only Output throws ArgumentMarshalerError")
    func nonGenerableOutputThrows() throws {
        let output = PlainTextOutput(text: "hi")
        #expect {
            try ArgumentMarshaler.renderOutput(output)
        } throws: { error in
            (error as? ArgumentMarshalerError)?.kind == .outputNotGenerable
        }
    }

    // `GeneratedContent.jsonString` traps the process for a non-finite
    // `Double` (see the matching comment on the "In" side, above) — a real
    // `@Generable` `Output` can plausibly produce one (a division, an
    // average of an empty collection, an overflow), so `renderOutput` must
    // sanitize before ever touching `.jsonString`. Unlike the "In" side's
    // pair, these cases can't be exercised pre-fix without crashing the
    // test process itself; the crash was independently reproduced and
    // confirmed outside this suite (a standalone probe against the same
    // compiled SDK) before `ArgumentMarshaler.sanitizingNonFiniteNumbers`
    // was added, so these are regression tests for that fix, not a live
    // red/green pair.

    @Test("an Infinity Double field in a structured Output degrades to null, not a crash")
    func infiniteDoubleFieldInOutputDegradesToNull() throws {
        let rendered = try ArgumentMarshaler.renderOutput(MeasurementOutput(value: .infinity))
        #expect(rendered == .object(["value": .null]))
    }

    @Test("a NaN Double field in a structured Output degrades to null, not a crash")
    func nanDoubleFieldInOutputDegradesToNull() throws {
        let rendered = try ArgumentMarshaler.renderOutput(MeasurementOutput(value: .nan))
        #expect(rendered == .object(["value": .null]))
    }
}

/// A structured `Output` with a `Double` field, used only to exercise
/// `renderOutput`'s non-finite-number guard — a plain scalar `Output`
/// (`WeatherResult`) can't isolate "one field is non-finite, the rest of the
/// structure still renders" the way a single-field fixture can.
@Generable
struct MeasurementOutput {
    var value: Double
}
