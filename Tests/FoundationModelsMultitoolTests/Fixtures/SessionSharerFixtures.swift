import Foundation
import ULID

@testable import FoundationModelsMultitool

/// One call of ``RecordingSessionSharer``: what the operation asked the
/// sharer to do.
enum SessionSharerCall: Equatable, Sendable {
    /// `share(_:options:)`: a new share of the session with the options.
    case share(ULID, SessionShareOptions)

    /// `update(_:options:)`: a new snapshot of the session with the options.
    case update(ULID, SessionShareOptions)

    /// `stop(_:)`: the end of the share of the session.
    case stop(ULID)
}

/// The error of a fake sharer.
struct SessionSharerFailure: Error, CustomStringConvertible {
    /// The text of the failure.
    let description: String
}

/// A fake ``SessionSharer``: it keeps the shares in memory, records each
/// call that changes a share, and yields the id of a session whose share a
/// case changes "outside" through ``yieldChange(of:)``.
///
/// The fake has the transcript text ``content``, as a real sharer has the
/// snapshot. A case reads that no answer gives it.
actor RecordingSessionSharer: SessionSharer {
    /// The fixed time of each share that the fake makes or updates.
    static let updatedAt = Date(timeIntervalSince1970: SessionsToolFixtures.fixedSecondsSince1970)

    /// The text of the snapshot that the fake keeps for each share.
    static let content = "The transcript says: the secret plan is in plan.md."

    /// The share of each session that has one.
    private(set) var shares: [ULID: SessionShare]

    /// Each call that changed a share, the oldest first.
    private(set) var calls: [SessionSharerCall] = []

    /// The stream of ``shareChanges()``.
    private let changes: AsyncStream<ULID>

    /// The continuation of ``changes``.
    private let changeContinuation: AsyncStream<ULID>.Continuation

    /// Makes the sharer.
    ///
    /// - Parameter shares: The shares that exist before the case. The
    ///   default is no share.
    init(shares: [ULID: SessionShare] = [:]) {
        self.shares = shares
        (changes, changeContinuation) = AsyncStream.makeStream(of: ULID.self)
    }

    /// The URL of the share of a session.
    ///
    /// - Parameter session: The session.
    /// - Returns: The URL.
    static func url(of session: ULID) -> URL {
        URL(string: "https://www.icloud.com/share/\(session.ulidString)")!
    }

    /// The share that the fake makes for a session with options.
    ///
    /// - Parameters:
    ///   - session: The session.
    ///   - options: The options of the share.
    /// - Returns: The share, at ``updatedAt``.
    static func share(of session: ULID, options: SessionShareOptions) -> SessionShare {
        SessionShare(
            url: url(of: session), anyoneWithLink: options.anyoneWithLink, options: options, updatedAt: updatedAt)
    }

    /// Records the call, and keeps a new share.
    ///
    /// - Parameters:
    ///   - session: The session.
    ///   - options: The options of the share.
    /// - Returns: The new share.
    func share(_ session: ULID, options: SessionShareOptions) async throws -> SessionShare {
        calls.append(.share(session, options))
        let share = Self.share(of: session, options: options)
        shares[session] = share
        return share
    }

    /// Records the call, and keeps the share with the new options.
    ///
    /// - Parameters:
    ///   - session: The session.
    ///   - options: The options of the share.
    /// - Returns: The updated share.
    /// - Throws: ``SessionSharerFailure`` when the session has no share.
    func update(_ session: ULID, options: SessionShareOptions) async throws -> SessionShare {
        calls.append(.update(session, options))
        if shares[session] == nil {
            throw SessionSharerFailure(description: "no share of \(session.ulidString)")
        }
        let share = Self.share(of: session, options: options)
        shares[session] = share
        return share
    }

    /// Records the call, and removes the share.
    ///
    /// - Parameter session: The session.
    func stop(_ session: ULID) async throws {
        calls.append(.stop(session))
        shares[session] = nil
    }

    /// The share of a session.
    ///
    /// - Parameter session: The session.
    /// - Returns: The share, or `nil` when the session has none.
    func share(of session: ULID) async throws -> SessionShare? {
        shares[session]
    }

    /// The ids that ``yieldChange(of:)`` gives.
    ///
    /// - Returns: The one stream of the fake. Give it to one reader only.
    nonisolated func shareChanges() -> AsyncStream<ULID> {
        changes
    }

    /// Yields a change of the share of a session that came from outside a
    /// call of the package.
    ///
    /// - Parameter session: The session whose share changed.
    nonisolated func yieldChange(of session: ULID) {
        changeContinuation.yield(session)
    }
}

/// A fake ``SessionSharer`` whose each call fails. It has no
/// ``SessionSharer/shareChanges()`` of its own, so it gives the default.
struct FailingSessionSharer: SessionSharer {
    /// The error of each call.
    let failure: SessionSharerFailure

    /// Throws ``failure``.
    ///
    /// - Parameters:
    ///   - session: The session.
    ///   - options: The options of the share.
    /// - Returns: Never.
    /// - Throws: ``failure``.
    func share(_ session: ULID, options: SessionShareOptions) async throws -> SessionShare {
        throw failure
    }

    /// Throws ``failure``.
    ///
    /// - Parameters:
    ///   - session: The session.
    ///   - options: The options of the share.
    /// - Returns: Never.
    /// - Throws: ``failure``.
    func update(_ session: ULID, options: SessionShareOptions) async throws -> SessionShare {
        throw failure
    }

    /// Throws ``failure``.
    ///
    /// - Parameter session: The session.
    /// - Throws: ``failure``.
    func stop(_ session: ULID) async throws {
        throw failure
    }

    /// Throws ``failure``.
    ///
    /// - Parameter session: The session.
    /// - Returns: Never.
    /// - Throws: ``failure``.
    func share(of session: ULID) async throws -> SessionShare? {
        throw failure
    }
}
