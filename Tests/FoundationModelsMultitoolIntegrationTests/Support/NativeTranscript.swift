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

    /// Verifies that a `findAPIs` call occurs before the first `runCode` call — the "search-then-code" trace assertion.
    ///
    /// - Parameter transcript: the transcript to scan.
    /// - Returns: `true` if a `findAPIs` call precedes the first `runCode`
    ///   call; `false` if there is no `runCode` call at all, or the first
    ///   `runCode` call has no preceding `findAPIs` call.
    static func findAPIsPrecedesRunCode(in transcript: Transcript) -> Bool {
        let calls = toolCalls(in: transcript)
        guard let runCodeIndex = calls.firstIndex(where: { $0.toolName == "runCode" }) else { return false }
        return calls[..<runCodeIndex].contains { $0.toolName == "findAPIs" }
    }

    /// Extracts the `tools.*` call paths every `runCode` tool call's snippet invokes.
    ///
    /// Performs a lexical scan for `tools.<name>(` / `tools.<group>.<name>(`
    /// call sites in each call's decoded `code` argument, not an interpreter
    /// run (the transcript records the code text the model wrote, not which
    /// calls it actually made at runtime) — the same "snippet invoked
    /// exactly the expected tools.*" trace assertion the retired
    /// `TranscriptAnalyzer.invokedToolPaths(in:)` implemented, ported to read
    /// a `runCode` call's arguments directly via `GeneratedContent
    /// .value(_:forProperty:)` rather than decoding through
    /// `RunCodeArguments`, so this file needs no `FoundationModelsMultitool`
    /// import at all.
    ///
    /// - Parameter transcript: the transcript to scan.
    /// - Returns: the union of every `runCode` call's `tools.*` call paths.
    static func invokedToolPaths(in transcript: Transcript) -> Set<String> {
        toolCalls(in: transcript).reduce(into: Set<String>()) { paths, call in
            guard call.toolName == "runCode",
                let code = try? call.arguments.value(String.self, forProperty: "code")
            else { return }
            paths.formUnion(toolCallPaths(in: code))
        }
    }

    /// Extracts the `tools.*` call paths a JavaScript snippet invokes — see `invokedToolPaths(in:)`.
    ///
    /// - Parameter code: one `runCode` call's JavaScript snippet text.
    /// - Returns: the distinct dotted call paths found, e.g. `["weather", "github.createIssue"]`.
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

    /// Decodes `findAPIsTool`'s selection-tier `Selection` results from its own recorded transcript.
    ///
    /// `findAPIsTool`'s internal selection tier remains Router-backed (task
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
    ///     `.flash` for `findAPIsTool`'s selection tier in this suite.
    /// - Returns: every `Selection` result decoded from that slot's
    ///   `.response` events, in recorded order — normally one per `findAPIs`
    ///   call.
    /// - Throws: a decoding error if a `.response` event's text isn't valid,
    ///   schema-conforming JSON for `Selection`.
    static func selections(in events: [TranscriptEvent], slot: ModelSlot) throws -> [Selection] {
        try events
            .filter { $0.slot == slot && $0.kind == .response }
            .compactMap(\.text)
            .map { try Selection(GeneratedContent(json: $0)) }
    }
}
