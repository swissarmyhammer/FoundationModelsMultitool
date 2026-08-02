# eventplan.md — Events, long-running work, and the consolidated tool surface

Router owns the host substrate: the event vocabulary, the outbox, the mailbox, and the
ambient `ToolContext` — one package, one product, with the host substrate in a
`Hosting/` source folder beside `Session/`.
MultiTool depends hard on Router and becomes the one code-mode surface (`runCode` /
`findAPIs`) with the async semantics for long-running work — the capabilities JS-based
tool systems hand to a handler and `FoundationModels.Tool.call(arguments:)` structurally
cannot. Shell, files, and MCP move into MultiTool as built-in capability modules;
OperationTool, Shelltool, the MCP package, and the FileTool package all retire. This is a
deliberate drift away from the Rust base's operation pattern — recorded and accepted.

## The capability contract

MultiTool's surface has two tiers. The baseline is unconditional — present on every
MultiTool, never behind a Builder option:

| Capability | Surface |
|---|---|
| Quick sync return | any `Tool` call that completes inside `waitSeconds` returns its value inline — enforced by `ElevatingTool` at the `Tool` protocol level, native path and code path alike |
| Long-running with token | elevation to `completionToken`; `status()` / `wait()` / `cancel()` builtins |
| Elicitation | `elicit()` at snippet top level and `ToolContext.elicit` in any tool — always available |
| Notification events | `notify()` / `progress()` at snippet top level and `ToolContext.post` / `progress` in any tool — always available |
| Discovery | `findAPIs`, `help()`, `docs()` |

The modules are opt-in, per the permission posture: `withShell()`, `withFiles()`,
`withMCP(servers:)`. A registered user tool gets the baseline automatically — the ambient
context is bound around every invocation, so elicitation and events cost a tool nothing
to adopt and nothing to ignore.

## The vocabulary and host substrate live in Router

`OperationEvent`, `OperationEventKind`, `OperationOutcome`, `OperationEventSink`, and
`EventEmittingTool` move out of OperationTool into Router — the host owns the vocabulary,
alongside the outbox, the mailbox, and the ambient `ToolContext`. MultiTool already
depends hard on Router: its library target links the `FoundationModelsRouter` product
today, and `FindAPIsTool`'s selection tier runs on Router-backed sessions. Phase 1 adds
no new edge — it moves the vocabulary to the Router side of an edge that exists. The
unknown-preserving `.other(_)` decoding and the terminal-event scope contract move
verbatim — they are already correct.

Placing `ToolContext` in Router has a consequence MultiTool alone could not deliver:
Router binds the task local around native `respond()` too, so a tool sees the same
ambient capabilities on the native token-constrained path and on the code path. The host
layer owns `window`; MultiTool only re-binds per snippet call with a freshly minted
`completionToken`.

Router stays one package with one product. A split was considered to spare emitting
tools the MLX build, but the plan removes its own consumers: MultiTool imports the full
Router today, and shell, files, and MCP become internal MultiTool folders by phase 4 —
after phase 5 no external package would import a hosting product at all. The substrate
lives in a `Hosting/` source folder beside `Session/`; if a third-party emitter ever
needs an MLX-free import, a product split along that folder boundary is a manifest
change at that time, with no source moves.

## Elevation: waitSeconds and the completion token

The elevation engine lives at the `FoundationModels.Tool` protocol level, in Router's
`Hosting/` folder — not down in the code-mode bridge. `ElevatingTool` wraps `any Tool` and
races its `call(arguments:)` against a `waitSeconds` timer (default **5 s**). A call
that finishes inside the window returns its rendered output. A call that does not is
parked in the session mailbox; the wrapper posts the synthesized events and returns the
pending envelope — `{ pending: true, completionToken: "01…" }` — as its rendered output.
The wrapper's `Output` is the rendered value, so a typed wrapped `Output` never has to
represent the pending case; the model reads text on the wire either way.

This is MCP's `CallWait` soft deadline and Shelltool's `RunSupervisor` race, promoted
into one engine — see "Consolidating the siblings" for the two-clocks model both already
agree on. Two mounts, one engine, two policies: Router applies the wrapper when composing a
native session's tool list, where every call elevates at `waitSeconds`; MultiTool's
`ToolInvoker` dispatches every `tools.*` call through the same engine with elevation
off — inner calls await to completion, and only the outer `runCode` call elevates (see
"The constraint boundary"). One engine owns parking, events, and outcomes either way.

