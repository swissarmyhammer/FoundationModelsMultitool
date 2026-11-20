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
// A target is only an id, a short id or a slug (D199 (e)). `#tag` names a
// group of sessions, not one target. A folder path is not an address.
//
// An archived session matches only its full id, with one exception: the `id`
// of `unarchive session` reads a short id and a slug only among the archived
// sessions (D204 (c)). ``SessionsReferenceScope`` tells the reader which
// sessions a short id and a slug look at.

import Foundation
import FoundationModelsExtras
import ULID

/// The sessions among which a short id and a slug of a session reference
/// look (D199 (d), D204 (c)). A full id names its session in each scope.
enum SessionsReferenceScope: Sendable {
    /// The sessions that are not archived: the rule of `send message` and of
    /// each session operation but `unarchive session`.
    case unarchived

    /// Only the archived sessions: the rule of `unarchive session`.
    case archived

    /// The directory query of the candidates of the scope: each session that
    /// the directory holds, the recorded sessions too.
    var query: SessionQuery {
        switch self {
        case .unarchived:
            SessionQuery(includesRecorded: true, limit: SessionsVisibility.unboundedLimit)
        case .archived:
            SessionQuery(state: .archived, includesRecorded: true, limit: SessionsVisibility.unboundedLimit)
        }
    }

    /// Resolves a reference among the candidates of the scope, with
    /// `SessionReference.resolve` of Extras.
    ///
    /// `SessionReference.resolve` never matches an archived session. For the
    /// archived scope, the reader thus gives it each candidate with the state
    /// `idle`, and then gives each match as the directory gave it. Thus the
    /// order of the lookup (the id, the short id, then the slug; the lookup
    /// folder, then all the sessions) is the same in each scope.
    ///
    /// - Parameters:
    ///   - reference: The reference, as written.
    ///   - lookupFolder: The folder in which a short id or a slug looks
    ///     first, or `nil`.
    ///   - candidates: The sessions of the scope that the viewer can see.
    /// - Returns: The resolution.
    func resolve(
        _ reference: String, lookupFolder: URL?, among candidates: [SessionSummary]
    ) -> SessionReferenceResolution {
        switch self {
        case .unarchived:
            return SessionReference.resolve(reference, sourceFolder: lookupFolder, among: candidates)
        case .archived:
            let matchable = candidates.map { candidate in
                var matchable = candidate
                matchable.state = .idle
                return matchable
            }
            let resolution = SessionReference.resolve(reference, sourceFolder: lookupFolder, among: matchable)
            return Self.resolution(resolution, restoring: candidates)
        }
    }

    /// The corrective of a reference that names no session of the scope.
    ///
    /// - Parameter text: The reference, as written.
    /// - Returns: The corrective.
    func noMatch(_ text: String) -> String {
        switch self {
        case .unarchived: SessionsToolText.notASessionID(text)
        case .archived: SessionsToolText.notAnArchivedSession(text)
        }
    }

    /// A resolution with each match replaced by the candidate that has its
    /// id.
    ///
    /// - Parameters:
    ///   - resolution: The resolution over the changed candidates.
    ///   - candidates: The candidates as the directory gave them.
    /// - Returns: The resolution over `candidates`.
    private static func resolution(
        _ resolution: SessionReferenceResolution, restoring candidates: [SessionSummary]
    ) -> SessionReferenceResolution {
        let byID = Dictionary(candidates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let restore = { (match: SessionSummary) in byID[match.id, default: match] }
        switch resolution {
        case .session(let match):
            return .session(restore(match))
        case .ambiguous(let matches):
            return .ambiguous(matches.map(restore))
        case .none:
            return .none
        }
    }
}

extension SessionsVisibility {
    /// Reads a message address from `sender` (D199 (c) to (e)).
    ///
    /// The lookup folder of a short id and of a slug is `sourceFolder`, else
    /// the working folder of the sending session. A sender that is the user,
    /// with no source folder, has no lookup folder: the lookup is in all the
    /// sessions that the viewer can see.
    ///
    /// - Parameters:
    ///   - text: The address, with any space around it.
    ///   - sender: The session or the user that sends the message.
    ///   - sourceFolder: The working folder of the session in which the user
    ///     wrote the message (D199 (f)), or `nil`. The default is `nil`.
    /// - Returns: The target.
    /// - Throws: ``SessionsRefusal`` for a text in no form and for a
    ///   reference that names more than one session; each error of the
    ///   directory.
    func messageAddress(
        _ text: String, from sender: SessionMessageSender, sourceFolder: URL? = nil
    ) async throws -> SessionAddress {
        switch try SessionsToolInput.addressForm(text) {
        case .tag(let tag):
            return .tag(tag)
        case .id(let id):
            return .session(id)
        case .name(let name):
            let lookupFolder = try await lookupFolder(of: sender, sourceFolder: sourceFolder)
            return try await address(ofName: name, lookupFolder: lookupFolder)
        case .shortID(let shortID):
            let lookupFolder = try await lookupFolder(of: sender, sourceFolder: sourceFolder)
            return try await address(ofShortID: shortID, written: text, lookupFolder: lookupFolder)
        }
    }

