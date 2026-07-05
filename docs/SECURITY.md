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

`console` is a minimal `console.log` shim that appends its arguments to the
captured console output (`ResultRenderer`); it is not the browser/Node
`console` and has no other methods. `tools` is the namespace every wrapped
`Tool` is bound under (`tools.<name>`, or `tools.<group>.<name>` for a
grouped tool) — each `tools.*` entry is a native bridge into exactly one
wrapped `Tool`'s own `call(arguments:)`, nothing else. `help()`/`docs(name)`
are read-only introspection over the same rendered `APISurface` the
registry-backed selection tier (`FoundationModelsMetadataRegistry`'s
`MetadataSearcher`/`SelectionTier`) and `findAPIs` use — they cannot mutate
anything.

Every `tools.*` call is validated (`ArgumentMarshaler`, `ToolInvoker`) before
it ever reaches the wrapped tool: a malformed call fails with a repairable
error text fed back to the model, never a crash, and never anything beyond
that one tool's own `call(arguments:)`.

## What the watchdog and caps bound

- **Execution time** (`MultiToolConfiguration.executionTimeLimit`, default
  5 seconds) — a runaway/infinite-loop snippet is force-terminated by the
  interpreter's watchdog (`JSContextGroupSetExecutionTimeLimit`), not left
  to run forever.
- **Cancellation** — cancelling the Swift `Task` running
  `MultiToolAgent.respond(to:)` or `MultiTool.call(arguments:)` force-
  terminates the in-flight snippet through that same watchdog path and
  propagates `CancellationError` — no leaked interpreter thread, no
  semaphore deadlock.
- **Return-value size** (`MultiToolConfiguration.returnValueCharacterLimit`,
  default 4,000 characters) and **console output size**
  (`MultiToolConfiguration.consoleCharacterLimit`, default 2,000 characters)
  — `ResultRenderer` truncates and appends a visible note rather than
  flooding the model's context with a fat result.
- **Agent turns** (`MultiToolConfiguration.maxAgentTurns`, default 8) — the
  search-then-code loop terminates with a typed error rather than spinning
  forever.
- **Repair turns** (`MultiToolConfiguration.maxRepairTurns`, default 1) — a
  bounded number of malformed-turn recovery attempts before the agent loop
  fails.

## What is NOT guaranteed

- **In-snippet tool-call arguments are not token-constrained.** Once the
  model is inside a `runCode` snippet, the arguments it writes for a
  `tools.X({...})` call are ordinary code the model authored — not
  schema-constrained at the token level the way a direct tool call under
  Apple's built-in tool-calling loop would be. `ToolInvoker`/
  `ArgumentMarshaler` validate every call before it reaches the wrapped tool
  and return a precise, repairable error on a mismatch, but that is
  validation *after the fact*, not a generation-time guarantee.
- **Escape hatches**, when the hard argument guarantee matters for one tool:
  - **Register it as a *direct* tool instead of wrapping it** —
    `MultiToolAgent(directTools:)` — and the agent loop surfaces a third
    affordance, `callTool(name, args)`, alongside `runCode`/`findAPIs`. The
    model gives the tool's exact name and a plain-language description of
    what it wants the call to accomplish (never the literal argument
    values); `DirectToolCall`
    (`Sources/FoundationModelsMultitool/Agent/DirectToolCall.swift`) then:
    encodes the tool's `parameters: GenerationSchema` to a JSON Schema
    string (reusing `ToolAPIRenderer`'s own encode path,
    `ToolAPIRenderer.jsonSchemaString(for:)`); constrains a one-shot Router
    guided-generation call to that schema via **`RoutedLLM
    .respond(to:matching:)`** — the *dynamic-JSON* guided shape, since the
    tool's `Arguments` type is only known through existential opening and
    isn't nameable as a compile-time `Generable` target for
    `respond(to:generating:)`; builds a `GeneratedContent(json:)` from the
    schema-valid `JSONValue` output; and invokes through the same
    `ToolInvoker` pipeline the `runCode` wrapped-tool path uses. One extra
    round trip buys xgrammar-constrained, schema-valid arguments end to end.
    An unknown direct-tool name, or `callTool` used with no direct tools
    configured, is rejected with an instructive, repairable message — never
    a crash.
  - Place the `MultiTool` and that tool directly in an Apple built-in
    `SystemLanguageModel` `LanguageModelSession(tools:)` instead of a Router
    model — the only place `FoundationModels`'s own token-level tool-calling
    loop applies here. `DirectToolCall`'s guided-generation path is the
    schema-valid escape hatch *on a Router model*; Apple's own
    constrained-decoding tool loop is a different mechanism, available only
    inside a built-in `SystemLanguageModel` session, never through
    `MultiToolAgent`.
- **A wrapped tool's own behavior is out of scope.** The sandbox bounds what
  a *snippet* can reach; it says nothing about what a wrapped `Tool`'s own
  `call(arguments:)` implementation does once invoked (e.g. a tool that
  itself makes network calls) — that is the tool author's responsibility,
  the same as if the tool were called directly rather than wrapped.
