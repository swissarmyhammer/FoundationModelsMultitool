# eventplan.md — Events, long-running work, and the consolidated tool surface

Note: This document uses ASD-STE100 Simplified Technical English. Code
identifiers (for example `ToolContext`) and product names are technical names.
They keep their usual form. Words such as "elevate", "park", "mount", and
"render" are technical verbs in this project. Multi-word terms of this project,
for example "terminal-event scope contract" and "do-more-per-call", are
technical names also.

Router owns the host substrate. The substrate contains the event vocabulary, the
outbox, the mailbox, and the ambient `ToolContext`. Router is one package with
one product. The substrate is in a `Hosting/` source folder adjacent to
`Session/`.

MultiTool has a hard dependency on Router. MultiTool becomes the only code-mode
surface (`runCode` / `findAPIs`). MultiTool supplies the async semantics for
long-running work. JS-based tool systems give these capabilities to a handler.
`FoundationModels.Tool.call(arguments:)` cannot supply them, because of its
structure.

Shell, files, and MCP move into MultiTool as built-in capability modules. We
remove OperationTool, Shelltool, the MCP package, and the FileTool package. This
is an intentional change away from the operation pattern of the Rust base. We
record this change, and we accept it.

## The capability contract

MultiTool's surface has two tiers. The baseline tier is unconditional. It is on
each MultiTool. It is never behind a Builder option.

| Capability | Surface |
|---|---|
| Quick sync return | A `Tool` call that completes in `waitSeconds` returns its value inline. `ElevatingTool` applies this rule at the `Tool` protocol level, on the native path and on the code path. |
| Long-running with token | The call elevates to a `completionToken`. The `status()`, `wait()`, and `cancel()` builtins do the follow-up. |
| Elicitation | `elicit()` is available at the snippet top level. `ToolContext.elicit` is available in each tool. These are always available. |
| Notification events | `notify()` and `progress()` are available at the snippet top level. `ToolContext.post` and `progress` are available in each tool. These are always available. |
| Discovery | `findAPIs`, `help()`, `docs()` |

The modules are opt-in: `withShell()`, `withFiles()`, and `withMCP(servers:)`.
This agrees with the permission posture. A registered user tool gets the
baseline automatically. Router or `ToolInvoker` binds the ambient context around each invocation. As
a result, a tool pays no cost to use elicitation and events. It also pays no
cost to ignore them.

## The vocabulary and the host substrate are in Router

`OperationEvent`, `OperationEventKind`, `OperationOutcome`,
`OperationEventSink`, and `EventEmittingTool` move out of OperationTool into
Router. The host owns the vocabulary. The host also owns the outbox, the
mailbox, and the ambient `ToolContext`.

MultiTool already has a hard dependency on Router. Its library target links the
`FoundationModelsRouter` product today. Also, the selection tier of
`FindAPIsTool` runs on Router-backed sessions.

Phase 1 adds no new dependency edge. It moves the vocabulary to the Router side
of an edge that exists. The `.other(_)` decoder and the terminal-event scope
contract move without change. They are already correct. The decoder keeps
unknown values.

`ToolContext` in Router has an effect that MultiTool alone cannot supply. Router
binds the task local around native `respond()` also. As a result, a tool sees
the same ambient capabilities on the native token-constrained path and on the
code path. The host layer owns `window`. MultiTool binds again only for each
snippet call, with a new `completionToken`.

Router stays one package with one product. We examined a split that would keep
the MLX build away from tools that send events. But the plan removes the
consumers of such a split. MultiTool imports the full Router today. Shell,
files, and MCP become internal MultiTool folders by the end of phase 4. After
phase 5, no external package imports a hosting product.

The substrate is in a `Hosting/` source folder adjacent to `Session/`. If a
third-party emitter needs an MLX-free import in the future, a product split
along that folder boundary is only a manifest change. No source moves are
necessary.

## Elevation: waitSeconds and the completion token

The elevation engine is at the `FoundationModels.Tool` protocol level, in
Router's `Hosting/` folder. It is not in the code-mode bridge. `ElevatingTool`
wraps `any Tool`. It runs `call(arguments:)` in a race against a `waitSeconds`
timer (default: 5 s). If the call completes in the window, the wrapper returns
the rendered output.

If the call does not complete, the wrapper parks the call in the session
mailbox. The wrapper then posts the synthesized events. It returns the pending
envelope — `{ pending: true, completionToken: "01…" }` — as the rendered
output. The wrapper's `Output` is the rendered value. As a result, a typed
wrapped `Output` does not need to represent the pending case. The model reads
text on the wire in each case.

