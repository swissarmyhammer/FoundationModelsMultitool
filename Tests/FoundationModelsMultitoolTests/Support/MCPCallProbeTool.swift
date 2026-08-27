// `MCPCallProbeTool` — the one `Tool` the call suites mount on the run plane
// of Router, and the mount and the error capture both suites share.
//
// `MCPServerCallTests` and `LostCallTests` each need three things: a plain
// `Tool` whose body is one `MCPServer.call(name:arguments:)`, the mount of
// that tool on the shared engine with a sink the test reads back, and the
// error a call threw, as a value a test can pattern-match. Each stands here
// one time, so neither suite carries a copy of the other's.

import FoundationModels
import FoundationModelsRouter
import MCP
import Testing
import ULID

@testable import FoundationModelsMultitool

/// A tool that calls one named tool of an `MCPServer` through
/// `MCPServer.call(name:arguments:)` and answers the rendered result.
///
/// A plain synchronous `Tool`, exactly what an MCP verb is under the
/// phase-4 note of eventplan.md: it declares no mount, so the site that
/// mounts it decides whether it runs to completion or in the background.
struct MCPCallProbeTool: FoundationModels.Tool {
    /// The `tools.*` name this probe installs under.
    static let probeName = "mcpProbe"

    let name = MCPCallProbeTool.probeName
    let description = "Calls one tool of an MCP server and answers its rendered result."

    /// The connected server the call goes to.
    let server: MCPServer

    /// The name of the tool of `server` the call names.
    let toolName: String

    /// The arguments of the call, or `nil` for a tool that takes none.
    let callArguments: [String: Value]?

    func call(arguments: NoArguments) async throws -> String {
        let result = try await server.call(name: toolName, arguments: callArguments)
        return ToolContentRenderer.render(result: result, budget: RenderBudget.default)
    }
}

/// The mount and the error capture the call suites share.
enum MCPCallProbe {
    /// Mounts `probe` on the shared engine of Router in run-to-completion
    /// mode, over `mailbox`, with `sink` as the upstream sink — the mount
    /// `RoutedModel.makeSession` applies to every tool of a session.
    ///
    /// The sink is handed to the engine directly, and not through an
    /// `AmbientUpstreamSink`, so every event a run posts carries that run's
    /// own `completionToken` as its `correlationID`, which is what a test of
    /// the correlation of two concurrent runs reads.
    ///
    /// - Parameters:
    ///   - probe: The probe to mount.
    ///   - mailbox: The session mailbox the engine tracks the run in.
    ///   - sink: The upstream sink the run's events reach.
    /// - Returns: The mounted engine.
    /// - Throws: When the decorator did not preserve the probe's own types.
    static func mountedRunToCompletion(
        _ probe: MCPCallProbeTool, mailbox: SessionMailbox, sink: any OperationEventSink
    ) throws -> any FoundationModels.Tool<NoArguments, String> {
        try #require(
            ToolMounting.makeWrapped(
                tool: probe,
                sessionID: ULID(),
                mailbox: mailbox,
                sink: sink,
                configuration: .synchronous
            ) as? any FoundationModels.Tool<NoArguments, String>
        )
    }

    /// The error `body` threw, or `nil` when it returned.
    ///
    /// `#expect(throws:)` reports the mismatch and gives the error no name a
    /// test can pattern-match on, so a case that reads the thrown value —
    /// its enum case, its protocol conformance — takes it from here.
    ///
    /// - Parameter body: The call that is expected to throw.
    /// - Returns: The thrown error, or `nil`.
    static func thrownError(from body: () async throws -> Void) async -> (any Error)? {
        do {
            try await body()
            return nil
        } catch {
            return error
        }
    }
}
