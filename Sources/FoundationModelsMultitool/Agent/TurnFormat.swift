import Foundation
import FoundationModelsRouter

/// One parsed step out of a raw agent-turn response: `runCode`, `findAPIs`, or a final answer.
///
/// Plan.md: "parse a tool call out of `raw` — runCode / findAPIs / final
/// answer". `MultiToolAgent.respond(to:)` dispatches on this after a
/// `TurnFormat` turns the session's raw text into one; the case names
/// mirror the two tools the model sees (`runCode`, `findAPIs`) plus the
/// loop's own terminal step (`final`, not a tool call at all).
public enum AgentStep: Sendable, Equatable {
    /// The model wants to search for relevant tool functions before writing a snippet.
    ///
    /// Plan.md's `findAPIs(task: string)`.
    case findAPIs(task: String)

    /// Represents the model's request to execute a JavaScript snippet.
    ///
    /// The snippet can invoke tools.* per plan.md's `runCode(code: string)`.
    case runCode(code: String)

    /// The model is done and `text` is its answer to the user.
    case final(text: String)
}

/// A raw turn that a `TurnFormat` could not parse into an `AgentStep`.
///
/// Thrown by `TurnFormat.parseTurn(_:)`; `MultiToolAgent.respond(to:)`
/// catches it to drive the bounded repair-turn loop (plan.md M4b: "a parse
/// failure triggers a bounded number of repair turns... before failing the
/// loop").
public struct TurnParseError: Error, Sendable, Equatable, CustomStringConvertible {
    /// A human-readable description of why the turn couldn't be parsed.
    ///
    /// Specific enough to hand back to the model as a repair instruction.
    public let message: String

    /// Creates a turn-parse error.
    ///
    /// - Parameter message: a human-readable description of the failure.
    public init(message: String) {
        self.message = message
    }

    /// A human-readable description of the error.
    ///
    /// Satisfies `CustomStringConvertible`; identical to `message`.
    public var description: String { message }
}

extension TurnParseError {
    /// Extracts the human-readable reason from a `parseTurn(_:)` failure.
    ///
    /// Returns this error's own `message` when `error` is a `TurnParseError`,
    /// else its generic description.
    ///
    /// Shared by every `TurnFormat.repairInstruction(for:)` conformer
    /// (`TolerantParseTurnFormat`, `GuidedTurnFormat`) so the same
    /// error-vs-message fallback isn't hand-copied per strategy.
    ///
    /// - Parameter error: the error `parseTurn(_:)` threw.
    /// - Returns: `error`'s `TurnParseError.message` when available, else
    ///   `String(describing: error)`.
    static func reason(for error: Error) -> String {
        (error as? TurnParseError)?.message ?? String(describing: error)
    }
}

/// A strategy for formatting and parsing agent turns.
///
/// Defines what `MultiToolAgent` tells the model about the response shape
/// it expects (formatting), and how raw session text becomes an
/// `AgentStep` (parsing).
///
/// Plan.md Router integration: "Two ways to make the model emit a
/// well-formed call rather than free prose... 1. Guided turns... 2. Prompted
/// convention + tolerant parse." `TolerantParseTurnFormat` below is the
/// second; `GuidedTurnFormat` (`AgentTurn.swift`, M4c) is the first. Because
/// `MultiToolAgent`'s loop (`respond(to:)`) is written entirely against this
/// protocol — never against either conformer directly — plugging in a
/// second strategy is adding a new conformer and a new static factory
/// (mirroring `.tolerantParse`/`.guided`); the loop itself does not change.
public protocol TurnFormat: Sendable {
    /// How many consecutive parse failures this format tolerates before `MultiToolAgent.respond(to:)` fails the loop.
    ///
    /// Each failure triggers a repair turn; exceeding this count fails the
    /// loop with `MultiToolAgentError.unparseableTurn`. Plan.md:
    /// "configurable, default 1."
    var maxRepairTurns: Int { get }