Follow-up differs by path, by design. Code mode has the `status(completionToken)` /
`wait(completionToken, seconds)` / `cancel(completionToken)` builtins, and the model
carries the token across turns. The native path has no builtins — completion arrives as
a turn-riding event through the outbox at the next turn boundary, and no follow-up
pseudo-tools return.

The token is a ULID and is identical to the run's event `correlationID`. The word is
always `completionToken` — never bare "token", which collides with LLM tokens in every
other document.

The mailbox is an actor in Router, beside `SessionOutbox` and scoped the same
way — one per session. A `runCode` sandbox is per-call and fresh; nothing parked may live
in it. `ForkableTool` composition applies: a fork gets its own mailbox, the same rule
`SessionOutbox` already follows.

**Parked runs die with the session.** A detached run exists to unblock the turn, not to
outlive the conversation; a child that survives its session has no observer, and its
state becomes manufactured `.lost`. Session teardown runs one deterministic sweep over
the mailbox, each kind by its own semantics: shell runs get `killpg(SIGKILL)` and post
`.stopped`; MCP requests get the advisory cancel and post `.cancelled` before the
transport closes; parked Swift tasks get cooperative cancellation. Every outcome is
journaled before the session closes — no orphans, no holes in the durable record. Work
that must outlive a session is a different feature (an explicit daemon or job store),
not built until motivated. The crash edge: teardown never ran, the memory-only mailbox
is gone, and restoration marks journaled runs with no terminal event `.lost` — the only
place `.lost` appears outside an MCP transport drop.

## MultiTool is both host and emitter

At build, MultiTool discovers emitters in its registry by conformance cast and connects
each to its mailbox sink — the same wiring Router does today, one level down. MultiTool
itself conforms to `EventEmittingTool`; Router discovers it with the same cast and
connects the outbox, unchanged. MultiTool's sink updates the mailbox first, then forwards
upstream. One connection point, two consumers, no new protocol.

For a parked call with no events of its own, the engine synthesizes them — wherever
elevation is on (the native mount, and the outer `runCode` run): one `progress` event
at elevation, one `.completed` event on finish carrying the rendered output in
`detail`, the `completionToken` as `correlationID`, and the correct `OperationOutcome`.
The terminal-event contract holds for every elevated run, emitter or not.

Terminal events are always forwarded upstream, including runs whose result a snippet
already collected through `wait()`. The outbox line is then redundant narration, but the
journal must stay complete — restoration reads `OperationEventSegment`, and a suppressed
event is a hole in the durable record.

## The ambient context

`ToolContext` is ambient, not a parameter — a sandbox-wide capability object connected
back to the calling session, in the way `window` is to a page. Swift's mechanism is
`@TaskLocal`:

```swift
struct ToolContext: Sendable {
    @TaskLocal static var current: ToolContext?
    // session-scoped: mailbox, upstream sink, session identity, cancellation
    // per-run: completionToken (minted by the invoker at each binding)
}
```

`ToolInvoker` binds it around every wrapped call —
`ToolContext.$current.withValue(ctx) { try await tool.call(arguments:) }` — with the
run's `completionToken` minted into each binding. The object is session-scoped; the
correlation is per-run. Capabilities:

- `post(_ event:)` and `progress(_ detail:)` — the event path, pre-wired with this run's
  `correlationID`.
- `elicit(_ request:) async throws -> ElicitationResponse` — ask the user something
  mid-run. This is just another elevation: the run parks as a pending promise, the
  elicitation request travels upstream through the same event chain, and the answer comes
  back down through the mailbox to resume the parked continuation. An elicitation is a
  long-running operation whose completion is a user reply — no second machinery.
- Cancellation, the run's `completionToken`, and session identity.

The host verb for answers is `respond(elicitationId, response)` on `RoutedSession`
(app host → Router → mailbox → resume) — answers address the elicitation, never the
run, because one run can hold several pending elicitations at once. Elicitation requests ride the event chain as
their own event kind beside `progress`/`completed`; the exact envelope is open below.

Three consequences of ambience:

