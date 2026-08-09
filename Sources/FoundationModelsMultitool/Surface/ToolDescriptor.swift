import Foundation

/// The rendered, ready-to-embed API surface for one wrapped tool — the
/// output of `ToolAPIRenderer`.
///
/// One generator (`ToolAPIRenderer`) produces this, and the very same
/// descriptor feeds the runtime `tools.<name>` binding, the registry-backed
/// selection tier's instruction prefix (`FoundationModelsMetadataRegistry`'s
/// `MetadataSearcher`/`SelectionTier`), and the in-snippet `help()`/`docs()`
/// globals, so the declaration, doc comment, and example can never drift
/// from one another (plan.md § "ToolAPIRenderer": "The renderer's output is
/// captured per tool as a `ToolDescriptor`... The same descriptor feeds the
/// runtime binding, the librarian prefix, and `help()`/`docs()` — one
/// generator, one source of truth, never drifting." — that "librarian
/// prefix" is the registry-backed selection tier's instruction prefix
/// referenced above).
public struct ToolDescriptor: Sendable, Equatable {
    /// The identifier the snippet calls this function by, e.g. `"getWeather"`.
    /// A group's namespace prefix (`tools.<group>.<name>`) is applied by a
    /// later milestone; M2 always renders a flat, unqualified `name`.
    public let name: String

    /// The bare `declare function …` signature line, with no doc comment —
    /// e.g. `declare function getWeather(args: { city: string }): Promise<string>;`.
    ///
    /// The return type is always a `Promise<…>`: a `tools.*` binding is an
    /// async host function, so the call yields a promise and the declared
    /// type says what awaiting it resolves to.
    public let declaration: String

    /// The JSDoc doc comment block (`/** … */`) rendered for `declaration`.
    public let doc: String

    /// The auto-generated, runnable example call this tool would be invoked
    /// with, e.g. `await tools.getWeather({ city: "city" });` — the same text
    /// that also appears inside `doc`'s `@example` line, with one deliberate
    /// exception: if a schema-derived value spliced into the call (an enum
    /// choice or property name) contains an embedded JSDoc comment
    /// terminator (`*/`), the `@example` line's copy neutralizes it (so the
    /// surrounding `/** … */` block can't be broken out of), while `example`
    /// itself is left exactly as generated — this field is meant to be
    /// copied and run verbatim, not read as comment prose.
    public let example: String

    /// The full renderable text block — `doc` followed by `declaration` —
    /// exactly what's spliced into `searchTools` results, the registry-backed
    /// selection tier's instruction prefix, and `help()`/`docs()`.
    public let source: String

    /// The same signature `declaration` states, as structure rather than
    /// text: what the single `args` object declares, and what awaiting the
    /// call resolves to.
    ///
    /// `declaration` is rendered *from* this value (see
    /// `ToolValueShape.declaredType`), so anything checking a call against
    /// this shape is checking it against exactly the signature the model was
    /// shown. That is what lets `SearchToolsTool`'s sample gate check a
    /// generated snippet's arguments and field reads without a second,
    /// independently-derived notion of the tool's type.
    public let signature: ToolSignature

    /// Creates a rendered tool descriptor.
    ///
    /// Explicit (rather than relying on the compiler-synthesized memberwise
    /// initializer) for the same reason as `HostFunction.init` in
    /// `Interpreter.swift`: a `public` struct's synthesized initializer is
    /// only `internal`-accessible, and `ToolAPIRenderer` needs to construct
    /// this type from outside the type's own file.
    ///
    /// - Parameters:
    ///   - name: the identifier the snippet calls this function by.
    ///   - declaration: the bare `declare function …` signature line.
    ///   - doc: the JSDoc doc comment block rendered for `declaration`.
    ///   - example: the auto-generated, runnable example call.
    ///   - source: the full renderable text block (`doc` + `declaration`).
    ///   - signature: the same signature `declaration` states, as structure.
    public init(
        name: String,
        declaration: String,
        doc: String,
        example: String,
        source: String,
        signature: ToolSignature
    ) {
        self.name = name
        self.declaration = declaration
        self.doc = doc
        self.example = example
        self.source = source
        self.signature = signature
    }
}
