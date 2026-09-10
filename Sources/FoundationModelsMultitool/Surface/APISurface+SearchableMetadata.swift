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
/// transcript for every selected entry, and the text the retrieval tier
/// tokenizes and embeds.
///
/// `renderSummaryBlock()` is `summaryBlock`: the same banner, then the
/// tool's description alone. The registry seeds the selection tier's prefix
/// from this text (`MetadataIndex.summaryBlock(forID:)`), so the forked
/// selection session reads one description per tool and no signature text,
/// while the main session still gets the full block of each selected id.
///
/// ## Why the retrieval tier reads the full block, measured
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
/// off, so the ranking is the retrieval tier's alone. Measured 2026-09-10,
/// and repeated: nothing on this path samples, so both runs printed the
/// same numbers to the digit.
///
///   setting                  group          rank 1   top 3   mean best
///   block/block              agentSurface     9/10   10/10        1.10
///   block/block              heldOut         10/15   13/15        1.87
///   description/description  agentSurface     9/10   10/10        1.10
///   description/description  heldOut          8/15   14/15        1.80
///   block/description        agentSurface    10/10   10/10        1.00
///   block/description        heldOut          6/15   12/15        2.13
///
/// "rank 1" counts the queries whose first answer is a path a reader
/// declared correct, "top 3" the queries that hold one in the first three
/// places, and "mean best" is the mean place of the best declared path.
/// Every declared path of every query ranked somewhere in all three
/// settings, so no setting lost a query outright.
///
/// **The choice: the full block, for the keyword index and the embedder
/// alike — the shipped conformance below, unchanged.** The card suspected
/// the embedder was the weak half, because a vector of a description plus a
/// TypeScript signature is not a vector of what the tool does. The
/// held-out group refutes that: swapping the embedder alone to the
/// description is the worst of the three settings there, on all three
/// counts (6 against 10 at rank 1, 12 against 13 in the top three, a mean
/// of 2.13 against 1.87). It wins only on the ten queries a coding agent
/// wrote while hunting for these very tools, which are thick with the
/// words the signature carries. The group written from a task description
/// alone is the one that says anything about a query nobody has seen, and
/// there the split loses.
///
/// The description-for-both setting is the one that reads a little better
/// on the held-out group (14 in the top three against 13, a mean of 1.80
/// against 1.87), and it costs half as much to embed: the nine blocks are
/// 18,720 characters against 9,057 characters of summary block. It is
/// still not taken, for a reason no ranking can outweigh. `renderBlock()`
/// holds three jobs at once in this registry — the keyword text, the
/// embedded text, and the text `SearchToolsTool` splices verbatim into the
/// main session — so a consumer cannot narrow the retrieval halves without
/// also stripping the signature from the text the main model is handed,
/// which is exactly what it needs to write the call. The gain is inside
/// one rank place; the loss would be the call site.
///
/// So the registry, not this file, is where a different answer would have
/// to start, and registry card `^kh2ttmm` asks for it: one text for the
/// verbatim splice, and seams for the keyword text and the embedded text
/// apart from it. Until those seams exist, this conformance is the whole
/// of the decision, and it is now a measured one rather than a default.
extension APISurface.Entry: SearchableMetadata {
    /// This entry's fully-qualified `tools.*` call path, used as its
    /// unique identifier within the catalog.
    public var id: String { path }

    /// The rendered content block for this entry.
    public func renderBlock() -> String { block }

    /// The banner and the description of this entry, for the selection
    /// prompt.
    public func renderSummaryBlock() -> String { summaryBlock }
}
