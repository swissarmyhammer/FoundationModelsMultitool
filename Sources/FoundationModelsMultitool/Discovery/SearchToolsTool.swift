import Foundation
import FoundationModels
import FoundationModelsMetadataRegistry
import FoundationModelsRouter

/// The arguments a `searchTools` call carries.
@Generable
public struct SearchToolsArguments: Sendable {
    /// The plain-language goal to search the catalog for.
    @Guide(
        description: "Describe the task in plain language. Returns the tool-functions for that task, "
            + "each with its typed signature and a runnable example."
    )
    public var task: String

    /// Creates `searchTools`'s arguments with the given task description.
    ///
    /// Explicit because a `public` struct's synthesized memberwise initializer
    /// is `internal` only.
    ///
    /// - Parameter task: the plain-language goal to search for.
    public init(task: String) {
        self.task = task
    }
}

/// The discovery tool a session searches for its mounted functions.
///
/// A host mounts this tool with
/// `MultiTool.Registry.makeSessionTools(librarian:sampleGenerator:)`, which
/// presents it before `runCode`.
///
/// The selection tier, when one is configured, answers only *what* is
/// relevant — ids, held to the current candidate set by a grammar.
/// `SearchToolsTool` owns how that answer reaches the caller: each selected
/// entry's `Match.item.block` spliced **verbatim**, never re-derived or
/// re-rendered, plus its runnable, namespace-qualified example.
public struct SearchToolsTool: Tool {
    /// This tool's `Tool`-protocol name, always `"searchTools"`.
    public let name = "searchTools"

    /// This tool's usage instructions, as the model reads them.
    ///
    /// Together with `MultiTool.description` this carries the **whole**
    /// behavioral contract a session needs. Mounting the two tools is the
    /// entire integration: a `Tool` conformance's description goes into the
    /// prompt on every turn, but a session instruction is optional and a host
    /// can supply none. So nothing load-bearing can live outside these two
    /// strings. `searchTools` owns the discovery mandate.
    ///
    /// Persona-free by design: no "you are a helpful assistant" framing, only
    /// how to call the tools.
    public let description = """
        This session's functions are mounted dynamically, and searchTools is the only
        way to see them. Call searchTools before you answer any request, passing the
        user's own request as the query; describe the task in plain language and you
        get back the relevant tool-functions, each with its typed signature, purpose,
        and a runnable example. Search again for every further capability the request
        needs, and say so and name the capability when nothing relevant comes back.
        Never name a function yourself, and never ask the user for data a function can
        fetch.
        """

    /// Where this tool's call boundaries are recorded — see ``CallTrace``.
    ///
    /// A discovery call runs to completion with no timeout at all
    /// (`mount` below), which is right — slow is not broken — but it
    /// also means nothing above this tool will ever interrupt a search that has
    /// stopped making progress. These spans are the only thing that tells a
    /// slow search from a stalled one.
    private static let trace = CallTrace(category: "SearchTools")

    /// The catalog searcher every `searchTools` call forwards to.
    private let searcher: MetadataSearcher<APISurface.Entry>

    /// The maximum number of matches to request per search call.
    private let limit: Int

    /// How to generate and validate this tool's runnable sample, or `nil` for
    /// the signatures-only result.
    private let sample: SampleSnippetConfig?

    /// Creates a `searchTools` tool over an already-built `searcher`, in
    /// whatever mode that searcher was assembled in.
    ///
    /// - Parameters:
    ///   - searcher: the searcher to forward every `searchTools(task)` call to.
    ///   - limit: the maximum number of matches to request per call.
    ///   - sample: how to generate and validate the runnable sample snippet
    ///     this tool leads its result with. Defaults to `nil` — no sample, and
    ///     the signatures-only result this tool has always returned.
    public init(
        searcher: MetadataSearcher<APISurface.Entry>,
        limit: Int,
        sample: SampleSnippetConfig? = nil
    ) {
        self.searcher = searcher
        self.limit = limit
        self.sample = sample
    }

