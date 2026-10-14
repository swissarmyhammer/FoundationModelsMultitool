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
/// catalogs recorded from real-model runs: what those tests grade is which
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

/// A tool whose `call` genuinely suspends before it returns, and records
/// whether it observed `Thread.isMainThread`. It exercises the async
/// promise-pump bridge: the real `async` work of the wrapped tool runs in its
/// own Swift `Task` (started by `JSCInterpreter.install(asyncHostFunction:into:
/// registry:)`) on the cooperative thread pool of Swift, never on the
/// JS-calling (dedicated interpreter worker) thread.
///
/// The call suspends on ``hold``, and not on a clock. The test opens the gate
/// of the hold after the call came, or gives the hold a gate that the code
/// under test opens at a fixed point (see ``SnippetEndSignalingInterpreter``).
/// Thus the call is pending for as long as the test needs, and no test
/// depends on the speed of the machine.
///
/// `final class ... Sendable` (rather than a `struct`), the same pattern as
/// `RecordingTool` (`ToolInvokerFixtures.swift`): recording requires shared
/// mutable state the test inspects *after* `MultiTool.call` returns, backed
/// by an `OSAllocatedUnfairLock` so the type stays `Sendable`.
final class DelayedTool: Tool, Sendable {
    let name = "delayed"
    let description = "Waits until the test lets it go on, then returns a fixed value."

    /// The hold that each call waits on before it returns.
    let hold: HeldCall

    private let ranOnMainThreadBox = OSAllocatedUnfairLock<Bool?>(initialState: nil)

    /// Creates a tool whose calls wait on `hold`.
    ///
    /// - Parameter hold: The hold that each call passes. The default is a new
    ///   hold that only the test releases.
    init(hold: HeldCall = HeldCall()) {
        self.hold = hold
    }

    /// Whether `call` observed `Thread.isMainThread` — `nil` until `call`
    /// has run at least once.
    var ranOnMainThread: Bool? { ranOnMainThreadBox.withLock { $0 } }

    func call(arguments: NoArguments) async throws -> String {
        try await hold.pass()
        ranOnMainThreadBox.withLock { $0 = Thread.isMainThread }
        return "delayed-result"
    }
}

// MARK: - Window-recording fixture (eventplan.md "Async JavaScript")

/// A tool that waits until the test releases it, and records the wall-clock
/// window (`start`, `end`) its own `call` ran in.
///
/// No test waits on a window or compares two windows to prove concurrency:
/// that compares the speed of the machine (card `^kdtrmhv`). The `Promise.all`
/// concurrency tests meet at a ``Rendezvous`` instead. The call waits on
/// ``hold``, and not on a clock. A test waits on the `arrival` gate of the
/// hold to know that the call started. A hold that the test never releases is
/// a call that never completes by itself, thus only a cancel can end it.
///
/// `final class ... Sendable` (rather than a `struct`), the same pattern as
/// `DelayedTool`: the test inspects `window` after `MultiTool.call` returns,
/// backed by an `OSAllocatedUnfairLock` so the type stays `Sendable`.
final class WindowRecordingTool: Tool, Sendable {
    let name: String
    let description = "Waits until the test releases it, recording the wall-clock window its call ran in."

    /// The hold that each call waits on before it returns.
    let hold = HeldCall()

    private let windowBox = OSAllocatedUnfairLock<(start: ContinuousClock.Instant, end: ContinuousClock.Instant)?>(
        initialState: nil
    )

    /// Creates a window-recording tool.
    ///
    /// - Parameter name: this tool's `tools.*` name.
    init(name: String) {
        self.name = name
    }

    /// The wall-clock window `call` ran in — `nil` until it has run at least
    /// once.
    var window: (start: ContinuousClock.Instant, end: ContinuousClock.Instant)? {
        windowBox.withLock { $0 }
    }

    func call(arguments: NoArguments) async throws -> String {
        let start = ContinuousClock.now
        try await hold.pass()
        let end = ContinuousClock.now
        windowBox.withLock { $0 = (start, end) }
        return "\(name)-result"
    }
}