    /// The turn-format-specific instructions to append to the agent's session instructions.
    ///
    /// Teaches the model how to shape its response. A guided strategy that
    /// constrains output via grammar rather than prose convention may
    /// return an empty string.
    ///
    /// - Parameter supportsFindAPIs: whether the agent's registry surfaces
    ///   `findAPIs` (`false` in direct mode) — the instructions should not
    ///   describe an action the model can't actually take.
    /// - Returns: the format instructions to append to the session's
    ///   instructions.
    func formatInstructions(supportsFindAPIs: Bool) -> String

    /// Parses one raw turn response into a well-formed `AgentStep`.
    ///
    /// - Parameter raw: the session's raw text response for this turn.
    /// - Returns: the parsed step.
    /// - Throws: `TurnParseError` (or another error) if `raw` can't be
    ///   parsed into a well-formed step.
    func parseTurn(_ raw: String) throws -> AgentStep

    /// Generates a repair instruction after a parse failure.
    ///
    /// Returns text to feed back to the model asking it to try the turn
    /// again in the expected format.
    ///
    /// - Parameter error: the error `parseTurn(_:)` threw.
    /// - Returns: the repair instruction to append to the transcript.
    func repairInstruction(for error: Error) -> String

    /// The Router grammar this format's session must be constrained to, or `nil` for an unconstrained session.
    ///
    /// `MultiToolAgent`'s production initializer reads this to decide how to
    /// build the main session: non-`nil` routes through
    /// `RoutedLLM.makeGuidedSession(_:instructions:workingDirectory:)`
    /// (`GuidedTurnFormat`, M4c); `nil` routes through the plain
    /// `RoutedLLM.makeSession(instructions:workingDirectory:)`
    /// (`TolerantParseTurnFormat`, via the default below — plan.md Router
    /// integration option 2, "Prompted convention + tolerant parse," has no
    /// grammar constraint at all). Session *construction* is the only place
    /// this differs; the loop's own dispatch/parse/repair code never reads
    /// it.
    var grammar: Grammar? { get }
}

extension TurnFormat {
    /// Default: no grammar constraint — a plain, unconstrained session.
    ///
    /// `TolerantParseTurnFormat` relies on this; `GuidedTurnFormat` is the
    /// one conformer that overrides it.
    public var grammar: Grammar? { nil }
}

/// Plan.md's "Prompted convention + tolerant parse" strategy: a ReAct-style instruction plus a lenient extractor.
///
/// Falls back to a repair turn when parsing fails (plan.md Router
/// integration, option 2).
///
/// The convention asks the model for exactly one `ACTION:` line per turn
/// (`findAPIs`, `runCode`, or `final`) followed by that action's field —
/// `TASK:`, a fenced ```` ```code``` ```` block after `CODE:`, or `ANSWER:`,
/// respectively. The extractor is lenient in three ways a real model's
/// output tends to need: it scans for the first matching marker rather than
/// requiring it to open the message (so a model's "Thought: ..." preamble
/// before the action doesn't break parsing), it matches markers
/// case-insensitively, and `runCode` falls back to "everything after
/// `CODE:`" when the model forgets the code fence.
public struct TolerantParseTurnFormat: TurnFormat {
    /// The field markers the format instructions teach the model and `parseTurn(_:)` scans for.
    ///
    /// Named constants so the two stay in sync by construction rather than
    /// by two hand-kept copies of each literal.
    private enum FieldMarker {
        static let action = "ACTION:"
        static let task = "TASK:"
        static let code = "CODE:"
        static let answer = "ANSWER:"
        /// The Markdown code-fence delimiter for code blocks.
        ///
        /// A named constant so `formatInstructions(supportsFindAPIs:)` and
        /// `extractCode(afterActionAt:in:)` stay in sync.
        static let codeFence = "```"
    }

    /// The `ACTION:` verbs `parseTurn(_:)` recognizes.
    ///
    /// One enum consolidating what used to be two parallel definitions
    /// (`ActionVerb`, lowercased for matching; `ActionName`, properly cased
    /// for display) that had to be kept in sync by hand despite sharing an
    /// identical case set. `rawValue` is the properly-cased spelling used in
    /// `formatInstructions(supportsFindAPIs:)`'s example lines and in
    /// `parseTurn(_:)`'s error messages; `lowercased` is the spelling
    /// `action.value.lowercased()` is compared against.
    private enum Action: String {
        case findAPIs
        case runCode
        case final

