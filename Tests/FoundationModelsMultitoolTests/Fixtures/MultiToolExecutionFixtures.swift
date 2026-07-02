import Foundation
import FoundationModels
import os

// MARK: - M4a `MultiTool` execution fixtures (plan.md § "MultiTool" / M4a)
//
// Small mock tools that exercise `MultiTool`'s `runCode` execution path end
// to end: composing two tools in one snippet, grouped-namespace dispatch,
// the v1 async bridge (plan.md Resolved #1), and a mis-called tool's
// repairable-error path. Outputs are wrapped in small `@Generable` structs
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

/// The `Output` of `CitiesTool` — a fixed trip itinerary, plan.md's own
/// worked `tripCities(): string[]` example.
@Generable
struct CitiesOutput {
    var cities: [String]
}

/// A standalone, no-argument tool returning a fixed list of city codes.
/// Paired with `TempTool` below so a snippet can `map` over its result and
/// call the other tool per element — the "compose two tools, only the final
/// value comes back" acceptance criterion.
struct CitiesTool: Tool {
    let name = "cities"
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
    let name = "temp"
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
/// snippet dispatches it as `tools.github.issueCount({…})` — exercises
/// grouped-namespace dispatch (plan.md Resolved #5).
struct IssueCountTool: Tool {
    let name = "issueCount"
    let description = "Open issue count for a repository."

    func call(arguments: RepoArguments) async throws -> IssueCountOutput {
        IssueCountOutput(count: 42)
    }
}

// MARK: - Async bridge fixture (plan.md Resolved #1)

/// A tool whose `call` genuinely suspends (`Task.sleep`) before returning,
/// recording whether it observed `Thread.isMainThread` — exercises the v1
/// async bridge: the wrapped tool's real `async` work runs on Swift's
/// cooperative thread pool while the JS-calling (dedicated interpreter
/// worker) thread blocks on a semaphore waiting for it.
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
