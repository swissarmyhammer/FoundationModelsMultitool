// `SessionsToolInput` — reads the text arguments of the `sessions` tool into
// the values of the directory.
//
// Each reader is forgiving where the intent is clear: a session id in any
// letter case, a kind or a state in any letter case, a list limit out of
// range brought into range, an agent written as `@agent` (in its own letter
// case, as an agent id is a folder name), a tag written as `#tag`, a message
// address in each form of session.md section 9, a message id in any letter
// case, and space around a text. An argument with no clear intent throws a
// ``SessionsToolInputError``, and the operation answers its corrective
// text.

import Foundation
import FoundationModelsExtras
import ULID

/// An argument of the `sessions` tool that the tool cannot read. The
/// operation catches it and answers ``correctiveText``; it never leaves the
/// tool.
struct SessionsToolInputError: Error {
    /// The corrective text that the model reads.
    let correctiveText: String
}

/// The readers of the text arguments of the `sessions` tool.
enum SessionsToolInput {
    /// The most sessions that one `list sessions` call gives.
    static let maximumListLimit = 100

    /// The first character of an absolute path.
    private static let rootPrefix = "/"

    /// The first character of a path under the home folder.
    private static let homePrefix = "~"

    /// The first character of an agent in a message address: `@agent`.
    private static let agentPrefix = "@"

    /// The first character of a tag in a message address: `#tag`.
    private static let tagPrefix = "#"

    /// The character between the agent and the folder of an agent address:
    /// `@agent:/path`.
    private static let folderSeparator: Character = ":"

    /// The session id of `text`, or `nil` for no text.
    ///
    /// - Parameter text: A session id, in any letter case, with any space
    ///   around it.
    /// - Returns: The id, or `nil` when `text` is `nil`.
    /// - Throws: ``SessionsToolInputError`` when `text` is not a ULID.
    static func sessionID(_ text: String?) throws(SessionsToolInputError) -> ULID? {
        guard let text else {
            return nil
        }
        return try sessionID(text)
    }

    /// The session id of `text`, or `caller` for no text.
    ///
    /// - Parameters:
    ///   - text: A session id, in any letter case, or `nil`.
    ///   - caller: The caller session, the session of a call with no id.
    /// - Returns: The id.
    /// - Throws: ``SessionsToolInputError`` when `text` is not a ULID.
    static func sessionID(_ text: String?, defaultingTo caller: ULID) throws(SessionsToolInputError) -> ULID {
        try sessionID(text) ?? caller
    }

    /// The session id of `text`.
    ///
    /// - Parameter text: A session id, in any letter case, with any space
    ///   around it.
    /// - Returns: The id.
    /// - Throws: ``SessionsToolInputError`` when `text` is not a ULID. The
    ///   text names `listSessions`.
    static func sessionID(_ text: String) throws(SessionsToolInputError) -> ULID {
        try requiredULID(text, corrective: SessionsToolText.notASessionID)
    }

    /// The message id of `text`.
    ///
    /// - Parameter text: A message id, in any letter case, with any space
    ///   around it.
    /// - Returns: The id.
    /// - Throws: ``SessionsToolInputError`` when `text` is not a ULID. The
    ///   text names `readInbox`.
    static func messageID(_ text: String) throws(SessionsToolInputError) -> MailID {
        MailID(try requiredULID(text, corrective: SessionsToolText.notAMessageID))
    }

    /// The target of a message that `text` names (session.md section 9).
    ///
    /// The reader reads the form of the text: a ULID, in any letter case, is a
    /// session; `@agent` and `@agent:/path` are an agent, in its own letter
    /// case, and in a folder when the text gives one; a path that starts with
    /// `/` or `~` is a folder; and `#tag` is a tag. In `@agent:/path` the last
    /// `:` before a `/` or a `~` starts the folder, thus a `folder:` agent id
    /// with a folder of its own stays whole.
    ///
    /// - Parameter text: The address, with any space around it.
    /// - Returns: The address.
    /// - Throws: ``SessionsToolInputError`` for a text in no form, which names
    ///   each form.
    static func address(_ text: String) throws(SessionsToolInputError) -> SessionAddress {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = ulid(trimmed) {
            return .session(id)
        }
        if isPath(trimmed), let folder = try folder(trimmed) {
            return .folder(folder)
        }
        if trimmed.hasPrefix(tagPrefix), let tag = nonBlank(bare(trimmed, prefix: tagPrefix)) {
            return .tag(tag)
        }
        if trimmed.hasPrefix(agentPrefix), let agent = try agentAddress(bare(trimmed, prefix: agentPrefix)) {
            return agent
        }
        throw SessionsToolInputError(correctiveText: SessionsToolText.notAnAddress(text))
    }

