/// The rendered, model-agnostic tool catalog `MultiTool.Builder.build()`
/// produces (plan.md Component 7).
///
/// One `ToolAPIRenderer` call per wrapped tool produces every entry's
/// `ToolDescriptor` (M2). This type adds the namespace a tool was added under
/// (plan.md Resolved #5) — see ``Entry/path``. `APISurface` itself is pure
/// data: no model wiring, and no rendering logic of its own beyond the
/// composition of already-rendered pieces.
public struct APISurface: Sendable, Equatable {
    /// One rendered tool in the catalog.
    public struct Entry: Sendable, Equatable {
        /// The fully-qualified path the snippet calls this tool by, relative
        /// to `tools`. It is always `descriptor.name` for a standalone entry
        /// (`group == nil`), and always `"\(group).\(descriptor.name)"` for a
        /// grouped one.
        public let path: String

        /// The group this tool was added under (via
        /// `addGroup(named:_:)`), or `nil` for a standalone (flat-namespaced)
        /// tool added via `addTool(_:)`/`addTools(_:)`.
        public let group: String?

        /// The tool's own rendered descriptor, exactly as `ToolAPIRenderer`
        /// produced it and never post-processed. Its `name`, `declaration`,
        /// `doc`, `example` and `source` are always unqualified (plan.md: "M2
        /// always renders a flat, unqualified `name`"); ``path`` is what
        /// carries the namespace.
        public let descriptor: ToolDescriptor

        /// Creates a catalog entry.
        ///
        /// Explicit, because a `public` struct's synthesized initializer is
        /// only `internal`-accessible, and a caller of the
        /// `FoundationModelsMultitool` library product must be able to
        /// construct an `Entry` directly.
        public init(path: String, group: String?, descriptor: ToolDescriptor) {
            self.path = path
            self.group = group
            self.descriptor = descriptor
        }

        /// The canonical `"verb noun"` string this entry's runs journal as
        /// their `OperationEvent.op` — `"execute shell"` for
        /// `tools.shell.execute`. `nil` for a standalone entry, which has no
        /// noun and keeps the tool's own name as its op.
        ///
        /// The order is externally specified, not a local choice. eventplan.md
        /// § "Registration of capabilities: noun/verb": "`OperationEvent.op`
        /// stays the canonical `"verb noun"` string. Registration derives it as
        /// `"\(verb) \(noun)"`."
        ///
        /// It comes from the same two halves ``path`` does: `group` is the
        /// noun `register(noun:tool:)` supplied, and `descriptor.name` is the
        /// verb `Tool.name` supplied. Neither half is spelled a second time
        /// anywhere. A verb could not derive this for itself, because it does
        /// not know its own noun. That is why the derivation stands here and
        /// not in the tool.
        ///
        /// The string appears on the run plane only, never in the event
        /// journal of an enclosing snippet. `MultiTool` hands it to
        /// `ToolMounting.makeWrapped`, which stamps it on the call's own
        /// `ToolContext.op`, so `SessionMailbox.track(tool:op:)` fills
        /// `BackgroundRun.op` from it and the run's `ToolInvocationRecord`
        /// carries it. The `OperationEvent`s of an inner `tools.*` call reach
        /// the session's outbox through the enclosing `runCode` context's
        /// `post(_:)`, which re-stamps each forwarded event with the OUTER
        /// run's identity.
        ///
        /// The `tool` field of each of those records keeps naming the tool
        /// itself (`"execute"`). Only `op` carries the pair.
        public var journalOp: String? {
            group.map { "\(descriptor.name) \($0)" }
        }

        /// This entry's full renderable text block, as it appears in the
        /// concatenated `APISurface.source`: a `// tools.<path>` banner line
        /// that names the fully-qualified call path, then `descriptor.source`
        /// with its embedded `@example` call qualified the same way (see
        /// `qualify(_:)`). The runnable example a reader sees thus always
        /// matches the namespace the banner just named, and never the bare
        /// call a model has no way to know needs a group prefix.
        ///
        /// `path` is safe to splice bare into a `//` comment. It is built only
        /// from `descriptor.name`, which `ToolAPIRenderer.render` validates as
        /// a legal TypeScript identifier and throws otherwise, and, for a
        /// grouped entry, `group`, which `MultiTool.Builder.build()` validates
        /// the same way before this `Entry` is constructed. Neither can hold a
        /// newline or another character that could break out of a single-line
        /// comment.
        public var block: String {
            "// tools.\(path)\n\(qualify(descriptor.source))"
        }

        /// `descriptor.example` — the auto-generated, runnable example call —
        /// with its bare `tools.<name>(` prefix qualified the same way
        /// ``block``'s embedded `@example` line is. A caller that splices this
        /// field directly (`SearchToolsTool.format`'s separate `Example: ...`
        /// trailer) thus never shows a call that disagrees with the one
        /// ``block`` displays.
        ///
        /// A no-op for a standalone entry, where `path == descriptor.name`.
        public var qualifiedExample: String {
            qualify(descriptor.example)
        }

        /// Replaces the unqualified `tools.<name>(` call prefix that
        /// `ToolAPIRenderer.render`'s `exampleCall` always renders with the
        /// fully-qualified `tools.<path>(` prefix, everywhere it appears in
        /// `text` — the embedded JSDoc `@example` line inside
        /// `descriptor.source`, and `descriptor.example` itself.
        ///
        /// A targeted substitution rather than a re-render: `descriptor` (M2's
        /// flat, unqualified rendering) is never re-derived, and only its one
        /// namespace-dependent call-path prefix is corrected. The replacement
        /// text is safe to splice, because `ToolAPIRenderer.render` validates
        /// `descriptor.name` as a legal TypeScript identifier: the text can
        /// never break out of the surrounding JSDoc or declaration syntax.
        ///
        /// This does not make the *search* substring
        /// `"tools.\(descriptor.name)("` unique within `text`. A tool's
        /// author-supplied `description` or `@Guide` prose, which
        /// `descriptor.source` also embeds verbatim, could in principle hold
        /// that exact literal substring. But the only place
        /// `ToolAPIRenderer.render` itself emits it is the `@example` line and
        /// `example` field this method targets, so the risk is theoretical and
        /// not practical for any real generated doc.
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
    /// Explicit for the same reason as ``Entry/init(path:group:descriptor:)``.
    public init(entries: [Entry]) {
        self.entries = entries
    }

    /// The full rendered surface — every entry's ``Entry/block``, in catalog
    /// order, separated by a blank line. It backs the instruction prefix of
    /// `FoundationModelsMetadataRegistry`'s registry-backed selection tier
    /// (`MetadataSearcher`/`SelectionTier`, prefix-cached per plan.md
    /// § "Discovery: a prefix-cached 'librarian' agent") and the in-snippet
    /// `help()`/`docs()` globals.
    public var source: String {
        entries.map(\.block).joined(separator: "\n\n")
    }

    /// Every standalone (flat-namespaced) entry, in catalog order — a view for
    /// a host UI that lists ungrouped tools separately from grouped ones.
    public var standaloneEntries: [Entry] {
        entries.filter { $0.group == nil }
    }

    /// Every grouped entry, keyed by group name, each group's entries in
    /// catalog order — a view for a host UI that renders namespace headings.
    public var groupedEntries: [String: [Entry]] {
        var result: [String: [Entry]] = [:]
        for entry in entries {
            guard let group = entry.group else { continue }
            result[group, default: []].append(entry)
        }
        return result
    }
}
