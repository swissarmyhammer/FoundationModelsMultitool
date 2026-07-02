import Foundation

/// One parsed step out of a raw agent-turn response — plan.md's "parse a
/// tool call out of `raw` — runCode / findAPIs / final answer".
///
/// `MultiToolAgent.respond(to:)` dispatches on this after a `TurnFormat`
/// turns the session's raw text into one; the case names mirror the two
/// tools the model sees (`runCode`, `findAPIs`) plus the loop's own
/// terminal step (`final`, not a tool call at all).
public enum AgentStep: Sendable, Equatable {
    /// The model wants to search for relevant tool functions before writing
    /// a snippet — plan.md's `findAPIs(task: string)`.
    case findAPIs(task: String)

    /// The model wants to run a JavaScript snippet against `tools.*` —
    /// plan.md's `runCode(code: string)`.
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
    /// A human-readable description of why the turn couldn't be parsed —
    /// specific enough to hand back to the model as a repair instruction.
    public let message: String

    /// Creates a turn-parse error.
    ///
    /// - Parameter message: a human-readable description of the failure.
    public init(message: String) {
        self.message = message
    }

    /// A human-readable description of the error, satisfying
    /// `CustomStringConvertible`. Identical to `message`.
    public var description: String { message }
}

/// A pluggable strategy for how one agent turn is formatted (what
/// `MultiToolAgent` tells the model about the response shape it expects)
/// and parsed (how raw session text becomes an `AgentStep`).
///
/// Plan.md Router integration: "Two ways to make the model emit a
/// well-formed call rather than free prose... 1. Guided turns... 2. Prompted
/// convention + tolerant parse." `TolerantParseTurnFormat` below is the
/// second; a `.guided` conformer arrives in M4c. Because `MultiToolAgent`'s
/// loop (`respond(to:)`) is written entirely against this protocol — never
/// against `TolerantParseTurnFormat` directly — plugging in a second
/// strategy is adding a new conformer and a new `.guided` static factory
/// (mirroring `.tolerantParse` below); the loop itself does not change.
public protocol TurnFormat: Sendable {
    /// How many consecutive parse failures `MultiToolAgent.respond(to:)`
    /// tolerates (each triggering a repair turn) before failing the loop
    /// with `MultiToolAgentError.unparseableTurn`. Plan.md: "configurable,
    /// default 1."
    var maxRepairTurns: Int { get }

    /// The turn-format-specific instructions to append to the agent's
    /// session instructions, teaching the model how to shape its response.
    /// A guided strategy that constrains output via grammar rather than
    /// prose convention may return an empty string.
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

    /// The text to feed back to the model after a parse failure, asking it
    /// to try the turn again in the expected format.
    ///
    /// - Parameter error: the error `parseTurn(_:)` threw.
    /// - Returns: the repair instruction to append to the transcript.
    func repairInstruction(for error: Error) -> String
}