1. **No second tool protocol.** The registry keeps one shape, `any Tool`. A tool reads
   `ToolContext.current` when it wants capabilities and ignores it when it does not.
   Every existing conformer works unchanged and can opt in without a signature change.
2. **Capture-at-start gets teeth.** A detached task does not inherit task locals. A tool
   that starts detached work and re-reads the ambient context finds `nil`, and posting
   through `nil` is already a safe no-op — the runtime now enforces what
   `EventEmittingContext`'s doc comment only requested. The rule's text carries over:
   capture the context once, at operation start, into whatever outlives the call.
3. **`connecting(_:)` is a candidate for retirement**, decided by phase 1's propagation
   probe (see Phases): if task locals arrive through Apple's `respond()`, the protocol
   deletes; if not, it stays as the native-path fallback. Code mode never depends on it.

## Async JavaScript

The v1 blocking bridge retires; phase 1 builds on the promise pump directly, rather
than building semaphore parking and its thread guards only to delete them. The mapping:
every `tools.<noun>.<verb>()` returns a JS Promise; the snippet is wrapped in
`(async () => { … })()` so top-level `await` works; each call starts a Swift Task
through `ElevatingTool`, and on settle, control hops back to the JS thread, resolves or
rejects the promise, and drains the microtask queue. JS single-thread semantics hold —
interleaving only at `await` points, the JavaScript the model already knows.

Parallelism becomes real: `Promise.all([tools.a.read(...), tools.b.fetch(...)])` fans
out concurrent Swift Tasks — do-more-per-call at the snippet level. Capabilities keep
their own serialization where order matters (atomic file writes, one shell run per
command), as they must in any async system. Errors map unchanged: a rejected promise is
a JS exception at the `await` point, the same repairable message and fix-and-re-call
contract. The common model slip — a returned promise with no `await` — settles at the
boundary: `ResultRenderer` awaits a thenable final value, so `return tools.x.y(...)`
still works. Cancellation maps to rejection: `cancel()` and the session sweep cancel the
in-flight child Tasks, reject every pending promise, drain, and tear the context down
within the time limit. Elevation composes: a snippet that outlives `waitSeconds`
elevates while its inner promises stay in flight; call settlements and elicitation
answers resolve them until the snippet finishes into its terminal event. The `runCode` description
gains one line: await every `tools.*` call; use `Promise.all` to run calls in parallel.

**What is a promise is pinned by one rule**: anything that crosses into Swift effects —
`tools.<noun>.<verb>()`, `elicit()`, `wait()`, `status()`, `cancel()` — returns a
promise; `help()` and `docs()` (pure surface reads) and `notify()` / `progress()`
(void, enqueue-and-continue, flushed by the bridge) are synchronous. If it does work or
asks a question, await it; if it describes or narrates, do not.

**Forgotten `await` has four shapes; three are caught.** An unawaited *return* settles
at the boundary — `ResultRenderer` awaits a thenable final value. A *floating call*
(`tools.files.write(...); return "done"`) is covered by **settle-before-return**: the
bridge tracks every promise it creates, and `runCode` produces no result until all of
them settle — the work really happens, and a floating rejection surfaces as the run's
error instead of vanishing (do-more-per-call's settle window, applied at the snippet
boundary). *Property access on a pending result* is caught by a Proxy trap: the bridge
returns proxied promises whose `get`, for anything but `then`/`catch`/`finally`, throws
a precise repairable error naming the call and the accessed property and asking "did
you forget `await`?". The residual is *truthiness or arithmetic on a promise* — not
trappable, a promise is always truthy — covered only by the description text and the
ordinary repair loop when the wrong branch errs downstream. The backstop for all four
is the existing contract: precise, model-repairable errors and immediate re-call.

**Session affinity across the seam.** The JS thread is not a Swift task — a JSC
callback lands outside any task tree — so routing never depends on task-tree
inheritance across the seam; it depends on values captured at bind time. One
`RunBinding` per `runCode` invocation, captured when `ElevatingTool` binds the ambient
context: the `ToolContext` (session identity, mailbox reference, sink), the outer
`completionToken`, and the interpreter's serial executor. Every promise carries it.
Each parallel inner call runs in a Task whose closure re-establishes the ambient
context from the binding explicitly — never trusting inheritance — and mints its own
per-call `completionToken` from the captured context, so parallel runs correlate
independently while posting to the same session's mailbox (an actor: affinity is
holding the reference, not being in a tree). A settling Task resolves its promise on
the binding's executor, keyed by promise id — two sessions sharing one registry can
never cross-route, because each invocation captured its own binding. Inbound routing
uses no task locals at all: `respond` / `complete` → `RoutedSession` → that session's
mailbox → the run entry → its resolver, hopping to the binding's executor — by
reference the whole way.

