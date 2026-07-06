import Foundation
import FoundationModels
import FoundationModelsMetadataRegistry
import FoundationModelsRouter

/// Reconstructs an agent loop's `AgentStep`s (and the selection tier's
/// `Selection` picks) from a Router JSONL transcript (`RecordingLevel.full`) — plan.md's
/// M6.5 trace assertions ("findAPIs before runCode", "selection tier returned
/// the expected minimal set", "snippet invoked exactly the expected tools.*",
/// "repair within N turns") read the transcript rather than instrumenting the
/// loop itself, so the same on-disk artifact a real gated run produces is
/// what both the gated integration suite
/// (`Tests/FoundationModelsMultitoolIntegrationTests`) and this type's own
/// ungated unit tests (`TranscriptAssertionTests`, run in normal CI against
/// checked-in fixture JSONL) exercise.
///
/// **Why a recorded `.response` event decodes 1:1 with one `parseTurn(_:)`
/// call.** `MultiToolAgent.respond(to:)` resends the whole *growing*
/// transcript as each turn's *prompt* (a Router session's `respond(to:)`
/// carries no memory of its own — see `MultiToolAgent`'s documentation), but
/// each turn's raw *response* is exactly that turn's fresh model output — so
/// a session's `.response` events, read in recorded order, are exactly the
/// sequence `TurnFormat.parseTurn(_:)` was called on, once per turn.
///
/// **Which format to parse with.** A `TranscriptEvent.grammar` is set only
/// when the session that produced it was constrained via
/// `RoutedLLM.makeGuidedSession(_:instructions:workingDirectory:)` — exactly
/// `GuidedTurnFormat`'s session-construction path (`TurnFormat.grammar`). So
/// a non-`nil` `grammar` on a `.response` event means decode it as an
/// `AgentTurn` (`GuidedTurnFormat`); `nil` means the tolerant `ACTION:`
/// convention (`TolerantParseTurnFormat`).
///
/// **Which session is "the main agent" vs. "the selection tier."** Rather
/// than threading an opaque session id through every caller, every helper
/// below filters on `TranscriptEvent.slot`: `MultiToolAgent`'s main loop
/// always runs on `profile.standard` (`.standard`) and the registry's
/// `SelectionTier` root/forked sessions always run on `profile.flash`
/// (`.flash`) — plan.md's Router integration and Discovery sections — so the
/// slot alone discriminates the two, correctly aggregating across every
/// selection tier `fork()` child a `respond(to:)` call created, in true
/// chronological order (`MergedTranscript.merged(under:)`'s `(ts, seq)` order
/// across every nested session file).
enum TranscriptAnalyzer {
    /// Decodes newline-delimited JSON transcript text into events, in file
    /// order — the shape `JSONLRecorder` writes and `MergedTranscript
    /// .merged(under:)` reads back, minus the cross-file `(ts, seq)` re-sort
    /// that only matters once more than one session's file is involved (a
    /// single session's own file is already in `seq` order, since one
    /// recorder actor appends it serially).
    ///
    /// - Parameter jsonl: the transcript text, one JSON object per line;
    ///   blank lines are ignored.
    /// - Returns: the decoded events, in file order.
    /// - Throws: a decoding error if any non-blank line isn't valid
    ///   `TranscriptEvent` JSON.
    static func decodeJSONL(_ jsonl: String) throws -> [TranscriptEvent] {
        let decoder = JSONDecoder()
        return try jsonl
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { try decoder.decode(TranscriptEvent.self, from: Data($0.utf8)) }
    }

    /// Parses one recorded `.response` event's text into an `AgentStep`,
    /// selecting the turn format by the event's own `grammar` field — see
    /// this type's documentation.
    ///
    /// - Parameter event: a `.response`-kind event.
    /// - Returns: the parsed step.
    /// - Throws: `TurnParseError` if `event.text` is `nil`; otherwise
    ///   whatever the selected `TurnFormat.parseTurn(_:)` throws.
    static func step(from event: TranscriptEvent) throws -> AgentStep {
        guard let text = event.text else {
            throw TurnParseError(message: "Transcript event seq \(event.seq) carries no text to parse a step from.")
        }
        let format: any TurnFormat = event.grammar != nil ? GuidedTurnFormat() : TolerantParseTurnFormat()
        return try format.parseTurn(text)
    }

    /// Every `.response` event stamped with `slot`, parsed into `AgentStep`s
    /// in recorded order — see this type's documentation for why `slot`
    /// alone correctly discriminates the main agent from the selection tier.
    ///
    /// Parse failures are silently skipped: a bad turn `MultiToolAgent
    /// .respond(to:)` itself already recovers from via a repair turn is not
    /// a step at all, and every trace assertion this type supports
    /// (search-then-code ordering, invoked tool paths, repair-turn counting)
    /// only cares about *successfully parsed* steps.
    ///
    /// - Parameters:
    ///   - events: the full decoded transcript.
    ///   - slot: the model slot whose `.response` events to parse.
    /// - Returns: the parsed steps, in recorded order.
    static func steps(in events: [TranscriptEvent], slot: ModelSlot) -> [AgentStep] {
        events
            .filter { $0.slot == slot && $0.kind == .response }
            .compactMap { try? step(from: $0) }
    }

