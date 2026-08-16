import Foundation
import FoundationModels
import FoundationModelsMetadataRegistry
import FoundationModelsRouter

/// The arguments a `searchTools` call carries.
///
/// The plain-language goal a `LanguageModelSession`'s native tool-calling loop
/// passes when it decides to call `searchTools`.
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
    /// Explicit for the same reason as every other public `@Generable` type's
    /// initializer in this package (e.g. `RunCodeArguments.init`): a
    /// `public` struct's synthesized memberwise initializer is only
    /// `internal`-accessible.
    ///
    /// - Parameter task: the plain-language goal to search for.
    public init(task: String) {
        self.task = task
    }
}

/// The discovery tool a session searches for its mounted functions.
///
/// plan.md Component 8 (Discovery): `searchTools` as its own real
/// `FoundationModels.Tool` conformer, independently constructible and
/// registerable directly alongside `MultiTool` in a native
/// `LanguageModelSession(tools: try registry.makeSessionTools(librarian:))`,
/// fully decoupled from the retired `MultiToolAgent` hand-rolled ReAct loop
/// and its turn machinery. That vending call is how a host should mount the
/// pair — it presents this tool *before* `runCode`, so the model reads
/// "discover what exists" before "execute code" when it picks its opening
/// move (see `MultiTool.Registry.makeSessionTools(librarian:)`).
///
/// Every call forwards to a searcher running in `.auto` mode.
///
/// `call(arguments:)` hands each `searchTools(task)` call to a
/// `MetadataSearcher<APISurface.Entry>` in `.auto` mode (plan.md §7):
/// cheap retrieval (BM25/trigram/cosine signals fused by RRF) when no
/// selection tier is configured, retrieval-then-LLM-selection over the
/// narrowed candidates when one is — never `.selection` unconditionally, so
/// discovery degrades gracefully instead of requiring a second model call by
/// construction.
///
/// The searcher's selection tier (when configured) answers *what* is
/// relevant — ids only, grammar-enforced against the current candidate set
/// via `idEnumGrammar(ids:)` (the registry's `SelectionTier`, generalizing
/// Multitool's own former `Librarian`) — and `SearchToolsTool` owns *how that
/// answer reaches the caller* — splicing each selected entry's `Match.item
/// .block` **verbatim** (never re-derived or re-rendered) plus its runnable,
/// namespace-qualified example, so the model reads exactly what the
/// searcher matched.
public struct SearchToolsTool: Tool {
    /// This tool's `Tool`-protocol name, always `"searchTools"`.
    public let name = "searchTools"

    /// This tool's usage instructions, as the model reads them.
    ///
    /// The `Tool`-protocol description presented for `searchTools`.
    ///
    /// Together with `MultiTool.description` this carries the **whole**
    /// behavioral contract a session needs. Mounting the two tools is the
    /// entire integration: a `Tool` conformance's description is serialized
    /// into the prompt on every turn, whereas a session instruction is
    /// optional and a host may not pass one, so nothing load-bearing may
    /// live outside these two strings.
    ///
    /// Ordered the way the surveyed code-execution tool prompts order theirs
    /// (Cloudflare `@cloudflare/codemode`, HuggingFace `smolagents`,
    /// Microsoft TaskWeaver, Vercel `ai-sdk-tool-code-execution`): the
    /// numbered procedure comes first, before any rule, because the
    /// procedure *is* the discovery mandate; each rule then carries its own
    /// mechanical consequence, which is specification rather than
    /// persuasion. The anti-guessing rule triggers on checkable
    /// conversational state ("if you have not called searchTools in this
    /// conversation") rather than on the model's own confidence — a
    /// confident model always passes an "if you are unsure" test, which is
    /// the failure this wording exists to close.
    ///
    /// Persona-free by design: no "you are a helpful assistant" framing,
    /// just clear information on how to call the tools — the only part that
    /// carries weight.
    ///
    /// The worked example uses `getDocument`/`getRevision` deliberately.
    /// Fixture-shaped example data (weather, trips) would hand a model the
    /// very value a gated scenario grades on, which passes with zero calls.
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
    /// A discovery call declares both of its clocks unbounded
    /// (`detachmentClocks(from:)` below), which is right — slow is not broken —
    /// but it also means nothing above this tool will ever interrupt a search
    /// that has stopped making progress. These spans are the only thing that
    /// tells a slow search from a stalled one.
    private static let trace = CallTrace(category: "SearchTools")

