// `SnapshotsCapability` — the `snapshots` noun, and the verbs that render
// under it.
//
// The model lists and acts on the workspace snapshots of its session: `list`
// (`ListSnapshots.swift`), `take` (`TakeSnapshot.swift`) and `rollback`
// (`RollbackSnapshot.swift`). The type holds no logic of its own, in the
// pattern of `GitCapability`. It names the noun one time, it makes the one
// `SnapshotsContext` over the store, and it composes the verbs over that
// context.
//
// **The capability does not know about hooks.** The host makes one
// `SnapshotStore` and gives it to this capability and to `SnapshotHook` of
// FoundationModelsHooks. The hook takes a snapshot on each tool event; the
// capability lets the model read and act on the same snapshots.

import Foundation
import FoundationModels
import FoundationModelsExtras
import FoundationModelsHooks

/// The snapshots capability: one noun, and the verbs that list, take and
/// roll back the workspace snapshots of the session.
///
/// ```swift
/// let store = SnapshotStore(directory: snapshotsURL)
/// let surface = try MultiTool.Builder()
///     .withCapability(SnapshotsCapability(store: store))   // tools.snapshots.*
///     .build()
/// ```
///
/// The model calls `list` first to find the index of a checkpoint, and then
/// `rollback` with that index. A rollback is a revert to a point in time, as
/// in git: it becomes a new checkpoint at the end of the list, and the later
/// checkpoints stay. Thus a rollback can roll forward, and a rollback can
/// itself be rolled back.
///
/// **The session key is read at call time.** The capability gets no session
/// key when it is built: the registry is built before the session exists, and
/// `MultiTool.forked()` gives the same tool to a fork. Each verb reads
/// `HookSession.current` when it runs: the `sessionKey` names the timeline,
/// and the `sessionID` is the owner that the store checks. Router binds
/// `HookSession.current` for each model call. Thus a fork in a different
/// working directory acts on its own key, and a session that did not open the
/// key gets none of the checkpoints of another owner. A call with no bound
/// session gives the correction of `SnapshotError.unavailable`. After a failed
/// open of the session or a timeline conflict of the key, each verb gives the
/// correction of `SnapshotError.notAvailable(cause:)`.
///
/// **A rollback inside a `runCode` snippet** makes no second checkpoint. The
/// store sets its `last` tree to the restored tree, thus the `PostToolUse`
/// snapshot of that `runCode` call finds no change from the rollback. A change
/// in the snippet before the rollback goes into a `SnapshotTrigger.pending`
/// checkpoint. A change in the snippet after the rollback goes into the
/// `PostToolUse` checkpoint.
public struct SnapshotsCapability: Capability {

    /// The one namespace each verb of this capability renders under — the
    /// first segment of `tools.snapshots.<verb>`.
    ///
    /// The capability OWNS this noun: `MultiTool.Builder.withCapability(_:)`
    /// claims the whole `tools.snapshots` namespace, so a second registration
    /// under it fails loudly at `buildRegistry()` rather than quietly at
    /// dispatch.
    public let noun = "snapshots"

    /// The verbs of the capability, in the order they render.
    ///
    /// Each one supplies its own second segment through `Tool.name`, so this
    /// array and the noun above are the whole of what the surface needs.
    public let tools: [any Tool]

    /// The `snapshots` GraphQL endpoint over the same store, built once for
    /// this capability.
    private let graph: SnapshotsGraph

    /// The GraphQL endpoints of the capability: its one `snapshots` endpoint.
    ///
    /// The verbs are plain tools, not `GraphQLEndpointTool`s, so the
    /// `Capability` default would give none.
    public var graphQLEndpoints: [any GraphQLEndpoint] {
        [graph]
    }

    /// Makes the snapshots capability over the store that the host gives to
    /// it, for a host whose session keys are the session IDs: the GraphQL
    /// endpoint treats a session ID as its session key.
    ///
    /// - Parameter store: The store that the host also gives to
    ///   `SnapshotHook`, which takes the snapshots on the tool events.
    public init(store: SnapshotStore) {
        self.init(store: store, sessionKey: { sessionId in sessionId })
    }

    /// Makes the snapshots capability over the store that the host gives to
    /// it, for a host whose session keys are not the session IDs — lineage
    /// keys, or one key that the sessions of a working directory share.
    ///
    /// The initializer builds one `SnapshotsContext` and hands it to each
    /// verb, and builds the ``SnapshotsGraph`` over the store.
    ///
    /// A GraphQL call names a session by its session ID, and the store takes
    /// the session key. `sessionKey` maps the one to the other. A change of
    /// the store names the sessions of its key itself (`SnapshotChange.owners`),
    /// so the endpoint needs no map back from a key to a session.
    ///
    /// - Parameters:
    ///   - store: The store that the host also gives to `SnapshotHook`, which
    ///     takes the snapshots on the tool events.
    ///   - sessionKey: Gives the session key of a session ID, or `nil` for a
    ///     session that the host does not know.
    public init(store: SnapshotStore, sessionKey: @escaping @Sendable (String) async -> String?) {
        let context = SnapshotsContext(store: store)
        tools = [ListSnapshots(context: context), TakeSnapshot(context: context), RollbackSnapshot(context: context)]
        graph = SnapshotsGraph(store: store, sessionKey: sessionKey)
    }
}
