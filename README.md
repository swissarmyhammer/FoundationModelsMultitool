# FoundationModelsMultitool

[![CI](https://github.com/swissarmyhammer/FoundationModelsMultitool/actions/workflows/ci.yml/badge.svg)](https://github.com/swissarmyhammer/FoundationModelsMultitool/actions/workflows/ci.yml)

A Swift package built on Apple **FoundationModels**. Its one idea: `MultiTool`,
a single `Tool` that wraps other in-process `Tool`s and exposes them to the
model as one callable code API (`runCode`) — instead of round-tripping every
intermediate result through the model's context, the model writes a snippet
that composes several tools with real control flow and returns only the
answer.

## Layering

The package stands in three layers, and each layer needs only the one under
it:

| Layer | What it holds | What it needs |
|---|---|---|
| Verb | Each `any Tool` of the files, shell and MCP capabilities | `FoundationModels` only |
| Router `Hosting/` | The ambient `ToolContext`, the event stream, elicitation, and the background engine | The verbs |
| `MultiTool` | `runCode`, `findAPIs`, and the snippet globals | Router and the verbs |

Each verb of files, shell and MCP works on a bare `LanguageModelSession`. Mount
`ShellCapability().tools` on one with no Router, and `tools.shell.execute`
runs the command to completion and answers with its report. Background is a
property of the Router mount, not of the verb: under a `RoutedSession` the same
verb parks its run and answers a pending envelope at once.

## Usage: mount the vended tools on a `RoutedSession`

`MultiTool` and `SearchToolsTool` are ordinary `FoundationModels.Tool`
conformers, and the host contract is one sentence: build a registry, mount what
`makeSessionTools(librarian:)` vends on a `RoutedSession`, and drive that
session by draining `streamEvents(to:)`. The session's own tool-calling loop
decides when to call `searchTools` (discovery) and `runCode` (execution).

The session type is part of the contract, not a detail. `MultiTool` declares
that it runs in the background: it conforms to `BackgroundTool` and gives a
`ToolMount`. A `RoutedSession` reads that declaration when it mounts the tool,
so every `runCode` call starts a background run and answers at once with a
pending envelope. The mount carries no condition, thus this is not the slow
calls only: a snippet that finishes in a millisecond answers with a token too.
The model collects the result with the mounted `wait` tool. A bare
`FoundationModels.LanguageModelSession` reads no such declaration, so it applies
no background wrapper and `MultiTool`'s own `call(arguments:)` runs in band: the
snippet blocks, no envelope is written, and `wait` has nothing to join.

This example mirrors the runnable demo in `Sources/MultitoolCLI`
(`CLIRunner.runDemo`), which drives exactly this wiring end to end:

```swift
import FoundationModels
import FoundationModelsMultitool
import FoundationModelsRouter

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

// 3. Mount what the registry vends on a `RoutedSession` the resolved
//    `.standard` slot vends. The session drives the searchTools → runCode
//    handoff itself; there is no hand-rolled agent loop.
//
//    `makeSessionTools(librarian:)` builds the tools and orders them:
//    `searchTools` first, then `runCode`, then `wait`, so the model reads
//    "discover what exists" before "execute code", and "block until a result
//    arrives" only after both. `searchTools`'s internal selection tier runs on
//    the same resolved profile's cheaper/faster `flash` slot, through
//    Router-backed sessions (fork-per-call prefix reuse). A `directMode()`
//    registry vends `runCode` and `wait` alone.
//
//    No `instructions:`. Mounting the vended tools is the whole integration —
//    their descriptions carry the entire behavioral contract, because a
//    `Tool` description is in the prompt on every turn while a session
//    instruction is optional.
let session = profile.standard.makeSession(
    tools: try registry.makeSessionTools(librarian: profile.flash)
)

// 4. Drive one turn by draining the event stream. `respond(to:)` self-drains
//    the background runs and returns the same answer, but the stream is the
//    only surface that reports a tool while that tool is still working — which
//    is what a backgrounded `runCode` does. `CLIRunner.drainTurn(_:output:)` is this
//    loop in full, including the tool-status events left out here.
var answer = ""
let prompt = "Of the cities on my trip, which is warmest right now?"
for try await event in await session.streamEvents(to: prompt) {
    switch event {
    case .textDelta(let fragment): answer += fragment
    // A tool ran and the model restarted its answer: drop what it said before.
    case .textReset: answer = ""
    case .toolCall(_, let name, _): print("Calling \(name)")
    default: break
    }
}
print(answer)
```

The demo pins one natively tool-calling-trained model on both `standard` (the
main session) and `flash` (`searchTools`'s selection tier). This README names
no model, because the package names one in exactly one place —
`CLIRunner.generationModel` in
[`Sources/MultitoolCLI/CLIRunner.swift`](Sources/MultitoolCLI/CLIRunner.swift).
The integration suite resolves that same profile rather than keeping a pin of
its own, so a swap there moves the demo and every graded scenario together, and
the measurement history behind each model that has held the slot lives beside
the suite in `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Support/LiveRouterFixture.swift`.
One reference in both slots means one resident model rather than a swap
between generation and selection on every search; see `CLIRunner.demoProfile`
for what that costs and for the Router gate that used to deadlock it.

For a small, fixed tool set, skip discovery entirely — direct mode: build the
registry with `.directMode()` and mount it the same way. A direct-mode
registry vends `runCode` and `wait` alone — direct mode takes discovery away,
never the background run — and snippets introspect the surface via
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

## Capabilities: shell, files and MCP servers

The built-in capabilities are opt-in. Each one owns one noun, and a builder
that never asks for a capability renders no entry under its noun. An MCP
server is a capability too: the host connects the server first, and
`withMCP(servers:)` waits for the server to be ready and reads its catalog.

```swift
let github = MCPServer(name: "github")
try await github.connect(via: transport)     // servers connect before buildRegistry()

let registry = try await MultiTool.Builder()
    .withShell()                              // tools.shell.execute, getLines, grepHistory
    .withFiles(root: workspaceURL)            // tools.files.read, write, edit, patch, glob, grep
    .withMCP(servers: [github])               // tools.github.<tool>, one for each catalog entry
    .buildRegistry()
```

Each connected server registers as its own top-level group, named after the
server: `tools.github.createIssue`, never `tools.mcp.github.createIssue`. The
model does not see the transport. A server whose name is a noun another
registration owns — a server named `files` beside `withFiles(root:)` — fails
at `buildRegistry()` with `MultiToolBuilderError.Kind.duplicateNoun`. A server
that cannot reach `.ready` makes `withMCP(servers:)` throw
`MCPServerError.notReady`.

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

`status`, `wait`, `cancel`, and `elicit` are the ambient background-run
globals: a snippet awaits each of them, exactly as it awaits a `tools.*` call.
A run report carries `state` — `running`, `complete`, or `error` — and a call
that has no run to report carries `result` instead. Outside a session — a
`MultiTool` called directly, with no session to reach — each rejects with a
named, repairable error rather than failing silently. `notify` and `progress`
are synchronous and return nothing; outside a session they are no-ops.

See [the full security model](docs/SECURITY.md) for what each one guarantees
and what the watchdog and caps bound.

## Tests

Two commands, two packages:

```sh
swift test                                                # unit tests
swift test --package-path IntegrationTests --no-parallel   # the real-model suite
```

The first runs the unit tests and nothing else. That is structural, not a
convention: the real-model suite is its own package under
[`IntegrationTests/`](IntegrationTests/Package.swift), and the root
`Package.swift` declares no integration target, so the root `swift test` cannot
reach one. No environment variable selects a suite.

The second resolves real models through FoundationModelsRouter and generates on
the GPU, so it downloads weights and takes 12 to 15 minutes. `--no-parallel` is
required rather than preferred: Swift Testing runs suites concurrently and
starts a test's `.timeLimit` when the test starts, while every scenario queues
for the one resident live profile — so a parallel run spends the limit on queue
time and a queued suite fails in the same way as a hang.

CI runs both, in two jobs. Its unit job also runs
`swift build --package-path IntegrationTests --build-tests` on every trigger, so
a broken integration test is caught by an ordinary push rather than by the next
expensive run.

## Install

Add it as a dependency in `Package.swift`:

```swift
.package(url: "https://github.com/swissarmyhammer/FoundationModelsMultitool", branch: "main")
```

## Documentation

Full design and milestone-by-milestone rationale live in [`plan.md`](plan.md),
which is a historical record: read its own "Status of this document" note
first, because this README and the source are what state the shipped contract.
Sandbox guarantees and escape hatches are documented in
[`docs/SECURITY.md`](docs/SECURITY.md). A runnable end-to-end demo (model
resolution, a tool-carrying `RoutedSession`, a drained turn, tool composition)
lives in `Sources/MultitoolCLI`, behind the thin `Sources/multitool-cli`
executable.

## The demo CLI

`multitool-cli` prints the rendered tool surface, then drives one turn. Its
repeatable `--mcp <name>=<command> [args...]` option attaches a stdio MCP
server: the CLI spawns the command, connects, and registers the catalog of the
server under the name as its noun. Every argument after the value that is no
flag of the CLI goes to the server command, so a server carries its own flags.

```sh
swift build --product mcp-test-server
multitool-cli --mcp echo=.build/debug/mcp-test-server --mode echo
```

The surface listing then names `tools.echo.echo` beside the fixture tools, and
a snippet calls it like any other verb. The CLI starts a `SurfaceRefresher`
after it mounts the session tools, so a `tools/list_changed` reaches the
surface at the next turn boundary; at the end of the run it calls
`MCPServerPool.shutdownAll()`, which stops that refresher, disconnects each
server and ends each subprocess. A `--mcp` value that carries no `=`, or names
a command that does not start, exits 64 with one line and touches no model.
