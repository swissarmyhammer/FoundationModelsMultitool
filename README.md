# FoundationModelsMultitool

[![CI](https://github.com/swissarmyhammer/FoundationModelsMultitool/actions/workflows/ci.yml/badge.svg)](https://github.com/swissarmyhammer/FoundationModelsMultitool/actions/workflows/ci.yml)

A Swift package built on Apple **FoundationModels**. Its one idea: `MultiTool`,
a single `Tool` that wraps other in-process `Tool`s and exposes them to the
model as one callable code API (`runCode`) — instead of round-tripping every
intermediate result through the model's context, the model writes a snippet
that composes several tools with real control flow and returns only the
answer.

## Usage: register on a native `LanguageModelSession`

`MultiTool` and `SearchToolsTool` are ordinary `FoundationModels.Tool`
conformers, so the primary integration is Apple's own native tool-calling
loop: register both directly on a `LanguageModelSession`, and the session
decides when to call `searchTools` (discovery) and `runCode` (execution). This
example mirrors the runnable demo in `Sources/multitool-cli`
(`CLIRunner.runDemo`), which drives exactly this wiring end to end:

```swift
import FoundationModels
import FoundationModelsMultitool
import FoundationModelsRouter
import MLXFoundationModels

// Any existing `Tool` conformer drops in unchanged.
@Generable
struct NoArguments { @Guide(description: "unused.") var unused: String? }
@Generable
struct TripOutput { var cities: [String] }

struct TripTool: Tool {
    let name = "getTrip"
    let description = "The cities on the user's current trip, in itinerary order."
    func call(arguments: NoArguments) async throws -> TripOutput {
        TripOutput(cities: ["ATX", "SFO", "NYC"])
    }
}

@Generable
struct WeatherArguments { @Guide(description: "IATA city code or city name.") var city: String }
@Generable
struct WeatherOutput { var tempC: Double }

struct WeatherTool: Tool {
    let name = "getWeather"
    let description = "Current weather for a city. Use when asked how warm/cold/rainy it is right now."
    func call(arguments: WeatherArguments) async throws -> WeatherOutput {
        WeatherOutput(tempC: ["ATX": 31, "SFO": 18, "NYC": 24][arguments.city] ?? 20)
    }
}

// 1. Collect the tools into a model-agnostic registry.
let registry = try MultiTool.Builder()
    .addTool(TripTool())
    .addTool(WeatherTool())
    .buildRegistry()

// 2. Resolve a model profile via FoundationModelsRouter (RAM-aware model
//    selection). The Router provides models — never a tool-calling loop.
//    Constructing the `Router` and its live loader is `CLIRunner.runDemo`'s
//    first step, verbatim.
let profile = try await router.resolve(profile: demoProfile, reporting: progress)

// 3. Wrap the resolved `.standard` slot as a real `FoundationModels
//    .LanguageModel` declaring `.toolCalling` — an `MLXLanguageModel`, built
//    exactly as `CLIRunner.makeMLXLanguageModel(for:)` does — and mount what
//    the registry vends. Apple's own tool-calling loop drives the searchTools →
//    runCode handoff; there is no hand-rolled agent loop.
//
//    `makeSessionTools(librarian:)` builds both tools and orders them:
//    `searchTools` first, then `runCode`, so the model reads "discover what
//    exists" before "execute code". `searchTools`'s internal selection tier
//    runs on the same resolved profile's cheaper/faster `flash` slot,
//    through Router-backed sessions (fork-per-call prefix reuse). A
//    `directMode()` registry vends `runCode` alone.
//
//    No `instructions:`. Mounting the two tools is the whole integration —
//    their descriptions carry the entire behavioral contract, because a
//    `Tool` description is in the prompt on every turn while a session
//    instruction is optional.
let mlxModel = makeMLXLanguageModel(for: profile.standard)
let session = LanguageModelSession(
    model: mlxModel,
    tools: try registry.makeSessionTools(librarian: profile.flash)
)

let response: LanguageModelSession.Response<String> =
    try await session.respond(to: "Of the cities on my trip, which is warmest right now?")
print(response.content)
```

The demo pins deliberately small models: the natively tool-calling-trained
`mlx-community/Qwen3-4B-Instruct-2507-4bit` on `standard` for the main
session, and `mlx-community/Qwen2.5-1.5B-Instruct-4bit` on `flash` for
`searchTools`'s selection tier (see `CLIRunner.demoProfile` for the rationale).

For a small, fixed tool set, skip discovery entirely — direct mode: build the
registry with `.directMode()` and mount it the same way. A direct-mode
registry vends `runCode` alone, and snippets introspect the surface via
`help()`/`docs(name)` instead (the demo's `--direct` flag).

The living-documentation suite,
[`Tests/FoundationModelsMultitoolTests/ExamplesTests.swift`](Tests/FoundationModelsMultitoolTests/ExamplesTests.swift),
holds copy-pasteable examples of every canonical call pattern — each runs
fully offline against a real `LanguageModelSession`.

## Calling `runCode` directly

`MultiTool` is also directly callable — no session at all. One `runCode`
call composes both tools; only the final value comes back:

Every `tools.*` call returns a promise, so a snippet composing more than one
call awaits each of them (or fans them out with `Promise.all`):

```swift
let multiTool = MultiTool(registry: registry)
let warmest = try await multiTool.call(
    arguments: RunCodeArguments(code: """
        const cities = (await tools.getTrip()).cities;
        const temps = [];
        for (const city of cities) {
          temps.push((await tools.getWeather({ city })).tempC);
        }
        return Math.max(...temps);
        """)
)
```

## Security model

A `runCode` snippet executes inside a fresh, deny-by-default JavaScriptCore
sandbox with no filesystem, network, or process access.

### Injected globals

The only globals beyond JavaScriptCore's standard ECMAScript environment that
a fresh `runCode` sandbox can reach:

- `console`
- `tools`
- `help`
- `docs`
- `status`
- `wait`
- `cancel`
- `elicit`
- `notify`
- `progress`

`status`, `wait`, `cancel`, and `elicit` are the ambient run-plane globals: a
snippet awaits each of them, exactly as it awaits a `tools.*` call. Outside a
session — a `MultiTool` called directly, with no run plane — each rejects with
a named, repairable error rather than failing silently. `notify` and `progress`
are synchronous and return nothing; outside a session they are no-ops.

See [the full security model](docs/SECURITY.md) for what each one guarantees
and what the watchdog and caps bound.

## Install

Add it as a dependency in `Package.swift`:

```swift
.package(url: "https://github.com/swissarmyhammer/FoundationModelsMultitool", branch: "main")
```

## Documentation

Full design and milestone-by-milestone rationale live in [`plan.md`](plan.md).
Sandbox guarantees and escape hatches are documented in
[`docs/SECURITY.md`](docs/SECURITY.md). A runnable end-to-end demo (model
resolution, a native tool-calling `LanguageModelSession`, tool composition)
lives in `Sources/multitool-cli`.
