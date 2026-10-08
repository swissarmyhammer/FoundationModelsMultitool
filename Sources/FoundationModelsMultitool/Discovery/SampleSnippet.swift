import Foundation
import FoundationModels
import FoundationModelsMetadataRegistry

/// How `searchTools` generates and validates the runnable sample snippet it leads
/// its result with.
///
/// Injectable and absent by default, exactly like the searcher's selection
/// tier: a host that supplies no config gets the signatures-only result
/// `searchTools` has always returned, byte for byte, and a test supplies a
/// scripted model instead of a real one.
public struct SampleSnippetConfig: Sendable {
    /// How many turns the generation session gets in total, the first attempt
    /// included — two retries after the opening try.
    ///
    /// Bounded because the gate feeds every failure back into the same session
    /// as its next turn. Without a ceiling, a generator that cannot satisfy
    /// the gate would keep being asked; with one, discovery falls back to the
    /// signatures alone.
    public static let defaultAttemptLimit = 3

    /// The model that writes the snippet.
    ///
    /// For each generation, the library makes one new `LanguageModelSession`
    /// on this model, with the generation instructions and **no tools**. The
    /// session writes a snippet, it does not execute one, and a session that
    /// holds `searchTools` could call `searchTools` from inside a
    /// `searchTools` call.
    ///
    /// The model must not be the model of the session that calls
    /// `searchTools`, for the reason that ``SearchToolsTool/SelectionFactory``
    /// gives. When the session fails, `searchTools` shows the error as a note
    /// beside the signatures.
    ///
    /// Every turn of one generation — the opening task and each repair — goes
    /// to the same session, so a failure it is told about is a failure it can
    /// see its own previous snippet for.
    public let model: any LanguageModel

    /// The sandbox a candidate's syntax check and typed-mock dry run run in.
    public let interpreter: any Interpreter

    /// How many turns one generation gets in total, the first attempt
    /// included.
    public let attemptLimit: Int

    /// Creates a sample-generation config.
    ///
    /// - Parameters:
    ///   - model: the model that writes the snippet.
    ///   - interpreter: the sandbox a candidate is parsed and dry-run in.
    ///     Defaults to a `JSCInterpreter`. The check has no timeout: it is
    ///     simple and runs in process.
    ///   - attemptLimit: how many turns one generation gets in total.
    ///     Defaults to ``defaultAttemptLimit``.
    public init(
        model: any LanguageModel,
        interpreter: any Interpreter = JSCInterpreter(),
        attemptLimit: Int = SampleSnippetConfig.defaultAttemptLimit
    ) {
        self.model = model
        self.interpreter = interpreter
        self.attemptLimit = attemptLimit
    }
}

/// Generates a candidate `runCode` snippet for one `searchTools` query, validates
/// it deterministically, and repairs it in-band until it passes or the attempts
/// run out.
///
/// ## Why this exists
///
/// `searchTools` used to answer with signatures and an instruction to go write a
/// snippet. That handoff is where the recorded failures happen: announcing a
/// plan and stopping, one call then narration, invented paths. This closes the
/// handoff by doing the writing here, where the answer can be *checked* before
/// the model ever sees it.
///
/// ## The gate
///
/// Four checks, cheapest and most certain first, so a failure feeds back the
/// most specific message available:
///
/// 1. **Extraction.** The instructions demand exactly one fenced code block
///    and nothing else, and the absence of a fence is itself a failure — so a
///    chatty reply is rejected and fed back rather than half-parsed into a
///    snippet.
/// 2. **Syntax.** `Interpreter.checkSyntax(of:)` parses the candidate,
///    installing nothing and executing nothing.
/// 3. **Paths.** Every `tools.*` path the candidate names must be one of the
///    matched entries — not merely somewhere in the catalog.
/// 4. **API usage.** `TypedMockDryRun` runs the candidate against typed mocks
///    of the matched entries, so wrong arity, wrong argument types, missing
///    required fields, undeclared field reads, and a forgotten `await` all
///    surface with the message the snippet itself produced.
///
/// Every failure is fed back into the **same** session as its next turn — a
/// repair loop rather than one-shot-and-discard, which is the in-band-repair
/// technique the code-mode survey found strongest in the field.
///
/// ## Never blocking discovery
///
/// A candidate that fails the gate, exhausted attempts, or no matched entries
/// all yield `nil`, and `searchTools` then answers with the signatures exactly
/// as it always has. An unvalidated candidate is never returned.
///
/// ## Never hiding a session error
///
/// An error of the generation session is not a failed candidate. It propagates
/// from ``generate(forTask:over:using:)``, and `searchTools` shows it to the
/// model as a note beside the signatures. A silent `nil` would hide a fault
/// that only the host can correct: for example, a session on the model of the
/// calling session, which a host that queues its work per model refuses.
enum SampleSnippet {
    /// Generates and validates a sample snippet for `task` over `entries`.
    ///
    /// - Parameters:
    ///   - task: the plain-language goal the caller passed to `searchTools`.
    ///   - entries: the matched catalog entries the snippet may use — the only
    ///     `tools.*` paths it is allowed to name.
    ///   - config: the model that writes the snippet, and what to check with.
    /// - Returns: the validated snippet, or `nil` when no candidate passed the
    ///   gate.
    /// - Throws: what the generation session throws. The error is not
    ///   changed.
    static func generate(
        forTask task: String,
        over entries: [APISurface.Entry],
        using config: SampleSnippetConfig
    ) async throws -> String? {
        guard !entries.isEmpty else { return nil }
        let session = LanguageModelSession(model: config.model, instructions: instructions(over: entries))
        var prompt = openingPrompt(forTask: task)
        for _ in 0..<max(1, config.attemptLimit) {
            let reply = try await respond(to: prompt, in: session)
            switch await verdict(on: reply, over: entries, using: config) {
            case .accepted(let snippet):
                return snippet
            case .rejected(let feedback):
                prompt = feedback
            }
        }
        return nil
    }

