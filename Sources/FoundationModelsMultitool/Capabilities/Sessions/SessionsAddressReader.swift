// `SessionsAddressReader` — the one reader of a message address, which the
// `send message` operation of the `sessions` tool and the `sendMessage`
// mutation of the `sessions` endpoint both call (D100, D199 (c) to (e)). The
// `id` of `check session` and of each change operation of the tool reads a
// session reference through the same resolver (D200 (e)).
//
// A session has one namespace: `@<id>`, `<id>`, `@<short id>`, `<short id>`
// and `@<slug>` name one session, through `SessionReference.resolve` of
// Extras, over the sessions that the caller can see. The order is a full id,
// then a short id, then a slug; a short id and a slug look first in the
// lookup folder, then in all the sessions. The lookup folder is the folder of
// the sending session, or, for the user, the folder of the session in which
// the user wrote the message (D199 (f)). An agent is a session: when
// `@<name>` names no session, the address is the agent with that name, and
// the directory starts a new root session of it. The launcher of the
// directory is the agent catalog: it refuses a name that no agent folder has
// with `SessionDirectoryError.unknownAgent`, and the send gives the corrective
// that no session and no agent has the name.
//
// `@agent:/path` and a folder path alone are aliases, in the style of D86:
// the reader reads `@agent:/path` as `@agent` with the lookup in `/path`
// first, reads a folder path as the newest root session in the folder, and
// reports each rewrite. `#tag` names a group of sessions, not one target.

import Foundation
import FoundationModelsExtras
import ULID

/// A message address after the reader: the target, and the report of the
/// rewrite of an alias.
struct SessionsAddressReading: Sendable, Equatable {
    /// The target of the message.
    let address: SessionAddress

    /// The report of the rewrite of an alias, or `nil` for an address that
    /// is not an alias.
    let rewrite: String?
}

extension SessionsVisibility {
    /// Reads a message address from `sender` (D199 (c) to (e)).
    ///
    /// The lookup folder of a short id and of a slug is `sourceFolder`, else
    /// the working folder of the sending session, or the folder of an
    /// `@agent:/path` alias. A sender that is the user, with no source
    /// folder, has no lookup folder: the lookup is in all the sessions that
    /// the viewer can see.
    ///
    /// - Parameters:
    ///   - text: The address, with any space around it.
    ///   - sender: The session or the user that sends the message.
    ///   - sourceFolder: The working folder of the session in which the user
    ///     wrote the message (D199 (f)), or `nil`. The default is `nil`.
    /// - Returns: The target, and the report of the rewrite of an alias.
    /// - Throws: ``SessionsRefusal`` for a text in no form, for a reference
    ///   that names more than one session, and for an alias with a relative
    ///   folder; each error of the directory.
    func messageAddress(
        _ text: String, from sender: SessionMessageSender, sourceFolder: URL? = nil
    ) async throws -> SessionsAddressReading {
        let written = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch try SessionsToolInput.addressForm(text) {
        case .folder(let folder):
            return SessionsAddressReading(
                address: .folder(folder), rewrite: SessionsToolText.folderAliasRewrite(written, folder: folder))
        case .tag(let tag):
            return SessionsAddressReading(address: .tag(tag), rewrite: nil)
        case .agentAlias(let name, let folder):
            return SessionsAddressReading(
                address: try await address(ofName: name, lookupFolder: folder),
                rewrite: SessionsToolText.agentAliasRewrite(written, name: name, folder: folder))
        case .id(let id):
            return SessionsAddressReading(address: .session(id), rewrite: nil)
        case .name(let name):
            let lookupFolder = try await lookupFolder(of: sender, sourceFolder: sourceFolder)
            return SessionsAddressReading(
                address: try await address(ofName: name, lookupFolder: lookupFolder), rewrite: nil)
        case .shortID(let shortID):
            let lookupFolder = try await lookupFolder(of: sender, sourceFolder: sourceFolder)
            return SessionsAddressReading(
                address: try await address(ofShortID: shortID, written: text, lookupFolder: lookupFolder),
                rewrite: nil)
        }
    }

