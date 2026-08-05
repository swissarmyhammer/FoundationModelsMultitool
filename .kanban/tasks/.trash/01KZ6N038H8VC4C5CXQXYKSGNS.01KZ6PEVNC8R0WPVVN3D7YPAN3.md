---
assignees:
- claude-code
depends_on: []
position_column: todo
position_ordinal: '8480'
title: '[Router] Elicitation envelope, third event kind, outbox coalescing'
---
Repo: ../FoundationModelsRouter. Basis: eventplan.md §"The elicitation envelope, fixed to the MCP spec".

## What
- New `Sources/FoundationModelsRouter/Hosting/Elicitation.swift`: `ElicitationRequest` — `mode` (`form` | `url`; omitted decodes as form), `message`, `elicitationId` (ULID); form mode carries `requestedSchema` restricted to the MCP subset (flat objects, primitive properties only: bounded strings with `email`/`uri`/`date`/`date-time` formats, numbers, booleans, single/multi-select enums, defaults — reject nested objects at construction); URL mode carries `url`. `ElicitationResponse` — three-action model `accept | decline | cancel`, `content` present only on a form-mode accept. Note: FoundationModelsMCP has no `ElicitationRequest` type today (its coordinator passes raw message+schema), so this is the first typed envelope; keep it Codable and spec-shaped so phase 4's MCP passthrough loses nothing.
- `Hosting/OperationEvent.swift`: add the third `OperationEventKind` case (`elicitation`), and carry the typed request on `OperationEvent` as an optional field mirroring how `outcome` was added (`decodeIfPresent` so previously recorded events decode unchanged). Update the terminal-event scope contract doc to span three kinds: elicitation events are never terminal; a run that posts events still posts exactly one `.completed`.
- `Session/SessionOutbox.swift` coalescing policy: elicitation events behave like `.completed` — always appended, never coalesced. Only `.progress` coalesces (existing in-place replacement by `(tool, correlationID)` stays).
- `Session/OperationEventSegment.swift` / `renderedLine(for:)`: render the elicitation kind sensibly in the turn-preamble line.

## Acceptance Criteria
- [ ] `ElicitationRequest` rejects a nested-object schema at construction; accepts every primitive shape in the restricted subset
- [ ] Decoding a recorded `OperationEvent` JSON with no elicitation key succeeds (back-compat); round trip preserves a present request
- [ ] `SessionOutbox` never coalesces elicitation events: two elicitations for the same `(tool, correlationID)` both survive a drain; interleaved `.progress` still coalesces
- [ ] Terminal contract doc names three kinds; `cd ../FoundationModelsRouter && swift test` green

## Tests
- [ ] New `Tests/FoundationModelsRouterTests/ElicitationEnvelopeTests.swift`: schema-subset acceptance/rejection matrix; three-action response codable round trips; form-content-only-on-accept invariant; omitted-mode-decodes-as-form
- [ ] Extend `SessionOutboxTests.swift`: elicitation-never-coalesces cases
- [ ] `cd ../FoundationModelsRouter && swift test` green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #phase-1 #router-first