    /// The role that the span of each turn of a generation session carries.
    static let sessionRole = "sampleSnippet"

    /// Sends one turn to the generation session, inside a span.
    ///
    /// The turn can wait a long time, for example while the model loads at
    /// the first request, and a suspended call shows in no stack. The enter
    /// record of the span shows a turn that never ends (see
    /// ``MultitoolTelemetry/SpanName``). The span records the length of the
    /// prompt and of the reply, never their text: a prompt carries the task
    /// of the caller.
    ///
    /// - Parameters:
    ///   - prompt: the text of the turn.
    ///   - session: the generation session.
    /// - Returns: the text of the reply.
    /// - Throws: what the session throws. The span records it first.
    static func respond(to prompt: String, in session: LanguageModelSession) async throws -> String {
        try await MultitoolTelemetry.traced(
            .agentSessionRespond, attributes: [.sessionRole: sessionRole, .promptCharacters: prompt.count]
        ) { span in
            let reply = try await session.respond(to: prompt).content
            span.attributes[MultitoolTelemetry.AttributeKey.outputCharacters.rawValue] = reply.count
            return reply
        }
    }

    /// What one checked generator reply earned.
    private enum Verdict: Sendable {
        /// The reply carried a snippet that cleared every check.
        case accepted(String)

        /// The reply failed a check; the payload is the feedback to send back
        /// as the session's next turn.
        case rejected(String)
    }

    /// Runs the whole gate over one generator reply.
    ///
    /// The dry run awaits `Interpreter.run`, which holds no thread while it
    /// waits (see the event-loop documentation of `JSCInterpreter`). The
    /// syntax check parses inline: it executes nothing, so it is short CPU
    /// work, not a wait.
    ///
    /// - Parameters:
    ///   - reply: the generator's raw reply text.
    ///   - entries: the matched catalog entries the snippet may use.
    ///   - config: the checking sandbox.
    /// - Returns: the accepted snippet, or the feedback to send back.
    private static func verdict(
        on reply: String,
        over entries: [APISurface.Entry],
        using config: SampleSnippetConfig
    ) async -> Verdict {
        guard let snippet = fencedBlock(in: reply) else {
            return .rejected(missingFenceFeedback)
        }
        do {
            try config.interpreter.checkSyntax(of: snippet)
        } catch {
            return .rejected(syntaxFeedback(describing: error))
        }
        let matchedPaths = entries.map(\.path)
        let known = Set(matchedPaths)
        let invented = UnknownToolHint.referencedToolPaths(in: snippet).first { !known.contains($0) }
        if let invented {
            return .rejected(unknownPathFeedback(named: invented, matchedPaths: matchedPaths))
        }
        let usageFailure = await TypedMockDryRun.apiUsageFailure(
            in: snippet,
            against: entries,
            using: config.interpreter
        )
        if let usageFailure {
            return .rejected(apiUsageFeedback(describing: usageFailure))
        }
        return .accepted(snippet)
    }

    // MARK: - Extraction

    /// The Markdown code-fence marker the generator is told to reply with.
    private static let fence = "```"

    /// Extracts the one fenced code block from `reply`, or `nil` when it has
    /// none.
    ///
    /// Deterministic rather than lenient: the opening fence's own line may
    /// carry an info string (`js`, `javascript`) and nothing else, recognized
    /// as such only when every character of it is alphanumeric or `+-_`, so a
    /// first line of real code is never mistaken for a language tag and
    /// discarded. A reply with no fence at all is a failure that feeds back,
    /// which is what makes this safe to keep strict.
    ///
    /// - Parameter reply: the generator's raw reply text.
    /// - Returns: the block's contents, trimmed, or `nil`.
    private static func fencedBlock(in reply: String) -> String? {
        guard let open = reply.range(of: fence) else { return nil }
        let afterOpen = reply[open.upperBound...]
        guard let close = afterOpen.range(of: fence) else { return nil }
        var body = afterOpen[..<close.lowerBound]
        if let newline = body.firstIndex(of: "\n"), isInfoString(body[..<newline]) {
            body = body[body.index(after: newline)...]
        }
        let snippet = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return snippet.isEmpty ? nil : snippet
    }