    /// Creates a `searchTools` tool bound to a Router profile.
    ///
    /// This path builds its searcher in `.auto` mode, never `.selection`. With
    /// no selection tier configured, `.auto` answers by retrieval alone, with
    /// no session and no tokens. Discovery then degrades, instead of requiring
    /// a second model call by construction.
    ///
    /// `librarian`'s own `RoutedLLM.makeGuidedSession(grammar:instructions:)`
    /// backs every selection call, not `LanguageModelSession`, because the
    /// FoundationModels interop path does not expose the Router's cache-level
    /// `fork()` that `SelectionConfig`'s cached-root contract needs.
    ///
    /// The `SelectionTier` supplies the correctly-scoped `idEnumGrammar(ids:)`
    /// for each call — the whole catalog under budget, the top-M candidates
    /// over it. This closure only threads that grammar into
    /// `makeGuidedSession`.
    ///
    /// - Parameters:
    ///   - registry: the catalog whose entries become the searcher's
    ///     catalog and, when `librarian` is supplied, the id set the
    ///     selection tier constrains its grammar to.
    ///   - librarian: the resolved `RoutedLLM` every selection session runs
    ///     on, or `nil` to leave the selection tier unconfigured — `.auto`
    ///     then always answers via retrieval alone.
    ///   - limit: the maximum number of matches to request per call. Defaults
    ///     to `nil`, which resolves to `registry.surface.entries.count` — so
    ///     nothing the searcher legitimately matched is ever truncated.
    ///   - sampleGenerator: the resolved `RoutedLLM` the sample-snippet
    ///     generation session runs on, or `nil` to leave sample generation
    ///     unconfigured — this tool then answers with the signatures alone,
    ///     exactly as it always has. Pass the **main** generation slot rather
    ///     than the librarian's: the sample is code the model is told to run,
    ///     so its quality matters more than its cost. The session is vended
    ///     through `RoutedLLM.makeSession(instructions:)` with no `tools:`
    ///     argument, which is what keeps `searchTools` off the generation
    ///     session's own surface: it writes a snippet, it does not execute
    ///     one.
    /// - Throws: reserved for API stability across selection-tier wiring
    ///   changes; the current construction path has no fallible step.
    public init(
        registry: MultiTool.Registry,
        librarian: RoutedLLM?,
        limit: Int? = nil,
        sampleGenerator: RoutedLLM? = nil
    ) throws {
        // **The selection session must come from `librarian`, a handle other
        // than the one whose turn is calling this tool. That is a correctness
        // requirement, not a cost preference.**
        //
        // `searchTools` is invoked from inside a turn's tool body. A Router
        // session holds its own `turnLock` for the whole turn, tool rounds
        // included, and both `RoutedSession.fork(workingDirectory:)` and the
        // `transcript` getter take `await turnLock.wait()` on that same lock.
        // So a selection tier that forked *the session it is running inside*
        // would block until the turn ended, and the turn cannot end until this
        // tool returns. That is a permanent hang, and it is the exact shape of
        // Router's `^d2ptrk1`.
        //
        // What keeps this package clear of it is only that `librarian` is a
        // different handle — `profile.flash`, with a `turnLock` of its own —
        // so nothing here ever waits on the caller's lock. Measured: the
        // `SearchToolsTool.makeSelectionSession` and `AgentSession.fork` spans
        // both enter and exit inside a millisecond.
        //
        // **Router's generation-permit loan does not cover this.** That fix
        // (`^1zt7vyg`) lends a `generationGate` permit to a nested turn and
        // deliberately leaves `turnLock` alone, because `turnLock` is the
        // correctness gate — their card states that as a constraint on its own
        // fix. So forking the in-turn session would deadlock immediately, loan
        // or no loan, and no upstream change is going to soften it.
        //
        // Reusing the caller's session here looks like the natural
        // simplification — one session, one transcript, no second handle to
        // thread. It is the one change this factory must never take.
        let selection: SelectionConfig? = librarian.map { librarian in
            SelectionConfig(model: { instructions, grammar in
                // Traced, and traced *here*, because both ends of this
                // factory are opaque from outside. The call itself is
                // synchronous but not cheap — a grammar-constrained session
                // compiles its grammar — and everything the tier then does
                // with the session it returns happens behind the
                // `AgentSession` seam. See `TracedAgentSession`.
                Self.trace.span(
                    "SearchToolsTool.makeSelectionSession",
                    detail: "instructionCharacters=\(instructions.count)"
                ) {
                    TracedAgentSession(
                        wrapped: RoutedAgentSession(
                            session: librarian.makeGuidedSession(grammar: grammar, instructions: instructions)
                        ),
                        role: TracedAgentSession.selectionRole
                    )
                }
            })
        }
        let sample: SampleSnippetConfig? = sampleGenerator.map { generator in
            SampleSnippetConfig(makeSession: { instructions in
                Self.trace.span(
                    "SearchToolsTool.makeSampleSession",
                    detail: "instructionCharacters=\(instructions.count)"
                ) {
                    TracedAgentSession(
                        wrapped: RoutedAgentSession(session: generator.makeSession(instructions: instructions)),
                        role: TracedAgentSession.sampleSnippetRole
                    )
                }
            })
        }
        self.init(
            searcher: MetadataSearcher(items: registry.surface.entries, mode: .auto, selection: selection),
            limit: limit ?? registry.surface.entries.count,
            sample: sample
        )
    }

