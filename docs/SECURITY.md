# Security model

A `runCode` snippet executes inside a fresh, deny-by-default JavaScriptCore
sandbox (`JSCInterpreter`, `Sources/FoundationModelsMultitool/Interpreter/JSCInterpreter.swift`).
Nothing beyond JavaScriptCore's own standard ECMAScript environment (`Math`,
`JSON`, `Array`, `Object`, …) is reachable except a small, fixed set of
globals this package injects. There is no filesystem, network, process, or
Objective-C/Swift bridging access of any kind — a fresh `JSContext` simply
has none of that, and this package never adds any.

## Injected globals

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

`console` is a minimal `console.log` shim that appends its arguments to the
captured console output (`ResultRenderer`); it is not the browser/Node
`console` and has no other methods. `tools` is the namespace every wrapped
`Tool` is bound under (`tools.<name>`, or `tools.<group>.<name>` for a
grouped tool) — each `tools.*` entry is a native bridge into exactly one
wrapped `Tool`'s own `call(arguments:)`, nothing else. `help()`/`docs(name)`
are read-only introspection over the same rendered `APISurface` the
registry-backed selection tier (`FoundationModelsMetadataRegistry`'s
`MetadataSearcher`/`SelectionTier`) and `searchTools` use — they cannot mutate
anything.

`status()`, `cancel()`, `elicit()`, `notify()`, and `progress()`
reach exactly one thing: the ambient `ToolContext` the session bound around
this `runCode` call — its own `SessionMailbox` and its own upstream event
sink, never another session's. Each is bounded by what that surface itself
allows:

- `status()` and `cancel()` are the **background runs**, which carry
  envelopes and outcomes only. A finished run reports its terminal event —
  the short report the tool returned plus the run's identifier. Router carries
  that report whole, so each tool keeps its own report short (`BackgroundTool`).
  The caps are listed in "The detail of a finished background run" below.
  `status()` reports
  a running run's token, op, kind, and latest progress, never its output. An
  unknown completion token is a reportable no-op, not a throw: one snippet
  cannot probe another session's tokens, because the mailbox it reaches is
  its own session's.
- `elicit()` asks the user a question mid-snippet through
  `ToolContext.elicit`, the same path a wrapped `Tool` uses. The request is
  the restricted MCP form/URL schema, decoded by Router's own
  `ElicitationRequest`, so a snippet can neither widen the schema nor reach
  the user by any other route.
- `notify()` and `progress()` enqueue one event apiece onto the session's
  outbox and return nothing. They cannot read anything back.

Outside a session — a `MultiTool` constructed and called directly, with no
ambient context — there is no session to reach: `status()`,
`cancel()`, and `elicit()` reject with a named, repairable error, and
`notify()`/`progress()` are silent no-ops. None of the five traps.

`wait` reaches nothing. The sandbox `wait()` is removed: a snippet that waits
for a background run holds the model for every session on it, and a settled
run comes back to the session as mail. The name stays only so that a call to
`wait()` throws a repair text at once, in a session or outside one.

Every `tools.*` call is validated (`ArgumentMarshaler`, `ToolInvoker`) before
it ever reaches the wrapped tool: a malformed call fails with a repairable
error text fed back to the model, never a crash, and never anything beyond
that one tool's own `call(arguments:)`.

## The web capability

The web capability (`Sources/FoundationModelsMultitool/Capabilities/Web/`)
gives a snippet the two verbs `tools.web.search` and `tools.web.fetch`. It does
not change the sandbox. The sandbox itself has no network access, and it gets
no new global. A snippet gets network access only from a mounted tool, the same
as it gets file access from the files capability. The web verbs are such tools.

- **Off by default.** The web capability is off by default. A host that does
  not call `withWeb` on the builder renders no `tools.web` namespace, thus a
  snippet has no web verb to call.
