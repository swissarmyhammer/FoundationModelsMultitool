/// The rendered, model-agnostic tool catalog `MultiTool.Builder.build()`
/// produces (plan.md Component 7): "the rendered catalog; backs the
/// librarian prefix, `help()`/`docs()`, and a host-listable data view." That
/// "librarian prefix" is now realized by `FoundationModelsMetadataRegistry`'s
/// registry-backed selection tier (`MetadataSearcher`/`SelectionTier`),
/// which renders this same `source` as its instruction preamble.
///
/// One `ToolAPIRenderer` call per wrapped tool produces every entry's
/// `ToolDescriptor` (M2); this type layers on the *namespace* a tool was
/// added under — flat at `tools.<name>` for a standalone tool, or
/// `tools.<group>.<name>` for one added via `addGroup(named:_:)` — per
/// plan.md Resolved #5. `APISurface` itself is pure data: no model wiring,
/// no rendering logic of its own beyond composing already-rendered pieces.
public struct APISurface: Sendable, Equatable {
    /// One rendered tool in the catalog.
    public struct Entry: Sendable, Equatable {
        /// The fully-qualified path the snippet calls this tool by,
        /// relative to `tools` — `"weather"` for a standalone tool, or
        /// `"<group>.<name>"` for a grouped one. Always equal to
        /// `descriptor.name` for a standalone entry (`group == nil`), and
        /// always `"\(group).\(descriptor.name)"` for a grouped one.
        public let path: String

        /// The group this tool was added under (via
        /// `addGroup(named:_:)`), or `nil` for a standalone (flat-namespaced)
        /// tool added via `addTool(_:)`/`addTools(_:)`.
        public let group: String?

        /// The tool's own rendered descriptor, exactly as `ToolAPIRenderer`
        /// produced it — its `name`/`declaration`/`doc`/`example`/`source`
        /// are always unqualified (plan.md: "M2 always renders a flat,
        /// unqualified `name`"); `path` is what carries the namespace.
        public let descriptor: ToolDescriptor

        /// Creates a catalog entry.
        ///
        /// Explicit for the same reason as `ToolDescriptor.init` in
        /// `ToolDescriptor.swift`: a `public` struct's synthesized
        /// initializer is only `internal`-accessible, and `Entry` is a
        /// public type of the `FoundationModelsMultitool` library product
        /// that callers must be able to construct directly.
        ///
        /// - Parameters:
        ///   - path: the fully-qualified snippet call path.
        ///   - group: the owning group name, or `nil` for a standalone tool.
        ///   - descriptor: the tool's own rendered descriptor.
        public init(path: String, group: String?, descriptor: ToolDescriptor) {
            self.path = path
            self.group = group
            self.descriptor = descriptor
        }

        /// This entry's full renderable text block, as it appears in the
        /// concatenated `APISurface.source`: a `// tools.<path>` banner
        /// line naming its fully-qualified call path (so a grouped tool's
        /// namespace is visible even though `descriptor` itself never
        /// mentions it — see `path`'s documentation), followed by
        /// `descriptor.source` — its JSDoc doc comment and `declare
        /// function` signature — with its embedded `@example` line's call
        /// qualified the same way (see `qualify(_:)`), so the runnable
        /// example a reader actually sees always matches the namespace the
        /// banner just named — never the bare, unqualified call a model
        /// has no way to infer needs a group prefix prepended.
        ///
        /// `path` is safe to splice bare into a `//` comment: it's built
        /// exclusively from `descriptor.name` (already validated as a
        /// legal TypeScript identifier by `ToolAPIRenderer.render`, which
        /// throws otherwise) and, for a grouped entry, `group` (validated
        /// the same way by `MultiTool.Builder.build()` before this `Entry`
        /// is ever constructed) — neither can contain a newline or other
        /// character that could break out of a single-line comment.
        public var block: String {
            "// tools.\(path)\n\(qualify(descriptor.source))"
        }

