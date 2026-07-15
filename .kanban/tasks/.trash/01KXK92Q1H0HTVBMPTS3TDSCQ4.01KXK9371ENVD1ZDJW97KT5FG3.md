---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: Tool-calling structural tag should follow the inferred ToolCallFormat, not hardcode Qwen's <tool_call> wrapper
---
## What

`Libraries/MLXFoundationModels/GuidedGeneration/SchemaConverter.swift`'s `encodeToolCallingGrammar(tools:)` hardcodes Qwen's `<tool_call>\n…\n</tool_call>` structural tag (with a bare-JSON alternative) for every model, while the parse side already does the right thing per model: `LLMModelFactory` infers a `ToolCallFormat` from the config's `model_type` (`Libraries/MLXLMCommon/Tool/ToolCallFormat.swift` — `glm4*` → `GLM4ToolCallParser`, `gemma4` → its parser, `lfm2*`, llama3 heuristics, etc.).

So a non-Qwen model's guided tool-calling decode is constrained toward a wrapper format it wasn't trained on, while its chat template presents tools in its own native format — a layering mismatch. The generation constraint should be derived from the same inferred `ToolCallFormat` the parser uses (each format contributing its own structural-tag spec), so both halves of the round trip agree with the model's training.

## Empirical context (2026-07-15, FoundationModelsMultitool gated suite, M3 Ultra)

Observed with `mlx-community/GLM-4.7-Flash-4bit` driven through `MLXLanguageModel`/`LanguageModelSession`: the model *functions* under the Qwen-framed constraint (the bare-JSON alternative gives it an escape hatch — 21 parseable tool calls in one scenario, 2/4 scenario pass rate), so this is a correctness-of-design issue rather than a hard breakage. But the mismatch plausibly costs reliability: the model is decoding against a foreign wrapper grammar its priors don't expect, and every non-Qwen model pays that tax. Qwen-family models (the currently-best-performing pins) are unaffected, which may itself be partially an artifact of this bias.

## Acceptance Criteria

- [ ] `encodeToolCallingGrammar` (or its caller in `MLXLanguageModel`'s tool-calling phase) selects the structural tag from the model's inferred `ToolCallFormat` instead of unconditionally using Qwen's `<tool_call>` wrapper.
- [ ] Qwen-family behavior is unchanged (regression-guard the existing structural tag for `ToolCallFormat` = default/Qwen).
- [ ] At least GLM4's format is wired (its parser already exists); other formats can follow the same seam incrementally.
- [ ] Existing tool-calling tests stay green.
