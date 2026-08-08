import FoundationModels

// MARK: - Fixtures for the generated-sample gate (`TypedMockDryRun`, `SampleSnippet`)
//
// The catalog these build is deliberately shaped like a real one rather than
// minimal: an optional and enum-constrained argument, an optional field on a
// result, and one tool whose argument object is the *same* declared shape as
// another tool's result — which is the chained-call case the dry run must let
// through untouched (a mock standing for `T` satisfies a parameter declared
// `T`).
//
// No fixture value here is a value a gated scenario grades on. The gate never
// shows the model a mock's value, and these tools return fixed placeholder
// data so a test can tell one call from another.

/// `ForecastTool`'s arguments — one required `city`, one optional
/// enum-constrained `days`.
@Generable
struct ForecastArguments {
    @Guide(description: "IATA city code.")
    var city: String

    @Guide(description: "how many days ahead", .anyOf(["1", "7"]))
    var days: String?
}

/// The `Output` of `ForecastTool` — one required field and one optional,
/// so a snippet reading the optional one is still reading a declared field.
@Generable
struct ForecastOutput {
    var summary: String
    var advisory: String?
}

/// A forecast lookup with an optional, enum-constrained argument.
struct ForecastTool: Tool {
    let name = "getForecast"
    let description = "Forecast for a city."

    func call(arguments: ForecastArguments) async throws -> ForecastOutput {
        ForecastOutput(summary: "placeholder", advisory: nil)
    }
}

/// `SummarizeTripTool`'s arguments — one required `trip`, declared as the
/// very type `CitiesTool` returns, so passing one tool's whole result
/// straight into the next is a correctly-typed call.
@Generable
struct SummarizeTripArguments {
    @Guide(description: "the trip to summarize.")
    var trip: CitiesOutput
}

/// A tool whose argument object is another tool's result shape.
struct SummarizeTripTool: Tool {
    let name = "summarizeTrip"
    let description = "Summarizes a trip."

    func call(arguments: SummarizeTripArguments) async throws -> String {
        arguments.trip.cities.joined(separator: ", ")
    }
}
