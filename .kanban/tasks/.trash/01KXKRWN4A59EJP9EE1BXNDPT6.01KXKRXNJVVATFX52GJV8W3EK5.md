---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: Support model_type "ministral3" (Devstral-2-123B) in LLMModelFactory
---
## What

`mlx-community/Devstral-2-123B-Instruct-2512-4bit` (Mistral's large Devstral 2, 14 shards ~65GB at 4-bit) fails to load with `.unsupportedModelType("ministral3")` — its `config.json` declares `model_type: "ministral3"`, which has no entry in `LLMModelFactory`'s registry. The 24B `Devstral-Small-2` declares `mistral3` and loads fine (via `Mistral3TextModel`), so `ministral3` is likely the same or a close variant of the Mistral3 architecture — check the upstream `transformers`/`mlx-lm` implementations for whether it can simply alias to `Mistral3TextConfiguration`/`Mistral3TextModel` or needs its own config (e.g. different attention/rope details).

Reproduced 2026-07-15 via FoundationModelsMultitool's gated suite on M3 Ultra; weights fully cached locally (`~/.cache/huggingface/hub/models--mlx-community--Devstral-2-123B-Instruct-2512-4bit`), so verification needs no re-download.

Also check `ToolCallFormat.infer` — it matches the `mistral3` prefix; `ministral3` does NOT start with "mistral3" (extra "ni"), so it needs its own prefix match to get the Mistral tool-call format/parser too.

## Acceptance Criteria

- [ ] `model_type: "ministral3"` resolves to a working model implementation in `LLMModelFactory`.
- [ ] `ToolCallFormat.infer` maps `ministral3` to the Mistral tool-call format.
- [ ] Devstral-2-123B-Instruct-2512-4bit loads and completes at least one tool-call round trip end to end.