This engine is a promotion of two designs: MCP's `CallWait` soft deadline and
Shelltool's `RunSupervisor` race. See "Consolidation of the siblings" for the
two-clocks model. The two designs already agree on that model.

There are two mounts, one engine, and two policies. Router applies the wrapper
when it composes the tool list of a native session. There, each call elevates
at `waitSeconds`. MultiTool's `ToolInvoker` sends each `tools.*` call through
the same engine with elevation off. Inner calls run until they complete, and
only the outer `runCode` call elevates (see "The constraint boundary"). One
engine owns the parked runs, the events, and the outcomes in each case.

Follow-up is different for each path, and this is intentional. Code mode has
the `status(completionToken)`, `wait(completionToken, seconds)`, and
`cancel(completionToken)` builtins. The model keeps the token across turns. The
native path has no builtins. Completion arrives as a turn-riding event through
the outbox at the next turn boundary. No follow-up pseudo-tools return.

The token is a ULID. It is the same value as the run's event `correlationID`.
The word is always `completionToken`. Do not write "token" alone. That word
collides with LLM tokens in every other document.

The mailbox is an actor in Router, adjacent to `SessionOutbox`. It has the same
scope: one mailbox for each session. A `runCode` sandbox is per-call and new
for each call. A parked item must not stay in it. `ForkableTool` composition
applies: a fork gets its own mailbox. `SessionOutbox` already obeys the same
rule.

**Parked runs die with the session.** A detached run exists to unblock the
turn; it does not continue after the conversation. A child that continues after
its session has no observer, and its state becomes a manufactured `.lost`.
Session teardown does one deterministic sweep of the mailbox. It processes each
kind with that kind's own semantics:

- Shell runs get `killpg(SIGKILL)` and post `.stopped`.
- MCP requests get the advisory cancel and post `.cancelled` before the
  transport closes.
- Parked Swift tasks get cooperative cancellation.

Each outcome goes into the journal before the session closes. There are no
orphans and no holes in the durable record. Work that must continue after a
session is a different feature (an explicit daemon or a job store). We do not
build that feature until a need exists.

The crash edge: teardown did not run, and the memory-only mailbox is gone.
Restoration marks journaled runs that have no terminal event as `.lost`. This
is the only place where `.lost` appears outside an MCP transport drop.

## MultiTool is a host and an emitter

At build time, MultiTool finds emitters in its registry with a conformance
cast. It connects each emitter to its mailbox sink. This is the same wiring
that Router does today, one level down.

MultiTool itself conforms to `EventEmittingTool`. Router finds it with the same
cast and connects the outbox, without change. MultiTool's sink updates the
mailbox first and then sends the event upstream. One connection point, two
consumers, no new protocol.

If a parked call has no events of its own, the engine makes the events. This
occurs where elevation is on: the native mount, and the outer `runCode` run.
The engine posts one `progress` event at elevation. It posts one `.completed`
event at the end. That event carries the rendered output in `detail`, the
`completionToken` as `correlationID`, and the correct `OperationOutcome`. The
terminal-event contract applies to each elevated run, with an emitter or
without one.

Terminal events always go upstream. This includes runs whose result a snippet
already collected through `wait()`. The outbox line is then unnecessary
narration. But the journal must stay complete. Restoration reads
`OperationEventSegment`. A removed event is a hole in the durable record.

## The ambient context

`ToolContext` is ambient. It is not a parameter. It is a sandbox-wide
capability object with a connection back to the calling session, as `window`
has to a page. Swift's mechanism is `@TaskLocal`:

```swift
struct ToolContext: Sendable {
    @TaskLocal static var current: ToolContext?
    // session-scoped: mailbox, upstream sink, session identity, cancellation
    // per-run: completionToken (minted by the invoker at each binding)
}
```

`ToolInvoker` binds the context around each wrapped call:
`ToolContext.$current.withValue(ctx) { try await tool.call(arguments:) }`. The
invoker mints the run's `completionToken` into each binding. The object has
session scope. The correlation has run scope. The capabilities are:

- `post(_ event:)` and `progress(_ detail:)` — the event path. The context
  supplies this run's `correlationID` before the call.
- `elicit(_ request:) async throws -> ElicitationResponse` — a question to the
  user in the middle of a run. This is only another elevation. The run parks as
  a pending promise. The elicitation request goes upstream through the same
  event chain. The answer comes down through the mailbox and resumes the parked
  continuation. An elicitation is a long-running operation. Its completion is a
  user reply. There is no second machinery.