## The elicitation envelope, pinned to the MCP spec

The envelope follows the MCP specification exactly (form mode: 2025-06-18; URL mode:
2025-11-25) — no invented shape. `ElicitationRequest` in Router's `Hosting/` folder
carries `mode` (`form` | `url`, omitted means form), `message`, and per mode:
`requestedSchema` for form — the spec's restricted subset, flat objects of primitive
properties only (bounded strings with `email`/`uri`/`date`/`date-time` formats, numbers,
booleans, single/multi-select enums, defaults) — or `url` + `elicitationId` for URL
mode. `ElicitationResponse` is the three-action model: `accept` | `decline` | `cancel`,
with `content` present only on a form-mode accept.

The request rides the event chain as the third `OperationEventKind` case, its payload
the typed request. Two contract updates come with the third kind: the outbox coalescing
policy keeps every elicitation event, never coalescing them (only `progress` coalesces),
and the terminal-event scope contract restates over three kinds — a run that posts any
event still posts exactly one `.completed`, and elicitation events are non-terminal. The `elicitationId` is a ULID, distinct from the run's
`completionToken`: one run can elicit more than once, and a URL completion addresses the
elicitation, not the run. Form answers come down through `respond(elicitationId, response)`; URL mode resolves
in two steps — the accept means only user consent to open, and completion arrives
separately through `complete(elicitationId)`, which the mailbox holds the run open for,
ignoring unknown or already-completed ids per spec. Tools must handle decline and
cancel; a declined elicitation is not a cancelled run.

The restricted form schema is enforced at our boundary for every elicitor — snippet
`elicit()`, `ToolContext.elicit`, and MCP passthrough — so passthrough is lossless and a
host form UI stays a flat form. The spec's trust rules bind the host seam, recorded here
as normative for the presenting app: sensitive information (credentials, keys, payment)
goes through URL mode only, never form; the host shows the full URL, never pre-fetches
it, never opens it without explicit consent, and opens it in a surface the client and
model cannot inspect. Those obligations land on the presenting layer (AgentViewKit's
concern later), not on Router, which only carries the typed envelope.

## The sandbox globals

The snippet-facing surface is the same idea one level up: a flat, window-like set of
globals, extending the existing `tools.*` / `help()` / `docs()` pattern with `status`,
`wait`, `cancel`, `elicit`, `notify`, and `progress`. A long snippet loop posts
`progress()` directly and the outbox coalesces it like any tool's progress event.
`elicit` at snippet top level is a capability the
parameter design never had — the model itself can pause for a user answer mid-snippet,
with no tool in between:

```javascript
const repo = await elicit("Which repository should I target?");
return tools.github.createIssue({ repo, title });
```

It parks and resumes through the same elevation path as everything else.

`elicit()` returns a promise like every other call (see "Async JavaScript") — the
snippet awaits it, control flow gets the answer, and no OS thread is held while the
user thinks. The model's turn is not held either: the outer `runCode` run elevates past
`waitSeconds` and the model gets the pending envelope. What pends is a promise plus a
suspended JSC context, resolved by `respond` from the next statement on. Two guards
bound the cost: a configuration cap on live suspended contexts, and a hard unblock —
`cancel(completionToken)` and the session-end sweep reject every pending promise, drain
the microtask queue, and tear the context down within the time limit, per the existing
cancellation-mid-snippet guarantee.

The globals need no `findAPIs` affordance. The two tool descriptions deliberately carry
the whole behavioral contract with no bespoke system prompt, so `MultiTool.description`
gains one sentence naming the ambient globals — `elicit()`, `notify()`, `progress()`,
and the `status()` / `wait()` / `cancel()` run verbs. `findAPIs` stays purely about
discovering `tools.*` functions: the globals are not searchable entries, because a
search result implies something findable-or-absent, and these are always present.

