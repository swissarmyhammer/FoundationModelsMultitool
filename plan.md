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
is already a `FoundationModels.Tool` drops in with `addTool(_:)`. (MCP-backed tools
would also just be `Tool`s, so they could drop in the same way — but wiring MCP up
is out of v1 scope; see M8.)

> Target: **OS 27+ only** (macOS 27 / iOS 27 and later). No back-deployment, **no
> `@available` branching, no degrade path** — matching the sibling
> `FoundationModelsMCP` plan so the two share a toolchain and a floor.

> Model: **via the `FoundationModelsRouter` package**
> (`github.com/swissarmyhammer/FoundationModelsRouter`, a SwiftPM dependency), not
> Apple's built-in `SystemLanguageModel`. *Both* the main session's model and the
> discovery selection tier run on Router-resolved (RAM-aware, MLX) open-weight models. So the built-in
> model's 4,096-token window — and
> `contextSize`/`tokenCount`/`.exceededContextWindowSize` — **do not apply**;
> context budgets are whatever the resolved models provide.
>
> Consequence — the single most important integration fact, detailed under
> **Router integration** below: the Router vends its *own* `RoutedSession`
> (`respond(to:) async throws -> String` + guided generation), **not** Apple's
> `LanguageModelSession`, and it has **no built-in tool-calling loop** — the
> Router provides models and sessions, never an agent loop. The *main* loop is
> nevertheless Apple's real native tool-calling: `MLXFoundationModels`'s
> `MLXLanguageModel` wraps the Router-resolved model as a genuine
> `FoundationModels.LanguageModel` declaring `.toolCalling`, so `multiTool` and
> `findAPIsTool` register directly on a native `LanguageModelSession(tools:)`
> and Apple's own loop dispatches `runCode`/`findAPIs`. (This package originally
> hand-rolled its own agent loop over a `RoutedSession` on the assumption no
> native path existed — see **Router integration** for that history and why the
> loop was retired.) Conforming wrapped tools (and the MultiTool) to
> `FoundationModels.Tool` is therefore load-bearing twice over: it is how
> black-box tools are introspected, and it is what lets `multiTool` and
> `findAPIsTool` register on the native session at all.

## Design principle: fuse many tools into one programmable surface

The conventional pattern puts every tool's schema in the model's instructions and
calls them one at a time, round-tripping each intermediate result through the
model's context. That is excellent for a handful of tools (it is exactly what the
sibling `FoundationModelsMCP` bridge does, with token-level argument guarantees).
It scales badly along three axes that a *code* surface fixes for free:

1. **Schema bloat.** N tool schemas in the instructions cost tokens, latency, and
   selection accuracy on *every* turn, whatever the window. The MultiTool puts
   **zero** tool schemas in the main session — only `runCode` + `findAPIs` — and
   keeps the derived API surface out in the interpreter and the discovery tier,
   so the cost is paid once, not per turn.
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
and the selection tier's prefix). It is purely *descriptive*; nothing here executes. It
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
| auto-generated usage | `@example const r = tools.getWeather({ city: "ATX" });` |

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
 * @example const c = tools.getWeather({ city: "ATX" }).tempC;
 */
declare function getWeather(args: { city: string; units?: "c" | "f" }): { tempC: number; summary: string };
// callable in a snippet as tools.getWeather({ city: "ATX" })
```

The renderer's output is captured per tool as a `ToolDescriptor` (name, TS
declaration, doc text, example, source). The same descriptor feeds the **runtime
binding**, the **selection tier's prefix**, and **`help()`/`docs()`** — one
generator, one source of truth, never drifting.

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

**This rendered surface *is* the model's search context.** The selection tier's
prefix is the concatenation of every tool's declaration block (doc + signature +
example);
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

So for `tools.getWeather({ city: "ATX" })` the interpreter:

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
// 1. Collect the tools. The Builder is a pure catalog — no model wiring here.
let registry = try MultiTool.Builder()
    .addTool(WeatherTool())                 // any FoundationModels.Tool — inline, black box, no source
    .addTool(thirdPartyToolFromSomePackage)
    .addTools(myToolArray)
    .addGroup(named: "github", githubTools) // many Tools under one namespace
    .buildRegistry()                        // rendered surface + live tools; still model-agnostic

// 2. Resolve one Router profile for THIS machine (RAM-aware). Router hands back a
//    LanguageModelProfile with standard/flash/embedding RoutedLLM handles — models,
//    never a tool-calling loop.
let router  = Router()                                          // FoundationModelsRouter, an actor
let profile = try await router.resolve(profile: travelProfile, reporting: progress)   // ProfileDefinition → LanguageModelProfile

// 3. Mount the registry's own tools on a native LanguageModelSession over the resolved
//    standard slot, wrapped as an MLXLanguageModel (Router integration below). findAPIs's
//    own selection tier runs on the same profile's cheaper/faster flash slot.
//    makeSessionTools orders the pair: findAPIs first, then runCode.
let session = LanguageModelSession(
    model: mlxModel,                        // MLXLanguageModel over profile.standard
    tools: try registry.makeSessionTools(librarian: profile.flash),
    instructions: "You are a travel assistant. Use runCode to get things done."
)
// The session surfaces exactly two operations to the model: runCode + findAPIs.
```

