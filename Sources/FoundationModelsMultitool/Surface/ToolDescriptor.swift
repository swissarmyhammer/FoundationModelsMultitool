import Foundation

/// The rendered, ready-to-embed API surface for one wrapped tool — the
/// output of `ToolAPIRenderer`.
///
/// One generator (`ToolAPIRenderer`) produces this, and the very same
/// descriptor feeds the runtime `tools.<name>` binding, the librarian's
/// instruction prefix, and the in-snippet `help()`/`docs()` globals, so the
/// declaration, doc comment, and example can never drift from one another
/// (plan.md § "ToolAPIRenderer": "The renderer's output is captured per tool
/// as a `ToolDescriptor`... The same descriptor feeds the runtime binding,
/// the librarian prefix, and `help()`/`docs()` — one generator, one source of
/// truth, never drifting.").
public struct ToolDescriptor: Sendable, Equatable {
    /// The identifier the snippet calls this function by, e.g. `"weather"`.
    /// A group's namespace prefix (`tools.<group>.<name>`) is applied by a
    /// later milestone; M2 always renders a flat, unqualified `name`.
    public let name: String

    /// The bare `declare function …` signature line, with no doc comment —
    /// e.g. `declare function weather(args: { city: string }): string;`.
    public let declaration: String

    /// The JSDoc doc comment block (`/** … */`) rendered for `declaration`.
    public let doc: String

    /// The auto-generated, runnable example call this tool would be invoked
    /// with, e.g. `tools.weather({ city: "city" });` — the same text that
    /// also appears inside `doc`'s `@example` line.
    public let example: String

    /// The full renderable text block — `doc` followed by `declaration` —
    /// exactly what's spliced into `findAPIs` results, the librarian's
    /// instruction prefix, and `help()`/`docs()`.
    public let source: String

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
    public init(name: String, declaration: String, doc: String, example: String, source: String) {
        self.name = name
        self.declaration = declaration
        self.doc = doc
        self.example = example
        self.source = source
    }
}
