---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m46h572c2gqfg7b28bq2fh0y
  text: |-
    ### Research — decisions

    Measured on 2026-10-05 with a probe test (deleted after the measurement). Surface: withFiles + withShell + a `code_context` group (getSymbol, searchSymbol, listSymbols, grepCode, getCallgraph). The hint searcher had no embedder (BM25 only, the unit-test mode).

    **Root cause.** Tier 1 compares the WHOLE dotted path. When the group is real, the shared group prefix (`files.`, `shell.`, `code_context.`) gives every verb of that group trigrams in common with the guess. Thus each verb of the group clears `similarityThreshold`, tier 1 always answers with "some verbs of the same group", and tier 2 never runs. Measured today:
    - `code_context.listFiles` -> resemblance [listSymbols, grepCode, getSymbol] (wrong group)
    - `files.find` -> resemblance [read, edit, glob] (glob only third)
    - `shell.run` -> resemblance [execute, getLines, grepHistory] (correct, but only because `execute` shares one more trigram)
    The prefix is necessary for a spelling mistake: `files.raed` -> `files.read` scores 0.56 on the whole path and 0 on the verb alone. Thus tier 1 must stay as it is.

    **Research 1 (cross-group tier 2 with the verb words): NOT supported.** BM25 answers: "list files" -> [code_context.listSymbols, files.grep, files.glob]; "find" -> [files.edit, files.patch] (find-and-replace words); "run" -> [shell.execute]. The first cross-group result for listFiles is files.grep, not files.glob, and "find" goes to edit. Two of the three calls get a wrong answer. Not implemented.

    **Research 2 (small alias table): supported, hint-only.** An alias that dispatches to the real tool hides the mistake from the model and from the `imaginedTool` log. Decision: the alias only names the real path in the hint; it never calls it. Scope rules:
    - The table holds the verbs of the package-owned capabilities only: `files.glob` (find, listFiles, ...) and `shell.execute` (run, exec, ...).
    - An alias applies only when the guess is `<real group>.<unknown verb>`. That is the case where tier 1 is blind (above). A guess under a group that does not exist (`bash.run`, `terminal.runCommand`, `process.spawn`) keeps the current tiers, so HintRankingTests and the live suite do not change.
    - An alias applies only when its target path is in the surface.
    - It is a new tier word, `alias`, in the `imaginedTool` record, so a host can tell a table answer from a ranked answer.

    **Research 3 (Node globals).** JSContext measured: Buffer, require, process, fs, module, exports, __dirname, TextEncoder, TextDecoder, atob, btoa, setTimeout, setInterval, queueMicrotask, structuredClone, URL, fetch, crypto are all `undefined`. TextEncoder is NOT available, so the hint must not tell the model to use it. JSC says `ReferenceError: Can't find variable: Buffer`, which gives no repair. Decision: add a hint-only text for a `Can't find variable: <name>` message where `<name>` is a known Node or browser global. Do not install stub objects (a stub changes `typeof Buffer` checks). Do not log it as `imaginedTool` (it is not a tool name).
  timestamp: 2026-10-05T17:18:05.900165+00:00
- actor: claude-code
  id: 01m46hskn951pqb4x3rxc6kyte
  text: |-
    ### Implementation landed

    - `UnknownToolHint`: new tier `verbAlias` (log word `alias`) and a hint-only alias table `verbAliases` (`files.glob`: find, findfiles, listfiles, ls; `shell.execute`: run, exec, runcommand). It runs after the group-call check and before the ranked tiers, only when the group of the guess is a real group, the verb (in lowercase) is in a row, and the row path is an entry of the surface. The hint names one path and its block. It never calls the tool. The research decisions are also in the type doc comment.
    - `UnavailableGlobalHint` (new, Discovery/): a hint for `ReferenceError: Can't find variable: <name>` when `<name>` is a Node.js or browser global (Buffer, TextEncoder, TextDecoder, atob, btoa, require, module, exports, fs, __dirname, __filename, process, setTimeout, setInterval, fetch). No stub objects, no `imaginedTool` record. `MultiTool.call` uses it only when `UnknownToolHint` gives no hint.
    - Live suite `UnknownToolHintLiveTests`: added `files.find` and `shell.run` (tier `alias`). It prints the result lines; the assertions are code properties only.

    Measured result of the live run (2026-10-05): `files.find -> alias [files.glob]`, `shell.run -> alias [shell.execute]`; the six old lines are the same as before.

    Note for the next agent: `files.raed` must stay in tier 1. The group prefix is what lets it score 0.56 against `files.read`. Thus do not strip the group from tier 1 to correct the prefix problem.
  timestamp: 2026-10-05T17:29:14.153493+00:00
- actor: claude-code
  id: 01m46hstw0rxm8ccce3y3jr6k7
  text: |-
    ### implement — changed
    - evidence: 8 files — Sources/FoundationModelsMultitool/Discovery/UnknownToolHint.swift, Sources/FoundationModelsMultitool/Discovery/UnavailableGlobalHint.swift (new), Sources/FoundationModelsMultitool/MultiTool.swift, Sources/FoundationModelsMultitool/Diagnostics/MultitoolTelemetry.swift, Tests/FoundationModelsMultitoolTests/VerbAliasHintTests.swift (new, 7 tests), Tests/FoundationModelsMultitoolTests/UnavailableGlobalHintTests.swift (new, 4 tests), IntegrationTests/.../UnknownToolHintLiveTests.swift. Commands: `swift build` (0 source warnings); `swift test` (1843 tests in 154 suites passed); `cd IntegrationTests && swift build --build-tests` (clean); `swift test --package-path IntegrationTests --no-parallel --filter UnknownToolHintLiveTests` (1 test passed).
    - next: /review
  timestamp: 2026-10-05T17:29:21.536005+00:00
- actor: claude-code
  id: 01m46j5142ppnzafarzxyevrsn
  text: |-
    ### test — green
    - evidence: `swift test` — 1843 tests in 154 suites passed, 0 failed, 0 skipped. `cd IntegrationTests && swift build --build-tests` — Build complete. Only warning: `missing creator for mutated node` for mlx-swift_Cmlx.bundle (known, from the mlx-swift dependency).
    - next: review
  timestamp: 2026-10-05T17:35:28.386671+00:00
- actor: claude-code
  id: 01m46j5t6weapwa3m0z8mkcfwh
  text: |-
    ### commit — changed
    - evidence: local commit "fix: give better repair hints for made-up verbs and missing globals". It includes all source, test, and .kanban changes (also the ledger of ^artzpvb). Not pushed. The sha is in `git log -1`; a comment cannot hold its own commit sha.
    - next: review
  timestamp: 2026-10-05T17:35:54.076401+00:00
position_column: doing
position_ordinal: '80'
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