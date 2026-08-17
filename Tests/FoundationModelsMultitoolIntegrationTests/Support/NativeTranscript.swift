import Foundation

import FoundationModels
import FoundationModelsMetadataRegistry
import FoundationModelsRouter

/// Trace assertions over a real `FoundationModels.Transcript` — the native
/// replacement for the retired `TranscriptAnalyzer`'s `AgentStep`-based
/// assertions, which only ever applied to `MultiToolAgent`'s hand-rolled
/// ReAct-loop transcript format (its own `ACTION:`/`TASK:`/`CODE:` or guided
/// JSON turn convention). A `LanguageModelSession`'s own transcript already
/// carries everything the gated scenario suite needs natively (`.toolCalls`
/// entries recording every tool invocation, in order) — there is no
/// turn-parsing step at all here, just reading the transcript Apple's own
/// native tool-calling loop already built.
///
/// Deliberately self-contained, with no dependency on `TranscriptAnalyzer
/// .swift`/`AgentStep` (retired alongside `MultiToolAgent` — see the
/// `7840f24` kanban task), so this gated suite's port does not itself become
/// a reason to keep that file around.
enum NativeTranscript {
    /// The tool name `MultiTool` mounts under — the snippet runner.
    private static let runCodeToolName = "runCode"

    /// The tool name `SearchToolsTool` mounts under — the catalog searcher.
    private static let searchToolsToolName = "searchTools"

    /// Every `Transcript.ToolCall` across every `.toolCalls` entry, in transcript order.
    ///
    /// A single `.toolCalls` entry can itself carry more than one call (a
    /// model requesting several tools in the same round); flattening keeps
    /// every helper below working over one flat, chronologically-ordered
    /// sequence.
    ///
    /// - Parameter transcript: the transcript to scan.
    /// - Returns: every tool call, in the order the session recorded them.
    static func toolCalls(in transcript: Transcript) -> [Transcript.ToolCall] {
        transcript.flatMap { entry -> [Transcript.ToolCall] in
            guard case .toolCalls(let calls) = entry else { return [] }
            return Array(calls)
        }
    }

    /// The number of tool calls to the tool named `name` — or, when `name` is `nil`, every tool call.
    ///
    /// - Parameters:
    ///   - transcript: the transcript to scan.
    ///   - name: the tool name to count calls for, or `nil` to count every
    ///     call regardless of name. Defaults to `nil`.
    /// - Returns: the matching call count.
    static func toolCallCount(in transcript: Transcript, named name: String? = nil) -> Int {
        toolCalls(in: transcript).count { name == nil || $0.toolName == name }
    }

    /// Verifies that a `searchTools` call occurs before the first `runCode` call — the "search-then-code" trace assertion.
    ///
    /// - Parameter transcript: the transcript to scan.
    /// - Returns: `true` if a `searchTools` call precedes the first `runCode`
    ///   call; `false` if there is no `runCode` call at all, or the first
    ///   `runCode` call has no preceding `searchTools` call.
    static func searchToolsPrecedesRunCode(in transcript: Transcript) -> Bool {
        let calls = toolCalls(in: transcript)
        guard let runCodeIndex = calls.firstIndex(where: { $0.toolName == runCodeToolName }) else {
            return false
        }
        return calls[..<runCodeIndex].contains { $0.toolName == searchToolsToolName }
    }

    /// Extracts the `tools.*` call paths every `runCode` tool call's snippet **wrote**.
    ///
    /// Answers exactly one question: which `tools.*` names did the model type
    /// into a snippet? It is a lexical scan for `tools.<name>(` /
    /// `tools.<group>.<name>(` call sites in each call's decoded `code`
    /// argument, never an interpreter run — the transcript records the code
    /// text the model wrote, not which of those calls resolved, ran, or
    /// returned.
    ///
    /// That makes it the right evidence for the `inventedPath` failure mode,
    /// whose question is precisely what the model reached for: a path the
    /// mounted catalog does not define never reaches a tool at all, so
    /// nothing but the source text can report it. It is the wrong evidence
    /// for any question about what happened. A snippet naming two functions
    /// no fixture defines scans as two call sites while both calls throw and
    /// nothing runs — the false pass task `0981ar3` removed.
    /// `ScenarioCallLog`'s `invokedPaths` and `returnedPaths`, recorded by the
    /// fixture tools themselves as they run, answer those questions instead.
    ///
    /// The same "snippet invoked exactly the expected tools.*" trace scan the
    /// retired `TranscriptAnalyzer.invokedToolPaths(in:)` implemented, ported
    /// to read a `runCode` call's arguments directly via `GeneratedContent
    /// .value(_:forProperty:)` rather than decoding through
    /// `RunCodeArguments`, so this file needs no `FoundationModelsMultitool`
    /// import at all.
    ///
    /// - Parameter transcript: the transcript to scan.
    /// - Returns: the union of every `runCode` call's typed `tools.*` call paths.
    static func typedToolPaths(in transcript: Transcript) -> Set<String> {
        toolCalls(in: transcript).reduce(into: Set<String>()) { paths, call in
            guard call.toolName == runCodeToolName,
                let code = try? call.arguments.value(String.self, forProperty: "code")
            else { return }
            paths.formUnion(toolCallPaths(in: code))
        }
    }

