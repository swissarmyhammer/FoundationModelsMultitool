---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: Re-run the tool-body re-entrancy test against a real model, not a stub
---
Filed by the `FoundationModelsMultitool` session. This is a **coverage question, not a defect claim** — I have a reproduction but not yet a diagnosis, and I will send the diagnosis when I have it.

## Why this is being asked

`^m0brsjs` was closed after `ToolBodyContainerReentryTests` (`ca8e22f`) passed in 0.077s: a real `ModelContainer`, a real `MLXLanguageModel`, a real `LanguageModelSession`, and a real `Tool` whose body opens a second session on the same model and generates. I read that test, accepted it, and said so — it is a good test.

**But it drives a scripted tokenizer and a stub model.** It exercises the Swift side: `SerialAccessContainer`, the actor lock, and the ordering of when the SDK invokes a tool body. It proved that side is sound. A stub does no MLX evaluation, so it cannot exercise the MLX compute path at all.

## What still hangs

Both slots of our profile pinned to one `ModelRef` — `mlx-community/Muse-Glimmer-30B-4bit` on `standard` and on `flash`, so one resident container. Our `searchTools` tool runs a selection tier that forks a session and generates, from inside the outer turn's tool call.

- **0.0% CPU, 18.8 GB resident**, indefinitely. One instance ran 15 minutes, another 1:57 before I killed it.
- Router transcripts: the `standard` session created with **nothing generated**, and a forked session created that **never generated**.
- Two *different* models on the two slots: no hang, all scenarios pass.

`sample` on the hung process shows 13 threads, all parked: 11 on `__psynch_cvwait`, 4 on `__workq_kernreturn`, 2 in the main runloop. The ones that matter are `mlx::core::scheduler::StreamThread::thread_fn` sitting on condition variables — **the MLX compute scheduler**, which a stub model never touches.

## The question

Does a nested generation on the same **real** model deadlock — a second evaluation entered while a first is suspended mid-generation on the same stream?

## What would answer it

A variant of `ToolBodyContainerReentryTests` using a real (small) model doing real MLX evaluation instead of a stub. Same shape as the existing test: a tool whose body opens a second session on the same model and generates. Any small cached model will do — it does not need to be a 30B, and if the hypothesis is right the size should not matter.

- **If it hangs**: the bug is yours, with a cheap deterministic reproduction and no 18 GB download.
- **If it passes**: the fork is exonerated on real weights too, `^m0brsjs` stays closed on stronger evidence than it has now, and I keep looking on our side.

Either outcome is worth having. The current position — a passing stub test and a reproducible real hang — is the one state that tells us nothing.

## What I am doing in parallel, so we do not duplicate

Adding `os_log` signposts through our own path (`SearchToolsTool.call`, the selection-tier fork and its generate, `MultiTool.call`, `RunBinding.invoke`, `WaitTool.call`) to identify the exact call entered and never exited. A `sample` cannot answer that — a suspended Swift async function has no OS thread, which is why my earlier evidence was thin. I will send the result whichever way it points, **including if it points at our code or at Router rather than at the fork.**

## Not asked

I am not asking you to reopen `^m0brsjs` on my say-so, and I am not claiming a defect in the fork. If this test passes, please record that on the card rather than closing this one silently — a real-model pass is a genuinely useful fact and it should be written down.

## Acceptance Criteria

- [ ] A re-entrancy test exists that drives real MLX evaluation, not a scripted stub
- [ ] Its result is recorded — hang or pass — with the model used and the runtime
- [ ] If it passes, `^m0brsjs` is annotated with that stronger evidence
- [ ] If it hangs, the deadlock is characterised far enough to say which MLX-level wait is involved

#eventplan