    /// The agent address of the text after the `@` of an address.
    ///
    /// - Parameter text: `agent` or `agent:/path`.
    /// - Returns: The address, or `nil` when the text names no agent.
    /// - Throws: ``SessionsToolInputError`` from ``folder(_:)``.
    private static func agentAddress(_ text: String) throws(SessionsToolInputError) -> SessionAddress? {
        let separator = text.indices.last { index in
            text[index] == folderSeparator && isPath(String(text[text.index(after: index)...]))
        }
        guard let separator else {
            return nonBlank(text).map { .agent(id: $0, folder: nil) }
        }
        let folder = try folder(String(text[text.index(after: separator)...]))
        return nonBlank(String(text[..<separator])).map { .agent(id: $0, folder: folder) }
    }

    /// Whether `text` is an absolute path or a path under the home folder.
    ///
    /// - Parameter text: The text, with no space around it.
    /// - Returns: True when `text` starts with `/` or `~`.
    private static func isPath(_ text: String) -> Bool {
        text.hasPrefix(rootPrefix) || text.hasPrefix(homePrefix)
    }

    /// The ULID of `text`, in any letter case, with any space around it.
    ///
    /// - Parameter text: The text.
    /// - Returns: The ULID, or `nil` when `text` is not a ULID.
    private static func ulid(_ text: String) -> ULID? {
        ULID(ulidString: text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
    }

    /// The ULID of `text`, as ``ulid(_:)`` reads it, which the text must hold.
    ///
    /// - Parameters:
    ///   - text: The text of an id argument.
    ///   - corrective: The corrective for a text that is not a ULID, given the
    ///     text as written.
    /// - Returns: The ULID.
    /// - Throws: ``SessionsToolInputError`` with the text of `corrective` when
    ///   `text` is not a ULID.
    private static func requiredULID(
        _ text: String, corrective: (String) -> String
    ) throws(SessionsToolInputError) -> ULID {
        guard let id = ulid(text) else {
            throw SessionsToolInputError(correctiveText: corrective(text))
        }
        return id
    }

    /// The working folder of `path`, or `nil` for no path.
    ///
    /// - Parameter path: An absolute path, or a path that starts with `~`.
    /// - Returns: The folder, or `nil` when `path` is `nil`.
    /// - Throws: ``SessionsToolInputError`` for a relative path.
    static func folder(_ path: String?) throws(SessionsToolInputError) -> URL? {
        guard let path else {
            return nil
        }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let expanded = trimmed.hasPrefix(homePrefix) ? NSString(string: trimmed).expandingTildeInPath : trimmed
        guard expanded.hasPrefix(rootPrefix) else {
            throw SessionsToolInputError(correctiveText: SessionsToolText.relativeFolder(path))
        }
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }

    /// The session kind of `text`, or `nil` for no text.
    ///
    /// - Parameter text: A kind, in any letter case.
    /// - Returns: The kind, or `nil` when `text` is `nil`.
    /// - Throws: ``SessionsToolInputError`` for a text that names no kind.
    static func kind(_ text: String?) throws(SessionsToolInputError) -> SessionKind? {
        try value(of: text, among: SessionKind.allCases, parameter: SessionsToolText.kindParameter)
    }

    /// The work state of `text`, or `nil` for no text.
    ///
    /// - Parameter text: A state, in any letter case.
    /// - Returns: The state, or `nil` when `text` is `nil`.
    /// - Throws: ``SessionsToolInputError`` for a text that names no state.
    static func state(_ text: String?) throws(SessionsToolInputError) -> SessionState? {
        try value(of: text, among: SessionState.allCases, parameter: SessionsToolText.stateParameter)
    }

    /// The agent id of `text`, or `nil` for no text or a blank text.
    ///
    /// An agent id is the folder name of the agent (`AgentDefinition.id` in
    /// FoundationModelsAgents), so its letter case is part of the id: the
    /// reader keeps the case as written and never folds it. The session
    /// directory resolves the id as given, or refuses it with
    /// `SessionDirectoryError.unknownAgent` and the near names, which the
    /// operation answers as a corrective. An agent registered as `Coder`
    /// starts from `Coder` or `@Coder`, and `coder` gets the corrective that
    /// names `Coder`.
    ///
    /// - Parameter text: An agent id, with any space around it, also in the
    ///   `@agent` form of a message address.
    /// - Returns: The id in its own letter case, or `nil` for the default of
    ///   the launcher.
    static func agentID(_ text: String?) -> String? {
        nonBlank(text.map { bare($0, prefix: agentPrefix) })
    }

    /// The tags of `texts`, each with no space around it and no `#`. A blank
    /// text gives no tag.
    ///
    /// - Parameter texts: The tags, or `nil` for none.
    /// - Returns: The tags, maybe none.
    static func tagSet(_ texts: [String]?) -> Set<String> {
        Set((texts ?? []).compactMap { nonBlank(bare($0, prefix: tagPrefix)) })
    }

    /// The tags of `texts`, as ``tagSet(_:)`` reads them, at least one.
    ///
    /// - Parameter texts: The tags.
    /// - Returns: The tags.
    /// - Throws: ``SessionsToolInputError`` when no text is a tag.
    static func tags(_ texts: [String]) throws(SessionsToolInputError) -> Set<String> {
        let tags = tagSet(texts)
        guard !tags.isEmpty else {
            throw SessionsToolInputError(correctiveText: SessionsToolText.noTags)
        }
        return tags
    }

    /// `text` with no space around it, which must hold more than space.
    ///
    /// - Parameters:
    ///   - text: The text of the argument.
    ///   - parameter: The name of the argument, for the corrective.
    /// - Returns: The text with no space around it.
    /// - Throws: ``SessionsToolInputError`` for a text that holds only space.
    static func requiredText(_ text: String, parameter: String) throws(SessionsToolInputError) -> String {
        guard let value = nonBlank(text) else {
            throw SessionsToolInputError(correctiveText: SessionsToolText.blankText(parameter))
        }
        return value
    }

    /// `text` with no space around it, or `nil` for no text or a text that
    /// holds only space.
    ///
    /// - Parameter text: The text, or `nil`.
    /// - Returns: The text, or `nil`.
    static func nonBlank(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    /// `text` with no space around it and no leading `prefix`.
    ///
    /// - Parameters:
    ///   - text: The text.
    ///   - prefix: The prefix to remove, when the text starts with it.
    /// - Returns: The bare text.
    private static func bare(_ text: String, prefix: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix(prefix) ? String(trimmed.dropFirst(prefix.count)) : trimmed
    }

    /// The limit of one listing: `requested` brought into
    /// `1...maximumListLimit`, or `fallback` for no limit.
    ///
    /// - Parameters:
    ///   - requested: The limit of the call, or `nil`.
    ///   - fallback: The limit of a call that names none.
    /// - Returns: The limit.
    static func listLimit(_ requested: Int?, defaultingTo fallback: Int) -> Int {
        min(max(requested ?? fallback, 1), maximumListLimit)
    }

    /// The directory query of one listing, with the rules that `list
    /// sessions` and the `sessions` query of the endpoint share: a `state` of
    /// `archived` also finds the sessions that are not live, because an
    /// archived session is never live, and the limit is brought into range.
    ///
    /// - Parameters:
    ///   - filter: The filter of the call; its `includesRecorded` and its
    ///     `limit` are not read.
    ///   - includeRecorded: True to also find the sessions that are not live,
    ///     or `nil` for the default, `false`.
    ///   - limit: The limit of the call, or `nil`.
    ///   - fallback: The limit of a call that names none.
    /// - Returns: The query.
    static func listQuery(
        _ filter: SessionQuery, includeRecorded: Bool?, limit: Int?, defaultingTo fallback: Int
    ) -> SessionQuery {
        var query = filter
        query.includesRecorded = (includeRecorded ?? false) || filter.state == .archived
        query.limit = listLimit(limit, defaultingTo: fallback)
        return query
    }

    /// The case of `values` whose raw value is `text`, in any letter case.
    ///
    /// - Parameters:
    ///   - text: The text of the argument, or `nil`.
    ///   - values: Each case of the type.
    ///   - parameter: The name of the argument, for the corrective.
    /// - Returns: The case, or `nil` when `text` is `nil`.
    /// - Throws: ``SessionsToolInputError`` for a text that names no case.
    private static func value<Value: RawRepresentable>(
        of text: String?, among values: [Value], parameter: String
    ) throws(SessionsToolInputError) -> Value? where Value.RawValue == String {
        guard let text else {
            return nil
        }
        let wanted = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let match = values.first(where: { $0.rawValue.lowercased() == wanted }) else {
            throw SessionsToolInputError(
                correctiveText: SessionsToolText.unknownValue(text, parameter: parameter, allowed: values.map(\.rawValue)))
        }
        return match
    }
}
