// `SessionsToolInput` — reads the text arguments of the `sessions` tool into
// the values of the directory.
//
// Each reader is forgiving where the intent is clear: a session id in any
// letter case, a kind or a state in any letter case, a list limit out of
// range brought into range, an agent written as `@agent`, a tag written as
// `#tag`, and space around a text. An argument with no clear intent throws a
// ``SessionsToolInputError``, and the operation answers its corrective text.

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
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = ULID(ulidString: trimmed.uppercased()) else {
            throw SessionsToolInputError(correctiveText: SessionsToolText.notASessionID(text))
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
    /// - Parameter text: An agent id, with any space around it, also in the
    ///   `@agent` form of a message address.
    /// - Returns: The id, or `nil` for the default of the launcher.
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

    /// The limit of one `list sessions` call: `requested` brought into
    /// `1...maximumListLimit`, or ``SessionQuery/defaultLimit`` for no limit.
    ///
    /// - Parameter requested: The limit of the call, or `nil`.
    /// - Returns: The limit.
    static func listLimit(_ requested: Int?) -> Int {
        min(max(requested ?? SessionQuery.defaultLimit, 1), maximumListLimit)
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
