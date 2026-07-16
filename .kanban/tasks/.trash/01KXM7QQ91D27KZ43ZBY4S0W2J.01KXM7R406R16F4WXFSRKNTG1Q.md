---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: Repeated-token runaway + tool-call text leak under constrained tool-calling decode for all non-Qwen families (GLM, mistral3, ministral3)
---
## What

After the `csfnhca` fix (44a96cf, keep Qwen structural tag for glm4) and the ministral3 support (cc1728a), real-hardware runs (2026-07-15 evening, revision cc1728a, FoundationModelsMultitool gated suite, M3 Ultra) show the SAME two failure signatures across **three different non-Qwen model families**, while Qwen models are unaffected:

**1. Repeated-token runaway** — constrained decode degenerates into an unbounded repeated-token tail mid-tool-call:
- GLM-4.7-Flash: `…const result = findAPI1}7}7}7}7…` (thousands of `}7`, ~353s); also a stray digit corrupting plain text ("…APIs that would9")
- Devstral-Small-2 (mistral3): `…tools.tripCities20250604123456789012345678901234567890…` (digits forever)
- Devstral-2-123B (ministral3): `…const weatherPromises10101010101010101010…` (alternating `10` forever)

The signature is identical: the snippet text reaches a point where the model's preferred continuation is presumably masked by the grammar, and decode locks into a short repeated token cycle instead of closing the JSON. Looks like the xgrammar constraint + sampler interplay has a degenerate cycle for these tokenizers — worth checking whether the constraint's allowed-token mask at these points admits only digits/braces and repetition-penalty state resets.

**2. Un-parsed `<tool_call>` wrapper leaking into final reply text** — for glm4 and mistral3 models the reply is literally `<tool_call>{"name": "runCode", …` (composeChain, both families, reproducible). The model emits the Qwen-style wrapper (as the structural tag constrains it to), but the per-family parser (GLM4ToolCallParser / MistralToolCallParser) evidently doesn't extract Qwen-style output — parse format and constrain format still disagree at runtime even after 44a96cf. Either the parsers should fall back to the Qwen/JSON parser when the structural tag is the Qwen tag, or the parser selection should follow the tag actually used for constraining, not the model family.

Also observed post-fix (Devstral-Small): the model announces an action ("I will confirm your booking… Please hold on.") and generation ends with zero parsed tool calls — possibly the same parse-miss with an empty wrapper.

Per-scenario logs available in FoundationModelsMultitool session records; all three models' weights fully cached locally for cheap verification (verify against the REAL models, not just unit tests — the csfnhca acceptance criteria passed unit-level but the live behavior is unchanged).

## Acceptance Criteria

- [ ] GLM-4.7-Flash, Devstral-Small-2, and Devstral-2-123B each complete all 4 gated FoundationModelsMultitool scenarios with zero repeated-token runaways and zero `<tool_call>` text in final replies, verified on real hardware.
- [ ] Parser selection and structural-tag selection provably agree per model at runtime.
- [ ] Qwen3-30B-A3B behavior unchanged.
