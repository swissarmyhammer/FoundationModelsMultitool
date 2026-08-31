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

## Capabilities

Three capabilities ship with the package, each a set of ordinary `Tool`s you
add to a catalog like any other: **files** (read, edit, patch, search),
**shell** (a sandboxed `execute` plus its history verbs), and **MCP** (attach a
stdio or HTTP server and register its catalog under a noun).

Every shell command runs under a seatbelt sandbox, and a snippet reaches
nothing but the tools you gave it. The guarantees and the escape hatches are
written down in [`docs/SECURITY.md`](docs/SECURITY.md) — read that before
mounting the shell capability.

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

This list is not documentation alone. `HardeningTests` parses it out of this
file and asserts it is set-equal to the globals the sandbox enumerates at
runtime, so a global added to the code and not to this list fails the suite.
Do not delete or reword the list items. [`docs/SECURITY.md`](docs/SECURITY.md)
says what each one guarantees.

## Documentation

- [`docs/SECURITY.md`](docs/SECURITY.md) — the sandbox contract: what a snippet
  can reach, what it cannot, and the deliberate escape hatches.
- [`plan.md`](plan.md) and [`eventplan.md`](eventplan.md) — design and
  milestone rationale. Both are historical records; read the status note at the
  top of each, because this README and the source state the shipped contract.
- `Tests/FoundationModelsMultitoolTests/ExamplesTests.swift` — each test is a
  self-contained, copy-pasteable "how do I…" against the public API.

## The demo CLI

`multitool-cli` prints the rendered tool surface, then drives one turn. Its
repeatable `--mcp <name>=<command> [args...]` option attaches a stdio MCP
server under that name:

```sh
swift build --product mcp-test-server
multitool-cli --mcp echo=.build/debug/mcp-test-server --mode echo
```

The listing then names `tools.echo.echo` beside the fixture tools, and a
snippet calls it like any other verb.
