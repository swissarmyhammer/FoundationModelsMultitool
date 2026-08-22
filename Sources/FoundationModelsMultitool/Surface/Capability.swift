import FoundationModels

/// A noun, plus the tools that render under that noun — eventplan.md §
/// "Registration of capabilities: noun/verb".
///
/// The grammar of the surface is fixed. Each capability entry is
/// `tools.<noun>.<verb>`, and it has two segments. The capability gives the
/// first segment one time. Each of its tools gives the second segment,
/// because `Tool.name` is the verb.
///
/// ```swift
/// struct FilesCapability: Capability {
///     let noun = "files"
///     let tools: [any Tool] = [EditTool(), ReadTool()]   // names: edit, read
/// }
///
/// let surface = try MultiTool.Builder()
///     .withCapability(FilesCapability())  // tools.files.edit, tools.files.read
///     .build()
/// ```
///
/// A capability holds no logic of its own. Thus a `Tool` conformer that
/// exists becomes part of a capability with no change to the conformer: put
/// the tool in the `tools` array, and the capability supplies the noun.
///
/// Built-in capabilities and user capabilities are the same thing. Third
/// party Swift code registers through this same protocol. An MCP server
/// obeys the same grammar, with the name of the server as the noun.
///
/// `Sendable`, because `MultiTool.Registry` is `Sendable` and holds the
/// tools of each capability. A capability that crosses a task boundary is
/// the usual case, and not a special case.
public protocol Capability: Sendable {
    /// The one namespace that each tool of this capability renders under —
    /// the first segment of `tools.<noun>.<verb>`.
    ///
    /// The noun must be a legal TypeScript identifier. `MultiTool.Builder`
    /// examines it at `buildRegistry()`, and not at registration — see
    /// `MultiToolBuilderError` for why no registration method throws. Two
    /// capabilities that give the same noun and the same verb are also a
    /// failure at `buildRegistry()`, and not a silent failure at dispatch.
    var noun: String { get }

    /// The tools of this capability, in the order they render.
    ///
    /// Each tool gives its own verb through `Tool.name`.
    /// `MultiTool.Builder.withCapability(_:)` gives the noun to each one.
    var tools: [any Tool] { get }
}
