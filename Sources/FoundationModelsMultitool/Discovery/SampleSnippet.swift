import Foundation
import FoundationModelsMetadataRegistry

/// How `findAPIs` generates and validates the runnable sample snippet it leads
/// its result with.
///
/// Injectable and absent by default, exactly like the searcher's selection
/// tier: a host that supplies no config gets the signatures-only result
/// `findAPIs` has always returned, byte for byte, and a test supplies a
/// scripted session instead of a model.
public struct SampleSnippetConfig: Sendable {
    /// How many turns the generation session gets in total, the first attempt
    /// included — two retries after the opening try.
    ///
    /// Bounded because the gate feeds every failure back into the same session
    /// as its next turn. Without a ceiling, a generator that cannot satisfy
    /// the gate would keep being asked; with one, discovery falls back to the
    /// signatures alone.
    public static let defaultAttemptLimit = 3

    /// The wall-clock ceiling for the sandbox that parses and dry-runs a
    /// candidate.
    ///
    /// Small on purpose: nothing real runs, every mock resolves immediately,
    /// and this budget is spent inside a `findAPIs` call the model is waiting
    /// on. A candidate that cannot finish in it is reported as a failure and
    /// fed back.
    public static let defaultCheckTimeLimit: TimeInterval = 2.0

    /// Opens the generation session, given the instructions to run it under.
    ///
    /// The session must mount **no tools** — it writes a snippet, it does not
    /// execute one, and a session holding `findAPIs` could call `findAPIs`
    /// from inside a `findAPIs` call. `RoutedLLM.makeSession(instructions:)`
    /// mounts none by default, which is how the production wiring satisfies
    /// this.
    ///
    /// Every turn of one generation attempt — the opening task and each
    /// repair — goes to the same returned session, so a failure it is told
    /// about is a failure it can see its own previous snippet for.
    public let makeSession: @Sendable (String) -> any AgentSession

    /// The sandbox a candidate's syntax check and typed-mock dry run run in.
    public let interpreter: any Interpreter

    /// How many turns one generation gets in total, the first attempt
    /// included.
    public let attemptLimit: Int

    /// Creates a sample-generation config.
    ///
    /// - Parameters:
    ///   - makeSession: opens the generation session for a set of
    ///     instructions. Must mount no tools.
    ///   - interpreter: the sandbox a candidate is parsed and dry-run in.
    ///     Defaults to a `JSCInterpreter` bounded by ``defaultCheckTimeLimit``.
    ///   - attemptLimit: how many turns one generation gets in total.
    ///     Defaults to ``defaultAttemptLimit``.
    public init(
        makeSession: @escaping @Sendable (String) -> any AgentSession,
        interpreter: any Interpreter = JSCInterpreter(timeLimit: SampleSnippetConfig.defaultCheckTimeLimit),
        attemptLimit: Int = SampleSnippetConfig.defaultAttemptLimit
    ) {
        self.makeSession = makeSession
        self.interpreter = interpreter
        self.attemptLimit = attemptLimit
    }
}

/// Generates a candidate `runCode` snippet for one `findAPIs` query, validates
/// it deterministically, and repairs it in-band until it passes or the attempts
/// run out.
///
/// ## Why this exists
///
/// `findAPIs` used to answer with signatures and an instruction to go write a
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
/// A generator error, a timeout, exhausted attempts, or no matched entries all
/// yield `nil`, and `findAPIs` then answers with the signatures exactly as it
/// always has. An unvalidated candidate is never returned.
enum SampleSnippet {
    /// Generates and validates a sample snippet for `task` over `entries`.
    ///
    /// - Parameters:
    ///   - task: the plain-language goal the caller passed to `findAPIs`.
    ///   - entries: the matched catalog entries the snippet may use — the only
    ///     `tools.*` paths it is allowed to name.
    ///   - config: how to open the generation session, and what to check with.
    /// - Returns: the validated snippet, or `nil` when no candidate passed the
    ///   gate.
    static func generate(
        forTask task: String,
        over entries: [APISurface.Entry],
        using config: SampleSnippetConfig
    ) async -> String? {
        guard !entries.isEmpty else { return nil }
        let session = config.makeSession(instructions(over: entries))
        var prompt = openingPrompt(forTask: task)
        for _ in 0..<max(1, config.attemptLimit) {
            guard let reply = try? await session.respond(to: prompt) else { return nil }
            switch await verdictOffCooperativePool(on: reply, over: entries, using: config) {
            case .accepted(let snippet):
                return snippet
            case .rejected(let feedback):
                prompt = feedback
            }
        }
        return nil
    }

    /// What one checked generator reply earned.
    private enum Verdict: Sendable {
        /// The reply carried a snippet that cleared every check.
        case accepted(String)

        /// The reply failed a check; the payload is the feedback to send back
        /// as the session's next turn.
        case rejected(String)
    }

    /// Runs the gate without blocking the cooperative pool.
    ///
    /// Both checks the gate performs are synchronous and blocking:
    /// `Interpreter.checkSyntax(of:)` parses inline, and
    /// `TypedMockDryRun.apiUsageFailure(in:against:using:)` blocks until the
    /// mocked snippet finishes or the sandbox's watchdog ends it. Called
    /// directly from this `async` context, that would tie up whichever
    /// cooperative-pool thread is running the enclosing `findAPIs` call for the
    /// whole check. Dispatching onto an elastic GCD queue and suspending
    /// instead means this function *suspends* rather than *blocks* — the same
    /// "never block the caller" treatment `MultiTool` gives the real
    /// `runCode` path.
    ///
    /// - Parameters:
    ///   - reply: the generator's raw reply text.
    ///   - entries: the matched catalog entries the snippet may use.
    ///   - config: the checking sandbox and session factory.
    /// - Returns: the accepted snippet, or the feedback to send back.
    private static func verdictOffCooperativePool(
        on reply: String,
        over entries: [APISurface.Entry],
        using config: SampleSnippetConfig
    ) async -> Verdict {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: verdict(on: reply, over: entries, using: config))
            }
        }
    }

    /// Runs the whole gate over one generator reply.
    ///
    /// - Parameters:
    ///   - reply: the generator's raw reply text.
    ///   - entries: the matched catalog entries the snippet may use.
    ///   - config: the checking sandbox and session factory.
    /// - Returns: the accepted snippet, or the feedback to send back.
    private static func verdict(
        on reply: String,
        over entries: [APISurface.Entry],
        using config: SampleSnippetConfig
    ) -> Verdict {
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
        let usageFailure = TypedMockDryRun.apiUsageFailure(
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
    /// text `findAPIs` shows the model — so the snippet is written against the
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
    /// - Parameter task: the plain-language goal passed to `findAPIs`.
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
        return "That snippet calls tools.\(invented), which does not exist. "
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
