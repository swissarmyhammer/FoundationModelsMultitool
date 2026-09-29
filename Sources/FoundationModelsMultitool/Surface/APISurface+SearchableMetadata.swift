import FoundationModelsMetadataRegistry

/// Conforms `APISurface.Entry` to the registry's `SearchableMetadata`
/// protocol (plan.md §4's catalog contract), so a rendered tool catalog can
/// be indexed and searched directly — no wrapper type, no re-derivation.
///
/// `id` is `path`: the fully-qualified `tools.*` call path, unique per
/// catalog (`MultiTool.Builder.build()` validates name collisions before an
/// `Entry` is ever constructed), and exactly what the selection grammar's id
/// enum and selection feedback need to name a tool by.
///
/// `renderBlock()` is `block`: the `// tools.<path>` banner plus
/// `descriptor.source` with its embedded `@example` call qualified to the
/// entry's fully-qualified `path` (see `Entry.block`/`Entry.qualify(_:)`)
/// — the same text `SearchToolsTool` splices, verbatim, into the main agent's
/// transcript for every selected entry. The keyword signals (BM25 and the
/// trigram index) also read this text, through the protocol default of
/// `renderIndexedText(from:)`.
///
/// `renderEmbeddedText(from:)` is `summaryBlock`: the embedder reads the
/// banner and the description of the tool, and no signature text.
///
/// `renderSummaryBlock()` is `summaryBlock` too. The registry seeds the
/// selection tier's prefix from this text
/// (`MetadataIndex.summaryBlock(forID:)`), so the forked selection session
/// reads one description per tool and no signature text, while the main
/// session still gets the full block of each selected id.
///
/// ## Why the embedder reads the description, measured
///
/// Card `^0z0te3n` gave the selection prompt the description alone and left
/// the retrieval half at the protocol default, so the keyword index and the
/// embedder still read the whole block. Card `^kvefc5z` asked whether that
/// half is correct, and forbade a guess.
///
/// `RetrievalTextSurfaceDiscoveryTests` answers it. Three settings over the
/// same nine-entry files-and-shell surface, the same embedder and the same
/// twenty-five queries — the ten of card `^zqz1zan` and the fifteen
/// held-out queries of card `^kn9ay20` — with the selection tier switched
/// off, so the ranking is the retrieval tier's alone. The setting names the
/// keyword text first and the embedded text second.
///
/// The first measurement, on 2026-09-10, is not valid. The Router batch
/// embed then gave every text of a batch except the longest a pad token in
/// its pooled vector (Router card `^nmmnn7k`, fixed in FoundationModelsRouter
/// 2a79f92), so the cosine signal of each setting measured that defect. Card
/// `^a9ketxt` measured again with the fixed embedder: one run on 2026-09-28
/// (Router 2a79f92) and one run on 2026-09-29 (Router f497700). Nothing on
/// this path samples, and the two runs printed the same numbers to the
/// digit:
///
///   setting                  group          rank 1   top 3   mean best
///   block/block              agentSurface     9/10   10/10        1.10
///   block/block              heldOut          9/15   14/15        1.87
///   description/description  agentSurface     9/10   10/10        1.10
///   description/description  heldOut         11/15   14/15        1.60
///   block/description        agentSurface    10/10   10/10        1.00
///   block/description        heldOut         11/15   14/15        1.67
///
/// "rank 1" counts the queries whose first answer is a path a reader
/// declared correct, "top 3" the queries that hold one in the first three
/// places, and "mean best" is the mean place of the best declared path.
/// Every declared path of every query ranked somewhere in all three
/// settings, so no setting lost a query outright.
///
/// **The choice: the full block for the keyword signals, and the summary
/// block for the embedder — the `block/description` setting.** The reasons:
///
/// - The embedder must read the description. The full block for the
///   embedder (`block/block`) is the worst setting of the three on the
///   held-out group: 9 of 15 at rank 1 against 11, and a mean of 1.87
///   against 1.60 and 1.67. It is not better than `block/description` on any
///   count of either group. The 2026-09-10 table said the opposite, and that
///   was the padding defect.
/// - The keyword signals keep the full block. `block/description` and
///   `description/description` are equal on the top-3 count of both groups.
///   Over all twenty-five queries, `block/description` puts 21 queries at
///   rank 1 against 20, and both have a mean best of 1.40 (35 places over 25
///   queries). `block/description` also puts 38 of the 45 declared paths in
///   the first three places, against 36. The held-out mean of
///   `description/description` is better by one place on one query, and
///   that is smaller than the agent-surface difference in the other
///   direction. A query that names a parameter or a word of the signature
///   finds it only in the full block.
/// - The embedder reads less text. The nine blocks are 18,956 characters
///   against 9,198 characters of summary block, so the one catalog embed at
///   the first search is approximately half as large.
///
/// The 2026-09-10 text kept the full block for the embedder also because
/// `renderBlock()` then held three jobs at once — the keyword text, the
/// embedded text and the verbatim splice. Registry card `^kh2ttmm` added
/// `renderIndexedText(from:)` and `renderEmbeddedText(from:)`, so this
/// conformance changes the embedded text alone, and `SearchToolsTool` still
/// splices the full block, with the signature the main model needs to write
/// the call.
///
/// `MultiTool.RegistryBundle/hintSearcher` ranks over the same entries, so
/// the hint tier also embeds the summary block.
extension APISurface.Entry: SearchableMetadata {
    /// This entry's fully-qualified `tools.*` call path, used as its
    /// unique identifier within the catalog.
    public var id: String { path }

    /// The rendered content block for this entry.
    public func renderBlock() -> String { block }

    /// The text the embedder embeds for this entry: the banner and the
    /// description, with no signature text.
    ///
    /// - Parameter block: this entry's `renderBlock()` output. The summary
    ///   block is not derived from it, so it is not read.
    /// - Returns: ``summaryBlock``.
    public func renderEmbeddedText(from block: String) -> String { summaryBlock }

    /// The banner and the description of this entry, for the selection
    /// prompt.
    public func renderSummaryBlock() -> String { summaryBlock }
}
