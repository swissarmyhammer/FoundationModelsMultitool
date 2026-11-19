// The change feed of the `sessions` GraphQL endpoint (MT-10, EXTRAS-9 rule
// 9): the `changes(after:)` subscription, the root `cursor` query, and the one
// change log of each endpoint, which the events of the directory feed.
//
// Each event of the directory names one session. The feed records it as one
// change of that session, `added` for a start and `changed` for each other
// event, an archive and an unarchive included, together with the chain of
// anchors of the session. The visibility rule reads only that chain, so a
// subscription filters each change for its viewer at once, with no read of
// the directory, and a change that the viewer cannot see is never sent.
//
// A message changes the inbox of its target two times. When the target
// cannot take the message at the send, the message waits in the queue of a
// working target or in the inbox of a recorded target, and the feed records a
// change of the target at the send. Thus `Session.unreadCount` of the target
// is current at once. When the target takes the message, the feed records a
// second change of the target.

import Foundation
import FoundationModelsExtras
import GraphQL
import Graphiti
import Synchronization
import ULID

// MARK: - The change log

/// One change of the change log of the `sessions` endpoint: one session, how
/// it changed, and its chain of anchors.
struct SessionsGraphChangeEvent: Sendable {
    /// How a change touched its session.
    enum Kind: Sendable {
        /// The session is new to the server: it started, a message restored
        /// it, or a user forked it. A new root session is one of these
        /// (session.md section 11.5).
        case added

        /// The facts, the work state or the inbox of the session changed, or
        /// the session was archived or unarchived. An archived session stays
        /// in the directory, so an archive is a change and not a removal, and
        /// an unarchive is a change and not an addition.
        case changed
    }

    /// The session that changed.
    let sessionID: ULID

    /// How the change touched the session.
    let kind: Kind

    /// The session and its anchors, as ``SessionsVisibility/anchorChain(of:)``
    /// gives them, which the visibility rule reads for each viewer.
    let anchorChain: [ULID]
}

extension SessionDirectoryEvent {
    /// The session that the event names, and how the event changed it in the
    /// change feed of the `sessions` endpoint.
    ///
    /// A message changes its target: its inbox. A message that waits in the
    /// queue or in the inbox of its target changes the target at the send,
    /// and the target changes again when it takes the message. An archive
    /// and an unarchive each change their session.
    var sessionChange: (sessionID: ULID, kind: SessionsGraphChangeEvent.Kind) {
        switch self {
        case .started(let summary, _): (summary.id, .added)
        case .factsChanged(let summary): (summary.id, .changed)
        case .stateChanged(let id, _, _): (id, .changed)
        case .messageQueued(let message): (message.to, .changed)
        case .messageDelivered(let message): (message.to, .changed)
        case .archived(let id): (id, .changed)
        case .unarchived(let id): (id, .changed)
        }
    }
}

/// Records one change of one session into the change log of the `sessions`
/// endpoint, with the chain of anchors of the session.
///
/// This is the one code path of each entry of the log: the events of the
/// directory, the share changes from outside that the sharer of the host
/// sends, and each share change that a share operation or a share mutation
/// makes. Thus each entry has the same chain of anchors, and a subscription
/// filters each entry with the same visibility rule.
struct SessionsGraphChangeRecorder: Sendable {
    /// The change log: the cursor and the changes of the endpoint.
    let log: ChangeLog<SessionsGraphChangeEvent>

    /// The directory, read with no viewer, for the chain of anchors of each
    /// changed session.
    let sessions: SessionsVisibility

    /// Records one change of a session as one entry of the log.
    ///
    /// - Parameters:
    ///   - kind: How the change touched the session.
    ///   - sessionID: The session that changed.
    func record(_ kind: SessionsGraphChangeEvent.Kind, of sessionID: ULID) async {
        let chain = await anchorChain(of: sessionID)
        await log.append(SessionsGraphChangeEvent(sessionID: sessionID, kind: kind, anchorChain: chain))
    }

    /// Records each id of a stream as one `changed` entry, until the stream
    /// ends or the task is cancelled.
    ///
    /// - Parameter ids: The ids of the changed sessions.
    func recordChanges(of ids: AsyncStream<ULID>) async {
        for await id in ids {
            await record(.changed, of: id)
        }
    }