`addTool` is generic over `T: Tool`, capturing the concrete type so `ToolInvoker`
can open it later — *inline* means the object and its type are known where you
register it, even though its source lives in another package. `addGroup(named:_:)`
takes an array of `Tool`s and namespaces them (below). Everything the MultiTool
accepts is a `FoundationModels.Tool` — nothing else. **Model wiring is separate
from tool collection**: the `Builder` produces a model-agnostic catalog; the
native `LanguageModelSession` — built over a Router-resolved model — is where
that catalog meets a model (see **Router integration**).

**Multiple functions / grouping.** A FoundationModels `Tool` is exactly one
function (one `call`); multiplicity comes from the *number of tools you add*, never
from one tool having two `call`s. `addGroup(named:_:)` takes many `Tool`s at once
and renders them under a **namespace** — `tools.github.createIssue({…})`,
`tools.github.search({…})` — organizing a related set and resolving name
collisions. A standalone tool stays flat at `tools.<name>`. A single tool that
multiplexes via an `op`-enum argument is still one function, `tools.x({ op, … })`;
the renderer shows `op` as a union and, when the schema is a clean discriminated
union, may expand it to `tools.x.<op>(…)`. (An MCP server is one such *source* of
many tools — but it's not itself a `Tool`; converting it is deferred, M8.)

## Router integration (the real API surface)

The `FoundationModelsRouter` package does **not** expose Apple's
`LanguageModelSession`, does **not** use `SystemLanguageModel`, and has **no
tool-calling loop**. Confirmed against the package source, its surface is:

- **`Router`** — an `actor` (not a shared singleton). You construct one and call
  `resolve(_ def: ProfileDefinition, reporting: ResolutionProgress) async throws ->
  LanguageModelProfile`. One profile is resident at a time (RAM budget); release
  before resolving another.
- **`ProfileDefinition`** — an authored, value-type profile: `name`, `description`,
  candidate `[ModelRef]` lists for the `standard`/`flash`/`embedding` slots (in
  preference order), and a `context` token budget (default 8192). Resolution picks,
  per slot, the first candidate that co-fits this machine's budget.
- **`LanguageModelProfile`** — the resolved handle set: `.standard` and `.flash`
  are `RoutedLLM`, `.embedding` is a `RoutedEmbedder`; `release()` evicts them. The
  two generation slots share one resident profile — you do **not** get two
  independently-selected models, you get one profile with a stronger `standard`
  slot and a cheaper/faster `flash` slot.
- **`RoutedLLM.makeSession(instructions:workingDirectory:) -> RoutedSession`** and
  **`makeGuidedSession(_ grammar:instructions:workingDirectory:)`** vend sessions.
- **`RoutedSession`** — an `actor` protocol with `respond(to:) async throws ->
  String`, `streamResponse(to:) -> AsyncThrowingStream<String, Error>`, and
  `fork(workingDirectory:)`. **No `tools:` parameter, no automatic tool loop.**
- **Guided generation** on `RoutedLLM` (xgrammar): `respond(to:following: Grammar)`
  → raw constrained text; `respond(to:matching jsonSchema:) -> JSONValue`; and,
  where `FoundationModels` is available, **`respond<T: Generable>(to:generating:
  T.Type) -> T`** — constrained *and decoded* into a `@Generable` type.
- **Live inference is gated.** Until the Router's own milestone 7, the live MLX
  decode path throws `GenerationError.notWiredForLiveInference`; the unit suite
  runs against stub containers. So *our* real-model tests are likewise gated (see
  **Integration tests**), and depend on the Router's live path landing.

### The main loop is Apple's native tool-calling (history: the hand-rolled loop)

**Current design.** The Router provides models and sessions — never a
tool-calling loop — and the main loop is Apple's own. `MLXFoundationModels`'s
`MLXLanguageModel` wraps the Router-resolved `profile.standard` slot as a real
`FoundationModels.LanguageModel` declaring `.toolCalling` (and
`.guidedGeneration`), built over the same resident weights the Router already
loaded. A **native `LanguageModelSession` over
`registry.makeSessionTools(librarian:)`** — `findAPIs` presented before
`runCode` — lets Apple's own token-level tool-calling loop decide when to
call `findAPIs` vs `runCode`; this package drives no turn loop of its own.
The production wiring is `Sources/multitool-cli/CLIRunner.swift`
(`makeMLXLanguageModel(for:)` + `runDemo`, which passes no session
instructions at all); the offline call-pattern reference is
`Tests/FoundationModelsMultitoolTests/ExamplesTests.swift`. Router-backed
`RoutedSession`s remain in exactly one place — `findAPIsTool`'s internal
selection tier (see **Discovery** below), which needs the Router's cache-level
`fork()` primitive the FoundationModels interop path doesn't expose.

**History — the loop this replaced.** The original plan concluded "the agent
loop is ours to build": the Router has no tool loop, the built-in
`SystemLanguageModel` wasn't the model source, and no path from a Router model
to Apple's native loop was believed to exist. So M4 hand-rolled
`MultiToolAgent`, a ReAct-style loop over a `RoutedSession` on
`profile.standard`:

```
loop:                                            // RETIRED — kept for the record
  raw = session.respond(to: turnPrompt)          // Router RoutedSession, plain text
  parse a tool call out of `raw`  ── runCode / findAPIs / final answer
    · findAPIs(task)  → ask the librarian (guided), splice the returned blocks in
    · runCode(code)   → JSCInterpreter runs it; tools.X() → native Swift tool.call
    · final           → return to the caller
  feed the tool result back as the next turn; repeat
```

It had two turn formats, both Router-native — **guided turns** (a `@Generable`
union of `{ findAPIs(task) | runCode(code) | final(text) }` via
`respond(to:generating:)`, parseable by construction) and a **prompted
ReAct-style convention with a tolerant parse** plus bounded repair turns — and
both were green in unit tests. On real hardware, neither held up: the gated
integration suite (documented on archived task `exbtj1n`) showed the
hand-rolled loop was **unreliable regardless of model size** — under guided
turns the model intermittently left the `kind`-matching field blank (xgrammar
cannot express a conditionally-required field), under tolerant parse it
rambled past token budgets before emitting a final action, and snippets
sometimes hardcoded plausible answers instead of calling the discovered
`tools.*` functions. `MLXLanguageModel`'s FoundationModels interop (once its
multi-turn tool-calling fix landed upstream) provided the better-founded
mechanism: the native loop Apple ships, driving the same Router-resolved
weights, with real token-level tool-call generation instead of a
parse-what-the-model-typed convention. `MultiToolAgent` — its turn grammar,
tolerant parser, repair budget, and `maxAgentTurns`/`maxRepairTurns` knobs —
was deleted in its favor. The pivot was a rewiring, not a rewrite: the Router
stayed loop-free as designed, and `multiTool`/`findAPIsTool` were already
`FoundationModels.Tool` conformers, so they registered on the native session
unchanged. The `runCode`/`findAPIs` *descriptions* (below) remain the fixed
instruction that teaches the search-then-code behavior.

