import Testing

@testable import FoundationModelsMultitool

/// M5 coverage for `ResultRenderer`: turning an `InterpreterResult` (or a
/// thrown `InterpreterError`) into the text handed back to the model —
/// return-value cap/truncation, independent console-output cap, and
/// repairable-error rendering that preserves a `ToolInvoker` validation
/// error's field/constraint text. No model is needed for any of this;
/// `JSCInterpreter` (M1) supplies real `InterpreterResult`/`InterpreterError`
/// values so the exception-fidelity test is a genuine round trip, not a
/// hand-built stand-in.
@Suite("ResultRenderer")
struct ResultRendererTests {
    // MARK: - Clean run: return-value-only, no error scaffolding

    @Test("a clean run with no console output renders return-value-only")
    func cleanRunRendersReturnValueOnly() {
        let result = InterpreterResult(returnValue: .object(["tempC": .number(20)]), consoleLines: [])

        let rendered = ResultRenderer.render(result)

        #expect(rendered == "{\"tempC\":20}")
        #expect(!rendered.lowercased().contains("error"))
        #expect(!rendered.lowercased().contains("fix"))
        #expect(!rendered.lowercased().contains("retry"))
    }

    // MARK: - Return-value cap: under / at / over

    @Test("a return value strictly under the cap is not truncated")
    func returnValueUnderCapIsNotTruncated() {
        let result = InterpreterResult(returnValue: .string("hi"), consoleLines: [])
        let limits = ResultRendererLimits(returnValueCharacterLimit: 10, consoleCharacterLimit: 10)

        let rendered = ResultRenderer.render(result, limits: limits)

        #expect(rendered == "\"hi\"")
        #expect(!rendered.contains("truncated"))
    }

    @Test("a return value exactly at the cap is not truncated")
    func returnValueAtCapIsNotTruncated() {
        // Serializes to `"aaaa"` — six characters, including the quotes.
        let result = InterpreterResult(returnValue: .string("aaaa"), consoleLines: [])
        let limits = ResultRendererLimits(returnValueCharacterLimit: 6, consoleCharacterLimit: 6)

        let rendered = ResultRenderer.render(result, limits: limits)

        #expect(rendered == "\"aaaa\"")
        #expect(!rendered.contains("truncated"))
    }

    @Test("a return value over the cap is truncated and carries a visible truncation note")
    func returnValueOverCapIsTruncatedWithNote() {
        // Serializes to `"aaaaaaaaaa"` (12 characters); cap it at 6.
        let result = InterpreterResult(returnValue: .string("aaaaaaaaaa"), consoleLines: [])
        let limits = ResultRendererLimits(returnValueCharacterLimit: 6, consoleCharacterLimit: 100)

        let rendered = ResultRenderer.render(result, limits: limits)

        #expect(rendered.hasPrefix("\"aaaaa"))
        #expect(rendered.contains("truncated"))
        #expect(rendered.contains("6"))
    }

    @Test("truncation never splits a multi-byte character")
    func truncationDoesNotSplitMultiByteCharacters() {
        // Each "🎉" is a single `Character` (one extended grapheme cluster)
        // but multiple UTF-8 bytes/UTF-16 code units — a byte-oriented cap
        // could slice through the middle of one and produce an invalid
        // string. Character-based truncation never can.
        let emojiString = String(repeating: "🎉", count: 20)
        let result = InterpreterResult(returnValue: .string(emojiString), consoleLines: [])
        let limits = ResultRendererLimits(returnValueCharacterLimit: 10, consoleCharacterLimit: 100)

        let rendered = ResultRenderer.render(result, limits: limits)

        // The serialized JSON is a leading quote followed by the emoji
        // characters, so the first 10 characters are the quote plus the
        // first 9 emoji — never a torn one.
        #expect(rendered.prefix(10) == "\"" + String(repeating: "🎉", count: 9))
        #expect(rendered.contains("truncated"))
    }

    // MARK: - Console output: included, capped independently

    @Test("console output is appended after the return value")
    func consoleOutputIsAppendedAfterReturnValue() {
        let result = InterpreterResult(returnValue: .number(1), consoleLines: ["first", "second"])

        let rendered = ResultRenderer.render(result)

        #expect(rendered.contains("1"))
        #expect(rendered.contains("first"))
        #expect(rendered.contains("second"))
        // The return value appears before the console output.
        let returnRange = rendered.range(of: "1")
        let consoleRange = rendered.range(of: "first")
        #expect(returnRange != nil && consoleRange != nil)
        if let returnRange, let consoleRange {
            #expect(returnRange.lowerBound < consoleRange.lowerBound)
        }
    }

