import Foundation
import FoundationModelsMetadataRegistry
import FoundationModelsRouter

// `RoutedAgentSession` — a Router session presented as an `AgentSession`.
//
// `FoundationModelsRanker` declared this type until `34fe8d4`, where it was
// removed. The supported route is now for each consumer to conform its own
// session type, thus this package holds the conformance. The shape is the one
// the ranker deleted, kept unchanged on purpose: a different shape here would
// be a third definition of the same seam, which is the outcome both packages
// want least.
//
// It stands in `MultitoolCLI` and not in the library, because discovery takes
// the registry seams and knows nothing of Router. The host picks the models,
// and this host picks Router ones.

/// A `RoutedSession` presented to the selection tier as an `AgentSession`.
///
/// The tier holds every session as `any AgentSession` and knows nothing of
/// Router. This is the whole of the join between the two.
public struct RoutedAgentSession: AgentSession {

    /// The Router session every call travels to.
    private let session: any RoutedSession

    /// Makes the presentation over one Router session.
    ///
    /// - Parameter session: The session to present.
    public init(session: any RoutedSession) {
        self.session = session
    }

    /// Sends `prompt` to the session and answers with its complete text.
    ///
    /// - Parameter prompt: The prompt to send.
    /// - Returns: The session's complete text response.
    /// - Throws: Whatever the underlying session throws, with Router's
    ///   same-model refusal replaced by ``SameModelDiscoveryError`` — see
    ///   ``explained(_:)``.
    public func respond(to prompt: String) async throws -> String {
        do {
            return try await session.respond(to: prompt)
        } catch {
            throw Self.explained(error)
        }
    }

    /// Forks a child session that continues this one's conversation.
    ///
    /// **This override is load-bearing, and the protocol default is wrong for
    /// a Router session.** `AgentSession.fork()` defaults to returning `self`,
    /// which is correct only for a session that cannot really fork. A
    /// `RoutedSession` forks at the cache level: the child gets a copy of the
    /// prefilled KV cache. Taking the default would leave the selection tier's
    /// cached-root path re-sending the assembled prefix on every call, and the
    /// loss would be silent — the tier would still answer correctly, only
    /// slower and at more tokens.
    ///
    /// - Returns: The forked child session.
    /// - Throws: Whatever the underlying session throws while forking, with
    ///   Router's same-model refusal replaced as ``respond(to:)`` replaces it.
    public func fork() async throws -> any AgentSession {
        do {
            return RoutedAgentSession(session: try await session.fork(workingDirectory: nil))
        } catch {
            throw Self.explained(error)
        }
    }

    /// `error`, with Router's same-model refusal replaced by an error whose
    /// text names the fix.
    ///
    /// Router refuses at once a wait inside an open submission on the same
    /// model (`GenerationQueueError.waitInsideOpenSubmission`). For discovery
    /// that refusal has one cause: the discovery session runs on the model of
    /// the session that called `searchTools`. Router's own text tells a tool
    /// author to use a background tool, but `searchTools` stays synchronous.
    /// The fix is a different model, and ``SameModelDiscoveryError`` says so.
    ///
    /// - Parameter error: The error the Router session threw.
    /// - Returns: A ``SameModelDiscoveryError`` for the same-model refusal,
    ///   and `error` unchanged for each other error.
    static func explained(_ error: any Error) -> any Error {
        guard case .waitInsideOpenSubmission(let model)? = error as? GenerationQueueError else {
            return error
        }
        return SameModelDiscoveryError(model: model)
    }
}

/// The error a discovery session gives when Router refuses it, because it
/// runs on the model of the session that called `searchTools`.
///
/// Router shows a failed tool call to the model as `String(describing:)` of
/// its error, so ``description`` carries the whole fix.
public struct SameModelDiscoveryError: Error, Equatable, CustomStringConvertible, LocalizedError {
    /// The model of the discovery session, which is also the model of the
    /// calling session.
    public let model: ModelRef

    /// Makes the error for a refusal on `model`.
    ///
    /// - Parameter model: The model that Router refused the wait on.
    public init(model: ModelRef) {
        self.model = model
    }

    /// The text of the error, which names the model and the fix.
    public var description: String {
        """
        searchTools started a discovery session on \(model.stringValue), which is also the model of \
        the session that called searchTools. searchTools is synchronous, so it cannot wait for a \
        session on the same model inside an open submission, and Router refused the wait. The \
        librarian model must be different from the model of the calling session. Use a flash model \
        that is different from the standard model.
        """
    }

    /// The same text as ``description``.
    public var errorDescription: String? { description }
}
