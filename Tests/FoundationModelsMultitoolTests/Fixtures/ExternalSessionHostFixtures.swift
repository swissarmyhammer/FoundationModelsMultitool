import Foundation
import FoundationModelsExtras
import Synchronization
import ULID

@testable import FoundationModelsMultitool

/// The error of a fake external session host.
struct ExternalSessionHostFailure: Error, CustomStringConvertible {
    /// The text of the failure.
    let description: String
}

/// A fake ``ExternalSessionHost``: a fixed index of external sessions and a
/// fixed history for each session.
///
/// The fake records each query, each count, each rebuild, each followed
/// folder, each read session and each continue request, so a case proves what the endpoint or the tool
/// asked the host to do. It gives signals as streams, so a case waits for an
/// event of the host and never for a time:
///
/// - ``queryStarts`` and ``queryCancellations`` for a query or a count that
///   waits for its cancellation (``blocksCalls``), and ``continueStarts`` and
///   ``continueCancellations`` for a continue that waits.
/// - ``updateTerminations`` gives `true` when a reader stops an update
///   stream (a cancellation) and `false` when the stream finishes.
///
/// ``add(_:indexState:)`` adds a row to the index and sends the change to
/// each follower.
final class FakeExternalSessionHost: ExternalSessionHost {
    /// The recorded calls and the open streams of the fake.
    private struct State {
        /// Each query, the oldest first.
        var queries: [ExternalSessionQuery] = []

        /// Each folder of `externalSessionChanges(folder:)`, the oldest first.
        var changeFolders: [URL?] = []

        /// Each session of `externalSessionUpdates(of:)`, the oldest first.
        var updateSessions: [ExternalSessionID] = []

        /// Each continue request, the oldest first.
        var continueRequests: [ExternalSessionContinueRequest] = []

        /// The scope of each count, the oldest first.
        var countScopes: [CountScope] = []

        /// The source of each rebuild, the oldest first.
        var rebuildSources: [String] = []

        /// The continuation of each followed change stream.
        var followers: [AsyncStream<ExternalSessionChange>.Continuation] = []

        /// The continuation of each stream that a waiting call reads. The
        /// fake holds them, so that the streams end only at a cancellation.
        var waits: [AsyncStream<Void>.Continuation] = []
    }

    /// The scope of one call of `externalSessionCounts(source:folder:)`.
    struct CountScope: Equatable {
        /// The source agent, or `nil` for each source.
        let source: String?

        /// The working folder, or `nil` for each folder.
        let folder: URL?
    }

    /// The sources that the fake knows. A rebuild of a different source
    /// gives ``ExternalSessionError/sourceUnreadable(source:)``.
    static let knownSources = [claudeCode, codex]

    /// The source agent of the sessions of the fake that are not automated.
    static let claudeCode = "claude-code"

    /// The source agent of the automated session of the fake.
    static let codex = "codex"

    /// The progress of a complete index.
    static let completeIndex = ExternalSessionIndexState(filesFound: 3, filesRead: 3, isComplete: true)

    /// The sessions of the index.
    let sessions: [ExternalSessionSummary]

    /// The progress of the index that each page gives.
    let indexState: ExternalSessionIndexState

    /// The cursor of the next page that each page gives.
    let nextCursor: String?

    /// The sources whose sessions the fake cannot read.
    let unreadableSources: [String]

    /// The batches of the history of each session, in order.
    let batches: [ExternalSessionUpdateBatch]

    /// True when an update stream finishes after its last batch. False when
    /// it stays open until its reader stops.
    let finishesUpdates: Bool

    /// True when a query and a continue wait until their task is cancelled.
    let blocksCalls: Bool

    /// The folders in which the fake cannot make a session.
    let unavailableFolders: [URL]

    /// The progress of the folder of a query with a folder. A query with no
    /// folder gets none.
    let folderIndexState: ExternalSessionIndexState?

    /// The cursor that the fake refuses with
    /// ``ExternalSessionError/invalidCursor(_:)``, or `nil`.
    let invalidCursor: String?

    /// The calls and the streams of the fake.
    private let state = Mutex(State())

    /// A signal for each start of a query.
    let queryStarts: AsyncStream<Void>

    /// A signal for each query that saw its cancellation.
    let queryCancellations: AsyncStream<Void>

    /// A signal for each start of a continue.
    let continueStarts: AsyncStream<Void>

    /// A signal for each continue that saw its cancellation.
    let continueCancellations: AsyncStream<Void>

    /// For each update stream that ended: `true` when its reader stopped it,
    /// `false` when it finished.
    let updateTerminations: AsyncStream<Bool>

    /// The continuation of ``queryStarts``.
    private let queryStart: AsyncStream<Void>.Continuation

    /// The continuation of ``queryCancellations``.
    private let queryCancellation: AsyncStream<Void>.Continuation

