import Foundation
import FoundationModels
import os

// MARK: - M4a `MultiTool` execution fixtures (plan.md § "MultiTool" / M4a)
//
// Small mock tools that exercise `MultiTool`'s `runCode` execution path end
// to end: composing two tools in one snippet, grouped-namespace dispatch,
// the async promise-pump bridge (eventplan.md "Async JavaScript"), and a
// mis-called tool's repairable-error path. Outputs are wrapped in small
// `@Generable` structs
// (rather than a bare `Double`/`Int`/`[String]`) except where a bare `String`
// Output is already proven safe by `ArgumentMarshalerTests
// .plainStringOutputRendersAsString` — the same conservative posture this
// package takes elsewhere toward unverified SDK shapes.

/// Arguments for a tool that takes nothing meaningful — an unused optional
/// field, since every `Tool.Arguments` must be an `object` schema (a
/// zero-property struct is untested territory this fixture avoids).
@Generable
struct NoArguments {
    @Guide(description: "unused.")
    var unused: String?
}

/// The `Output` of `CitiesTool` — a fixed trip itinerary.
@Generable
struct CitiesOutput {
    var cities: [String]
}

/// A standalone, no-argument tool returning a fixed list of city codes.
/// Paired with `TempTool` below so a snippet can `map` over its result and
/// call the other tool per element — the "compose two tools, only the final
/// value comes back" acceptance criterion.
struct CitiesTool: Tool {
    let name = "getCities"
    let description = "The cities on the trip."

    func call(arguments: NoArguments) async throws -> CitiesOutput {
        CitiesOutput(cities: ["AAA", "BBB", "CCC"])
    }
}

/// `TempTool`'s arguments — one required `city`, so calling it with no
/// `city` (the mis-called-tool test) fails validation before `call` ever
/// runs.
@Generable
struct TempArguments {
    @Guide(description: "IATA city code.")
    var city: String
}

/// The `Output` of `TempTool`.
@Generable
struct TempOutput {
    var tempC: Double
}

/// Fixed, distinct per-city temperatures — distinct enough that a test can
/// assert the composed snippet's rendered result contains only the final
/// (maximum) value, never an intermediate city code or temperature.
private let fixtureTemperatures: [String: Double] = ["AAA": 11, "BBB": 22, "CCC": 33]

/// Per-city temperature lookup.
struct TempTool: Tool {
    let name = "getTemperature"
    let description = "Current temperature (Celsius) for a city."

    func call(arguments: TempArguments) async throws -> TempOutput {
        TempOutput(tempC: fixtureTemperatures[arguments.city] ?? 0)
    }
}

// MARK: - Grouped-namespace dispatch fixture

/// Arguments for `IssueCountTool` — one required `repo`.
@Generable
struct RepoArguments {
    @Guide(description: "the repository name.")
    var repo: String
}

/// The `Output` of `IssueCountTool`.
@Generable
struct IssueCountOutput {
    var count: Int
}

/// A group fixture tool — added via `addGroup(named: "github", …)`, so a
/// snippet dispatches it as `tools.github.getIssueCount({…})` — exercises
/// grouped-namespace dispatch (plan.md Resolved #5).
struct IssueCountTool: Tool {
    let name = "getIssueCount"
    let description = "Open issue count for a repository."

    func call(arguments: RepoArguments) async throws -> IssueCountOutput {
        IssueCountOutput(count: 42)
    }
}

// MARK: - Named-catalog fixture (UnknownToolHint ranking)

/// A catalog entry whose `tools.*` name and description are supplied per
/// instance, so a test can assemble a realistic multi-tool catalog out of
/// values instead of one near-identical `Tool` type per name.
///
/// Exists for the ranking tests in `UnknownToolHintTests`, which reproduce
/// catalogs recorded from real gated runs: what those tests grade is which
/// entry the did-you-mean hint ranks highest for an invented name, so the
/// only fixture state that matters is the name and the description the
/// ranker reads. `call` is never reached — a snippet naming an entry that
/// does not exist fails before dispatch — but returns a real, distinguishable
/// value rather than a stub, so a test that does dispatch one still gets
/// meaningful output.
struct CatalogEntryTool: Tool {
    let name: String
    let description: String

