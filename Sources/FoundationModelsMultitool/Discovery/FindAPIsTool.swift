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

    /// This tool's `Tool`-protocol description, presented to the model as
    /// usage instructions for `findAPIs`.
    public let description = """
        Describe, in plain language, what you are trying to accomplish. Returns the few
        tool-functions relevant to that task — each with its typed signature, purpose,
        and a runnable example — so you can write a runCode snippet. Prefer this over
        guessing function names.
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
    /// selection tier through `librarian`'s guided sessions, constrained to
    /// exactly `registry.surface`'s entry paths via `idEnumGrammar(ids:)` —
    /// mirroring the "librarian on the flash slot" split, decoupled from any
    /// main loop's own turn machinery. Per `SelectionConfig`'s own
    /// cached-root/`fork()`-per-call contract, `librarian`'s own `RoutedLLM
    /// .makeGuidedSession(grammar:instructions:)` — not `LanguageModelSession`
    /// — backs every selection call, since the FoundationModels interop path
    /// doesn't expose the Router's cache-level `fork()`.
    ///
    /// - Parameters:
    ///   - registry: the catalog whose entries become the searcher's catalog
    ///     and, when `librarian` is supplied, constrain the selection
    ///     grammar.
    ///   - librarian: the resolved `RoutedLLM` every selection session runs
    ///     on, or `nil` to leave the selection tier unconfigured — `.auto`
    ///     then always answers via retrieval alone.
    ///   - limit: the maximum number of matches to request per call. Defaults
    ///     to `nil`, which resolves to `registry.surface.entries.count` — so
    ///     nothing the searcher legitimately matched is ever truncated.
    /// - Throws: whatever `idEnumGrammar(ids:)` throws while deriving the
    ///   selection tier's id-enum grammar — not expected in practice (see
    ///   that function's documentation), and only reachable when `librarian`
    ///   is non-`nil`.
    public init(registry: MultiTool.Registry, librarian: RoutedLLM?, limit: Int? = nil) throws {
        let selection: SelectionConfig? = try librarian.map { librarian in
            let grammar = try idEnumGrammar(ids: registry.surface.entries.map(\.path))
            return SelectionConfig(model: { instructions in
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

    /// Formats a search result into the text describing the matched
    /// tool-functions — one block per matched function, each entry's
    /// verbatim `Match.item.block` — the `// tools.<path>` banner naming its
    /// fully-qualified call path, followed by its unmodified `declare
    /// function`/JSDoc source (`ToolDescriptor` fields are always
    /// unqualified; `path`/`block` carry the namespace — see
    /// `APISurface.swift`'s `Entry` documentation) — followed by its runnable
    /// example, qualified the same way via `Entry.qualifiedExample` so this
    /// trailer never shows a different, bare call than the one `block`'s own
    /// embedded `@example` line just displayed.
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
    }
}