    /// The catalog searcher every `searchTools` call forwards to.
    ///
    /// Runs in `.auto` mode (plan.md §7): retrieval-only when no selection tier
    /// is configured, retrieval-then-selection when one is.
    private let searcher: MetadataSearcher<APISurface.Entry>

    /// The maximum number of matches to request per search call.
    ///
    /// Typically the catalog's own entry count, so nothing the model
    /// legitimately selected from the full candidate set is ever truncated.
    private let limit: Int

    /// How to generate and validate this tool's runnable sample.
    ///
    /// `nil` answers with the signatures alone.
    ///
    /// Absent by default, exactly like the searcher's selection tier: a host
    /// that supplies nothing here gets the result `searchTools` has always
    /// returned, byte for byte.
    private let sample: SampleSnippetConfig?

    /// Creates a `searchTools` tool over an already-built `searcher`.
    ///
    /// The test-facing/low-level entry point: a caller (production or test)
    /// that has already assembled a `MetadataSearcher` — with or without a
    /// selection tier, in whatever mode it chose — wires it in directly. Used
    /// by `init(registry:librarian:limit:)` below, and by tests driving a
    /// scripted searcher through the internal `AgentSession` seam.
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
    /// Uses the resolved profile's generation slot for its selection tier — the
    /// production, independently
    /// constructible entry point plan.md calls for: no dependency on any
    /// agent loop or turn machinery, just a registry and an optional
    /// selection-tier backing.
    ///
    /// Builds a `.auto`-mode `MetadataSearcher` over `registry.surface
    /// .entries`: when `librarian` is `nil`, `.auto` degrades to `.retrieval`
    /// (no session, no tokens); when it's supplied, `.auto` drives its
    /// selection tier through `librarian`'s guided sessions — mirroring the
    /// "librarian on the flash slot" split, decoupled from any main loop's
    /// own turn machinery. Per `SelectionConfig`'s own cached-root/`fork()`
    /// -per-call contract, `librarian`'s own `RoutedLLM.makeGuidedSession
    /// (grammar:instructions:)` — not `LanguageModelSession` — backs every
    /// selection call, since the FoundationModels interop path doesn't
    /// expose the Router's cache-level `fork()`.
    ///
    /// The selection grammar is no longer built here: `SelectionConfig
    /// .model` now receives the current call's `Grammar` alongside its
    /// instructions, so the `SelectionTier` supplies the correctly-scoped
    /// `idEnumGrammar(ids:)` per call (the whole catalog under budget, the
    /// top-M candidates over budget) — this closure just threads that
    /// grammar into `makeGuidedSession`.
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
    /// Searches `searcher`, then formats the result into this tool's `Output`.
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

    /// Generates and validates the runnable sample for one call.
    ///
    /// Answers `nil` when this tool has no generator configured or the gate
    /// rejected every candidate.
    ///
    /// - Parameters:
    ///   - task: the plain-language goal passed to `searchTools`.
    ///   - entries: the matched entries the snippet may call.
    /// - Returns: the validated snippet, or `nil`.
    private func generateSample(forTask task: String, over entries: [APISurface.Entry]) async -> String? {
        guard let sample else { return nil }
        return await SampleSnippet.generate(forTask: task, over: entries, using: sample)
    }

