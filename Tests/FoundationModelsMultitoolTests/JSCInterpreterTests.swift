import Foundation
import Testing
import os

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// M1 coverage for `JSCInterpreter`: return-value capture, console capture,
/// exception mapping, cross-run statelessness, host-function round-trips,
/// the cancellation watchdog, and the event loop that settles async host
/// functions (task `^cf57dtd`). No model is needed for any of this.
@Suite("JSCInterpreter", .serialized)
struct JSCInterpreterTests {
    /// Runs `code` in a task of its own, waits until `hold` sees its first
    /// call, releases the hold, and gives the result of the run.
    ///
    /// An async host function that calls `hold.pass()` is a genuine async
    /// call: it suspends until the test releases it. The release comes at an
    /// event (the first call arrived) and never after a real delay. After the
    /// release, each later call passes at once. The wait for the first call
    /// also ends when the run ends — see ``HeldCall/releaseOnArrival(during:)``.
    /// Thus a snippet that never calls an async host function that passes
    /// `hold` gives its own result, and the checks of the test fail on it.
    ///
    /// - Parameters:
    ///   - interpreter: The interpreter that runs the snippet.
    ///   - code: The JavaScript source to run.
    ///   - installing: The synchronous host functions to install.
    ///   - installingAsync: The asynchronous host functions to install.
    ///   - hold: The hold that the async host functions pass.
    /// - Returns: The result of the run.
    /// - Throws: What the run throws.
    private static func run(
        _ interpreter: JSCInterpreter,
        code: String,
        installing: [HostFunction] = [],
        installingAsync: [AsyncHostFunction],
        releasing hold: HeldCall
    ) async throws -> InterpreterResult {
        try await hold.releaseOnArrival {
            try await interpreter.run(code: code, installing: installing, installingAsync: installingAsync)
        }
    }

