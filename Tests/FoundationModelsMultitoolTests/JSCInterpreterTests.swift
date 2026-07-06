import Testing
import os

@testable import FoundationModelsMultitool

/// M1 coverage for `JSCInterpreter`: return-value capture, console capture,
/// exception mapping, cross-run statelessness, host-function round-trips,
/// and the execution-time watchdog. No model is needed for any of this.
@Suite("JSCInterpreter")
struct JSCInterpreterTests {
    @Test("a snippet's return value round-trips out as JSON")
    func returnValueRoundTripsAsJson() throws {
        let interpreter = JSCInterpreter()
        let result = try interpreter.run(
            code: "return { a: 1, b: \"two\", c: [true, null, 3.5] };",
            installing: []
        )
        #expect(
            result.returnValue == .object([
                "a": .number(1),
                "b": .string("two"),
                "c": .array([.bool(true), .null, .number(3.5)]),
            ])
        )
    }

    @Test("a snippet with no explicit return produces a null return value")
    func missingReturnValueIsNull() throws {
        let interpreter = JSCInterpreter()
        let result = try interpreter.run(code: "const x = 1;", installing: [])
        #expect(result.returnValue == .null)
    }

    @Test("console.log lines are captured in order")
    func consoleLogLinesCapturedInOrder() throws {
        let interpreter = JSCInterpreter()
        let result = try interpreter.run(
            code: """
            console.log("first");
            console.log("second", 42);
            return null;
            """,
            installing: []
        )
        #expect(result.consoleLines == ["first", "second 42"])
    }

    @Test("a JS throw surfaces as InterpreterError with message and location")
    func jsThrowSurfacesAsInterpreterError() throws {
        let interpreter = JSCInterpreter()
        #expect {
            try interpreter.run(
                code: """
                function boom() {
                  throw new Error("kaboom");
                }
                boom();
                """,
                installing: []
            )
        } throws: { error in
            guard let interpreterError = error as? InterpreterError else { return false }
            return interpreterError.kind == .exception
                && interpreterError.message.contains("kaboom")
                && interpreterError.line == 2
        }
    }

    @Test("a fresh context per run: globals set in run N are absent in run N+1")
    func freshContextPerRun() throws {
        let interpreter = JSCInterpreter()

        let first = try interpreter.run(
            code: "globalThis.counter = 1; return counter;",
            installing: []
        )
        #expect(first.returnValue == .number(1))

        let second = try interpreter.run(
            code: "return typeof counter;",
            installing: []
        )
        #expect(second.returnValue == .string("undefined"))
    }

    @Test("an installed host function is callable from the snippet")
    func hostFunctionIsCallableFromSnippet() throws {
        let interpreter = JSCInterpreter()
        let double = HostFunction(name: "double") { arguments in
            guard case .number(let value) = arguments.first else {
                throw InterpreterError(kind: .exception, message: "expected a number argument")
            }
            return .number(value * 2)
        }
        let result = try interpreter.run(code: "return double(21);", installing: [double])
        #expect(result.returnValue == .number(42))
    }

    @Test("an infinite loop is terminated by the watchdog within the configured limit")
    func infiniteLoopTerminatedByWatchdog() throws {
        let interpreter = JSCInterpreter(timeLimit: 1.0)
        let start = ContinuousClock.now
        #expect {
            try interpreter.run(code: "while (true) {}", installing: [])
        } throws: { error in
            guard let interpreterError = error as? InterpreterError else { return false }
            return interpreterError.kind == .timeout
        }
        // Generous CI-safe bound: the watchdog should fire close to the
        // configured limit, not hang the test indefinitely.
        #expect(start.duration(to: .now) < .seconds(10))
    }

    @Test("a host function that throws surfaces as InterpreterError")
    func hostFunctionThrowSurfacesAsInterpreterError() throws {
        let interpreter = JSCInterpreter()
        let boom = HostFunction(name: "boom") { _ in
            throw InterpreterError(kind: .exception, message: "nope")
        }
        #expect {
            try interpreter.run(code: "return boom();", installing: [boom])
        } throws: { error in
            guard let interpreterError = error as? InterpreterError else { return false }
            return interpreterError.kind == .exception
                && interpreterError.message.contains("boom")
                && interpreterError.message.contains("nope")
        }
    }

    @Test("a JS syntax error surfaces as InterpreterError")
    func syntaxErrorSurfacesAsInterpreterError() throws {
        let interpreter = JSCInterpreter()
        #expect {
            try interpreter.run(code: "function( {{{", installing: [])
        } throws: { error in
            guard let interpreterError = error as? InterpreterError else { return false }
            return interpreterError.kind == .exception
        }
    }

    @Test("a host function returning a non-finite number round-trips as null")
    func hostFunctionNonFiniteReturnValueRoundTripsAsNull() throws {
        let interpreter = JSCInterpreter()
        let makeNaN = HostFunction(name: "makeNaN") { _ in .number(.nan) }
        let result = try interpreter.run(
            code: "return makeNaN() === null ? \"isNull\" : \"notNull\";",
            installing: [makeNaN]
        )
        #expect(result.returnValue == .string("isNull"))
    }

    @Test("a snippet passing Infinity as a host function argument round-trips as null")
    func hostFunctionNonFiniteArgumentRoundTripsAsNull() throws {
        let interpreter = JSCInterpreter()
        let receivedBox = OSAllocatedUnfairLock<InterpreterValue?>(initialState: nil)
        let record = HostFunction(name: "record") { arguments in
            receivedBox.withLock { $0 = arguments.first }
            return .null
        }
        _ = try interpreter.run(code: "record(Infinity);", installing: [record])
        #expect(receivedBox.withLock { $0 } == .null)
    }

    @Test("a snippet ending in a single-line comment before the injected wrapper still evaluates correctly")
    func trailingLineCommentBeforeWrapperIsHandled() throws {
        let interpreter = JSCInterpreter()
        let result = try interpreter.run(code: "return 1; // trailing comment", installing: [])
        #expect(result.returnValue == .number(1))
    }

    @Test("DIAGNOSTIC: isCancelled forces early termination of an infinite loop, isolated from other tests")
    func diagnosticCancellationForcesEarlyTermination() throws {
        let interpreter = JSCInterpreter(timeLimit: 10.0)
        let cancelledBox = OSAllocatedUnfairLock(initialState: false)
        let start = ContinuousClock.now
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
            cancelledBox.withLock { $0 = true }
        }
        #expect {
            try interpreter.run(
                code: "while (true) {}",
                installing: [],
                isCancelled: { cancelledBox.withLock { $0 } }
            )
        } throws: { error in
            error is CancellationError
        }
        let elapsed = start.duration(to: .now)
        print("DIAGNOSTIC elapsed: \(elapsed)")
        #expect(elapsed < .seconds(3))
    }

    @Test("concurrent run() calls from multiple threads stay isolated")
    func concurrentRunsStayIsolated() async throws {
        let interpreter = JSCInterpreter()
        let count = 20

        let results = try await withThrowingTaskGroup(of: (Int, InterpreterValue).self) { group in
            for index in 0..<count {
                group.addTask {
                    let result = try interpreter.run(code: "return \(index);", installing: [])
                    return (index, result.returnValue)
                }
            }
            var collected: [Int: InterpreterValue] = [:]
            for try await (index, value) in group {
                collected[index] = value
            }
            return collected
        }

        for index in 0..<count {
            #expect(results[index] == .number(Double(index)))
        }
    }
}
