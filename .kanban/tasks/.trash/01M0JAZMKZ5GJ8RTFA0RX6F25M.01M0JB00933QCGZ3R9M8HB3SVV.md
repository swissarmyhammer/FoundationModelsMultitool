---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: The pending envelope's `next` text prescribes a `runCode` snippet that cannot collect the run
---
Filed from FoundationModelsMultitool card `^4qcf1v9`. This card is native to Router: the text lives in Router, and only Router can change it.

## What happens

`PendingRunEnvelope.renderedMidfix` and `renderedSuffix` in `Sources/FoundationModelsRouter/Hosting/DetachingTool.swift` render this `next` text on every park:

> Call this tool again with a snippet that does: return await wait("<completionToken>", 60). When the returned state is "settled", the result is in its detail field. When it is "deadline_elapsed", the run is still going: call wait again with the same completionToken.

For Multitool's `runCode`, this instruction cannot collect the run:

1. `runCode` always backgrounds. `MultiTool.detachmentClocks(from:)` (Multitool, `Sources/FoundationModelsMultitool/MultiTool+Detachment.swift`) answers a zero wait clock (Multitool task `^cv98vff`). Each `runCode` call returns a fresh pending envelope before its snippet runs.
2. So the prescribed snippet `return await wait("T0", 60)` returns a new envelope for a new token T1. It does not return the result of T0. The `next` text of T1 prescribes the same snippet for T1. The model obeys it. Each round costs one model generation.
3. Measured with no model (Multitool mounted under `.nativeSessionMount`, one scripted background run): on a settled T0 the call returned a fresh envelope in 42 µs; on a running T0 in 112 µs; the second hop minted a third token. Measured with a model (Multitool CI run `32392350928`): 21 rounds and 1777 s for an 8-second fixture. The model escaped only when it called the `wait` tool with the original token.
4. The state names in the text ("settled", "deadline_elapsed") are Router's `WaitOutcome` names. Multitool's sandbox `wait()` and its `wait` tool report `state: complete | error` and `result: timeout | unknown`. The text names values the model does not see.
5. Multitool's `runCode` description already says "do not wait()". The in-band `next` text wins over the tool description. The transcript shows this.

The collect step for a Router-mounted Multitool session is the `wait` **tool** (`Sources/FoundationModelsMultitool/WaitTool.swift`, mounted by `MultiTool.Registry.makeSessionTools`), called with the same completionToken. Multitool tasks `^2w9vbkm` and `^h773bed` record why: a snippet-level wait asks the model for a duration it cannot know. Router card `01M03NR0CQ8MX1SV2NQ466D38P` already recorded that this instruction is Router behaviour on every host.

## What Multitool needs

The `next` text of a pending envelope must lead the model to a collect step that works:

- The text must not prescribe a `runCode` snippet. For a detaching tool other than `runCode`, "call this tool again with a snippet" is also wrong: a shell tool has no snippets.
- The text must name the same completionToken, and a collect step that returns the result in band: the `wait` tool with that completionToken.
- The state names in the text must match what the collect step reports, or the text must not name states.

Two designs. The choice is Router's:

- A. Change the fixed text. Example: "Call the wait tool with completionToken "<T>". When its state is "complete", answer from its detail. When its result is "timeout", call wait again with the same completionToken." Keep `isRendered(text:)` exact.
- B. Let the wrapped tool supply the collect sentence through `DetachmentParameterProviding` (an optional requirement with a default). The tool that owns the collect verb then owns the sentence. `PendingRunEnvelope.isRendered(text:)` then recognizes the prefix, the token, and a `next` field, not one fixed suffix. `TokenCappingTool` is the one `isRendered` caller.

Call sites: `DetachingTool.detach(...)` builds the envelope. `Tests/FoundationModelsRouterTests/DetachingToolTests.swift` asserts the current snippet text `return await wait("<token>", 60)` near its line 460. `Tests/FoundationModelsRouterTests/SessionOutboxToolWiringTests.swift` uses `isRendered`.

Multitool has touched nothing in the Router tree.

## Acceptance Criteria

- [ ] The `next` text does not prescribe a `runCode` snippet, and names the same completionToken for a collect step that returns in band.
- [ ] `isRendered(text:)` recognizes every rendered envelope, and `TokenCappingTool` passes it through.
- [ ] Router tests green.
- [ ] Multitool is told on its card `^4qcf1v9`, so it can bump its Router pin and re-measure the elevation scenario.