## Usage: attaching to a session

The MultiTool and `FindAPIsTool` are ordinary `FoundationModels.Tool`
conformers, so attaching is native: register both on a `LanguageModelSession`
over the Router-resolved model, and Apple's own tool-calling loop surfaces
exactly two operations — `runCode` + `findAPIs` — to the model (mirroring
`CLIRunner.runDemo`, the shipped production wiring):

```swift
let router  = Router()
let profile = try await router.resolve(profile: travelProfile, reporting: progress)   // FoundationModelsRouter

let mlxModel = makeMLXLanguageModel(for: profile.standard)   // MLXLanguageModel: .toolCalling over the resident weights
let session  = LanguageModelSession(
    model: mlxModel,
    tools: try registry.makeSessionTools(librarian: profile.flash),   // findAPIs, then runCode
    instructions: "You are a travel assistant. Use runCode to get things done."
)

let reply: LanguageModelSession.Response<String> =
    try await session.respond(to: "Of the cities on my trip, which is warmest now?")
// "Austin (31°C)."
```

What the native tool-calling loop does behind that one call:

```
findAPIs({ task: "list trip cities, get weather for each" })
  └─ selection tier (profile.flash, guided, fork-per-call) → tools.getTrip(): { cities: string[] }
                 tools.getWeather({ city: string; units?: "c"|"f" }): { tempC: number; summary: string }
runCode({ code: `
  const cities = tools.getTrip().cities;
  const wx = cities.map(c => ({ c, t: tools.getWeather({ city: c }).tempC }));
  return wx.sort((a,b) => b.t - a.t)[0];
` })
  └─ fresh JSContext, each tools.X() → native Swift tool.call → returns { c: "Austin", t: 31 }
     (the per-city weather results never enter the model's context)
model → "Austin (31°C)."
```

**Direct mode (skip discovery).** For a small/fixed tool set, register only
`runCode` and let the snippet introspect:

```swift
let session = LanguageModelSession(
    model: mlxModel,
    tools: [MultiTool(registry: registry.directMode())],  // only runCode; help()/docs() inside the snippet
    instructions: "Tools are documented via help(). Use runCode."
)
// in a snippet:  help() → ["getTrip","getWeather",…];  docs("getWeather") → signature + doc + example
```

**Elicitation works wrapped.** A tool that asks the user for input is just another
async tool: `tools.askUser({…})` inside a snippet suspends (the v1 blocking bridge)
until the user answers, then returns the structured value *into the program*, so the
model uses it in the same snippet — no extra round-trip. No special handling.

