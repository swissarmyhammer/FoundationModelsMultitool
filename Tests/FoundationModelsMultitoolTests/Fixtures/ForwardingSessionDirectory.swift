import FoundationModelsExtras
import ULID

/// A session directory that is a value type: each call goes to a backing
/// `InMemorySessionDirectory`. A test of the one endpoint of each directory
/// uses it as a directory with no identity.
struct ForwardingSessionDirectory: SessionDirectory {
    /// The directory that each call goes to.
    let backing: InMemorySessionDirectory

    /// The summaries of the backing directory that match `query`.
    ///
    /// - Parameter query: The filter.
    /// - Returns: The summaries.
    /// - Throws: The error of the backing directory.
    func sessions(matching query: SessionQuery) async throws -> [SessionSummary] {
        try await backing.sessions(matching: query)
    }

    /// The summary of one session of the backing directory.
    ///
    /// - Parameter id: The session id.
    /// - Returns: The summary, or `nil`.
    /// - Throws: The error of the backing directory.
    func summary(of id: ULID) async throws -> SessionSummary? {
        try await backing.summary(of: id)
    }

    /// Starts a session in the backing directory.
    ///
    /// - Parameter request: The start request.
    /// - Returns: The summary of the new session.
    /// - Throws: The error of the backing directory.
    func start(_ request: SessionStartRequest) async throws -> SessionSummary {
        try await backing.start(request)
    }

    /// Adds tags in the backing directory.
    ///
    /// - Parameters:
    ///   - tags: The tags.
    ///   - id: The session id.
    /// - Returns: The summary with the new tags.
    /// - Throws: The error of the backing directory.
    func addTags(_ tags: Set<String>, to id: ULID) async throws -> SessionSummary {
        try await backing.addTags(tags, to: id)
    }

    /// Removes tags in the backing directory.
    ///
    /// - Parameters:
    ///   - tags: The tags.
    ///   - id: The session id.
    /// - Returns: The summary with the tags that stay.
    /// - Throws: The error of the backing directory.
    func removeTags(_ tags: Set<String>, from id: ULID) async throws -> SessionSummary {
        try await backing.removeTags(tags, from: id)
    }

    /// Sets a title in the backing directory.
    ///
    /// - Parameters:
    ///   - title: The title.
    ///   - id: The session id.
    /// - Returns: The summary with the new title.
    /// - Throws: The error of the backing directory.
    func setTitle(_ title: String, of id: ULID) async throws -> SessionSummary {
        try await backing.setTitle(title, of: id)
    }

    /// Sends a message through the backing directory.
    ///
    /// - Parameter message: The message.
    /// - Returns: One receipt for each target.
    /// - Throws: The error of the backing directory.
    func send(_ message: OutgoingSessionMessage) async throws -> [SessionSendReceipt] {
        try await backing.send(message)
    }

    /// The unread messages of the backing directory to `id`.
    ///
    /// - Parameters:
    ///   - id: The session id.
    ///   - markRead: True to mark them read.
    /// - Returns: The messages.
    /// - Throws: The error of the backing directory.
    func inbox(of id: ULID, markRead: Bool) async throws -> [SessionMessage] {
        try await backing.inbox(of: id, markRead: markRead)
    }

    /// One message of the backing directory.
    ///
    /// - Parameters:
    ///   - id: The message id.
    ///   - recipient: The session that the message went to.
    /// - Returns: The message, or `nil`.
    /// - Throws: The error of the backing directory.
    func message(_ id: MailID, to recipient: ULID) async throws -> SessionMessage? {
        try await backing.message(id, to: recipient)
    }

    /// Archives a session in the backing directory.
    ///
    /// - Parameters:
    ///   - id: The session id.
    ///   - archiver: The session or the user that archives it.
    /// - Returns: The summary of the archived session.
    /// - Throws: The error of the backing directory.
    func archive(_ id: ULID, by archiver: SessionMessageSender) async throws -> SessionSummary {
        try await backing.archive(id, by: archiver)
    }

    /// The events of the backing directory.
    ///
    /// - Returns: A new stream of the events.
    func events() -> AsyncStream<SessionDirectoryEvent> {
        backing.events()
    }
}