        /// The lowercased variant of each action verb for case-insensitive matching.
        ///
        /// Returns `rawValue.lowercased()`, the spelling `parseTurn(_:)`'s
        /// `switch` compares `action.value.lowercased()` against.
        var lowercased: String { rawValue.lowercased() }
    }

    /// Maximum repair turns for this format.
    ///
    /// Determines how many consecutive parse failures this format tolerates
    /// before `MultiToolAgent.respond(to:)` fails the loop — see
    /// `TurnFormat.maxRepairTurns`. Set at `init`, clamped to `0` or above.
    public let maxRepairTurns: Int

    /// Creates a tolerant-parse turn format.
    ///
    /// - Parameter maxRepairTurns: how many consecutive parse failures to
    ///   tolerate before `MultiToolAgent.respond(to:)` fails the loop.
    ///   Negative values are clamped to `0` (no repair turns at all — the
    ///   first parse failure fails the loop immediately). Defaults to `1`.
    public init(maxRepairTurns: Int = 1) {
        self.maxRepairTurns = max(0, maxRepairTurns)
    }

    /// Builds format instructions for the ReAct-style action markers.
    ///
    /// Includes `ACTION:`, `TASK:`, `CODE:`, and `ANSWER:` markers this
    /// conformer's `parseTurn(_:)` expects — see
    /// `TurnFormat.formatInstructions(supportsFindAPIs:)`.
    ///
    /// - Parameter supportsFindAPIs: whether to include the `findAPIs`
    ///   action's instructions; omitted entirely in direct mode.
    /// - Returns: the full format instructions.
    public func formatInstructions(supportsFindAPIs: Bool) -> String {
        var lines = [
            "On each turn, respond with exactly one action, using exactly one of the",
            "formats below — nothing else in the message.",
            "",
        ]
        if supportsFindAPIs {
            lines.append(contentsOf: [
                "To search for relevant tool functions:",
                "\(FieldMarker.action) \(Action.findAPIs.rawValue)",
                "\(FieldMarker.task) <what you are trying to accomplish, in plain language>",
                "",
            ])
        }
        lines.append(contentsOf: [
            "To run a JavaScript snippet against tools.*:",
            "\(FieldMarker.action) \(Action.runCode.rawValue)",
            FieldMarker.code,
            "\(FieldMarker.codeFence)js",
            "<your code here>",
            FieldMarker.codeFence,
            "",
        ])
        lines.append(contentsOf: [
            "To give your final answer:",
            "\(FieldMarker.action) \(Action.final.rawValue)",
            "\(FieldMarker.answer) <the final answer text>",
        ])
        return lines.joined(separator: "\n")
    }