/// Plan.md's "Prompted convention + tolerant parse": a ReAct-style
/// instruction plus a lenient extractor, falling back to a repair turn when
/// parsing fails (plan.md Router integration, option 2).
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
    /// The field markers the format instructions teach the model and
    /// `parseTurn(_:)` scans for — named constants so the two stay in sync
    /// by construction rather than by two hand-kept copies of each literal.
    private enum FieldMarker {
        static let action = "ACTION:"
        static let task = "TASK:"
        static let code = "CODE:"
        static let answer = "ANSWER:"
        /// The Markdown code-fence delimiter `formatInstructions(supportsFindAPIs:)`
        /// teaches the model and `extractCode(afterActionAt:in:)` scans for —
        /// one named constant so both stay in sync.
        static let codeFence = "```"
    }

    /// The `ACTION:` verbs `parseTurn(_:)` recognizes, lowercased to match
    /// `action.value.lowercased()`'s case-insensitive comparison — named
    /// constants so the verb spelled out in error messages and the one
    /// compared against in the `switch` below can never drift apart.
    private enum ActionVerb {
        static let findAPIs = "findapis"
        static let runCode = "runcode"
        static let final = "final"
    }

    /// How many consecutive parse failures this format tolerates before
    /// `MultiToolAgent.respond(to:)` fails the loop — see
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

    /// Builds the ReAct-style `ACTION:`/`TASK:`/`CODE:`/`ANSWER:` format
    /// instructions this conformer's `parseTurn(_:)` expects — see
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
                "\(FieldMarker.action) findAPIs",
                "\(FieldMarker.task) <what you are trying to accomplish, in plain language>",
                "",
            ])
        }
        lines.append(contentsOf: [
            "To run a JavaScript snippet against tools.*:",
            "\(FieldMarker.action) runCode",
            FieldMarker.code,
            "\(FieldMarker.codeFence)js",
            "<your code here>",
            FieldMarker.codeFence,
            "",
            "To give your final answer:",
            "\(FieldMarker.action) final",
            "\(FieldMarker.answer) <the final answer text>",
        ])
        return lines.joined(separator: "\n")
    }

    /// Leniently parses `raw` into an `AgentStep` — see
    /// `TurnFormat.parseTurn(_:)`.
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
                message: "No \"\(FieldMarker.action)\" line found. Expected \"\(FieldMarker.action) findAPIs\", "
                    + "\"\(FieldMarker.action) runCode\", or \"\(FieldMarker.action) final\"."
            )
        }

        switch action.value.lowercased() {
        case ActionVerb.findAPIs:
            guard let task = Self.firstField(marker: FieldMarker.task, in: lines, from: action.lineIndex + 1),
                !task.value.isEmpty
            else {
                throw TurnParseError(
                    message: "\(FieldMarker.action) findAPIs requires a non-empty \"\(FieldMarker.task)\" line."
                )
            }
            return .findAPIs(task: task.value)

        case ActionVerb.runCode:
            guard let code = Self.extractCode(afterActionAt: action.lineIndex, in: lines),
                !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw TurnParseError(
                    message: "\(FieldMarker.action) runCode requires a \"\(FieldMarker.code)\" section "
                        + "containing the snippet."
                )
            }
            return .runCode(code: code)

        case ActionVerb.final:
            guard
                let answer = Self.extractRest(marker: FieldMarker.answer, afterActionAt: action.lineIndex, in: lines),
                !answer.isEmpty
            else {
                throw TurnParseError(
                    message: "\(FieldMarker.action) final requires a non-empty \"\(FieldMarker.answer)\" field."
                )
            }
            return .final(text: answer)

        default:
            throw TurnParseError(
                message: "Unrecognized \(FieldMarker.action) \"\(action.value)\". "
                    + "Expected findAPIs, runCode, or final."
            )
        }
    }

    /// Builds the repair-turn text fed back to the model after a parse
    /// failure — see `TurnFormat.repairInstruction(for:)`.
    ///
    /// - Parameter error: the error `parseTurn(_:)` threw — its
    ///   `TurnParseError.message` when available, else its description.
    /// - Returns: the repair instruction to append to the transcript.
    public func repairInstruction(for error: Error) -> String {
        let reason = (error as? TurnParseError)?.message ?? String(describing: error)
        return """
            Your previous response could not be parsed: \(reason)

            Respond again with exactly one \(FieldMarker.action), in the required format, and nothing else.
            """
    }

    // MARK: - Lenient extraction

    /// One `marker:` field found while scanning `lines` — its line index
    /// (so a caller can keep scanning after it) and the trimmed text
    /// following the marker on that same line.
    private struct Field {
        let lineIndex: Int
        let value: String
    }

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

    /// Extracts a `runCode` snippet's body: the contents of the first fenced
    /// code block (```` ``` ```` or ```` ```js ````, etc.) found after a
    /// `CODE:` marker, or — if the model forgot the fence — everything from
    /// `CODE:` to the end of the message, as a tolerant fallback.
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
        var fallbackLines: [String] = []
        if !codeField.value.isEmpty {
            fallbackLines.append(codeField.value)
        }
        fallbackLines.append(contentsOf: lines[index...])
        return fallbackLines.joined(separator: "\n")
    }

    /// Extracts everything from a marker (inclusive of the same-line
    /// remainder) to the end of the message, trimmed — the shape a `final`
    /// turn's `ANSWER:` field needs, since the answer text may itself span
    /// multiple lines.
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
        var resultLines: [String] = []
        if !field.value.isEmpty {
            resultLines.append(field.value)
        }
        if field.lineIndex + 1 < lines.count {
            resultLines.append(contentsOf: lines[(field.lineIndex + 1)...])
        }
        return resultLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension TurnFormat where Self == TolerantParseTurnFormat {
    /// Plan.md's "Prompted convention + tolerant parse" strategy — see
    /// `TolerantParseTurnFormat`.
    ///
    /// - Parameter maxRepairTurns: how many consecutive parse failures to
    ///   tolerate before the loop fails. Defaults to `1`.
    /// - Returns: a `TolerantParseTurnFormat` configured with `maxRepairTurns`.
    public static func tolerantParse(maxRepairTurns: Int = 1) -> TolerantParseTurnFormat {
        TolerantParseTurnFormat(maxRepairTurns: maxRepairTurns)
    }
}