`findAPIs` is about finding APIs, nothing else — never a view of running state, never a
run-plane surface. Its ambition is upward, not sideways: each result carries the
declaration, the doc comment, and a sample snippet showing the call composed correctly,
so the model copies a working shape instead of inferring one. Rediscovery of in-flight
work after compaction belongs to the run plane: `status()` with no argument lists every
pending run — token, op, latest progress — and Router's compaction boundary carries the
live `completionTokens` the same way boundary metadata already preserves discovered-tool
state. A post-compaction model reads its pending work from the boundary, then
interrogates `status()`.

## OperationTool retires

Schema fusion exists to fit N schemas into a 4,096-token instruction window. MultiTool
solves the same pressure differently — one `runCode` schema plus a rendered API surface —
so fusion's reason to exist disappears once the model surface is code mode. With the
sibling tools absorbed as capability modules, nothing outside OperationTool consumes
`@Operation` either, so the whole package retires: the fused `OperationTool<Context>`
runtime, `SchemaFusion`, noun-in-path dispatch, the macro, and the ArgumentParser CLI
driver. Capabilities author directly against MultiTool's own registry surface — a
`ToolDescriptor` plus a plain `Tool` conformer reading `ToolContext.current`.
`EventEmittingContext` dissolves into the ambient context; typed per-capability contexts
(`ShellContext`, `FileContext`) survive as ordinary constructor dependencies.

