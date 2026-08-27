// `MCPTool` — the plain synchronous `FoundationModels.Tool` that one server
// tool renders as: the verb of the MCP grammar.
//
// A behavioral port of
// `../FoundationModelsMCP/Sources/FoundationModelsMCP/MCPTool.swift`.
// eventplan.md § "Registration of capabilities": "MCP obeys the same grammar.
// The server is the noun, and the tool is the verb (`tools.github.createIssue`)."
// `Tool.name` is the MCP tool name, and the capability supplies the noun.
//
// **A plain `Tool`, and portable.** `MCPTool` does not conform to
// `BackgroundTool`. A plain `Tool` needs only a `LanguageModelSession`, and
// `BackgroundTool` means nothing without the engine of Router. What the verb
// needs from the run plane, `MCPServer.call(name:arguments:)` reads off the
// ambient `ToolContext` — progress and elicitation when a context is bound,
// and nothing at all when none is (eventplan.md § "The ambient context"). Thus
// one `MCPTool` serves three hosts with no change: a bare Foundation Models
// session, a Router `RoutedSession`, and a MultiTool snippet. The result of an
// MCP call is the value, and it has no content-plane store, so a background
// envelope would give the model a 4 KB tail and nothing else (eventplan.md §
// "The run plane and the content plane are different surfaces"). That is why
// the verb is synchronous. A host that mounts a long MCP verb on the native
// path gives it a background `ToolMount` at the mount site; the verb itself
// declares none.
//
// **What is not ported.** The soft deadline (`waiting(for:)`, `wait`), the
// Operations-shaped route (`operationRoute`, `routingOperationEvents(through:)`),
// the `renamed(to:)` and `bound(to:)` copies, and the `MCPToolCalling` seam
// are gone. The server is the one seam, and the catalog entry is the one
// source of the metadata. `rendering(withBudget:)` stays: it is the per-tool
// half of the render budget.
//
// **Verb legality.** The rule is `ToolAPIRenderer.isLegalTSIdentifier` in
// `Surface/ToolAPIRenderer.swift` (`[A-Za-z_$][A-Za-z0-9_$]*`), and the
// renderer throws `ToolAPIRendererError` for an illegal `Tool.name` at
// `buildRegistry()`; this type neither checks nor rewrites the name, so
// `findAPIs` shows the name the model calls.
//
// **The type is internal**, the way `Execute` and `Read` are: the capability
// that registers the verbs of a connected server is the production caller,
// and the tests reach the type with `@testable import`.

import FoundationModels
import MCP

/// The `FoundationModels.Tool` adapter that turns one MCP server tool into a
/// tool a `LanguageModelSession` can call.
///
/// One `MCPTool` stands for exactly one tool of one ``MCPServer``: its
/// `Arguments` is the opaque `GeneratedContent` produced by constrained
/// generation against the converted ``parameters`` schema, and
/// ``call(arguments:)`` is a pure pass-through — encode the generated
/// arguments, forward them to ``MCPServer/call(name:arguments:)``, and render
/// whatever the server returns. The server is the authoritative validator of
/// the call, and its `isError` reaches the model in band through
/// `ToolContentRenderer`; this type never re-validates, repairs, or retries a
/// call itself.
struct MCPTool: FoundationModels.Tool {
    /// `GeneratedContent` already conforms to `ConvertibleFromGeneratedContent`
    /// (the identity conversion), so no per-tool `Generable` type is needed.
    typealias Arguments = GeneratedContent

    /// The catalog entry of the server tool — the one source of the name, the
    /// description, the converted ``parameters`` and the raw `outputSchema`
    /// the renderer validates a `structuredContent` result against.
    let entry: MCPCatalogEntry

    /// The connected server every ``call(arguments:)`` goes to — the one
    /// seam of this verb.
    let server: MCPServer

