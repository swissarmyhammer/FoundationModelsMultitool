---
assignees:
- claude-code
position_column: todo
position_ordinal: '8780'
title: respond(to:) must self-drain the run plane before it returns
---
Filed by the `FoundationModelsMultitool` session as the consumer requirement behind its card `^n6kgckr`.

## What we found in this tree

`respond(to:maxTokens:)` (`Session/RoutedSessionActorGeneration.swift:18`) awaits **generation only**. Its own comment says it composes the prompt with "whatever the outbox drains for this turn" — the outbox, not the run plane. Nothing in that file touches the mailbox.

`sweep()` is teardown driven by `close()`: it *cancels* parked runs and synthesizes their terminals. It is the opposite of draining them.

So today a `respond` turn that parks a run returns with the run still parked, and its result reaches the model only if a *later* turn folds it in.

## Why that is now a defect rather than a design choice

`FoundationModelsMultitool` just made `runCode` **always** background (its `^cv98vff`). A turn's tool call no longer returns data — it returns a reference to work still running. So on `respond`:

- The model writes its answer from **a token and nothing else**. That is not hypothetical; it is the failure already measured on the streaming surface before the run plane existed: `invoked=[] returned=[]`, and an answer of "I don't have access to real-time weather data".
- The caller asked for FoundationModels semantics — block, then give me the answer — and got a surface that returns before the work it started has finished.

On streaming, backgrounding is the feature. **On `respond`, backgrounding must be invisible: the same final answer, just slower.** That is what keeps `respond` a real FoundationModels surface rather than a degraded one.

## The requirement

Before `respond(to:)` returns, every run that turn parked has settled and its result has reached the model's context. Concretely, a consumer must be able to assert all four:

1. the answer is **grounded** in what the backgrounded tool actually returned, not in the token;
2. after the call returns, the session has **no parked runs left**;
3. the caller never had to call a `wait` tool to get there — if the model must call `wait` on this surface, the drain is not doing its job;
4. the same scenario through `respond` and through a drained `streamEvents` reaches the **same** final answer.

## The hazard to design against

A drain that feeds settled results back to the model invites another turn, which may park more runs. The loop must terminate. Whether that is "drain only what this call's turn parked", a re-entry bound, or something else is Router's call — but a `respond` that can spin forever is worse than one that returns early, so the termination rule belongs in the design, not in a follow-up.

Please also say plainly, in the `respond(to:)` doc comment, which surface drains what. A consumer reading it today cannot tell that the outbox and the run plane are different things that drain at different times.

## Acceptance Criteria

- [ ] `respond(to:)` does not return while a run parked by its own turn is still in flight
- [ ] The settled result reaches the model in the same call, so the answer is written from the data rather than from a token
- [ ] The termination rule is chosen, documented, and covered by a test that parks a run from inside a drained turn
- [ ] `streamEvents` behaviour is unchanged — backgrounding stays the feature there; a shared drain must not quietly make streaming block too
- [ ] The `respond(to:)` doc comment says what it drains, and what it does not
- [ ] `swift build` clean and `swift test` green

#eventplan