    /// The chain of anchors of a changed session.
    ///
    /// A session that the directory does not hold has a chain of the session
    /// alone. A directory that fails to read the chain is not expected: the
    /// chain is then the session alone, which an external client sees only
    /// when it owns the session, and an error record tells of the failure.
    ///
    /// - Parameter id: The session id.
    /// - Returns: The session and its anchors, the session first.
    private func anchorChain(of id: ULID) async -> [ULID] {
        do {
            guard let summary = try await sessions.directory.summary(of: id) else {
                return [id]
            }
            return try await sessions.anchorChain(of: summary)
        } catch  where Task.isCancelled {
            // The feed is gone: the loop that records ends, and no subscriber
            // reads this change.
            return [id]
        } catch {
            assertionFailure("The anchor chain of the changed session \(id) could not be read: \(error)")
            MultitoolTelemetry.logger.log(
                .sessionAnchorChainReadFailed, level: .error, metadata: MultitoolTelemetry.errorMetadata(of: error))
            return [id]
        }
    }
}

/// The change log of one `sessions` endpoint, the task that feeds it with
/// the events of the directory, and the task that feeds it with the share
/// changes from outside.
///
/// The feed reads each event that the directory sends after the feed is
/// made: it asks the directory for its events before it returns. Each event
/// is one change in the log, in the order of the events. The log has a random
/// epoch, so a cursor of another feed, for example of an earlier run, gives
/// `RESYNC_REQUIRED`.
///
/// The endpoint holds its feed, and the context of each call holds it too, so
/// a running subscription keeps its feed. Each task holds the recorder, which
/// holds the log and the directory and never the feed, so the last release of
/// the feed cancels the tasks, and the tasks then stop reading.
final class SessionsGraphChangeFeed: Sendable {
    /// The one recorder of each entry of ``log``.
    let recorder: SessionsGraphChangeRecorder

    /// The task that reads the events of the directory into ``log``.
    private let task: Task<Void, Never>

    /// The task that reads the share changes from outside into ``log``, or
    /// `nil` before ``followShareChanges(of:)`` starts it.
    private let shareChangesTask = Mutex<Task<Void, Never>?>(nil)

    /// Makes the feed of a directory, and starts to read its events.
    ///
    /// - Parameters:
    ///   - directory: The session directory.
    ///   - capacity: The number of the newest changes that the log holds,
    ///     so that a subscription resumes after a cursor at most this many
    ///     changes old.
    init(directory: any SessionDirectory, capacity: Int) {
        let recorder = SessionsGraphChangeRecorder(
            log: ChangeLog<SessionsGraphChangeEvent>(capacity: capacity),
            sessions: SessionsVisibility(directory: directory, viewer: nil))
        let events = directory.events()
        self.recorder = recorder
        task = Task { await Self.record(events, with: recorder) }
    }

    /// Cancels the tasks, which then stop reading.
    deinit {
        task.cancel()
        shareChangesTask.withLock { $0?.cancel() }
    }

    /// The change log: the cursor and the changes of the endpoint.
    var log: ChangeLog<SessionsGraphChangeEvent> {
        recorder.log
    }

    /// Starts to read the share changes from outside of `sharer`, one
    /// `changed` entry for each id. The feed reads the changes of one sharer
    /// only: a later call, with the same sharer or a different one, starts
    /// no second read.
    ///
    /// - Parameter sharer: The sharer of the host.
    func followShareChanges(of sharer: any SessionSharer) {
        shareChangesTask.withLock { task in
            guard task == nil else {
                return
            }
            let changes = sharer.shareChanges()
            task = Task { [recorder] in await recorder.recordChanges(of: changes) }
        }
    }

    /// Records each event as one change, until the events end or the task is
    /// cancelled.
    ///
    /// - Parameters:
    ///   - events: The events of the directory.
    ///   - recorder: The recorder of the log.
    private static func record(
        _ events: AsyncStream<SessionDirectoryEvent>, with recorder: SessionsGraphChangeRecorder
    ) async {
        for await event in events {
            let (sessionID, kind) = event.sessionChange
            await recorder.record(kind, of: sessionID)
        }
    }
}

// MARK: - The change type and the arguments

