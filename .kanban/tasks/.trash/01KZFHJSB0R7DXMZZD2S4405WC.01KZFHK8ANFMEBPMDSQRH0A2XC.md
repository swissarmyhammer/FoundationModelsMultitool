---
assignees:
- claude-code
position_column: todo
position_ordinal: '8180'
title: '[Router] Pre-discovery seeding: deterministic first tool call via transcript construction'
---
HUMAN-DIRECTED (2026-08-07). Router-native card; edits only FoundationModelsRouter sources. Companion to card 01KZFH9TT6QNRQ8DPBRYWC0Q4F (self-describing pending envelope); together they are the structural fix for MultiTool's gated-suite reliability (MultiTool card 01KZ6N5Z39W4ZBBE74JTKRDWB8).

## Why

MultiTool's three residual gated failure classes — over-refusal ("I don't have access to real-time data"), announce-then-stop, and answering from the model's own knowledge — are all ONE event: a first assistant turn containing zero tool calls. Two facts, both measured on 2026-08-07:
- Upfront prose cannot eliminate this class: three separate "never refuse" statements are already shipped, and description-text iteration across three 5-run arms moved nothing (A/B/C: 12/20, 11/20, 14/20 — null).
- The human ruling is explicit: NO retry gates; the suite must pass every run. So the class must become structurally impossible, not statistically tolerated.

Apple's `LanguageModelSession` exposes no `tool_choice: required`. But Router does not need it: Router already constructs transcripts entry-by-entry — `Recording/TranscriptReconstruction.swift` builds `[Transcript.Entry]` including tool calls/outputs via `TranscriptEntryMapper`, and `RoutedLLM.swift:478` already builds `LanguageModelSession(model:tools:transcript:)` from constructed transcripts. Seeding a REAL discovery call into the turn makes the first tool call deterministic by construction: the model resumes a turn in which discovery has already happened, concrete typed signatures are in front of it, and the refusal-shaped opening move is already spent. Its first decision becomes composing the runCode snippet, not deciding whether it has access.

## What

An opt-in session option (working name `DiscoveryPriming`; naming free) that, given a turn's user prompt P:
1. Executes the designated mounted discovery tool host-side with the prompt as its query — a REAL call producing REAL output. Never fabricate or template the output.
2. Builds the turn's transcript as: …existing entries… → prompt(P) → toolCalls(<tool>, {query: P}) → toolOutput(<real result>) → and only then generates the assistant response.

Design constraints:
- OFF by default; the host enables it per session (or per turn). It becomes the RECOMMENDED mount for data-facing sessions in MultiTool's documented host contract.
- Generic over any mounted tool taking one string-valued argument (MultiTool's `findAPIs` is the motivating consumer); the option names the tool and the argument property.
- The seeded entries must be structurally indistinguishable from SDK-native ones: they round-trip through `TranscriptDiffer`/the recording sidecar with no special-casing (they ARE genuine calls and get recorded as such).
- If the discovery call throws, generate WITHOUT seeding (never block the turn); surface the failure on the session's event stream.

## Acceptance Criteria
- [ ] Ungated unit test: priming on + stub discovery tool → the backend receives entries exactly prompt → toolCalls → toolOutput (stub's real output) before generation
- [ ] Ungated unit test: priming off → construction byte-identical to current behavior
- [ ] Seeded entries round-trip through recording/diffing with no special-case branch
- [ ] Discovery-throw path: turn proceeds unseeded, failure surfaced as an event
- [ ] `swift test` green in FoundationModelsRouter
- [ ] Committed AND PUSHED on `main` — MultiTool consumes Router by branch pin; unpushed = invisible to the gated re-measure

## Tests
- [ ] Unit coverage per criteria above (stub tools, no live inference)
- [ ] The live end-to-end proof is MultiTool's gated suite, on MultiTool's board — not here

## Workflow
- Use `/tdd` — failing transcript-construction tests first.

#phase-1