- Cancellation, the run's `completionToken`, and the session identity.

The host verb for answers is `respond(elicitationId, response)` on
`RoutedSession` (app host → Router → mailbox → resume). Answers address the
elicitation. They never address the run, because one run can hold more than one
pending elicitation at the same time. Elicitation requests ride the event chain
as their own event kind, adjacent to `progress` and `completed`. The section
"The elicitation envelope, fixed to the MCP spec" below gives the exact
envelope.

Ambience has three effects:

1. **No second tool protocol.** The registry keeps one shape: `any Tool`. A
   tool reads `ToolContext.current` when it wants capabilities. It ignores the
   context when it does not. Every conformer that exists works without change.
   Each conformer can opt in without a signature change.
2. **Capture-at-start becomes an enforced rule.** A detached task does not
   inherit task locals. A tool that starts detached work, and then reads the
   ambient context again, finds `nil`. A post through `nil` is already a safe
   no-op. The runtime now enforces the rule that the doc comment of
   `EventEmittingContext` only requested. The text of the rule stays: capture
   the context one time, at operation start, into the object that continues
   after the call.
3. **`connecting(_:)` is a candidate for removal.** The propagation probe of
   phase 1 decides this (see "Phases"). If task locals arrive through Apple's
   `respond()`, we delete the protocol. If they do not arrive, the protocol
   stays as the fallback for the native path. Code mode never depends on it.

## Async JavaScript

We remove the v1 blocking bridge. Phase 1 builds on the promise pump directly.
We do not build a semaphore-based park mechanism and its thread guards only to
delete them later. The rules are:

- Each `tools.<noun>.<verb>()` call returns a JS Promise.
- The bridge wraps the snippet in `(async () => { … })()`. As a result,
  top-level `await` is available.
- Each call starts a Swift Task through `ElevatingTool`.
- When the task settles, control moves back to the JS thread. The bridge
  resolves or rejects the promise. Then it drains the microtask queue.

JS single-thread semantics hold. Interleaved operation occurs only at `await`
points. This is the JavaScript that the model already knows.

Parallel calls become real. `Promise.all([tools.a.read(...), tools.b.fetch(...)])`
starts concurrent Swift Tasks. This is do-more-per-call at the snippet level.
Capabilities keep their own serialization where order is important (atomic file
writes; one shell run for each command). Each async system must do this. Errors
map without change: a rejected promise is a JS exception at the `await` point,
with the same repairable message and the same fix-and-re-call contract.

Cancellation maps to rejection. `cancel()` and the session sweep cancel the
in-flight child Tasks. They reject each pending promise, drain the microtask
queue, and remove the context in the time limit.

Elevation composes. A snippet that continues after `waitSeconds` elevates while
its inner promises stay in flight. Call settlements and elicitation answers
resolve them until the snippet ends in its terminal event. The `runCode`
description gets one more line: await each `tools.*` call; use `Promise.all`
to run calls in parallel.

**One rule specifies what is a promise.** Each call that goes into Swift
effects returns a promise: `tools.<noun>.<verb>()`, `elicit()`, `wait()`,
`status()`, `cancel()`. These calls are synchronous: `help()` and `docs()`
(pure surface reads), and `notify()` / `progress()` (void; they enqueue and
continue; the bridge flushes them). If a call does work or asks a question,
await it. If a call describes or narrates, do not await it.

**A forgotten `await` has four shapes. Three are caught.**

- An unawaited *return* settles at the boundary. `ResultRenderer` awaits a
  thenable final value. As a result, `return tools.x.y(...)` is correct.
- Settle-before-return catches a *floating call*
  (`tools.files.write(...); return "done"`). The bridge records each promise that it creates.
  `runCode` gives no result until all of them settle. The work occurs. A
  floating rejection becomes the run's error. It does not disappear. This is
  the settle window of do-more-per-call, applied at the snippet boundary.
- A Proxy trap catches *property access on a pending result*. The bridge
  returns proxied promises. For each property except `then`, `catch`, and
  `finally`, the `get` trap throws a precise repairable error. The error names
  the call and the property. It asks "did you forget `await`?".
- The shape that stays is *truthiness or arithmetic on a promise*. A trap
  cannot catch this shape. A promise is always truthy. Only the description
  text and the usual repair loop cover it, when the incorrect branch fails
  downstream.

The backstop for all four shapes is the contract that exists: precise,
model-repairable errors and an immediate re-call.

**Session affinity across the seam.** The JS thread is not a Swift task. A JSC
callback lands outside every task tree. As a result, the route never depends on
task-tree inheritance across the seam. It depends on values captured at bind
time.