    /// Whether `text` is a code fence's info string rather than code.
    ///
    /// - Parameter text: the remainder of the opening fence's own line.
    /// - Returns: `true` when every character is alphanumeric or one of
    ///   `+`, `-`, `_`, which is the form a language tag takes rather than the
    ///   form a JavaScript statement takes.
    private static func isInfoString(_ text: Substring) -> Bool {
        text.trimmingCharacters(in: .whitespaces)
            .allSatisfy { $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "_" }
    }

    // MARK: - Instructions and prompts

    /// The output envelope every instruction and every piece of feedback
    /// closes with.
    ///
    /// Named once because all five carry it: the extraction step is only
    /// deterministic if the envelope is restated on every turn, and restating
    /// it from one constant is what keeps the five wordings from drifting.
    private static let envelope =
        "Reply with one fenced code block containing only the snippet, and nothing else — "
        + "no prose, no explanation, no second block."

    /// The instructions the generation session runs under.
    ///
    /// Carries the matched entries' own rendered blocks verbatim — the same
    /// text `searchTools` shows the model — so the snippet is written against the
    /// real signatures rather than a paraphrase of them. No worked example and
    /// no sample data: an example built from a fixture-shaped call would hand
    /// the generator, and through it the model, a value a scenario grades on.
    ///
    /// - Parameter entries: the matched catalog entries.
    /// - Returns: the instruction text.
    private static func instructions(over entries: [APISurface.Entry]) -> String {
        """
        You write one JavaScript snippet that carries out a task with the functions below. \
        The snippet runs in a sandbox where those functions are already bound under `tools.*`.

        \(entries.map(\.block).joined(separator: "\n\n"))

        Write whatever JavaScript the task needs — variables, loops, map/filter, \
        sorting, comparison, arithmetic, string work. The functions fetch data; the \
        JavaScript around them does the work of answering the task.

        Rules.
        Every tools.* path you call must be one listed above; a path that is not \
        listed comes back as an error, not as data.
        Put `await` on every call; without it you hold a promise, not a value.
        Pass values between calls with variables.
        Read only the fields a declared return type has; reading any other field \
        is an error.
        End with `return` on the value that answers the task.

        \(envelope)
        """
    }

    /// The first turn's prompt: the task, and nothing else.
    ///
    /// - Parameter task: the plain-language goal passed to `searchTools`.
    /// - Returns: the opening prompt.
    private static func openingPrompt(forTask task: String) -> String {
        """
        Write the snippet for this task.

        \(task)
        """
    }

    // MARK: - The four feedback messages

    /// Feedback for a reply that carried no fenced code block.
    private static let missingFenceFeedback = "Your reply had no fenced code block. \(envelope)"

    /// Feedback for a candidate that does not parse — the engine's own message
    /// verbatim, including the line it blames, because that is the most
    /// specific thing anyone knows about the failure.
    ///
    /// - Parameter error: the error `Interpreter.checkSyntax(of:)` threw.
    /// - Returns: the feedback text.
    private static func syntaxFeedback(describing error: any Error) -> String {
        let reported = (error as? InterpreterError)?.description ?? String(describing: error)
        return "That snippet does not parse. JavaScript reported: \(reported) Fix it. \(envelope)"
    }

    /// Feedback for a candidate naming a `tools.*` path outside the matched
    /// set, naming every path that does exist.
    ///
    /// - Parameters:
    ///   - invented: the path the candidate named, without its `tools.` prefix.
    ///   - matchedPaths: every matched entry's path, in catalog order.
    /// - Returns: the feedback text.
    private static func unknownPathFeedback(named invented: String, matchedPaths: [String]) -> String {
        let available = matchedPaths.map { "tools.\($0)" }.joined(separator: ", ")
        return "That snippet calls tools.\(invented), which \(UnknownToolHint.missingPathPhrase). "
            + "These are the only paths that exist: \(available). Rewrite it using those. \(envelope)"
    }

    /// Feedback for a candidate that threw when its calls were checked against
    /// the declared signatures — the thrown message verbatim.
    ///
    /// - Parameter failure: the message `TypedMockDryRun` reported.
    /// - Returns: the feedback text.
    private static func apiUsageFeedback(describing failure: String) -> String {
        "That snippet failed when its calls were checked against the declared signatures: "
            + "\(failure) Fix it. \(envelope)"
    }
}