    /// The session id that the `id` of a session operation names (D200 (e)):
    /// `<id>`, `@<id>`, `<short id>`, `@<short id>` or `@<slug>`.
    ///
    /// A full id gives its id at once, thus an archived session, which the
    /// resolver never matches, is still found by its id. A short id and a
    /// slug go through the resolver of `send message`, over the sessions of
    /// `scope` that the viewer can see. A text with no `@` names a session
    /// only by its short id. The reader never starts an agent.
    ///
    /// - Parameters:
    ///   - text: The `id` as written.
    ///   - lookupFolder: The folder in which a short id or a slug looks
    ///     first, or `nil` to look in all the sessions at once.
    ///   - scope: The sessions that a short id and a slug look at. The
    ///     default is the sessions that are not archived.
    ///   - outcome: The sentence of the ambiguous corrective that tells what
    ///     the call did not do. The default is
    ///     ``SessionsToolText/notChangedSentence``.
    /// - Returns: The session id.
    /// - Throws: ``SessionsRefusal`` for a reference that names more than one
    ///   session, and for a reference that names no session of `scope` that
    ///   the viewer can see; each error of the directory.
    func sessionID(
        referencedBy text: String, lookupFolder: URL?, scope: SessionsReferenceScope = .unarchived,
        outcome: String = SessionsToolText.notChangedSentence
    ) async throws -> ULID {
        if let id = SessionsToolInput.fullSessionID(text) {
            return id
        }
        let resolution =
            SessionsToolInput.isAtReference(text)
            ? try await resolution(of: text, lookupFolder: lookupFolder, scope: scope)
            : try await shortIDResolution(of: text, lookupFolder: lookupFolder, scope: scope)
        switch resolution {
        case .session(let summary):
            return summary.id
        case .ambiguous(let matches):
            throw Self.ambiguity(of: text, among: matches, outcome: outcome)
        case .none:
            throw SessionsRefusal(.invalidSessionID, scope.noMatch(text))
        }
    }

    /// The session id that the `id` of a session operation names, with the
    /// working folder of the caller as the lookup folder (D200 (e)).
    ///
    /// - Parameters:
    ///   - text: The `id` as written.
    ///   - callerID: The caller session, or `nil` for a call with no caller
    ///     session: the lookup is then in all the sessions at once.
    ///   - scope: The sessions that a short id and a slug look at. The
    ///     default is the sessions that are not archived.
    /// - Returns: The session id.
    /// - Throws: What ``sessionID(referencedBy:lookupFolder:scope:)`` throws.
    func sessionID(
        referencedBy text: String, callerID: ULID?, scope: SessionsReferenceScope = .unarchived
    ) async throws -> ULID {
        guard let callerID else {
            return try await sessionID(referencedBy: text, lookupFolder: nil, scope: scope)
        }
        let lookupFolder = try await workingFolder(of: .session(callerID))
        return try await sessionID(referencedBy: text, lookupFolder: lookupFolder, scope: scope)
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
    /// session of `scope` that the viewer can see, the recorded sessions too.
    ///
    /// - Parameters:
    ///   - reference: The reference, as written.
    ///   - lookupFolder: The folder in which a short id or a slug looks
    ///     first, or `nil`.
    ///   - scope: The sessions that a short id and a slug look at. The
    ///     default is the sessions that are not archived.
    /// - Returns: The resolution.
    /// - Throws: Each error of the directory.
    func resolution(
        of reference: String, lookupFolder: URL?, scope: SessionsReferenceScope = .unarchived
    ) async throws -> SessionReferenceResolution {
        let candidates = try await sessions(matching: scope.query)
        return scope.resolve(reference, lookupFolder: lookupFolder, among: candidates)
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
    ///   - scope: The sessions that the short id looks at. The default is
    ///     the sessions that are not archived.
    /// - Returns: The resolution.
    /// - Throws: Each error of the directory.
    private func shortIDResolution(
        of text: String, lookupFolder: URL?, scope: SessionsReferenceScope = .unarchived
    ) async throws -> SessionReferenceResolution {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch try await resolution(of: text, lookupFolder: lookupFolder, scope: scope) {
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
