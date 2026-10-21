// `SessionsToolContext` — the shared context of the operations of the
// `sessions` tool.
//
// session.md section 8: `SessionsToolContext` holds `any SessionDirectory`.
// Each operation reads the directory through it, and reads the caller
// session from `ToolContext.current` at the start of its call.

import FoundationModelsExtras
import ULID

/// The shared context of the operations of ``SessionsTool``.
struct SessionsToolContext: Sendable {
    /// The session directory that each operation reads.
    let directory: any SessionDirectory

    /// The session of the current call, or `nil` for a call with no
    /// `ToolContext` (outside a Router session). A call with no caller can
    /// only read the directory (session.md section 8.2).
    var callerID: ULID? {
        ToolContext.current?.sessionID
    }

    /// Runs the work of an operation that acts for the caller session, and
    /// turns each error into a corrective.
    ///
    /// - Parameters:
    ///   - opString: The op string of the operation, for the corrective of a
    ///     call with no caller session.
    ///   - body: The work, given the caller id.
    /// - Returns: What `body` gave, a corrective for a call with no caller
    ///   session, or the corrective of the error that `body` threw.
    func answer(asCallerOf opString: String, _ body: (ULID) async throws -> String) async -> String {
        guard let callerID else {
            return SessionsToolText.noCallerSession(opString)
        }
        do {
            return try await body(callerID)
        } catch {
            return SessionsToolText.corrective(for: error)
        }
    }

    /// The summary of the session `id`, which must exist.
    ///
    /// - Parameter id: The session id.
    /// - Returns: The summary.
    /// - Throws: `SessionDirectoryError.unknownSession` when no session has
    ///   the id, and each error of `summary(of:)`.
    func existingSummary(of id: ULID) async throws -> SessionSummary {
        guard let summary = try await directory.summary(of: id) else {
            throw SessionDirectoryError.unknownSession(id)
        }
        return summary
    }
}