There is one `RunBinding` for each `runCode` invocation. `ElevatingTool`
captures it when it binds the ambient context. The binding holds the
`ToolContext` (session identity, mailbox reference, sink), the outer
`completionToken`, and the serial executor of the interpreter. Each promise
carries the binding.

Each parallel inner call runs in a Task. The closure of that Task sets the
ambient context again from the binding, explicitly. It never trusts
inheritance. It mints its own per-call `completionToken` from the captured
context. As a result, parallel runs correlate independently. They post to the
mailbox of the same session.

The mailbox is an actor: affinity is possession of the reference, not a
position in a tree. A Task that settles resolves its promise on the binding's
executor, keyed by the promise id. Two sessions that share one registry can
never cross-route, because each invocation captured its own binding. The
inbound route uses no task locals: `respond` / `complete` → `RoutedSession` →
that session's mailbox → the run entry → its resolver, with a hop to the
binding's executor. The route holds references the full way.

## The elicitation envelope, fixed to the MCP spec

The envelope obeys the MCP specification exactly (form mode: 2025-06-18; URL
mode: 2025-11-25). There is no invented shape. `ElicitationRequest` is in
Router's `Hosting/` folder. It carries `mode` (`form` | `url`; if omitted,
form) and `message`.

For form mode, it carries `requestedSchema`: the restricted subset from the
spec. That subset is flat objects with primitive properties only — bounded
strings with `email` / `uri` / `date` / `date-time` formats, numbers, booleans,
single-select and multi-select enums, and defaults. For URL mode, it carries
`url` and `elicitationId`. `ElicitationResponse` is the three-action model:
`accept` | `decline` | `cancel`. `content` is present only on a form-mode
accept.

The request rides the event chain as the third `OperationEventKind` case. Its
payload is the typed request. The third kind changes two contracts. First, the
outbox coalescing policy keeps each elicitation event and never coalesces them.
Only `progress` coalesces.

Second, the terminal-event scope contract now spans three kinds. A run that
posts an event still posts exactly one `.completed`. Elicitation events are not
terminal.

The `elicitationId` is a ULID. It is different from the run's
`completionToken`. One run can elicit more than one time. A URL completion
addresses the elicitation, not the run. Form answers come down through
`respond(elicitationId, response)`.

URL mode resolves in two steps. The accept means only that the user agrees to
open the URL. The completion arrives separately through
`complete(elicitationId)`. The mailbox holds the run open for the completion,
and it ignores unknown ids and completed ids, per the spec. Tools must process
decline and cancel. A declined elicitation is not a cancelled run.

Our boundary enforces the restricted form schema for each elicitor: snippet
`elicit()`, `ToolContext.elicit`, and MCP passthrough. As a result, passthrough
loses nothing, and a host form UI stays a flat form. The trust rules of the
spec bind the host seam. This document records them as normative for the
presenting app:

- Sensitive information (credentials, keys, payment) goes through URL mode
  only, never through a form.
- The host shows the full URL.
- The host never pre-fetches the URL.
- The host never opens the URL without explicit consent.
- The host opens the URL in a surface that the client and the model cannot
  inspect.

