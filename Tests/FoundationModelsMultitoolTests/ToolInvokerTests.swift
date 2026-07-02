import FoundationModels
import Testing

@testable import FoundationModelsMultitool

/// M3b coverage for `ToolInvoker`: invoking an `any Tool` through implicit
/// existential opening (SE-0352), the two pre-call validation layers
/// (missing/shape-mismatched fields, `@Guide` constraint violations), and
/// that a tool's own thrown error passes through unwrapped. No model is
/// needed for any of this — `content` is hand-built via
/// `ArgumentMarshaler.marshalArguments`, exactly as `JSCInterpreter` would
/// produce it from a snippet's call.
@Suite("ToolInvoker")
struct ToolInvokerTests {
    // MARK: - Existential opening

    @Test("an any Tool (concrete type unnamed at the call site) is invoked successfully via existential opening")
    func anyToolInvokedViaExistentialOpening() async throws {
        let tool: any Tool = WeatherTool()
        let content = try ArgumentMarshaler.marshalArguments(.object(["city": .string("ATX")]))

        let output = try await ToolInvoker.invoke(tool, content: content)

        // `output`'s static type is `any PromptRepresentable` — the upper
        // bound SE-0352 leaves once `T` can no longer be named outside the
        // call — so rendering it back out (itself another existential-open
        // call) is how the test proves the real `WeatherResult` came back,
        // without ever naming `WeatherTool`/`WeatherResult` at the call site.
        let rendered = try ArgumentMarshaler.renderOutput(output)
        #expect(rendered == .object(["tempC": .number(20), "summary": .string("Sunny")]))
    }

    // MARK: - Field values reach the tool's call

    @Test("invoke decodes marshaled fields through to the tool's call")
    func invokeDecodesFieldsThroughToCall() async throws {
        let tool = RecordingTool()
        let content = try ArgumentMarshaler.marshalArguments(
            .object(["city": .string("ATX"), "units": .string("f")])
        )

        _ = try await ToolInvoker.invoke(tool, content: content)

        #expect(tool.recorded?.city == "ATX")
        #expect(tool.recorded?.units == "f")
    }

    @Test("an omitted optional field decodes as nil, not a validation failure")
    func omittedOptionalFieldDecodesAsNil() async throws {
        let tool = RecordingTool()
        let content = try ArgumentMarshaler.marshalArguments(.object(["city": .string("ATX")]))

        _ = try await ToolInvoker.invoke(tool, content: content)

        #expect(tool.recorded?.city == "ATX")
        #expect(tool.recorded?.units == nil)
    }

    // MARK: - Shape mismatch fails BEFORE call, naming the offending field