    /// The continuation of ``continueStarts``.
    private let continueStart: AsyncStream<Void>.Continuation

    /// The continuation of ``continueCancellations``.
    private let continueCancellation: AsyncStream<Void>.Continuation

    /// The continuation of ``updateTerminations``.
    private let updateTermination: AsyncStream<Bool>.Continuation

    /// Makes the fake.
    ///
    /// - Parameters:
    ///   - sessions: The sessions of the index. The default is
    ///     ``typedSession`` and ``automatedSession``.
    ///   - indexState: The progress of the index. The default is complete.
    ///   - nextCursor: The cursor of the next page. The default is none.
    ///   - unreadableSources: The sources that the fake cannot read. The
    ///     default is none.
    ///   - batches: The batches of the history of each session. The default
    ///     is none.
    ///   - finishesUpdates: True when an update stream finishes after its
    ///     last batch. The default is true.
    ///   - blocksCalls: True when a query and a continue wait until their
    ///     task is cancelled. The default is false.
    ///   - unavailableFolders: The folders in which the fake cannot make a
    ///     session. The default is none.
    ///   - folderIndexState: The progress of the folder of a query with a
    ///     folder. The default is none.
    ///   - invalidCursor: The cursor that the fake refuses. The default is
    ///     none.
    init(
        sessions: [ExternalSessionSummary] = [typedSession, automatedSession],
        indexState: ExternalSessionIndexState = completeIndex, nextCursor: String? = nil,
        unreadableSources: [String] = [], batches: [ExternalSessionUpdateBatch] = [], finishesUpdates: Bool = true,
        blocksCalls: Bool = false, unavailableFolders: [URL] = [],
        folderIndexState: ExternalSessionIndexState? = nil, invalidCursor: String? = nil
    ) {
        self.sessions = sessions
        self.indexState = indexState
        self.nextCursor = nextCursor
        self.unreadableSources = unreadableSources
        self.batches = batches
        self.finishesUpdates = finishesUpdates
        self.blocksCalls = blocksCalls
        self.unavailableFolders = unavailableFolders
        self.folderIndexState = folderIndexState
        self.invalidCursor = invalidCursor
        (queryStarts, queryStart) = AsyncStream.makeStream()
        (queryCancellations, queryCancellation) = AsyncStream.makeStream()
        (continueStarts, continueStart) = AsyncStream.makeStream()
        (continueCancellations, continueCancellation) = AsyncStream.makeStream()
        (updateTerminations, updateTermination) = AsyncStream.makeStream()
    }

    // MARK: - The fixed sessions

    /// A typed session of Claude Code in ``SessionsToolFixtures/workingFolder``.
    static let typedSession = ExternalSessionSummary(
        source: claudeCode, sourceID: "a1b2c3", path: "-work-project/a1b2c3.jsonl", projectKey: "-work-project",
        size: 4096, modified: SessionsToolFixtures.fixedDate, cwd: SessionsToolFixtures.workingFolder,
        gitBranch: "main", title: "Fix the parser", firstPrompt: "The parser fails", lastPrompt: "Run the tests",
        firstDate: SessionsToolFixtures.fixedDate, lastDate: SessionsToolFixtures.fixedDate, state: .read)

    /// The first session that a continue made from ``continuedSession``.
    static let firstContinuation = ExternalSessionContinuation(
        sessionID: ULID(), createdAt: SessionsToolFixtures.fixedDate)

    /// The second session that a continue made from ``continuedSession``,
    /// one hour after the first.
    static let secondContinuation = ExternalSessionContinuation(
        sessionID: ULID(), createdAt: SessionsToolFixtures.fixedDate.addingTimeInterval(3600))

    /// ``typedSession`` with the two sessions that a continue made from it.
    static let continuedSession: ExternalSessionSummary = {
        var session = typedSession
        session.continuedSessions = [firstContinuation, secondContinuation]
        return session
    }()

    /// An automated session of Codex with no text and no folder.
    static let automatedSession = ExternalSessionSummary(
        source: codex, sourceID: "rollout-42", path: "2027/01/15/rollout-42.jsonl", size: 8_000_000_000,
        modified: SessionsToolFixtures.fixedDate, isAutomated: true, state: .found)

    /// A session that the index adds after the first page.
    static let addedSession = ExternalSessionSummary(
        source: claudeCode, sourceID: "d4e5f6", path: "-work-project/d4e5f6.jsonl", projectKey: "-work-project",
        size: 2048, modified: SessionsToolFixtures.fixedDate, cwd: SessionsToolFixtures.workingFolder,
        title: "Add the cache", state: .read)

