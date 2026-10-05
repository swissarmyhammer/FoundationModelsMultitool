---
assignees:
- claude-code
position_column: todo
position_ordinal: '8480'
title: 'runCode: better repair hints for made-up verbs and missing globals (Buffer)'
---
## Priority

Lower than the other tasks of the SWE-bench run. Do research first, then implement only the parts that the research supports.

## Problem

In the SWE-bench run (reported by the FoundationModelsACPAgent session), the model called verbs that do not exist inside `runCode`:

| Call | Count | Recovery |
|---|---|---|
| `tools.code_context.listFiles` | 2 | none |
| `tools.files.find` | 2 | yes |
| `tools.shell.run` | 1 | yes; the hint said `tools.shell.execute` |

For `listFiles`, the hint pointed to a `listSymbol...` verb in the same group. That is not what the model wanted; the model wanted a list of files (`tools.files.glob`). Snippets also used `Buffer`, which is not in the JavaScriptCore runtime.

## Where

- `Sources/FoundationModelsMultitool/Discovery/UnknownToolHint.swift`: `hint(message:snippet:surface:searcher:...)` (line 219). Tier 1 is name resemblance (containment, then trigram Jaccard, `similarityThreshold = 0.2`). Tier 2 is catalog relevance (`MetadataSearcher`), and it runs only when tier 1 finds nothing. For `code_context.listFiles`, tier 1 matches `listSymbol...` on the shared `list` text, thus tier 2 never runs.
- `Sources/FoundationModelsMultitool/MultiTool+SandboxGlobals.swift`: the globals of the sandbox. Line 317-321 shows the pattern for a removed name (`wait`) that keeps a function and gives a clear error (`SandboxGlobalError.waitRemoved`).
- `Sources/FoundationModelsMultitool/MultiTool.swift`: where the `runCode` error and the hint are joined, and the `imaginedTool` log record (`MultitoolTelemetry.LogMessage.imaginedTool`).
- Tests: `UnknownToolHintTests.swift`, `HintRankingTests.swift`, `IntegrationTests/.../UnknownToolHintLiveTests.swift`.

## Research

1. For a verb that does not exist in a real group, find out if the hint must also rank the verb against the other groups. Example: `code_context.listFiles` → `files.glob`. One option: when the group exists and the verb does not, run tier 1 inside the group AND tier 2 over the full catalog with the verb words ("list files"), and show the tier-2 result when it is in a different group. Measure on the three calls above.
2. Find out if a small alias table is better (for example `files.find` → `files.glob`, `shell.run` → `shell.execute`, `*.listFiles` → `files.glob`). Note: an alias that calls the real tool hides the mistake; an alias that only gives the hint is safer. Record the decision.
3. For `Buffer`, and other Node globals that a model uses (`require`, `process`, `fs`), find out if a `ReferenceError` hint helps: for example `Buffer is not available in runCode. Use a string, or TextEncoder if it exists.` First check which globals the runtime has.

## Fix

Implement the parts that the research supports. Keep the current tiers for all guesses that they already resolve correctly (see `HintRankingTests`).

## Tests

- `code_context.listFiles` (with a test catalog that has a `code_context` group with a `listSymbols` verb, and `files.glob`) gives a hint that names `files.glob`.
- `files.find` and `shell.run` still give the correct hint.
- If a `Buffer` hint is added: a snippet that uses `Buffer` gives that hint.
- Do not assert a fixed model score in a live test; print the result.

## Acceptance

- `swift build` and `swift test` pass with no new warnings.
- The research decisions are written in the task comments or in the doc comment of `UnknownToolHint`. #discovery #defect