    /// Runs one `searchTools(task)` call.
    ///
    /// - Parameter arguments: the plain-language goal to search for.
    /// - Returns: the text describing the matched tool-functions, led by a
    ///   validated runnable snippet when one was generated — see
    ///   `format(task:matches:sample:)`.
    /// - Throws: whatever `searcher.search(intent:limit:)` throws. Sample
    ///   generation never throws out of here: a failure in it yields no
    ///   sample, and discovery answers with the signatures alone.
    ///
    /// Three spans, because this call has two independent model-backed steps
    /// and formatting is neither: the search (which drives the selection tier)
    /// and the sample generation (which drives a generation session) can each
    /// stall on their own, and one span over the whole call could not say
    /// which.
    public func call(arguments: SearchToolsArguments) async throws -> String {
        try await Self.trace.span("SearchToolsTool.call", detail: "task=\(arguments.task)") {
            let matches = try await Self.trace.span(
                "SearchToolsTool.search",
                detail: "limit=\(limit)"
            ) {
                try await searcher.search(intent: arguments.task, limit: limit)
            }
            let snippet = await Self.trace.span(
                "SearchToolsTool.generateSample",
                detail: "matches=\(matches.count)"
            ) {
                await generateSample(forTask: arguments.task, over: matches.map(\.item))
            }
            return Self.format(task: arguments.task, matches: matches, sample: snippet)
        }
    }

    /// Generates and validates the runnable sample for one call, over the
    /// `entries` the snippet may call.
    ///
    /// Answers `nil` when this tool has no generator configured or the gate
    /// rejected every candidate.
    private func generateSample(forTask task: String, over entries: [APISurface.Entry]) async -> String? {
        guard let sample else { return nil }
        return await SampleSnippet.generate(forTask: task, over: entries, using: sample)
    }

    /// The sentence that orders a model to write a snippet from scratch.
    ///
    /// The only place it is written. ``nextStepFooter`` opens with it, and
    /// `SearchToolsToolTests` reads it here in both directions — asserting it is
    /// present when no sample was generated, and absent when one was. The
    /// absent case carries that proof alone: "Call runCode now" appears in
    /// both ``nextStepFooter`` and ``runSampleFooter``, so only this sentence
    /// tells them apart. A copy of it in the test would keep holding after a
    /// reword, whichever footer shipped.
    static let writeSnippetInstruction = "Now write one runCode snippet"

    /// The imperative next-step footer a signatures-only result ends with.
    ///
    /// The result of a `searchTools` call is the moment of maximum model
    /// attention. Functions described without the next action prescribed leave
    /// the two dominant failure modes open: the model announces a plan instead
    /// of acting, and it answers from priors instead of from a snippet's real
    /// return value. This footer closes both. Its composition clause — put
    /// every call the task needs in that one snippet — is what multi-step
    /// tasks need spelled out, because the models that fail them stop after
    /// describing step one.
    private static let nextStepFooter = """
        \(writeSnippetInstruction) that calls these exact tools.* paths. Put every \
        call the task needs in that one snippet, passing values between them with \
        variables, and return the result. Call runCode now. Answer only from what it \
        returns.
        """

    /// The next-step footer a sample-carrying result ends with.
    ///
    /// "Now write one runCode snippet" is false once a snippet has been
    /// supplied — following it literally means discarding the sample and
    /// writing another, which throws away the whole point of generating one.
    /// So this footer points at *that* snippet, and demotes the signature
    /// blocks behind it to what they now are: the material for repairing a
    /// real error, not the material for composing a first attempt.
    ///
    /// The sample earned that framing by clearing the gate — real syntax, real
    /// paths, real arities, real field access. What can survive the gate is
    /// semantic wrongness, and `runCode`'s own repair path already handles
    /// that: the error comes back and the model fixes the snippet.
    private static let runSampleFooter = """
        Call runCode now with that snippet, and answer only from what it returns. The \
        signatures it was written against are below — read them only to fix an error \
        runCode hands back.
        """

