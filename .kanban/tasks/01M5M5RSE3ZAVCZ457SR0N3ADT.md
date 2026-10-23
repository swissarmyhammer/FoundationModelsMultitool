---
assignees:
- claude-code
position_column: done
position_ordinal: ffffffc280
title: Snapshots map store owners to host sessions and back
---
Request from FoundationModelsACPAgent (2026-10-23, user approved). Checkpoint owners are Router session ids; after a model switch the replacement Router session owns the key, and the host (ACP) session id is no longer an owner.

- [ ] `SnapshotsGraph(store:sessionKey:hostSession:storeOwner:...)` and `SnapshotsCapability(store:sessionKey:hostSession:storeOwner:...)`
- [ ] `hostSession: @Sendable (String) async -> String?` maps a store owner to the host session id (nil keeps the owner). The change feed fans out to the distinct mapped ids; `SnapshotChange.owner` and `Checkpoint.owner` go through it
- [ ] `storeOwner: @Sendable (String) async -> String?` maps a host session id to the live store owner (nil keeps the id), used for take/rollback/list
- [ ] Tests: two Router owners mapped to one host session give one change under the host id with owner = host id; rollback through the host id works when only the replacement owns the key