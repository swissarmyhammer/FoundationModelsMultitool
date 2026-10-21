// `SessionsToolInput` — reads the text arguments of the `sessions` tool into
// the values of the directory.
//
// Each reader is forgiving where the intent is clear: a session id in any
// letter case, a kind or a state in any letter case, and a list limit out of
// range brought into range. An argument with no clear intent throws a
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
