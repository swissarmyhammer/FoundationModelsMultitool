import Foundation
import FoundationModels
import FoundationModelsExtras
import FoundationModelsMetadataRegistry

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
/// `MultiTool.Registry.makeSessionTools(selection:embedder:sampleSession:)`,
/// which presents it before `runCode`.
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
    static let trace = CallTrace(category: "SearchTools")

    /// Where this tool reads the catalog it searches.
    private enum Catalog: Sendable {
        /// One searcher, built before this tool, that never changes.
        case fixed(searcher: MetadataSearcher<APISurface.Entry>, limit: Int)

        /// The holder this tool shares with the `runCode` mounted beside it.
        /// Each call reads the holder's current bundle, so a swap at the
        /// submission boundary reaches discovery and execution at the same
        /// tick. `limit` is `nil` for "every entry of the current registry".
        case shared(holder: MultiTool.RegistryHolder, limit: Int?)
    }

    /// The error a call throws when the shared holder's bundle was built
    /// with no discovery searcher.
    ///
    /// A bundle built with `DiscoverySearch.none` has none; only
    /// `makeSessionToolsAndStaging` builds the bundle a `searchTools` shares,
    /// and it always configures one. So this is a programming error, and it
    /// is thrown, not hidden by a searcher built on the fly.
    struct DiscoverySearcherMissing: Error {}

    /// The catalog this tool searches.
    private let catalog: Catalog

    /// How to generate and validate this tool's runnable sample, or `nil` for
    /// the signatures-only result.
    private let sample: SampleSnippetConfig?

    /// Creates a `searchTools` tool over an already-built `searcher`, in
    /// whatever mode that searcher was assembled in.
    ///
    /// The searcher `makeSearcher(over:selection:embedder:)` builds for
    /// `init(registry:selection:embedder:limit:sampleSession:)` comes
    /// through here as well, and a test's scripted or keyword-only searcher
    /// comes through here too.
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
        self.catalog = .fixed(searcher: searcher, limit: limit)
        self.sample = sample
    }

    /// Creates a `searchTools` tool that reads the catalog of `holder` at
    /// each call — the tool `makeSessionToolsAndStaging` mounts beside the
    /// `runCode` that shares the same holder.
    ///
    /// - Parameters:
    ///   - holder: the box whose current bundle every call searches. Its
    ///     bundle must carry a discovery searcher — see
    ///     `DiscoverySearch.configured`.
    ///   - limit: the maximum number of matches to request per call, or
    ///     `nil` for the entry count of the registry current at the call.
    ///   - sample: how to generate and validate the runnable sample snippet,
    ///     or `nil` for the signatures-only result.
    init(
        holder: MultiTool.RegistryHolder,
        limit: Int? = nil,
        sample: SampleSnippetConfig? = nil
    ) {
        self.catalog = .shared(holder: holder, limit: limit)
        self.sample = sample
    }

    /// The searcher over `entries` a `searchTools` tool forwards to, in
    /// `.auto` mode: selection when `selection` is configured, retrieval
    /// alone otherwise.
    ///
    /// The one place a discovery searcher is built. `init(registry:...)`
    /// builds one here for a fixed catalog, and `MultiTool.RegistryBundle`
    /// builds one here for each bundle of a shared holder.
    ///
    /// **Why the catalog is not embedded here.** A bundle is built
    /// synchronously: `RegistryBundle.init` runs under the holder's lock at
    /// every surface swap, and `makeSessionToolsAndStaging` starts no task of
    /// its own (`SurfaceRefresher.swift` states that rule). Embedding a
    /// catalog is an `async` call on a model. The registry reconciles the two
    /// itself: a `MetadataSearcher` built synchronously with an embedder
    /// embeds every not-yet-embedded entry inside its **first** `search`, one
    /// time, and every later search finds the work done. Until that first
    /// search the catalog is keyword-searchable, which is what the registry
    /// promises of an index that is still catching up.
    ///
    /// A searcher built with no embedder skips the step and stays what it
    /// was: BM25 and trigram alone, with the registry reporting
    /// `.embeddingUnavailable` on each search. A transient embed failure
    /// leaves the searcher keyword-only for the life of its bundle — the
    /// registry marks the catch-up done on every exit — and the next surface
    /// swap builds a fresh bundle that embeds again.
    ///
    /// - Parameters:
    ///   - entries: the catalog to index.
    ///   - selection: the selection tier, or `nil` for retrieval alone.
    ///   - embedder: the embedder the searcher ranks with from its first
    ///     search on, or `nil` for keyword-only ranking.
    /// - Returns: the searcher.
    static func makeSearcher(
        over entries: [APISurface.Entry], selection: SelectionConfig?, embedder: (any TextEmbedding)?
    ) -> MetadataSearcher<APISurface.Entry> {
        MetadataSearcher(
            index: MetadataIndex(items: entries), mode: .auto, embedder: embedder, selection: selection)
    }

    /// The searcher and the limit one call uses, read at the call.
    ///
    /// - Returns: the searcher to forward to, and the maximum number of
    ///   matches to request.
    /// - Throws: ``DiscoverySearcherMissing`` when a shared holder's bundle
    ///   carries no discovery searcher.
    private func resolveCatalog() throws -> (searcher: MetadataSearcher<APISurface.Entry>, limit: Int) {
        switch catalog {
        case .fixed(let searcher, let limit):
            return (searcher, limit)
        case .shared(let holder, let limit):
            let bundle = holder.current
            guard let searcher = bundle.discoverySearcher else { throw DiscoverySearcherMissing() }
            return (searcher, limit ?? bundle.registry.surface.entries.count)
        }
    }

    /// Creates a `searchTools` tool over a registry, with the models the host
    /// picked.
    ///
    /// This path builds its searcher in `.auto` mode, never `.selection`. With
    /// no selection tier configured, `.auto` answers by retrieval alone, with
    /// no session and no tokens. Discovery then degrades, instead of requiring
    /// a second model call by construction.
    ///
    /// The selection tier is made here, one time, for the ids of the whole
    /// catalog. The tier's session factory takes the instructions alone as of
    /// the ranker's `34fe8d4`, so a host that limits the output with a
    /// grammar builds one grammar over the whole catalog. Over budget, the
    /// tier prompts one slice of the catalog at a time while that grammar
    /// still permits every id in the catalog. That is safe: the tier's own
    /// `.unknownSelectedId` filter drops an id outside the slice the prompt
    /// carried. Under `capacityCharacterLimit` the over-budget path never
    /// runs.
    ///
    /// - Parameters:
    ///   - registry: the catalog whose entries become the searcher's
    ///     catalog, and whose ids `selection` receives.
    ///   - selection: makes the selection tier for the catalog ids, or `nil`
    ///     to leave the selection tier unconfigured — `.auto` then always
    ///     answers via retrieval alone. See ``SelectionFactory``.
    ///   - embedder: the embedder the searcher ranks with, or `nil` (the
    ///     default) for keyword-only ranking, which the registry reports on
    ///     every search as `no embedder configured`. The catalog is embedded
    ///     at the first search, never at this call — see
    ///     ``makeSearcher(over:selection:embedder:)``.
    ///   - limit: the maximum number of matches to request per call. Defaults
    ///     to `nil`, which resolves to `registry.surface.entries.count` — so
    ///     nothing the searcher legitimately matched is ever truncated.
    ///   - sampleSession: makes the session the sample snippet is generated
    ///     on, or `nil` (the default) to leave sample generation unconfigured
    ///     — this tool then answers with the signatures alone, exactly as it
    ///     always has. Back it with a model that is not the model of the
    ///     session that calls `searchTools` — see ``SessionFactory``. The
    ///     session must mount no tools: it writes a snippet, it does not
    ///     execute one.
    /// - Throws: what `selection` throws while it builds the selection tier.
    public init(
        registry: MultiTool.Registry,
        selection: SelectionFactory?,
        embedder: (any TextEmbedding)? = nil,
        limit: Int? = nil,
        sampleSession: SessionFactory? = nil
    ) throws {
        self.init(
            searcher: Self.makeSearcher(
                over: registry.surface.entries,
                selection: try Self.makeSelection(selection, ids: registry.surface.entries.map(\.path)),
                embedder: embedder),
            limit: limit ?? registry.surface.entries.count,
            sample: Self.makeSample(sessionFactory: sampleSession)
        )
    }

    /// Runs one `searchTools(task)` call.
    ///
    /// - Parameter arguments: the plain-language goal to search for.
    /// - Returns: the text describing the matched tool-functions, led by a
    ///   validated runnable snippet when one was generated — see
    ///   `format(task:matches:sample:)`.
    /// - Throws: whatever `searcher.search(intent:limit:)` throws, and
    ///   ``DiscoverySearcherMissing`` from a shared holder with no discovery
    ///   searcher. An error of the selection session comes out of the search
    ///   unchanged, so the model reads it as the error of this call, and not
    ///   as an empty selection. Sample generation never throws out of here: a
    ///   candidate that fails the gate yields no sample, and an error of the
    ///   sample session yields a note beside the signatures — see
    ///   ``SampleOutcome``.
    ///
    /// Three spans, because this call has two independent model-backed steps
    /// and formatting is neither: the search (which drives the selection tier)
    /// and the sample generation (which drives a generation session) can each
    /// stall on their own, and one span over the whole call could not say
    /// which.
    public func call(arguments: SearchToolsArguments) async throws -> String {
        try await Self.trace.span("SearchToolsTool.call", detail: "task=\(arguments.task)") {
            // Read one time, at the top: the catalog of a shared holder can
            // swap at the next submission boundary, and this call searches the one
            // current when it started.
            let (searcher, limit) = try resolveCatalog()
            let matches = try await Self.trace.span(
                "SearchToolsTool.search",
                detail: "limit=\(limit)"
            ) {
                try await searcher.search(intent: arguments.task, limit: limit)
            }
            let sample = await Self.trace.span(
                "SearchToolsTool.generateSample",
                detail: "matches=\(matches.count)"
            ) {
                await generateSample(forTask: arguments.task, over: matches.map(\.item))
            }
            return Self.format(task: arguments.task, matches: matches, sample: sample)
        }
    }

    /// What the sample step of one call gave.
    enum SampleOutcome: Sendable, Equatable {
        /// A validated runnable snippet, which the result leads with.
        case snippet(String)

        /// No snippet: no generator is configured, nothing matched, or the
        /// gate rejected every candidate. The result is the signatures alone.
        case absent

        /// The generation session threw. The payload is the note the result
        /// shows beside the signatures, with the error of the session in it.
        case failed(note: String)
    }

    /// The words that start the note of a sample session that threw — see
    /// ``sampleFailureNote(describing:)``.
    static let sampleFailureLead = "searchTools did not write a sample snippet, because the sample session failed."

    /// The note a result shows when the sample session threw.
    ///
    /// The note gives the text of the error. It prefers the localized
    /// description, because a host error often puts the fix there.
    ///
    /// - Parameter error: the error of the sample session.
    /// - Returns: the note text.
    static func sampleFailureNote(describing error: any Error) -> String {
        let text = (error as? any LocalizedError)?.errorDescription ?? String(describing: error)
        return "\(sampleFailureLead) The error: \(text)"
    }

    /// Generates and validates the runnable sample for one call, over the
    /// `entries` the snippet may call.
    ///
    /// - Parameters:
    ///   - task: the plain-language goal passed to `searchTools`.
    ///   - entries: the matched catalog entries the snippet may call.
    /// - Returns: the snippet; ``SampleOutcome/absent`` when this tool has no
    ///   generator or the gate rejected every candidate; or
    ///   ``SampleOutcome/failed(note:)`` when the generation session threw.
    private func generateSample(forTask task: String, over entries: [APISurface.Entry]) async -> SampleOutcome {
        guard let sample else { return .absent }
        do {
            let snippet = try await SampleSnippet.generate(forTask: task, over: entries, using: sample)
            return snippet.map(SampleOutcome.snippet) ?? .absent
        } catch {
            return .failed(note: Self.sampleFailureNote(describing: error))
        }
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
    /// **The order of the blocks, and it is a rule.** The blocks stand in the
    /// order `matches` arrives in, and this function sorts nothing. The model
    /// reaches for the first tool it reads, so that order is the answer this
    /// package gives, and it is this:
    ///
    /// 1. Under the selection budget, the order the selection model answered
    ///    in, over the whole catalog.
    /// 2. Over the budget, where `SelectionTier` splits the catalog into
    ///    slices and prompts each one, slice by slice in catalog order, and
    ///    inside each slice the order that slice's model answered in. So a
    ///    match from an earlier slice stands above a match from a later one,
    ///    whatever either model thought of its own pick.
    /// 3. Either way, an id the model repeats is kept at its first place and
    ///    spliced one time, and the list is cut to the limit of the call
    ///    after every slice has answered.
    ///
    /// **The score is not the order key, and it cannot be.** A tier match is
    /// scored `1 / rank` by its position *in its own slice*
    /// (`SelectionTier.orderScore(rank:)`), so the first pick of every slice
    /// scores `1.0` and a sort by score could not tell the slices apart. The
    /// order above is the tier's merge order carried through
    /// `MetadataSearcher`, which maps the tier's matches one for one and
    /// never re-sorts them. `OverBudgetSelectionOrderTests` holds the rule
    /// over a real above-budget surface, and no change in the ranker is
    /// needed for it: catalog order between slices is what the tier already
    /// does.
    ///
    /// When `sample` is a snippet the runnable snippet **leads**, and the
    /// signature blocks follow it as supporting material: the deliverable is
    /// code to run, not documentation to read, so the code is what the model
    /// reads first. When it is absent the result is exactly what it has always
    /// been, down to the byte — a candidate that failed the gate, or a
    /// generator that was never configured, must never cost discovery
    /// anything. When the sample session threw, the result is the
    /// signatures-only result with the note of that error before the footer:
    /// the model still gets the signatures, and the fault stays visible.
    ///
    /// - Parameters:
    ///   - task: the plain-language goal passed to `searchTools`, echoed in the
    ///     header line.
    ///   - matches: the searcher's decoded result.
    ///   - sample: what the sample step gave. Defaults to
    ///     ``SampleOutcome/absent``, the signatures-only result.
    /// - Returns: the formatted text.
    static func format(
        task: String, matches: [Match<APISurface.Entry>], sample: SampleOutcome = .absent
    ) -> String {
        guard !matches.isEmpty else {
            return "searchTools(\"\(task)\") found no matching functions."
        }
        let blocks = matches
            .map { match in "\(match.item.block)\nExample: \(match.item.qualifiedExample)" }
            .joined(separator: "\n\n")
        let signaturesOnly = "searchTools(\"\(task)\") found:\n" + blocks + "\n\n"
        switch sample {
        case .snippet(let snippet):
            return "searchTools(\"\(task)\") wrote this snippet for that task:\n\n\(snippet)\n\n"
                + "\(runSampleFooter)\n\n\(signaturesHeading)\n" + blocks
        case .absent:
            return signaturesOnly + nextStepFooter
        case .failed(let note):
            return signaturesOnly + "\(note)\n\n\(nextStepFooter)"
        }
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
    public var mount: ToolMount? { .synchronous }
}
