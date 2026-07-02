import FoundationModels

/// One tool-function the librarian selected as relevant to a `findAPIs(task)`
/// call — plan.md § "Discovery": "each with its typed signature, purpose, and
/// a runnable example."
///
/// Every field is copied verbatim from the matching `ToolDescriptor`/
/// `APISurface.Entry` the librarian selected — the guided model is asked to
/// *pick*, not *paraphrase* — so `FindAPITool` can splice `signature`/`doc`/
/// `example` straight into the main agent's transcript unmodified.
@Generable
public struct FoundAPI: Sendable, Equatable {
    /// The function's bare name, e.g. `"weather"`.
    @Guide(description: "the function's name, e.g. \"weather\".")
    public var name: String

    /// The function's full call signature, e.g. `"tools.weather(args: {
    /// city: string }): { tempC: number }"`.
    @Guide(
        description: "the function's full call signature, e.g. "
            + "\"tools.weather(args: { city: string }): { tempC: number }\"."
    )
    public var signature: String

    /// The function's purpose, copied verbatim from its rendered doc
    /// comment.
    @Guide(description: "the function's purpose, verbatim from its rendered doc comment.")
    public var doc: String

    /// A runnable example call, e.g. `"const c = tools.weather({ city:
    /// \"ATX\" }).tempC;"`.
    @Guide(description: "a runnable example call, e.g. \"const c = tools.weather({ city: \\\"ATX\\\" }).tempC;\".")
    public var example: String

    /// Creates one selected tool-function.
    ///
    /// Explicit for the same reason as this package's other public struct
    /// initializers (e.g. `ToolDescriptor.init`, `RunCodeArguments.init`): a
    /// `public` struct's synthesized memberwise initializer is only
    /// `internal`-accessible.
    ///
    /// - Parameters:
    ///   - name: the function's bare name.
    ///   - signature: the function's full call signature.
    ///   - doc: the function's purpose, verbatim from its rendered doc
    ///     comment.
    ///   - example: a runnable example call.
    public init(name: String, signature: String, doc: String, example: String) {
        self.name = name
        self.signature = signature
        self.doc = doc
        self.example = example
    }
}

/// The librarian's guided-generation result for one `findAPIs(task)` call —
/// plan.md § "Discovery: a prefix-cached 'librarian' agent":
///
/// ```swift
/// @Generable struct FoundAPIs { var functions: [FoundAPI] }
/// ```
///
/// Produced via Router guided generation
/// (`RoutedLLM.respond(to:generating:)`, reached here through
/// `AgentSession.respond(to:generating:)`), so the pick is well-formed by
/// construction — never free prose the caller must parse.
@Generable
public struct FoundAPIs: Sendable, Equatable {
    /// The selected functions — fewest that suffice, in call order when
    /// order matters (plan.md's librarian instructions); empty when nothing
    /// in the surface fits the task.
    @Guide(
        description: "the selected functions, fewest that suffice, in call order when order "
            + "matters; empty if nothing in the surface fits the task."
    )
    public var functions: [FoundAPI]

    /// Creates a librarian result.
    ///
    /// Explicit for the same reason as `FoundAPI.init` above.
    ///
    /// - Parameter functions: the selected functions, fewest that suffice.
    public init(functions: [FoundAPI]) {
        self.functions = functions
    }
}