    /// Extracts the scalar values the tools genuinely returned to the model.
    ///
    /// This is the counterpart to `typedToolPaths(in:)` and answers a
    /// different question. That one reads the code the model *wrote*; this
    /// one reads what came *back*, so a caller can tell a reply that carries
    /// real fixture data from one that carries an invention. Which *paths*
    /// returned, as opposed to which values, is `ScenarioCallLog`'s
    /// `returnedPaths`.
    ///
    /// Reads only `runCode` outputs, and only those that parse as JSON. A
    /// clean `ResultRenderer.render(_:limits:)` success is the serialized
    /// return value and nothing else — no frame text — so a `runCode` output
    /// that parses is exactly the data a snippet returned, and its leaf
    /// scalars are that data with no heuristic in between. An output that
    /// does not parse contributes nothing rather than contributing noise:
    /// that covers a repairable error, an appended `Console output:` section,
    /// a truncation note, and `ToolReturnLedger`'s uncarried-return notice,
    /// none of which is data the tools produced. The last of those is the
    /// case where a snippet returned a sentence rather than what it read, so
    /// the values it contributes nothing about are values it never carried.
    /// A `searchTools` output is skipped outright — it is the catalog the model
    /// was shown, not an answer it was given.
    ///
    /// Booleans are skipped: JSON `true` bridges to the same numeric type as
    /// `1`, and a reply containing "1" is no evidence that anything came
    /// back.
    ///
    /// - Parameter transcript: the transcript to scan.
    /// - Returns: every distinct scalar the `runCode` outputs carried,
    ///   rendered as text.
    /// One `tools.*`-bearing call as the session's event stream reports it.
    ///
    /// `RoutedSession` publishes no transcript, so a run on the Router path
    /// derives the same evidence from `SessionEvent.toolCall`, which carries
    /// the tool's name and its arguments as JSON.
    struct StreamedCall {
        /// The mounted tool's name.
        let name: String

        /// The call's arguments, as the event delivered them.
        let argumentsJSON: String

        /// The tool's rendered output, once it completed.
        var output: String?
    }

    /// Every `tools.*` path the `runCode` calls in `calls` wrote.
    ///
    /// The event-stream twin of ``typedToolPaths(in:)``: same extraction, same
    /// `runCode`-only filter, reading the snippet out of the call's arguments
    /// JSON rather than out of a transcript entry.
    ///
    /// - Parameter calls: the run's calls, in the order the stream reported.
    /// - Returns: every `tools.*` path those snippets named.
    static func typedToolPaths(in calls: [StreamedCall]) -> Set<String> {
        calls.reduce(into: Set<String>()) { paths, call in
            guard call.name == runCodeToolName, let code = snippet(of: call) else { return }
            paths.formUnion(toolCallPaths(in: code))
        }
    }

    /// Whether a `searchTools` call precedes the first `runCode` call.
    ///
    /// The event-stream twin of ``searchToolsPrecedesRunCode(in:)``.
    ///
    /// - Parameter calls: the run's calls, in the order the stream reported.
    /// - Returns: `true` when discovery came first, `false` when no `runCode`
    ///   call was made at all.
    static func searchToolsPrecedesRunCode(in calls: [StreamedCall]) -> Bool {
        guard let runCodeIndex = calls.firstIndex(where: { $0.name == runCodeToolName }) else {
            return false
        }
        return calls[..<runCodeIndex].contains { $0.name == searchToolsToolName }
    }

    /// Every scalar the `runCode` calls in `calls` returned.
    ///
    /// The event-stream twin of ``returnedValues(in:)``.
    ///
    /// - Parameter calls: the run's calls, with their outputs attached.
    /// - Returns: every scalar those outputs carried.
    static func returnedValues(in calls: [StreamedCall]) -> Set<String> {
        calls.reduce(into: Set<String>()) { values, call in
            guard call.name == runCodeToolName, let output = call.output,
                let data = output.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            else {
                return
            }
            collectScalars(of: json, into: &values)
        }
    }

    /// Reads the snippet out of a `runCode` call's arguments JSON.
    ///
    /// - Parameter call: the call to read.
    /// - Returns: the snippet source, or `nil` when the arguments carry none.
    private static func snippet(of call: StreamedCall) -> String? {
        guard let data = call.argumentsJSON.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return object["code"] as? String
    }

    static func returnedValues(in transcript: Transcript) -> Set<String> {
        transcript.reduce(into: Set<String>()) { values, entry in
            guard case .toolOutput(let output) = entry, output.toolName == runCodeToolName else {
                return
            }
            guard let data = text(of: output).data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            else {
                return
            }
            collectScalars(of: json, into: &values)
        }
    }

