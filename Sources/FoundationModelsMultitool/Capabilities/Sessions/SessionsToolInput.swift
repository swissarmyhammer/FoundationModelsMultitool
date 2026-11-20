// `SessionsToolInput` — reads the text arguments of the `sessions` tool into
// the values of the directory.
//
// Each reader is forgiving where the intent is clear: a session id in any
// letter case, a kind or a state in any letter case, a list limit out of
// range brought into range, an agent written as `@agent` (in its own letter
// case, as an agent id is a folder name), a tag written as `#tag`, a message
// address in each form of session.md section 9, a message id in any letter
// case, and space around a text. An argument with no clear intent throws a
// ``SessionsRefusal``: the operation answers its corrective text, and the
// `sessions` endpoint gives it as a coded error.

import Foundation
import FoundationModelsExtras
import ULID

/// The form of a message address, before the directory resolves it.
enum SessionsAddressForm: Sendable, Equatable {
    /// `#tag`: each live session with the tag.
    case tag(String)

    /// A full session id, with or without `@`.
    case id(ULID)

    /// A short id or a slug after `@`, or the name of an agent when no
    /// session has it.
    case name(String)

    /// A text with no `@`: it can name a session only by its short id.
    case shortID(String)
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

    /// The session id of `text`, or `nil` for no text.
    ///
    /// - Parameter text: A session id, in any letter case, with any space
    ///   around it.
    /// - Returns: The id, or `nil` when `text` is `nil`.
    /// - Throws: ``SessionsRefusal`` when `text` is not a ULID.
    static func sessionID(_ text: String?) throws(SessionsRefusal) -> ULID? {
        guard let text else {
            return nil
        }
        return try sessionID(text)
    }

    /// The session id of `text`.
    ///
    /// - Parameter text: A session id, in any letter case, with any space
    ///   around it.
    /// - Returns: The id.
    /// - Throws: ``SessionsRefusal`` when `text` is not a ULID. The text
    ///   names `listSessions`.
    static func sessionID(_ text: String) throws(SessionsRefusal) -> ULID {
        try requiredULID(text, kind: .invalidSessionID, corrective: SessionsToolText.notAFullSessionID)
    }

    /// The session id of a reference that is a full session id, with or
    /// without `@` (D199 (c), D200 (e)).
    ///
    /// - Parameter text: The reference, with any space around it.
    /// - Returns: The id, or `nil` when the reference is not a full id.
    static func fullSessionID(_ text: String) -> ULID? {
        ulid(bare(text, prefix: agentPrefix))
    }

    /// Whether a reference starts with `@`. Only such a reference can name a
    /// session by its slug: a text with no `@` names a session only by its
    /// id or its short id.
    ///
    /// - Parameter text: The reference, with any space around it.
    /// - Returns: True when the text starts with `@`.
    static func isAtReference(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(agentPrefix)
    }

    /// The message id of `text`.
    ///
    /// - Parameter text: A message id, in any letter case, with any space
    ///   around it.
    /// - Returns: The id.
    /// - Throws: ``SessionsRefusal`` when `text` is not a ULID. The text
    ///   names `readInbox`.
    static func messageID(_ text: String) throws(SessionsRefusal) -> MailID {
        MailID(try requiredULID(text, kind: .invalidMessageID, corrective: SessionsToolText.notAMessageID))
    }

    /// The form of a message address, as the text gives it (D199 (c), (e)).
    ///
    /// The reader reads the form only, and does not read the directory:
    /// `#tag` is a tag; a ULID in any letter case, with or without `@`, is a
    /// session id; another text after `@` is a short id or a slug; and a text
    /// with no `@` is a short id. A target is only an id, a short id or a
    /// slug (D199 (e)): a folder path reads as a short id, which names no
    /// session. ``SessionsVisibility/messageAddress(_:from:sourceFolder:)``
    /// then resolves the references.
    ///
    /// - Parameter text: The address, with any space around it.
    /// - Returns: The form.
    /// - Throws: ``SessionsRefusal`` for a text in no form, which names each
    ///   form.
    static func addressForm(_ text: String) throws(SessionsRefusal) -> SessionsAddressForm {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(tagPrefix), let tag = nonBlank(bare(trimmed, prefix: tagPrefix)) {
            return .tag(tag)
        }
        if let form = referenceForm(trimmed) {
            return form
        }
        throw SessionsRefusal(.invalidAddress, SessionsToolText.notAnAddress(text))
    }

