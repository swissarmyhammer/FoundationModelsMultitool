---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0021vgq5hs6a9qw6bms6wm7
  text: |-
    ### Router's half: filed, with the evidence

    `respond` does **not** self-drain today. Read in their tree, not assumed:

    - `respond(to:maxTokens:)` (`Session/RoutedSessionActorGeneration.swift:18`) awaits generation only. Its own comment says it composes the prompt with "whatever the outbox drains for this turn" — the outbox, which is not the run plane. Nothing in that file touches the mailbox.
    - `sweep()` is teardown driven by `close()`: it *cancels* parked runs and synthesizes their terminals. It is the opposite of draining them.

    So this card's prediction was right, and it is now a defect rather than a design choice, because `^cv98vff` landed: a tool call no longer returns data on any surface.

    Filed as **`^nmpejc5`** on Router's board — "respond(to:) must self-drain the run plane before it returns" — with the four consumer assertions, and with the hazard called out rather than deferred: a drain that feeds settled results back to the model invites another turn, which may park more runs, so the termination rule belongs in their design. Their session has it.

    ### Our half: written, gated, and honest about what it will do today

    `RespondDrainTests.swift` plus `runRespondDrainScenario(...)` in `ScenarioRunner.swift`. It runs the compose/chain scenario — two tools, so a drain that collected only the first shows up as a wrong answer rather than a lucky one — through `respond`, then the same scenario through a drained `streamEvents` on its own session.

    **It is written to fail until Router's half lands, and its own doc comment says so**, so a red run reads as the requirement being observed rather than as a flake.

    Making "nothing survives the call" observable needed one thing: a session's run plane is reachable only through a `ToolContext`, which exists only inside a tool call. `ScenarioCallLog` now keeps the first ambient context its fixture tools ran under, and reads `parkedRuns()` off it after the turn. That is the product's own public capability — the same one `status()` and `wait` use — not a back door.

    ### One deliberate departure from this card, and why

    The card asks for answer parity **by equality**. Two independent live generations are not byte-equal, so a literal `==` would be a sampling gate wearing an assertion's clothes: green or red by luck, and the first thing a later reader would "fix" by loosening. Parity is asserted on substance instead — which accepted answers each reply contains must match, so both surfaces name the same fixture value and neither names a different one.

    The card's real worry is preserved exactly: parity is asserted **beside** groundedness, never instead of it, so two surfaces refusing identically still fails.

    ### Acceptance criteria

    - [x] The gated scenario exists, compiles, and is skipped with `MULTITOOL_INTEGRATION` unset (ungated suite green: 335 in 27, 49 in 8)
    - [ ] A `respond` run whose `runCode` backgrounds still reaches the **grounded** answer
    - [ ] Answer parity with a drained `streamEvents`
    - [ ] No pending run survives the call
    - [ ] A `respond` turn needs no `wait` call

    The four gated criteria need two things that are not ours: real hardware, and Router's `^nmpejc5`. This card stays in review until both are in.

    ### Kept, as this card asked

    The streaming scenarios did not move. `SearchThenCallTests` and `ElevationTests` stay on `streamEvents`, and this suite sits beside them — `respond` draining everything is exactly what would make it the easy surface to drift onto.
  timestamp: 2026-08-14T11:55:53.239969+00:00
