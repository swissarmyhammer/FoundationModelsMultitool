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
            "\(banner)\n\(qualify(descriptor.source))"
        }

        /// The short text block that seeds the registry-backed selection
        /// tier's prompt for this entry: the same `// tools.<path>` banner
        /// ``block`` opens with, then `descriptor.description` alone —
        /// no `@param`, `@returns` or `@example` line and no
        /// `declare function` line.
        ///
        /// The selection model chooses BETWEEN tools, so the description is
        /// what it needs; the signature is what the main session needs once
        /// a tool is chosen, and `SearchToolsTool` splices ``block`` for
        /// that. Measured on 2026-09-09 over the agent's nine-entry
        /// files-and-shell surface: the full blocks made a 17,263-character
        /// prefix, and the description-only blocks make one of 7,600.
        ///
        /// The description passes through `qualify(_:)` exactly as it does
        /// inside ``block``, so a `tools.<name>(` call an author wrote in the
        /// prose reads the same in both texts.
        ///
        /// **Two rules apply to the description, and they apply here.** The
        /// description of a tool is not always text this package wrote. An
        /// MCP tool carries the description its server gave, word for word
        /// (`MCPTool.description`), so a third party writes part of the
        /// selection prompt. The rules stand at this one place, and not in
        /// the MCP capability, thus a native tool with the same fault obeys
        /// them too:
        ///
        /// 1. **A description longer than
        ///    ``summaryDescriptionCharacterLimit`` is cut**, on a word
        ///    boundary, and the cut is visible: the text ends with a
        ///    `[cut <n> characters]` line of its own that names how many
        ///    characters it does not show. Without the cap, a server that
        ///    declares forty tools of several thousand characters each sets
        ///    the size of the prompt, the number of model calls and the time
        ///    of one `searchTools` call.
        /// 2. **A description that is empty, or spaces alone, is replaced**
        ///    by a sentence that names the verb and the names of its
        ///    arguments — `"read takes path and encoding."` A server is
        ///    permitted to give no description, and such a tool must stay
        ///    callable, but a banner with nothing under it leaves the
        ///    selection model a path and nothing more to read.
        ///
        /// Neither rule reaches ``block``, which the main session reads after
        /// a tool is chosen, and neither rule reaches the tool itself, which
        /// keeps the name, the description and the schema the server gave.
        public var summaryBlock: String {
            "\(banner)\n\(summaryDescription)"
        }

        /// The greatest number of characters of description ``summaryBlock``
        /// carries, the cut marker counted in.
        ///
        /// Measured on 2026-09-10 over the two surfaces this package renders.
        /// The nine-entry files-and-shell surface: a description of 682 to
        /// 1,663 characters (the longest is `files.patch`), a `summaryBlock`
        /// of 706 to 1,684 characters, and a `block` of 1,498 to 2,916. The
        /// three-verb loopback MCP surface: a description of 39 to 57
        /// characters, a `summaryBlock` of 62 to 85, and a `block` of 230 to
        /// 288.
        ///
        /// The limit stands above the longest description this package
        /// writes, with room for that description to grow by about a fifth,
        /// thus no shipped description is cut today and the rule bites only
        /// on text that is far outside what a description is for.
        public static let summaryDescriptionCharacterLimit = 2_000

        /// The text ``summaryBlock`` puts under the banner: the description,
        /// cut to ``summaryDescriptionCharacterLimit``, or the sentence that
        /// stands in for a description the tool does not give.
        private var summaryDescription: String {
            let described = qualify(descriptor.description)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !described.isEmpty else { return argumentSentence }
            return Self.cut(described)
        }

        /// What ``summaryDescription`` reads when the tool gives no
        /// description: one sentence that names the verb and the names of the
        /// arguments its schema declares.
        ///
        /// The argument names are the only other words the entry holds that a
        /// person wrote. They are what the block carried before the selection
        /// prompt narrowed to the description alone, and they are what a
        /// reader of the tool would match a request against.
        private var argumentSentence: String {
            let names = descriptor.signature.arguments.properties.map(\.name)
            guard !names.isEmpty else {
                return "\(descriptor.name) takes no argument."
            }
            return "\(descriptor.name) takes \(Self.sentenceList(of: names))."
        }

        /// Cuts `description` to ``summaryDescriptionCharacterLimit`` on a
        /// word boundary, and marks the cut.
        ///
        /// The head is kept, and the tail goes away. `ToolContentRenderer`
        /// elides the MIDDLE of a tool result, because the tail of a result
        /// often holds the answer; a description opens with what the tool is
        /// for, so the head is the half a selection model must read.
        ///
        /// Room for the marker is reserved against the largest count the
        /// marker could name, thus the result never goes over the limit.
        ///
        /// - Parameter description: The description to cut.
        /// - Returns: `description` unchanged when it is inside the limit;
        ///   otherwise its head, back to the last space, and the marker.
        private static func cut(_ description: String) -> String {
            guard description.count > summaryDescriptionCharacterLimit else {
                return description
            }
            let worstCaseMarker = summaryCutMarker(cutCount: description.count)
            let keptLimit = max(summaryDescriptionCharacterLimit - worstCaseMarker.count, 0)
            let head = description.prefix(keptLimit)
            let boundary = head.lastIndex { $0.isWhitespace } ?? head.endIndex
            let kept = head[head.startIndex..<boundary]
            return kept + summaryCutMarker(cutCount: description.count - kept.count)
        }

        /// The marker that closes a cut description, on a line of its own, and
        /// names how many characters of the description are not shown.
        ///
        /// - Parameter cutCount: The number of characters the marker reports
        ///   as cut.
        /// - Returns: A standalone `"[cut <cutCount> characters]"` line.
        static func summaryCutMarker(cutCount: Int) -> String {
            "\n[cut \(cutCount) characters]"
        }

        /// Joins `names` the way a sentence does — `"path"`, `"path and
        /// encoding"`, `"path, encoding and count"`.
        ///
        /// - Parameter names: The names to join, in declared order.
        /// - Returns: The joined text, or the empty string for no name.
        private static func sentenceList(of names: [String]) -> String {
            guard let last = names.last else { return "" }
            guard names.count > 1 else { return last }
            return "\(names.dropLast().joined(separator: ", ")) and \(last)"
        }

        /// The `// tools.<path>` line that opens ``block`` and
        /// ``summaryBlock``, so the two texts name the entry the same way and
        /// a reader of either finds the fully-qualified call path on its
        /// first line.
        private var banner: String {
            "// tools.\(path)"
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
    /// order, separated by a blank line. It backs the in-snippet
    /// `help()`/`docs()` globals. The registry-backed selection tier
    /// (`MetadataSearcher`/`SelectionTier`, prefix-cached per plan.md
    /// § "Discovery: a prefix-cached 'librarian' agent") does not read it:
    /// that tier assembles its prefix from each entry's
    /// ``Entry/summaryBlock``.
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
