---
depends_on:
- 01KWQC004XSC6ZS9PW10WF5GAD
position_column: todo
position_ordinal: '8380'
title: Replace local AgentSession seam with the registry's public seam
---
## What
The registry publicly exports `AgentSession`, its `respond(to:generating:)`/`fork()` extension defaults, and `RoutedAgentSession` — lifted verbatim from this package's internal copy (the registry's `Session/AgentSession.swift` header says: "Multitool later re-exports this seam from here instead of defining its own copy"). Delete the local copy and consume the registry's.

- Delete `Sources/FoundationModelsMultitool/Agent/AgentSession.swift`.
- Add `import FoundationModelsMetadataRegistry` where the seam is used: `Sources/FoundationModelsMultitool/Agent/MultiToolAgent.swift`, `Sources/FoundationModelsMultitool/Agent/Librarian.swift` (still present at this point — it migrates in a later task), and the test fakes:
  - `Tests/FoundationModelsMultitoolTests/Fixtures/MultiToolAgentFixtures.swift` (`ScriptedAgentSession: AgentSession`)
  - `Tests/FoundationModelsMultitoolTests/Fixtures/LibrarianFixtures.swift` (`RootSessionRespondCalledDirectlySession`, `RecordingSessionFactory`)
- The registry's protocol and conformer are drop-in identical (same requirements, same extension defaults, `RoutedAgentSession.init(session:)` public), so no behavior changes — only the defining module moves.
- `DirectCallSession` (in `DirectToolCall.swift`) is a deliberately separate seam over `RoutedLLM.respond(to:matching:)` — leave it untouched.

## Acceptance Criteria
- [ ] No `protocol AgentSession` or `struct RoutedAgentSession` definition remains anywhere in this repo (grep proves it).
- [ ] All existing tests pass unchanged in behavior — fakes conform to the registry's public protocol.
- [ ] `swift build` and full `swift test` green.

## Tests
- [ ] Existing suite is the regression net: `swift test` — full suite green (LibrarianTests, MultiToolAgentTests, GuidedTurnFormatTests all drive the seam).
- [ ] `grep -rn "protocol AgentSession\|struct RoutedAgentSession" Sources/ Tests/` returns nothing.

## Workflow
- Use `/tdd` — the existing tests are the failing/passing signal; make the swap keeping them green.