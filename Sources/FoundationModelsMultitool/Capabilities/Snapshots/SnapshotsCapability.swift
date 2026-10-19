// `SnapshotsCapability` — the `snapshots` noun, and the verbs that render
// under it.
//
// The model lists and acts on the workspace snapshots of its session: `list`
// (`ListSnapshots.swift`), `take` (`TakeSnapshot.swift`), `undo`
// (`UndoSnapshot.swift`) and `redo` (`RedoSnapshot.swift`). The type holds no
// logic of its own, in the pattern of `GitCapability`. It names the noun one
// time, it makes the one `SnapshotsContext` over the store, and it composes
// the verbs over that context.
//
// **The capability does not know about hooks.** The host makes one
// `SnapshotStore` and gives it to this capability and to `SnapshotHook` of
// FoundationModelsHooks. The hook takes a snapshot on each tool event; the
// capability lets the model read and act on the same snapshots.

import Foundation
import FoundationModels
import FoundationModelsHooks

/// The snapshots capability: one noun, and the verbs that list, take, undo
/// and redo the workspace snapshots of the session.
///
/// ```swift
/// let store = SnapshotStore(directory: snapshotsURL)
/// let surface = try MultiTool.Builder()
///     .withCapability(SnapshotsCapability(store: store))   // tools.snapshots.*
///     .build()
/// ```
///
/// **The session key is read at call time.** The capability gets no session
/// key when it is built: the registry is built before the session exists, and
/// `MultiTool.forked()` gives the same tool to a fork. Each verb reads
/// `HookSession.current?.sessionKey` when it runs, and Router binds
/// `HookSession.current` for each model call. Thus a fork in a different
/// working directory acts on its own key. A call with no bound session gives
/// the correction of `SnapshotError.unavailable`.
///
/// **An undo inside a `runCode` snippet** sets the `last` tree of the store to
/// the restored tree. Thus the `PostToolUse` snapshot of that `runCode` call
/// finds no change and makes no checkpoint. An undo can also run before the
/// snapshot of the tool call before it; the store then records that change as
/// `SnapshotTrigger.pending`.
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

    /// Makes the snapshots capability over the store that the host gives to
    /// it.
    ///
    /// The initializer builds one `SnapshotsContext` and hands it to each
    /// verb.
    ///
    /// - Parameter store: The store that the host also gives to
    ///   `SnapshotHook`, which takes the snapshots on the tool events.
    public init(store: SnapshotStore) {
        let context = SnapshotsContext(store: store)
        tools = [
            ListSnapshots(context: context), TakeSnapshot(context: context), UndoSnapshot(context: context),
            RedoSnapshot(context: context),
        ]
    }
}
