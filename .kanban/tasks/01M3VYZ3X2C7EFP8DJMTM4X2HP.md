---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: Integration tests fail on time limits and a wrong model answer under machine load
---
## What
One run of `swift test --package-path IntegrationTests --no-parallel` on 2026-10-01 (work of ^kghyac5) had 5 failures that are not on a web search path. The load average was about 100 from other sessions. The output is in the scratchpad file `integ2.log` of that session.

- `FilesBareSessionTests`: the model answered "no lines in the file". This is a wrong answer, not a time limit and not a network failure.
- `NestedGenerationProbeTests`: 60 s time limit.
- `NoDescriptionSurfaceDiscoveryTests`: 600 s time limit.
- `OverBudgetSurfaceDiscoveryTests`: 360 s time limit.
- `SearchThenCallTests`: 720 s time limit.

In the run before it, `CLISmokeTests` (600 s) and `AgentSurfaceDiscoveryTests` (300 s) failed on time limits, and they passed in this run. Each model step took 15 s to 3 min under load.

## Decide
- Do these tests fail on a quiet machine? Run the suite one time when the load average is low, and record the result.
- If they pass on a quiet machine: how the real-model tests stay stable under load, without a wider time limit and without a skip, or the card records the decision of a person.
- `FilesBareSessionTests`: is the wrong answer a prompt or tool problem, or a model limit?

Do not skip tests and do not widen time limits without a decision on this card.

## Acceptance Criteria
- [ ] The cause of each of the 5 failures is recorded on this card.
- [ ] Each failure is fixed, or the card records the decision of a person for it.

## Tests
- [ ] `swift test --package-path IntegrationTests --no-parallel` passes.