    /// The form of an address that is not a tag: a session id, a name after
    /// `@`, or a short id with no `@`.
    ///
    /// - Parameter text: The address, with no space around it.
    /// - Returns: The form, or `nil` when the text names nothing.
    private static func referenceForm(_ text: String) -> SessionsAddressForm? {
        if let id = fullSessionID(text) {
            return .id(id)
        }
        guard text.hasPrefix(agentPrefix) else {
            return nonBlank(text).map { .shortID($0) }
        }
        return nonBlank(bare(text, prefix: agentPrefix)).map { .name($0) }
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
    ///   - kind: The kind of the refusal of a text that is not a ULID.
    ///   - corrective: The corrective for a text that is not a ULID, given the
    ///     text as written.
    /// - Returns: The ULID.
    /// - Throws: ``SessionsRefusal`` of `kind`, with the text of `corrective`,
    ///   when `text` is not a ULID.
    static func requiredULID(
        _ text: String, kind: SessionsRefusal.Kind, corrective: (String) -> String
    ) throws(SessionsRefusal) -> ULID {
        guard let id = ulid(text) else {
            throw SessionsRefusal(kind, corrective(text))
        }
        return id
    }

    /// The working folder of `path`, or `nil` for no path.
    ///
    /// - Parameter path: An absolute path, or a path that starts with `~`.
    /// - Returns: The folder, or `nil` when `path` is `nil`.
    /// - Throws: ``SessionsRefusal`` for a relative path.
    static func folder(_ path: String?) throws(SessionsRefusal) -> URL? {
        guard let path else {
            return nil
        }
        return try absoluteFolder(path)
    }

    /// The working folder of `path`.
    ///
    /// - Parameter path: An absolute path, or a path that starts with `~`.
    /// - Returns: The folder.
    /// - Throws: ``SessionsRefusal`` for a relative path.
    static func absoluteFolder(_ path: String) throws(SessionsRefusal) -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let expanded = trimmed.hasPrefix(homePrefix) ? NSString(string: trimmed).expandingTildeInPath : trimmed
        guard expanded.hasPrefix(rootPrefix) else {
            throw SessionsRefusal(.invalidFolder, SessionsToolText.relativeFolder(path))
        }
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }

    /// The file of an export: `path` in `folder`, or `defaultName` in
    /// `folder` for no path or a blank path (D202 (g)).
    ///
    /// The reader reads the path as text and does not touch the disk. It
    /// removes each `.` and `..` part, so a path such as `notes/../a.md`
    /// stays in the folder.
    ///
    /// - Parameters:
    ///   - path: A file name or a relative path, or `nil`.
    ///   - folder: The session folder.
    ///   - defaultName: The file name of a call with no path.
    /// - Returns: The file, in `folder` or in a folder under it.
    /// - Throws: ``SessionsRefusal`` for an absolute path, a path that starts
    ///   with `~`, and a path that goes out of `folder` or names `folder`
    ///   itself.
    static func exportFile(_ path: String?, in folder: URL, defaultName: String) throws(SessionsRefusal) -> URL {
        let relative = nonBlank(path) ?? defaultName
        let base = folder.standardizedFileURL
        let file = base.appendingPathComponent(relative).standardizedFileURL
        guard !relative.hasPrefix(rootPrefix), !relative.hasPrefix(homePrefix),
            file.pathComponents.count > base.pathComponents.count,
            file.pathComponents.starts(with: base.pathComponents)
        else {
            throw SessionsRefusal(.invalidPath, SessionsToolText.pathOutOfFolder(relative, folder: base))
        }
        return file
    }

    /// The format of an export, or ``SessionExportFormat/markdown`` for no
    /// text.
    ///
    /// - Parameter text: A format, in any letter case.
    /// - Returns: The format.
    /// - Throws: ``SessionsRefusal`` for a text that names no format. Its
    ///   corrective names each format.
    static func exportFormat(_ text: String?) throws(SessionsRefusal) -> SessionExportFormat {
        try value(of: text, among: SessionExportFormat.allCases, parameter: SessionsToolText.formatParameter)
            ?? .markdown
    }

    /// The session kind of `text`, or `nil` for no text.
    ///
    /// - Parameter text: A kind, in any letter case.
    /// - Returns: The kind, or `nil` when `text` is `nil`.
    /// - Throws: ``SessionsRefusal`` for a text that names no kind.
    static func kind(_ text: String?) throws(SessionsRefusal) -> SessionKind? {
        try value(of: text, among: SessionKind.allCases, parameter: SessionsToolText.kindParameter)
    }

    /// The work state of `text`, or `nil` for no text.
    ///
    /// - Parameter text: A state, in any letter case.
    /// - Returns: The state, or `nil` when `text` is `nil`.
    /// - Throws: ``SessionsRefusal`` for a text that names no state.
    static func state(_ text: String?) throws(SessionsRefusal) -> SessionState? {
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
    /// - Throws: ``SessionsRefusal`` when no text is a tag.
    static func tags(_ texts: [String]) throws(SessionsRefusal) -> Set<String> {
        let tags = tagSet(texts)
        guard !tags.isEmpty else {
            throw SessionsRefusal(.missingTags, SessionsToolText.noTags)
        }
        return tags
    }

    /// `text` with no space around it, which must hold more than space.
    ///
    /// - Parameters:
    ///   - text: The text of the argument.
    ///   - parameter: The name of the argument, for the corrective.
    /// - Returns: The text with no space around it.
    /// - Throws: ``SessionsRefusal`` for a text that holds only space.
    static func requiredText(_ text: String, parameter: String) throws(SessionsRefusal) -> String {
        guard let value = nonBlank(text) else {
            throw SessionsRefusal(.blankText, SessionsToolText.blankText(parameter))
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
    /// - Throws: ``SessionsRefusal`` for a text that names no case.
    private static func value<Value: RawRepresentable>(
        of text: String?, among values: [Value], parameter: String
    ) throws(SessionsRefusal) -> Value? where Value.RawValue == String {
        guard let text else {
            return nil
        }
        let wanted = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let match = values.first(where: { $0.rawValue.lowercased() == wanted }) else {
            throw SessionsRefusal(
                .invalidValue,
                SessionsToolText.unknownValue(text, parameter: parameter, allowed: values.map(\.rawValue)))
        }
        return match
    }
}
