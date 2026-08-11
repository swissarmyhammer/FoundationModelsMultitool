---
assignees:
- claude-code
depends_on:
- 01KZRJQF59Z8CQCW2VVBFFRDPR
- 01KZRJNSJRB1RGKQDEBCV98VFF
- 01KZRJRJAQ77BGS5GQYDDGJPS6
- 01KZRJVF6WWA07R6W0TN6KGCKR
position_column: todo
position_ordinal: '8680'
title: 'CAPSTONE: the gated integration suite passes on streaming, with search/run/wait working end to end'
---
The card the other five are for. Nothing here is new work — it is the claim that the work *landed*, measured the only way it can be.

Depends on all four behaviour cards: `^bffrdpr`, `^cv98vff`, `^ddgjps6`, `^n6kgckr`.

## Why a capstone exists at all

Every fix this session passed its unit tests and changed nothing about a real turn. The description clause forbidding `wait()` was pinned by an assertion and the model wrote `wait(token, 60)` seven times anyway. A green unit suite has repeatedly meant "the code does what I wrote", never "the model can use it".

So this card is the one that cannot be satisfied by construction. It closes on a **recorded gated run**, pasted in, whatever it says.

## What must be true

- [ ] `MULTITOOL_INTEGRATION=1 swift test --filter SearchThenCallTests` — the per-scenario table recorded here verbatim, all four scenarios `result=PASS`
- [ ] Each passing scenario is **grounded**: `returnedPaths` contains what the scenario declared in `groundedIn`, so the answer came from a tool return and not from the model's own knowledge
- [ ] `invented=[]` and no scenario reports `thrash=1`
- [ ] The elevation and async fan-out scenarios pass too — `ElevationTests`, `AsyncFanOutTests` — because they are what exercise a genuinely parked run
- [ ] Ungated `swift test` green, both targets, counts recorded

## What the trace must show, not just the score

A pass with the wrong shape is a false pass, and this suite has produced several. So the run's own trace has to show the design working:

- [ ] `searchTools` returns a catalog **inline** — no pending envelope, no `wait` needed to obtain it
- [ ] `runCode` returns a **token**, every time it is called, in every scenario
- [ ] Where a result was needed, either it arrived on its own or the model called **`wait`** — and `wait` returned the run's `detail`
- [ ] **No `wait(` in any snippet**, and no seconds guessed anywhere by the model
- [ ] `progress=` is non-zero on at least one scenario, with detail in it, proving a slow call reported while running rather than going silent

## Read the trace before believing the score

Prior false passes, all recorded, all worth re-checking against:

- A run scored `grounded=pass` having fetched only the itinerary, naming the warmest city it could not have known (`0981ar3`).
- A run scored `grounded=pass` while both its `tools.*` calls named functions no fixture defined, so nothing ran at all (same task).
- A run passed the compose scenario while answering "there are no cities on your trip" (`k4mj1gm`).

The graders were hardened after each, and the lesson stands: **the number is not the evidence, the trace is.**

## If it does not pass

Record what it actually did — the `SCENARIO`/`RESULT`/`MODES` lines and the `CALL`/`DONE`/`RUN` trace — and file the next fault as its own card. Do not tune a threshold, resample, or re-run hoping for a better draw. Every failure so far has been a structural fault with a single cause, and each was found by reading one trace rather than by averaging several. #eventplan