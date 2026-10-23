---
assignees:
- claude-code
position_column: done
position_ordinal: ffffffc080
title: Model-facing snapshots verbs show the owner of each checkpoint
---
Request from FoundationModelsACPAgent (2026-10-23, user approved). Hooks 4f463f2 gives `Checkpoint.owner`; the snapshots graph shows it, the model-facing verbs do not.

- [ ] `owner` on each checkpoint that `tools.snapshots.list` gives, and on the checkpoint `take` / `rollback` give back

Tests first.