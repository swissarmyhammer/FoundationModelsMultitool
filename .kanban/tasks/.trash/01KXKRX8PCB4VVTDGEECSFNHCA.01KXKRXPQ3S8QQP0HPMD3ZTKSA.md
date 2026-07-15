---
assignees:
- claude-code
position_column: todo
position_ordinal: '8180'
title: 'GLM4 structural-tag wiring regresses GLM-4.7-Flash: <tool_call> text leaks and grammar runaways'
---
## What

After `cf4fa81` ("derive tool-calling structural tag from inferred ToolCallFormat (wire GLM4)"), `mlx-community/GLM-4.7-Flash-4bit` regressed versus its pre-fix behavior on FoundationModelsMultitool's gated suite (2026-07-15, M3 Ultra, revision `1fbeb5d`):

- **Tool-call text leaking into replies**: the discovery scenario's final reply began with literal un-parsed Qwen-style wrapper text — `<tool_call>{"name": "runCode", "arguments": {"code": "const { findAPIs } = tools;\nconst result = findAPI…` — i.e. the model emitted the QWEN wrapper (not GLM4's) and the parse side (now expecting GLM4 format) didn't extract it.
- **Grammar runaway**: that same reply then degenerated into thousands of repeated `1}7}7}7}7}…` tokens for ~353 seconds — the compiled constraint permitting an unbounded garbage tail.
- Other scenarios ran but `invokedToolPaths` came back empty where the pre-fix run had genuine `tools.*` grounding.

Pre-fix baseline for comparison (same suite, pinned checkout 4330528): GLM-4.7-Flash scored 2/4 route-scored with 21 well-formed parseable tool calls in one scenario and zero output corruption.

Hypothesis to check: the generation-side structural tag and the parse-side `GLM4ToolCallParser` now disagree about which wrapper GLM-4.7-Flash actually emits — the model appears to produce Qwen-style `<tool_call>` (possibly because its chat template or its training uses that shape rather than the GLM4 format the new tag/parser pair assumes), so the constraint fights the model and the parser misses its output. Note Devstral-Small-2 (mistral3) shows the same leak+runaway signature post-update (`<tool_call>` as reply text, digit runaway `tripCities2025060412345…`), suggesting the mismatch may be in the shared seam rather than GLM4-specific.

## Acceptance Criteria

- [ ] GLM-4.7-Flash-4bit completes the four gated scenarios with zero un-parsed tool-call text in final replies and zero repeated-token runaways.
- [ ] Whatever wrapper the structural tag constrains generation to is the same one the parser extracts, per model family, verified against what the model's own chat template declares.
- [ ] Qwen-family behavior unchanged (Qwen3-30B-A3B-Instruct-2507 still passes its scenarios).
