import Testing

@testable import FoundationModelsMultitool

/// Coverage for `CallTrace` — the signposted call-boundary tracer this package
/// wraps its suspendable entry points in.
///
/// What is asserted here is **transparency**, which is the whole contract a
/// tracer owes the calls it wraps: a traced call returns exactly what the
/// untraced one returned, and fails exactly the way the untraced one failed.
/// Every span in this package sits on a production path, so a tracer that
/// swallowed an error or altered a value would be a defect in the product
/// rather than in its diagnostics.
///
/// Nothing here reads the unified log back. `os` publishes into the system log
/// store and offers no supported in-process read-back, and a test that scraped
/// `log show` would pin diagnostic wording rather than the property that
/// matters — and would need a live log daemon to run at all.
@Suite("CallTrace")
struct CallTraceTests {
    /// The error a failing traced body throws, so a test can prove that the
    /// very same error — not merely *an* error — came back out.
    private struct TracedFailure: Error, Equatable {
        /// Which span threw, so a wrong error cannot pass by accident.
        let marker: String
    }

    /// The tracer under test. Its own category, so these spans never mix into
    /// a real area's stream when the suite runs on a machine that is watching
    /// one.
    private let trace = CallTrace(category: "CallTraceTests")

    // MARK: - An asynchronous span is transparent

    // Every body below suspends, and that is what puts the asynchronous
    // overload under test. `span` is overloaded on `async` alone, and a
    // non-suspending body is an exact match for the synchronous overload — so
    // a body that merely sat inside an `async` test would silently measure the
    // other one, and leave the overload that wraps every real model call
    // uncovered.

    @Test("an asynchronous span hands back exactly what its body returned")
    func asynchronousSpanReturnsTheBodysValue() async {
        let returned = await trace.span("test.asynchronousReturn", detail: "returns") {
            await Task.yield()
            return "the body's own value"
        }

        #expect(returned == "the body's own value")
    }

    @Test("an asynchronous span rethrows its body's error unchanged")
    func asynchronousSpanRethrowsTheBodysError() async {
        await #expect(throws: TracedFailure(marker: "asynchronous")) {
            try await trace.span("test.asynchronousThrow", detail: "throws") { () async throws -> String in
                await Task.yield()
                throw TracedFailure(marker: "asynchronous")
            }
        }
    }

    // MARK: - A synchronous span is transparent

    @Test("a synchronous span hands back exactly what its body returned")
    func synchronousSpanReturnsTheBodysValue() {
        let returned = trace.span("test.synchronousReturn", detail: "returns") {
            "the body's own value"
        }

        #expect(returned == "the body's own value")
    }

    @Test("a synchronous span rethrows its body's error unchanged")
    func synchronousSpanRethrowsTheBodysError() {
        #expect(throws: TracedFailure(marker: "synchronous")) {
            try trace.span("test.synchronousThrow", detail: "throws") { () throws -> String in
                throw TracedFailure(marker: "synchronous")
            }
        }
    }

    // MARK: - Every span reads one absence the same way

    @Test("the absent-field spelling is a single non-empty word, so a stream never shows a blank field")
    func absentFieldHasOneSpelling() {
        // A detail field a call did not carry is printed rather than omitted:
        // an omitted field reads as a truncated line, and a reader tracing a
        // hang cannot tell a missing field from a missing log line.
        #expect(!CallTrace.absent.isEmpty)
        #expect(!CallTrace.absent.contains(" "))
    }
}
