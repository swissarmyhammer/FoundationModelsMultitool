// The `fork session` operation of the `sessions` tool (D205, D100: the agent
// can do what the UI can do).
//
// A fork is a new top-level session of the kind `fork`, in the folder of its
// source, with a copy of the history of the source up to a cut. After the
// cut, the fork works alone. With no `id`, the source is the caller session,
// and the cut is the calling tool call: the fork gets the history up to this
// call, not the call. With an `id`, the cut is the last completed turn of
// that session.
//
// The operation acts for the caller session, as the change operations do: a
// call with no caller gives a corrective. Each error is a corrective text,
// never a thrown model error. The work of the fork is in the extension of
// ``SessionsToolContext`` at the end of this file, which the `forkSession`
// mutation of the `sessions` endpoint calls too (MT-10).

import Foundation
import FoundationModels
import FoundationModelsExtras
import Operations
import ULID

/// Forks a session from here (`fork session`, D205).
@Generable
@Operation(
    verb: "fork", noun: "session",
    description: """
        Fork a session from here: the fork has the history up to this call and then works alone. With an id, \
        the fork has the history of that session up to its last completed turn. The fork does not report back: \
        to tell it something, use `send message`.
        """)
struct ForkSession {
    /// The session to fork: its id, its short id or its slug.
    @Guide(description: SessionsToolText.forkSourceReference)
    var id: String?

    /// The first prompt of the fork.
    @Guide(description: "Optional. The first prompt of the fork. With none, the fork waits for a message.")
    @OperationParam(aliases: ["firstPrompt", "prompt", "text"])
    var message: String?
}

extension ForkSession {
    /// Forks the caller session at this call, or the session `id` at its last
    /// completed turn.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: The id, the short id and the name of the fork, and the
    ///   sentence that tells that it works alone. A corrective for a call
    ///   with no caller, an id that names no session or more than one
    ///   session, an archived source, a server that cannot fork, or another
    ///   error of the directory.
    func execute(in context: SessionsToolContext) async throws -> String {
        await context.answer(asCallerOf: Self.opString) { callerID in
            let source = try await context.sessionID(referencedBy: id, defaultingTo: callerID)
            let cut: SessionForkCut = id == nil ? .callingToolCall : .lastCompletedTurn
            let fork = try await context.fork(session: source, at: cut, firstPrompt: message, by: .session(callerID))
            return SessionsToolText.forked(fork)
        }
    }
}

extension SessionsToolContext {
    /// Forks a session, for `fork session` and the `forkSession` mutation
    /// (D205).
    ///
    /// A fork that a user asks for names the client of the user, so only that
    /// client opens the fork in a tab, as a start does (D90).
    ///
    /// - Parameters:
    ///   - source: The session to fork.
    ///   - cut: The point in the history of the source where the fork cuts
    ///     it.
    ///   - message: The first prompt of the fork, with any space around it,
    ///     or `nil` for none. A text that holds only space is none.
    ///   - forker: The session or the user that asks for the fork.
    /// - Returns: The fork.
    /// - Throws: Each error of `SessionDirectory.fork(_:)`: an unknown or
    ///   archived source, a cut out of range, and a server that cannot fork.
    func fork(
        session source: ULID, at cut: SessionForkCut, firstPrompt message: String?, by forker: SessionMessageSender
    ) async throws -> SessionSummary {
        var request = SessionForkRequest(
            sourceID: source, cut: cut, firstPrompt: SessionsToolInput.nonBlank(message), forker: forker)
        if case .user(let clientID) = forker {
            request.requestedByClient = clientID
        }
        return try await directory.fork(request)
    }
}