    /// One entry of a history.
    ///
    /// - Parameters:
    ///   - kind: The kind of the entry.
    ///   - text: The text of the entry, at `content.text`, or `nil`.
    ///   - title: The title of the entry, or `nil`.
    ///   - status: The status of the entry, or `nil`.
    /// - Returns: The entry, at the fixed date.
    static func entry(
        _ kind: String, text: String? = nil, title: String? = nil, status: String? = nil
    ) -> SessionTranscriptEntry {
        var fields: [String: OperationValue] = [:]
        fields["content"] = text.map { .object(["type": .string("text"), "text": .string($0)]) }
        fields["title"] = title.map(OperationValue.string)
        fields["status"] = status.map(OperationValue.string)
        return SessionTranscriptEntry(kind: kind, timestamp: SessionsToolFixtures.fixedDate, payload: .object(fields))
    }

    /// The batches of a history of `count` turns, one batch for each turn:
    /// a user prompt, a thought, an answer, a tool call and its result.
    ///
    /// - Parameter count: The number of turns.
    /// - Returns: The batches.
    static func turns(_ count: Int) -> [ExternalSessionUpdateBatch] {
        (1...count).map { number in
            ExternalSessionUpdateBatch(entries: [
                entry("user_message_chunk", text: "prompt \(number)"),
                entry("agent_thought_chunk", text: "thought \(number)"),
                entry("agent_message_chunk", text: "answer \(number)"),
                entry("tool_call", title: "Read file\(number).swift"),
                entry("tool_call_update", text: "contents \(number)", status: "completed"),
            ])
        }
    }

    // MARK: - The recorded calls

    /// Each query, the oldest first.
    var queries: [ExternalSessionQuery] {
        state.withLock { $0.queries }
    }

    /// Each folder of `externalSessionChanges(folder:)`, the oldest first.
    var changeFolders: [URL?] {
        state.withLock { $0.changeFolders }
    }

    /// Each session of `externalSessionUpdates(of:)`, the oldest first.
    var updateSessions: [ExternalSessionID] {
        state.withLock { $0.updateSessions }
    }

    /// Each continue request, the oldest first.
    var continueRequests: [ExternalSessionContinueRequest] {
        state.withLock { $0.continueRequests }
    }

    /// The scope of each count, the oldest first.
    var countScopes: [CountScope] {
        state.withLock { $0.countScopes }
    }

    /// The source of each rebuild, the oldest first.
    var rebuildSources: [String] {
        state.withLock { $0.rebuildSources }
    }

    /// Adds a session to the index, and sends the change to each follower.
    ///
    /// - Parameters:
    ///   - session: The session that the index adds.
    ///   - indexState: The progress of the index after the change.
    func add(
        _ session: ExternalSessionSummary, indexState: ExternalSessionIndexState,
        folderIndexState: ExternalSessionIndexState? = nil
    ) {
        let followers = state.withLock { $0.followers }
        for follower in followers {
            follower.yield(
                ExternalSessionChange(
                    changed: [session], indexState: indexState, folderIndexState: folderIndexState))
        }
    }

    // MARK: - ExternalSessionHost

    /// Records the query, and gives the sessions of its source, its folder
    /// and its automated filter.
    ///
    /// - Parameter query: The query.
    /// - Returns: The page.
    /// - Throws: `CancellationError` after the cancellation of a waiting
    ///   call.
    func externalSessions(_ query: ExternalSessionQuery) async throws -> ExternalSessionPage {
        state.withLock { $0.queries.append(query) }
        if blocksCalls {
            try await waitForCancellation(started: queryStart, cancelled: queryCancellation)
        }
        if let cursor = query.cursor, cursor == invalidCursor {
            throw ExternalSessionError.invalidCursor(cursor)
        }
        let matching = sessions.filter { session in
            (query.source ?? session.source) == session.source
                && (query.folder.map { $0.path == session.cwd?.path } ?? true)
                && (query.automated || !session.isAutomated)
        }
        return ExternalSessionPage(
            sessions: Array(matching.prefix(query.limit)), indexState: indexState, nextCursor: nextCursor,
            unreadableSources: unreadableSources, folderIndexState: query.folder == nil ? nil : folderIndexState)
    }

    /// Records the scope, and counts the typed and the automated sessions of
    /// its source and its folder.
    ///
    /// - Parameters:
    ///   - source: The source agent, or `nil` for each source.
    ///   - folder: The working folder, or `nil` for each folder.
    /// - Returns: The counts, with ``folderIndexState`` for a scope with a
    ///   folder when the fake has one, else with ``indexState``.
    /// - Throws: `CancellationError` after the cancellation of a waiting
    ///   call.
    func externalSessionCounts(source: String?, folder: URL?) async throws -> ExternalSessionCounts {
        state.withLock { $0.countScopes.append(CountScope(source: source, folder: folder)) }
        if blocksCalls {
            try await waitForCancellation(started: queryStart, cancelled: queryCancellation)
        }
        let matching = sessions.filter { session in
            (source ?? session.source) == session.source && (folder.map { $0.path == session.cwd?.path } ?? true)
        }
        let automatedCount = matching.filter(\.isAutomated).count
        return ExternalSessionCounts(
            typedCount: matching.count - automatedCount, automatedCount: automatedCount,
            indexState: folder == nil ? indexState : folderIndexState ?? indexState)
    }

