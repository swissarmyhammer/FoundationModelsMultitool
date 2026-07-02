import FoundationModels
import os

// MARK: - `RecordingTool` — records the arguments `ToolInvoker.invoke` decoded
//
// `ToolInvoker.invoke` hands a real, statically-typed `T.Arguments` value to
// `tool.call(arguments:)` — this fixture's `call` records that value (rather
// than doing real work) so `ToolInvokerTests` can assert on exactly what was
// decoded, and that it's `nil` whenever a test expects validation to fail
// *before* `call` ever runs. Reuses `OSAllocatedUnfairLock` for the
// `Sendable` capture box, the same pattern `JSCInterpreterTests` uses for a
// host function's received arguments.

/// `RecordingTool`'s arguments — one required `city`, one optional
/// enum-constrained `units`, deliberately the same shape as the plan's
/// worked `WeatherArguments` example so a shape-mismatch/missing-field test
/// against it reads naturally.
@Generable
struct RecordingToolArguments {
    @Guide(description: "IATA city code or city name.")
    var city: String

    @Guide(description: "temperature unit", .anyOf(["c", "f"]))
    var units: String?
}

/// `RecordingTool`'s `Output` — irrelevant to what these tests assert on;
/// exists only because `Tool.call(arguments:)` must return something.
@Generable
struct RecordingToolOutput {
    var echoedCity: String
}

/// A `Tool` whose `call(arguments:)` records the arguments it received
/// instead of doing real work. `final class ... Sendable` (rather than a
/// `struct`) because recording requires shared mutable state visible to the
/// test after `invoke` returns; `Tool` requires `Sendable`, satisfied here
/// because the only stored property is a `let` `OSAllocatedUnfairLock`
/// (itself `Sendable`).
final class RecordingTool: Tool, Sendable {
    let name = "recordingTool"
    let description = "Records the arguments it receives, for test assertions."

    private let recordedBox = OSAllocatedUnfairLock<RecordingToolArguments?>(initialState: nil)

    /// The arguments `call(arguments:)` most recently received, or `nil` if
    /// `call` has never run.
    var recorded: RecordingToolArguments? { recordedBox.withLock { $0 } }

    func call(arguments: RecordingToolArguments) async throws -> RecordingToolOutput {
        recordedBox.withLock { $0 = arguments }
        return RecordingToolOutput(echoedCity: arguments.city)
    }
}

// MARK: - `ThrowingTool` — a tool whose `call` always throws
//
// Exercises the "a throwing tool's error propagates with its message
// intact" acceptance criterion: `ToolInvoker.invoke` must never wrap this
// error in a `ToolInvokerError`.

/// A distinctive error type `ThrowingTool` throws, so a test can assert the
/// exact same error instance (kind + message) comes back out of
/// `ToolInvoker.invoke` unchanged, not re-wrapped.
struct ThrowingToolError: Error, Equatable, CustomStringConvertible {
    let message: String
    var description: String { message }
}

/// A `Tool` that always throws `ThrowingToolError` from `call`, never
/// returning normally.
struct ThrowingTool: Tool {
    let name = "throwingTool"
    let description = "Always throws, to exercise error-message passthrough."

    func call(arguments: RecordingToolArguments) async throws -> RecordingToolOutput {
        throw ThrowingToolError(message: "boom: \(arguments.city)")
    }
}

// MARK: - Guide-violation tools
//
// Reuse `RangedIntegerArgument`/`CountedArrayArgument`
// (`Tests/.../Fixtures/ToolAPIRendererFixtures.swift`) rather than
// re-declaring equivalent `@Guide`-annotated structs — those fixtures
// already isolate exactly the numeric-range and array-count guide shapes
// M3b's validation needs to exercise. Only a `Tool` wrapper is new here;
// `WeatherTool` (also reused, from the same fixtures file) already covers
// the enum/`anyOf` guide, plus the missing-required-field and
// shape-mismatch cases, via its required `city: String`.

/// A shared, semantically-irrelevant `Output` for the guide-violation
/// fixture tools below — their tests all expect validation to fail before
/// `call` ever runs, so the actual `Output` shape returned on success
/// doesn't matter to any assertion.
@Generable
struct EchoOutput {
    var value: String
}

/// Wraps `RangedIntegerArgument` (`score: Int`, `.range(1...10)`) so
/// `ToolInvokerTests` can exercise a numeric-range guide violation through a
/// real `Tool`.
struct RangedTool: Tool {
    let name = "rangedTool"
    let description = "Echoes a ranged score."

    func call(arguments: RangedIntegerArgument) async throws -> EchoOutput {
        EchoOutput(value: String(arguments.score))
    }
}

/// Wraps `CountedArrayArgument` (`ratings: [Int]`, `.count(1...3)`) so
/// `ToolInvokerTests` can exercise an array-count guide violation through a
/// real `Tool`.
struct CountedTool: Tool {
    let name = "countedTool"
    let description = "Echoes the count of ratings."

    func call(arguments: CountedArrayArgument) async throws -> EchoOutput {
        EchoOutput(value: String(arguments.ratings.count))
    }
}
