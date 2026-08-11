---
assignees:
- claude-code
position_column: todo
position_ordinal: '8180'
title: 'runCode must state its dialect: JavaScriptCore, no modules, and tools.* is the only way out'
---
## Why

Gated trace, `--filter singleCallWeather`, Router `c7b9477`. The model's opening move:

```
CALL [1] runCode args={"code": "import requests\nimport json\n\n# Get current weather for Austin, TX\napi_key = \"YOUR_API_KEY\"  # Placeholder - need to check if there's a built-in weather tool\n..."}
DONE     runCode out=The snippet failed: Unexpected identifier 'requests'. import call expects one or two arguments. (line 8) ⏎ Fix the snippet and call runCode again.
```

Two separate faults, both ours.

**The description never says what is absent.** It says `runCode` is "an isolated JavaScript runtime". It does not say there are no modules, no `import`, no `require`, no network, and no filesystem — nor that `tools.*` is the only way to reach anything outside the snippet. The model wrote Python with an HTTP client because nothing ruled it out. The sandbox is JavaScriptCore: core JavaScript only, not node, deno, or bun, and no module loader of any kind.

**The error teaches the wrong lesson.** We pass JSC's parser text through verbatim, and it reads "import call expects one or two arguments" — which says `import` **exists** and the arity was wrong. The corrective a model draws from that is `import("requests")`, not "there are no modules here". An error whose repair instruction points away from the fix is worse than a bare failure.

## What to change

`Sources/FoundationModelsMultitool/MultiTool.swift:325` — the shipped `description`. Add a directive statement of the dialect and its boundary. Imperative, no rationale, per the standing rule that a tool description is an order. Keep it tight — the description shares the prompt with `searchTools`' own — but no test enforces a word or sentence count, so tightness is a judgement here, not a threshold to satisfy.

**The error-message half is out of scope — human ruling.** This card first proposed detecting a module attempt from the snippet source and rewriting JSC's misleading text. Rejected in favour of the cheaper fix that addresses the cause:

> gosh on ^vkyfwqm i was thinking you can just give a better tool description and tell the model it is using javascript core, do not import modules use core js, all your tools are at tools.

The description is where a model learns the dialect, and it learns it *before* writing the snippet rather than after failing. Source-sniffing to rewrite a parser message is a lot of machinery to restate what one sentence can say up front. JSC's "import call expects one or two arguments" still reaches a model that ignores the description; that is accepted, not fixed here.

The engine is named rather than merely described. A model already knows what JavaScriptCore implies — no module loader, none of node's, deno's or bun's APIs — so the name carries the restriction more compactly than a list of absences.

## Acceptance Criteria

- [x] The shipped `runCode` description states the dialect and the boundary: core JavaScript, no modules, no `import`/`require`, no network, no filesystem, `tools.*` is the only way out
- [x] The engine is named: "The runtime is JavaScriptCore, core JavaScript only", followed by `import` and `require` do not exist, no modules, no node/deno/bun APIs, and every callable function is under `tools.*`
- [x] The description contract test (`MultiToolExecutionTests.descriptionCarriesTheErrorRecoveryContract`) pins every new clause and passes. Correction to this card as first written: there is **no** word/sentence budget test on the description — that count was editorial discipline, not an enforced rule
- [x] Ungated suite green with the new clauses: 320 tests / 26 suites, plus 49 / 8
- [ ] `MULTITOOL_INTEGRATION=1 swift test --filter singleCallWeather` is re-run and the opening `CALL [1]` recorded, whatever it is. The claim is that the model stops reaching for modules; no unit test can show that. **Not blocked on Router**: this is measurable from the first call the model makes, which happens before any tool parks #eventplan