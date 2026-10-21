// The change feed of the `snapshots` GraphQL endpoint (MT-13, EXTRAS-9 rule
// 9): the `changes(after:sessionId:)` subscription, the root `cursor` query,
// and the one change log of each store, which the change stream of the store
// (HOOKS-1) feeds.
//
// Each change of the store is one new checkpoint of one session key: a take,
// a pending or rollback checkpoint of a rollback, or a change made while the
// key was closed. The feed records it as one change that adds the checkpoint,
// with the session ID that the host gives for the key. The filters of a
// subscription read only that session ID, so a subscription filters each
// change for its viewer at once, and a change that the viewer cannot see is
// never sent.

import Foundation
import FoundationModelsExtras
import FoundationModelsHooks
import Graphiti
import GraphQL
import Synchronization

// MARK: - The change log

/// One change of the change log of the `snapshots` endpoint: one new
/// checkpoint of one session.
struct SnapshotsGraphChangeEvent: Sendable {
    /// The session whose timeline holds the new checkpoint.
    let sessionId: String

    /// The index of the new checkpoint.
    let index: Int
}

/// The change log of one ``SnapshotStore``, and the task that feeds it with
/// the change stream of the store.
///
/// The stream of the store carries only the checkpoints that the store adds
/// after the feed subscribes, and the subscription is a call on the actor of
/// the store, so it ends after the feed is made. ``readyLog`` waits for the
/// subscription, so each checkpoint after a cursor that ``readyLog`` gives is
/// in the log. The log has a random epoch, so a cursor of another feed, for
/// example of an earlier run, gives `RESYNC_REQUIRED`.
///
/// One store has one feed (EXTRAS-9 rule 1): ``feed(of:sessionId:capacity:)``
/// gives the same instance for each endpoint over the same store. Each
/// endpoint and the context of each call hold the feed, so a running
/// subscription keeps its feed. The task holds the log
/// and the stream and never the feed, so the last release of the feed cancels
/// the task, and the cancel ends the stream of the store.
final class SnapshotsGraphChangeFeed: Sendable {
    /// The change log: the cursor and the changes of the store.
    private let log: ChangeLog<SnapshotsGraphChangeEvent>

    /// The subscription to the change stream of the store, which ends when
    /// the store has the subscriber.
    private let subscription: Task<AsyncStream<SnapshotChange>, Never>

    /// The task that reads the change stream of the store into ``log``.
    private let task: Task<Void, Never>

    /// Makes the feed of a store, subscribes to the change stream of the
    /// store, and starts to read it. A caller outside this type gets the feed
    /// with ``feed(of:sessionId:capacity:)``, which makes one for each store.
    ///
    /// - Parameters:
    ///   - store: The store.
    ///   - sessionId: Gives the session ID of a session key, or `nil` for a
    ///     key that the host does not know.
    ///   - capacity: The number of the newest changes that the log holds, so
    ///     that a subscription resumes after a cursor at most this many
    ///     changes old.
    private init(store: SnapshotStore, sessionId: @escaping @Sendable (String) async -> String?, capacity: Int) {
        let log = ChangeLog<SnapshotsGraphChangeEvent>(capacity: capacity)
        let subscription = Task { await store.changes() }
        self.log = log
        self.subscription = subscription
        task = Task { await Self.record(await subscription.value, into: log, naming: sessionId) }
    }

    /// Cancels the task, which then stops reading the change stream.
    deinit {
        task.cancel()
    }

    /// The change log, once the feed reads the change stream of the store.
    var readyLog: ChangeLog<SnapshotsGraphChangeEvent> {
        get async {
            _ = await subscription.value
            return log
        }
    }