/// The `SessionChange` type: one change of the sessions, in the shape of
/// EXTRAS-9 rule 9.
///
/// One change names one session, in `added` or in `changed`.
struct SessionsGraphChange: Hashable, Sendable {
    /// The cursor that resumes the subscription after this change.
    let cursor: String

    /// The time of the change.
    let at: DateTime

    /// The session that the change added, or none.
    let added: [ToolkitID]

    /// The session that the change changed, or none.
    let changed: [ToolkitID]

    /// The sessions that the change removed: none, because the directory
    /// removes no session. An archived session stays, and its archive is a
    /// change.
    var removed: [ToolkitID] {
        []
    }

    /// Makes the change of one entry of the change log.
    ///
    /// - Parameter entry: The entry, which gives the cursor, the time and the
    ///   session.
    init(_ entry: ChangeLogEntry<SessionsGraphChangeEvent>) {
        let session = [ToolkitID(entry.event.sessionID.ulidString)]
        cursor = entry.cursor
        at = DateTime(entry.at)
        added = entry.event.kind == .added ? session : []
        changed = entry.event.kind == .changed ? session : []
    }
}

/// The arguments of `Subscription.changes`.
struct SessionsGraphChangesArguments: Codable, Sendable {
    /// The cursor to resume after, or `nil` for the changes from now on.
    let after: String?
}

// MARK: - The resolvers

extension SessionsGraphResolver {
    /// Resolves `Query.cursor`: the cursor of the newest change.
    ///
    /// - Parameters:
    ///   - context: The context of the call, which holds the change feed.
    ///   - arguments: No argument.
    /// - Returns: The cursor.
    func cursor(context: SessionsGraphContext, arguments _: NoArguments) async -> String {
        await context.changes.log.cursor
    }

    /// Resolves the source stream of `Subscription.changes`: the changes
    /// after the cursor that the viewer of the call can see.
    ///
    /// - Parameters:
    ///   - context: The context of the call, which holds the change feed and
    ///     the visibility of the viewer.
    ///   - arguments: The cursor to resume after.
    /// - Returns: The stream of the entries. It ends with `RESYNC_REQUIRED`
    ///   when the log cannot give each change after the cursor.
    func changes(
        context: SessionsGraphContext, arguments: SessionsGraphChangesArguments
    ) async -> ChangeLog<SessionsGraphChangeEvent>.Changes {
        let sessions = context.sessions
        return await context.changes.log.changes(after: arguments.after) { change in
            sessions.sees(anchorChain: change.anchorChain)
        }
    }
}

// MARK: - The schema

extension SessionsGraphAPI {
    /// The `SessionChange` type.
    ///
    /// - Returns: The type.
    static func changeType() -> SchemaType {
        Type(SessionsGraphChange.self, as: "SessionChange") {
            Field("cursor", at: \.cursor).description("The cursor that resumes the subscription after this change.")
            Field("at", at: \.at).description("The time of the change.")
            Field("added", at: \.added).description("The session that started: new, restored or forked.")
            Field("changed", at: \.changed)
                .description("The session whose facts, state or inbox changed, or that was archived.")
            Field("removed", at: \.removed)
                .description("The sessions that left the server: none, because an archived session stays.")
        }
        .description("One change of one session that you can see.")
    }

    /// The `Query.cursor` field.
    ///
    /// - Returns: The field.
    static func cursorField() -> SchemaField {
        Field("cursor", at: SessionsGraphResolver.cursor)
            .description(
                "The cursor of the newest change. Read the sessions, then subscribe to changes after this cursor.")
    }

    /// The `Subscription.changes` field.
    ///
    /// - Returns: The field.
    static func changesField() -> SchemaField {
        SubscriptionField(
            "changes",
            at: { (entry: ChangeLogEntry<SessionsGraphChangeEvent>) in
                { (_: SessionsGraphContext, _: SessionsGraphChangesArguments) async throws -> SessionsGraphChange in
                    SessionsGraphChange(entry)
                }
            },
            atSub: SessionsGraphResolver.changes
        ) {
            Argument("after", at: \.after)
                .description(
                    "The cursor to resume after, from the cursor query or a change. None: the changes from now.")
        }
        .description(
            "The changes of the sessions that you can see, after a cursor. RESYNC_REQUIRED ends it when a change "
                + "after the cursor is lost: read the sessions and the cursor again, then subscribe with that cursor.")
    }
}
