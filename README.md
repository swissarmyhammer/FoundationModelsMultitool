# FoundationModelsMultitool

[![CI](https://github.com/swissarmyhammer/FoundationModelsMultitool/actions/workflows/ci.yml/badge.svg)](https://github.com/swissarmyhammer/FoundationModelsMultitool/actions/workflows/ci.yml)

One `Tool` that turns a catalog of Swift tools into a code API the model calls in one shot.

`MultiTool` wraps your in-process `FoundationModels` tools and presents them to
the model as a single `runCode` function. Rather than round-tripping every
intermediate result through the model's context, the model writes one snippet
that composes several tools with real control flow and returns only the answer.
Mount it on a bare `LanguageModelSession` and it works; mount it on a
`RoutedSession` and the same verbs gain background runs, an event stream and
elicitation, without changing a line of the tools themselves.

```swift
import FoundationModels
import FoundationModelsMultitool

// Standalone tools render at tools.<name>; a group nests its tools under
// tools.<group>.<name>.
let registry = try MultiTool.Builder()
    .addTool(TripCitiesTool())
    .addGroup(named: "weather", [WeatherTool()])
    .buildRegistry()

// MultiTool is one Tool. Hand it to a session like any other.
let session = LanguageModelSession(
    model: SystemLanguageModel.default,
    tools: [MultiTool(registry: registry)],
    instructions: "Use runCode to answer questions about the trip."
)

// The model writes one snippet — `const t = tools.getTrip(); ...` — that calls
// several tools and returns only what the answer needs.
let response: LanguageModelSession.Response<String> =
    try await session.respond(to: "Which city on my trip is warmest?")
```

## Install

```swift
.package(url: "https://github.com/swissarmyhammer/FoundationModelsMultitool.git", branch: "main")
```

## Documentation

Six ready-made capabilities ship with the package: files, shell, web, git,
environment and MCP.

- [`docs/GUIDE.md`](docs/GUIDE.md) — the capabilities, background runs, discovery and operation tools.
- [`docs/SECURITY.md`](docs/SECURITY.md) — the sandbox contract. Read it before you mount the shell or web capability.
- [`ARCHITECTURE.md`](ARCHITECTURE.md) — how the package fits together.
- `Tests/FoundationModelsMultitoolTests/ExamplesTests.swift` — copy-pasteable "how do I…" examples against the public API.
