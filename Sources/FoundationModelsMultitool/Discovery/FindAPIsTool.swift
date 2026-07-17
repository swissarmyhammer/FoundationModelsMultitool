import FoundationModels
import FoundationModelsMetadataRegistry
import FoundationModelsRouter

/// The arguments `FindAPIsTool.call(arguments:)` accepts — the plain-language
/// goal a `LanguageModelSession`'s native tool-calling loop passes when it
/// decides to call `findAPIs`.
@Generable
public struct FindAPIsArguments: Sendable {
    @Guide(
        description: "Describe, in plain language, what you are trying to accomplish. Returns the few "
            + "tool-functions relevant to that task."
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
/// `LanguageModelSession(tools: [multiTool, findAPIsTool])`, fully decoupled
/// from the retired `MultiToolAgent` hand-rolled ReAct loop and its turn
/// machinery.
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

    /// The package-owned session instruction that makes the findAPIs +
    /// runCode tool pair behave — ready to use whole as a
    /// `LanguageModelSession`'s `instructions`, or to append to a caller's
    /// own instructions.
    ///
    /// The tool descriptions already carry the full behavioral contract, so
    /// this is deliberately not a duplicate of them — it is the one thing a
    /// description structurally *can't* deliver: the upfront, first-move
    /// stance. Empirically (recorded on task `k4mj1gm`, real-model gated
    /// runs), descriptions alone leave a model announcing a plan and
    /// stopping without acting — small models collapse to 1/4, and even a
    /// capable model over-refuses the trivial single-tool case — because a
    /// tool description is read when the model is already choosing a tool,
    /// not when it decides its opening move. This instruction supplies that
    /// opening move directly: real access, findAPIs first, then runCode, act
    /// rather than narrate, answer only from returned data. Adding it takes
    /// the same model from 1/4 to 4/4.
    ///
    /// Persona-free by design: no "you are a helpful assistant" framing,
    /// just clear information on how to call the tools — the only part that
    /// carries weight.
    public static let sessionInstructions = """
        You have real, working access to the user's live data and services through your \
        tools, including anything real-time. Never refuse or claim you lack access to \
        current data: instead, always call findAPIs first to discover the exact \
        functions for the task, then call runCode to invoke them under tools.* — make \
        the calls, do not merely describe what you would do — and answer only from what \
        the tools return, never from your own assumptions.
        """

    /// This tool's `Tool`-protocol description, presented to the model as
    /// usage instructions for `findAPIs`.
    ///
    /// Deliberately carries the whole behavioral contract a session needs —
    /// the access framing (real access, the user's own data behind the
    /// catalog, never ask or refuse instead of searching) and the workflow
    /// (search, then one runCode snippet over the exact discovered paths,
    /// answer only from returned data). The package must be drop-in usable
    /// with no bespoke system prompt: registering `findAPIs` + `runCode`
    /// alone is the product surface, so the "system prompt" lives here.
    public let description = """
        This is how you use your tools. You are connected to the user's live data and \
        services, and you have real, working access: every function you might need — \
        including the user's own data such as their trip, bookings, and other live \
        values — is behind this catalog. Before you answer, and before you ask the user \
        for anything, call findAPIs first: describe in plain language what you are \
        trying to accomplish, and you get back the few relevant tool-functions, each \
        with its typed signature, purpose, and a runnable example. Search here instead \
        of asking the user, and instead of guessing function names, once per kind of \
        data you need. The tools genuinely execute and return real data, so never \
        refuse for lack of access — you have access through them. Then write one \
        runCode snippet that calls those exact tools.* paths to get your answer. If \
        findAPIs truly finds no relevant function for the request, say so honestly \
        rather than invent an answer.
        """

    /// The catalog searcher every `findAPIs` call forwards to — runs in
    /// `.auto` mode (plan.md §7): retrieval-only when no selection tier is
    /// configured, retrieval-then-selection when one is.
    private let searcher: MetadataSearcher<APISurface.Entry>

    /// The maximum number of matches to request per `search(intent:limit:)`
    /// call — typically the catalog's own entry count, so nothing the model
    /// legitimately selected from the full candidate set is ever truncated.
    private let limit: Int

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
    public init(searcher: MetadataSearcher<APISurface.Entry>, limit: Int) {
        self.searcher = searcher
        self.limit = limit
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
    /// - Throws: reserved for API stability across selection-tier wiring
    ///   changes; the current construction path has no fallible step.
    public init(registry: MultiTool.Registry, librarian: RoutedLLM?, limit: Int? = nil) throws {
        let selection: SelectionConfig? = librarian.map { librarian in
            SelectionConfig(model: { instructions, grammar in
                RoutedAgentSession(session: librarian.makeGuidedSession(grammar: grammar, instructions: instructions))
            })
        }
        self.init(
            searcher: MetadataSearcher(items: registry.surface.entries, mode: .auto, selection: selection),
            limit: limit ?? registry.surface.entries.count
        )
    }

    /// Runs one `findAPIs(task)` call: searches `searcher`, then formats its
    /// result into this tool's `Output`.
    ///
    /// - Parameter arguments: the plain-language goal to search for.
    /// - Returns: the text describing the matched tool-functions — see
    ///   `format(task:matches:)`.
    /// - Throws: whatever `searcher.search(intent:limit:)` throws.
    public func call(arguments: FindAPIsArguments) async throws -> String {
        let matches = try await searcher.search(intent: arguments.task, limit: limit)
        return Self.format(task: arguments.task, matches: matches)
    }

    /// The imperative next-step footer every non-empty result ends with.
    ///
    /// The result of a `findAPIs` call is the moment of maximum model
    /// attention, and describing functions without prescribing the next
    /// action leaves the two dominant failure modes open: announcing a plan
    /// instead of acting, and answering from priors instead of from a
    /// snippet's real return value. The footer closes both, and its
    /// composition clause ("compose multiple calls in that one snippet")
    /// is what multi-step tasks need spelled out — the models that fail
    /// them stop after describing step one.
    private static let nextStepFooter = """
        Now write one runCode snippet that calls these exact tools.* paths — compose \
        multiple calls in that one snippet with variables as needed — and return the \
        real result. Do not describe a plan and do not answer from memory: call \
        runCode now, and answer only from what it returns.
        """

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
    /// - Parameters:
    ///   - task: the plain-language goal passed to `findAPIs`, echoed in the
    ///     header line.
    ///   - matches: the searcher's decoded result.
    /// - Returns: the formatted text.
    static func format(task: String, matches: [Match<APISurface.Entry>]) -> String {
        guard !matches.isEmpty else {
            return "findAPIs(\"\(task)\") found no matching functions."
        }
        let blocks = matches.map { match in
            "\(match.item.block)\nExample: \(match.item.qualifiedExample)"
        }
        return "findAPIs(\"\(task)\") found:\n" + blocks.joined(separator: "\n\n")
            + "\n\n\(nextStepFooter)"
    }
}