    /// Joins one tool output's text segments.
    ///
    /// - Parameter output: the recorded tool output.
    /// - Returns: the output's text, segments concatenated in order.
    private static func text(of output: Transcript.ToolOutput) -> String {
        output.segments
            .compactMap { segment -> String? in
                guard case .text(let textSegment) = segment else { return nil }
                return textSegment.content
            }
            .joined()
    }

    /// Walks a decoded JSON value and collects its leaf scalars as text.
    ///
    /// - Parameters:
    ///   - json: the decoded value to walk.
    ///   - values: the set to insert each leaf scalar into.
    private static func collectScalars(of json: Any, into values: inout Set<String>) {
        switch json {
        case let object as [String: Any]:
            for value in object.values {
                collectScalars(of: value, into: &values)
            }
        case let array as [Any]:
            for value in array {
                collectScalars(of: value, into: &values)
            }
        case let text as String:
            values.insert(text)
        case let number as NSNumber where CFGetTypeID(number) != CFBooleanGetTypeID():
            values.insert(number.stringValue)
        default:
            break
        }
    }

    /// Extracts the `tools.*` call paths a JavaScript snippet writes — see `typedToolPaths(in:)`.
    ///
    /// - Parameter code: one `runCode` call's JavaScript snippet text.
    /// - Returns: the distinct dotted call paths found, e.g. `["getWeather", "github.createIssue"]`.
    private static func toolCallPaths(in code: String) -> Set<String> {
        let range = NSRange(code.startIndex..., in: code)
        let matches = toolCallRegex.matches(in: code, range: range)
        return Set(
            matches.compactMap { match -> String? in
                guard let pathRange = Range(match.range(at: 1), in: code) else { return nil }
                return String(code[pathRange])
            }
        )
    }

    /// The compiled call-site regex `toolCallPaths(in:)` scans for `tools.*` call sites.
    ///
    /// Matches `tools.<name>` / `tools.<group>.<name>` call sites. Computed
    /// once, since `NSRegularExpression` compilation is comparatively
    /// expensive and this pattern never changes — the same pattern the
    /// retired `TranscriptAnalyzer.toolCallRegex` used.
    private static let toolCallRegex: NSRegularExpression = {
        let pattern = #"(?<![A-Za-z0-9_$])tools\.([A-Za-z_$][A-Za-z0-9_$]*(?:\.[A-Za-z_$][A-Za-z0-9_$]*)?)\s*\("#
        // `try!` is safe here: `pattern` is a compile-time-known literal that
        // is valid by construction, so `NSRegularExpression`'s initializer
        // can never actually throw.
        return try! NSRegularExpression(pattern: pattern)
    }()

    /// Decodes `searchToolsTool`'s selection-tier `Selection` results from its own recorded transcript.
    ///
    /// `searchToolsTool`'s internal selection tier remains Router-backed (task
    /// `4aveepp`'s decision, kept specifically to preserve `PrefixReuseTests`'
    /// fork()-based prefix-reuse property) — every selection call is still a
    /// real, recorded Router session, independent of the *main*
    /// `LanguageModelSession` above (which wraps a bare `MLXLanguageModel`,
    /// never Router-vended, so it is never recorded here). Redeclared here
    /// (rather than reusing the retired `TranscriptAnalyzer
    /// .selections(in:slot:)`) so this file has no dependency on
    /// `TranscriptAnalyzer.swift`.
    ///
    /// - Parameters:
    ///   - events: the full decoded Router transcript (see
    ///     `LiveRouterFixture.transcriptEvents()`).
    ///   - slot: the model slot whose `.response` events to decode — always
    ///     `.flash` for `searchToolsTool`'s selection tier in this suite.
    /// - Returns: every `Selection` result decoded from that slot's
    ///   `.response` events, in recorded order — normally one per `searchTools`
    ///   call.
    /// - Throws: a decoding error if a `.response` event's body isn't valid,
    ///   schema-conforming JSON for `Selection`.
    static func selections(in events: [TranscriptEvent], slot: ModelSlot) throws -> [Selection] {
        try events
            .filter { $0.slot == slot && $0.kind == .response }
            .compactMap(Self.selectionJSON)
            .map { try Selection(GeneratedContent(json: $0)) }
    }

    /// Extracts a `.response` event's selection JSON body.
    ///
    /// A guided selection response is recorded as a **`.structure` segment**
    /// (`contentJSON`) on the event's entry payload — never as `.text`, so
    /// `TranscriptEvent.text` (which joins only `.text` segments) is `nil`
    /// for it. Reads the first structured segment's JSON, falling back to
    /// the event's plain `text` body for any recording shape that carries
    /// the JSON as text instead.
    ///
    /// - Parameter event: the `.response` event to extract from.
    /// - Returns: the selection's JSON body, or `nil` if the event carries
    ///   neither a structured segment nor body text.
    private static func selectionJSON(of event: TranscriptEvent) -> String? {
        if let segments = event.entry?.segments {
            for segment in segments {
                if case .structure(_, _, let contentJSON) = segment {
                    return contentJSON
                }
            }
        }
        return event.text
    }
}