These obligations are on the presenting layer (AgentViewKit's concern later).
They are not on Router. Router only carries the typed envelope.

## The sandbox globals

The snippet-facing surface is the same idea, one level up: a flat, window-like
set of globals. It extends the `tools.*` / `help()` / `docs()` pattern that
exists with `status`, `wait`, `cancel`, `elicit`, `notify`, and `progress`. A
long snippet loop posts `progress()` directly. The outbox coalesces it like the
progress event of each tool.

`elicit` at the snippet top level is a capability that the parameter design did
not have. The model itself can stop for a user answer in the middle of a
snippet, with no tool between:

```javascript
const repo = await elicit("Which repository should I target?");
return tools.github.createIssue({ repo, title });
```

It parks and resumes through the same elevation path as every other call.

`elicit()` returns a promise like every other call (see "Async JavaScript").
The snippet awaits it. The control flow gets the answer. No OS thread is held
while the user thinks.

The model's turn is also not held. The outer `runCode` run elevates past
`waitSeconds`, and the model gets the pending envelope. The pending items are a
promise plus a suspended JSC context. `respond` resolves them, and the snippet
continues from the next statement.

Two guards limit the cost: a configuration cap on live suspended contexts, and
a hard unblock. `cancel(completionToken)` and the session-end sweep reject each
pending promise, drain the microtask queue, and remove the context in the time
limit. This obeys the cancellation-mid-snippet guarantee that exists.

The globals need no `findAPIs` entry. The two tool descriptions carry the full
behavioral contract, with no special system prompt. This is intentional. As a
result, `MultiTool.description` gets one more sentence. That sentence names the
ambient globals: `elicit()`, `notify()`, `progress()`, and the `status()` /
`wait()` / `cancel()` run verbs.

`findAPIs` stays only about the discovery of `tools.*` functions. The globals
are not searchable entries. A search result implies an item that can be found
or absent. These globals are always present.

`findAPIs` finds APIs. It does nothing else. It is never a view of running
state. It is never a run-plane surface. Its growth is upward, not sideways.

Each result carries the declaration, the doc comment, and a sample snippet that
shows a correct call. As a result, the model copies a correct shape. It does
not infer one.

Rediscovery of in-flight work after compaction belongs to the run plane.
`status()` with no argument lists each pending run: token, op, and latest
progress. Router's compaction boundary carries the live `completionTokens`, in
the same way that boundary metadata keeps discovered-tool state. A
post-compaction model reads its pending work from the boundary. Then it calls
`status()`.

## We remove OperationTool

Schema fusion exists to fit N schemas into a 4,096-token instruction window.
MultiTool removes the same pressure differently: one `runCode` schema plus a
rendered API surface. As a result, the reason for fusion goes away when the
model surface is code mode. The sibling tools become capability modules. Then
nothing outside OperationTool uses `@Operation`. As a result, we remove the
full package: the fused `OperationTool<Context>` runtime, `SchemaFusion`,
noun-in-path dispatch, the macro, and the ArgumentParser CLI driver.

Authors write capabilities directly against MultiTool's own registry surface: a
`ToolDescriptor` plus a plain `Tool` conformer that reads `ToolContext.current`.
`EventEmittingContext` dissolves into the ambient context. Typed per-capability
contexts (`ShellContext`, `FileContext`) stay as usual constructor
dependencies.

The change away from the Rust base is in machinery, not in taxonomy. Dispatch
becomes the rendered code API instead of fused operations. The `{verb} {noun}`
structure stays as the registration shape and the surface layout (see
"Registration of capabilities: noun/verb"). We accept this. It is narrower than
first stated.

Per-capability CLIs (`FileToolCLI`, Shelltool's dual-use verbs) go away with
the driver that made them. `multitool-cli` becomes the single demo and test
binary. This closes the earlier open question of a test binary different from
`sah`.

## Consolidation of the siblings

I read all three repositories. The central conclusion: **the elevation
machinery already exists two times.**

FoundationModelsMCP has `CallWait`. It contains:

- a soft deadline that detaches the call
- a `RunningCall` / `CallHandle` registry
- the `get_result` / `list_calls` / `cancel_call` follow-up tools
- throttled progress
- one terminal `OperationEvent`.

Shelltool has `RunSupervisor` / `ShellRunner`. It contains:

- a deadline race that detaches and does not kill
- a `ProcessRegistry` with an exit sweep
- a capture-at-start sink that posts detached events.

As a result, consolidation is promotion, not construction. One elevation engine
goes in `ToolInvoker` plus the Router mailbox. We delete the two local designs.

The two-clocks model of MCP goes into the engine without change. `waitSeconds`
limits *the block of the tool call*. Nothing resets it. A per-call `timeout`
limits *the work itself*. Progress resets it.

Progress keeps the work alive. It never gives the caller more wait time. We
remove the MCP follow-up pseudo-tools (`get_result`, `list_calls`,
`cancel_call`) and the equivalent Shelltool operations. The uniform `status()`
/ `wait()` / `cancel()` builtins replace them.

**Shell** (`Capabilities/Shell`) gets `ShellRunner`, `OutputBuffer`, the
`.shell` dotfolder with the history of each session, the `grep history` /
`get lines` operations, and `ShellPolicy`. The three policy outcomes stay:
allow, deny, ask. But the ask outcome changes its meaning. Today it refuses,
because the tool cannot speak to a human.

With elicitation always available, ask goes through `ToolContext.elicit`, and
the remembered-"always" store works as designed. Detach supervision moves to
the shared engine. The `.stopped` outcome keeps its authoritative
`killpg(SIGKILL)` semantics.

**Files** (`Capabilities/Files`) gets the six operations: read, write, edit,
patch, glob, and grep. It also gets `PathGuard` root bounds, `Hashline`, the
shape-inferred dispatch of `EditEngine`, `AtomicWriter`, `FileChangeJournal`,
and the `DiagnosticsBridge`. The FoundationModelsCodeContext dependency comes
with it. Live compiler diagnostics in each write result and edit result is the
full point of the capability, per do-more-per-call. Corrective results (a
payload that cannot resolve; a path outside the root) stay in-band. They are
never thrown.

**MCP** (`Capabilities/MCP`) gets `MCPServer`, `StdioServerProcess`, the
`SchemaConverter` / `GeneratedContentCodec` pair, `ToolContentRenderer` with
its `RenderBudget`, and the `ToolCatalog`. Each connected server registers as
its own top-level group: `tools.github.createIssue`, never
`tools.mcp.github.createIssue`. The model must not see the transport. MCP
progress maps onto `progress` events. Advisory cancellation and transport drop
keep their honest outcomes (`.cancelled`, `.lost`).

**Elicitation unifies on the MCP shape.** `ElicitationCoordinator` already
serves the two directions: server-initiated `elicitation/create` and
agent-initiated. It already specifies the hard case: URL mode is a
three-message flow, and its `notifications/elicitation/complete` arrives
separately from the accept response. `ToolContext.elicit` gets this protocol
without change. The Router mailbox must hold a URL-mode elicitation open past
the accept, until `complete(elicitationId:)` arrives. The host app keeps
ownership of the presenting UI, exactly as the coordinator contract states
today.

**The run plane and the content plane are different surfaces. One identifier
joins them.** The mailbox carries envelopes and outcomes. It never carries bulk
output. `status()` / `wait()` answer lifecycle questions only.

Captured content lives in the store of the capability that owns it. Shell
output stays in the per-session dotfolder. `tools.shell.getLines` and
`tools.shell.grepHistory` read it as usual surface operations. They apply to a
live detached run (`OutputBuffer` reads while the child runs) and to a
completed run (the store stays after the run).

The join: the `commandID` of a shell run is its `correlationID` is its
`completionToken` — one string, two planes. Nested runs obey the same rule. An
elevated `runCode` has its own outer token. Its pending envelope and `status()`
list the child runs found so far. The `detail` of each terminal event carries
the output tail plus the run's identifier. As a result, the model always knows
how to get more.

**Processes and tasks stay different kinds.** Three different objects can be
behind a parked run:

- A Swift task (a parked native call). Cancellation is cooperative.
- An OS process group (shell). `killpg(SIGKILL)` is authoritative. The outcome
  is `.stopped`.
- An MCP request (a protocol task). Cancellation is advisory. The outcome is
  `.cancelled`. A transport drop is `.lost`.

The engine owns the runs: correlation, park state, events, and outcomes. The
capability gives the engine a run body plus a canceler. The canceler carries
the capability's own semantics. `cancel(completionToken)` returns the honest
outcome. This keeps the authority distinction that `OperationOutcome` already
makes mandatory.

As a result, the two registries stay separate. Shell's registry holds the child
process groups of each run. MCP's registry holds the server subprocesses.
Server subprocesses are infrastructure. They have session lifetime, they are
never runs, and they never get a `completionToken`.

To kill a server subprocess is a host-level act on each in-flight call that it
carries. It is not a run cancellation.

**The surface never changes in place. A change means rebuild and swap.**
Servers connect before `buildRegistry()`. A late server, a reconnect, or an MCP
`tools/list_changed` starts a full rebuild. MultiTool renders the new registry
complete at the side. Then MultiTool swaps it in atomically at the next turn
boundary — the same boundary where the outbox folds in events.

Nothing changes below a snippet that runs. An in-flight run keeps the registry
that it started with. The swap does not touch parked runs, because the mailbox
has session scope in Router, not registry scope. The rendered surface is cheap
to rebuild. The transcript is the part that persists.

Surface uniformity is the reward. `findAPIs` searches built-in entries and
user-registered entries in the same way. `help()` / `docs()` render them in
the same way. A snippet composes them freely. The output of a shell command
flows into a file edit and an MCP call in one snippet. The intermediate values
never touch the model's context.

The Builder opts modules in explicitly: `withShell()`, `withFiles(root:)`, and
`withMCP(servers:)`. They are off by default. This keeps the permission
posture at the registry boundary, where the consent system of the runtime spec
gates it later.

## The constraint boundary, and the escape hatch

Code mode does not lose token-level constrained arguments. The boundary moves.
`runCode` is a `Tool` with `@Generable` arguments. Guided generation constrains
that envelope at the token level. The call is always well-formed, and `code` is
always a string.

The guarantee for the arguments of the wrapped tools changes. In the snippet,
those arguments are model-written code. Their validation occurs at runtime,
not at decode time. The two layers of `ToolInvoker` do the validation, with
precise, model-repairable errors and the immediate re-call contract. A
decode-time guarantee becomes a runtime guarantee with a repair loop. That is
different, not lost.

The envelope carries the control surface explicitly. Each argument has `@Guide`
documentation and token constraints:

- `code`.
- `waitSeconds` — the first clock. It sets how long this run blocks before it
  elevates. The default is the configured 5. A value of `0` detaches
  immediately (MCP's `bounded(.zero)` case).
- `timeout` — the second clock. It is the hard limit on the work. Progress
  resets it.

`findAPIs` keeps its search argument as the discovery half. **Inner `tools.*`
calls never elevate.** An awaited inner call runs until it completes, limited
by `timeout`. Only the outer `runCode` elevates.

There is one elevation point, at the boundary that the model already sees. As
a result, no snippet branches on a pending envelope in the middle of code. A
capability that wants detach semantics declares it as a usual argument
(shell's `wait`). The capability then returns the run's identifier for the
builtins. The two clocks appear exactly one time, at the envelope.

Does a weak model do better with per-tool decode-time constraints, or with the
code envelope plus the repair loop? That is an empirical question for the gated
evaluations, not a known deficiency. The plain-`Tool` registration path stays
because it is free. The registry holds `any Tool`, and `ElevatingTool` wraps
each path in the same way. The path does not stay because code mode is
deficient. Code mode is the default surface.

## Registration of capabilities: noun/verb

Registration is one repeatable shape. It keeps the noun/verb taxonomy. We
removed the fusion machinery. We did not remove the structure. The path grammar
is fixed: **each entry is `tools.<noun>.<verb>` — exactly two segments, no flat
entries.**

A `Tool` conformer that exists already supplies the verb: `Tool.name` is the
verb. As a result, the registration primitive is `register(noun:tool:)`. It
supplies only the noun. A `Capability` is only a noun plus its `[any Tool]`.
`Builder.withCapability(_:)` fills in the noun one time. Each conformer drops
in without change.

MCP obeys the same grammar. The server is the noun, and the tool is the verb
(`tools.github.createIssue`). Nouns are unique. Registration rejects a
duplicate noun. An MCP server with the name `files`, against the files
capability, fails loudly at `buildRegistry()`. It does not fail silently at
dispatch.

The renderer and the selection grammar enforce two segments. The path, the
`findAPIs` result, the `help()` entry, and the event `op` all come from the
one pair: `tools.<noun>.<verb>` on the surface, `"verb noun"` in the journal.
The surface reads as we want the model to think: `tools.files.edit({...})`,
`tools.shell.execute({...})`.

The layout is one folder for each noun and one file for each verb.
`Capabilities/Files/Edit.swift` holds the `@Generable` Arguments, the Output,
the handler that reads `ToolContext.current`, the doc comment, and one example
snippet. `findAPIs` serves that snippet as the sample for that entry.

`OperationEvent.op` stays the canonical `"verb noun"` string. Registration
derives it as `"\(verb) \(noun)"`. As a result, Router renders the journal and
the outbox without change.

Built-in capabilities and user capabilities are the same thing. `withShell()`
is a short form of `withCapability(ShellCapability(...))`. Third-party Swift
code registers through the same protocol. That identity is the repeatable
part.

## The instruction footprint

The "available tools" block that goes to the system prompt is two schemas —
`runCode` and `findAPIs` — plus their description text. It is small and
constant, independent of the number of capabilities and servers in the
registry. Constant means cacheable. Prefix reuse works across turns and
sessions. The block fits the 4,096-token on-device window, with space for
work.

All other content is behavior, and the two descriptions carry all of it. There
is no special system prompt, as fixed today. `runCode` keeps its half: never
guess function names; answer only from what the tools return; on an error,
repair and re-call immediately.

The half of `findAPIs` is the caution: *present your problem*, in task terms,
and learn what exists. Do not do a name search for a function that the model
already believes in. A problem statement retrieves. A guessed name confirms a
bias.

We measure the discipline. We do not hope for it. The gated suite keeps the
trajectory gate for search-then-call (`findAPIs` before `runCode`) as the
regression test. That test shows that the contract text continues to work as
models and descriptions change.

## Phases

Each consolidation is one phase. Each phase gets its own tag at completion.
The exit criterion of each phase is a deletion. When the last phase lands, the
Shelltool, FileTool, MCP, and OperationTool packages are gone.

**Phase 1 — foundation. Tag: `consolidation-1-foundation`** (Router and
MultiTool). The scope:

- The `Hosting/` folder in Router. The event vocabulary becomes Router's.
  Router drops its `Operations` import.
- The siblings continue to compile through a transitional shim. `Operations`
  becomes typealiases that re-export Router's canonical types. As a result, one
  build that holds the two imports (ACPAgent does) sees one type, not two
  ambiguous types. The shim pulls MLX transitively into the builds of the
  doomed packages. This is temporary build weight only, and we schedule
  each payer for deletion. The shim itself dies with OperationTool in phase 5.
- The mailbox actor adjacent to `SessionOutbox`.
- The `ElevatingTool` engine at the `Tool` protocol level, with the two-clocks
  model. Router mounts it for native sessions. `ToolInvoker` mounts it for
  `tools.*` dispatch.
- The `status()` / `wait()` / `cancel()` builtins.
- The ambient `ToolContext`, with `elicit` and `notify` on the MCP coordinator
  shape.
- The promise-pump interpreter that replaces the v1 blocking bridge (see
  "Async JavaScript").
- MultiTool as host-and-emitter, with synthesized events for parked native
  calls.

Phase 1 includes the **propagation probe**, a gated test that answers one
question. When Apple's `LanguageModelSession.respond` calls a tool, does the
task-local `ToolContext` arrive, or is it `nil`? One probe tool reads
`ToolContext.current` inside `call(arguments:)`. The test binds the context
around `respond()`. It runs one prompt on the MLX path and one on the system
model. The two answers are both acceptable, and we decide the two branches now:

- The context propagates → native tools get the ambient context free. We
  delete `EventEmittingTool` / `connecting(_:)` in this phase.
- The context does not propagate → native tools keep composition-time wiring.
  That wiring must carry the *full* context: the sink and the mailbox.
  `ElevatingTool` reads the mailbox from the ambient context, and elevation on
  the native path would break without the full context. The protocol stays.

The two results have no effect on code mode. `ToolInvoker` binds the context
itself, and no Apple code is in that path. The probe gates a file deletion. It
never gates the phase.

Exit: Router imports no `Operations` (only the shim points the other way). The
Router and MultiTool gated suites are green. The org-wide zero-imports check
is the exit of phase 5, not of this phase.

**Phase 2 — shell. Tag: `consolidation-2-shell`.** `Capabilities/Shell` gets
`ShellRunner`, `OutputBuffer`, the `.shell` dotfolder, the history operations,
and `ShellPolicy` with ask routed through `ToolContext.elicit`. Detach
supervision moves to the shared engine. We delete `RunSupervisor` and the race
logic of the shell `ProcessRegistry`, and the engine replaces them. Shell is
the reference emitter. Its detached commands prove the elevation path end to
end. Exit: ACPAgent, Extras, and Skills — the three org consumers of
Shelltool — move to the MultiTool capability, and we archive the
FoundationModelsShelltool repository.

**Phase 3 — files. Tag: `consolidation-3-files`.** `Capabilities/Files` gets
the six operations, `PathGuard`, `Hashline`, `EditEngine`, `AtomicWriter`,
`FileChangeJournal`, and `DiagnosticsBridge`. It brings the
FoundationModelsCodeContext dependency. Exit: ACPAgent and Skills move off
FileTool, and we archive the FoundationModelsFileTool repository.

**Phase 4 — mcp. Tag: `consolidation-4-mcp`.** `Capabilities/MCP` gets
`MCPServer`, `StdioServerProcess`, the codec pair, `ToolContentRenderer` +
`RenderBudget`, and `ToolCatalog`. Servers register as top-level groups. We
remove the follow-up pseudo-tools, and the builtins replace them. The
`ElicitationCoordinator` protocol becomes the host seam of
`ToolContext.elicit`, URL mode included. Exit: we archive the
FoundationModelsMCP repository. ACPAgent, its one org consumer, moves first.

**Phase 5 — operation. Tag: `consolidation-5-operation`.** Nothing imports
`Operations` or `OperationsCLI` any longer. We make sure of this across the
org. We do not assume it. Skills is the last known consumer and moves here.
The per-capability CLIs are gone, and `multitool-cli` is the single demo and
test binary. Exit: we archive the FoundationModelsOperationTool repository.

The order is fixed: 1 → 2 → 3 → 4 → 5. Phases 2–4 each depend only on phase 1.
But they land serially. As a result, the elevation engine hardens against one
consumer at a time. Shell goes first, as the emitter that tests each path.

## Open

None. The sections above settle every item from the plan work.