    /// The session id that the `id` of a session operation names (D200 (e)):
    /// `<id>`, `@<id>`, `<short id>`, `@<short id>` or `@<slug>`.
    ///
    /// A full id gives its id at once, thus an archived session, which the
    /// resolver never matches, is still found by its id. A short id and a
    /// slug go through the resolver of `send message`, over the sessions
    /// that the viewer can see. A text with no `@` names a session only by
    /// its short id. The reader never starts an agent.
    ///
    /// - Parameters:
    ///   - text: The `id` as written.
    ///   - lookupFolder: The folder in which a short id or a slug looks
    ///     first, or `nil` to look in all the sessions at once.
    /// - Returns: The session id.
    /// - Throws: ``SessionsRefusal`` for a reference that names more than one
    ///   session, and for a reference that names no session that the viewer
    ///   can see; each error of the directory.
    func sessionID(referencedBy text: String, lookupFolder: URL?) async throws -> ULID {
        if let id = SessionsToolInput.fullSessionID(text) {
            return id
        }
        let resolution =
            SessionsToolInput.isAtReference(text)
            ? try await resolution(of: text, lookupFolder: lookupFolder)
            : try await shortIDResolution(of: text, lookupFolder: lookupFolder)
        switch resolution {
        case .session(let summary):
            return summary.id
        case .ambiguous(let matches):
            throw Self.ambiguity(of: text, among: matches, outcome: SessionsToolText.notChangedSentence)
        case .none:
            throw SessionsRefusal(.invalidSessionID, SessionsToolText.notASessionID(text))
        }
    }

    /// The session id that the `id` of a session operation names, with the
    /// working folder of the caller as the lookup folder (D200 (e)).
    ///
    /// - Parameters:
    ///   - text: The `id` as written.
    ///   - callerID: The caller session, or `nil` for a call with no caller
    ///     session: the lookup is then in all the sessions at once.
    /// - Returns: The session id.
    /// - Throws: What ``sessionID(referencedBy:lookupFolder:)`` throws.
    func sessionID(referencedBy text: String, callerID: ULID?) async throws -> ULID {
        guard let callerID else {
            return try await sessionID(referencedBy: text, lookupFolder: nil)
        }
        let lookupFolder = try await workingFolder(of: .session(callerID))
        return try await sessionID(referencedBy: text, lookupFolder: lookupFolder)
    }

    /// The one session that a reference names, among the sessions that the
    /// viewer can see: a full id, a short id or a slug, with or without `@`.
    ///
    /// - Parameters:
    ///   - reference: The reference, as written.
    ///   - lookupFolder: The folder in which a short id or a slug looks
    ///     first, or `nil` to look in all the sessions at once.
    /// - Returns: The session, or `nil` when the reference names no session
    ///   that the viewer can see and that is not archived.
    /// - Throws: ``SessionsRefusal`` for a reference that names more than one
    ///   session, and each error of the directory.
    func session(named reference: String, lookupFolder: URL?) async throws -> SessionSummary? {
        switch try await resolution(of: reference, lookupFolder: lookupFolder) {
        case .session(let summary):
            return summary
        case .ambiguous(let matches):
            throw Self.ambiguity(of: reference, among: matches, outcome: SessionsToolText.notSentSentence)
        case .none:
            return nil
        }
    }

    /// The resolution of a reference by `SessionReference.resolve`, over each
    /// session that the viewer can see, the recorded sessions too.
    ///
    /// - Parameters:
    ///   - reference: The reference, as written.
    ///   - lookupFolder: The folder in which a short id or a slug looks
    ///     first, or `nil`.
    /// - Returns: The resolution.
    /// - Throws: Each error of the directory.
    func resolution(of reference: String, lookupFolder: URL?) async throws -> SessionReferenceResolution {
        let candidates = try await sessions(matching: SessionQuery(includesRecorded: true, limit: Self.unboundedLimit))
        return SessionReference.resolve(reference, sourceFolder: lookupFolder, among: candidates)
    }

