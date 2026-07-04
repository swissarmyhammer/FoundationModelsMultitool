import Foundation
import FoundationModels
import FoundationModelsMetadataRegistry
import FoundationModelsRouter
import os

/// plan.md § "Discovery: a prefix-cached 'librarian' agent (Router `flash`
/// slot)" + M6: a long-lived session rooted on the full `APISurface` as its
/// instruction prefix, answering each `findAPIs(task)` call with guided,
/// decoded `FoundAPIs` output.
///
/// **Prefix reuse** maps to the `AgentSession.fork()` seam (plan.md Finding
/// #6): the root session is created once — seeded with the assembled prefix
/// (selection guidance + every rendered block) as its instructions — and
/// cached for this `Librarian`'s lifetime; every `findAPIs(task:)` call
/// `fork()`s a *fresh child* from it rather than querying the root directly,
/// so the prefix is prefilled once and each call's generation diverges from
/// an independent copy of that prefilled KV cache (verified on real
/// hardware in M6.5, per plan Finding #6).
///
/// **Capacity fallback** (plan Resolved #6): when the assembled prefix
/// exceeds `capacityCharacterLimit`, the surface is lexically pre-filtered
/// against the task's own keywords before seeding a *one-off* session (no
/// caching, no `fork()` — the filtered instructions differ per task, so
/// there is no stable prefix to reuse), and the cut is reported through
/// `onPrefilterCut`.
actor Librarian {
    /// Where this actor's own diagnostics are logged — `onPrefilterCut`'s
    /// default conformer.
    static let logger = Logger(subsystem: "FoundationModelsMultitool", category: "Librarian")

    /// A generous default capacity, in characters, approximating
    /// `ProfileDefinition`'s own default 8,192-token context budget (plan.md
    /// § "Router integration") at roughly 4 characters per token. Callers
    /// with a more precise budget for their resolved `flash` model should
    /// pass their own `capacityCharacterLimit`; this default exists so the
    /// production initializer has a reasonable value to fall back on.
    static let defaultCapacityCharacterLimit = 32_000

    /// The curated selection guidance prepended to every rendered block —
    /// plan.md § "The librarian's assembled prompt (concrete)", verbatim.
    static let selectionGuidance = """
        You are an API librarian. Given a task, return ONLY the functions needed — fewest
        that suffice, in call order when order matters. Do not invent functions; return an
        empty list if nothing fits.
        """

    /// Reports one lexical pre-filter cut — plan.md Resolved #6: "log the
    /// cut."
    struct PrefilterCutEvent: Sendable, Equatable {
        /// The `findAPIs` task the pre-filter ran for.
        let task: String
        /// How many blocks the full surface had before filtering.
        let totalBlocks: Int
        /// How many blocks survived the filter.
        let keptBlocks: Int
        /// The full assembled prefix's length, in characters, that triggered
        /// the fallback.
        let fullPrefixCharacterCount: Int
        /// The capacity, in characters, the full prefix exceeded.
        let capacityCharacterLimit: Int
    }

    /// The full, unfiltered catalog this librarian answers `findAPIs` calls
    /// over.
    private let surface: APISurface

    /// The capacity, in characters, the assembled prefix (`fullPrefixInstructions`)
    /// must fit under to use the cached, `fork()`-per-call root session.
    /// Clamped to at least `0` at `init`.
    private let capacityCharacterLimit: Int

    /// `Self.assemblePrefix(surface:)`, precomputed once at `init` since
    /// `surface` never changes for this librarian's lifetime.
    private let fullPrefixInstructions: String

    /// Creates a session seeded with the given instructions — the seam both
    /// the cached root session and a capacity-fallback one-off session are
    /// built through. `@Sendable` so it can cross this actor's isolation
    /// boundary; production wires it to
    /// `RoutedLLM.makeGuidedSession(_:instructions:workingDirectory:)`.
    private let makeSession: @Sendable (String) -> any AgentSession

    /// Called once per lexical pre-filter cut. Defaults to logging via
    /// `Self.logger`; a test overrides this to capture the event instead of
    /// asserting against the real logging subsystem — the same pattern
    /// `ToolAPIRenderer.render(_:onWiden:)` established for its own
    /// build-time diagnostics.
    private let onPrefilterCut: @Sendable (PrefilterCutEvent) -> Void

    /// This librarian's cached root session — `nil` until the first
    /// under-budget `findAPIs(task:)` call creates and caches it.
    private var rootSession: (any AgentSession)?

    /// Creates a librarian over a pre-built session factory — the test-facing
    /// entry point (mirrors `MultiToolAgent`'s own `AgentSession`-seam
    /// initializer): unit tests drive this against a scripted fake with zero
    /// GPU and no Router dependency.
    ///
    /// - Parameters:
    ///   - surface: the full catalog to answer `findAPIs` calls over.
    ///   - capacityCharacterLimit: the assembled prefix's character budget.
    ///     Negative values are clamped to `0`. Defaults to
    ///     `defaultCapacityCharacterLimit`.
    ///   - onPrefilterCut: called once per lexical pre-filter cut. Defaults
    ///     to logging via `Self.logger`.
    ///   - makeSession: creates a session seeded with the given instructions
    ///     text.
    init(
        surface: APISurface,
        capacityCharacterLimit: Int = Librarian.defaultCapacityCharacterLimit,
        onPrefilterCut: @escaping @Sendable (PrefilterCutEvent) -> Void = { Librarian.logPrefilterCut($0) },
        makeSession: @escaping @Sendable (String) -> any AgentSession
    ) {
        self.surface = surface
        self.capacityCharacterLimit = max(0, capacityCharacterLimit)
        self.fullPrefixInstructions = Self.assemblePrefix(surface: surface)
        self.onPrefilterCut = onPrefilterCut
        self.makeSession = makeSession
    }

    /// Creates a librarian bound to a resolved Router model — plan.md:
    /// "Configured via `MultiToolAgent(librarian:)` — pass the `RoutedLLM`
    /// handle (typically `profile.flash`)."
    ///
    /// - Parameters:
    ///   - surface: the full catalog to answer `findAPIs` calls over.
    ///   - librarian: the resolved `RoutedLLM` this librarian's sessions run
    ///     on — typically `profile.flash`.
    ///   - capacityCharacterLimit: the assembled prefix's character budget.
    ///     Defaults to `defaultCapacityCharacterLimit`.
    ///   - onPrefilterCut: called once per lexical pre-filter cut. Defaults
    ///     to logging via `Self.logger`.
    /// - Throws: an encoding error if `FoundAPIs.generationSchema` can't be
    ///   encoded to JSON Schema — not expected for a valid `@Generable`
    ///   type, kept `throws` rather than trapping because it's a genuine,
    ///   if practically unreachable, failure mode of `JSONEncoder`.
    init(
        surface: APISurface,
        librarian: RoutedLLM,
        capacityCharacterLimit: Int = Librarian.defaultCapacityCharacterLimit,
        onPrefilterCut: @escaping @Sendable (PrefilterCutEvent) -> Void = { Librarian.logPrefilterCut($0) }
    ) throws {
        let grammar = Grammar.jsonSchema(try Self.grammarSchemaSource())
        self.init(
            surface: surface,
            capacityCharacterLimit: capacityCharacterLimit,
            onPrefilterCut: onPrefilterCut
        ) { instructions in
            RoutedAgentSession(session: librarian.makeGuidedSession(grammar, instructions: instructions))
        }
    }

    /// Answers one `findAPIs(task:)` call — plan.md: guided
    /// `respond(to: task, generating: FoundAPIs.self)`.
    ///
    /// Under budget: reuses (creating on first use) this librarian's cached
    /// root session, seeded with the full assembled prefix, and `fork()`s a
    /// fresh child per call so the prefix's prefilled compute is inherited
    /// rather than replayed. Over budget: lexically pre-filters the surface
    /// against `task`'s keywords, reports the cut via `onPrefilterCut`, and
    /// queries a fresh one-off session seeded with the filtered prefix —
    /// there is no stable prefix to `fork()` from, since the filtered
    /// instructions differ per task.
    ///
    /// - Parameter task: the plain-language goal to find relevant functions
    ///   for.
    /// - Returns: the selected functions, well-formed by construction.
    /// - Throws: whatever the underlying session's `fork()`/`respond(to:)`
    ///   throws, or a decoding error if the response isn't valid,
    ///   schema-conforming JSON for `FoundAPIs`.
    func findAPIs(task: String) async throws -> FoundAPIs {
        guard fullPrefixInstructions.count <= capacityCharacterLimit else {
            let (filteredSurface, keptCount) = Self.lexicallyFilter(surface: surface, task: task)
            return try await respondFromFilteredSurface(
                task: task,
                filteredSurface: filteredSurface,
                keptCount: keptCount
            )
        }

        let child = try await cachedRootSession().fork()
        return try await child.respond(to: task, generating: FoundAPIs.self)
    }

    /// The capacity-fallback half of `findAPIs(task:)`: reports the lexical
    /// pre-filter cut and queries a fresh one-off session seeded with the
    /// filtered prefix.
    ///
    /// - Parameters:
    ///   - task: the plain-language goal to find relevant functions for.
    ///   - filteredSurface: the lexically pre-filtered surface to seed the
    ///     one-off session with.
    ///   - keptCount: how many entries `filteredSurface` kept, for the
    ///     reported `PrefilterCutEvent`.
    /// - Returns: the selected functions.
    /// - Throws: whatever the one-off session's `respond(to:)` throws, or a
    ///   decoding error if the response isn't valid, schema-conforming JSON
    ///   for `FoundAPIs`.
    private func respondFromFilteredSurface(
        task: String,
        filteredSurface: APISurface,
        keptCount: Int
    ) async throws -> FoundAPIs {
        onPrefilterCut(
            PrefilterCutEvent(
                task: task,
                totalBlocks: surface.entries.count,
                keptBlocks: keptCount,
                fullPrefixCharacterCount: fullPrefixInstructions.count,
                capacityCharacterLimit: capacityCharacterLimit
            )
        )
        let filteredInstructions = Self.assemblePrefix(surface: filteredSurface)
        let session = makeSession(filteredInstructions)
        return try await session.respond(to: task, generating: FoundAPIs.self)
    }

    /// Returns this librarian's cached root session, creating and caching it
    /// on first use.
    ///
    /// - Returns: the cached root session, seeded with the full assembled
    ///   prefix.
    private func cachedRootSession() async throws -> any AgentSession {
        if let rootSession { return rootSession }
        let session = makeSession(fullPrefixInstructions)
        rootSession = session
        return session
    }

    // MARK: - Prefix assembly

    /// Assembles the librarian's instruction prefix — plan.md § "The
    /// librarian's assembled prompt (concrete)": `selectionGuidance`
    /// followed by a `# Available functions` header and every entry's
    /// rendered block, in catalog order.
    ///
    /// - Parameter surface: the catalog to assemble a prefix for.
    /// - Returns: the assembled prefix text.
    static func assemblePrefix(surface: APISurface) -> String {
        "\(selectionGuidance)\n\n# Available functions\n\(surface.source)"
    }

    // MARK: - Capacity fallback (plan Resolved #6)

    /// Lexically pre-filters `surface`'s entries to those whose rendered
    /// block mentions at least one of `task`'s own significant words —
    /// plan.md Resolved #6: "lexically pre-filter the candidates before
    /// seeding."
    ///
    /// Deliberately simple (substring matching over lowercased text, no
    /// embeddings/ranking): the capacity fallback only needs to keep the
    /// surface a small model can actually hold, not to be the primary
    /// selection mechanism — that's still the librarian's own guided
    /// generation over whatever survives this filter.
    ///
    /// - Parameters:
    ///   - surface: the full catalog to filter.
    ///   - task: the plain-language `findAPIs` task whose words drive the
    ///     filter.
    /// - Returns: the filtered surface (entries in their original catalog
    ///   order) and how many entries it kept. When `task` has no
    ///   significant words to match on, every entry is kept — an
    ///   unfilterable task is better handled by the guided model itself than
    ///   by cutting the whole surface.
    static func lexicallyFilter(surface: APISurface, task: String) -> (surface: APISurface, keptCount: Int) {
        let keywords = significantWords(in: task)
        guard !keywords.isEmpty else { return (surface, surface.entries.count) }

        let kept = surface.entries.filter { entry in
            let haystack = "\(entry.path) \(entry.descriptor.source)".lowercased()
            return keywords.contains { haystack.contains($0) }
        }
        return (APISurface(entries: kept), kept.count)
    }

    /// Splits `text` into lowercased, alphanumeric-run "words" at least 3
    /// characters long — long enough to skip common short stop words
    /// ("a", "is", "to") that would otherwise match almost every block.
    ///
    /// - Parameter text: the text to tokenize.
    /// - Returns: the set of significant words found.
    private static func significantWords(in text: String) -> Set<String> {
        Set(
            text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 3 }
        )
    }

    // MARK: - Guided-generation grammar

    /// Derives `FoundAPIs`'s JSON Schema — the one source of truth for the
    /// grammar constraining every root session's `respond(to:)` (mirrors
    /// the derivation `RoutedLLM.respond<T: Generable>(to:generating:)`
    /// performs internally for its own one-shot sessions, per that method's
    /// documentation — replicated here because this librarian needs the
    /// schema *once*, at session-creation time, to build a *reusable*
    /// guided session rather than a fresh one per call).
    ///
    /// - Returns: the JSON Schema source string.
    /// - Throws: an encoding error if `FoundAPIs.generationSchema` can't be
    ///   encoded — not expected for a valid `@Generable` type.
    static func grammarSchemaSource() throws -> String {
        let data = try JSONEncoder().encode(FoundAPIs.generationSchema)
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Default diagnostics

    /// The default `onPrefilterCut` conformer: logs the cut via
    /// `Self.logger`.
    ///
    /// - Parameter event: the pre-filter cut to log.
    static func logPrefilterCut(_ event: PrefilterCutEvent) {
        logger.notice(
            """
            Librarian prefix (\(event.fullPrefixCharacterCount, privacy: .public) characters) exceeds its \
            \(event.capacityCharacterLimit, privacy: .public)-character capacity; lexically pre-filtered from \
            \(event.totalBlocks, privacy: .public) to \(event.keptBlocks, privacy: .public) block(s) for task \
            "\(event.task, privacy: .public)".
            """
        )
    }
}
