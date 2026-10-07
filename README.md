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

The library does not depend on FoundationModelsRouter. Tool hosting comes from
FoundationModelsExtras: `ToolContext`, `BackgroundTool`, `ToolMount`,
`ToolMounting`, `SubmissionBoundaryTool`, `ToolCallReport` and the `RunPlane`
that mints each completion token. A host that mounts the tools on a
`RoutedSession` adds Router itself. In this repository, only the test targets
link Router.

## Capabilities

Five capabilities ship with the package, each a set of ordinary `Tool`s you
add to a catalog like any other: **files** (read, edit, patch, search),
**shell** (a sandboxed `execute` plus its history verbs), **web** (search the
web and fetch a page), **git** (read the status, the history, and a semantic
diff of a repository), and **MCP** (attach a stdio or HTTP server and register
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
in this order. The two keyless providers, `duckDuckGoHTML` and then
`braveHTML`, come last. When no variable is set, the search is keyless.

| Provider | Environment variable |
|---|---|
| `braveAPI` | `BRAVE_SEARCH_API_KEY` (or `BRAVE_API_KEY`) |
| `tavily` | `TAVILY_API_KEY` |
| `exa` | `EXA_API_KEY` |
| `serper` | `SERPER_API_KEY` |
| `kagi` | `KAGI_API_KEY` |
| `searxng` | `SEARXNG_URL` (the base URL of your instance, not a key) |

The capability tries the providers in list order. When a provider fails, the
capability tries the next provider and adds a line to `notes`. A provider that
sends HTTP 429 gets no request until its cooldown ends: the `Retry-After` time
of the response, else 60 seconds, and never more than 10 minutes. Use
`withWeb(configuration: .keyless)` to read no environment, or give a
`WebConfiguration` with your own provider list. A second `withWeb` call
replaces the first: the last call wins. A key stays in Swift. The sandbox, the
rendered surface, and each result never show a key value.

### Git

The git capability is off by default. Call `withGit(root:)` on the builder to
mount it. The capability adds seven verbs under `tools.git`:

| Verb | Arguments | Result |
|---|---|---|
| `tools.git.status` | none | `staged`, `unstaged`, `untracked`, and `renamed` paths, and `isClean` |
| `tools.git.branches` | none | the local `branches`, the `current` branch, and the `main` branch |
| `tools.git.changes` | `branch?`, `range?` | `branch`, `parentBranch`, `range`, and the changed `files` |
| `tools.git.show` | `path`, `ref?` | the `content` of the file at the ref (HEAD when you omit it) |
| `tools.git.log` | `ref?`, `path?`, `limit?` | `commits`, newest first: `sha`, `shortSha`, `author`, `date`, and `subject` |
| `tools.git.blame` | `path`, `startLine?`, `endLine?` | one row for each line: `line`, `text`, `state`, and the `sha`, `author`, and `date` of the commit |
| `tools.git.diff` | `left?`, `right?`, `leftText?`, `rightText?`, `language?` | a semantic diff: a `summary` of the counts and the `changes`, one for each entity |

A snippet reads the changed files, and then diffs each file against HEAD, in
parallel:

```js
const changes = await tools.git.changes({});
const diffs = await Promise.all(
  changes.files.slice(0, 5).map(path => tools.git.diff({ left: `${path}@HEAD`, right: path })));
return { branch: changes.branch, parent: changes.parentBranch, diffs };
```

These are the rules of the capability:

- The capability is read-only. No verb changes the repository. To change a
  file, use `tools.files.*`. To run a different git command, use
  `tools.shell.*`, when the host mounts those capabilities.
- The repository is the one that contains the root, and the root can be a
  folder below the top of the repository. Each path argument goes through the
  same path guard as the files capability, thus a path cannot go out of the
  root. Each path in a result is relative to the root, and a file outside the
  root is in no result. One exception: a path that reads history (`show`,
  `log`, and `diff` with `path@ref`) goes through the guard with
  `absentFolders: .accepted`. Thus the guard does not refuse a folder that a
  later commit removed. All the other checks of the guard stay the same.
- A mistake that the model can correct (an unknown ref, an unknown path, a
  bad range, or a root in no repository) does not throw. It comes back in the
  result as a `correction` field.
- The capability links libgit2. It does not need the `git` command on the
  machine.

`tools.git.diff` compares entities (functions, classes, keys, and other
entities), not lines. It has three modes: two inline texts with a `language`,
two files (`left` and `right`, each a path or `path@ref`), or no argument,
which diffs each changed file of the work folder against HEAD. It finds the
entities with tree-sitter for these languages: Rust, TypeScript, TSX,
JavaScript, JSX, Python, Go, Java, C, C++, C#, Ruby, PHP, Swift, Elixir, and
Bash. It reads these data formats: JSON, YAML, TOML, CSV, and Markdown. A Vue
file gives its `<script>` block to the TypeScript or JavaScript parser. A file
of each other type goes to the fallback plugin, which compares chunks of
lines.

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

`wait` is not a usable global. The sandbox `wait()` is removed, because a
snippet that waits for a background run holds the model for every session on
it. The name stays only so that a call to `wait()` fails with a repair text:
return the completion token, end the answer, and the result comes back as
mail.

This list is not documentation alone. `HardeningTests` parses it out of this
file and asserts it is set-equal to the globals the sandbox enumerates at
runtime, so a global added to the code and not to this list fails the suite.
Do not delete or reword the list items. [`docs/SECURITY.md`](docs/SECURITY.md)
says what each one guarantees.

## Background runs and mail delivery

On a `RoutedSession`, each `runCode` call goes to the background. The call
first waits for its snippet for `MultiToolConfiguration.inlineSettleGrace`
(default `MultiToolConfiguration.defaultInlineSettleGrace`, 5 seconds):

- A snippet that settles in that time gives its result in the tool output,
  with `pending: false`. No mail comes for that run.
- A snippet that is still running gives a pending envelope with a
  `completionToken`. The model ends its answer. When the snippet settles,
  Router puts its result into the session outbox as mail, and that mail
  starts the next submission of the session. The model answers from that
  message.

A snippet can look at a running snippet with `status()` and stop it with
`cancel(completionToken)`. A snippet cannot wait for a run. Router runs the
work of each model on one queue, and a wait inside a submission holds the
model for every session on it.

On a bare `LanguageModelSession` there is no background: the snippet runs to
its end inside the call, and no mail comes.

## Discovery and the librarian model

`registry.makeSessionTools(selection:embedder:sampleSession:)` mounts
`searchTools` before `runCode`. `searchTools` asks a second model, the
librarian, which tool-functions fit the task. It can also ask a model to
write a sample snippet.

The librarian model must be different from the model of the calling session.
The same rule applies to the model of the sample snippet. `searchTools` is
synchronous, so its sessions run inside the open submission of the calling
session. Router runs the work of each model in order, and it refuses at once
a wait on the model of that open submission. With Router, give the `flash`
slot a model that is different from the `standard` slot, and give
`profile.flash` to the librarian.

`searchTools` does not hide a failed session. An error of the librarian is the
error of the `searchTools` call. An error of the sample session is a note
beside the signatures. When the librarian and the calling session use the
same model, the `searchTools` call fails with the refusal of Router. Use a
different flash model.

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