    /// Records the source of the rebuild.
    ///
    /// - Parameter source: The source agent.
    /// - Throws: ``ExternalSessionError/sourceUnreadable(source:)`` for a
    ///   source that the fake does not know or cannot read.
    func rebuildExternalSessionIndex(source: String) async throws {
        state.withLock { $0.rebuildSources.append(source) }
        guard Self.knownSources.contains(source), !unreadableSources.contains(source) else {
            throw ExternalSessionError.sourceUnreadable(source: source)
        }
    }

    /// Records the folder, and gives a stream that ``add(_:indexState:)``
    /// feeds.
    ///
    /// - Parameter folder: The folder to follow.
    /// - Returns: The stream.
    func externalSessionChanges(folder: URL?) -> AsyncStream<ExternalSessionChange> {
        let (stream, continuation) = AsyncStream.makeStream(of: ExternalSessionChange.self)
        state.withLock { state in
            state.changeFolders.append(folder)
            state.followers.append(continuation)
        }
        return stream
    }

    /// Records the session, and gives ``batches``.
    ///
    /// - Parameter session: The session.
    /// - Returns: The stream. It finishes with
    ///   ``ExternalSessionError/sourceUnreadable(source:)`` for a source that
    ///   the fake cannot read, and with
    ///   ``ExternalSessionError/unknownSession(_:)`` for a session that the
    ///   index does not have.
    func externalSessionUpdates(of session: ExternalSessionID) -> AsyncThrowingStream<
        ExternalSessionUpdateBatch, any Error
    > {
        state.withLock { $0.updateSessions.append(session) }
        let termination = updateTermination
        let error = updateError(of: session)
        return AsyncThrowingStream { continuation in
            continuation.onTermination = { reason in
                if case .cancelled = reason {
                    termination.yield(true)
                } else {
                    termination.yield(false)
                }
            }
            if let error {
                continuation.finish(throwing: error)
                return
            }
            for batch in batches {
                continuation.yield(batch)
            }
            if finishesUpdates {
                continuation.finish()
            }
        }
    }

    /// Records the request, and gives a new session in the folder of the
    /// request, else in the working folder of the session.
    ///
    /// - Parameter request: The request.
    /// - Returns: The summary of the new session, with the name of the
    ///   request, else `claude-code`.
    /// - Throws: ``ExternalSessionError`` for a source that the fake cannot
    ///   read, a session that the index does not have, and a folder in which
    ///   it cannot make a session; `CancellationError` after the
    ///   cancellation of a waiting call.
    func continueExternalSession(_ request: ExternalSessionContinueRequest) async throws -> SessionSummary {
        state.withLock { $0.continueRequests.append(request) }
        if blocksCalls {
            try await waitForCancellation(started: continueStart, cancelled: continueCancellation)
        }
        if let error = updateError(of: request.session) {
            throw error
        }
        let source = sessions.first { $0.id == request.session }
        let folder = request.folder ?? source?.cwd ?? SessionsToolFixtures.workingFolder
        if unavailableFolders.contains(where: { $0.path == folder.path }) {
            throw ExternalSessionError.folderUnavailable(folder)
        }
        return SessionsToolFixtures.summary(title: request.name ?? Self.claudeCode, folder: folder)
    }

    // MARK: - Helpers

    /// The error of a read or a continue of a session.
    ///
    /// - Parameter session: The session.
    /// - Returns: The error, or `nil` when the fake can read the session.
    private func updateError(of session: ExternalSessionID) -> ExternalSessionError? {
        if unreadableSources.contains(session.source) {
            return .sourceUnreadable(source: session.source)
        }
        guard sessions.contains(where: { $0.id == session }) else {
            return .unknownSession(session)
        }
        return nil
    }

    /// Signals the start, waits until the task is cancelled, signals the
    /// cancellation, and throws `CancellationError`.
    ///
    /// - Parameters:
    ///   - started: The signal of the start.
    ///   - cancelled: The signal of the cancellation.
    /// - Throws: `CancellationError`.
    private func waitForCancellation(
        started: AsyncStream<Void>.Continuation, cancelled: AsyncStream<Void>.Continuation
    ) async throws {
        let (wait, keep) = AsyncStream.makeStream(of: Void.self)
        state.withLock { $0.waits.append(keep) }
        started.yield()
        for await _ in wait {}
        cancelled.yield()
        throw CancellationError()
    }
}
