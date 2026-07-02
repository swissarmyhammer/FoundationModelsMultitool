/// The rendered, model-agnostic tool catalog `MultiTool.Builder.build()`
/// produces (plan.md Component 7): "the rendered catalog; backs the
/// librarian prefix, `help()`/`docs()`, and a host-listable data view."
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
        /// Explicit (rather than relying on the compiler-synthesized
        /// memberwise initializer) for the same reason as
        /// `ToolDescriptor.init` in `ToolDescriptor.swift`: a `public`
        /// struct's synthesized initializer is only `internal`-accessible,
        /// and `Entry` is a public type of the `FoundationModelsMultitool`
        /// library product — without this, no module outside
        /// `FoundationModelsMultitool` could construct an `Entry`, even
        /// though `APISurface`'s public `entries` array exposes them.
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
        /// function` signature — verbatim and unmodified.
        ///
        /// `path` is safe to splice bare into a `//` comment: it's built
        /// exclusively from `descriptor.name` (already validated as a
        /// legal TypeScript identifier by `ToolAPIRenderer.render`, which
        /// throws otherwise) and, for a grouped entry, `group` (validated
        /// the same way by `MultiTool.Builder.build()` before this `Entry`
        /// is ever constructed) — neither can contain a newline or other
        /// character that could break out of a single-line comment.
        public var block: String {
            "// tools.\(path)\n\(descriptor.source)"
        }
    }

    /// Every tool in the catalog, in the order `addTool`/`addTools`/
    /// `addGroup` recorded it.
    public let entries: [Entry]

    /// Creates a rendered API surface.
    ///
    /// Explicit (rather than relying on the compiler-synthesized memberwise
    /// initializer) for the same reason as `Entry.init` above: a `public`
    /// struct's synthesized initializer is only `internal`-accessible, and
    /// `APISurface` is the public return type of `MultiTool.Builder.build()`
    /// — a host could reasonably need to assemble one directly (e.g. in
    /// tests, or composing entries produced some other way) without this.
    ///
    /// - Parameter entries: every tool in the catalog, in catalog order.
    public init(entries: [Entry]) {
        self.entries = entries
    }

    /// The full rendered surface — every entry's `block`, in catalog
    /// order, separated by a blank line. This is what backs the
    /// librarian's instruction prefix and the in-snippet `help()`/`docs()`
    /// globals (plan.md § "Discovery: a prefix-cached 'librarian' agent").
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
