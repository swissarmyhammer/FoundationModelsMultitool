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
/// `renderBlock()` is `block`: the `// tools.<path>` banner plus verbatim
/// `descriptor.source` — the same text `FindAPITool` splices, verbatim,
/// into the main agent's transcript for every selected entry.
/// `renderSummaryBlock()` is left at the protocol's default (identical to
/// `renderBlock()`): descriptor blocks are already compact, so there's no
/// shorter summary to offer.
extension APISurface.Entry: SearchableMetadata {
    /// This entry's fully-qualified `tools.*` call path, used as its
    /// unique identifier within the catalog.
    public var id: String { path }

    /// The rendered content block for this entry.
    public func renderBlock() -> String { block }
}
