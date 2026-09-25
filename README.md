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

Four capabilities ship with the package, each a set of ordinary `Tool`s you
add to a catalog like any other: **files** (read, edit, patch, search),
**shell** (a sandboxed `execute` plus its history verbs), **web** (search the
web and fetch a page), and **MCP** (attach a stdio or HTTP server and register
its catalog under a noun).

Every shell command runs under a seatbelt sandbox, and a snippet reaches
nothing but the tools you gave it. The guarantees and the escape hatches are
written down in [`docs/SECURITY.md`](docs/SECURITY.md) — read that before
mounting the shell capability or the web capability.

### Web

The web capability is off by default. Call
`withWeb(configuration:sessionConfiguration:)` on the builder to mount it. The
capability adds two verbs:

- `tools.web.search` searches the web. It gives ranked hits (title, URL,
  snippet). It never fetches a page.
- `tools.web.fetch` fetches one URL. It gives the page as markdown, text, or
  raw content, in windows.

A snippet searches, and then fetches the pages that it selects, in parallel:

```js
const hits = await tools.web.search({ query: "swift structured concurrency" });
const pages = await Promise.all(
  hits.results.slice(0, 3).map(r => tools.web.fetch({ url: r.url, maxCharacters: 4000 })));
return pages.map(p => ({ url: p.url, title: p.title, head: p.content.slice(0, 400) }));
```

`withWeb()` with no arguments uses `WebConfiguration.fromEnvironment()`. That
configuration puts each keyed provider whose environment variable is set first,
in this order. The two keyless providers, `braveHTML` and `duckDuckGoHTML`,
come last. When no variable is set, the search is keyless.

| Provider | Environment variable |
|---|---|
| `braveAPI` | `BRAVE_SEARCH_API_KEY` (or `BRAVE_API_KEY`) |
| `tavily` | `TAVILY_API_KEY` |
| `exa` | `EXA_API_KEY` |
| `serper` | `SERPER_API_KEY` |
| `kagi` | `KAGI_API_KEY` |
| `searxng` | `SEARXNG_URL` (the base URL of your instance, not a key) |

The capability tries the providers in list order. When a provider fails, the
capability tries the next provider and adds a line to `notes`. Use
`withWeb(configuration: .keyless)` to read no environment, or give a
`WebConfiguration` with your own provider list. A second `withWeb` call
replaces the first: the last call wins. A key stays in Swift. The sandbox, the
rendered surface, and each result never show a key value.

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
list. `TypedMockDryRun` mocks a `.json` result as a value that reads as an
object and as an array, so the snippet reads the list as an array, and the dry
run accepts it over the verbs above. A sample snippet from `searchTools` can
have the same shape:

```js
const notes = await tools.notes.listNote({});
const hits = notes.filter((note) => note.body.includes("Friday"));
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

The `--web` flag mounts the web capability with `withWeb()`. The provider keys
come from the environment variables in the table of the `### Web` section.
