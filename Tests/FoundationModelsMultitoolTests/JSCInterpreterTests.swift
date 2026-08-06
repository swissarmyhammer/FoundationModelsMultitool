import Foundation
import Testing
import os

@testable import FoundationModelsMultitool

/// M1 coverage for `JSCInterpreter`: return-value capture, console capture,
/// exception mapping, cross-run statelessness, host-function round-trips,
/// and the execution-time watchdog. No model is needed for any of this.
@Suite("JSCInterpreter", .serialized)
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

    @Test("a sync result the bridge cannot convert to JSON surfaces the underlying conversion error")
    func syncResultConversionFailureSurfacesUnderlyingError() throws {
        // The sync bridge and the async bridge convert a host function's
        // successful result through the very same `jsValue(from:in:)`, and
        // both report a failure of that conversion as `"<name>: <error>"`.
        // This is the sync half of that pair; the async half is
        // `asyncResultConversionFailureRejectsWithUnderlyingError`. Reaching
        // the branch takes a snippet that breaks the sandbox's own
        // `JSON.parse` — the mechanism the conversion goes through — before
        // it calls the host function. The stub returns `undefined` rather
        // than throwing: a throwing stub would additionally notify a
        // TypeError into the context, which would surface instead of the
        // message under test.
        let interpreter = JSCInterpreter()
        let weather = HostFunction(name: "weather") { _ in .object(["tempC": .number(31)]) }
        let result = try interpreter.run(
            code: """
            JSON.parse = function () { return undefined; };
            try {
              weather();
              return "unreachable";
            } catch (e) {
              return e.message;
            }
            """,
            installing: [weather]
        )
        #expect(result.returnValue == .string("weather: JSON.parse is unavailable."))
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

    @Test("an async result the bridge cannot convert to JSON rejects with the underlying conversion error")
    func asyncResultConversionFailureRejectsWithUnderlyingError() throws {
        // `settle(_:in:)`'s success branch used to reject with a fixed
        // "could not convert the result to JSON." string, discarding the
        // real error and diverging from the sync bridge's
        // `"<name>: <error>"` shape. Reaching that branch takes a snippet
        // that breaks the sandbox's own `JSON.parse` — the mechanism
        // `jsValue(from:in:)` converts through — after the call has started
        // but before the pump settles it. The stub returns `undefined`
        // rather than throwing: a throwing stub would additionally notify a
        // TypeError into the context, which `evaluate` reports ahead of the
        // rejection, hiding the message under test.
        let interpreter = JSCInterpreter()
        let weather = AsyncHostFunction(name: "weatherAsync") { _ in
            try await Task.sleep(nanoseconds: 20_000_000)
            return .object(["tempC": .number(31)])
        }
        let result = try interpreter.run(
            code: """
            const pending = weatherAsync();
            JSON.parse = function () { return undefined; };
            try {
              await pending;
              return "unreachable";
            } catch (e) {
              return e.message;
            }
            """,
            installing: [],
            installingAsync: [weather]
        )
        #expect(result.returnValue == .string("weatherAsync: JSON.parse is unavailable."))
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

    @Test("a .then(undefined, nonFunction) with a non-callable rejection handler still fails the run on rejection")
    func thenWithNonCallableRejectionHandlerStillFailsRun() throws {
        // A non-undefined/non-null second argument to `.then` is not on its
        // own proof of a genuine rejection handler — `.then(undefined,
        // false)` supplies a value that cannot run as `onRejected`, so the
        // real `Promise.prototype.then` treats it exactly like `undefined`
        // (per spec, a non-callable `onRejected` is replaced with a default
        // handler that rethrows). The rejection must still be reported as
        // floating, not swallowed as "handled" merely because a second
        // argument happened to be present.
        let interpreter = JSCInterpreter()
        let boom = AsyncHostFunction(name: "boomAsync") { _ in
            try await Task.sleep(nanoseconds: 20_000_000)
            throw InterpreterError(kind: .exception, message: "nope")
        }
        #expect {
            try interpreter.run(
                code: """
                boomAsync().then(undefined, false);
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

    @Test("a .then(undefined, objectInstanceofFunction) with a merely-instanceof-Function, non-callable handler still fails the run")
    func thenWithInstanceOfFunctionButNonCallableHandlerStillFailsRun() throws {
        // `instanceof Function` is neither necessary nor sufficient for
        // callability: `Object.create(Function.prototype)` passes
        // `instanceof Function` (it inherits from `Function.prototype`) yet
        // has no internal `[[Call]]` — `typeof` reports `"object"`, and the
        // real `Promise.prototype.then` cannot invoke it as `onRejected`.
        // Marking this "handled" would be exactly the false positive the
        // original finding named, just with a different witness value than
        // `.then(undefined, false)`.
        let interpreter = JSCInterpreter()
        let boom = AsyncHostFunction(name: "boomAsync") { _ in
            try await Task.sleep(nanoseconds: 20_000_000)
            throw InterpreterError(kind: .exception, message: "nope")
        }
        #expect {
            try interpreter.run(
                code: """
                boomAsync().then(undefined, Object.create(Function.prototype));
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

    @Test("a .then(undefined, callableButNotInstanceofFunction) handler is still recognized as genuinely handling the rejection")
    func thenWithCallableButNotInstanceOfFunctionHandlerDoesNotFailRun() throws {
        // `Function.prototype` is itself callable (`typeof
        // Function.prototype === "function"`, a real no-op function) but is
        // NOT `instanceof Function` (its own prototype is
        // `Object.prototype`, not `Function.prototype`). A rejection
        // handler this permissive but genuinely callable must still count
        // as handled — the other direction of the same false test the
        // previous case guards.
        let interpreter = JSCInterpreter()
        let boom = AsyncHostFunction(name: "boomAsync") { _ in
            try await Task.sleep(nanoseconds: 20_000_000)
            throw InterpreterError(kind: .exception, message: "nope")
        }
        let result = try interpreter.run(
            code: """
            boomAsync().then(undefined, Function.prototype);
            return "done";
            """,
            installing: [],
            installingAsync: [boom]
        )
        #expect(result.returnValue == .string("done"))
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
        // the sandbox — and everything it retained, including the async
        // host function's own closure — must have been torn down.
        //
        // The closure below captures `canary` directly, so the *only* two
        // strong owners are this test's own `var` and that closure (which
        // `install(asyncHostFunction:into:registry:)` embeds in the native
        // function it installs on the context). Dropping this test's `var`
        // after `run` returns and observing the `weak` reference go `nil`
        // proves the closure — and the context that was the only other
        // thing keeping it alive — was actually released, not merely that
        // some unrelated shared box was cleared out from under it.
        final class Canary: @unchecked Sendable {}
        var canary: Canary? = Canary()
        weak let weakCanary = canary
        try autoreleasepool {
            let interpreter = JSCInterpreter()
            let touch = AsyncHostFunction(name: "touchAsync") { [canary] _ in
                _ = canary
                return .null
            }
            _ = try interpreter.run(
                code: "touchAsync(); return \"done\";",
                installing: [],
                installingAsync: [touch]
            )
        }
        canary = nil
        #expect(weakCanary == nil)
    }

    // MARK: - Proxy trap on pending results

    @Test("accessing a property other than then/catch/finally on a pending async host-function result throws a precise, model-repairable error naming the call and the property")
    func propertyAccessOnPendingResultThrowsForgotAwaitError() throws {
        let interpreter = JSCInterpreter()
        let call = AsyncHostFunction(name: "tools.x.y") { _ in
            try await Task.sleep(nanoseconds: 20_000_000)
            return .object(["value": .number(1)])
        }
        #expect {
            try interpreter.run(
                code: """
                const r = globalThis["tools.x.y"]();
                return r.value;
                """,
                installing: [],
                installingAsync: [call]
            )
        } throws: { error in
            guard let interpreterError = error as? InterpreterError else { return false }
            return interpreterError.kind == .exception
                && interpreterError.message.contains("tools.x.y")
                && interpreterError.message.contains("value")
                && interpreterError.message.contains("did you forget")
                && interpreterError.message.contains("await")
        }
    }

    @Test("arithmetic coercion of a pending async host-function result throws a precise, model-repairable error naming the call, rather than escaping the trap")
    func arithmeticCoercionOfPendingResultThrowsForgotAwaitError() throws {
        // eventplan.md frames "truthiness/arithmetic on a promise" as one
        // uncaught shape, but only bare truthiness genuinely evades this
        // trap (`ToBoolean` on an object never looks up a property).
        // Arithmetic reaches `ToPrimitive`, which does `Get`s for
        // `@@toPrimitive`/`valueOf`/`toString` — none of them exempted here
        // — so this is caught too, incidentally. Regression coverage for
        // `describeNonExemptProperty`, which must render the `Symbol`
        // property key `@@toPrimitive` names without itself crashing.
        let interpreter = JSCInterpreter()
        let call = AsyncHostFunction(name: "tools.x.y") { _ in
            try await Task.sleep(nanoseconds: 20_000_000)
            return .number(1)
        }
        #expect {
            try interpreter.run(
                code: """
                const r = globalThis["tools.x.y"]();
                return r + 1;
                """,
                installing: [],
                installingAsync: [call]
            )
        } throws: { error in
            guard let interpreterError = error as? InterpreterError else { return false }
            return interpreterError.kind == .exception
                && interpreterError.message.contains("tools.x.y")
                && interpreterError.message.contains("did you forget")
                && interpreterError.message.contains("await")
        }
    }

    @Test("console.log on a pending async host-function result throws a precise, model-repairable error instead of crashing the process")
    func consoleLogOnPendingResultThrowsForgotAwaitErrorInsteadOfCrashing() throws {
        // Regression: `console.log(r)` coerces `r` via the same
        // `ToPrimitive`/`@@toPrimitive` path as arithmetic, which trips this
        // trap — and `installConsole`'s own argument-to-string conversion
        // used to force-unwrap `JSValue.toString()`'s result, which is
        // `nil` (not itself throwing) exactly when that coercion fails,
        // crashing the whole host process instead of surfacing the trap's
        // repairable error. Confirmed against JSC directly while
        // implementing this fix.
        let interpreter = JSCInterpreter()
        let call = AsyncHostFunction(name: "tools.x.y") { _ in
            try await Task.sleep(nanoseconds: 20_000_000)
            return .number(1)
        }
        #expect {
            try interpreter.run(
                code: """
                const r = globalThis["tools.x.y"]();
                console.log(r);
                return "unreachable";
                """,
                installing: [],
                installingAsync: [call]
            )
        } throws: { error in
            guard let interpreterError = error as? InterpreterError else { return false }
            return interpreterError.kind == .exception
                && interpreterError.message.contains("tools.x.y")
                && interpreterError.message.contains("did you forget")
        }
    }

    @Test("then, catch, and finally are exempt from the pending-result proxy trap")
    func thenCatchFinallyAreExemptFromTheProxyTrap() throws {
        let interpreter = JSCInterpreter()
        let call = AsyncHostFunction(name: "tools.x.y") { _ in
            try await Task.sleep(nanoseconds: 20_000_000)
            return .number(1)
        }
        let result = try interpreter.run(
            code: """
            const r = globalThis["tools.x.y"]();
            const hasThen = typeof r.then === "function";
            const hasCatch = typeof r.catch === "function";
            const hasFinally = typeof r.finally === "function";
            await r;
            return { hasThen: hasThen, hasCatch: hasCatch, hasFinally: hasFinally };
            """,
            installing: [],
            installingAsync: [call]
        )
        #expect(
            result.returnValue == .object([
                "hasThen": .bool(true),
                "hasCatch": .bool(true),
                "hasFinally": .bool(true),
            ])
        )
    }

    @Test("a rejected proxied result is still catchable via .catch even though it is wrapped in a Proxy")
    func proxiedRejectionIsStillCatchable() throws {
        let interpreter = JSCInterpreter()
        let boom = AsyncHostFunction(name: "tools.boom") { _ in
            try await Task.sleep(nanoseconds: 20_000_000)
            throw InterpreterError(kind: .exception, message: "nope")
        }
        let result = try interpreter.run(
            code: """
            return globalThis["tools.boom"]().catch(function(e) { return "caught:" + e; });
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

    @Test("Promise.all resolves both values through the proxy wrapping each pending result")
    func promiseAllResolvesBothProxiedResults() throws {
        let interpreter = JSCInterpreter()
        let a = AsyncHostFunction(name: "tools.a") { _ in
            try await Task.sleep(nanoseconds: 20_000_000)
            return .number(1)
        }
        let b = AsyncHostFunction(name: "tools.b") { _ in
            try await Task.sleep(nanoseconds: 20_000_000)
            return .number(2)
        }
        let result = try interpreter.run(
            code: """
            const values = await Promise.all([globalThis["tools.a"](), globalThis["tools.b"]()]);
            return values[0] + values[1];
            """,
            installing: [],
            installingAsync: [a, b]
        )
        #expect(result.returnValue == .number(3))
    }

    @Test("the forgot-await proxy trap error renders through ResultRenderer with the standard repair instruction")
    func pendingResultPropertyAccessErrorRendersWithRepairInstruction() throws {
        let interpreter = JSCInterpreter()
        let call = AsyncHostFunction(name: "tools.x.y") { _ in
            try await Task.sleep(nanoseconds: 20_000_000)
            return .object(["value": .number(1)])
        }
        do {
            _ = try interpreter.run(
                code: """
                const r = globalThis["tools.x.y"]();
                return r.value;
                """,
                installing: [],
                installingAsync: [call]
            )
            Issue.record("expected the run to throw")
        } catch let interpreterError as InterpreterError {
            let rendered = ResultRenderer.render(interpreterError)
            #expect(rendered.contains("tools.x.y"))
            #expect(rendered.contains("value"))
            #expect(rendered.contains("await"))
            #expect(rendered.hasSuffix("Fix the snippet and call runCode again."))
        }
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

    /// The snippet the cancellation pin and both of its controls run
    /// unchanged: it witnesses that it entered the `try` block, that an
    /// author-written `.catch()` on the pending call ran, and that an
    /// author-written `finally {}` ran.
    ///
    /// Shared verbatim so the pin's negative claim and the controls' positive
    /// ones are made about one piece of code rather than three that could
    /// drift apart.
    private static let cleanupWitnessSnippet = """
        try {
            record("entered");
            await slowAsync().catch(() => { record("catch"); });
            record("afterAwait");
        } finally {
            record("finally");
        }
        return "done";
        """

    /// Builds the `record(marker)` global ``cleanupWitnessSnippet`` calls.
    ///
    /// Deliberately a synchronous `HostFunction` rather than an
    /// `AsyncHostFunction`: it runs inline on the run's own queue, so a marker
    /// lands before `run` returns and a cancelled run cannot drop it for the
    /// wrong reason.
    ///
    /// - Parameter markers: the recorded markers, appended to in call order.
    /// - Returns: the host function to install as `record`.
    private static func makeRecorder(
        into markers: OSAllocatedUnfairLock<[InterpreterValue]>
    ) -> HostFunction {
        HostFunction(name: "record") { arguments in
            markers.withLock { $0.append(arguments.first ?? .null) }
            return .null
        }
    }

    @Test(
        "cancelling a snippet parked on a pending call runs none of its author-written .catch() or finally {}"
    )
    func cancellationSkipsAuthorCatchAndFinally() throws {
        // Pins the ruled cancellation contract (eventplan.md "Async
        // JavaScript"): `cancel` is terminate-without-settling, NOT
        // reject-and-unwind. `PromiseRegistry.cancelAllPending` cancels each
        // backing Swift Task and drops the entry without calling
        // `resolve`/`reject`, so the suspended continuation never resumes and
        // no author cleanup code runs. That is deliberate — settling would
        // resume author JS outside any armed watchdog, which would make a
        // cancelled snippet's `finally { while (true) {} }` unkillable.
        //
        // An `AsyncHostFunction` is what a `tools.*` call is at this layer, so
        // this pins the same path `cancel(completionToken)` drives. The
        // witness is `record` (see `makeRecorder(into:)`), and the snippet is
        // the one both controls below run unchanged.
        let interpreter = JSCInterpreter(timeLimit: 10.0)
        let cancelledBox = OSAllocatedUnfairLock(initialState: false)
        let markers = OSAllocatedUnfairLock<[InterpreterValue]>(initialState: [])
        let slow = AsyncHostFunction(name: "slowAsync") { _ in
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return .null
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
            cancelledBox.withLock { $0 = true }
        }
        let start = ContinuousClock.now
        #expect {
            try interpreter.run(
                code: Self.cleanupWitnessSnippet,
                installing: [Self.makeRecorder(into: markers)],
                installingAsync: [slow],
                isCancelled: { cancelledBox.withLock { $0 } }
            )
        } throws: { error in
            error is CancellationError
        }
        #expect(start.duration(to: .now) < .seconds(3))
        // The sandbox is torn down by the time `run` returns. This sleep buys
        // the cancelled backing Task time to unwind, and gives any late
        // resumption of the suspended continuation a window to land a marker
        // before the markers are read. It does not reach the five seconds at
        // which the pending call would have settled on its own — nothing in
        // this test waits that long.
        Thread.sleep(forTimeInterval: 0.3)
        // `entered` and nothing after it. That first marker is the witness
        // that the snippet really did start, so the absence of `catch` and
        // `finally` is cleanup that was skipped, not a snippet the cancel beat
        // to the `try` block.
        #expect(markers.withLock { $0 } == [.string("entered")])
    }

    @Test("an uncancelled snippet does run its author-written finally {} after a pending call settles")
    func uncancelledSnippetRunsAuthorFinally() throws {
        // The positive control for the `finally` half of
        // `cancellationSkipsAuthorCatchAndFinally`. Same snippet, same witness,
        // no cancellation — so the markers land. Without it, the pin's
        // assertion would still hold if the `record` host function or the async
        // IIFE's `finally` handling broke outright, and the pin would pass
        // while pinning nothing.
        let interpreter = JSCInterpreter(timeLimit: 10.0)
        let markers = OSAllocatedUnfairLock<[InterpreterValue]>(initialState: [])
        let quick = AsyncHostFunction(name: "slowAsync") { _ in
            try await Task.sleep(nanoseconds: 20_000_000)
            return .null
        }
        let result = try interpreter.run(
            code: Self.cleanupWitnessSnippet,
            installing: [Self.makeRecorder(into: markers)],
            installingAsync: [quick]
        )
        #expect(result.returnValue == .string("done"))
        #expect(
            markers.withLock { $0 } == [
                .string("entered"), .string("afterAwait"), .string("finally"),
            ]
        )
    }

    @Test("an uncancelled snippet does run its author-written .catch() when a pending call rejects")
    func uncancelledSnippetRunsAuthorCatch() throws {
        // The positive control for the `.catch()` half of the same pin. The
        // `finally` control above installs a `slowAsync` that resolves, so it
        // never reaches the `.catch()` arm: on its own it would leave the pin
        // asserting the absence of a marker nothing had shown could appear at
        // all. Here the pending call rejects, so an uncancelled run must record
        // `catch` — and the rejection is handled, so the run still completes
        // through `afterAwait` and `finally`.
        let interpreter = JSCInterpreter(timeLimit: 10.0)
        let markers = OSAllocatedUnfairLock<[InterpreterValue]>(initialState: [])
        let rejecting = AsyncHostFunction(name: "slowAsync") { _ in
            try await Task.sleep(nanoseconds: 20_000_000)
            throw InterpreterError(kind: .exception, message: "nope")
        }
        let result = try interpreter.run(
            code: Self.cleanupWitnessSnippet,
            installing: [Self.makeRecorder(into: markers)],
            installingAsync: [rejecting]
        )
        #expect(result.returnValue == .string("done"))
        #expect(
            markers.withLock { $0 } == [
                .string("entered"), .string("catch"), .string("afterAwait"), .string("finally"),
            ]
        )
    }
}