        /// `descriptor.example` — the auto-generated, runnable example
        /// call — with its bare `tools.<name>(` call prefix qualified the
        /// same way `block`'s embedded `@example` line is, so a caller
        /// splicing this field directly (`FindAPIsTool.format`'s separate
        /// `Example: ...` trailer) never shows a different, disagreeing
        /// call than the one `block` itself displays.
        ///
        /// A no-op for a standalone entry (`path == descriptor.name`) —
        /// `descriptor.example` is returned unmodified.
        public var qualifiedExample: String {
            qualify(descriptor.example)
        }

        /// Replaces the unqualified `tools.<name>(` call prefix
        /// `ToolAPIRenderer.render`'s `exampleCall` always renders with the
        /// fully-qualified `tools.<path>(` prefix, everywhere it appears in
        /// `text` — the embedded JSDoc `@example` line inside
        /// `descriptor.source`, and `descriptor.example` itself.
        ///
        /// A targeted substitution rather than a re-render: `descriptor`
        /// (M2's flat, unqualified rendering) is never re-derived, only its
        /// one namespace-dependent call-path prefix is corrected. Safe to
        /// splice, since `descriptor.name` is validated as a legal TS
        /// identifier by `ToolAPIRenderer.render`: the replacement text can
        /// never itself break out of the surrounding JSDoc/declaration
        /// syntax. This does not guarantee the *search* substring
        /// `"tools.\(descriptor.name)("` is unique within `text` — a tool's
        /// author-supplied `description`/`@Guide` prose (also embedded
        /// verbatim in `descriptor.source`) could in principle happen to
        /// contain that exact literal substring — but the only place
        /// `ToolAPIRenderer.render` itself ever emits it is the `@example`
        /// line/`example` field this method targets, so this is a
        /// theoretical, not a practical, concern for any real generated
        /// doc. A no-op for a standalone entry, since `path ==
        /// descriptor.name` there.
        ///
        /// - Parameter text: the rendered text to qualify — either
        ///   `descriptor.source` or `descriptor.example`.
        /// - Returns: `text` with its bare call prefix qualified.
        private func qualify(_ text: String) -> String {
            text.replacingOccurrences(
                of: "tools.\(descriptor.name)(",
                with: "tools.\(path)("
            )
        }
    }

    /// Every tool in the catalog, in the order `addTool`/`addTools`/
    /// `addGroup` recorded it.
    public let entries: [Entry]

    /// Creates a rendered API surface.
    ///
    /// Explicit for the same reason as `Entry.init` above: a `public`
    /// struct's synthesized initializer is only `internal`-accessible, and
    /// `APISurface` is the public return type of `MultiTool.Builder.build()`
    /// that a host may need to assemble directly (e.g. in tests).
    ///
    /// - Parameter entries: every tool in the catalog, in catalog order.
    public init(entries: [Entry]) {
        self.entries = entries
    }

    /// The full rendered surface — every entry's `block`, in catalog
    /// order, separated by a blank line. This is what backs the
    /// registry-backed selection tier's instruction prefix
    /// (`FoundationModelsMetadataRegistry`'s `MetadataSearcher`/
    /// `SelectionTier`, prefix-cached per plan.md § "Discovery: a
    /// prefix-cached 'librarian' agent") and the in-snippet `help()`/`docs()`
    /// globals.
    public var source: String {
        entries.map(\.block).joined(separator: "\n\n")
    }

    /// Every standalone (flat-namespaced) entry, in catalog order — a
    /// convenience view for a host UI that wants to list ungrouped tools
    /// separately from grouped ones.
    public var standaloneEntries: [Entry] {
        entries.filter { $0.group == nil }
    }

    /// Every grouped entry, keyed by its group name, each group's entries
    /// kept in catalog order — a convenience view for a host UI that wants
    /// to render tools under their namespace headings.
    public var groupedEntries: [String: [Entry]] {
        var result: [String: [Entry]] = [:]
        for entry in entries {
            guard let group = entry.group else { continue }
            result[group, default: []].append(entry)
        }
        return result
    }
}
