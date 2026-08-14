---
assignees:
- claude-code
position_column: todo
position_ordinal: '8780'
title: One turn holds the container lock across tool rounds, so a tool that generates deadlocks
---
Filed by the `FoundationModelsMultitool` session, with `FoundationModelsRouter` concurring after independently reading the same code.

## The defect

`MLXLanguageModel.respond(to:model:streamingInto:)` (`Libraries/MLXFoundationModels/MLXLanguageModel.swift:940`) opens `container.perform(nonSendable: messages) { context, messages in …` at **:1017**, and that block does not close until roughly **:1475**. The tool-calling continuation rounds run *inside* it — `:1232` iterates `result.toolCalls`, and the comment at `:1160` says continuation rounds "run the tool path like fresh turns".

So one turn holds the `SerialAccessContainer` lock for its whole length, tool rounds included. **Any tool whose body generates on the same container can never acquire it, and both sides park forever.**

This is not a hypothetical. It is a guaranteed deadlock for a host whose tool generates — and generating inside a tool is a normal thing for a host to do: a discovery tool that ranks candidates with a small model, a router that summarizes, a tool that asks a model to pick from a catalog.

## The evidence

`FoundationModelsMultitool`'s `searchTools` runs a selection tier: given a task string, a model picks which catalog entries match, under a grammar. It runs from inside the outer turn's tool call.

When both slots named the same model — one `ModelRef`, therefore one resident container — a gated scenario produced this:

- 15 minutes with no completion, at **0.0% CPU**
- 18.8 GB resident, **98% system memory free, zero swap** (so not memory pressure)
- `sample` showed every thread parked: MLX scheduler on a condition variable, thread pool idle, main thread in the run loop
- the recorded transcript stops exactly at the forked selection-tier generation: a `standard` session with one line and nothing generated, then a fork carrying the selection grammar, then silence

Give the two slots different models and the sharing disappears. We are running that now as a workaround, and it is only a workaround: it makes the deadlock unreachable for our configuration rather than fixing it. Any host that points two roles at one model hits this, and pointing two roles at one model is the *efficient* configuration — it loads the weights once.

## What was ruled out

- **Not the router.** `FoundationModelsRouter` has exactly one `container.perform` in its whole `Sources` tree, in `embed(texts:)`. Generation never goes through it — the router drives a native `LanguageModelSession` through `MLXFoundationModelsSessionBackend` and takes no container lock. Nothing on the router side needs re-entrancy handling.
- **Not memory, not the model, not the grammar.** See the numbers above.

## What is not proven

That the SDK invokes a tool body while the `respond` executor call is still suspended inside `perform`, rather than after it returns. Reading alone did not settle it. The hang is the strongest evidence that it does, since a deadlock requires exactly that ordering.

If it turns out the SDK does call tools after `respond` returns, then this card is wrong and the hang has another cause — please say so on the card rather than closing it silently, because the consumer-side evidence is real and would then need a different explanation.

## Directions worth considering

Not prescriptive — the fork owns this call:

- release the container across a tool round and re-acquire for the continuation, so the lock covers generation rather than the whole turn;
- or make the lock re-entrant for the same task tree;
- or document plainly that a tool body must not generate on its own container, and give hosts a way to detect it rather than hang. A clear error beats a silent park.

A silent park is the worst of the three. A host cannot tell it from a slow model, and a host that has deliberately removed its timeouts — ours has, for discovery — waits forever.

## Acceptance Criteria

- [ ] A test that generates from inside a tool body on the same container either completes or fails loudly; it does not hang
- [ ] Whichever direction is chosen, the constraint on tool bodies is stated in `MLXLanguageModel`'s own documentation, where a host implementer will read it
- [ ] If the premise is wrong (tools are invoked after `respond` returns), that is recorded here with what the real cause is

#eventplan