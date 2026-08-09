import FoundationModels
import FoundationModelsMetadataRegistry
import FoundationModelsRouter

/// The arguments `FindAPIsTool.call(arguments:)` accepts — the plain-language
/// goal a `LanguageModelSession`'s native tool-calling loop passes when it
/// decides to call `findAPIs`.
@Generable
public struct FindAPIsArguments: Sendable {
    @Guide(
        description: "Describe the task in plain language. Returns the tool-functions for that task, "
            + "each with its typed signature and a runnable example."
    )
    public var task: String

    /// Creates `findAPIs`'s arguments with the given task description.
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

/// plan.md Component 8 (Discovery) — `findAPIs` as its own real
/// `FoundationModels.Tool` conformer, independently constructible and
/// registerable directly alongside `MultiTool` in a native
/// `LanguageModelSession(tools: try registry.makeSessionTools(librarian:))`,
/// fully decoupled from the retired `MultiToolAgent` hand-rolled ReAct loop
/// and its turn machinery. That vending call is how a host should mount the
/// pair — it presents this tool *before* `runCode`, so the model reads
/// "discover what exists" before "execute code" when it picks its opening
/// move (see `MultiTool.Registry.makeSessionTools(librarian:)`).
///
/// `call(arguments:)` forwards every `findAPIs(task)` call to a
/// `MetadataSearcher<APISurface.Entry>` running in `.auto` mode (plan.md §7):
/// cheap retrieval (BM25/trigram/cosine signals fused by RRF) when no
/// selection tier is configured, retrieval-then-LLM-selection over the
/// narrowed candidates when one is — never `.selection` unconditionally, so
/// discovery degrades gracefully instead of requiring a second model call by
/// construction.
///
/// The searcher's selection tier (when configured) answers *what* is
/// relevant — ids only, grammar-enforced against the current candidate set
/// via `idEnumGrammar(ids:)` (the registry's `SelectionTier`, generalizing
/// Multitool's own former `Librarian`) — and `FindAPIsTool` owns *how that
/// answer reaches the caller* — splicing each selected entry's `Match.item
/// .block` **verbatim** (never re-derived or re-rendered) plus its runnable,
/// namespace-qualified example, so the model reads exactly what the
/// searcher matched.
public struct FindAPIsTool: Tool {
    /// This tool's `Tool`-protocol name, always `"findAPIs"`.
    public let name = "findAPIs"

    /// This tool's `Tool`-protocol description, presented to the model as
    /// usage instructions for `findAPIs`.
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
    /// conversational state ("if you have not called findAPIs in this
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
        This is how you use your tools. findAPIs and runCode together reach every
        function this session has, including the user's own data. The set of
        functions is loaded dynamically and changes from session to session, so
        findAPIs is what tells you the current set.

        Call findAPIs at least once in every session, passing the user's own request
        as the query, before you answer it. Until you have called it you do not know
        what this session mounts. Narrow follow-up searches come after that one, not
        instead of it.

        Assume any user request needs these functions. Almost all of them do. Call
        findAPIs first, before you answer and before you ask the user for anything.
        Describe in plain language what you are trying to accomplish. You get back
        the few relevant tool-functions, each with its typed signature, purpose,
        and a runnable example.

        Search here instead of asking the user, and instead of naming a function
        yourself. Call findAPIs once per kind of data you need, and again whenever
        the request still needs a function you do not hold yet.

        Then write one runCode snippet calling those exact tools.* paths, and answer
        from what that snippet returns.

        Worked example.

        findAPIs("read a document's title") returns:

            // tools.getDocument
            declare function getDocument(id: string): Promise<{ title: string }>

        The request also needs the editor's name and no function for that came back,
        so findAPIs("who last edited a document") returns:

            // tools.getRevision
            declare function getRevision(id: string): Promise<{ editor: string }>

        Both functions are in hand, so one runCode snippet finishes the task:

            const doc = await tools.getDocument("d-17");
            const rev = await tools.getRevision(doc.latestRevisionId);
            return { title: doc.title, editor: rev.editor };

        When findAPIs returns no relevant function for the request, say so and name
        the capability that is missing.