    /// The render budget this tool's calls use, or `nil` (the default) to
    /// use the server's own ``MCPServer/renderBudget``. Only
    /// ``rendering(withBudget:)`` sets it — the per-tool override, for
    /// marking one known-verbose tool `RenderBudget.unlimited` without
    /// moving the whole server's default.
    private let renderBudget: RenderBudget?

    /// The tool's name, verbatim from the server — the verb the model calls.
    var name: String { entry.name }

    /// The tool's description, verbatim from the server, or an empty string
    /// if the server declared none.
    var description: String { entry.description }

    /// The tool's argument schema, converted from the server's `inputSchema`
    /// by `SchemaConverter` when the catalog entry was built — the schema a
    /// `LanguageModelSession` constrains generation against.
    var parameters: GenerationSchema { entry.parameters }

    /// Always `true`: the converted ``parameters`` schema is injected into
    /// the model's instructions so it knows this tool's argument shape.
    let includesSchemaInInstructions = true

    /// Creates the verb for one catalog entry of one server.
    ///
    /// - Parameters:
    ///   - entry: The catalog entry of the server tool.
    ///   - server: The connected server every call goes to.
    init(entry: MCPCatalogEntry, server: MCPServer) {
        self.init(entry: entry, server: server, renderBudget: nil)
    }

    /// The one designated initializer, which ``rendering(withBudget:)`` also
    /// builds its copy through.
    ///
    /// - Parameters:
    ///   - entry: The catalog entry of the server tool.
    ///   - server: The connected server every call goes to.
    ///   - renderBudget: The per-tool render budget, or `nil` for the
    ///     server's own.
    private init(entry: MCPCatalogEntry, server: MCPServer, renderBudget: RenderBudget?) {
        self.entry = entry
        self.server = server
        self.renderBudget = renderBudget
    }

    /// Returns a copy of this tool whose calls render with `budget`, leaving
    /// every other property — name, description, parameters, and the server
    /// it calls — unchanged.
    ///
    /// The per-tool half of the render budget's host overrides (see
    /// `RenderBudget`): a host that also caps *this* tool's output downstream
    /// can mark it `RenderBudget.unlimited` so this package's own trimming
    /// never composes with that downstream cap, while every other tool on the
    /// same server keeps trimming at the server's own default.
    ///
    /// - Parameter budget: The render budget this tool's calls use.
    /// - Returns: A copy of this tool that renders with `budget`.
    func rendering(withBudget budget: RenderBudget) -> MCPTool {
        MCPTool(entry: entry, server: server, renderBudget: budget)
    }

    /// Calls the server tool and renders its result for the model.
    ///
    /// Encodes `arguments` into the argument map of `tools/call`, forwards it
    /// verbatim to ``MCPServer/call(name:arguments:)``, and renders whatever
    /// comes back — success, `isError`, or `structuredContent` — through
    /// `ToolContentRenderer` against this tool's own declared `outputSchema`,
    /// under this tool's own budget or the server's. An `isError` result is
    /// rendered, never thrown: the server's failure is content the model
    /// reads and can react to. So are the two in-band answers of the server,
    /// a server that is not `.ready` and a bare call that exceeded
    /// `MCPServer.callTimeout`.
    ///
    /// - Parameter arguments: The generated arguments, already constrained
    ///   against ``parameters`` by the calling session.
    /// - Returns: The rendered `tools/call` result.
    /// - Throws: `GeneratedContentCodecError.argumentsRequireObject` if
    ///   `arguments.kind` is not `.structure`, or what
    ///   ``MCPServer/call(name:arguments:)`` throws — `CancellationError`
    ///   when the calling `Task` was cancelled, `MCPServerError.lost` when
    ///   the transport dropped under the request, or the JSON-RPC error the
    ///   server answered with, unchanged.
    func call(arguments: GeneratedContent) async throws -> String {
        let mcpArguments = try GeneratedContentCodec.arguments(from: arguments)
        let result = try await server.call(name: entry.name, arguments: mcpArguments)
        return ToolContentRenderer.render(
            result: result, outputSchema: entry.outputSchema, budget: renderBudget ?? server.renderBudget)
    }
}
