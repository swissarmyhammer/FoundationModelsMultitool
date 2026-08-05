import Foundation
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

    // MARK: - Top-level await

    @Test("a snippet may await a host function's result at the top level")
    func topLevelAwaitOfHostFunctionResult() throws {
        let interpreter = JSCInterpreter()
        let weather = HostFunction(name: "weather") { _ in .object(["tempC": .number(31)]) }
        let result = try interpreter.run(
            code: """
            const conditions = await weather();
            return conditions.tempC;
            """,
            installing: [weather]
        )
        #expect(result.returnValue == .number(31))
    }

    @Test("a snippet may await a genuine promise at the top level")
    func topLevelAwaitOfPromise() throws {
        let interpreter = JSCInterpreter()
        let result = try interpreter.run(
            code: "return await Promise.resolve(42);",
            installing: []
        )
        #expect(result.returnValue == .number(42))
    }

    @Test("an awaited rejection surfaces as InterpreterError with its message")
    func awaitedRejectionSurfacesAsInterpreterError() throws {
        let interpreter = JSCInterpreter()
        #expect {
            try interpreter.run(
                code: "await Promise.reject(new Error(\"kaput\"));",
                installing: []
            )
        } throws: { error in
            guard let interpreterError = error as? InterpreterError else { return false }
            return interpreterError.kind == .exception
                && interpreterError.message.contains("kaput")
        }
    }

    @Test("awaiting a promise that never settles surfaces as InterpreterError, not a hang")
    func neverSettlingAwaitSurfacesAsInterpreterError() throws {
        let interpreter = JSCInterpreter()
        #expect {
            try interpreter.run(
                code: "await new Promise(function() {});",
                installing: []
            )
        } throws: { error in
            guard let interpreterError = error as? InterpreterError else { return false }
            return interpreterError.kind == .exception
                && interpreterError.message.contains("never settled")
        }
    }

    // MARK: - Async host functions (promise pump)

    @Test("a snippet may await an async host function's result at the top level")
    func topLevelAwaitOfAsyncHostFunctionResult() throws {
        let interpreter = JSCInterpreter()
        let weather = AsyncHostFunction(name: "weatherAsync") { _ in
            try await Task.sleep(nanoseconds: 20_000_000)
            return .object(["tempC": .number(31)])
        }
        let result = try interpreter.run(
            code: """
            const conditions = await weatherAsync();
            return conditions.tempC;
            """,
            installing: [],
            installingAsync: [weather]
        )
        #expect(result.returnValue == .number(31))
    }

    @Test("the sandbox stays alive across multiple sequential async host-function awaits")
    func sandboxSurvivesMultipleSequentialAwaits() throws {
        let interpreter = JSCInterpreter()
        let increment = AsyncHostFunction(name: "incrementAsync") { arguments in
            guard case .number(let value) = arguments.first else {
                throw InterpreterError(kind: .exception, message: "expected a number argument")
            }
            try await Task.sleep(nanoseconds: 20_000_000)
            return .number(value + 1)
        }
        let result = try interpreter.run(
            code: """
            let total = 0;
            total = await incrementAsync(total);
            total = await incrementAsync(total);
            total = await incrementAsync(total);
            return total;
            """,
            installing: [],
            installingAsync: [increment]
        )
        #expect(result.returnValue == .number(3))
    }

    @Test("Promise.all over two async host functions runs them concurrently")
    func promiseAllRunsAsyncHostFunctionsConcurrently() throws {
        let interpreter = JSCInterpreter()
        let windows = OSAllocatedUnfairLock<[(start: ContinuousClock.Instant, end: ContinuousClock.Instant)]>(
            initialState: []
        )
        func makeDelayed(name: String) -> AsyncHostFunction {
            AsyncHostFunction(name: name) { _ in
                let start = ContinuousClock.now
                try await Task.sleep(nanoseconds: 200_000_000)
                let end = ContinuousClock.now
                windows.withLock { $0.append((start, end)) }
                return .null
            }
        }
        let result = try interpreter.run(
            code: """
            await Promise.all([slowA(), slowB()]);
            return "done";
            """,
            installing: [],
            installingAsync: [makeDelayed(name: "slowA"), makeDelayed(name: "slowB")]
        )
        #expect(result.returnValue == .string("done"))
        let recorded = windows.withLock { $0 }
        #expect(recorded.count == 2)
        // Real concurrency, not serialization: each call's window overlaps
        // the other's — if the bridge ran them one after another, one
        // window would start only after the other had already ended.
        let overlap = recorded[0].start < recorded[1].end && recorded[1].start < recorded[0].end
        #expect(overlap)
    }

    @Test("a floating async host-function call completes before the run returns")
    func floatingAsyncCallSettlesBeforeReturn() throws {
        let interpreter = JSCInterpreter()
        let completed = OSAllocatedUnfairLock(initialState: false)
        let write = AsyncHostFunction(name: "writeAsync") { _ in
            try await Task.sleep(nanoseconds: 100_000_000)
            completed.withLock { $0 = true }
            return .null
        }
        let result = try interpreter.run(
            code: """
            writeAsync();
            return "done";
            """,
            installing: [],
            installingAsync: [write]
        )
        #expect(result.returnValue == .string("done"))
        #expect(completed.withLock { $0 })
    }

    @Test("a floating async host-function rejection fails the run")
    func floatingAsyncRejectionFailsRun() throws {
        let interpreter = JSCInterpreter()
        let boom = AsyncHostFunction(name: "boomAsync") { _ in
            try await Task.sleep(nanoseconds: 50_000_000)
            throw InterpreterError(kind: .exception, message: "nope")
        }
        #expect {
            try interpreter.run(
                code: """
                boomAsync();
                return "done";
                """,
                installing: [],
                installingAsync: [boom]
            )
        } throws: { error in
            guard let interpreterError = error as? InterpreterError else { return false }
            return interpreterError.kind == .exception
                && interpreterError.message.contains("boomAsync")
                && interpreterError.message.contains("nope")
        }
    }

    @Test("an awaited async host-function rejection that is caught does not fail the run")
    func caughtAsyncRejectionDoesNotFailRun() throws {
        let interpreter = JSCInterpreter()
        let boom = AsyncHostFunction(name: "boomAsync") { _ in
            try await Task.sleep(nanoseconds: 20_000_000)
            throw InterpreterError(kind: .exception, message: "nope")
        }
        let result = try interpreter.run(
            code: """
            try {
              await boomAsync();
              return "unreachable";
            } catch (e) {
              return "caught";
            }
            """,
            installing: [],
            installingAsync: [boom]
        )
        #expect(result.returnValue == .string("caught"))
    }

    @Test("a rejection that settles while a different sibling call is still pending is still caught, not reported as floating")
    func delayedSequentialAwaitOfEarlierSettledRejectionIsStillCaught() throws {
        // Regression: `pumpUntilSettled` used to decide "floating" per
        // individual settlement, which fires too early here — `fast`
        // rejects and settles while the snippet is still suspended on
        // `await slow()`, well before the snippet's own code even reaches
        // `await fast()`. Floating-rejection detection must only be decided
        // once, after the whole registry has drained.
        let interpreter = JSCInterpreter()
        let slow = AsyncHostFunction(name: "slow") { _ in
            try await Task.sleep(nanoseconds: 150_000_000)
            return .string("slow-done")
        }
        let fast = AsyncHostFunction(name: "fast") { _ in
            try await Task.sleep(nanoseconds: 10_000_000)
            throw InterpreterError(kind: .exception, message: "fast-boom")
        }
        let result = try interpreter.run(
            code: """
            const slowPromise = slow();
            const fastPromise = fast();
            try {
              await slowPromise;
              await fastPromise;
              return "unreachable";
            } catch (e) {
              return "caught";
            }
            """,
            installing: [],
            installingAsync: [slow, fast]
        )
        #expect(result.returnValue == .string("caught"))
    }

    @Test("a snippet's own floating rejection, unrelated to any async host function, does not fail the run")
    func snippetOwnFloatingRejectionIsOutOfScope() throws {
        // Floating-rejection detection is scoped to promises the async
        // host-function bridge itself creates (eventplan.md: "each promise
        // it creates") — a snippet's own `Promise.reject(...)`, with no
        // async host functions installed at all, is untouched by it.
        let interpreter = JSCInterpreter()
        let result = try interpreter.run(
            code: """
            Promise.reject(new Error("snippet-made"));
            return "ok";
            """,
            installing: []
        )
        #expect(result.returnValue == .string("ok"))
    }

    @Test("an async host function's unawaited RETURNED promise settles at the run's boundary")
    func unawaitedReturnedPromiseSettlesAtBoundary() throws {
        let interpreter = JSCInterpreter()
        let weather = AsyncHostFunction(name: "weatherAsync") { _ in
            try await Task.sleep(nanoseconds: 20_000_000)
            return .object(["tempC": .number(31)])
        }
        let result = try interpreter.run(
            code: "return weatherAsync();",
            installing: [],
            installingAsync: [weather]
        )
        #expect(result.returnValue == .object(["tempC": .number(31)]))
    }

    @Test("a bridge call's returned value supports .catch(...), not just await/.then")
    func bridgeReturnValueSupportsCatch() throws {
        let interpreter = JSCInterpreter()
        let boom = AsyncHostFunction(name: "boomAsync") { _ in
            try await Task.sleep(nanoseconds: 20_000_000)
            throw InterpreterError(kind: .exception, message: "nope")
        }
        let result = try interpreter.run(
            code: """
            return boomAsync().catch(function(e) { return "caught:" + e; });
            """,
            installing: [],
            installingAsync: [boom]
        )
        guard case .string(let value) = result.returnValue else {
            Issue.record("expected a string return value")
            return
        }
        #expect(value.hasPrefix("caught:"))
    }

    @Test("a .then(onFulfilled) with no rejection handler still fails the run on rejection")
    func thenWithNoRejectionHandlerStillFailsRun() throws {
        // Consumption means the rejection was genuinely handled, not merely
        // that `.then` was called: `.then(onFulfilled)` alone supplies no
        // `onRejected`, so a `boomAsync()` rejection here is exactly as
        // unaddressed as `boomAsync(); return "done";` — it must still fail
        // the run, not disappear into the untracked derived promise
        // `.then(onFulfilled)` creates.
        let interpreter = JSCInterpreter()
        let boom = AsyncHostFunction(name: "boomAsync") { _ in
            try await Task.sleep(nanoseconds: 20_000_000)
            throw InterpreterError(kind: .exception, message: "nope")
        }
        #expect {
            try interpreter.run(
                code: """
                boomAsync().then(function(v) { return v; });
                return "done";
                """,
                installing: [],
                installingAsync: [boom]
            )
        } throws: { error in
            guard let interpreterError = error as? InterpreterError else { return false }
            return interpreterError.kind == .exception
                && interpreterError.message.contains("boomAsync")
                && interpreterError.message.contains("nope")
        }
    }

    @Test("a bridge call's returned value supports .finally(...) and is instanceof Promise")
    func bridgeReturnValueSupportsFinallyAndIsPromise() throws {
        let interpreter = JSCInterpreter()
        let weather = AsyncHostFunction(name: "weatherAsync") { _ in
            try await Task.sleep(nanoseconds: 20_000_000)
            return .number(31)
        }
        let result = try interpreter.run(
            code: """
            let ranFinally = false;
            const value = await weatherAsync().finally(function() { ranFinally = true; });
            return { value: value, ranFinally: ranFinally, isPromise: weatherAsync() instanceof Promise };
            """,
            installing: [],
            installingAsync: [weather]
        )
        #expect(
            result.returnValue == .object([
                "value": .number(31),
                "ranFinally": .bool(true),
                "isPromise": .bool(true),
            ])
        )
    }

    @Test("running a snippet with an async host function does not leak the sandbox")
    func asyncHostFunctionDoesNotLeakTheSandbox() throws {
        // Regression: an earlier version of the promise bridge captured the
        // internal `JSValue` promise directly inside a native function
        // installed into that same `JSContext` — a retain cycle (the
        // context's heap holds the function, the function holds the
        // `JSValue`, the `JSValue` holds its `JSContext`) that kept the
        // whole sandbox alive forever. `run` blocks until every bridge
        // promise settles (`pumpUntilSettled`), so by the time it returns,
        // the canary's only remaining reference is this test's own `var`.
        final class Canary: @unchecked Sendable {
            static let deinitCount = OSAllocatedUnfairLock(initialState: 0)
            deinit { Canary.deinitCount.withLock { $0 += 1 } }
        }
        let before = Canary.deinitCount.withLock { $0 }
        let canaryBox = OSAllocatedUnfairLock<Canary?>(initialState: Canary())
        let interpreter = JSCInterpreter()
        let touch = AsyncHostFunction(name: "touchAsync") { _ in
            canaryBox.withLock { _ = $0 }
            return .null
        }
        _ = try interpreter.run(
            code: "touchAsync(); return \"done\";",
            installing: [],
            installingAsync: [touch]
        )
        canaryBox.withLock { $0 = nil }
        #expect(Canary.deinitCount.withLock { $0 } == before + 1)
    }

    @Test("isCancelled mid-await cancels a pending async host function and returns within the time limit")
    func cancellationCancelsPendingAsyncHostFunction() throws {
        let interpreter = JSCInterpreter(timeLimit: 10.0)
        let cancelledBox = OSAllocatedUnfairLock(initialState: false)
        let taskWasCancelled = OSAllocatedUnfairLock(initialState: false)
        let slow = AsyncHostFunction(name: "slowAsync") { _ in
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch {
                taskWasCancelled.withLock { $0 = true }
                throw error
            }
            return .null
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
            cancelledBox.withLock { $0 = true }
        }
        let start = ContinuousClock.now
        #expect {
            try interpreter.run(
                code: "await slowAsync(); return \"done\";",
                installing: [],
                installingAsync: [slow],
                isCancelled: { cancelledBox.withLock { $0 } }
            )
        } throws: { error in
            error is CancellationError
        }
        #expect(start.duration(to: .now) < .seconds(3))
        // Give the abandoned background Task a moment to observe its own
        // cancellation after `run` has already returned.
        Thread.sleep(forTimeInterval: 0.3)
        #expect(taskWasCancelled.withLock { $0 })
    }
}