- actor: claude-code
  id: 01m02xyw533crpd1fdj1fv4yam
  text: |-
    ### Gated run: three criteria met, and the fourth was a wrong assertion.

    Router's half landed (`d2be019`, their `^nmpejc5`), so this suite ran for the first time. Result, twice:

    ```
    RESPOND-DRAIN respondSelfDrain elapsed=102.6s parked=0 waitCalls=2 groundedIn=["getTrip","getWeather"] accepted=["SFO","San Francisco"]
    RESPOND-DRAIN respondSelfDrain stream                              groundedIn=["getTrip","getWeather"] accepted=["SFO","San Francisco"]

    RESPOND-DRAIN respondSelfDrain elapsed=79.1s  parked=0 waitCalls=1 groundedIn=["getTrip","getWeather"] accepted=["SFO"]
    RESPOND-DRAIN respondSelfDrain stream                              groundedIn=["getTrip","getWeather"] accepted=["SFO"]
    ```

    Grounded in both fixture tools, parity with the drained stream in both runs, and an empty run plane on return.

    ### The fourth criterion was wrong, and this card should own that

    > A `respond` turn needs **no `wait` call** to reach its answer. If the model has to call `wait` on this surface, the drain is not doing its job.

    Measured: `waitCalls` is 1-2. The reasoning does not survive `^cv98vff`. Every `runCode` backgrounds on **every** surface now, and the pending envelope it returns instructs the model to collect it — `PendingRunEnvelope.renderedMidfix`: *"Call this tool again with a snippet that does: return await wait(...)"*. The assertion demanded the model ignore an instruction the product gives it. Changed to report rather than assert, with the reason recorded at the assertion site.

    ### The finding that matters more, and it is uncomfortable

    **This suite does not prove the drain works.** `parked=0` on return is necessary but not sufficient, because two different things empty the run plane:

    1. the model collects in-band, because the envelope told it to;
    2. the turn ends with runs still parked, and `respond`'s drain settles them.

    Measured, **(1)** happens. So the scenario exercises the blocking surface — same grounded answer, same accepted set, nothing dangling — while leaving Router's drain **untouched**, because the model left it nothing to do.

    Isolating the drain needs a turn that ends with a run still in flight: a snippet that starts long work and returns without awaiting it, so the model answers while the run is going. That scenario does not exist. Until it does, nobody should cite this test as proof the drain works, and the runner's own documentation now says so.

    ### Acceptance criteria

    - [x] A `respond` run whose `runCode` backgrounds still reaches the grounded answer
    - [x] Answer parity with a drained `streamEvents` (on substance, not bytes — the departure was recorded when the runner was written)
    - [x] No pending run survives the call
    - [x] ~~A `respond` turn needs no `wait` call~~ — retired as unsound; `wait` calls are reported instead
    - [ ] **New, and not done: a scenario that isolates the drain by leaving a run in flight at turn end**

    The last one is genuinely open work created by this run. It is small, it needs no Router change, and it is the difference between "the surface behaves" and "the drain works". Filing it rather than closing this card on a technicality.
  timestamp: 2026-08-15T14:42:04.579864+00:00
depends_on:
- 01KZRJNSJRB1RGKQDEBCV98VFF
position_column: done
position_ordinal: c480
title: respond must self-drain the run plane, and gated tests must prove it
---
The fifth task. Depends on `^cv98vff`, because the requirement only bites once `runCode` always backgrounds.

> we also need to add some integration tests with `respond` -- self-draining blocking mode in router, and make sure `respond` provides that self draining behavior in router

## Why this becomes load-bearing

Once `runCode` **always** hands back a token, `respond(to:)` has to drain more than the generation. A turn's tool call no longer returns data — it returns a reference to work still running. So:

- If `respond` awaits only the turn, it returns an answer written from **a token and nothing else**. That is precisely the failure already measured on the streaming surface: `invoked=[] returned=[]`, "I don't have access to real-time weather data".
- "Blocks and drains" therefore has to mean **drains the run plane**: every run this turn parked is settled, and its result is in the model's context, before `respond` returns.

Put plainly: on streaming, backgrounding is the feature. On `respond`, backgrounding must be **invisible** — same final answer, just slower. That is what makes `respond` still FoundationModels semantics rather than a degraded surface.

## Two halves

**Router's half.** Confirm `respond` actually self-drains, and fix it if not. It is not enough for the turn to end; the parked runs it spawned must settle and reach the model first. Router has the machinery — `SessionMailbox.sweep()`, the journal, and the text preamble — but the current design folds a settled run's outcome into *the next turn's prompt*, which for `respond` means the answer is written before the data arrives. File on Router with this card as the consumer requirement.

**Our half.** Gated coverage that would fail if `respond` did not drain:

- [ ] A `respond` run of a scenario whose `runCode` backgrounds still reaches the **grounded** answer — the fixture's own distinctive value, with `returnedPaths` showing the tool really returned
- [ ] Answer parity, asserted by equality: the same scenario through `respond` and through a drained `streamEvents` produce the same final answer. This is the one job `respond` keeps in this suite
- [ ] No pending run survives the call: after `respond` returns, the mailbox has nothing parked. A dangling token means the drain is incomplete even if the answer happened to be right
- [ ] A `respond` turn needs **no `wait` call** to reach its answer. If the model has to call `wait` on this surface, the drain is not doing its job

## Why the parity test is not enough on its own

Two runs can agree on a wrong answer. Both surfaces refusing identically — "I don't have access" — satisfies equality while proving nothing, and that is not a hypothetical: it is what every recorded run of both surfaces did. So parity is asserted **alongside** groundedness, never instead of it.

## Do not let this hide the streaming path

`respond` draining everything makes it the easy surface to test, and a suite that drifts onto it stops observing the three rules entirely. The gated scenarios stay on streaming; `respond` coverage is added beside them, not in place of them. #eventplan