    @Test("a snippet's return value round-trips out as JSON")
    func returnValueRoundTripsAsJson() async throws {
        let interpreter = JSCInterpreter()
        let result = try await interpreter.run(
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
    func missingReturnValueIsNull() async throws {
        let interpreter = JSCInterpreter()
        let result = try await interpreter.run(code: "const x = 1;", installing: [])
        #expect(result.returnValue == .null)
    }

    @Test("console.log lines are captured in order")
    func consoleLogLinesCapturedInOrder() async throws {
        let interpreter = JSCInterpreter()
        let result = try await interpreter.run(
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
    func jsThrowSurfacesAsInterpreterError() async throws {
        let interpreter = JSCInterpreter()
        await #expect {
            try await interpreter.run(
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
    func freshContextPerRun() async throws {
        let interpreter = JSCInterpreter()

        let first = try await interpreter.run(
            code: "globalThis.counter = 1; return counter;",
            installing: []
        )
        #expect(first.returnValue == .number(1))

        let second = try await interpreter.run(
            code: "return typeof counter;",
            installing: []
        )
        #expect(second.returnValue == .string("undefined"))
    }

    @Test("an installed host function is callable from the snippet")
    func hostFunctionIsCallableFromSnippet() async throws {
        let interpreter = JSCInterpreter()
        let double = HostFunction(name: "double") { arguments in
            guard case .number(let value) = arguments.first else {
                throw InterpreterError(kind: .exception, message: "expected a number argument")
            }
            return .number(value * 2)
        }
        let result = try await interpreter.run(code: "return double(21);", installing: [double])
        #expect(result.returnValue == .number(42))
    }

    @Test("a host function that throws surfaces as InterpreterError")
    func hostFunctionThrowSurfacesAsInterpreterError() async throws {
        let interpreter = JSCInterpreter()
        let boom = HostFunction(name: "boom") { _ in
            throw InterpreterError(kind: .exception, message: "nope")
        }
        await #expect {
            try await interpreter.run(code: "return boom();", installing: [boom])
        } throws: { error in
            guard let interpreterError = error as? InterpreterError else { return false }
            return interpreterError.kind == .exception
                && interpreterError.message.contains("boom")
                && interpreterError.message.contains("nope")
        }
    }

    @Test("a sync result the bridge cannot convert to JSON surfaces the underlying conversion error")
    func syncResultConversionFailureSurfacesUnderlyingError() async throws {
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
        let weather = HostFunction(name: "getWeather") { _ in .object(["tempC": .number(31)]) }
        let result = try await interpreter.run(
            code: """
            JSON.parse = function () { return undefined; };
            try {
              getWeather();
              return "unreachable";
            } catch (e) {
              return e.message;
            }
            """,
            installing: [weather]
        )
        #expect(result.returnValue == .string("getWeather: JSON.parse is unavailable."))
    }

    @Test("a JS syntax error surfaces as InterpreterError")
    func syntaxErrorSurfacesAsInterpreterError() async throws {
        let interpreter = JSCInterpreter()
        await #expect {
            try await interpreter.run(code: "function( {{{", installing: [])
        } throws: { error in
            guard let interpreterError = error as? InterpreterError else { return false }
            return interpreterError.kind == .exception
        }
    }

    @Test("a host function returning a non-finite number round-trips as null")
    func hostFunctionNonFiniteReturnValueRoundTripsAsNull() async throws {
        let interpreter = JSCInterpreter()
        let makeNaN = HostFunction(name: "makeNaN") { _ in .number(.nan) }
        let result = try await interpreter.run(
            code: "return makeNaN() === null ? \"isNull\" : \"notNull\";",
            installing: [makeNaN]
        )
        #expect(result.returnValue == .string("isNull"))
    }

    @Test("a snippet passing Infinity as a host function argument round-trips as null")
    func hostFunctionNonFiniteArgumentRoundTripsAsNull() async throws {
        let interpreter = JSCInterpreter()
        let receivedBox = OSAllocatedUnfairLock<InterpreterValue?>(initialState: nil)
        let record = HostFunction(name: "record") { arguments in
            receivedBox.withLock { $0 = arguments.first }
            return .null
        }
        _ = try await interpreter.run(code: "record(Infinity);", installing: [record])
        #expect(receivedBox.withLock { $0 } == .null)
    }

    @Test("a snippet ending in a single-line comment before the injected wrapper still evaluates correctly")
    func trailingLineCommentBeforeWrapperIsHandled() async throws {
        let interpreter = JSCInterpreter()
        let result = try await interpreter.run(code: "return 1; // trailing comment", installing: [])
        #expect(result.returnValue == .number(1))
    }

    /// The sandbox has no clock, thus only the cancellation can end the loop,
    /// and the `CancellationError` is the outcome that proves it did. The
    /// cancel comes at an event — the loop started — and never after a real
    /// delay. The wait for the start also ends when the run ends, and the test
    /// then fails at once. A cancellation that the watchdog does not read
    /// makes the test hang. The test reads no real time (card `^3np5yzj`: no
    /// test checks the speed of the machine).
    @Test("cancelling the calling task forces early termination of an infinite loop")
    func cancellationForcesEarlyTerminationOfAnInfiniteLoop() async throws {
        let interpreter = JSCInterpreter()
        let loopStarted = TestGate()
        let started = HostFunction(name: "started") { _ in
            loopStarted.open()
            return .null
        }
        let run = try await EventRace.watch(
            { try await interpreter.run(code: "started(); while (true) {}", installing: [started]) },
            untilOpen: loopStarted, orFail: "the run ended before the loop started")
        run.task.cancel()

        await #expect(throws: CancellationError.self) { try await run.task.value }
    }

    @Test("concurrent run() calls from multiple tasks stay isolated")
    func concurrentRunsStayIsolated() async throws {
        let interpreter = JSCInterpreter()
        let count = 20

        let results = try await withThrowingTaskGroup(of: (Int, InterpreterValue).self) { group in
            for index in 0..<count {
                group.addTask {
                    let result = try await interpreter.run(code: "return \(index);", installing: [])
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
    func topLevelAwaitOfHostFunctionResult() async throws {
        let interpreter = JSCInterpreter()
        let weather = HostFunction(name: "getWeather") { _ in .object(["tempC": .number(31)]) }
        let result = try await interpreter.run(
            code: """
            const conditions = await getWeather();
            return conditions.tempC;
            """,
            installing: [weather]
        )
        #expect(result.returnValue == .number(31))
    }

    @Test("a snippet may await a genuine promise at the top level")
    func topLevelAwaitOfPromise() async throws {
        let interpreter = JSCInterpreter()
        let result = try await interpreter.run(
            code: "return await Promise.resolve(42);",
            installing: []
        )
        #expect(result.returnValue == .number(42))
    }

    @Test("an awaited rejection surfaces as InterpreterError with its message")
    func awaitedRejectionSurfacesAsInterpreterError() async throws {
        let interpreter = JSCInterpreter()
        await #expect {
            try await interpreter.run(
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
    func neverSettlingAwaitSurfacesAsInterpreterError() async throws {
        let interpreter = JSCInterpreter()
        await #expect {
            try await interpreter.run(
                code: "await new Promise(function() {});",
                installing: []
            )
        } throws: { error in
            guard let interpreterError = error as? InterpreterError else { return false }
            return interpreterError.kind == .exception
                && interpreterError.message.contains("never settled")
        }
    }

    // MARK: - Parse-only syntax check

    @Test("checkSyntax accepts a snippet that parses")
    func syntaxCheckAcceptsParseableSnippet() throws {
        let interpreter = JSCInterpreter()
        #expect(throws: Never.self) {
            try interpreter.checkSyntax(of: "const x = 1;\nreturn x + 1;")
        }
    }

    @Test("checkSyntax accepts a top-level await and a top-level return, exactly as run does")
    func syntaxCheckAcceptsTopLevelAwaitAndReturn() throws {
        let interpreter = JSCInterpreter()
        // Neither is legal at the true top level of a script — both are legal
        // only inside the async IIFE `run` wraps every snippet in, so this
        // passing is what proves the check parses the same wrapped source
        // `run` evaluates.
        #expect(throws: Never.self) {
            try interpreter.checkSyntax(of: "const w = await someCall();\nreturn w.field;")
        }
    }

    @Test("checkSyntax rejects a snippet that does not parse, reporting the engine's own message and line")
    func syntaxCheckRejectsUnparseableSnippet() throws {
        let interpreter = JSCInterpreter()
        #expect {
            try interpreter.checkSyntax(of: "const x = 1;\nreturn x +;")
        } throws: { error in
            guard let interpreterError = error as? InterpreterError else { return false }
            return interpreterError.kind == .exception
                && !interpreterError.message.isEmpty
                && interpreterError.line == 2
        }
    }

    @Test("checkSyntax executes nothing: an infinite loop parses instead of hitting the watchdog")
    func syntaxCheckExecutesNothing() throws {
        // `run` on this source ends only when its task is cancelled. Parsing
        // it throws nothing and returns, which is the observable difference
        // between checking and running: a check that ran the loop makes the
        // test hang. The outcome decides, and the test reads no real time
        // (card `^3np5yzj`).
        let interpreter = JSCInterpreter()
        #expect(throws: Never.self) {
            try interpreter.checkSyntax(of: "while (true) {}")
        }
    }

    @Test("checkSyntax installs nothing: a snippet naming an uninstalled global still parses")
    func syntaxCheckInstallsNothing() async throws {
        let interpreter = JSCInterpreter()
        // `tools` is never installed by `checkSyntax`, and an unresolved
        // identifier is a runtime failure rather than a parse failure — so
        // this parses, and would throw a `ReferenceError` under `run`.
        #expect(throws: Never.self) {
            try interpreter.checkSyntax(of: "return tools.whatever();")
        }
        await #expect(throws: InterpreterError.self) {
            try await interpreter.run(code: "return tools.whatever();", installing: [])
        }
    }

    // MARK: - Async host functions (the event loop)

    @Test("a snippet may await an async host function's result at the top level")
    func topLevelAwaitOfAsyncHostFunctionResult() async throws {
        let interpreter = JSCInterpreter()
        let hold = HeldCall()
        let weather = AsyncHostFunction(name: "getWeatherAsync") { _ in
            try await hold.pass()
            return .object(["tempC": .number(31)])
        }
        let result = try await Self.run(
            interpreter,
            code: """
            const conditions = await getWeatherAsync();
            return conditions.tempC;
            """,
            installingAsync: [weather],
            releasing: hold
        )
        #expect(result.returnValue == .number(31))
    }

    @Test("the sandbox stays alive across multiple sequential async host-function awaits")
    func sandboxSurvivesMultipleSequentialAwaits() async throws {
        let interpreter = JSCInterpreter()
        let hold = HeldCall()
        let increment = AsyncHostFunction(name: "incrementAsync") { arguments in
            guard case .number(let value) = arguments.first else {
                throw InterpreterError(kind: .exception, message: "expected a number argument")
            }
            try await hold.pass()
            return .number(value + 1)
        }
        let result = try await Self.run(
            interpreter,
            code: """
            let total = 0;
            total = await incrementAsync(total);
            total = await incrementAsync(total);
            total = await incrementAsync(total);
            return total;
            """,
            installingAsync: [increment],
            releasing: hold
        )
        #expect(result.returnValue == .number(3))
    }

    /// Each call waits at one ``Rendezvous`` until the other call has
    /// arrived. A bridge that ran them one after another leaves the first call
    /// waiting for a call that cannot start, and the test hangs. Thus the run
    /// returns "done" only when both calls ran at the same time, and the test
    /// reads no real time (card `^kdtrmhv`: no test checks the speed of the
    /// machine).
    @Test("Promise.all over two async host functions runs them concurrently")
    func promiseAllRunsAsyncHostFunctionsConcurrently() async throws {
        let interpreter = JSCInterpreter()
        let rendezvous = Rendezvous(partySize: Self.concurrentCallCount)
        func makeMeeting(name: String) -> AsyncHostFunction {
            AsyncHostFunction(name: name) { _ in
                await rendezvous.arrive()
                return .null
            }
        }
        let result = try await interpreter.run(
            code: """
            await Promise.all([slowA(), slowB()]);
            return "done";
            """,
            installing: [],
            installingAsync: [makeMeeting(name: "slowA"), makeMeeting(name: "slowB")]
        )
        #expect(result.returnValue == .string("done"))
    }

    /// How many async host functions the `Promise.all` snippet starts
    /// together.
    private static let concurrentCallCount = 2

    /// The floating call waits until the snippet has reached its `return`.
    /// The snippet tells this with the synchronous `reachedReturn()` call
    /// just before the `return`. Thus the call cannot end before the snippet
    /// returns, and the run must wait for it. The order comes from events and
    /// never from a real delay.
    @Test("a floating async host-function call completes before the run returns")
    func floatingAsyncCallSettlesBeforeReturn() async throws {
        let interpreter = JSCInterpreter()
        let completed = OSAllocatedUnfairLock(initialState: false)
        let returnReached = TestGate()
        let reachedReturn = HostFunction(name: "reachedReturn") { _ in
            returnReached.open()
            return .null
        }
        let write = AsyncHostFunction(name: "writeAsync") { _ in
            try await returnReached.wait()
            completed.withLock { $0 = true }
            return .null
        }
        let result = try await interpreter.run(
            code: """
            writeAsync();
            reachedReturn();
            return "done";
            """,
            installing: [reachedReturn],
            installingAsync: [write]
        )
        #expect(result.returnValue == .string("done"))
        #expect(completed.withLock { $0 })
    }

    @Test("a floating async host-function rejection fails the run")
    func floatingAsyncRejectionFailsRun() async throws {
        let interpreter = JSCInterpreter()
        let hold = HeldCall()
        let boom = AsyncHostFunction(name: "boomAsync") { _ in
            try await hold.pass()
            throw InterpreterError(kind: .exception, message: "nope")
        }
        await #expect {
            try await Self.run(
                interpreter,
                code: """
                boomAsync();
                return "done";
                """,
                installingAsync: [boom],
                releasing: hold
            )
        } throws: { error in
            guard let interpreterError = error as? InterpreterError else { return false }
            return interpreterError.kind == .exception
                && interpreterError.message.contains("boomAsync")
                && interpreterError.message.contains("nope")
        }
    }

    @Test("an awaited async host-function rejection that is caught does not fail the run")
    func caughtAsyncRejectionDoesNotFailRun() async throws {
        let interpreter = JSCInterpreter()
        let hold = HeldCall()
        let boom = AsyncHostFunction(name: "boomAsync") { _ in
            try await hold.pass()
            throw InterpreterError(kind: .exception, message: "nope")
        }
        let result = try await Self.run(
            interpreter,
            code: """
            try {
              await boomAsync();
              return "unreachable";
            } catch (e) {
              return "caught";
            }
            """,
            installingAsync: [boom],
            releasing: hold
        )
        #expect(result.returnValue == .string("caught"))
    }

    @Test("a rejection that settles while a different sibling call is still pending is still caught, not reported as floating")
    func delayedSequentialAwaitOfEarlierSettledRejectionIsStillCaught() async throws {
        // Regression: the bridge used to decide "floating" per individual
        // settlement, which fires too early here — `fast` rejects and
        // settles while the snippet is still suspended on `await slow()`,
        // well before the snippet's own code even reaches `await fast()`.
        // Floating-rejection detection must only be decided once, after the
        // whole registry has drained.
        //
        // The order is fixed by gates and never by a real delay. The fast
        // call rejects before the test opens the slow call: `slow` waits on
        // `slowGate`, and the test opens it only after `fast` has ended. The
        // wait for the end of `fast` also ends when the run ends, and the test
        // then fails at once.
        let interpreter = JSCInterpreter()
        let slowGate = TestGate()
        let fastEnded = TestGate()
        let slow = AsyncHostFunction(name: "slow") { _ in
            try await slowGate.wait()
            return .string("slow-done")
        }
        let fast = AsyncHostFunction(name: "fast") { _ in
            defer { fastEnded.open() }
            throw InterpreterError(kind: .exception, message: "fast-boom")
        }
        // On each path the slow call goes on, thus the run can end.
        defer { slowGate.open() }
        let running = try await EventRace.watch(
            {
                try await interpreter.run(
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
            },
            untilOpen: fastEnded, orFail: "the run ended before the fast call ended")
        slowGate.open()
        let result = try await running.task.value
        #expect(result.returnValue == .string("caught"))
    }

    @Test("a snippet's own floating rejection, unrelated to any async host function, does not fail the run")
    func snippetOwnFloatingRejectionIsOutOfScope() async throws {
        // Floating-rejection detection is scoped to promises the async
        // host-function bridge itself creates (eventplan.md: "each promise
        // it creates") — a snippet's own `Promise.reject(...)`, with no
        // async host functions installed at all, is untouched by it.
        let interpreter = JSCInterpreter()
        let result = try await interpreter.run(
            code: """
            Promise.reject(new Error("snippet-made"));
            return "ok";
            """,
            installing: []
        )
        #expect(result.returnValue == .string("ok"))
    }

    @Test("an async host function's unawaited RETURNED promise settles at the run's boundary")
    func unawaitedReturnedPromiseSettlesAtBoundary() async throws {
        let interpreter = JSCInterpreter()
        let hold = HeldCall()
        let weather = AsyncHostFunction(name: "getWeatherAsync") { _ in
            try await hold.pass()
            return .object(["tempC": .number(31)])
        }
        let result = try await Self.run(
            interpreter,
            code: "return getWeatherAsync();",
            installingAsync: [weather],
            releasing: hold
        )
        #expect(result.returnValue == .object(["tempC": .number(31)]))
    }

    @Test("an async result the bridge cannot convert to JSON rejects with the underlying conversion error")
    func asyncResultConversionFailureRejectsWithUnderlyingError() async throws {
        // `settle(_:with:in:recordingFailuresTo:)`'s success branch used to
        // reject with a fixed "could not convert the result to JSON." string,
        // discarding the real error and diverging from the sync bridge's
        // `"<name>: <error>"` shape. Reaching that branch takes a snippet
        // that breaks the sandbox's own `JSON.parse` — the mechanism
        // `jsValue(from:in:)` converts through — after the call has started
        // but before its settle job runs. The stub returns `undefined`
        // rather than throwing: a throwing stub would additionally notify a
        // TypeError into the context, which the run reports ahead of the
        // rejection, hiding the message under test.
        let interpreter = JSCInterpreter()
        let hold = HeldCall()
        let weather = AsyncHostFunction(name: "getWeatherAsync") { _ in
            try await hold.pass()
            return .object(["tempC": .number(31)])
        }
        let result = try await Self.run(
            interpreter,
            code: """
            const pending = getWeatherAsync();
            JSON.parse = function () { return undefined; };
            try {
              await pending;
              return "unreachable";
            } catch (e) {
              return e.message;
            }
            """,
            installingAsync: [weather],
            releasing: hold
        )
        #expect(result.returnValue == .string("getWeatherAsync: JSON.parse is unavailable."))
    }

    @Test("a bridge call's returned value supports .catch(...), not just await/.then")
    func bridgeReturnValueSupportsCatch() async throws {
        let interpreter = JSCInterpreter()
        let hold = HeldCall()
        let boom = AsyncHostFunction(name: "boomAsync") { _ in
            try await hold.pass()
            throw InterpreterError(kind: .exception, message: "nope")
        }
        let result = try await Self.run(
            interpreter,
            code: """
            return boomAsync().catch(function(e) { return "caught:" + e; });
            """,
            installingAsync: [boom],
            releasing: hold
        )
        let value = try #require(result.returnValue.stringText, "expected a string return value")
        #expect(value.hasPrefix("caught:"))
    }

    @Test("a .then(onFulfilled) with no rejection handler still fails the run on rejection")
    func thenWithNoRejectionHandlerStillFailsRun() async throws {
        // Consumption means the rejection was genuinely handled, not merely
        // that `.then` was called: `.then(onFulfilled)` alone supplies no
        // `onRejected`, so a `boomAsync()` rejection here is exactly as
        // unaddressed as `boomAsync(); return "done";` — it must still fail
        // the run, not disappear into the untracked derived promise
        // `.then(onFulfilled)` creates.
        let interpreter = JSCInterpreter()
        let hold = HeldCall()
        let boom = AsyncHostFunction(name: "boomAsync") { _ in
            try await hold.pass()
            throw InterpreterError(kind: .exception, message: "nope")
        }
        await #expect {
            try await Self.run(
                interpreter,
                code: """
                boomAsync().then(function(v) { return v; });
                return "done";
                """,
                installingAsync: [boom],
                releasing: hold
            )
        } throws: { error in
            guard let interpreterError = error as? InterpreterError else { return false }
            return interpreterError.kind == .exception
                && interpreterError.message.contains("boomAsync")
                && interpreterError.message.contains("nope")
        }
    }

    @Test("a .then(undefined, nonFunction) with a non-callable rejection handler still fails the run on rejection")
    func thenWithNonCallableRejectionHandlerStillFailsRun() async throws {
        // A non-undefined/non-null second argument to `.then` is not on its
        // own proof of a genuine rejection handler — `.then(undefined,
        // false)` supplies a value that cannot run as `onRejected`, so the
        // real `Promise.prototype.then` treats it exactly like `undefined`
        // (per spec, a non-callable `onRejected` is replaced with a default
        // handler that rethrows). The rejection must still be reported as
        // floating, not swallowed as "handled" merely because a second
        // argument happened to be present.
        let interpreter = JSCInterpreter()
        let hold = HeldCall()
        let boom = AsyncHostFunction(name: "boomAsync") { _ in
            try await hold.pass()
            throw InterpreterError(kind: .exception, message: "nope")
        }
        await #expect {
            try await Self.run(
                interpreter,
                code: """
                boomAsync().then(undefined, false);
                return "done";
                """,
                installingAsync: [boom],
                releasing: hold
            )
        } throws: { error in
            guard let interpreterError = error as? InterpreterError else { return false }
            return interpreterError.kind == .exception
                && interpreterError.message.contains("boomAsync")
                && interpreterError.message.contains("nope")
        }
    }

    @Test("a .then(undefined, objectInstanceofFunction) with a merely-instanceof-Function, non-callable handler still fails the run")
    func thenWithInstanceOfFunctionButNonCallableHandlerStillFailsRun() async throws {
        // `instanceof Function` is neither necessary nor sufficient for
        // callability: `Object.create(Function.prototype)` passes
        // `instanceof Function` (it inherits from `Function.prototype`) yet
        // has no internal `[[Call]]` — `typeof` reports `"object"`, and the
        // real `Promise.prototype.then` cannot invoke it as `onRejected`.
        // Marking this "handled" would be exactly the false positive the
        // original finding named, just with a different witness value than
        // `.then(undefined, false)`.
        let interpreter = JSCInterpreter()
        let hold = HeldCall()
        let boom = AsyncHostFunction(name: "boomAsync") { _ in
            try await hold.pass()
            throw InterpreterError(kind: .exception, message: "nope")
        }
        await #expect {
            try await Self.run(
                interpreter,
                code: """
                boomAsync().then(undefined, Object.create(Function.prototype));
                return "done";
                """,
                installingAsync: [boom],
                releasing: hold
            )
        } throws: { error in
            guard let interpreterError = error as? InterpreterError else { return false }
            return interpreterError.kind == .exception
                && interpreterError.message.contains("boomAsync")
                && interpreterError.message.contains("nope")
        }
    }

