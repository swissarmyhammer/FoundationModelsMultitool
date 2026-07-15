---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: Tool-calling transcript rendering violates Mistral3's strict-alternation chat template (Devstral unusable)
---
## What

Driving native tool calling through `MLXLanguageModel`/`LanguageModelSession` with a `mistral3`-family model throws before generation on every multi-turn tool exchange:

```
TemplateException: "After the optional system message, conversation roles must alternate user and assistant"
```

Reproduced 2026-07-15 with `mlx-community/Devstral-Small-2-24B-Instruct-2512-4bit` (model_type `mistral3`, arch `Mistral3ForConditionalGeneration`) via FoundationModelsMultitool's gated suite (M3 Ultra): all 4 scenarios throw this from the template-rendering step — the model never gets to generate. The tool-calling loop's message sequence (user → assistant tool-call → tool result → assistant …) is rendered in a shape Mistral's strict-alternation Jinja template rejects.

The parse/infer side is already mistral3-aware (`ToolCallFormat.infer` matches the `mistral3` prefix; `MistralToolCallParser` exists), so this is specifically the *prompt-rendering* half: the message generator that builds the chat array from the FoundationModels transcript doesn't produce a sequence Mistral's template accepts (e.g. tool results likely need the `tool` role adjacent to the assistant tool-call turn in the exact shape the template's alternation check permits, or need folding into the surrounding turns the way Mistral's reference clients do).

## Why it matters

Devstral Small 2 is arguably the strongest open agentic-coding model runnable on Apple Silicon (68% SWE-bench Verified, purpose-trained for tool-driven work, 24B dense ~13GB at 4-bit, the most-downloaded Devstral MLX build) — and it is currently 100% unusable for native tool calling through this stack, failing before inference on the very workload it's best at.

## Acceptance Criteria

- [ ] A multi-turn tool-calling exchange (user → assistant tool call → tool output → assistant answer) renders through the mistral3 chat template without TemplateException.
- [ ] Verified end to end with Devstral-Small-2-24B-Instruct-2512-4bit generating at least one real tool-call round trip.
- [ ] Non-Mistral families' rendering unchanged (regression-guard Qwen/GLM paths).