- **The URL guard.** `WebAddressGuard` checks the URL of each request before the
  request goes out. It refuses a scheme other than `http` and `https`, a URL
  with user info (`user:pass@`), a blocked host name (for example `localhost`
  or `metadata.google.internal`), and a blocked host suffix (`.local`,
  `.localhost`, `.internal`). Then it resolves the host and checks each
  address. One address in a blocked range (for example a loopback, private,
  link-local, or multicast address) is sufficient for a refusal. The
  link-local range includes the cloud metadata address `169.254.169.254`. The
  guard also checks each redirect hop, and it stops a request after
  `WebFetchPolicy.maxRedirects` hops (default 10, the default argument of
  `WebFetchPolicy.init`). A refusal is a `correction`
  value that the snippet reads, not a thrown error.
- **Known limit: DNS rebinding.** The guard resolves the host, and then
  `URLSession` resolves it again to connect. A DNS server that gives a
  different address the second time (DNS rebinding) can pass the guard. A host
  that must stop this uses a network policy outside the process.
- **Keys.** Keys stay in Swift. The capability uses a key only to make the
  `URLRequest` of its provider. `tools.web.*` has no key parameter, thus the
  sandbox and the model never see a key. `WebAPIKey` shows
  `WebAPIKey(<redacted>)` in its `description`, its `debugDescription`, and its
  `dump` output. Before the error text of a provider goes into `notes` or
  `correction`, the capability replaces each key value in it with
  `<redacted>`.
- **Page content is untrusted data.** A fetched page and a search snippet are
  data from outside. Such text can contain instructions that try to control
  the model. The capability does not remove that text. The host must know that
  the model reads it.
- **SearXNG.** The base URL of a SearXNG instance (`searxng(URL)`, or the
  `SEARXNG_URL` variable) is host configuration. The guard does not check the
  search request to that base URL, because a SearXNG instance on the local
  network is a normal case. The guard still checks each redirect hop of that
  request, and each result URL that a snippet fetches.

## What the watchdog and caps bound

- **Execution time** — a runaway/infinite-loop snippet is force-terminated by
  the interpreter's watchdog (`JSContextGroupSetExecutionTimeLimit`), not left
  to run forever. A snippet that waits for a `tools.*` call that never
  completes executes no JS, so the watchdog has nothing to stop: the
  wall-clock timer of the run ends it at the same ceiling, and cancels the
  pending call. Under a `MultiTool` the ceiling it terminates at is always
  `MultiToolConfiguration.executionTimeLimit`, which defaults to
  `MultiToolConfiguration.defaultExecutionTimeLimit` (120 seconds). That holds for
  the sandbox `MultiTool.init` builds for itself and for one injected through
  its `interpreter:` parameter alike: `MultiTool.init` re-arms whatever
  interpreter it is given from the configured ceiling
  (`Interpreter.withTimeLimit(_:)`), so a caller cannot leave a sandbox
  running under some other limit by handing over a `JSCInterpreter()` built
  with its own. A `JSCInterpreter` run directly, outside any `MultiTool`,
  terminates at the limit its constructor received
  (`JSCInterpreter(timeLimit:)`). The ceiling is absolute: it is measured from
  sandbox creation, and neither reporting progress nor suspending on `elicit()`
  moves that reference point, so no snippet can hold a context open
  indefinitely.
- **Inner-call time** — each `tools.*` call inside a snippet runs to
  completion under its own bound, `RunBinding.innerCallMount`. Its timeout is
  `MultiToolConfiguration.defaultExecutionTimeLimit` (120 seconds). Router
  gives a tool a timeout only when the tool states one, thus this mount
  states it. An inner call does not move the reference point of the snippet
  ceiling above, which is measured from sandbox creation.
- **Cancellation** — cancelling the Swift `Task` running
  `MultiTool.call(arguments:)` force-terminates the in-flight snippet
  through that same watchdog path, cancels each pending `tools.*` call, and
  propagates `CancellationError` — no leaked interpreter thread, no
  semaphore deadlock.