    @Test("console output over its cap is truncated independently of the return-value cap")
    func consoleOutputOverCapIsTruncatedIndependently() {
        let result = InterpreterResult(
            returnValue: .string("ok"),
            consoleLines: ["aaaaaaaaaa"] // 10 characters
        )
        let limits = ResultRendererLimits(returnValueCharacterLimit: 1_000, consoleCharacterLimit: 4)

        let rendered = ResultRenderer.render(result, limits: limits)

        // The return value (well under its generous cap) is untouched...
        #expect(rendered.contains("\"ok\""))
        // ...but the console section is cut down to its own small cap.
        #expect(rendered.contains("aaaa"))
        #expect(!rendered.contains("aaaaaaaaaa"))
        #expect(rendered.contains("truncated"))
    }

    @Test("console output at its cap is not truncated")
    func consoleOutputAtCapIsNotTruncated() {
        let result = InterpreterResult(returnValue: .null, consoleLines: ["abcd"])
        let limits = ResultRendererLimits(returnValueCharacterLimit: 1_000, consoleCharacterLimit: 4)

        let rendered = ResultRenderer.render(result, limits: limits)

        #expect(rendered.contains("abcd"))
        #expect(!rendered.contains("truncated"))
    }

    // MARK: - Default limits, exercised at their real boundary

    @Test("the default return-value limit truncates a value over 4,000 characters")
    func defaultReturnValueLimitTruncatesOverFourThousandCharacters() {
        let result = InterpreterResult(returnValue: .string(String(repeating: "a", count: 4_100)), consoleLines: [])

        let rendered = ResultRenderer.render(result)

        #expect(rendered.contains("truncated"))
        #expect(rendered.contains("4000"))
    }

    @Test("the default console limit truncates output over 2,000 characters")
    func defaultConsoleLimitTruncatesOverTwoThousandCharacters() {
        let result = InterpreterResult(returnValue: .null, consoleLines: [String(repeating: "a", count: 2_100)])

        let rendered = ResultRenderer.render(result)

        #expect(rendered.contains("truncated"))
        #expect(rendered.contains("2000"))
    }

    // MARK: - Negative limits are clamped, never crash

    @Test("a negative limit is clamped to zero rather than trapping in String.prefix")
    func negativeLimitIsClampedToZero() {
        let limits = ResultRendererLimits(returnValueCharacterLimit: -5, consoleCharacterLimit: -1)

        #expect(limits.returnValueCharacterLimit == 0)
        #expect(limits.consoleCharacterLimit == 0)

        // Exercise the clamped limit through the real render path (not just
        // the stored property) so a regression that clamps the property but
        // not the enforced cap would still be caught.
        let result = InterpreterResult(returnValue: .string("hi"), consoleLines: ["log"])
        let rendered = ResultRenderer.render(result, limits: limits)

        #expect(rendered.contains("truncated"))
        #expect(!rendered.contains("\"hi\""))
    }

    // MARK: - Repairable errors

    @Test("an InterpreterError renders as a repairable error with an instruction to retry")
    func interpreterErrorRendersAsRepairableError() {
        let error = InterpreterError(kind: .exception, message: "boom", line: 3)

        let rendered = ResultRenderer.render(error)

        #expect(rendered.contains("boom"))
        #expect(rendered.contains("3"))
        #expect(rendered.lowercased().contains("fix"))
        #expect(rendered.lowercased().contains("retry") || rendered.lowercased().contains("again"))
    }

    @Test("a timeout InterpreterError is distinguishable from a thrown-exception error")
    func timeoutErrorIsDistinguishableFromException() {
        let timeout = InterpreterError(kind: .timeout, message: "Execution exceeded the 5.0s time limit.")

        let rendered = ResultRenderer.render(timeout)

        #expect(rendered.lowercased().contains("time"))
        #expect(rendered.contains("Execution exceeded the 5.0s time limit."))
    }

    @Test("a ToolInvoker validation error's field and constraint text survive rendering intact")
    func toolInvokerValidationErrorFieldTextSurvivesRendering() throws {
        // Mirrors the real pipeline exactly: `JSCInterpreter.install` wraps
        // any thrown Swift error (here, a `ToolInvokerError` a host function
        // representing a wrapped tool would throw) as a JS exception whose
        // message is `"<hostFunctionName>: \(error)"`, which JSC then
        // surfaces back out as an `InterpreterError`. So this is a genuine
        // round trip through the real interpreter, not a hand-built stand-in.
        let interpreter = JSCInterpreter()
        let failingTool = HostFunction(name: "weather") { _ in
            throw ToolInvokerError(
                kind: .missingRequiredField,
                field: "city",
                message: "Tool \"weather\" is missing its required argument \"city\"."
            )
        }

        var caught: InterpreterError?
        do {
            _ = try interpreter.run(code: "return weather({});", installing: [failingTool])
        } catch let error as InterpreterError {
            caught = error
        }
        let interpreterError = try #require(caught)

        let rendered = ResultRenderer.render(interpreterError)

        #expect(rendered.contains("city"))
        #expect(rendered.contains("Tool \"weather\" is missing its required argument \"city\"."))
        #expect(rendered.lowercased().contains("fix"))
    }
}
