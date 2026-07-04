# FoundationModelsMultitool

[![CI](https://github.com/swissarmyhammer/FoundationModelsMultitool/actions/workflows/ci.yml/badge.svg)](https://github.com/swissarmyhammer/FoundationModelsMultitool/actions/workflows/ci.yml)

A Swift package built on Apple **FoundationModels**. Its one idea: `MultiTool`,
a single `Tool` that wraps other in-process `Tool`s and exposes them to the
model as one callable code API (`runCode`) — instead of round-tripping every
intermediate result through the model's context, the model writes a snippet
that composes several tools with real control flow and returns only the
answer.

```swift
import FoundationModels
import FoundationModelsMultitool

// Any existing `Tool` conformer drops in unchanged.
@Generable
struct NoArguments { @Guide(description: "unused.") var unused: String? }
@Generable
struct TripCitiesOutput { var cities: [String] }

struct TripCitiesTool: Tool {
    let name = "tripCities"
    let description = "The cities on the user's current trip."
    func call(arguments: NoArguments) async throws -> TripCitiesOutput {
        TripCitiesOutput(cities: ["ATX", "SFO", "NYC"])
    }
}

@Generable
struct WeatherArguments { @Guide(description: "IATA city code.") var city: String }
@Generable
struct WeatherOutput { var tempC: Double }

struct WeatherTool: Tool {
    let name = "weather"
    let description = "Current temperature (Celsius) for a city."
    func call(arguments: WeatherArguments) async throws -> WeatherOutput {
        WeatherOutput(tempC: ["ATX": 31, "SFO": 18, "NYC": 24][arguments.city] ?? 20)
    }
}

let registry = try MultiTool.Builder()
    .addTool(TripCitiesTool())
    .addTool(WeatherTool())
    .buildRegistry()
let multiTool = MultiTool(registry: registry)

// One `runCode` call composes both tools; only the final value comes back.
let warmest = try await multiTool.call(
    arguments: RunCodeArguments(code: """
        const cities = tools.tripCities().cities;
        const temps = cities.map(c => tools.weather({ city: c }).tempC);
        return Math.max(...temps);
        """)
)
```

`MultiTool` conforms to `FoundationModels.Tool` itself, so it drops into an
Apple `LanguageModelSession(tools:)` or a `MultiToolAgent` loop the same way
any other tool would. Snippets run in a deny-by-default JavaScriptCore
sandbox with no filesystem, network, or process access — see
[the security model](docs/SECURITY.md) for what's bounded and what isn't.

## Install

Add it as a dependency in `Package.swift`:

```swift
.package(url: "https://github.com/swissarmyhammer/FoundationModelsMultitool", branch: "main")
```

## Documentation

Full design and milestone-by-milestone rationale live in [`plan.md`](plan.md).
Sandbox guarantees and escape hatches are documented in
[`docs/SECURITY.md`](docs/SECURITY.md). A runnable end-to-end demo (model
resolution, agent loop, tool composition) lives in `Sources/multitool-cli`.
