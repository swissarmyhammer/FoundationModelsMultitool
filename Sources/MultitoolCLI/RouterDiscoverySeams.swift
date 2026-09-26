import FoundationModelsMetadataRegistry
import FoundationModelsMultitool
import FoundationModelsRouter

/// The discovery seams of `FoundationModelsMultitool`, over the Router
/// handles of a resolved profile.
///
/// Discovery takes the seams of FoundationModelsMetadataRegistry and knows
/// nothing of Router: a ``SearchToolsTool/SelectionFactory``, an
/// `any TextEmbedding` and a ``SearchToolsTool/SessionFactory``. The host
/// picks the models. This is the one place where the sample CLI turns its
/// Router handles into those seams, and `CLIRunner` mounts its session tools
/// with the result:
///
/// ```swift
/// let seams = RouterDiscoverySeams(librarian: profile.flash, embedder: profile.embedding)
/// let mounted = try registry.makeSessionToolsAndStaging(
///     selection: seams.selection, embedder: seams.embedder, sampleSession: seams.sampleSession)
/// ```
public struct RouterDiscoverySeams: Sendable {
    /// Makes the selection tier for the catalog ids, on guided sessions of
    /// the librarian.
    public let selection: SearchToolsTool.SelectionFactory

    /// The embedding handle of the profile, presented as a `TextEmbedding`.
    public let embedder: any TextEmbedding

    /// Makes the sample-snippet session on the generator, or `nil` when no
    /// generator was given and `searchTools` answers with signatures alone.
    public let sampleSession: SearchToolsTool.SessionFactory?

    /// Makes the seams over the Router handles of a resolved profile.
    ///
    /// - Parameters:
    ///   - librarian: the model every selection session runs on. It must be
    ///     a handle other than the one whose session mounts `searchTools` —
    ///     see ``makeSelection(makeGuidedSession:)``. The sample CLI passes
    ///     `profile.flash`.
    ///   - embedder: the embedding handle both searchers rank with. The
    ///     sample CLI passes `profile.embedding`.
    ///   - sampleGenerator: the model the sample snippet is written on, or
    ///     `nil` (the default) for no sample. Pass the **main** generation
    ///     slot rather than the librarian: the sample is code the model is
    ///     told to run, so its quality matters more than its cost. Its
    ///     session is made with no `tools:` argument, which keeps
    ///     `searchTools` off it: it writes a snippet, it does not execute
    ///     one.
    public init(librarian: RoutedLLM, embedder: RoutedEmbedder, sampleGenerator: RoutedLLM? = nil) {
        self.selection = Self.makeSelection { grammar, instructions in
            librarian.makeGuidedSession(grammar: grammar, instructions: instructions)
        }
        self.embedder = RoutedTextEmbedding(embedder: embedder)
        self.sampleSession = sampleGenerator.map(Self.makeSampleSession(generator:))
    }

    /// The session factory over `generator`: one plain Router session per
    /// instruction text, with no tools mounted.
    ///
    /// - Parameter generator: the model the sample snippet is written on.
    /// - Returns: the session factory.
    static func makeSampleSession(generator: RoutedLLM) -> SearchToolsTool.SessionFactory {
        { instructions in
            RoutedAgentSession(session: generator.makeSession(instructions: instructions))
        }
    }

    /// The selection factory over `makeGuidedSession`: for each catalog, one
    /// id grammar, and every session of the tier made under it.
    ///
    /// **One grammar for every call, built before the session factory rather
    /// than inside it.** `SelectionConfig`'s factory takes the instructions
    /// alone as of the ranker's `34fe8d4`, so a grammar scoped to one round's
    /// candidates is not expressible. Over budget, the tier prompts one slice
    /// of the catalog at a time while this grammar still permits every id in
    /// the catalog. That is safe: the tier's own `.unknownSelectedId` filter
    /// drops an id outside the slice the prompt carried.
    ///
    /// **The selection session must come from a handle other than the one
    /// whose turn calls `searchTools`. That is a correctness requirement, not
    /// a cost preference.** `searchTools` is invoked from inside a turn's tool
    /// body. A Router session holds its own `turnLock` for the whole turn,
    /// tool rounds included, and both `RoutedSession.fork(workingDirectory:)`
    /// and the `transcript` getter take `await turnLock.wait()` on that same
    /// lock. So a selection tier that forked *the session it is running
    /// inside* would block until the turn ended, and the turn cannot end
    /// until this tool returns. That is a permanent hang, and it is the exact
    /// shape of Router's `^d2ptrk1`. What keeps this host clear of it is only
    /// that the librarian is a different handle — `profile.flash`, with a
    /// `turnLock` of its own. Measured: the
    /// `SearchToolsTool.makeSelectionSession` and `AgentSession.fork` spans
    /// both enter and exit inside a millisecond.
    ///
    /// **Router's generation-permit loan does not cover this.** That fix
    /// (`^1zt7vyg`) lends a `generationGate` permit to a nested turn and
    /// deliberately leaves `turnLock` alone, because `turnLock` is the
    /// correctness gate. So forking the in-turn session would deadlock
    /// immediately, loan or no loan. Reusing the caller's session here looks
    /// like the natural simplification. It is the one change this factory
    /// must never take.
    ///
    /// - Parameter makeGuidedSession: makes one guided Router session from a
    ///   grammar and the instructions. ``init(librarian:embedder:sampleGenerator:)``
    ///   passes the librarian's `makeGuidedSession(grammar:instructions:)`, and a
    ///   test passes a closure that records the grammar.
    /// - Returns: the selection factory.
    static func makeSelection(
        makeGuidedSession: @escaping @Sendable (Grammar, String) -> any RoutedSession
    ) -> SearchToolsTool.SelectionFactory {
        { ids in
            let grammar = try SelectionGrammar.idEnumGrammar(ids: ids)
            return SelectionConfig(model: { instructions in
                RoutedAgentSession(session: makeGuidedSession(grammar, instructions))
            })
        }
    }
}
