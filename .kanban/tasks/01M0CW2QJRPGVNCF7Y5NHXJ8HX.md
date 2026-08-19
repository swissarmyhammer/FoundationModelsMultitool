---
assignees:
- claude-code
position_column: todo
position_ordinal: '8180'
title: 'InBandCollectionCanary: test the background-run mechanism with a delayed echo, and split the teaching claim off it'
---
`InBandCollectionCanaryTests` exceeded its 600-second ceiling on CI run `32203706380` — the only failure in a run where the other ten suites passed. It is the most expensive suite in the target and it grades two unrelated things through one costly model loop.

Design worked out with the user 2026-08-19; the delayed-echo shape is theirs.

## What the test actually checks, in plain terms

`runCode` runs the tool call in the background and returns a handle. `wait(handle)` collects the result. Two different parties can do that collecting:

- **the model**, by calling the mounted `wait` tool, or
- **`RoutedSession.respond(to:)`**, which collects anything still outstanding when the call ends.

Both produce an answer that looks right, so `validAnswer` and `grounded` cannot tell them apart. The discrimination is `inBandCollection` (`waitCalls > 0`), `runPlaneEmptyAtAnswer` (nothing outstanding when the model's **first** turn ended) and `runPlaneEmpty`.

So the question under test is **who collected the result**, not whether the answer was right.

## Two properties are bundled, and only one needs the expensive setup

**A — the mechanism.** A tool call runs in the background, returns a handle, and the result comes back through that handle intact. Pure plumbing.

**B — the teaching.** The prompt tells the model *not* to block. So the only thing that can make it call `wait` is the instruction carried on the handle itself, competing against the user's explicit request. The recorded run collected anyway, three times over, which is how strongly that in-band instruction outweighs the prompt. This is the evidence behind this package's "in-band teaching beats upfront prose" rule and behind `^466d38p`.

The current suite pays for a full discovery -> snippet -> background-run -> collect -> answer loop to establish a precondition, when everything it grades happens strictly after the handle is in the model's hands.

## The current fixture never exercises "later"

`IntegrationArchiveRebuildTool` returns **immediately** — it hands back the manifest code with no delay. The comment at `Fixtures/ScenarioTools.swift` says the delay was removed deliberately. But the model then has to generate a whole turn before it calls `wait`, and that takes seconds, so the result is always already available by the time anything collects it.

**The suite named for deferred completion has never once collected a result that was not already finished.** `wait` returns instantly every time. The deferred path — a real deadline, a real wake-up — is untested.

## What to build

**A delayed echo tool.** Takes a value, returns a handle, and settles with that value a few seconds later. Prompt the model explicitly to call it by name and report what comes back. That gives:

- a genuinely deferred completion, so `wait` must actually wait and be woken — more mechanism covered than today
- exact grounding: echo a nonce the model has never seen, so the reply either carries it or it does not; no fixture constant and no grounding judgment
- the shortest sequence that still passes through the real machinery — with `directMode()` there is no discovery at all: call the named tool, take the handle, `wait`, report

The delay costs wall-clock, not compute. That is the right trade: it buys real coverage of the deferred path while removing model turns.

**Keep one adversarial run for B.** An explicit "call it and wait" prompt makes `inBandCollection` a test of the prompt, which is exactly what the current suite's own comment warns against: "A prompt that asked the model to wait would make `inBandCollection` a test of the prompt; this one makes it a test of the product." So B keeps the "do not block" prompt. It just stops being something the everyday mechanism check has to pay for.

`runPlaneEmptyAtAnswer` survives in both shapes — a model that ends its turn with work still outstanding fails it whatever the prompt said.

## Do not

- Do not raise the 600-second ceiling to make CI green. That hides a 70-minute run rather than fixing it.
- Do not delete the adversarial prompt. It is the only evidence for the in-band teaching rule.
- Do not use the old vocabulary in anything new here — see `^820xc9z`. Write the new tool and suite as background run / handle / collect, with states `running`, `complete`, `error`.

## Open question for the run, not for the card

Whether the delayed echo still needs the 27B. Its claim is protocol-following taught in-band, and a nonce echo is structurally impossible to hallucinate, which is a much weaker capability claim than `SearchThenCallTests` makes. Measure it against a smaller model rather than assuming either way — that is the `^ck74mtg` method.

## Acceptance Criteria

- [ ] A delayed echo tool exists whose result genuinely settles after the handle is issued, so `wait` waits and is woken
- [ ] The everyday mechanism test drives the shortest sequence: named tool, handle, collect, report — no discovery
- [ ] Grounding is a nonce, so a hallucinated answer cannot pass
- [ ] The adversarial "do not block" run still exists and still grades `inBandCollection` against the instruction on the handle rather than against the prompt
- [ ] The 600-second ceiling is re-derived from measurement on the slowest machine that runs it, or removed as the wrong instrument — never simply raised

## Tests

- [ ] Ungated `swift test` green
- [ ] Both gated shapes run green locally, per-suite times recorded here
- [ ] A full gated CI run green, with the canary's time recorded against the 4214s whole-run baseline from `32203706380`
