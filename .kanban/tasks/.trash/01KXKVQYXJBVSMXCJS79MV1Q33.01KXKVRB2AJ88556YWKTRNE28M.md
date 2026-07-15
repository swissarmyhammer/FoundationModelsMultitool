---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: 'MiniMax-M2 tool-calling transcript rendering: tool-role message rendered without its preceding assistant tool-call turn'
---
## What

Driving native tool calling with `mlx-community/MiniMax-M2-4bit` (model_type `minimax`, arch `MiniMaxM2ForCausalLM`) through `MLXLanguageModel`/`LanguageModelSession` throws on multi-turn tool exchanges:

```
TemplateException: "Message has tool role, but there was no previous assistant message with a tool call!"
```

Reproduced 2026-07-15 (M3 Ultra, 512GB, revision `1fbeb5d`, FoundationModelsMultitool gated suite): 3 of 4 scenarios threw this the moment a tool result had to be rendered back — the assistant tool-call turn is evidently missing/misplaced in the chat array by the time MiniMax's Jinja template validates it. This is the same class of failure as the (fixed) Mistral strict-alternation issue — `cd52383` renders mistral tool-call turns as structured `tool_calls`; MiniMax's family appears to need the same structured rendering path (its template checks that a `tool` message follows an assistant message carrying `tool_calls`).

The 4th scenario (composeChain) rendered but made 0 parsed tool calls and its final reply read like leaked reasoning ("I need to find out what cities are on the user's trip and then check the current…") — worth checking whether M2's interleaved `<think>` output is being handled by the reasoning path or ending up in the text reply.

Note: MiniMax-M2 is one of only two families with a dedicated tool-call parser already wired (`MiniMaxM2ToolCallParser`) — the parse side is ready; it's the render side that blocks it. Weights are fully cached locally (~119GB under `~/.cache/huggingface/hub/models--mlx-community--MiniMax-M2-4bit`), so verification needs no re-download.

## Acceptance Criteria

- [ ] A multi-turn tool-calling exchange renders through MiniMax-M2's chat template without TemplateException (assistant tool-call turn present before each tool-role message).
- [ ] MiniMax-M2-4bit completes at least one real tool-call round trip end to end.
- [ ] M2's thinking output does not leak into the final text reply.
- [ ] Mistral/Qwen/GLM rendering unchanged.
