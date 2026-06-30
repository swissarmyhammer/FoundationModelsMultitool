# FoundationModelsMultitool — Plan

A Swift package built on Apple **FoundationModels**. Its one idea: a single
`Tool` — the **MultiTool** — that **wraps other, in-process `Tool`s and exposes
them to the model as a callable code API**. The model calls the MultiTool with one
argument, a snippet of code; the snippet calls the wrapped tools as ordinary
functions, composes their results with real control flow, and returns only what
matters.

**It is a tool that calls tools** — "the Cloudflare Code Mode move, done on
existing FoundationModels `Tool`s, in a way that feels native." These are **inline
Swift Tools**: live objects in your process. You register a `Tool` instance; the
snippet's `tools.foo({…})` becomes a **real Swift `tool.call(…)`**. This is *not*
MCP — no wire protocol, and the runtime call path is native Swift, not JSON-Schema
marshaling (the build-time doc renderer reads each tool's own `GenerationSchema`). The
tools are **black boxes from other packages**: we assume **no source access and no
ability to modify them**, only their public `Tool` protocol surface. Anything that
is already a `FoundationModels.Tool` drops in with `addTool(_:)` — hand-written
`@Generable` tools, and (because the sibling's `MCPTool` *is* a `Tool`) MCP-backed
tools too.

> Target: **OS 27+ only** (macOS 27 / iOS 27 and later). No back-deployment, **no
> `@available` branching, no degrade path** — matching the sibling
> `FoundationModelsMCP` plan so the two share a toolchain and a floor.

> Model: **via `FoundationModelsRouter`**, not Apple's built-in
> `SystemLanguageModel`. *Both* the main session and the librarian run on
> Router-selected (RAM-aware, MLX) open-weight models. So the built-in model's
> 4,096-token window — and `contextSize`/`tokenCount`/`.exceededContextWindowSize`
> — **do not apply**; context budgets are whatever the Router-selected models
> provide.

## Design principle: fuse many tools into one programmable surface

The conventional pattern puts every tool's schema in the model's instructions and
calls them one at a time, round-tripping each intermediate result through the
model's context. That is excellent for a handful of tools (it is exactly what the
sibling `FoundationModelsMCP` bridge does, with token-level argument guarantees).
It scales badly along three axes that a *code* surface fixes for free:

1. **Schema bloat.** N tool schemas in the instructions cost tokens, latency, and
   selection accuracy on *every* turn, whatever the window. The MultiTool puts
   **zero** tool schemas in the main session — only `runCode` + `findAPIs` — and
   keeps the derived API surface out in the interpreter and the librarian, so the
   cost is paid once, not per turn.
2. **Chaining overhead.** With one-tool-per-turn calling, every intermediate result
   is copied *through the model* to feed the next call. In a snippet, the model
   writes the pipeline once; intermediates **stay in the sandbox** and only the
   final return value re-enters the context.
3. **Composition.** Loops, conditionals, map/filter, error handling, fan-out over a
   list — free in a language, awkward-to-impossible as discrete tool calls.

This is the FoundationModels-native realization of **Cloudflare Code Mode** and
**Anthropic's "code execution with MCP"**, generalized over the `Tool` protocol.
Where the sibling project *surfaces* each tool (one constrained tool per
capability), the MultiTool **fuses** them into a single programmable surface. They
are duals on the same substrate, and they compose (below).

## Problem

FoundationModels gives you `LanguageModelSession(tools:)`. There is no shipping way
to hand the model a *set of in-process, black-box tools as a code API* — "here are
your tools as functions; write a program that calls them; I'll run it and give you
the result." Doing that, **without touching the tools' source**, requires three
pieces this package provides:

- a way to **turn each `Tool` into a documented function** purely from its public
  surface (`name`, `description`, `parameters: GenerationSchema`);
- a way to **invoke an `any Tool` whose `Arguments` type we cannot name** from a
  JS argument object — as a *native Swift call*; and
- **discovery**, so the model can find the right functions without the whole
  surface living in its working context.

All three are achievable against the public protocol — see Findings.

## The core: turning inline `Tool`s into an API surface

A FoundationModels `Tool` exposes everything we need **publicly**, with no source
access (Findings #1):

- `name` → the function name,
- `description` → the function's doc comment,
- `parameters: GenerationSchema` → the args shape — a native Swift value readable
  off `any Tool`,
- `Arguments: ConvertibleFromGeneratedContent` + `call(arguments:) async -> Output`
  → the function body (invoked via existential opening, Findings #2),
- `Output: PromptRepresentable` → the return value.

So the API surface is **derived, never hand-authored, and never requires the
tool's source.** Two transformations do the work — `ToolAPIRenderer` (declaration)
and `ToolInvoker` (the native call) — specified below because *this mapping is the
product*.

### `ToolAPIRenderer`: `Tool` → a typed, documented declaration ⭐

For each wrapped tool we emit a **TypeScript-style declaration with a JSDoc doc
comment** — the surface the model reads (in `findAPIs` results, `help()`/`docs()`,
and the librarian's prefix). It is purely *descriptive*; nothing here executes. It
is the human/LLM-facing description, exactly as Cloudflare Code Mode presents a
typed API.

**Schema source — encode → transliterate → capture comments.** Every tool exposes
`parameters: GenerationSchema`. The pipeline (confirmed against DocC JSON):
**encode the schema** (`GenerationSchema` is `Encodable` and is Apple's JSON-Schema
analog) → **transliterate that JSON to the TS signature** → **capture each field's
description/guide as the doc comment**. `GenerationSchema` has no field-enumeration
API, so encoding is the read path (`CustomDebugStringConvertible` is a fallback).
Build-time doc generation only; the runtime call path carries no schema (invocation
stays native; see `ToolInvoker`).

**Type mapping** (schema element → TypeScript type, for the rendered signature):

| Schema element | TS type | Notes |
|---|---|---|
| `object` + properties | `{ a: T; b?: U }` | required → `a`, optional → `b?` |
| `string` | `string` | |
| `integer` / `number` | `number` | integer vs. float noted in the doc comment |
| `boolean` | `boolean` | |
| `array<T>` | `T[]` | element type rendered recursively |
| `enum` / choice of constants | `"a" \| "b" \| "c"` | string/number literal union |
| nested `object` | inline `{ … }` (or a named `type` if reused) | |
| optional / nullable | `?` on the property; `\| null` only if nullable | |
| anything the schema can't express to us | `any` (widened) | **logged**, constraint moved into the doc text |

**Doc-comment mapping** — every constraint the model needs to call correctly
becomes prose, so the *type* stays clean and the *guidance* is explicit:

| Source on the tool | Rendered as |
|---|---|
| `tool.description` | the function's leading `/** … */` summary |
| per-property `description` / `@Guide` text | `@param args.<name> — <text>` |
| `enum` options | `@param … one of "a" \| "b" \| "c"` |
| numeric guide `minimum`/`maximum`/`range` | `@param … (range mn…mx)` |
| string guide `pattern` | `@param … (pattern: /…/ )` |
| array guide `minItems`/`maxItems`/`count` | `@param … (n…m items)` |
| default value | `@param … default <v>` |
| required vs. optional | optional params marked `(optional)` |
| `Output` shape (when known — see below) | `@returns <type> — <description>` |
| auto-generated usage | `@example const r = tools.weather({ city: "ATX" });` |

**Return-type handling.** `Output` is `PromptRepresentable`; its shape isn't always
schema-described (Findings #4): if `Output` is structured (`ToolOutput` wrapping
`GeneratedContent`, or a `@Generable` type) → render its TS type and hand the
snippet a JS **object**; otherwise (a plain text `ToolOutput`) → type it `string`
and document it in `@returns` prose.

**Worked example.** A `WeatherTool` whose `Arguments` is `{ city: String (required,
"IATA code or city name"); units: enum c|f (optional, default c) }` renders to:

```ts
/**
 * Current weather for a city.
 * @param args.city — IATA city code or city name.
 * @param args.units — temperature unit; one of "c" | "f". default "c". (optional)
 * @returns { tempC: number; summary: string } — current conditions.
 * @example const c = tools.weather({ city: "ATX" }).tempC;
 */
declare function weather(args: { city: string; units?: "c" | "f" }): { tempC: number; summary: string };
// callable in a snippet as tools.weather({ city: "ATX" })
```

The renderer's output is captured per tool as a `ToolDescriptor` (name, TS
declaration, doc text, example, source). The same descriptor feeds the **runtime
binding**, the **librarian prefix**, and **`help()`/`docs()`** — one generator, one
source of truth, never drifting.

**Object (named) parameters, always — never positional.** Every generated function
takes a *single object argument*, `tools.name({ field: … })`, mirroring the args
1:1: the model remembers field *names* (spelled out in the doc comment), not order;
optionals are simply omitted; the call site is self-documenting and is the form
most present in training data; and it maps cleanly onto the tool's `Arguments`.

**Completeness is a contract.** Every wrapped tool produces exactly one complete
declaration — summary, every parameter with its constraints, return type, runnable
`@example`. `Builder.build()` fails loudly if a tool can't be fully rendered rather
than emit a lossy stub; a golden-file test pins the rendered surface for a fixture
tool set (M2).

**This rendered surface *is* the agent's search context.** The librarian's prefix
is the concatenation of every tool's declaration block (doc + signature + example);
`findAPIs(task)` returns the matching subset verbatim; `help()`/`docs()` print the
same blocks. The signatures and doc comments aren't *also* generated for discovery
— they *are* discovery. *(Rendered as JSDoc `/** … */` with
`@param`/`@returns`/`@example`, the JS-native idiom; a compact `///` one-line form
is supported where brevity beats structured tags.)*

### `ToolInvoker`: a native call into a black-box `any Tool` ⭐

The hard part of "feels native on existing tools": we hold an `any Tool` and must
call it without naming its `Arguments` type. Swift's **implicit existential
opening** (SE-0352, Swift 5.7+) solves it — pass the existential into a generic that
binds the concrete type, so the whole thing stays a direct Swift call:

```
// conceptual — the existential opens into `T` at the call boundary
func invoke<T: Tool>(_ tool: T, jsArgs: JSValue) async throws -> T.Output {
    let args = try T.Arguments(makeGeneratedContent(from: jsArgs))   // ConvertibleFromGeneratedContent
    return try await tool.call(arguments: args)
}
```

So for `tools.weather({ city: "ATX" })` the interpreter:

1. **Marshals** the JS argument object → `GeneratedContent(properties:id:)` built
   natively from its key/values (no schema, no JSON string; `init(json:)` is an
   alternative).
2. **Validates** — `T.Arguments(content)` *throws* on type/shape mismatch (free
   validation); `ToolInvoker` adds guide checks (enum/range/count) for a precise
   pre-call error.
3. **Calls** `await tool.call(arguments:)` — a real Swift method call (blocking the
   JS thread per the v1 async policy; Resolved #1).
4. **Renders** `Output` → a JS value: a structured `Output`'s `GeneratedContent`
   has a `jsonString`, parsed into a JS object; a text `Output` becomes a string.
   Intermediates stay in the sandbox.

No source, no per-tool glue, no codegen, no JSON Schema — one generic invoker over
the public protocol. Validation/`call` errors become JS exceptions carrying the
message, which `ResultRenderer` turns into a repairable error for the model.

### The central tradeoff, stated honestly

When the model calls a tool *directly* (the sibling's path), constrained decoding
guarantees schema-valid arguments at the token level. Inside a snippet the
arguments are code the model wrote — **not** token-level constrained. We **lose
that guarantee at the in-snippet call boundary** and replace it with (a) validation
at each call site (`Arguments(content)` throws, plus guide checks) and (b) a
**repair loop** — the precise error goes back and the model fixes the call. Same
bargain as Code Mode / code-execution-with-MCP; the hard guarantee stays available
for any tool you place *directly* in the session.

## Adding tools is the easy path

```swift
let registry = try await MultiTool.Builder()
    .addTool(WeatherTool())                 // any FoundationModels.Tool — inline, black box, no source
    .addTool(thirdPartyToolFromSomePackage)
    .addTools(myToolArray)
    .add(server: githubMCPServer)           // sibling MCPServer → all its MCPTools, free
    .searchModel(.router(.default))         // librarian's model comes from FoundationModelsRouter
    .build()

// The MultiTool is itself a Tool. Add it (plus findAPIs) to a Router-backed session:
let session = LanguageModelSession(model: routerModel, multitool: registry, instructions: …)
// main session sees exactly two tools: runCode + findAPIs
```

`addTool` is generic over `T: Tool`, capturing the concrete type so `ToolInvoker`
can open it later — *inline* means the object and its type are known where you
register it, even though its source lives in another package. `add(server:)` is the
composition payoff: a sibling `MCPServer` vends `MCPTool`s, each a
`FoundationModels.Tool`, so it flows in with no special-casing.

**Multiple functions / grouping.** A FoundationModels `Tool` is exactly one
function (one `call`); multiplicity comes from the *number of tools you add*, never
from one tool having two `call`s. `add(server:)` / `addGroup(named:_:)` register
many at once and render them under a **namespace** — `tools.github.createIssue({…})`,
`tools.github.search({…})` — which organizes a many-function provider and resolves
name collisions across sources. A standalone tool stays flat at `tools.<name>`. A
single tool that multiplexes via an `op`-enum argument is still one function,
`tools.x({ op, … })`; the renderer shows `op` as a union and, when the schema is a
clean discriminated union, may expand it to `tools.x.<op>(…)`.

## Usage: attaching to a session

The MultiTool **is** a `Tool`. The `LanguageModelSession(multitool:)` convenience
attaches it (and wires the librarian) so the main session sees exactly two tools —
`runCode` + `findAPIs` — on a Router-backed model:

```swift
let routerModel = try await Router.shared.selectModel()      // FoundationModelsRouter
let session = LanguageModelSession(
    model: routerModel,
    multitool: registry,                                     // from the Builder above
    instructions: "You are a travel assistant. Use runCode to get things done."
)

let reply = try await session.respond(to: "Of the cities on my trip, which is warmest now?")
// "Austin (31°C)."
```

What the session's tool loop does behind that one call:

```
findAPIs({ task: "list trip cities, get weather for each" })
  └─ librarian → tools.tripCities(): string[]
                 tools.weather({ city: string; units?: "c"|"f" }): { tempC: number; summary: string }
runCode({ code: `
  const cities = tools.tripCities();
  const wx = cities.map(c => ({ c, t: tools.weather({ city: c }).tempC }));
  return wx.sort((a,b) => b.t - a.t)[0];
` })
  └─ fresh JSContext, each tools.X() → native Swift tool.call → returns { c: "Austin", t: 31 }
     (the per-city weather results never enter the model's context)
model → "Austin (31°C)."
```

**Direct mode (skip discovery).** For a small/fixed tool set, surface only `runCode`
and let the snippet introspect:

```swift
let session = LanguageModelSession(
    model: routerModel,
    multitool: registry.directMode(),    // only runCode; help()/docs() inside the snippet
    instructions: "Tools are documented via help(). Use runCode."
)
// in a snippet:  help() → ["tripCities","weather",…];  docs("weather") → signature + doc + example
```

**Elicitation works wrapped.** A tool that asks the user for input is just another
async tool: `tools.askUser({…})` inside a snippet suspends (the v1 blocking bridge)
until the user answers, then returns the structured value *into the program*, so the
model uses it in the same snippet — no extra round-trip. No special handling.

**Escape hatch — place a tool directly.** The one reason to compose a tool
*alongside* the MultiTool instead of wrapping it is to keep the **token-level arg
guarantee** (constrained decoding on its arguments):

```swift
let session = LanguageModelSession(
    model: routerModel,
    tools: [registry.runCodeTool, registry.findAPIsTool, ConfirmPaymentTool()],
    instructions: …
)
// ConfirmPaymentTool: model calls it directly (args constrained); everything else via runCode.
```

## Discovery: a prefix-cached "librarian" agent (Router model)

Discovery is agentic, mirroring the sibling's search. Both the main session and the
librarian run on **FoundationModelsRouter**-selected models; the librarian is a
*separate* session so the full generated surface stays out of the main session's
working context and can be served by a different Router model (e.g. cheaper or
larger-context) tuned for retrieval.

- The **librarian** is a separate, long-lived `LanguageModelSession` whose
  *instructions* are the full generated surface. If its prefix is reused across
  calls it stays cheap (prefix/KV reuse — a Router/MLX backend property to confirm,
  Findings #6), and the surface **never enters the main session**.
- `findAPIs(task:)` returns the few relevant tool-functions (constrained output:
  `{ function, signature, doc, example }`) for the main model to program against.
- Configured via `Builder.searchModel(_:)` — a Router preset (`.router(.default)`)
  or a custom `LanguageModelSession` builder given the candidate catalog (the
  sibling's `SearchAgent` shape).

Plus in-language `help()`/`docs()` globals backed by the same surface.

```
main LanguageModelSession   (Router model; sees only: runCode, findAPIs)
   │  findAPIs("for each city in my trip, get weather and pick the warmest")
   ▼
FindAPITool ─► librarian (Router model, full surface as its instruction prefix)
   │           └─► top-N { function, signature, doc, example }
   ▼
main model writes a snippet:
   runCode(`
     const cities = tools.tripCities();
     const wx = cities.map(c => ({ c, t: tools.weather({city: c}).tempC }));
     return wx.sort((a,b) => b.t - a.t)[0].c;
   `)
   ▼
MultiTool.call → Interpreter runs it, each tools.X() → native Swift tool.call
   │  intermediates stay in the sandbox; only the final value returns
   ▼
ResultRenderer ─► ToolOutput ─► back to the model
```

### The two tools, as the main model sees them

These two `description`s *are* the prompt that makes the model search-then-code —
fixed strings, not per-tool. This is the search affordance:

```
runCode(code: string)
  Run a JavaScript snippet against the available tools, exposed as functions under
  `tools.*`. Compose calls with normal code — variables, loops, map/filter — and
  `return` the final value (only that comes back; intermediates stay private).
  Call findAPIs first to learn exact signatures, or help()/docs(name) in-snippet.
  Errors are returned to you to fix and retry.

findAPIs(task: string)
  Describe, in plain language, what you are trying to accomplish. Returns the few
  tool-functions relevant to that task — each with its typed signature, purpose,
  and a runnable example — so you can write a runCode snippet. Prefer this over
  guessing function names.
```

`task` carries a `@Guide`: *"the goal in plain language, e.g. 'the warmest city on
my trip' — describe the outcome, not a function name."* This is the same two-verb
contract as Cloudflare Code Mode's `search()` + `execute()`.

### The librarian's assembled prompt (concrete)

`FindAPITool` forwards `task` to the librarian session, whose **instructions are the
cached prefix**: curated selection guidance + every tool's rendered block.

```
[instructions / cached prefix]
You are an API librarian. Given a task, return ONLY the functions needed — fewest
that suffice, in call order when order matters. Do not invent functions; return an
empty list if nothing fits.

# Available functions
/**
 * The cities on the user's current trip, in itinerary order.
 * @returns string[] — IATA city codes.
 * @example const cs = tools.tripCities();
 */
declare function tripCities(): string[];

/**
 * Current weather for a city. Use when the user asks how warm/cold/rainy it is now.
 * @param args.city — IATA city code or city name.
 * @param args.units — one of "c" | "f". default "c". (optional)
 * @returns { tempC: number; summary: string }
 * @example const c = tools.weather({ city: "ATX" }).tempC;
 */
declare function weather(args: { city: string; units?: "c" | "f" }): { tempC: number; summary: string };

… (calendar, convertCurrency, … every wrapped tool's block) …

[prompt for this call]
list the cities on my trip and get the current weather for each
```

The librarian runs under guided generation against a `@Generable` result, so the
pick is always well-formed:

```swift
@Generable struct FoundAPIs { var functions: [FoundAPI] }
@Generable struct FoundAPI { var name: String; var signature: String; var doc: String; var example: String }
```

Returned to the main session (note `calendar`/`convertCurrency` are in the prefix
but **not** selected, so they never reach the main context):

```json
{ "functions": [
  { "name": "tripCities", "signature": "tools.tripCities(): string[]",
    "doc": "The cities on the user's current trip.", "example": "const cs = tools.tripCities();" },
  { "name": "weather",
    "signature": "tools.weather(args: { city: string; units?: \"c\"|\"f\" }): { tempC: number; summary: string }",
    "doc": "Current weather for a city.", "example": "const c = tools.weather({ city: \"ATX\" }).tempC;" }
]}
```

### Describing tools so agents pick them

The librarian selects by *reasoning over* each rendered block, so discoverability is
a property of the `name` / `description` / `@Guide`s the tool author already writes —
we add no new metadata system, we surface those and lint for completeness (M2):

- **Description states purpose AND trigger** — "what it does" + "when you'd use it."
  The librarian matches the task's *intent*, so the trigger clause carries weight.
- **Name is a verb-y identifier the model would guess** (`weather`, `tripCities`),
  not an internal code (`wx_lookup_v2`).
- **Every parameter has a `@Guide`** — these become the `@param` lines; an
  undocumented param is one the model fills in blind.
- **Enums/ranges live in `@Guide`** so they render as `"c"|"f"` / `(range 1…10)`
  instead of a bare `string`/`number`.

```
✗ name "lookup"   desc "Returns data."   → librarian can't tell when to pick it
✓ name "weather"  desc "Current weather for a city. Use when the user asks how
                        warm/cold/rainy it is now."   → reliably selected
```

## Interpreter engine: JavaScriptCore (with a swappable seam)

**Decision: JavaScriptCore (JSC), behind an `Interpreter` protocol.** The snippet is
orchestration glue (call functions, munge results, control flow) over values that
marshal to/from the tools' `Arguments`/`Output`. JSC fits exactly: JSON-native, a
clean deny-by-default sandbox (a fresh `JSContext` reaches nothing we don't inject —
only `tools.*`, `console`, `JSON`, `help`/`docs`), zero dependency, iOS-legal
(interpreter mode; JIT is gated to system processes), and JS is the most
LLM-trained language. A Swift tree-walking interpreter (SwiftScript /
SwiftlyInterpreter) was evaluated and set aside: its edge is an auto-generated
Foundation bridge, irrelevant here because we expose only the wrapped tools, while
its costs (pre-release maturity, language gaps) remain.

**Async (Resolved #1).** Each `tools.X()` `await`s a tool `call`; JSC is
synchronous. v1 runs the interpreter **off the main thread** and **blocks the JS
thread on a semaphore** per call while the async `call` runs on the cooperative
pool — the standard JSContext bridging pattern, safe under stateless snippets. A
JSC microtask/promise pump exposing real `async`/`await` and **parallel tool
fan-out** (`Promise.all`) is a later upgrade.

**Execution limits (Resolved #2).** Runaway loops are bounded by
`JSContextGroupSetExecutionTimeLimit` + a `JSShouldTerminateCallback` watchdog.
Caveat: that symbol is `JS_EXPORT` but declared in `JSContextRefPrivate.h`, **not
in the public SDK header set** — we declare the extern ourselves (a stable,
long-exported symbol; low-but-nonzero review risk). Fallback: run JS on a dedicated
thread and abandon the context on timeout, or instrument loop back-edges. Plus an
output-size cap.

## State: stateless snippets

Each `runCode` gets a **fresh `JSContext`** — no shared state between calls, which
keeps the blocking async bridge safe and behavior predictable. A persistent context
+ a Voyager/Anthropic-"skills" reusable-function library is a v2 mode (Resolved #7),
not a default.

## Output: intermediates stay in the sandbox

Only the snippet's `return` value (JSON-serialized) and captured `console.log` come
back. `ResultRenderer` (the analogue of the sibling's `ToolContentRenderer`):
serialize the return with a **size cap + truncation note** (so a fat tool result
can't flood the model), append capped console output, and on failure render the
JS/validation exception as a repairable error.

## Components

⭐ marks the value-add (touches FoundationModels types or the interpreter core).

1. **`MultiTool`** ⭐ — the `runCode` `Tool`. Holds the wrapped `[any Tool]`; builds
   a fresh interpreter with each tool installed as `tools.<name>`; runs the snippet;
   renders via `ResultRenderer`. *Is itself a `Tool`.*
2. **`MultiTool.Builder`** — `addTool(_:)` / `addTools(_:)` / `addGroup(named:_:)` /
   `add(server:)` / `searchModel(_:)`. The easy contribution path; black-box tools
   only. Grouped/server tools render under a `tools.<group>.<name>` namespace.
3. **`ToolAPIRenderer`** ⭐ — encodes a `GenerationSchema` (Apple's JSON-Schema
   analog) → typed signature + doc comment.
4. **`ArgumentMarshaler`** ⭐ — JS value → `GeneratedContent` (content, not schema),
   and `Output` → JS value.
5. **`ToolInvoker`** ⭐ — generic existential-opening invoker: marshal → validate →
   native `call` → render. The no-source invocation core.
6. **`Interpreter`** (protocol) + **`JSCInterpreter`** ⭐ — fresh context, std
   surface, install `tools.*`, run under a time limit, capture return + console, map
   exceptions. Unit-testable without the model.
7. **`APISurface`** — the rendered catalog; backs the librarian prefix,
   `help()`/`docs()`, and a host-UI listing (plain data, no UI code).
8. **`FindAPITool`** ⭐ + **`Librarian`** — discovery over `APISurface` on a
   Router-selected model.
9. **`ResultRenderer`** ⭐ — return + console → `ToolOutput`; size/trim; exception →
   repairable error.

## Milestones

- [ ] **M0 — Scaffold.** SwiftPM library + executable sample (CLI). Depend on
  `FoundationModels`, `JavaScriptCore`, and **FoundationModelsRouter**. OS 27 floor,
  no `@available`. CI on macOS with the OS-27 SDK.
- [ ] **M1 — Interpreter core.** `Interpreter` + `JSCInterpreter`: fresh `JSContext`,
  std surface, `run(code)` under the time-limit watchdog, capture return + console,
  map exceptions. No model needed.
- [ ] **M2 — `ToolAPIRenderer`.** Encode a `GenerationSchema` → transliterate the
  JSON Schema to a typed signature + doc. Table-driven + golden-file tests over a
  schema corpus. (Encoded shape known — Findings #3.)
- [ ] **M3 — `ArgumentMarshaler` + `ToolInvoker`.** JS value ⇄ `GeneratedContent`;
  existential opening over a mock `Tool`; validate; render `Output` to a JS value.
  **Pin: the exact `Output` read-back (Findings #4).**
- [ ] **M4 — `MultiTool` end-to-end.** Wrap **two real third-party-style `@Generable`
  tools** (no source modification), install `tools.*`, drive a real
  `LanguageModelSession` that composes their results in one snippet.
- [ ] **M5 — `ResultRenderer` + repair loop.** Serialize/cap/trim; repairable
  errors; verify the model fixes a bad tool call from the error.
- [ ] **M6 — Librarian + `findAPIs` on Router.** `FindAPITool` + librarian on a
  Router-selected model; constrained output; confirm the MLX backend reuses the
  instruction-prefix KV cache across `findAPIs` calls.
- [ ] **M7 — In-JS `help()` / `docs()`.**
- [ ] **M8 — Sibling integration.** `Builder.add(server:)` consuming a
  `FoundationModelsMCP` `MCPServer` — "Code Mode over MCP," end-to-end.
- [ ] **M9 — Sample CLI.** A prompt that triggers `findAPIs` then a multi-tool
  `runCode`.
- [ ] **M10 — Hardening.** Limits tuned; async-bridge policy; cancellation; logging;
  written security model (a snippet reaches *only* the wrapped tools).

## Testing strategy

- **Interpreter** (M1): return, console, exception mapping, timeout. No model.
- **`ToolAPIRenderer`** (M2): table-driven + golden-file over a `GenerationSchema`
  corpus.
- **Marshaler + `ToolInvoker`** (M3): round-trips; existential opening over a mock
  `Tool` that records the marshaled `GeneratedContent`; validation pass/fail.
- **`ResultRenderer`** (M5): caps, truncation, exception → error.
- **E2E** (M4/M6/M8/M9): gated/optional, needs the model (Router) on real hardware.

## Findings (research)

1. **`Tool` is introspectable as a black box.** The protocol publicly exposes
   `name`, `description`, **`parameters: GenerationSchema`**, and
   `includesSchemaInInstructions: Bool`; `Arguments: ConvertibleFromGeneratedContent`,
   `Output: PromptRepresentable`, `call(arguments:) async throws -> Output`. The
   renderer reads `tool.parameters` with **no source access**.
2. **Invoking `any Tool` with no source is solved by the language.** Swift's
   implicit existential opening (SE-0352, 5.7+) lets a generic `invoke<T: Tool>`
   build `T.Arguments` from a `GeneratedContent` and call it without naming the type
   — the mechanism behind `ToolInvoker`. ✅
3. **`GenerationSchema` encodes to *standard JSON Schema* — shape confirmed.** It's
   `Encodable`/`Decodable`; `JSONEncoder().encode(schema)` emits plain JSON Schema
   and round-trips via `JSONDecoder().decode(GenerationSchema.self, …)`. Confirmed
   shape (OpenFoundationModels, the API-compatible reimpl, + its tests): struct →
   `{"type":"object","properties":{…},"required":[…]}`; field →
   `{"type":"string"|"integer"|"number"|"boolean","description":…}`; optional →
   `{"type":["boolean","null"]}` and dropped from `required`; enum →
   `{"type":"string","enum":[…]}`. So the renderer reads `tool.parameters`, encodes,
   and transliterates that JSON straight into the TS+JSDoc surface — the type-mapping
   table above is 1:1 with this shape. (No field-enumeration API, so encode is the
   read path; build-time only.)
4. **Marshaling both directions is confirmed (DocC JSON).** `GeneratedContent` has
   `init(properties:id:)` (build natively from key/values — args in, no JSON string),
   `init(json:)`, a **`jsonString`** property (results out → JS via `JSON.parse`),
   plus `value(_:forProperty:)`/`properties()`. Minor pin: `ToolOutput`'s accessor
   for its underlying `GeneratedContent` (its DocC page 404'd) — worst case, render
   `Output` via `PromptRepresentable` text.
5. **No built-in model, so no 4K limit.** The 4,096-token `SystemLanguageModel`
   window (and `contextSize`/`tokenCount`/`.exceededContextWindowSize`) is a
   *built-in-model* property and **does not apply** — all sessions run on
   `FoundationModelsRouter`-selected MLX models with their own (generally larger)
   windows. Keeping schemas out of the main session is still worth it for token
   cost, latency, and selection accuracy, not because of a hard cap.
6. **Prefix reuse is a Router/MLX property, not Apple `prewarm()`.** The librarian's
   stable instruction prefix is cheap only if the MLX backend reuses its KV cache
   across turns of one reused session. Apple's `prewarm()`/transcript-diffing is for
   the built-in model, which we don't use — so treat librarian prefix reuse as a
   **Router/MLX capability to confirm**, not a given.
7. **FoundationModelsRouter is the model source for everything (per the user).** Both
   the main session and the librarian use Router-selected (RAM-aware, MLX) models — a
   hard dependency. Single backend, not the sibling's built-in/MLX split; Router also
   owns xgrammar, available for constraining `findAPIs` output.

## Resolved open questions

- **#1 Async — block in v1.** Interpreter off the main thread; each `tools.X()`
  blocks the JS thread on a semaphore while `call` runs on the cooperative pool.
  Parallel fan-out via a JSC promise pump is a later upgrade.
- **#2 Execution limits.** `JSContextGroupSetExecutionTimeLimit` watchdog
  (extern-declared; low review risk) + output-size cap; documented fallbacks.
- **#3 `Output` → script value.** Structured `Output` → JS object; else string. Exact
  read-back pinned at M3.
- **#4 Arg validation.** Lean on `Arguments(content)` throwing (free) + guide checks;
  precise, repairable errors. Narrow coercions only if the model trips often.
- **#5 Namespacing, grouping & collisions.** A `Tool` is one function. Standalone
  tools live at `tools.<name>`; a *group* (an `MCPServer`, or `addGroup(named:)`)
  renders under `tools.<group>.<name>` — organizing many-function providers and
  resolving duplicate names across sources. A single tool multiplexing via an
  `op`-enum is one function (`tools.x({ op, … })`), optionally expanded to
  `tools.x.<op>(…)` for a clean discriminated union. `help()` shows the layout.
- **#6 Librarian capacity.** Librarian on a Router model; budget against *that
  model's* window (not the built-in 4K). If a surface exceeds it, lexical pre-filter
  the candidates before seeding and **log** the cut (mirrors the sibling's M8).
- **#7 State across calls — deferred (v2).** Stateless by default; persistent
  context + skill library is a future mode.
- **#8 Direct placement (escape hatch).** The *only* reason to place a tool
  directly rather than wrap it is to keep the **token-level arg guarantee**
  (constrained decoding on its arguments) — or a deliberate policy to force the
  model to call it explicitly. **Elicitation needs no exception:** a wrapped
  `tools.askUser({…})` suspends mid-snippet (the async bridge) until the user
  answers and returns the structured value into the program — better wrapped, since
  the model uses the answer in the same snippet without a round-trip.

### Remaining pins (require the compiled SDK)

- **Apple-encoder parity** (Finding #3) — the encoded JSON-Schema shape is known
  from the API-compatible reimpl + the round-trip usage pattern; confirm Apple's own
  encoder matches it. Low risk.
- **`ToolOutput` → `GeneratedContent` accessor** (Finding #4) — its DocC page 404'd.
- **`JSContextGroupSetExecutionTimeLimit`** header availability / review posture —
  confirm extern-declare under the OS-27 SDK; fallback ready.
- **Router interop & prefix reuse** — which Router entry point backs the main and
  librarian `LanguageModelSession`s (the sibling's M10 Path A/B), and whether the MLX
  backend reuses the librarian's instruction-prefix KV cache (Finding #6).

## Prior art

- **Cloudflare "Code Mode"** — convert a tool surface into a typed API and let the
  model write code against it in a V8 isolate; exposes **`search()` + `execute()`**
  (validates `findAPIs` + `runCode`); ~1.17M tokens of tool defs → ~1,000. The
  thesis — models write better code than bespoke tool-call JSON — is this design's
  foundation. ([blog](https://blog.cloudflare.com/code-mode/),
  ["…an API in 1,000 tokens"](https://blog.cloudflare.com/code-mode-mcp/),
  [docs](https://developers.cloudflare.com/agents/api-reference/codemode/))
- **Anthropic "Code execution with MCP"** (Adam Jones, Conor Kelly) — present servers
  as code APIs; load only needed tools; process data in the execution environment;
  return only final results. Validates progressive disclosure (librarian) and
  intermediates-stay-in-sandbox (`ResultRenderer`).
  ([engineering blog](https://www.anthropic.com/engineering/code-execution-with-mcp))
- **`smolagents` `CodeAgent`** + **CodeAct** (Wang et al., 2024,
  [arXiv](https://arxiv.org/abs/2402.01030)) — code as the action space beats JSON
  actions on multi-step tasks.
- **`FoundationModelsMCP`** (sibling) — the per-tool MCP bridge. We reuse its
  agentic-search, `Builder`/provider, and UI-catalog patterns; its `MCPTool`s are
  `Tool`s the MultiTool can wrap. The schema-constrained complement to this
  code-surface approach.
- **`FoundationModelsRouter`** (sibling-of-sibling) — RAM-aware MLX model selection +
  xgrammar engine; supplies the models for both sessions here.

## References

- FoundationModels `Tool` — https://developer.apple.com/documentation/foundationmodels/tool ·
  Output — https://developer.apple.com/documentation/foundationmodels/tool/output ·
  tool-calling guide — https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling
- `GenerationSchema` — https://developer.apple.com/documentation/foundationmodels/generationschema
- `GeneratedContent.init(json:)` — https://developer.apple.com/documentation/foundationmodels/generatedcontent/init(json:)
- Managing the context window (background; built-in model) —
  https://developer.apple.com/documentation/foundationmodels/managing-the-context-window
- Implicit existential opening (SE-0352) — https://github.com/swiftlang/swift-evolution/blob/main/proposals/0352-implicit-open-existentials.md
- JavaScriptCore — https://developer.apple.com/documentation/javascriptcore ·
  `JSContextGroupSetExecutionTimeLimit` (in `JSContextRefPrivate.h`, `JS_EXPORT`) —
  https://github.com/WebKit/WebKit/blob/main/Source/JavaScriptCore/API/JSContextRefPrivate.h
- iOS JIT restriction (why JSC is interpreter-mode in 3rd-party apps) —
  https://developer.apple.com/documentation/BundleResources/Entitlements/com.apple.security.cs.allow-jit
- Cloudflare Code Mode — https://blog.cloudflare.com/code-mode/ · https://blog.cloudflare.com/code-mode-mcp/
- Anthropic, Code execution with MCP — https://www.anthropic.com/engineering/code-execution-with-mcp
- CodeAct — https://arxiv.org/abs/2402.01030
- Swift tree-walking interpreters (evaluated, set aside) —
  https://github.com/Cocoanetics/SwiftScript · https://github.com/ForestP/SwiftlyInterpreter
- Sibling plans — ../FoundationModelsMCP/plan.md · ../FoundationModelsRouter