    /// The imperative next-step footer a signatures-only result ends with.
    ///
    /// The result of a `searchTools` call is the moment of maximum model
    /// attention, and describing functions without prescribing the next
    /// action leaves the two dominant failure modes open: announcing a plan
    /// instead of acting, and answering from priors instead of from a
    /// snippet's real return value. The footer closes both, and its
    /// composition clause ("compose multiple calls in that one snippet")
    /// is what multi-step tasks need spelled out — the models that fail
    /// them stop after describing step one.
    /// The sentence that orders a model to write a snippet from scratch.
    ///
    /// The only place it is written. ``nextStepFooter`` opens with it, and
    /// `SearchToolsToolTests` reads it here in both directions — asserting it is
    /// present when no sample was generated, and absent when one was. The
    /// absent case carries that proof alone: "Call runCode now" appears in
    /// both this footer and ``runSampleFooter``, so only this sentence tells
    /// them apart. A copy of it in the test would keep holding after a
    /// reword, whichever footer shipped.
    static let writeSnippetInstruction = "Now write one runCode snippet"

    private static let nextStepFooter = """
        \(writeSnippetInstruction) that calls these exact tools.* paths. Put every \
        call the task needs in that one snippet, passing values between them with \
        variables, and return the result. Call runCode now. Answer only from what it \
        returns.
        """

    /// The next-step footer a sample-carrying result ends with.
    ///
    /// Used in place of ``nextStepFooter``.
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
    /// embedded `@example` line just displayed. A non-empty result closes
    /// with `nextStepFooter`.
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

extension SearchToolsTool: DetachmentParameterProviding {
    /// The per-call clocks a discovery call carries: neither of them a limit.
    ///
    /// **Discovery is synchronous.** A model cannot write a snippet without
    /// knowing which `tools.*` paths exist, so nothing can be done while a
    /// discovery call is in flight — there is no concurrent work for a detached
    /// one to overlap with. Parking it turns a blocking dependency into one the
    /// model has to go and collect, which is strictly worse than waiting.
    ///
    /// **And a timeout is not backgrounding.** The two clocks answer different
    /// questions: `waitSeconds` asks when a call should become asynchronous, and
    /// the answer here is never; `timeout` asks how long the work may run before
    /// it is cancelled and reported as failed. For a prerequisite read the second
    /// answer is also "no limit", because *slow is not broken*. A timeout would
    /// report a failure for a search that is merely still working, and the model
    /// would act on a lie: it would be told discovery failed when discovery is
    /// running. Only a real error — the searcher throwing, the selection model
    /// failing — should reach the model, and those already do, as errors.
    ///
    /// Measured, both limits fired in turn. At the mount's stock 5-second wait
    /// every discovery call parked, and the model never obtained the catalog:
    /// three gated runs ended `invoked=[] returned=[]` answering "I don't have
    /// access to real-time weather data". With the wait raised, the 120-second
    /// work clock cancelled it instead —
    /// `DetachingToolError.timedOut(tool: "searchTools", timeoutSeconds: 120.0)`,
    /// the turn dead in its first call.
    ///
    /// **This is a workaround, not the declaration.** What this tool needs to say
    /// is `DetachConfiguration.Mode.runToCompletion` with no timeout — the mode
    /// Router already mounts for inner `tools.*` calls. `mode` is read from the
    /// wrap-time configuration (`DetachingTool.swift:384`) and
    /// `DetachmentParameterProviding` exposes only the two clocks, so a tool
    /// cannot declare its own mode today. Two very large numbers express the
    /// intent; a per-tool mode would state it. Filed on Router's `w8dzvee`.
    ///
    /// - Parameter arguments: the call's arguments, unread — every discovery call
    ///   is a prerequisite, so every one gets the same answer.
    /// - Returns: both clocks, set beyond any real search.
    public func detachmentClocks(
        from arguments: GeneratedContent
    ) -> (waitSeconds: TimeInterval?, timeout: TimeInterval?) {
        (Self.unlimitedSeconds, Self.unlimitedSeconds)
    }

    /// The value both of a discovery call's clocks are set to.
    ///
    /// Not `.infinity`, which the run plane clamps anyway, and not a tuned
    /// figure either: it names `ToolContext.waitSecondsCeiling`, the ceiling
    /// Router itself treats as "no practical limit", so nothing here invents a
    /// second notion of unbounded and no literal can drift from it. Any real
    /// search finishes or fails long before it.
    static let unlimitedSeconds: TimeInterval = ToolContext.waitSecondsCeiling
}
