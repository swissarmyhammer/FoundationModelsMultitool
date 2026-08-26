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

`status()`, `wait()`, `cancel()`, `elicit()`, `notify()`, and `progress()`
reach exactly one thing: the ambient `ToolContext` the session bound around
this `runCode` call — its own `SessionMailbox` and its own upstream event
sink, never another session's. Each is bounded by what that surface itself
allows:

- `status()`, `wait()`, and `cancel()` are the **background runs**, which carry
  envelopes and outcomes only. `wait()` resolves to a run's terminal event —
  a bounded output tail (`SessionMailbox.terminalDetailTailLimit`) plus the
  run's identifier — never a capability's full store, and `status()` reports
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
ambient context — there is no session to reach: `status()`, `wait()`,
`cancel()`, and `elicit()` reject with a named, repairable error, and
`notify()`/`progress()` are silent no-ops. None of the six traps.

Every `tools.*` call is validated (`ArgumentMarshaler`, `ToolInvoker`) before
it ever reaches the wrapped tool: a malformed call fails with a repairable
error text fed back to the model, never a crash, and never anything beyond
that one tool's own `call(arguments:)`.

## What the watchdog and caps bound

- **Execution time** — a runaway/infinite-loop snippet is force-terminated by
  the interpreter's watchdog (`JSContextGroupSetExecutionTimeLimit`), not left
  to run forever. Under a `MultiTool` the ceiling it terminates at is always
  `MultiToolConfiguration.executionTimeLimit`, which defaults to
  `ToolMount.defaultTimeoutSeconds` (120 seconds). That holds for
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
- **Cancellation** — cancelling the Swift `Task` running
  `MultiTool.call(arguments:)` force-terminates the in-flight snippet
  through that same watchdog path and propagates `CancellationError` — no
  leaked interpreter thread, no semaphore deadlock.
- **Return-value size** (`MultiToolConfiguration.returnValueCharacterLimit`,
  default 4,000 characters) and **console output size**
  (`MultiToolConfiguration.consoleCharacterLimit`, default 2,000 characters)
  — `ResultRenderer` truncates and appends a visible note rather than
  flooding the model's context with a fat result.

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