- **Return-value size** (`MultiToolConfiguration.returnValueCharacterLimit`,
  default `ResultRendererLimits.defaultReturnValueCharacterLimit`, 4,000
  characters) and **console output size**
  (`MultiToolConfiguration.consoleCharacterLimit`, default
  `ResultRendererLimits.defaultConsoleCharacterLimit`, 2,000 characters)
  — `ResultRenderer` truncates and appends a visible note rather than
  flooding the model's context with a fat result.
- **Live snippets** — no number limits how many `runCode` snippets run or
  wait at the same time. A snippet executes JS only in short jobs, and a
  snippet that waits for a `tools.*` call holds no thread, only its
  JavaScriptCore context in memory (see `JSCInterpreter`). Each live snippet
  is still bounded by the execution-time ceiling above, so no suspended
  context lives past it.

### The detail of a finished background run

A finished background run comes back to the model as mail, and the mail
carries the `detail` of the terminal event of the run. Router does not cut
that detail (Router commit `f3b72f5` removed its tail cut). Thus the caps of
this package are the only bound on it:

- **`runCode`.** The detail is the rendered result of the snippet.
  `ResultRenderer` cuts the serialized return value to
  `MultiToolConfiguration.returnValueCharacterLimit` (default
  `ResultRendererLimits.defaultReturnValueCharacterLimit`, 4,000 characters),
  and it cuts the console output to
  `MultiToolConfiguration.consoleCharacterLimit` (default
  `ResultRendererLimits.defaultConsoleCharacterLimit`, 2,000 characters). Each
  cut adds one note line that gives the length before the cut.
- **`tools.shell.execute`.** The detail is the report of the command. The
  report holds only the last `Execute.tailLineCount` (32) lines of the output,
  but one line has no length limit. `ResultRenderer` cuts the rendered report
  to `ResultRendererLimits.default.returnValueCharacterLimit` (4,000
  characters), and adds the same note line. The report keys are sorted, so
  `commandID` comes first and stays in the kept part. The model can read the
  full output with `tools.shell.getLines`.

`MultiToolExecutionTests` and `ShellExecuteTests` prove each bound with a run
that writes ten times too much output.

Turn budgeting is no longer this package's to bound: the retired hand-rolled
ReAct loop's `maxAgentTurns`/`maxRepairTurns` knobs were removed with it, and
the session's own native tool-calling loop — the shipped main loop, running
inside the `RoutedSession` a host mounts the vended tools on — owns how many
`searchTools`/`runCode` turns a request may take.

## What is NOT guaranteed

- **In-snippet tool-call arguments are not token-constrained.** Once the
  model is inside a `runCode` snippet, the arguments it writes for a
  `tools.X({...})` call are ordinary code the model authored — not
  schema-constrained at the token level the way a direct tool call under
  Apple's built-in tool-calling loop would be. `ToolInvoker`/
  `ArgumentMarshaler` validate every call before it reaches the wrapped tool
  and return a precise, repairable error on a mismatch, but that is
  validation *after the fact*, not a generation-time guarantee.
- **Escape hatch**, when the hard argument guarantee matters for one tool:
  mount that tool on the session alongside the vended ones. The shipped main
  loop is already `FoundationModels`'s own native tool-calling — the
  `RoutedSession` that `profile.standard.makeSession(tools:)` vends runs it
  over the Router-resolved model (`Sources/MultitoolCLI/CLIRunner.swift`
  drives exactly that) — and every tool mounted on the session gets
  schema-constrained argument generation as a basic property of native
  tool-calling itself. So a tool not meant for JS-snippet composition is
  simply mounted as its own separate `Tool` alongside `multiTool` and
  `searchToolsTool`, rather than routed through `MultiTool`'s registry at
  all.
- **A wrapped tool's own behavior is out of scope.** The sandbox bounds what
  a *snippet* can reach; it says nothing about what a wrapped `Tool`'s own
  `call(arguments:)` implementation does once invoked (e.g. a tool that
  itself makes network calls) — that is the tool author's responsibility,
  the same as if the tool were called directly rather than wrapped.
