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

## Operation tools

An `OperationTool` from the Extras `Operations` module holds many operations
behind one `call`. The payload of that call carries an `op` string, and the
string selects the operation. You mount such a tool as you mount a plain tool:
with `addTool`, with `addGroup(named:_:)`, or inside a `Capability`. No new
builder method is necessary.

`MultiTool` expands the tool into one verb for each operation. Each verb renders
at `tools.<toolName>.<verbNoun>`, and the op string `tag note` becomes the verb
`tagNote`. The notes fixture in
`Tests/FoundationModelsMultitoolTests/Fixtures/OperationToolFixtures.swift` has
five operations, and they render as these five declarations:

```ts
declare function addNote(args: { title: string; body?: string; tags?: string[] }): Promise<object>;
declare function getNote(args: { id: string }): Promise<object>;
declare function listNote(args: { tag?: string }): Promise<object>;
declare function deleteNote(args: { id: string }): Promise<object>;
declare function tagNote(args: { id: string; tag: string; priority?: "low" | "medium" | "high" }): Promise<object>;
```

These are the rules of the surface:

- Each verb shows only its own fields, and each required mark is true for that
  operation. The `op` field does not appear. The fused form `tools.notes({op})`
  is not mounted, and a call on it is a `TypeError` in the snippet.
- A result is a parsed JSON value, declared `Promise<object>`. The surface does
  not know the fields of the result, so a snippet reads them as it reads any
  JSON. A refusal is a thrown error, and the snippet can catch it.
- Inside a group or a capability, the verbs flatten into that noun. The verbs
  of the fixture under `addGroup(named: "code", [notes])` render at
  `tools.code.<verb>`, with no `notes` level. Two operation tools in one group
  that share an op string are a build error at `buildRegistry()`.

The snippet below lists the notes, keeps the notes whose body names Friday, and
tags each one. The declared type `object` says nothing about the shape of the
list, so the snippet reads the list through `Object.values`. `TypedMockDryRun`
accepts this snippet over the verbs above, so a sample snippet from
`searchTools` can have the same shape:

```js
const notes = await tools.notes.listNote({});
const hits = Object.values(notes).filter((note) => note.body.includes("Friday"));
for (const note of hits) {
  await tools.notes.tagNote({ id: note.id, tag: "due" });
}
return hits.map((note) => note.id);
```

`ReadmeOperationSectionTests` reads this section. Each `declare function` line
above must be a line of
`Tests/FoundationModelsMultitoolTests/Goldens/OperationSurface.ts.txt`, and the
snippet must pass the dry run over the fixture. Do not edit the declarations by
hand; change the fixture and the golden first.

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