    /// Records each new checkpoint of a session key that the host knows as
    /// one change, until the stream ends or the task is cancelled.
    ///
    /// A checkpoint of a session key that the host does not know gives no
    /// change, as `checkpoints` gives no checkpoint of that key.
    ///
    /// - Parameters:
    ///   - changes: The change stream of the store.
    ///   - log: The change log.
    ///   - sessionId: Gives the session ID of a session key, or `nil`.
    private static func record(
        _ changes: AsyncStream<SnapshotChange>,
        into log: ChangeLog<SnapshotsGraphChangeEvent>,
        naming sessionId: @Sendable (String) async -> String?
    ) async {
        for await change in changes {
            guard let id = await sessionId(change.sessionKey) else {
                continue
            }
            await log.append(SnapshotsGraphChangeEvent(sessionId: id, index: change.checkpoint.index))
        }
    }

    // MARK: The one feed of each store

    /// Gives the one feed of `store` (EXTRAS-9 rule 1).
    ///
    /// The first call for a store makes the feed with `sessionId` and
    /// `capacity`, and each later call gives the same instance while a caller
    /// holds it; the later call's `sessionId` and `capacity` are not read. A
    /// host gives each endpoint over one store the same resolvers. This call
    /// does no I/O.
    ///
    /// - Parameters:
    ///   - store: The store.
    ///   - sessionId: Gives the session ID of a session key, or `nil` for a
    ///     key that the host does not know.
    ///   - capacity: The number of the newest changes that the log holds.
    /// - Returns: The feed.
    static func feed(
        of store: SnapshotStore, sessionId: @escaping @Sendable (String) async -> String?, capacity: Int
    ) -> SnapshotsGraphChangeFeed {
        let key = ObjectIdentifier(store)
        return feeds.withLock { feeds in
            feeds = feeds.filter { $0.value.isLive }
            if let entry = feeds[key], entry.store === store, let feed = entry.feed {
                return feed
            }
            let feed = SnapshotsGraphChangeFeed(store: store, sessionId: sessionId, capacity: capacity)
            feeds[key] = WeakFeed(feed: feed, store: store)
            return feed
        }
    }

    /// One feed and its store, which ``feeds`` holds weakly: the table never
    /// keeps a feed or a store alive. The weak store tells a store that is
    /// gone from a later store that took its object identifier.
    private struct WeakFeed {
        /// The feed, or `nil` after the last caller released it.
        weak var feed: SnapshotsGraphChangeFeed?

        /// The store of ``feed``, or `nil` after the store went away.
        weak var store: SnapshotStore?

        /// Tells if the feed and its store both still exist.
        var isLive: Bool {
            feed != nil && store != nil
        }
    }

    /// The feed of each store that a caller holds now, by the object
    /// identifier of the store.
    private static let feeds = Mutex<[ObjectIdentifier: WeakFeed]>([:])
}

// MARK: - The change type and the arguments

/// The `SnapshotChange` type: one change of the checkpoints, in the shape of
/// EXTRAS-9 rule 9.
///
/// One change adds one checkpoint, whose id is the `id` of the `Checkpoint`
/// that `checkpoint(sessionId:index:)` gives. The client queries
/// `checkpoint` for the rest of the checkpoint.
struct SnapshotsGraphChange: Sendable {
    /// The cursor that resumes the subscription after this change.
    let cursor: String

    /// The time of the change.
    let at: DateTime

    /// The session whose timeline changed.
    let sessionId: ToolkitID

    /// The checkpoint that the change added.
    let added: [ToolkitID]

    /// The checkpoints that the change changed: none, because a checkpoint
    /// never changes.
    var changed: [ToolkitID] {
        []
    }

    /// The checkpoints that the change removed: none, because the timeline is
    /// append only; a rollback is a new checkpoint.
    var removed: [ToolkitID] {
        []
    }

    /// Makes the change of one entry of the change log.
    ///
    /// - Parameter entry: The entry, which gives the cursor, the time and the
    ///   checkpoint.
    init(_ entry: ChangeLogEntry<SnapshotsGraphChangeEvent>) {
        cursor = entry.cursor
        at = DateTime(entry.at)
        sessionId = ToolkitID(entry.event.sessionId)
        added = [SnapshotsGraphCheckpoint.id(sessionId: entry.event.sessionId, index: entry.event.index)]
    }
}

/// The arguments of `Subscription.changes`.
struct SnapshotsGraphChangesArguments: Codable, Sendable {
    /// The cursor to resume after, or `nil` for the changes from now on.
    let after: String?