    @Test("a shape-mismatched argument fails before call, naming the offending field")
    func shapeMismatchFailsBeforeCallNamingField() async throws {
        let tool = RecordingTool()
        // `city` is declared `String`; supply a number instead.
        let content = try ArgumentMarshaler.marshalArguments(.object(["city": .number(42)]))

        await #expect {
            try await ToolInvoker.invoke(tool, content: content)
        } throws: { error in
            guard let invokerError = error as? ToolInvokerError else { return false }
            return invokerError.kind == .typeMismatch
                && invokerError.field == "city"
                && invokerError.message.contains("city")
        }
        #expect(tool.recorded == nil)
    }

    @Test("a missing required argument fails before call, naming the offending field")
    func missingRequiredFieldFailsBeforeCallNamingField() async throws {
        let tool = RecordingTool()
        let content = try ArgumentMarshaler.marshalArguments(.object([:]))

        await #expect {
            try await ToolInvoker.invoke(tool, content: content)
        } throws: { error in
            guard let invokerError = error as? ToolInvokerError else { return false }
            return invokerError.kind == .missingRequiredField
                && invokerError.field == "city"
                && invokerError.message.contains("city")
        }
        #expect(tool.recorded == nil)
    }

    // MARK: - Guide violations fail, quoting the constraint

    @Test("a bad enum value fails with a message quoting the allowed choices")
    func enumGuideViolationQuotesConstraint() async throws {
        let tool = WeatherTool()
        let content = try ArgumentMarshaler.marshalArguments(
            .object(["city": .string("ATX"), "units": .string("kelvin")])
        )

        await #expect {
            try await ToolInvoker.invoke(tool, content: content)
        } throws: { error in
            guard let invokerError = error as? ToolInvokerError else { return false }
            return invokerError.kind == .guideViolation
                && invokerError.field == "units"
                && invokerError.message.contains("\"c\"")
                && invokerError.message.contains("\"f\"")
                && invokerError.message.contains("kelvin")
        }
    }

    @Test("an out-of-range number fails with a message quoting the bound")
    func numericRangeGuideViolationQuotesConstraint() async throws {
        let tool = RangedTool()
        let content = try ArgumentMarshaler.marshalArguments(.object(["score": .number(99)]))

        await #expect {
            try await ToolInvoker.invoke(tool, content: content)
        } throws: { error in
            guard let invokerError = error as? ToolInvokerError else { return false }
            return invokerError.kind == .guideViolation
                && invokerError.field == "score"
                && invokerError.message.contains("10")
                && invokerError.message.contains("99")
        }
    }

    @Test("an array below the minimum count fails with a message quoting the bound")
    func arrayCountGuideViolationQuotesConstraint() async throws {
        let tool = CountedTool()
        let content = try ArgumentMarshaler.marshalArguments(.object(["ratings": .array([])]))

        await #expect {
            try await ToolInvoker.invoke(tool, content: content)
        } throws: { error in
            guard let invokerError = error as? ToolInvokerError else { return false }
            return invokerError.kind == .guideViolation
                && invokerError.field == "ratings"
                && invokerError.message.contains("1")
        }
    }

    @Test("an array above the maximum count fails with a message quoting the bound")
    func arrayCountAboveMaximumGuideViolationQuotesConstraint() async throws {
        let tool = CountedTool()
        let content = try ArgumentMarshaler.marshalArguments(
            .object(["ratings": .array([.number(1), .number(2), .number(3), .number(4)])])
        )

        await #expect {
            try await ToolInvoker.invoke(tool, content: content)
        } throws: { error in
            guard let invokerError = error as? ToolInvokerError else { return false }
            return invokerError.kind == .guideViolation
                && invokerError.field == "ratings"
                && invokerError.message.contains("3")
        }
    }

    @Test("an explicit null for a required argument fails before call, naming the offending field")
    func explicitNullForRequiredFieldFailsBeforeCallNamingField() async throws {
        let tool = RecordingTool()
        let content = try ArgumentMarshaler.marshalArguments(.object(["city": .null]))

        await #expect {
            try await ToolInvoker.invoke(tool, content: content)
        } throws: { error in
            guard let invokerError = error as? ToolInvokerError else { return false }
            return invokerError.kind == .typeMismatch
                && invokerError.field == "city"
                && invokerError.message.contains("city")
        }
        #expect(tool.recorded == nil)
    }

    // MARK: - The T.Arguments(content) fallback layer

    @Test("a mismatch invisible to the top-level guide check (an array element's own type) is still caught by T.Arguments's own decoding, before call")
    func nestedElementTypeMismatchCaughtByArgumentsDecoding() async throws {
        let tool = CountedTool()
        // `ratings` satisfies the top-level array-count guide (1...3 items,
        // one supplied) — only `T.Arguments(content)`'s own `[Int]`
        // decoding can catch that the one element is a string, not an Int.
        let content = try ArgumentMarshaler.marshalArguments(.object(["ratings": .array([.string("not-a-number")])]))

        await #expect {
            try await ToolInvoker.invoke(tool, content: content)
        } throws: { error in
            (error as? ToolInvokerError)?.kind == .invalidArguments
        }
    }

    // MARK: - A throwing tool's error propagates with its message intact

    @Test("a throwing tool's error propagates with its message intact, not wrapped")
    func throwingToolErrorPropagatesUnwrapped() async throws {
        let tool = ThrowingTool()
        let content = try ArgumentMarshaler.marshalArguments(.object(["city": .string("ATX")]))

        await #expect {
            try await ToolInvoker.invoke(tool, content: content)
        } throws: { error in
            (error as? ThrowingToolError) == ThrowingToolError(message: "boom: ATX")
        }
    }
}