    /// Leniently parses `raw` into an `AgentStep` — see `TurnFormat.parseTurn(_:)`.
    ///
    /// Scans for the first `ACTION:` marker (case-insensitively, tolerating
    /// preamble text before it), then extracts that action's field —
    /// `TASK:` for `findAPIs`, a fenced code block after `CODE:` (falling
    /// back to everything after `CODE:` if the model omits the fence) for
    /// `runCode`, or the rest of the message after `ANSWER:` for `final`.
    ///
    /// - Parameter raw: the session's raw text response for this turn.
    /// - Returns: the parsed step.
    /// - Throws: `TurnParseError` if no `ACTION:` marker is found, the
    ///   action verb is unrecognized, or the matched action's required
    ///   field is missing or empty.
    public func parseTurn(_ raw: String) throws -> AgentStep {
        let lines = raw.components(separatedBy: "\n")
        guard let action = Self.firstField(marker: FieldMarker.action, in: lines) else {
            throw TurnParseError(
                message: "No \"\(FieldMarker.action)\" line found. Expected \"\(FieldMarker.action) \(Action.findAPIs.rawValue)\", "
                    + "\"\(FieldMarker.action) \(Action.runCode.rawValue)\", or \"\(FieldMarker.action) \(Action.final.rawValue)\"."
            )
        }

        switch action.value.lowercased() {
        case Action.findAPIs.lowercased:
            guard let task = Self.firstField(marker: FieldMarker.task, in: lines, from: action.lineIndex + 1),
                !task.value.isEmpty
            else {
                throw TurnParseError(
                    message: "\(FieldMarker.action) \(Action.findAPIs.rawValue) requires a non-empty \"\(FieldMarker.task)\" line."
                )
            }
            return .findAPIs(task: task.value)

        case Action.runCode.lowercased:
            guard let code = Self.extractCode(afterActionAt: action.lineIndex, in: lines),
                !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw TurnParseError(
                    message: "\(FieldMarker.action) \(Action.runCode.rawValue) requires a \"\(FieldMarker.code)\" section "
                        + "containing the snippet."
                )
            }
            return .runCode(code: code)

        case Action.final.lowercased:
            guard
                let answer = Self.extractRest(marker: FieldMarker.answer, afterActionAt: action.lineIndex, in: lines),
                !answer.isEmpty
            else {
                throw TurnParseError(
                    message: "\(FieldMarker.action) \(Action.final.rawValue) requires a non-empty \"\(FieldMarker.answer)\" field."
                )
            }
            return .final(text: answer)

        default:
            throw TurnParseError(
                message: "Unrecognized \(FieldMarker.action) \"\(action.value)\". "
                    + "Expected \(Action.findAPIs.rawValue), \(Action.runCode.rawValue), or \(Action.final.rawValue)."
            )
        }
    }

    /// Builds a repair instruction for a parse failure.
    ///
    /// Generates the repair-turn text fed back to the model — see
    /// `TurnFormat.repairInstruction(for:)`.
    ///
    /// - Parameter error: the error `parseTurn(_:)` threw — its
    ///   `TurnParseError.message` when available, else its description.
    /// - Returns: the repair instruction to append to the transcript.
    public func repairInstruction(for error: Error) -> String {
        return """
            Your previous response could not be parsed: \(TurnParseError.reason(for: error))

            Respond again with exactly one \(FieldMarker.action), in the required format, and nothing else.
            """
    }

    // MARK: - Lenient extraction

    /// A field marker found while scanning `lines`.
    ///
    /// Contains its line index (so a caller can keep scanning after it) and
    /// the trimmed text following the marker on that same line.
    private struct Field {
        let lineIndex: Int
        let value: String
    }

    /// Finds the first field marker in the given lines.
    ///
    /// Scans `lines`, from `startIndex` onward, for the first line whose
    /// trimmed text starts with `marker` (case-insensitively), and returns
    /// that line's index and the trimmed text after the marker.
    ///
    /// - Parameters:
    ///   - marker: the field marker to search for, e.g. `"ACTION:"`.
    ///   - lines: the raw turn's lines.
    ///   - startIndex: the index to start scanning from. Defaults to `0`.
    /// - Returns: the matching field, or `nil` if no line starts with
    ///   `marker`.
    private static func firstField(marker: String, in lines: [String], from startIndex: Int = 0) -> Field? {
        guard startIndex >= 0 else { return nil }
        for index in startIndex..<lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard trimmed.lowercased().hasPrefix(marker.lowercased()) else { continue }
            let value = String(trimmed.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
            return Field(lineIndex: index, value: value)
        }
        return nil
    }

    /// Extracts the code body from a `runCode` action.
    ///
    /// Returns the contents of the first fenced code block (```` ``` ````
    /// or ```` ```js ````, etc.) found after a `CODE:` marker, or — if the
    /// model forgot the fence — everything from `CODE:` to the end of the
    /// message, as a tolerant fallback.
    ///
    /// - Parameters:
    ///   - actionIndex: the line index of the `ACTION:` line to search
    ///     after.
    ///   - lines: the raw turn's lines.
    /// - Returns: the extracted code, or `nil` if no `CODE:` marker is
    ///   present at all.
    private static func extractCode(afterActionAt actionIndex: Int, in lines: [String]) -> String? {
        guard let codeField = firstField(marker: FieldMarker.code, in: lines, from: actionIndex + 1) else {
            return nil
        }

        var index = codeField.lineIndex + 1
        while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
            index += 1
        }

        if index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(FieldMarker.codeFence) {
            var codeLines: [String] = []
            index += 1
            while index < lines.count,
                !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(FieldMarker.codeFence)
            {
                codeLines.append(lines[index])
                index += 1
            }
            return codeLines.joined(separator: "\n")
        }

        // Tolerant fallback: no fence — treat everything from CODE: onward
        // (including any text on the CODE: line itself) as the snippet.
        return Self.joinFieldValue(codeField.value, withLinesFrom: lines, startIndex: index, trimmed: false)
    }

    /// Extracts the full text from a marker to the end of the message.
    ///
    /// Includes the same-line remainder and all subsequent lines, trimmed —
    /// the shape a `final` turn's `ANSWER:` field needs, since the answer
    /// text may itself span multiple lines.
    ///
    /// - Parameters:
    ///   - marker: the field marker to search for, e.g. `"ANSWER:"`.
    ///   - actionIndex: the line index of the `ACTION:` line to search
    ///     after.
    ///   - lines: the raw turn's lines.
    /// - Returns: the trimmed rest-of-message text, or `nil` if `marker`
    ///   isn't present.
    private static func extractRest(marker: String, afterActionAt actionIndex: Int, in lines: [String]) -> String? {
        guard let field = firstField(marker: marker, in: lines, from: actionIndex + 1) else { return nil }
        return Self.joinFieldValue(field.value, withLinesFrom: lines, startIndex: field.lineIndex + 1, trimmed: true)
    }

    /// Joins a field's same-line value (if non-empty) with the lines that follow it.
    ///
    /// Shared by `extractCode(afterActionAt:in:)`'s no-fence fallback and
    /// `extractRest(marker:afterActionAt:in:)`: both build an array
    /// containing the field's own same-line text (when present) followed by
    /// every line from `startIndex` onward, then join with `"\n"`.
    ///
    /// - Parameters:
    ///   - fieldValue: the field's trimmed same-line text; included first
    ///     when non-empty.
    ///   - lines: the raw turn's lines.
    ///   - startIndex: the first subsequent line to include; safe to pass an
    ///     index equal to `lines.count` (no subsequent lines).
    ///   - trimmed: whether to trim the joined result of leading/trailing
    ///     whitespace and newlines. `extractRest` needs this; `extractCode`'s
    ///     no-fence fallback does not.
    /// - Returns: the joined text.
    private static func joinFieldValue(
        _ fieldValue: String,
        withLinesFrom lines: [String],
        startIndex: Int,
        trimmed: Bool
    ) -> String {
        var resultLines: [String] = []
        if !fieldValue.isEmpty {
            resultLines.append(fieldValue)
        }
        if startIndex < lines.count {
            resultLines.append(contentsOf: lines[startIndex...])
        }
        let joined = resultLines.joined(separator: "\n")
        return trimmed ? joined.trimmingCharacters(in: .whitespacesAndNewlines) : joined
    }
}

extension TurnFormat where Self == TolerantParseTurnFormat {
    /// Creates a tolerant-parse turn format with configurable repair turns.
    ///
    /// Implements plan.md's "Prompted convention + tolerant parse" strategy
    /// — see `TolerantParseTurnFormat`.
    ///
    /// - Parameter maxRepairTurns: how many consecutive parse failures to
    ///   tolerate before the loop fails. Defaults to `1`.
    /// - Returns: a `TolerantParseTurnFormat` configured with `maxRepairTurns`.
    public static func tolerantParse(maxRepairTurns: Int = 1) -> TolerantParseTurnFormat {
        TolerantParseTurnFormat(maxRepairTurns: maxRepairTurns)
    }
}