    func call(arguments: NoArguments) async throws -> String {
        "\(name)-result"
    }
}

// MARK: - Async bridge fixture (eventplan.md "Async JavaScript")

/// A tool whose `call` genuinely suspends (`Task.sleep`) before returning,
/// recording whether it observed `Thread.isMainThread` — exercises the async
/// promise-pump bridge: the wrapped tool's real `async` work runs in its own
/// Swift `Task` (started by `JSCInterpreter.install(asyncHostFunction:into:
/// registry:)`) on Swift's cooperative thread pool, never on the JS-calling
/// (dedicated interpreter worker) thread.
///
/// `final class ... Sendable` (rather than a `struct`), the same pattern as
/// `RecordingTool` (`ToolInvokerFixtures.swift`): recording requires shared
/// mutable state the test inspects *after* `MultiTool.call` returns, backed
/// by an `OSAllocatedUnfairLock` so the type stays `Sendable`.
final class DelayedTool: Tool, Sendable {
    let name = "delayed"
    let description = "Waits briefly, then returns a fixed value."

    private let ranOnMainThreadBox = OSAllocatedUnfairLock<Bool?>(initialState: nil)

    /// Whether `call` observed `Thread.isMainThread` — `nil` until `call`
    /// has run at least once.
    var ranOnMainThread: Bool? { ranOnMainThreadBox.withLock { $0 } }

    func call(arguments: NoArguments) async throws -> String {
        try await Task.sleep(nanoseconds: 20_000_000)
        ranOnMainThreadBox.withLock { $0 = Thread.isMainThread }
        return "delayed-result"
    }
}

// MARK: - Promise.all concurrency fixture (eventplan.md "Async JavaScript")

/// A tool that records the wall-clock window (`start`, `end`) its own `call`
/// ran in — the concurrency-proving counterpart to `DelayedTool`: two of
/// these, called through a snippet's `Promise.all([...])`, prove the
/// underlying Swift `Task`s the async bridge starts for each `tools.*` call
/// actually overlap in wall-clock time, rather than running one after
/// another the way the retired v1 blocking bridge always did.
///
/// `final class ... Sendable` (rather than a `struct`), the same pattern as
/// `DelayedTool`: the test inspects `window` after `MultiTool.call` returns,
/// backed by an `OSAllocatedUnfairLock` so the type stays `Sendable`.
final class WindowRecordingTool: Tool, Sendable {
    let name: String
    let description = "Waits for a fixed duration, recording the wall-clock window its call ran in."

    private let delayNanoseconds: UInt64
    private let windowBox = OSAllocatedUnfairLock<(start: ContinuousClock.Instant, end: ContinuousClock.Instant)?>(
        initialState: nil
    )

    /// Creates a window-recording tool.
    ///
    /// - Parameters:
    ///   - name: this tool's `tools.*` name.
    ///   - delayNanoseconds: how long `call` sleeps before returning.
    init(name: String, delayNanoseconds: UInt64) {
        self.name = name
        self.delayNanoseconds = delayNanoseconds
    }

    /// The wall-clock window `call` ran in — `nil` until it has run at least
    /// once.
    var window: (start: ContinuousClock.Instant, end: ContinuousClock.Instant)? {
        windowBox.withLock { $0 }
    }

    func call(arguments: NoArguments) async throws -> String {
        let start = ContinuousClock.now
        try await Task.sleep(nanoseconds: delayNanoseconds)
        let end = ContinuousClock.now
        windowBox.withLock { $0 = (start, end) }
        return "\(name)-result"
    }
}
