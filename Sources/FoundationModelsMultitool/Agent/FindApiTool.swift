import FoundationModelsMetadataRegistry

/// plan.md Component 8 (the other half of "Discovery"): forwards the agent
/// loop's `findAPIs(task)` step to a `MetadataSearcher<ApiSurface.Entry>`
/// running in `.selection` mode, formatting its verbatim `Match`es into the
/// text spliced into the next main-agent turn.
///
/// The searcher's selection tier answers *what* is relevant — ids only,
/// grammar-enforced against the current candidate set (the registry's
/// `SelectionTier`, generalizing Multitool's own former `Librarian`) — and
/// `FindApiTool` owns *how that answer reaches the main agent's
/// transcript* — splicing each selected entry's `Match.item.block`
/// **verbatim** (never re-derived or re-rendered) plus its runnable
/// example, so the main model reads exactly what the registry selected.
struct FindApiTool: Sendable {
    /// The catalog searcher this tool forwards every `findAPIs(task)` call
    /// to — expected to run in `.selection` mode (`.retrieval`/`.auto` would
    /// still format correctly, but wouldn't honor a guided model's ids-only
    /// selection contract).
    private let searcher: MetadataSearcher<ApiSurface.Entry>

    /// The maximum number of matches to request per `search(intent:limit:)`
    /// call — typically the catalog's own entry count, so nothing the model
    /// legitimately selected from the full candidate set is ever truncated.
    private let limit: Int

    /// Creates a `findAPIs` dispatcher over `searcher`.
    ///
    /// - Parameters:
    ///   - searcher: the searcher to forward every `findAPIs(task)` call to.
    ///   - limit: the maximum number of matches to request per call.
    init(searcher: MetadataSearcher<ApiSurface.Entry>, limit: Int) {
        self.searcher = searcher
        self.limit = limit
    }

    /// Dispatches one `findAPIs(task)` step: searches `searcher`, then
    /// formats its result into the text to feed back into the main agent's
    /// transcript.
    ///
    /// - Parameter task: the plain-language goal the model passed to
    ///   `findAPIs`.
    /// - Returns: the text to splice into the next main-agent turn.
    /// - Throws: whatever `searcher.search(intent:limit:)` throws.
    func dispatch(task: String) async throws -> String {
        let matches = try await searcher.search(intent: task, limit: limit)
        return Self.format(task: task, matches: matches)
    }

    /// Formats a `.selection`-mode search result into the text spliced into
    /// the main agent's transcript — one block per selected function, each
    /// entry's verbatim `Match.item.block` — the `// tools.<path>` banner
    /// naming its fully-qualified call path, followed by its unmodified
    /// `declare function`/JSDoc source (`ToolDescriptor` fields are always
    /// unqualified; `path`/`block` carry the namespace — see
    /// `ApiSurface.swift`'s `Entry` documentation) — followed by its
    /// runnable example, qualified the same way via `Entry.qualifiedExample`
    /// so this trailer never shows a different, bare call than the one
    /// `block`'s own embedded `@example` line just displayed.
    ///
    /// - Parameters:
    ///   - task: the plain-language goal the model passed to `findAPIs`,
    ///     echoed in the header line so the transcript reads naturally
    ///     alongside `runCode`'s own result feedback (mirrors
    ///     `MultiToolAgent`'s existing `runCode result:` framing).
    ///   - matches: the searcher's decoded result.
    /// - Returns: the formatted text.
    static func format(task: String, matches: [Match<ApiSurface.Entry>]) -> String {
        guard !matches.isEmpty else {
            return "findAPIs(\"\(task)\") found no matching functions."
        }
        let blocks = matches.map { match in
            "\(match.item.block)\nExample: \(match.item.qualifiedExample)"
        }
        return "findAPIs(\"\(task)\") found:\n" + blocks.joined(separator: "\n\n")
    }
}
