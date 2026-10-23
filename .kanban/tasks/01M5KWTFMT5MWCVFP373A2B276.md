---
assignees:
- claude-code
position_column: done
position_ordinal: ffffffbe80
title: 'Snapshots graph: fan changes out to change.owners and expose owner'
---
Request from FoundationModelsACPAgent (2026-10-23). FoundationModelsHooks 4f463f2: `Checkpoint.owner`, `SnapshotChange.owners` / `.owner`, `SnapshotStore.shared(directory:)`. Sessions of one cwd now share one snapshot key, so the `sessionId: (key) -> String?` resolver of SnapshotsCapability/SnapshotsGraph can no longer map a key to one session.

- [ ] change feed records one change per owner in `change.owners` (that the host knows, via `sessionKey`), so each session of a key sees each change of the key, whoever made it
- [ ] drop the `sessionId` resolver from `SnapshotsGraph.init` and `SnapshotsCapability.init(store:sessionKey:)` (no backward compatibility)
- [ ] `owner: ID!` on `Checkpoint` and on `SnapshotChange` in the snapshots graph; golden updated

Tests first: two sessions on one key both receive a take by either; owner on change and checkpoint names the session that made it.