**Escape hatch — keep the schema-valid-args guarantee.** The one reason to *not*
wrap a tool as in-snippet code is to keep a hard argument guarantee. The main
session *is* Apple's native tool-calling loop, so the escape hatch is simply to
register that one tool as its own separate `Tool` alongside `multiTool` and
`findAPIsTool` — native tool-calling generates its arguments against the tool's
own `parameters: GenerationSchema`, instead of the model authoring them as
ordinary code inside a snippet (see `docs/SECURITY.md`, "What is NOT
guaranteed").

## Discovery: `findAPIs` and its prefix-cached selection tier (Router `flash` slot)

Discovery is `FindAPIsTool` — `findAPIs` as its own real `FoundationModels
.Tool`, registered on the native session alongside `multiTool` (Component 8).
The main session runs on the profile's `standard` slot; discovery's
**selection tier** — the model-backed "librarian" role, still literally named
`librarian:` in `FindAPIsTool(registry:librarian:)` — runs on the **same
resolved profile's `flash` slot**, the cheaper/faster generation model of the
one resident profile, as separate Router-backed sessions, so the full
generated surface stays out of the main session's working context.

Internally, every `findAPIs(task)` call forwards to a
`MetadataSearcher<APISurface.Entry>` (from the extracted
[`FoundationModelsMetadataRegistry`](../FoundationModelsMetadataRegistry/plan.md)
package) running in `.auto` mode:

- **Retrieval always runs.** Ranked hybrid retrieval (BM25 + trigram + cosine,
  fused by RRF) narrows the catalog to candidates — no model call, no tokens.
  With no `librarian` configured, `.auto` degrades to retrieval alone.
- **Selection runs when a `librarian: RoutedLLM` is configured** (typically
  `profile.flash`): the registry's `SelectionTier` asks that model *which*
  candidates are relevant. Its answer is **ids only**, xgrammar-constrained to
  the candidate id enum (`idEnumGrammar(ids:)`) — the model cannot invent a
  function and never re-types a signature.
- `FindAPIsTool` then splices each selected entry's rendered block **verbatim
  from the surface** (`Match.item.block`, plus its runnable,
  namespace-qualified example) into the tool output the main model reads.

**Prefix reuse maps to a concrete Router primitive — which is why this tier
stays Router-backed.** The selection tier's sessions come from
`profile.flash.makeGuidedSession(grammar:instructions:)` with the rendered
surface as the instruction prefix. Per `SelectionConfig`'s cached-root/
fork-per-call contract, each `findAPIs` call forks the prefilled root —
`RoutedSession.fork(workingDirectory:)` seeds the child from a *copy* of the
parent's prefilled KV cache (`SessionKVCache.copy()`) — so it inherits the
prefix compute and diverges, rather than re-prefilling the surface each time
(Findings #6). The FoundationModels interop path (`MLXLanguageModel`) doesn't
expose the Router's cache-level `fork()`, so the selection tier is the one
place `RoutedSession`s remain in the design. The surface **never enters the
main session's context**.

Plus in-language `help()`/`docs()` globals backed by the same surface.

> **History.** Discovery was originally designed as a "librarian" *agent* — a
> long-lived `RoutedSession` invoked from the hand-rolled `MultiToolAgent`
> loop, returning `{ function, signature, doc, example }` records the model
> re-typed under guided generation. Its planned extraction into
> [`../FoundationModelsMetadataRegistry`](../FoundationModelsMetadataRegistry/plan.md)
> landed as designed: `Librarian` became `MetadataSearcher<APISurface.Entry>`
> + `SelectionTier`, the guided output became ids-only (with
> `signature`/`doc`/`example` looked up verbatim from the surface), and the
> over-budget `lexicallyFilter` keep/drop became ranked hybrid retrieval.
> When `MultiToolAgent` was later retired (see **Router integration**),
> `findAPIs` survived unchanged in substance — it simply became its own
> `Tool` on the native session rather than a branch of a hand-rolled loop.

```
main session   (native LanguageModelSession over MLXLanguageModel(profile.standard);
   │            sees only: runCode, findAPIs)
   │  findAPIs("for each city in my trip, get weather and pick the warmest")
   ▼
FindAPIsTool ─► MetadataSearcher (.auto): hybrid retrieval → candidates
   │            └─► SelectionTier (guided RoutedSession on profile.flash,
   │                 surface as its cached instruction prefix, fork() per call)
   │                 → ids, grammar-constrained to the candidate set
   │            └─► matched blocks spliced verbatim, plus qualified examples
   ▼
main model writes a snippet:
   runCode(`
     const cities = tools.getTrip().cities;
     const wx = cities.map(c => ({ c, t: tools.getWeather({city: c}).tempC }));
     return wx.sort((a,b) => b.t - a.t)[0].c;
   `)
   ▼
MultiTool.call → Interpreter runs it, each tools.X() → native Swift tool.call
   │  intermediates stay in the sandbox; only the final value returns
   ▼
ResultRenderer ─► ToolOutput ─► back to the model (the session's own tool loop)
```

### The two tools, as the main model sees them

These two `description`s *are* the prompt that makes the model search-then-code —
fixed strings, not per-tool, handed to the native session the same way any
tool's description is. They are the *whole* prompt: the shipped session — and
the gated integration suite alike — passes no session-level instructions,
because a `Tool` description is serialized into the prompt on every turn while
a session instruction is optional and a host may never pass one. Each clause
targets an empirically observed small-model failure mode. This is the search
affordance:

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

### The selection tier's assembled prompt (concrete)

`FindAPIsTool` forwards `task` to the selection tier, whose **instructions are
the cached prefix**: curated selection guidance + every candidate tool's
rendered block. Each `findAPIs` call forks the prefilled root session and asks
one question — the shape:

```
[instructions / cached prefix]
Given a task, return ONLY the functions needed — fewest that suffice. Do not
invent functions; return an empty list if nothing fits.

# Available functions
/**
 * The cities on the user's current trip, in itinerary order.
 * @returns { cities: string[] } — the itinerary's IATA city codes.
 * @example const cs = tools.getTrip().cities;
 */
declare function getTrip(): { cities: string[] };

/**
 * Current weather for a city. Use when the user asks how warm/cold/rainy it is now.
 * @param args.city — IATA city code or city name.
 * @param args.units — one of "c" | "f". default "c". (optional)
 * @returns { tempC: number; summary: string }
 * @example const c = tools.getWeather({ city: "ATX" }).tempC;
 */
declare function getWeather(args: { city: string; units?: "c" | "f" }): { tempC: number; summary: string };

… (calendar, convertCurrency, … every candidate's block) …

[prompt for this call]
list the cities on my trip and get the current weather for each
```

The answer is produced under guided generation, xgrammar-constrained to an
enum of the candidate ids (`idEnumGrammar(ids:)`), so the pick is well-formed —
and nothing *but* a pick — by construction:

```json
{ "ids": ["getTrip", "getWeather"] }
```

`FindAPIsTool` then formats the tool output the main model reads by looking
each id up in the surface — every block spliced verbatim, never re-typed by a
model (note `calendar`/`convertCurrency` are in the prefix but **not**
selected, so they never reach the main context):

```
findAPIs("list the cities on my trip and get the current weather for each") found:
// tools.getTrip
/**
 * The cities on the user's current trip, in itinerary order.
 * @returns { cities: string[] } — the itinerary's IATA city codes.
 * @example const cs = tools.getTrip().cities;
 */
declare function getTrip(): { cities: string[] };
Example: const cs = tools.getTrip().cities;

// tools.getWeather
/**
 * Current weather for a city. Use when the user asks how warm/cold/rainy it is now.
 * …
 */
declare function getWeather(args: { city: string; units?: "c" | "f" }): { tempC: number; summary: string };
Example: const c = tools.getWeather({ city: "ATX" }).tempC;
```

### Describing tools so agents pick them

Retrieval ranks — and the selection tier picks — by *reasoning over* each
rendered block, so discoverability is a property of the `name` / `description`
/ `@Guide`s the tool author already writes — we add no new metadata system, we
surface those and lint for completeness (M2):

- **Description states purpose AND trigger** — "what it does" + "when you'd use it."
  The selection tier matches the task's *intent*, so the trigger clause carries weight.
- **Name is `verbNoun`, the identifier the model would guess** (`getWeather`,
  `getTrip`, `bookHotel`) — not a bare noun (`weather`, `tripCities`) and not an
  internal code (`wx_lookup_v2`). The verb matters as much as the noun: a model
  reading a catalog infers its dominant convention and *applies it to names it
  has not seen*, so a catalog that is `verbNoun` everywhere except one tool
  makes that one tool the hardest to call. Be consistent across the whole
  catalog you mount.
- **Every parameter has a `@Guide`** — these become the `@param` lines; an
  undocumented param is one the model fills in blind.
- **Enums/ranges live in `@Guide`** so they render as `"c"|"f"` / `(range 1…10)`
  instead of a bare `string`/`number`.

```
✗ name "lookup"   desc "Returns data."   → the selection tier can't tell when to pick it
✗ name "weather"  desc "Current weather for a city…"   → right description, but the
                        bare noun fights a catalog of verbNoun neighbours
✓ name "getWeather"  desc "Current weather for a city. Use when the user asks how
                        warm/cold/rainy it is now."   → reliably selected
```

> **Naming (2026-08-07, task `tkrdwb8`).** The `verbNoun` rule above is a human
> ruling, made after a gated `discoveryUnderDistractors` run showed the model
> emitting `getTrip`/`getWeather` against fixtures named `tripCities`/`weather`:
> ten of the twelve mounted tools were `verbNoun`, so the model was inferring the
> convention correctly and the two fixtures were the outliers. Every worked
> example in this document was renamed to match.
>
> The same pass corrected the worked `getTrip`'s **return shape**, which this
> document had shown as `getTrip(): string[]` in every walkthrough. No tool in
> this repo produces that shape, and none did before the rename either: the
> gated fixture returns a whole trip object (`IntegrationTripOutput` — `cities`
> plus dates, traveler and confirmation code), and the shipped CLI demo returns
> an object too (`DemoTripOutput`, whose one field is `cities`). The divergence
> was the document's, not one gated outlier's, so the examples above now
> navigate to `.cities` the way a real itinerary API forces. What was wrong was
> the shape claimed for these two tools, not the renderer's range: a bare
> `string[]` return is a shape `ToolAPIRenderer` does emit. It requires an
> object schema of a tool's `parameters` only, never of its return, and
> `[String]` is itself `Generable`, so a tool returning one renders its array
> root as `string[]`; an `Output` that is `PromptRepresentable` without being
> `Generable` renders as `string` instead (the `echoText` fixture pinned in
> `Tests/FoundationModelsMultitoolTests/Goldens/BuilderSurface.ts.txt`).

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

One in-band notice closes a successful render: a snippet that called `tools.*`
and returned a value carrying nothing those calls returned is told so, because
that snippet and one that reports a real result are otherwise indistinguishable
from the model's side (task `wnfzwxg`, `ToolReturnLedger`).

The notice states a fact and does not claim an intent. A snippet that discarded
a tool's return and answered `{ started: true }` and one that computed a total
out of what it read are the same value to any structural reader — neither
carries what the calls returned, and only intent separates them. So the notice
reports the shared fact and asks the model the one question it can answer, and
the run that summarized deliberately reads a sentence and moves on.

## Components

⭐ marks the value-add (touches FoundationModels types or the interpreter core).

1. **`MultiTool`** ⭐ — the `runCode` `Tool`. Holds the wrapped `[any Tool]`; builds
   a fresh interpreter with each tool installed as `tools.<name>`; runs the snippet;
   renders via `ResultRenderer`. Conforms to `FoundationModels.Tool`, so it
   registers directly on the native `LanguageModelSession` (Router integration).
2. **`MultiTool.Builder`** — `addTool(_:)` / `addTools(_:)` / `addGroup(named:_:)` /
   `build()`. The easy contribution path; takes `any Tool` only, produces a
   model-agnostic catalog (no model wiring). Grouped tools render under a
   `tools.<group>.<name>` namespace.
2b. **`MultiToolAgent`** ⭐ (**retired**) — was the hand-rolled search-then-code
   ReAct loop over a `RoutedSession` (prompt → parse a `runCode`/`findAPIs`/final
   step, guided or tolerant-parse → dispatch → feed back) — the tool loop the
   Router does not provide. Deleted after real-hardware testing showed it
   unreliable regardless of model size; Apple's native `LanguageModelSession`
   tool-calling loop over `MLXLanguageModel` replaced it (see **Router
   integration**'s history).
3. **`ToolAPIRenderer`** ⭐ — encodes a `GenerationSchema` (Apple's JSON-Schema
   analog) → typed signature + doc comment.
4. **`ArgumentMarshaler`** ⭐ — JS value → `GeneratedContent` (content, not schema),
   and `Output` → JS value.
5. **`ToolInvoker`** ⭐ — generic existential-opening invoker: marshal → validate →
   native `call` → render. The no-source invocation core.
6. **`Interpreter`** (protocol) + **`JSCInterpreter`** ⭐ — fresh context, std
   surface, install `tools.*`, run under a time limit, capture return + console, map
   exceptions. Unit-testable without the model.
7. **`APISurface`** — the rendered catalog; backs the selection tier's prefix,
   `help()`/`docs()`, and a host-UI listing (plain data, no UI code).
8. **`FindAPIsTool`** ⭐ — discovery over `APISurface`: `findAPIs` as its own
   real `Tool` on the native session, forwarding to
   `FoundationModelsMetadataRegistry`'s `MetadataSearcher`/`SelectionTier` on a
   Router-resolved `flash` slot (the extracted, generalized former
   `Librarian` — see **Discovery**).
9. **`ResultRenderer`** ⭐ — return + console → `ToolOutput`; size/trim; exception →
   repairable error.

## Milestones

> **As-built note.** The milestones below are kept as originally planned — the
> historical record. Where the design later pivoted, the rewritten sections
> above are authoritative: M4's `MultiToolAgent` loop (and its
> guided-vs-tolerant turn-format question) was built, proved unreliable on
> real hardware, and was retired for Apple's native `LanguageModelSession`
> tool-calling (see **Router integration**); M6's `Librarian`/`FoundAPIs`
> shapes landed as `FoundationModelsMetadataRegistry`'s
> `MetadataSearcher`/`SelectionTier` with ids-only guided output (see
> **Discovery**); M6.5's gated suite now drives native sessions
> (`ScenarioRunner`/`NativeToolCallEvaluation`), not an agent loop.

- [ ] **M0 — Scaffold.** SwiftPM library + executable sample (CLI). Depend on
  `FoundationModels`, `JavaScriptCore`, and the **`FoundationModelsRouter`**
  package — `.package(url: "https://github.com/swissarmyhammer/FoundationModelsRouter", branch: "main")`
  and `.product(name: "FoundationModelsRouter", package: "FoundationModelsRouter")`
  (pin to a tag/commit once the Router tags a release; it is itself
  `swift-tools-version: 6.1`, `.macOS("27.0")`). OS 27 floor, no `@available`. CI on
  macOS with the OS-27 SDK.
- [ ] **M1 — Interpreter core.** `Interpreter` + `JSCInterpreter`: fresh `JSContext`,
  std surface, `run(code)` under the time-limit watchdog, capture return + console,
  map exceptions. No model needed.
- [ ] **M2 — `ToolAPIRenderer`.** Encode a `GenerationSchema` → transliterate the
  JSON Schema to a typed signature + doc. Table-driven + golden-file tests over a
  schema corpus. (Encoded shape known — Findings #3.)
- [ ] **M3 — `ArgumentMarshaler` + `ToolInvoker`.** JS value ⇄ `GeneratedContent`;
  existential opening over a mock `Tool`; validate; render `Output` to a JS value.
  **Pin: the exact `Output` read-back (Findings #4).**
- [ ] **M4 — `MultiTool` + `MultiToolAgent` end-to-end.** Wrap **two real
  third-party-style `@Generable` tools** (no source modification), install
  `tools.*`, and drive them through the `MultiToolAgent` loop over a Router
  `RoutedSession` (`profile.standard`) that composes their results in one snippet.
  Settle the turn format (guided grammar vs. tolerant parse — Router integration).
- [ ] **M5 — `ResultRenderer` + repair loop.** Serialize/cap/trim; repairable
  errors; verify the model fixes a bad tool call from the error.
- [ ] **M6 — Librarian + `findAPIs` on Router.** `FindAPITool` + librarian on the
  profile's `flash` slot via guided `respond(to:generating: FoundAPIs.self)`;
  confirm the MLX backend reuses the instruction-prefix KV cache across `findAPIs`
  calls, using `RoutedSession.fork()` (KV `copy()`) if a plain reused session does
  not.
- [ ] **M6.5 — Integration tests on a small real tool-calling model.** Gated,
  opt-in real-model suite that runs a few sample MultiTools end to end and asserts
  the agent **searches then calls** correctly (see **Integration tests**). Depends
  on the Router's live inference path (its milestone 7); until then it is skipped.
- [ ] **M7 — In-JS `help()` / `docs()`.**
- [ ] **M8 — (deferred) MCP tools.** Out of v1 scope. MCP-backed `Tool`s are
  ordinary `Tool`s, so `addTool`/`addGroup` already cover them; any bulk "import a
  whole server" ergonomics are future work.
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
- **E2E** (M4/M6/M9): gated/optional, needs the model (Router) on real hardware.

### Integration tests — sample MultiTools on a small real tool-calling model (M6.5)

> **As-built note.** This strategy predates the agent-loop retirement (see
> **Router integration**): the shipped gated suite drives native
> `LanguageModelSession`s via `ScenarioRunner` and grades them with
> `NativeToolCallEvaluation` — the Evaluations subject is the session's own
> `respond(to:)`, not the deleted `MultiToolAgent.respond(to:)`. The
> loop-observability assertions below survive as transcript/tool-output
> assertions on the native session.

The unit suites above run without a model. But the *whole thesis* — that a small
open-weight model will reliably **search (`findAPIs`) and then call (`runCode`)**
against a fused surface — can only be proven against a real model doing real
tool-calling. This suite does exactly that, and is the plan's answer to "does the
search-then-code loop actually work?"

- **Shape it on the Router's own gated suite.** Router ships a separate
  `…IntegrationTests` target that downloads *deliberately tiny* real models and runs
  them end to end behind an opt-in env var (so it never fires on a network/GPU-less
  box, and never in normal CI). We mirror that: a `FoundationModelsMultitoolIntegrationTests`
  target, opt-in via env var, resolving a `ProfileDefinition` of small
  tool-calling-capable models (e.g. a few-hundred-MB-to-low-GB instruct model whose
  `flash` slot can also drive the librarian). It depends on the Router's live
  inference path (its milestone 7); until that lands the suite `throws`/skips on
  `GenerationError.notWiredForLiveInference`.
- **A few representative sample MultiTools**, each a small fixed tool set that
  forces the behavior we care about:
  1. **single-call** — one obvious tool (`getWeather`); asserts the model finds it and
     calls it, not that it hallucinates an answer.
  2. **compose/chain** — `getTrip` → `getWeather` per city → pick warmest; asserts
     the model writes *one* `runCode` snippet that composes (intermediates never
     re-enter context), not N single tool calls.
  3. **discovery under distractors** — ~20 wrapped tools where only 2 are relevant;
     asserts `findAPIs` returns the right minimal set and the snippet uses exactly
     those (the fused-surface selection-accuracy claim).
  4. **repair** — a tool the model tends to mis-call; asserts the repair loop
     recovers from the returned error within a bounded number of turns.
- **Assert on the loop, not just the final string.** Because `MultiToolAgent` owns
  the loop, the test harness can observe each step — which is the point. Router also
  records every turn to a JSONL transcript (`RecordingLevel.full`), so assertions
  can check *that* `findAPIs` was called before `runCode`, *which* functions the
  librarian returned, and *which* `tools.*` the snippet actually invoked — turning
  "did it search then call?" into a checkable trace rather than a vibe.

**Apple's Evaluations framework (`import Evaluations`).** This is exactly what the
search-then-call assertions should be built on — a real framework (WWDC26 "Meet the
Evaluations framework", session 298) that measures generative-feature quality and
**integrates with Swift Testing**, so the eval suite lives beside the rest of the
tests and fails when aggregate behavior drops below a threshold. The mapping:

- **Subject = our feature.** An `Evaluation` conformer names the code under test —
  for us `MultiToolAgent.respond(to:)` — so the eval runs the *whole* agent loop end
  to end per sample, not a single model call. (Its output is what evaluators grade.)
- **Dataset = `ModelSample`s.** `ArrayLoader(samples: [ModelSample(prompt: …,
  expected: …)])` for the four sample MultiTools; `SampleGenerator`'s
  `makeSamples(…, targetCount:)` can synthesize distractor/paraphrase variants from a
  seed set to widen coverage.
- **Graders = quantitative `Evaluator`s over the recorded loop.** Because the loop is
  observable (and Router records every turn to a JSONL transcript), the important
  assertions are deterministic pass/fail `Evaluator`s, no judge needed:
  `Metric("SearchedThenCalled")` — `findAPIs` before `runCode`;
  `Metric("CalledExpectedTools")` — the snippet invoked exactly the expected
  `tools.*`; `Metric("RepairedWithinN")` — recovered from a bad call within a bounded
  turn count. Each evaluator returns `metric.passing(rationale:)` /
  `metric.failing(rationale:)` (or `metric.score(_)`), aggregated in
  `aggregateMetrics(using:)` via `computeMean`/`computeStandardDeviation`.
- **Optional `ModelJudgeEvaluator`** for softer answer-quality ("is the final answer
  right and well-formed"), with a `.numeric([...])` scale / `ScoreDimension`s and a
  judge model — pure test infrastructure (e.g. Apple's `PrivateCloudComputeLanguageModel`),
  orthogonal to the Router-runs-the-feature rule.
- **Pass gate = an optimization target in Swift Testing.** The eval is a `@Test`
  with the `.evaluates(evaluation, info:)` trait, and the gate is an ordinary
  expectation on the aggregate:
  `#expect(EvaluationContext.current.result.aggregateValue(.mean(of: searchedThenCalled)) >= 0.9)`.
  That turns "does it search then call?" into a scored pass-rate we can track across
  candidate small models and regress on prompt/model changes — Xcode renders a
  per-sample report (prompt, measurements, full model response) for triage.

*(Minor pin: confirm the exact `Evaluation`-conformance member names and the
`subject`/run signature against the shipping SDK — the framework and its Swift
Testing `.evaluates` trait, `ModelSample`, `Evaluator`/`Metric`, `ModelJudgeEvaluator`,
and `SampleGenerator` are verified from the WWDC26 material, but a member name may
differ by SDK seed. The framework runs features end to end, so a multi-step agent is
a supported subject.)*

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
7. **FoundationModelsRouter is the model source for everything (per the user), and
   it vends its own session type — not Apple's.** Confirmed against the package
   source: `Router` is an `actor`; `resolve(_:reporting:)` turns a
   `ProfileDefinition` into a resident `LanguageModelProfile` with `standard`/`flash`
   `RoutedLLM` slots (one profile resident at a time); `RoutedLLM.makeSession(…)`
   vends a `RoutedSession` whose surface is `respond(to:) -> String` + guided
   generation (`respond(to:following:)`, `respond(to:matching:)`, and typed
   `respond(to:generating:)`). **There is no `LanguageModelSession`, no
   `SystemLanguageModel`, and no built-in tool-calling loop** — so, at the time,
   `runCode`/`findAPIs` were dispatched by *our* `MultiToolAgent` loop, with
   `findAPIs`'s constrained output produced by Router guided generation
   (xgrammar). (That hand-rolled loop was later retired for Apple's native
   tool-calling over `MLXLanguageModel` — see **Router integration** — while
   the guided-generation half lives on in `findAPIs`'s selection tier.) Router
   also owns xgrammar and a `fork()`/`SessionKVCache.copy()` primitive we use
   for the selection tier's prefix reuse. **Live MLX inference is gated to the Router's milestone 7**
   (`GenerationError.notWiredForLiveInference` until then), which bounds when our
   real-model integration suite can run.

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
  tools live at `tools.<name>`; a *group* (`addGroup(named:)`) renders under
  `tools.<group>.<name>` — organizing a related set and resolving duplicate names.
  A single tool multiplexing via an `op`-enum is one function (`tools.x({ op, … })`),
  optionally expanded to `tools.x.<op>(…)` for a clean discriminated union. `help()`
  shows the layout.
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
- **Router live inference + prefix reuse** — the entry points are known
  (`Router.resolve` → `LanguageModelProfile` → `RoutedLLM.makeSession` /
  `respond(to:generating:)`); what remains is (a) the Router's live MLX decode
  landing (its milestone 7; today `GenerationError.notWiredForLiveInference`), and
  (b) whether a reused selection-tier `RoutedSession` reuses its instruction-prefix
  KV cache, or whether we must drive reuse explicitly via `fork()`/`SessionKVCache.copy()`
  (Finding #6). Both are confirmable only against the built Router + real hardware.
  **Both since resolved on real hardware:** the Router's live path landed (the
  gated suite and `multitool-cli` run live models), and prefix reuse is driven
  explicitly via fork-per-call — the shipped `SelectionConfig` contract (see
  **Discovery**; the gated `SelectionForkPerCallTests` holds the fork-per-call
  contract itself, read off the recording). Read "prefix reuse is driven" as
  the mechanism being engaged, never as reuse being measured: no suite in this
  repository can see whether a prefill was skipped, and that suite's own
  documentation states why.

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
- **`FoundationModelsMCP`** (sibling) — the per-tool MCP bridge. We borrow its
  agentic-search and `Builder` patterns. Its `MCPTool`s are ordinary
  `FoundationModels.Tool`s, so the MultiTool could wrap them later (deferred, M8).
  The schema-constrained complement to this code-surface approach.
- **`FoundationModelsRouter`** (`github.com/swissarmyhammer/FoundationModelsRouter`,
  a SwiftPM dependency) — RAM-aware MLX model selection (author a `ProfileDefinition`,
  `resolve` it to a `LanguageModelProfile` with `standard`/`flash`/`embedding`
  slots) + an xgrammar guided-generation engine. Supplies the models for both the
  main session and the selection tier here, and its `RoutedSession` (+ `fork()` KV
  copy) and typed guided generation are the primitives the retired
  `MultiToolAgent` built on and `FindAPIsTool`'s selection tier still builds on.
  Its own gated `IntegrationTests` target (tiny real models, opt-in env var) is
  the template for ours.

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
- `FoundationModelsRouter` package — https://github.com/swissarmyhammer/FoundationModelsRouter
  (local: `../FoundationModelsRouter`; key types `Router`, `ProfileDefinition`,
  `LanguageModelProfile`, `RoutedLLM`, `RoutedSession`, `Grammar`)
- Apple **Evaluations** framework — https://developer.apple.com/documentation/evaluations ·
  "Meet the Evaluations framework" (WWDC26 #298) https://developer.apple.com/videos/play/wwdc2026/298/ ·
  Swift Testing `.evaluates` trait — https://developer.apple.com/documentation/testing ·
  used by the M6.5 integration suite to grade search-then-call
- Sibling plans — ../FoundationModelsMCP/plan.md · ../FoundationModelsRouter