    /// The lookup folder of a short id and of a slug: `sourceFolder`, else
    /// the working folder of the sender.
    ///
    /// - Parameters:
    ///   - sender: The sender.
    ///   - sourceFolder: The working folder of the source session, or `nil`.
    /// - Returns: The folder, or `nil` for a lookup in all the sessions.
    /// - Throws: Each error of the directory.
    private func lookupFolder(of sender: SessionMessageSender, sourceFolder: URL?) async throws -> URL? {
        guard let sourceFolder else {
            return try await workingFolder(of: sender)
        }
        return sourceFolder
    }

    /// The working folder of a sending session, or `nil` for the user.
    ///
    /// - Parameter sender: The sender.
    /// - Returns: The folder, or `nil` when the sender is the user or a
    ///   session that the viewer cannot see.
    /// - Throws: Each error of the directory.
    func workingFolder(of sender: SessionMessageSender) async throws -> URL? {
        guard case .session(let id) = sender else {
            return nil
        }
        return try await summary(of: id)?.workingDirectory
    }

    /// The target of `@<name>`: the session with that short id or slug, or
    /// else the agent with that name (D199 (e)).
    ///
    /// - Parameters:
    ///   - name: The text after the `@`.
    ///   - lookupFolder: The folder in which the lookup looks first, and the
    ///     folder of a new session of the agent.
    /// - Returns: The address.
    /// - Throws: ``SessionsRefusal`` for a name that names more than one
    ///   session, and each error of the directory.
    private func address(ofName name: String, lookupFolder: URL?) async throws -> SessionAddress {
        guard let summary = try await session(named: name, lookupFolder: lookupFolder) else {
            return .agent(id: name, folder: lookupFolder)
        }
        return .session(summary.id)
    }

    /// The target of a text with no `@`: only a short id names a session
    /// with no `@`.
    ///
    /// - Parameters:
    ///   - shortID: The text, with no space around it.
    ///   - written: The address as written, for the corrective.
    ///   - lookupFolder: The folder in which the lookup looks first.
    /// - Returns: The session.
    /// - Throws: ``SessionsRefusal`` for a short id of more than one session,
    ///   and for a text that is the short id of no session; each error of the
    ///   directory.
    private func address(
        ofShortID shortID: String, written: String, lookupFolder: URL?
    ) async throws -> SessionAddress {
        switch try await shortIDResolution(of: shortID, lookupFolder: lookupFolder) {
        case .session(let summary):
            return .session(summary.id)
        case .ambiguous(let matches):
            throw Self.ambiguity(of: shortID, among: matches, outcome: SessionsToolText.notSentSentence)
        case .none:
            throw SessionsRefusal(.invalidAddress, SessionsToolText.notAnAddress(written))
        }
    }

    /// The resolution of a text with no `@`, in which only a short id names a
    /// session: a match by the slug alone is no match.
    ///
    /// - Parameters:
    ///   - text: The text, with any space around it.
    ///   - lookupFolder: The folder in which the lookup looks first, or
    ///     `nil`.
    /// - Returns: The resolution.
    /// - Throws: Each error of the directory.
    private func shortIDResolution(of text: String, lookupFolder: URL?) async throws -> SessionReferenceResolution {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch try await resolution(of: text, lookupFolder: lookupFolder) {
        case .session(let summary) where summary.shortID == key:
            return .session(summary)
        case .ambiguous(let matches) where matches.allSatisfy({ $0.shortID == key }):
            return .ambiguous(matches)
        case .session, .ambiguous, .none:
            return .none
        }
    }

    /// The refusal of a reference that names more than one session: the call
    /// does nothing, and the corrective lists each match.
    ///
    /// - Parameters:
    ///   - reference: The reference, as written.
    ///   - matches: The sessions that match.
    ///   - outcome: The sentence that tells what the call did not do.
    /// - Returns: The refusal.
    private static func ambiguity(
        of reference: String, among matches: [SessionSummary], outcome: String
    ) -> SessionsRefusal {
        SessionsRefusal(
            .ambiguousReference, SessionsToolText.ambiguousReference(reference, matches: matches, outcome: outcome))
    }
}
