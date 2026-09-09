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