    /// The heading the signature blocks sit under when a sample leads.
    ///
    /// Their demotion to supporting material is stated rather than merely
    /// implied by position.
    private static let signaturesHeading = "The functions that snippet calls:"

    /// Formats a search result into the text the model reads.
    ///
    /// One block per matched function, each entry's
    /// verbatim `Match.item.block` — the `// tools.<path>` banner naming its
    /// fully-qualified call path, followed by its unmodified `declare
    /// function`/JSDoc source (`ToolDescriptor` fields are always
    /// unqualified; `path`/`block` carry the namespace — see
    /// `APISurface.swift`'s `Entry` documentation) — followed by its runnable
    /// example, qualified the same way via `Entry.qualifiedExample` so this
    /// trailer never shows a different, bare call than the one `block`'s own
    /// embedded `@example` line just displayed.
    ///
    /// When `sample` is present the runnable snippet **leads**, and the
    /// signature blocks follow it as supporting material: the deliverable is
    /// code to run, not documentation to read, so the code is what the model
    /// reads first. When it is absent the result is exactly what it has always
    /// been, down to the byte — a generator that failed, timed out, or was
    /// never configured must never cost discovery anything.
    ///
    /// - Parameters:
    ///   - task: the plain-language goal passed to `searchTools`, echoed in the
    ///     header line.
    ///   - matches: the searcher's decoded result.
    ///   - sample: the validated runnable snippet to lead with, or `nil` for
    ///     the signatures-only result. Defaults to `nil`.
    /// - Returns: the formatted text.
    static func format(task: String, matches: [Match<APISurface.Entry>], sample: String? = nil) -> String {
        guard !matches.isEmpty else {
            return "searchTools(\"\(task)\") found no matching functions."
        }
        let blocks = matches
            .map { match in "\(match.item.block)\nExample: \(match.item.qualifiedExample)" }
            .joined(separator: "\n\n")
        guard let sample else {
            return "searchTools(\"\(task)\") found:\n" + blocks + "\n\n\(nextStepFooter)"
        }
        return "searchTools(\"\(task)\") wrote this snippet for that task:\n\n\(sample)\n\n"
            + "\(runSampleFooter)\n\n\(signaturesHeading)\n" + blocks
    }
}

// MARK: - Discovery is synchronous (task h773bed)

extension SearchToolsTool: BackgroundTool {
    /// The mount a discovery call carries: run to completion, under no clock.
    ///
    /// **Discovery is synchronous.** A model cannot write a snippet without
    /// knowing which `tools.*` paths exist, so nothing can be done while a
    /// discovery call is in flight — there is no concurrent work for a
    /// background one to overlap with. Backgrounding it turns a blocking
    /// dependency into one the model has to go and collect, which is strictly
    /// worse than waiting.
    ///
    /// **And a timeout is not backgrounding.** A mount answers two questions:
    /// its mode asks whether a call hands back a handle, and the answer here
    /// is never; its `timeout` asks how long the work may run before it is
    /// cancelled and reported as failed. For a prerequisite read the second
    /// answer is also "no limit", because *slow is not broken*. A timeout
    /// would report a failure for a search that is merely still working, and
    /// the model would act on a lie: it would be told discovery failed when
    /// discovery is running. Only a real error — the searcher throwing, the
    /// selection model failing — should reach the model, and those already
    /// do, as errors.
    ///
    /// Measured, both limits fired in turn. Under a mount that backgrounded
    /// slow calls, every discovery call was backgrounded, and the model never
    /// obtained the catalog: three real-model runs ended
    /// `invoked=[] returned=[]` answering "I don't have access to real-time
    /// weather data". Under the stock 120-second work clock, that clock
    /// cancelled it instead —
    /// `ToolMountError.timedOut(tool: "searchTools", timeoutSeconds: 120.0)`,
    /// the turn dead in its first call.
    ///
    /// `runCode` declares the background mount for itself, and this tool
    /// declares run-to-completion. One session, two policies, each stated by
    /// the tool it belongs to.
    public var mount: ToolMount? { .synchronousUnbounded }
}
