// MARK: - The no-op check of a runCode snippet
//
// SWE-bench run no-otel-1011 recorded a model that sent 73 `runCode` calls
// while one `tools.*` call was pending. Each of these snippets called no
// `tools.*` verb (`return null`, `return "end 11"`, ...), and one form
// (`await new Promise(() => {});`) never settles. A host must know that a call
// is a no-op before it runs the call, so the check reads the snippet text and
// never runs it (task `^9pnyvyp`). The check only gives information: the
// Multitool does not block or change a call because of it, with one
// exception: ``isStandbySnippet(_:)`` while other background work runs gets
// ``standbyAnswer(for:)`` (SWE-bench run bench24-1023b).

import Foundation
import FoundationModelsExtras

extension MultiTool {
    /// The identifier through which a snippet reaches every `tools.*` verb,
    /// as UTF-8 bytes. The preamble of each run binds it as
    /// `globalThis.tools`.
    private static let toolsIdentifier = Array("tools".utf8)

    /// The bytes that start a JavaScript `\u` escape. An identifier can hold
    /// one, so a snippet can spell `tools` with no plain `tools` in its text.
    private static let unicodeEscapeOpener = Array("\\u".utf8)

    /// The bytes that continue an ASCII JavaScript identifier. Each other
    /// byte counts as a word boundary. A non-ASCII identifier character
    /// therefore counts as a boundary too, and that only makes the check
    /// return `false` more often.
    private static let identifierPartBytes = Set(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_$".utf8)

    /// Tells if a `runCode` snippet calls no `tools.*` verb.
    ///
    /// The check is static and pure: it reads the snippet text and never runs
    /// the snippet. A host uses it to see a no-op call before the call runs,
    /// for example a call that only returns a placeholder while an earlier
    /// call is pending.
    ///
    /// The result is `true` only when the text holds no whole-word identifier
    /// `tools` and no `\u` escape. A snippet that names `tools` through an
    /// alias (`const t = tools;`) or a computed member (`tools["shell"]`)
    /// thus gives `false`. The check is strict in one direction only: a
    /// no-op snippet that holds the word `tools`, for example in a string or
    /// a comment, gives `false`, and that is safe.
    ///
    /// A static check of the text cannot see a name that the snippet builds
    /// at run time, for example `globalThis["to" + "ols"]`.
    ///
    /// - Parameter snippet: The raw JavaScript text of the call, as
    ///   `RunCodeArguments.snippet` holds it.
    /// - Returns: `true` when the snippet calls no `tools.*` verb.
    public static func callsNoTool(snippet: String) -> Bool {
        let bytes = Array(snippet.utf8)
        guard bytes.firstRange(of: unicodeEscapeOpener) == nil else { return false }
        let matches = bytes.ranges(of: toolsIdentifier)
        return !matches.contains { isWholeIdentifier($0, in: bytes) }
    }

    /// The answer a standby snippet gets while background work of the session
    /// is still going — see ``isStandbySnippet(_:)``.
    ///
    /// SWE-bench run bench24-1023b, django__django-13925: the model knew to
    /// wait for a background command, and waited by sending `return
    /// "standby"` 28 times in two minutes. noqueue24 django__django-14672: an
    /// answer that asked for no text and no tool call was an empty output,
    /// which the model cannot give, and it sent `return "stop"`, `"halt"`,
    /// `"end"` 122 times. This answer says the call did nothing, names each
    /// open call with its completion token, says the results come as
    /// messages, and asks for a plain-text status. The text after the first
    /// sentence is ``PendingRunEnvelope/waitingStatusInstruction(for:)`` of
    /// FoundationModelsExtras, the one owner of that text.
    ///
    /// - Parameter calls: The open background calls of the session.
    /// - Returns: The answer.
    public static func standbyAnswer(for calls: [(description: String, completionToken: String)]) -> String {
        "Nothing ran: this snippet calls no tool. " + PendingRunEnvelope.waitingStatusInstruction(for: calls)
    }

    /// Tells if a `runCode` snippet only stands by: it calls no `tools.*`
    /// verb, and after its comments it is empty, `return;`, or `return` of
    /// one constant — a string with no `${`, a number, `true`, `false`,
    /// `null` or `undefined`.
    ///
    /// Static and pure, as ``callsNoTool(snippet:)`` is. It is strict in one
    /// direction only: a snippet that computes anything (`return 1 + 1`,
    /// `return a`) is not a standby, and runs as before.
    ///
    /// - Parameter snippet: The raw JavaScript text of the call.
    /// - Returns: `true` when the snippet only returns a constant, or nothing.
    public static func isStandbySnippet(_ snippet: String) -> Bool {
        guard callsNoTool(snippet: snippet), let code = withoutComments(snippet) else { return false }
        let body = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let constant =
            #"(?:"(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*'|`(?:[^`\\$]|\\.|\$(?!\{))*`|-?\d+(?:\.\d+)?|true|false|null|undefined)"#
        let pattern = #"^(?:return(?:\s+"# + constant + #")?\s*;?)?$"#
        return body.range(of: pattern, options: .regularExpression) != nil
    }

    /// The background calls of the session of `context` that are open, other
    /// than the run of this `runCode` call itself, each with a short
    /// description and its completion token.
    ///
    /// Each mounted `runCode` call is a background run of its own (see
    /// ``mount``), thus the run of `context` does not count, nor the run that
    /// holds it (`holdingRunToken`) when the call is mounted inside one. A run
    /// is described as its pending envelope described it: the
    /// `callDescription(for:)` of its tool (`execute <command>`), or its op.
    ///
    /// - Parameter context: The session context the call runs under.
    /// - Returns: The other open calls; empty when no other work is going.
    static func otherBackgroundCalls(in context: ToolContext) async -> [(description: String, completionToken: String)] {
        let own: Set = [context.completionToken, context.holdingRunToken]
        return await context.backgroundRuns()
            .filter { !own.contains($0.completionToken) }
            .map { (description: $0.description, completionToken: $0.completionToken) }
    }

    /// `snippet` with each `//` and `/* */` comment taken out, or `nil` when a
    /// string or a comment does not close.
    ///
    /// A comment marker inside a string literal stays, thus `return "a // b"`
    /// keeps its string.
    ///
    /// - Parameter snippet: The raw JavaScript text.
    /// - Returns: The text without comments, or `nil`.
    private static func withoutComments(_ snippet: String) -> String? {
        let characters = Array(snippet)
        var output = ""
        var index = 0
        while index < characters.count {
            let character = characters[index]
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            if character == "/", next == "/" {
                while index < characters.count, characters[index] != "\n" { index += 1 }
            } else if character == "/", next == "*" {
                index += 2
                while index + 1 < characters.count, !(characters[index] == "*" && characters[index + 1] == "/") {
                    index += 1
                }
                guard index + 1 < characters.count else { return nil }
                index += 2
                output.append(" ")
            } else if character == "\"" || character == "'" || character == "`" {
                let start = index
                index += 1
                while index < characters.count, characters[index] != character {
                    index += characters[index] == "\\" ? 2 : 1
                }
                guard index < characters.count else { return nil }
                index += 1
                output.append(contentsOf: characters[start..<index])
            } else {
                output.append(character)
                index += 1
            }
        }
        return output
    }

    /// Tells if the bytes in `range` are a whole identifier: no identifier
    /// byte comes directly before or directly after them.
    ///
    /// - Parameters:
    ///   - range: The range of one match of ``toolsIdentifier``.
    ///   - bytes: The UTF-8 bytes of the snippet.
    /// - Returns: `true` when both neighbors are word boundaries.
    private static func isWholeIdentifier(_ range: Range<Int>, in bytes: [UInt8]) -> Bool {
        let neighbors = [bytes[..<range.lowerBound].last, bytes[range.upperBound...].first]
        return neighbors.allSatisfy { neighbor in
            neighbor.map { !identifierPartBytes.contains($0) } ?? true
        }
    }
}