    @Test("a .then(undefined, callableButNotInstanceofFunction) handler is still recognized as genuinely handling the rejection")
    func thenWithCallableButNotInstanceOfFunctionHandlerDoesNotFailRun() async throws {
        // `Function.prototype` is itself callable (`typeof
        // Function.prototype === "function"`, a real no-op function) but is
        // NOT `instanceof Function` (its own prototype is
        // `Object.prototype`, not `Function.prototype`). A rejection
        // handler this permissive but genuinely callable must still count
        // as handled — the other direction of the same false test the
        // previous case guards.
        let interpreter = JSCInterpreter()
        let hold = HeldCall()
        let boom = AsyncHostFunction(name: "boomAsync") { _ in
            try await hold.pass()
            throw InterpreterError(kind: .exception, message: "nope")
        }
        let result = try await Self.run(
            interpreter,
            code: """
            boomAsync().then(undefined, Function.prototype);
            return "done";
            """,
            installingAsync: [boom],
            releasing: hold
        )
        #expect(result.returnValue == .string("done"))
    }

    @Test("a bridge call's returned value supports .finally(...) and is instanceof Promise")
    func bridgeReturnValueSupportsFinallyAndIsPromise() async throws {
        let interpreter = JSCInterpreter()
        let hold = HeldCall()
        let weather = AsyncHostFunction(name: "getWeatherAsync") { _ in
            try await hold.pass()
            return .number(31)
        }
        let result = try await Self.run(
            interpreter,
            code: """
            let ranFinally = false;
            const value = await getWeatherAsync().finally(function() { ranFinally = true; });
            return { value: value, ranFinally: ranFinally, isPromise: getWeatherAsync() instanceof Promise };
            """,
            installingAsync: [weather],
            releasing: hold
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
    func asyncHostFunctionDoesNotLeakTheSandbox() async throws {
        // Regression: an earlier version of the promise bridge captured the
        // internal `JSValue` promise directly inside a native function
        // installed into that same `JSContext` — a retain cycle (the
        // context's heap holds the function, the function holds the
        // `JSValue`, the `JSValue` holds its `JSContext`) that kept the
        // whole sandbox alive forever. `run` does not return until every
        // bridge promise settles, so by the time it returns, the sandbox —
        // and everything it retained, including the async host function's
        // own closure — must have been torn down.
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
        try await Self.runTouching(canary)
        canary = nil
        #expect(weakCanary == nil)
    }

    /// Runs one snippet whose only async host function captures `canary`,
    /// for ``asyncHostFunctionDoesNotLeakTheSandbox()``.
    ///
    /// A function of its own, so the interpreter and the host function are
    /// locals that end when it returns, and only the sandbox could still
    /// hold the closure.
    ///
    /// - Parameter canary: the object the host function captures.
    private static func runTouching(_ canary: (some AnyObject & Sendable)?) async throws {
        let interpreter = JSCInterpreter()
        let touch = AsyncHostFunction(name: "touchAsync") { [canary] _ in
            _ = canary
            return .null
        }
        _ = try await interpreter.run(
            code: "touchAsync(); return \"done\";",
            installing: [],
            installingAsync: [touch]
        )
    }

    // MARK: - Proxy trap on pending results

    @Test("accessing a property other than then/catch/finally on a pending async host-function result throws a precise, model-repairable error naming the call and the property")
    func propertyAccessOnPendingResultThrowsForgotAwaitError() async throws {
        let interpreter = JSCInterpreter()
        let hold = HeldCall()
        let call = AsyncHostFunction(name: "tools.x.y") { _ in
            try await hold.pass()
            return .object(["value": .number(1)])
        }
        await #expect {
            try await Self.run(
                interpreter,
                code: """
                const r = globalThis["tools.x.y"]();
                return r.value;
                """,
                installingAsync: [call],
                releasing: hold
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
    func arithmeticCoercionOfPendingResultThrowsForgotAwaitError() async throws {
        // eventplan.md frames "truthiness/arithmetic on a promise" as one
        // uncaught shape, but only bare truthiness genuinely evades this
        // trap (`ToBoolean` on an object never looks up a property).
        // Arithmetic reaches `ToPrimitive`, which does `Get`s for
        // `@@toPrimitive`/`valueOf`/`toString` — none of them exempted here
        // — so this is caught too, incidentally. Regression coverage for
        // `describeNonExemptProperty`, which must render the `Symbol`
        // property key `@@toPrimitive` names without itself crashing.
        let interpreter = JSCInterpreter()
        let hold = HeldCall()
        let call = AsyncHostFunction(name: "tools.x.y") { _ in
            try await hold.pass()
            return .number(1)
        }
        await #expect {
            try await Self.run(
                interpreter,
                code: """
                const r = globalThis["tools.x.y"]();
                return r + 1;
                """,
                installingAsync: [call],
                releasing: hold
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
    func consoleLogOnPendingResultThrowsForgotAwaitErrorInsteadOfCrashing() async throws {
        // Regression: `console.log(r)` coerces `r` via the same
        // `ToPrimitive`/`@@toPrimitive` path as arithmetic, which trips this
        // trap — and `installConsole`'s own argument-to-string conversion
        // used to force-unwrap `JSValue.toString()`'s result, which is
        // `nil` (not itself throwing) exactly when that coercion fails,
        // crashing the whole host process instead of surfacing the trap's
        // repairable error. Confirmed against JSC directly while
        // implementing this fix.
        let interpreter = JSCInterpreter()
        let hold = HeldCall()
        let call = AsyncHostFunction(name: "tools.x.y") { _ in
            try await hold.pass()
            return .number(1)
        }
        await #expect {
            try await Self.run(
                interpreter,
                code: """
                const r = globalThis["tools.x.y"]();
                console.log(r);
                return "unreachable";
                """,
                installingAsync: [call],
                releasing: hold
            )
        } throws: { error in
            guard let interpreterError = error as? InterpreterError else { return false }
            return interpreterError.kind == .exception
                && interpreterError.message.contains("tools.x.y")
                && interpreterError.message.contains("did you forget")
        }
    }

    @Test("then, catch, and finally are exempt from the pending-result proxy trap")
    func thenCatchFinallyAreExemptFromTheProxyTrap() async throws {
        let interpreter = JSCInterpreter()
        let hold = HeldCall()
        let call = AsyncHostFunction(name: "tools.x.y") { _ in
            try await hold.pass()
            return .number(1)
        }
        let result = try await Self.run(
            interpreter,
            code: """
            const r = globalThis["tools.x.y"]();
            const hasThen = typeof r.then === "function";
            const hasCatch = typeof r.catch === "function";
            const hasFinally = typeof r.finally === "function";
            await r;
            return { hasThen: hasThen, hasCatch: hasCatch, hasFinally: hasFinally };
            """,
            installingAsync: [call],
            releasing: hold
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
    func proxiedRejectionIsStillCatchable() async throws {
        let interpreter = JSCInterpreter()
        let hold = HeldCall()
        let boom = AsyncHostFunction(name: "tools.boom") { _ in
            try await hold.pass()
            throw InterpreterError(kind: .exception, message: "nope")
        }
        let result = try await Self.run(
            interpreter,
            code: """
            return globalThis["tools.boom"]().catch(function(e) { return "caught:" + e; });
            """,
            installingAsync: [boom],
            releasing: hold
        )
        let value = try #require(result.returnValue.stringText, "expected a string return value")
        #expect(value.hasPrefix("caught:"))
    }

    @Test("Promise.all resolves both values through the proxy wrapping each pending result")
    func promiseAllResolvesBothProxiedResults() async throws {
        let interpreter = JSCInterpreter()
        // The two calls share one hold: the first call that arrives releases
        // it, and then each call passes at once.
        let hold = HeldCall()
        let a = AsyncHostFunction(name: "tools.a") { _ in
            try await hold.pass()
            return .number(1)
        }
        let b = AsyncHostFunction(name: "tools.b") { _ in
            try await hold.pass()
            return .number(2)
        }
        let result = try await Self.run(
            interpreter,
            code: """
            const values = await Promise.all([globalThis["tools.a"](), globalThis["tools.b"]()]);
            return values[0] + values[1];
            """,
            installingAsync: [a, b],
            releasing: hold
        )
        #expect(result.returnValue == .number(3))
    }

    @Test("the forgot-await proxy trap error renders through ResultRenderer with the standard repair instruction")
    func pendingResultPropertyAccessErrorRendersWithRepairInstruction() async throws {
        let interpreter = JSCInterpreter()
        let hold = HeldCall()
        let call = AsyncHostFunction(name: "tools.x.y") { _ in
            try await hold.pass()
            return .object(["value": .number(1)])
        }
        do {
            _ = try await Self.run(
                interpreter,
                code: """
                const r = globalThis["tools.x.y"]();
                return r.value;
                """,
                installingAsync: [call],
                releasing: hold
            )
            Issue.record("expected the run to throw")
        } catch let interpreterError as InterpreterError {
            let rendered = ResultRenderer.render(interpreterError)
            #expect(rendered.contains("tools.x.y"))
            #expect(rendered.contains("value"))
            #expect(rendered.contains("await"))
            // `hasSuffix`, not `contains`: the directive is the last thing the
            // model reads, so where it sits in the rendered error is part of
            // what this asserts: `hasSuffix` pins that nothing follows the
            // directive, which `contains` would not. This call site passes no
            // hint, so it says nothing about where a hint would land.
            // Only the text is read off the directive instead of restated.
            #expect(rendered.hasSuffix(RepairDirective.repairSnippet.closingLine))
        }
    }

    // MARK: - Cancellation

    /// The pending call waits on a gate that the test never opens, and the
    /// sandbox has no clock, thus only the cancel can end the run, and the
    /// `CancellationError` is the outcome that proves it did. The cancel comes
    /// at an event (the pending call started) and never after a real delay,
    /// and the test waits for the cancelled call's own event and never for a
    /// fixed time (card `^kdtrmhv`: no test checks the speed of the machine).
    @Test("cancelling the calling task mid-await cancels a pending async host function")
    func cancellationCancelsPendingAsyncHostFunction() async throws {
        let interpreter = JSCInterpreter()
        let callStarted = TestGate()
        let taskWasCancelled = TestGate()
        let neverOpened = TestGate()
        let slow = AsyncHostFunction(name: "slowAsync") { _ in
            callStarted.open()
            do {
                try await neverOpened.wait()
            } catch {
                taskWasCancelled.open()
                throw error
            }
            return .null
        }
        let run = try await EventRace.watch(
            {
                try await interpreter.run(
                    code: "await slowAsync(); return \"done\";",
                    installing: [],
                    installingAsync: [slow]
                )
            },
            untilOpen: callStarted, orFail: "the run ended before the pending call started")
        run.task.cancel()

        await #expect(throws: CancellationError.self) { try await run.task.value }
        // The cancelled backing Task observes its own cancellation after the
        // run ended: wait for that event.
        try await taskWasCancelled.wait()
    }

    /// The snippet the cancellation pin and both of its controls run
    /// unchanged: it witnesses that it entered the `try` block, that an
    /// author-written `.catch()` was attached to the pending call, that that
    /// `.catch()` ran, and that an author-written `finally {}` ran.
    ///
    /// The `attached` marker is what makes the pin's `.catch()` half a
    /// construction rather than a timing margin. Entering the `try` already
    /// arms `finally`, so `entered` on its own closes that arm — but a run
    /// terminated between `entered` and the `.catch()` call would leave the
    /// handler unattached and still produce the pin's markers, its
    /// `CancellationError`, and its short duration. Binding the promise,
    /// recording `attached` immediately after the handler is installed on it,
    /// and awaiting the bound promise afterwards makes that false pass
    /// unmatchable: the marker cannot land unless the handler is already live
    /// on a call that has not settled.
    ///
    /// Shared verbatim so the pin's negative claim and the controls' positive
    /// ones are made about one piece of code rather than three that could
    /// drift apart.
    private static let cleanupWitnessSnippet = """
        try {
            record("entered");
            const pending = slowAsync().catch(() => { record("catch"); });
            record("attached");
            await pending;
            record("afterAwait");
        } finally {
            record("finally");
        }
        return "done";
        """

    /// Builds the `record(marker)` global ``cleanupWitnessSnippet`` calls.
    ///
    /// Deliberately a synchronous `HostFunction` rather than an
    /// `AsyncHostFunction`: it runs inline in the job that calls it, so a
    /// marker lands before `run` returns and a cancelled run cannot drop it
    /// for the wrong reason.
    ///
    /// - Parameters:
    ///   - markers: the recorded markers, appended to in call order.
    ///   - attached: the gate that the recorder opens when it records the
    ///     marker `attached`, after it appended the marker. A test that must
    ///     know when the author's handler is attached waits on this gate. The
    ///     default is a gate that no one waits on.
    /// - Returns: the host function to install as `record`.
    private static func makeRecorder(
        into markers: OSAllocatedUnfairLock<[InterpreterValue]>,
        attached: TestGate = TestGate()
    ) -> HostFunction {
        HostFunction(name: "record") { arguments in
            markers.withLock { $0.append(arguments.first ?? .null) }
            if arguments.first == .string("attached") {
                attached.open()
            }
            return .null
        }
    }

    @Test("cancelling a snippet that waits on a pending call runs none of its author-written .catch() or finally {}")
    func cancellationSkipsAuthorCatchAndFinally() async throws {
        // Pins the ruled cancellation contract (eventplan.md "Async
        // JavaScript"): `cancel` is terminate-without-settling, NOT
        // reject-and-unwind. `PromiseRegistry.cancelAllPending` cancels each
        // backing Swift Task and drops the entry without calling
        // `resolve`/`reject`, so the suspended continuation never resumes and
        // no author cleanup code runs. That is deliberate — settling would
        // resume author JS in a run that is ending, which would make a
        // cancelled snippet's `finally { while (true) {} }` unkillable.
        //
        // An `AsyncHostFunction` is what a `tools.*` call is at this layer, so
        // this pins the same path `cancel(completionToken)` drives. The
        // witness is `record` (see `makeRecorder(into:attached:)`), and the
        // snippet is the one both controls below run unchanged.
        //
        // The cancel lands on an event, and never after a real delay: the
        // pending call waits on the gate that `record` opens when it records
        // `attached`, and only then reports that it started. Then it waits on
        // a gate that the test never opens. The test cancels, and waits for
        // the cancelled call's own event, and never for a fixed time (card
        // `^kdtrmhv`: no test checks the speed of the machine). The sandbox
        // has no clock, thus only the cancel can end the run.
        let interpreter = JSCInterpreter()
        let markers = OSAllocatedUnfairLock<[InterpreterValue]>(initialState: [])
        let attached = TestGate()
        let pendingCallStarted = TestGate()
        let pendingCallEnded = TestGate()
        let neverOpened = TestGate()
        let slow = AsyncHostFunction(name: "slowAsync") { _ in
            defer { pendingCallEnded.open() }
            try await attached.wait()
            pendingCallStarted.open()
            try await neverOpened.wait()
            return .null
        }
        let run = try await EventRace.watch(
            {
                try await interpreter.run(
                    code: Self.cleanupWitnessSnippet,
                    installing: [Self.makeRecorder(into: markers, attached: attached)],
                    installingAsync: [slow]
                )
            },
            untilOpen: pendingCallStarted, orFail: "the run ended before the pending call started")
        run.task.cancel()

        await #expect(throws: CancellationError.self) { try await run.task.value }
        // The cancelled backing Task unwinds after the run ended, and its
        // late completion reaches the job queue of the run. Waiting for that
        // unwind gives a late resumption of the suspended continuation its
        // chance to land a marker before the markers are read.
        try await pendingCallEnded.wait()
        // `entered` and `attached`, and nothing after them. `entered` witnesses
        // that the snippet really did start; `attached` witnesses that the
        // author's `.catch()` was installed on the pending call before the
        // cancel landed. So the absence of `catch` and `finally` is cleanup
        // that was skipped, not a snippet the cancel beat to the `try` block or
        // to the handler's installation.
        #expect(markers.withLock { $0 } == [.string("entered"), .string("attached")])
    }

    @Test("an uncancelled snippet does run its author-written finally {} after a pending call settles")
    func uncancelledSnippetRunsAuthorFinally() async throws {
        // The positive control for the `finally` half of
        // `cancellationSkipsAuthorCatchAndFinally`. Same snippet, same witness,
        // no cancellation — so the markers land. Without it, the pin's
        // assertion would still hold if the `record` host function or the async
        // IIFE's `finally` handling broke outright, and the pin would pass
        // while pinning nothing.
        let interpreter = JSCInterpreter()
        let markers = OSAllocatedUnfairLock<[InterpreterValue]>(initialState: [])
        let hold = HeldCall()
        let quick = AsyncHostFunction(name: "slowAsync") { _ in
            try await hold.pass()
            return .null
        }
        let result = try await Self.run(
            interpreter,
            code: Self.cleanupWitnessSnippet,
            installing: [Self.makeRecorder(into: markers)],
            installingAsync: [quick],
            releasing: hold
        )
        #expect(result.returnValue == .string("done"))
        #expect(
            markers.withLock { $0 } == [
                .string("entered"), .string("attached"), .string("afterAwait"), .string("finally"),
            ]
        )
    }

    @Test("an uncancelled snippet does run its author-written .catch() when a pending call rejects")
    func uncancelledSnippetRunsAuthorCatch() async throws {
        // The positive control for the `.catch()` half of the same pin. The
        // `finally` control above installs a `slowAsync` that resolves, so it
        // never reaches the `.catch()` arm: on its own it would leave the pin
        // asserting the absence of a marker nothing had shown could appear at
        // all. Here the pending call rejects, so an uncancelled run must record
        // `catch` — and the rejection is handled, so the run still completes
        // through `afterAwait` and `finally`.
        let interpreter = JSCInterpreter()
        let markers = OSAllocatedUnfairLock<[InterpreterValue]>(initialState: [])
        let hold = HeldCall()
        let rejecting = AsyncHostFunction(name: "slowAsync") { _ in
            try await hold.pass()
            throw InterpreterError(kind: .exception, message: "nope")
        }
        let result = try await Self.run(
            interpreter,
            code: Self.cleanupWitnessSnippet,
            installing: [Self.makeRecorder(into: markers)],
            installingAsync: [rejecting],
            releasing: hold
        )
        #expect(result.returnValue == .string("done"))
        #expect(
            markers.withLock { $0 } == [
                .string("entered"), .string("attached"), .string("catch"), .string("afterAwait"),
                .string("finally"),
            ]
        )
    }
}
