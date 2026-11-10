import Foundation
import os

/// The errors the `tools.*` calls of one `runCode` invocation returned as
/// values, and the section a failed snippet shows them in.
///
/// **The gap this closes.** A tool can answer with an error and not throw: a
/// GraphQL endpoint answers `{"errors":[...]}` with no `data`. The snippet
/// then reads `r.data.addTask`, and the failure the model sees is only
/// "undefined is not an object (evaluating 'r.data.addTask')". The real
/// cause never reaches it (planner24 django__django-14411 seq 21873, where
/// the error was `Variable "$col" of type "String!" used in position
/// expecting type "ID"`). This record keeps those errors, so the failure text
/// can name them.
///
/// A successful snippet never shows them: it returns what it returns.
///
/// A reference type guarded by `OSAllocatedUnfairLock`, for the reason
/// ``ToolReturnLedger`` gives.
final class ToolErrorRecord: Sendable {

    /// The most errors the section names. A snippet that collected more is
    /// told how many it left out.
    static let maximumShownErrors = 5

    /// The longest error message the section carries, in characters.
    static let maximumMessageLength = 300

    /// The sentence the section opens with.
    static let sectionLead = "A tool call in this snippet returned errors:"

    /// Each error recorded, as `tools.<path>: [CODE] message`, oldest first.
    private let errors = OSAllocatedUnfairLock(initialState: [String]())

    /// Records the errors one call returned, if it returned any.
    ///
    /// - Parameters:
    ///   - value: What the call returned: an object, or the JSON text of one.
    ///   - path: The path the snippet called it by, without `tools.`.
    func record(_ value: InterpreterValue, from path: String) {
        let found = Self.errorMessages(in: value)
        guard !found.isEmpty else { return }
        errors.withLock { $0.append(contentsOf: found.map { "tools.\(path): \($0)" }) }
    }

    /// The section a failed snippet shows, or `nil` when no call returned an
    /// error.
    var section: String? {
        let all = errors.withLock { $0 }
        guard !all.isEmpty else { return nil }
        let shown = all.prefix(Self.maximumShownErrors).joined(separator: "; ")
        let more = all.count > Self.maximumShownErrors
            ? " (and \(all.count - Self.maximumShownErrors) more)" : ""
        return "\(Self.sectionLead) \(shown)\(more)."
    }

    // MARK: - Reading an error out of a value

    /// The error messages one returned value carries.
    ///
    /// The shapes read: a non-empty `errors` list (GraphQL), an `error` text
    /// or object, `isError: true` with MCP `content` text, and a `correction`
    /// text (the in-band refusal of this package's own verbs). JSON text of an
    /// object is read as that object.
    static func errorMessages(in value: InterpreterValue) -> [String] {
        guard case .object(let fields) = parsedObject(value) else { return [] }
        var found: [String] = []
        if case .array(let list)? = fields["errors"] {
            found += list.map(message(of:))
        }
        if let error = fields["error"], error != .null, error != .bool(false) {
            found.append(message(of: error))
        }
        if fields["isError"] == .bool(true) {
            found.append(contentText(fields["content"]) ?? "the call reported an error")
        }
        if case .string(let correction)? = fields["correction"], !correction.isEmpty {
            found.append(capped(correction))
        }
        return found
    }

    /// `value` as an object: itself, or the object its JSON text holds.
    private static func parsedObject(_ value: InterpreterValue) -> InterpreterValue? {
        switch value {
        case .object:
            return value
        case .string(let text):
            guard text.first == "{", let data = text.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(InterpreterValue.self, from: data)
        default:
            return nil
        }
    }

    /// One error as `[CODE] message`, or as its message alone when it names
    /// no code.
    private static func message(of error: InterpreterValue) -> String {
        guard case .object(let fields) = error else {
            if case .string(let text) = error { return capped(text) }
            return capped(ResultRenderer.serialize(error))
        }
        var code: InterpreterValue? = fields["code"]
        if code == nil, case .object(let extensions)? = fields["extensions"] { code = extensions["code"] }
        let prefix: String
        switch code {
        case .string(let text)?: prefix = "[\(text)] "
        case .number(let number)?: prefix = "[\(Int(number))] "
        default: prefix = ""
        }
        guard case .string(let text)? = fields["message"] else {
            return prefix + capped(ResultRenderer.serialize(error))
        }
        return prefix + capped(text)
    }

    /// The text blocks of an MCP `content` list, joined, or `nil`.
    private static func contentText(_ content: InterpreterValue?) -> String? {
        guard case .array(let blocks)? = content else { return nil }
        let texts = blocks.compactMap { block -> String? in
            guard case .object(let fields) = block, case .string(let text)? = fields["text"] else { return nil }
            return text
        }
        return texts.isEmpty ? nil : capped(texts.joined(separator: " "))
    }

    /// `text` cut to ``maximumMessageLength`` characters.
    private static func capped(_ text: String) -> String {
        text.count > maximumMessageLength ? String(text.prefix(maximumMessageLength)) + "…" : text
    }
}
