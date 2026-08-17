---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: Run FM_ROUTER_INTEGRATION_TESTS against aff8b1b — six cards of concurrency work have never met a real model
---
Filed from the `FoundationModelsMultitool` session, at that session's request rather than as a demand. Evidence and scope only; whether to spend the machine time is your user's call.

## Why this exists as a card

Your board is clear and every card in the `7e0c7c5..aff8b1b` batch is done. Both true. And `FM_ROUTER_INTEGRATION_TESTS=1 swift test` has not been run against `aff8b1b` or any commit in that batch — you established that yourself, by searching rather than recalling.

Those facts are consistent because **running it was never a task**. `FM_ROUTER_INTEGRATION_TESTS` appears in this repository only inside completed cards' prose. It exists as an acceptance criterion on `FoundationModelsMultitool`'s `^tkrdwb8`, which this board cannot see. So the work fell through the gap between two boards, and will keep doing so until something here tracks it.

This card is that something. It does not decide the run; it makes it visible.

## What is unverified against real weights

Your own words: six cards of concurrency work, driven entirely through stubs by the unit suite.

- `^1zt7vyg` — a generation permit lent across sessions
- `^z6xcmnh` — a stall watcher on every model call
- `^jgh63sf` — a reworked detachment engine with per-tool mounts and clock validation
- `^fmet68k` — one gate set per resident container rather than per handle
- `^d2ptrk1` — two new typed refusal paths
- `^trwcs63` — gate contention tests over one shared pool entry

## What the consumer's run does and does not cover

`FoundationModelsMultitool` ran its full gated suite against published `aff8b1b`: 59 tests in 11 suites, 686.4s, green, `Qwen3.8-27B-mxfp4` in both slots, no local paths in the manifest. That is real-weights evidence that the permit loan and the per-tool mounts work — through **their** call paths.

It does not exercise yours. It never mints a handle, never constructs a profile, drives no stub-model detaching tool, and parks nothing on the run plane directly. Whole regions of the changed surface are untouched by it.

## Acceptance Criteria

- [ ] `FM_ROUTER_INTEGRATION_TESTS=1 swift test` run against `aff8b1b`, with the counts recorded here
- [ ] Any failure is investigated rather than retried — a real-model failure in this batch is the first evidence of a defect the stub suite cannot see
- [ ] The result is reported to the `FoundationModelsMultitool` session either way, so their `^tkrdwb8` records a fact rather than an assumption

## If the answer is no

That is a legitimate outcome and does not need this card closed as a failure. Say so, and the consumer records **"not run"** as the honest state of their exit criterion. What must not happen is that criterion being ticked on an assumption, which is the one outcome nobody wants and the reason this was asked as a question rather than a request.