The drift away from the Rust base is in machinery, not taxonomy: dispatch becomes the
rendered code API instead of fused operations, while the `{verb} {noun}` structuring
survives as the registration shape and the surface layout (see "Registering
capabilities: noun/verb"). Accepted, and narrower than first stated.

Per-capability CLIs (`FileToolCLI`, Shelltool's dual-use verbs) retire with the driver
that generated them. `multitool-cli` becomes the single demo and testing binary, closing
the earlier open question of a testing binary distinct from `sah`.

## Consolidating the siblings

I read all three repositories. The central finding: **the elevation machinery already
exists, twice.** FoundationModelsMCP has `CallWait` — a soft deadline that detaches the
call, a `RunningCall`/`CallHandle` registry, `get_result` / `list_calls` / `cancel_call`
follow-up tools, throttled progress, and one terminal `OperationEvent`. Shelltool has
`RunSupervisor`/`ShellRunner` — a deadline race that detaches rather than kills, a
`ProcessRegistry` with an exit sweep, and detached-event posting through a
capture-at-start sink. Consolidation is therefore promotion, not construction: one
elevation engine in `ToolInvoker` + the Router mailbox, and both local implementations
delete.

MCP's two-clocks model carries into the engine verbatim: `waitSeconds` bounds *the tool
call's block* and is reset by nothing; a per-call `timeout` bounds *the work itself* and
is reset by progress. Progress keeps the work alive; it never buys the caller more
waiting time. The MCP follow-up pseudo-tools (`get_result`, `list_calls`, `cancel_call`)
and Shelltool's equivalent operations retire in favor of the uniform `status()` /
`wait()` / `cancel()` builtins.

**Shell** (`Capabilities/Shell`) absorbs `ShellRunner`, `OutputBuffer`, the per-session
`.shell` history dotfolder, `grep history` / `get lines` retrieval, and `ShellPolicy`.
The policy's three outcomes stay — allow, deny, ask — but the ask outcome changes
meaning: today it refuses because the tool cannot reach a human; with elicitation always
available, ask routes through `ToolContext.elicit` and the remembered-"always" store
works as designed. Detach supervision moves to the shared engine; the `.stopped` outcome
keeps its authoritative `killpg(SIGKILL)` semantics.

**Files** (`Capabilities/Files`) absorbs the six operations — read, write, edit, patch,
glob, grep — plus `PathGuard` root bounding, `Hashline`, the `EditEngine`'s
shape-inferred dispatch, `AtomicWriter`, `FileChangeJournal`, and the
`DiagnosticsBridge`. The FoundationModelsCodeContext dependency comes with it: live
compiler diagnostics folded into every write and edit result is the capability's whole
point, per do-more-per-call. Corrective results (a payload that cannot resolve, a path
outside the root) stay in-band, never thrown.

**MCP** (`Capabilities/MCP`) absorbs `MCPServer`, `StdioServerProcess`, the
`SchemaConverter`/`GeneratedContentCodec` pair, `ToolContentRenderer` with its
`RenderBudget`, and the `ToolCatalog`. Each connected server registers as its own
top-level group — `tools.github.createIssue`, never `tools.mcp.github.createIssue`; the
model must not see the transport. MCP progress maps onto `progress` events; advisory
cancellation and transport drop keep their honest outcomes (`.cancelled`, `.lost`).

**Elicitation unifies on the MCP shape.** `ElicitationCoordinator` already serves both
directions — server-initiated `elicitation/create` and agent-initiated — and already
defines the hard case: URL mode is a three-message flow whose
`notifications/elicitation/complete` arrives separately from the accept response.
`ToolContext.elicit` absorbs this protocol as-is; the Router mailbox must hold a URL-mode
elicitation open past the accept until `complete(elicitationId:)` lands. The host app
keeps owning the presenting UI, exactly as the coordinator contract states today.

**The run plane and the content plane are separate surfaces, joined by one
identifier.** The mailbox carries envelopes and outcomes, never bulk output — `status()`
/ `wait()` answer lifecycle questions only. Captured content lives in the owning
capability's store: shell output stays in the per-session dotfolder, addressable through
`tools.shell.getLines` and `tools.shell.grepHistory` as ordinary surface operations, on a
live detached run (`OutputBuffer` reads while the child runs) and on a completed one
(the store is durable past the run). The join: a shell run's `commandID` is its
`correlationID` is its `completionToken` — one string, two planes. Nesting follows: an
elevated `runCode` has its own outer token, its pending envelope and `status()` list the
child runs discovered so far, and every terminal event's `detail` carries the output
tail plus the run's identifier, so the model always knows how to fetch more.

**Processes and tasks stay distinct kinds.** Three different objects can sit behind a
parked run: a Swift task (a parked native call — cancellation is cooperative), an OS
process group (shell — `killpg(SIGKILL)` is authoritative, `.stopped`), and an MCP
request (a protocol task — cancellation is advisory, `.cancelled`; a transport drop is
`.lost`). The engine owns runs — correlation, parking, events, outcomes — and takes from
the capability a run body plus a canceler carrying that capability's own semantics.
`cancel(completionToken)` returns the honest outcome, preserving the authority
distinction `OperationOutcome` already forbids flattening. The two registries therefore
stay separate: shell's tracks per-run child process groups; MCP's tracks server
subprocesses, which are infrastructure — session-lifetime, never runs, never issued a
`completionToken`. Killing a server subprocess is a host-level act on every in-flight
call it carries, not a run cancellation.

**The surface is immutable; change means rebuild-and-swap.** Servers connect before
`buildRegistry()`. A late server, a reconnect, or an MCP `tools/list_changed` triggers a
full rebuild: the new registry is rendered complete off to the side, then swapped in
atomically at the next turn boundary — the same boundary the outbox already folds
events into. Nothing mutates under a running snippet: an in-flight run keeps the
registry it started with, and parked runs survive the swap untouched because the
mailbox is session-scoped in Router, not registry-scoped. The rendered surface is
cheap to rebuild; the transcript is what persists.

Surface uniformity is the payoff: `findAPIs` searches built-in and user-registered
entries identically, `help()`/`docs()` render them identically, and a snippet composes
them freely — a shell command's output flows into a file edit and an MCP call in one
snippet, with intermediates never touching the model's context.

The Builder opts modules in explicitly — `withShell()`, `withFiles(root:)`,
`withMCP(servers:)` — off by default, keeping the permission posture at the registry
boundary where the runtime spec's consent system gates it later.

## The constraint boundary, and the escape hatch

Code mode does not give up token-level constrained arguments — the boundary moves.
`runCode` is a `Tool` with `@Generable` arguments, and guided generation constrains that
envelope at the token level: the call is always well-formed, and `code` is always a
string. What changes is the guarantee for the wrapped tools' arguments: inside the
snippet they are model-written code, so their validation happens at runtime —
`ToolInvoker`'s two layers, with precise, model-repairable errors and the immediate
re-call contract — instead of at decode time. A decode-time guarantee becomes a runtime
guarantee with a repair loop; different, not surrendered.

The envelope carries the control surface explicitly, each argument `@Guide`-documented
and token-constrained: `code`; `waitSeconds`, the first clock — how long this run blocks
before it elevates, defaulting to the configured 5, with `0` detaching immediately
(MCP's `bounded(.zero)` case); and `timeout`, the second clock — the hard bound on the
work, reset by progress. `findAPIs` keeps its search argument as the discovery half.
**Inner `tools.*` calls never elevate**: an awaited inner call runs to completion,
bounded by `timeout`, and only the outer `runCode` elevates — one elevation point, at
the boundary the model already sees, so no snippet ever branches on a pending envelope
mid-code. A capability wanting detach semantics declares it as an ordinary argument
(shell's `wait`), returning its identifier for the builtins. The two clocks appear
exactly once, at the envelope.

Whether a weak model does better with per-tool decode-time constraint or with the code
envelope plus repair loop is an empirical question for the gated evaluations, not a
settled deficiency. The plain-`Tool` registration path stays because it is free — the
registry holds `any Tool`, and `ElevatingTool` wraps either path identically — not
because code mode is deficient. Code mode is the default surface.

## Registering capabilities: noun/verb

Registration is one repeatable shape, and it keeps the noun/verb taxonomy — the fusion
machinery retired; the structuring did not. The path grammar is pinned: **every entry is
`tools.<noun>.<verb>` — exactly two segments, no flat entries.** An existing `Tool`
conformer already provides the verb — `Tool.name` is the verb — so the registration
primitive is `register(noun:tool:)`, supplying only the noun. A `Capability` is nothing
more than a noun plus its `[any Tool]`, and `Builder.withCapability(_:)` fills the noun
in once; any conformer drops in unchanged.
MCP obeys the same grammar with the server as the noun and the tool as the verb
(`tools.github.createIssue`). Nouns are unique: registration rejects a duplicate noun
(an MCP server named `files` against the files capability fails loudly at
`buildRegistry()`, not silently at dispatch). The renderer and the selection grammar enforce two
segments, and path, `findAPIs` result, `help()` entry, and event `op` all derive from
the one pair — `tools.<noun>.<verb>` on the surface, `"verb noun"` in the journal. The
surface reads as the model should think: `tools.files.edit({...})`,
`tools.shell.execute({...})`.

Layout is one folder per noun, one file per verb: `Capabilities/Files/Edit.swift` holds
the `@Generable` Arguments, the Output, the handler reading `ToolContext.current`, the
doc comment, and one example snippet — the sample `findAPIs` serves for that entry.
`OperationEvent.op` stays the canonical `"verb noun"` string, derived as
`"\(verb) \(noun)"` at registration, so Router's journal and outbox rendering continue
unchanged. Built-in and user capabilities are the same thing: `withShell()` is sugar for
`withCapability(ShellCapability(...))`, and third-party Swift code registers by the
identical protocol — that identity is the repeatable part.

## The instruction footprint

The "available tools" block that reaches the system prompt is two schemas — `runCode`
and `findAPIs` — plus their description text, small and constant regardless of how many
capabilities and servers the registry holds. Constant means cacheable: prefix reuse
works across turns and sessions, and the block fits the 4,096-token on-device window
with room left for work.

Everything else is behavior, and the two descriptions carry all of it — no bespoke
system prompt, as pinned today. `runCode` keeps its half: never guess function names,
answer only from what tools return, repair and immediately re-call on error.
`findAPIs`' half is the admonishment: *present your problem*, in task terms, and learn
what exists — not a name search for a function the model already believes in. A problem
statement retrieves; a guessed name confirms bias. The discipline is measured, not
hoped for: the gated suite keeps the search-then-call trajectory gate
(`findAPIs` precedes `runCode`) as the regression test that the contract text keeps
working as models and descriptions change.

## Phases

Each consolidation is one phase, tagged separately at completion, and each phase's exit
criterion is a deletion. When the last phase lands, the Shelltool, FileTool, MCP, and
OperationTool packages are gone.

**Phase 1 — foundation. Tag: `consolidation-1-foundation`** (Router and MultiTool).
The `Hosting/` folder in Router; the event vocabulary becomes Router's, and Router
drops its `Operations` import. The siblings keep compiling through a transitional shim:
`Operations` becomes typealiases re-exporting Router's canonical types, so one build
holding both imports (ACPAgent does) sees one type, not two ambiguous ones. The shim
transitively pulls MLX into the doomed packages' builds — build weight only, temporary,
and every payer is scheduled for deletion; the shim itself dies with OperationTool in
phase 5. Also in scope: the mailbox actor beside `SessionOutbox`; the `ElevatingTool`
engine at the `Tool` protocol level with the two-clocks model, mounted by Router for
native sessions and by `ToolInvoker` for `tools.*` dispatch; the `status()` / `wait()` /
`cancel()`
builtins; the ambient `ToolContext` with `elicit` and `notify` on the MCP coordinator
shape; the promise-pump interpreter replacing the v1 blocking bridge (see "Async
JavaScript"); MultiTool as host-and-emitter with synthesized events for parked native
calls.

Phase 1 includes the **propagation probe**, a gated test answering one question: when
Apple's `LanguageModelSession.respond` calls a tool, does the task-local `ToolContext`
arrive, or is it `nil`? One probe tool reads `ToolContext.current` inside
`call(arguments:)`; the test binds the context around `respond()` and runs one prompt on
the MLX path and one on the system model. Both answers are fine, and both branches are
decided now: propagates → native tools get the ambient context for free, and
`EventEmittingTool`/`connecting(_:)` delete in this phase; does not propagate → native
tools keep composition-time wiring, and it must carry the *full* context — sink and
mailbox both — because `ElevatingTool` reads the mailbox from the ambient context and
elevation itself would otherwise break on the native path; the protocol stays. Code mode is unaffected either way —
`ToolInvoker` binds the context itself and no Apple code is in that path. The probe
gates a file deletion, never the phase.

Exit: Router imports no `Operations` (only the shim points the other way); the Router
and MultiTool gated suites are green. The org-wide zero-imports check is phase 5's exit,
not this one's.

**Phase 2 — shell. Tag: `consolidation-2-shell`.** `Capabilities/Shell` absorbs
`ShellRunner`, `OutputBuffer`, the `.shell` dotfolder, history retrieval, and
`ShellPolicy` with ask routed through `ToolContext.elicit`. Detach supervision moves to
the shared engine; `RunSupervisor` and the shell `ProcessRegistry`'s race logic delete
in place of it. Shell is the reference emitter — its detached commands prove the
elevation path end to end. Exit: ACPAgent, Extras, and Skills — Shelltool's three org
consumers — migrate to the MultiTool capability, and the FoundationModelsShelltool
repository is archived.

**Phase 3 — files. Tag: `consolidation-3-files`.** `Capabilities/Files` absorbs the six
operations, `PathGuard`, `Hashline`, `EditEngine`, `AtomicWriter`, `FileChangeJournal`,
and `DiagnosticsBridge`, bringing the FoundationModelsCodeContext dependency with it.
Exit: ACPAgent and Skills migrate off FileTool, and the FoundationModelsFileTool
repository is archived.

**Phase 4 — mcp. Tag: `consolidation-4-mcp`.** `Capabilities/MCP` absorbs `MCPServer`,
`StdioServerProcess`, the codec pair, `ToolContentRenderer` + `RenderBudget`, and
`ToolCatalog`; servers register as top-level groups; the follow-up pseudo-tools retire
in favor of the builtins; the `ElicitationCoordinator` protocol becomes
`ToolContext.elicit`'s host seam, URL mode included. Exit: the FoundationModelsMCP
repository is archived; ACPAgent, its one org consumer, migrates first.

**Phase 5 — operation. Tag: `consolidation-5-operation`.** Nothing imports `Operations`
or `OperationsCLI` any longer — verified across the org, not assumed; Skills is the
last known consumer and migrates here. Per-capability CLIs are gone and
`multitool-cli` is the single demo and testing binary. Exit: the
FoundationModelsOperationTool repository is archived.

Order is fixed: 1 → 2 → 3 → 4 → 5. Phases 2–4 each depend only on 1, but land serially
so the elevation engine hardens against one consumer at a time, with shell first as the
emitter that exercises every path.

## Open

None — every item raised during planning is settled above.