        Only a request that is pure arithmetic or string work needs no functions at
        all. Run a runCode snippet and return the result.
        """

    /// The catalog searcher every `findAPIs` call forwards to — runs in
    /// `.auto` mode (plan.md §7): retrieval-only when no selection tier is
    /// configured, retrieval-then-selection when one is.
    private let searcher: MetadataSearcher<APISurface.Entry>

    /// The maximum number of matches to request per `search(intent:limit:)`
    /// call — typically the catalog's own entry count, so nothing the model
    /// legitimately selected from the full candidate set is ever truncated.
    private let limit: Int

    /// How to generate and validate the runnable sample this tool leads its
    /// result with, or `nil` to answer with the signatures alone.
    ///
    /// Absent by default, exactly like the searcher's selection tier: a host
    /// that supplies nothing here gets the result `findAPIs` has always
    /// returned, byte for byte.
    private let sample: SampleSnippetConfig?

    /// Creates a `findAPIs` tool over an already-built `searcher`.
    ///
    /// The test-facing/low-level entry point: a caller (production or test)
    /// that has already assembled a `MetadataSearcher` — with or without a
    /// selection tier, in whatever mode it chose — wires it in directly. Used
    /// by `init(registry:librarian:limit:)` below, and by tests driving a
    /// scripted searcher through the internal `AgentSession` seam.
    ///
    /// - Parameters:
    ///   - searcher: the searcher to forward every `findAPIs(task)` call to.
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

    /// Creates a `findAPIs` tool bound to a resolved Router profile's
    /// generation slot for its selection tier — the production, independently
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
    ///     argument, which is what keeps `findAPIs` off the generation
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
                RoutedAgentSession(session: librarian.makeGuidedSession(grammar: grammar, instructions: instructions))
            })
        }
        let sample: SampleSnippetConfig? = sampleGenerator.map { generator in
            SampleSnippetConfig(makeSession: { instructions in
                RoutedAgentSession(session: generator.makeSession(instructions: instructions))
            })
        }
        self.init(
            searcher: MetadataSearcher(items: registry.surface.entries, mode: .auto, selection: selection),
            limit: limit ?? registry.surface.entries.count,
            sample: sample
        )
    }

    /// Runs one `findAPIs(task)` call: searches `searcher`, then formats its
    /// result into this tool's `Output`.
    ///
    /// - Parameter arguments: the plain-language goal to search for.
    /// - Returns: the text describing the matched tool-functions, led by a
    ///   validated runnable snippet when one was generated — see
    ///   `format(task:matches:sample:)`.
    /// - Throws: whatever `searcher.search(intent:limit:)` throws. Sample
    ///   generation never throws out of here: a failure in it yields no
    ///   sample, and discovery answers with the signatures alone.
    public func call(arguments: FindAPIsArguments) async throws -> String {
        let matches = try await searcher.search(intent: arguments.task, limit: limit)
        let snippet = await generateSample(forTask: arguments.task, over: matches.map(\.item))
        return Self.format(task: arguments.task, matches: matches, sample: snippet)
    }

    /// Generates and validates the runnable sample for one call, or answers
    /// `nil` when this tool has no generator configured or the gate rejected
    /// every candidate.
    ///
    /// - Parameters:
    ///   - task: the plain-language goal passed to `findAPIs`.
    ///   - entries: the matched entries the snippet may call.
    /// - Returns: the validated snippet, or `nil`.
    private func generateSample(forTask task: String, over entries: [APISurface.Entry]) async -> String? {
        guard let sample else { return nil }
        return await SampleSnippet.generate(forTask: task, over: entries, using: sample)
    }

    /// The imperative next-step footer a signatures-only result ends with.
    ///
    /// The result of a `findAPIs` call is the moment of maximum model
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
    /// `FindAPIsToolTests` reads it here in both directions — asserting it is
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

    /// The imperative next-step footer a result carrying a validated sample
    /// ends with, in place of ``nextStepFooter``.
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

    /// The heading the signature blocks sit under when a sample leads the
    /// result, so their demotion to supporting material is stated rather than
    /// merely implied by position.
    private static let signaturesHeading = "The functions that snippet calls:"

    /// Formats a search result into the text describing the matched
    /// tool-functions — one block per matched function, each entry's
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
    ///   - task: the plain-language goal passed to `findAPIs`, echoed in the
    ///     header line.
    ///   - matches: the searcher's decoded result.
    ///   - sample: the validated runnable snippet to lead with, or `nil` for
    ///     the signatures-only result. Defaults to `nil`.
    /// - Returns: the formatted text.
    static func format(task: String, matches: [Match<APISurface.Entry>], sample: String? = nil) -> String {
        guard !matches.isEmpty else {
            return "findAPIs(\"\(task)\") found no matching functions."
        }
        let blocks = matches
            .map { match in "\(match.item.block)\nExample: \(match.item.qualifiedExample)" }
            .joined(separator: "\n\n")
        guard let sample else {
            return "findAPIs(\"\(task)\") found:\n" + blocks + "\n\n\(nextStepFooter)"
        }
        return "findAPIs(\"\(task)\") wrote this snippet for that task:\n\n\(sample)\n\n"
            + "\(runSampleFooter)\n\n\(signaturesHeading)\n" + blocks
    }
}