    /// Whether a `.findAPIs` step occurs before the first `.runCode` step —
    /// plan.md's "search-then-code" trace assertion.
    ///
    /// - Parameter steps: the ordered steps to inspect (see `steps(in:slot:)`).
    /// - Returns: `true` if a `.findAPIs` step precedes the first `.runCode`
    ///   step; `false` if there is no `.runCode` step at all, or the first
    ///   `.runCode` step has no `.findAPIs` step before it.
    static func findAPIsPrecedesRunCode(in steps: [AgentStep]) -> Bool {
        guard let runCodeIndex = steps.firstIndex(where: \.isRunCode) else { return false }
        return steps[..<runCodeIndex].contains(where: \.isFindAPIs)
    }

    /// The `tools.*` call paths a `runCode` snippet's code text invokes
    /// *syntactically* — a lexical scan for `tools.<name>(` /
    /// `tools.<group>.<name>(` call sites, not an interpreter run (the
    /// transcript records the code text the model wrote, not which calls it
    /// actually made at runtime).
    ///
    /// - Parameter code: one `.runCode` step's JavaScript snippet text.
    /// - Returns: the distinct dotted call paths found, e.g. `["weather",
    ///   "github.createIssue"]`.
    static func toolCallPaths(in code: String) -> Set<String> {
        let range = NSRange(code.startIndex..., in: code)
        let matches = toolCallRegex.matches(in: code, range: range)
        return Set(
            matches.compactMap { match -> String? in
                guard let pathRange = Range(match.range(at: 1), in: code) else { return nil }
                return String(code[pathRange])
            }
        )
    }

    /// Every distinct `tools.*` call path invoked across every `.runCode`
    /// step in `steps` — plan.md's "snippet invoked exactly the expected
    /// tools.*" trace assertion.
    ///
    /// - Parameter steps: the ordered steps to scan (see `steps(in:slot:)`).
    /// - Returns: the union of `toolCallPaths(in:)` over every `.runCode`
    ///   step's code.
    static func invokedToolPaths(in steps: [AgentStep]) -> Set<String> {
        steps.reduce(into: Set<String>()) { paths, step in
            guard case .runCode(let code) = step else { return }
            paths.formUnion(toolCallPaths(in: code))
        }
    }

    /// How many `.runCode` steps occurred before the first `.final` step —
    /// plan.md's "repair within N turns" trace assertion: a scenario that
    /// mis-calls a tool once and then corrects itself produces more than one
    /// `.runCode` step before `.final`.
    ///
    /// - Parameter steps: the ordered steps to scan (see `steps(in:slot:)`).
    /// - Returns: how many `.runCode` steps precede the first `.final` step;
    ///   every `.runCode` step in `steps` if there is no `.final` step at all.
    static func runCodeStepsBeforeFinal(in steps: [AgentStep]) -> Int {
        var count = 0
        for step in steps {
            switch step {
            case .runCode:
                count += 1
            case .final:
                return count
            case .findAPIs:
                continue
            }
        }
        return count
    }

    /// Decodes the selection tier's `Selection` results from its `.response`
    /// events — the raw guided-generation JSON `AgentSession
    /// .respond(to:generating:)` decodes at call time — plan.md's "selection
    /// tier returned the expected minimal set" trace assertion, now
    /// generalized to the registry's ids-only `Selection` shape (plan.md §6: "Ids only,
    /// grammar-enforced" — superseding Multitool's own former `FoundAPIs`,
    /// which had the model reproduce each function's fields).
    ///
    /// - Parameters:
    ///   - events: the full decoded transcript.
    ///   - slot: the model slot whose `.response` events to decode —
    ///     typically `.flash` (see this type's documentation).
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

    /// The compiled `tools.<name>` / `tools.<group>.<name>` call-site regex
    /// `toolCallPaths(in:)` scans with — computed once, since
    /// `NSRegularExpression` compilation is comparatively expensive and this
    /// pattern never changes.
    private static let toolCallRegex: NSRegularExpression = {
        let pattern = #"(?<![A-Za-z0-9_$])tools\.([A-Za-z_$][A-Za-z0-9_$]*(?:\.[A-Za-z_$][A-Za-z0-9_$]*)?)\s*\("#
        // The pattern is a fixed literal validated by this type's own tests;
        // an invalid pattern here would be a broken invariant in this type's
        // own definition, not a runtime condition — the same category
        // `AgentTurn.jsonSchemaSource` documents for its own unreachable
        // failure branch.
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            preconditionFailure("TranscriptAnalyzer.toolCallRegex: invalid fixed regex pattern \"\(pattern)\".")
        }
        return regex
    }()
}

extension AgentStep {
    /// Whether this step is `.runCode` — `TranscriptAnalyzer
    /// .findAPIsPrecedesRunCode(in:)`'s `firstIndex(where:)` predicate.
    fileprivate var isRunCode: Bool {
        if case .runCode = self { return true }
        return false
    }

    /// Whether this step is `.findAPIs` — `TranscriptAnalyzer
    /// .findAPIsPrecedesRunCode(in:)`'s `contains(where:)` predicate.
    fileprivate var isFindAPIs: Bool {
        if case .findAPIs = self { return true }
        return false
    }
}