    /// The session whose changes to give, or `nil` for each session.
    let sessionId: ToolkitID?
}

// MARK: - The resolvers

extension SnapshotsGraphResolver {
    /// Resolves `Query.cursor`: the cursor of the newest change.
    ///
    /// - Parameters:
    ///   - context: The context of the call, which holds the change feed.
    ///   - arguments: No argument.
    /// - Returns: The cursor.
    func cursor(context: SnapshotsGraphContext, arguments _: NoArguments) async -> String {
        await context.changes.readyLog.cursor
    }

    /// Resolves the source stream of `Subscription.changes`: the changes
    /// after the cursor, of the named session or of each session, that the
    /// viewer of the call can see.
    ///
    /// - Parameters:
    ///   - context: The context of the call, which holds the change feed and
    ///     the viewer.
    ///   - arguments: The cursor to resume after, and the session.
    /// - Returns: The stream of the entries. It ends with `RESYNC_REQUIRED`
    ///   when the log cannot give each change after the cursor.
    func changes(
        context: SnapshotsGraphContext, arguments: SnapshotsGraphChangesArguments
    ) async -> ChangeLog<SnapshotsGraphChangeEvent>.Changes {
        let named = arguments.sessionId?.text
        return await context.changes.readyLog.changes(after: arguments.after) { change in
            context.canSee(change.sessionId) && (named ?? change.sessionId) == change.sessionId
        }
    }
}

// MARK: - The schema

extension SnapshotsGraphAPI {
    /// One type of the schema: an object type or an input object.
    typealias SchemaType = TypeComponent<SnapshotsGraphResolver, SnapshotsGraphContext>

    /// One root field of the schema: a query, a mutation or a subscription.
    typealias SchemaField = FieldComponent<SnapshotsGraphResolver, SnapshotsGraphContext>

    /// The `SnapshotChange` type.
    ///
    /// - Returns: The type.
    static func changeType() -> SchemaType {
        Type(SnapshotsGraphChange.self, as: "SnapshotChange") {
            Field("cursor", at: \.cursor).description("The cursor that resumes the subscription after this change.")
            Field("at", at: \.at).description("The time of the change.")
            Field("sessionId", at: \.sessionId).description("The session whose checkpoints changed.")
            Field("added", at: \.added)
                .description("The new checkpoint: query checkpoint(sessionId:index:) for its files and trigger.")
            Field("changed", at: \.changed)
                .description("The checkpoints that changed: none, a checkpoint never changes.")
            Field("removed", at: \.removed)
                .description("The checkpoints that left the timeline: none, a rollback is a new checkpoint.")
        }
        .description("One new checkpoint of one session that you can see.")
    }

    /// The `Query.cursor` field.
    ///
    /// - Returns: The field.
    static func cursorField() -> SchemaField {
        Field("cursor", at: SnapshotsGraphResolver.cursor)
            .description(
                "The cursor of the newest change. Read the checkpoints, then subscribe to changes after this cursor.")
    }

    /// The `Subscription.changes` field.
    ///
    /// - Returns: The field.
    static func changesField() -> SchemaField {
        SubscriptionField(
            "changes",
            at: { (entry: ChangeLogEntry<SnapshotsGraphChangeEvent>) in
                { (_: SnapshotsGraphContext, _: SnapshotsGraphChangesArguments) async throws -> SnapshotsGraphChange in
                    SnapshotsGraphChange(entry)
                }
            },
            atSub: SnapshotsGraphResolver.changes
        ) {
            Argument("after", at: \.after)
                .description(
                    "The cursor to resume after, from the cursor query or a change. None: the changes from now.")
            Argument("sessionId", at: \.sessionId)
                .description("The session whose changes to give. None: each session that you can see.")
        }
        .description(
            "The new checkpoints of the sessions that you can see, after a cursor. RESYNC_REQUIRED ends it when a "
                + "change after the cursor is lost: read the checkpoints and the cursor again, then subscribe with "
                + "that cursor.")
    }
}
