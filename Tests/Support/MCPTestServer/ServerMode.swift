// `ServerMode` — which tool set `mcp-test-server` registers.
//
// A behavioral port of
// `../FoundationModelsMCP/Sources/MCPTestServer/ServerMode.swift`. Test
// support — see the header of `ScriptedServer.swift`. The source named the
// `Examples/` executable each mode served; this package ships no examples,
// and the one new mode, `loopback`, serves the three tools the MCP suites
// cite by name.

import MCP

/// The tool set the `mcp-test-server` executable registers on the server it
/// starts, selected by its `--mode` command-line argument.
///
/// Exists so that `main.swift` stays a thin dispatcher: the parse and the
/// dispatch stand here, in a tested library, and not as top-level executable
/// code. ``all`` is the default for a caller that passes no `--mode` flag.
public enum ServerMode: String, Sendable, CaseIterable {
    /// Registers only ``ScriptedServer/addEchoTool(named:description:)``.
    case echo

    /// Registers only ``ScriptedServer/addFilesystemTools(initialFiles:)``.
    case fileSystem

    /// Registers only an elicit-on-command tool, through
    /// ``ScriptedServer/addElicitingTool(named:message:requestedSchema:preElicitationDelay:postElicitationStall:)``,
    /// under ``elicitOnCommandToolName``.
    case eliciting

    /// Registers only ``ScriptedServer/addCatalogShowcaseTool(named:)`` — one
    /// tool that fills every catalog-facing field.
    case catalog

    /// Starts ``ScriptedServer/startDynamicToolsetScenario()`` — a tool set
    /// that adds, re-schemas and removes a tool on a timer.
    case dynamic

    /// Registers only ``ScriptedServer/addSlowBuildTool(named:totalSteps:stepDelay:)``
    /// at its default cadence of about twenty steps, about one second apart.
    case longRunning

    /// Registers ``ScriptedServer/addLoopbackTools()`` — `echo`, `elicitEcho`
    /// and `elicitURL`, the three tools the MCP suites cite by name — so a
    /// gated case in `IntegrationTests/` that cannot script a server
    /// in-process still reaches `elicitEcho` over stdio.
    case loopback

    /// Registers the echo tool and the filesystem tools — the default when no
    /// `--mode` flag is given.
    case all

    /// The command-line flag ``parse(from:)`` searches `arguments` for.
    public static let flagName = "--mode"

    /// Parses a `--mode` argument out of `arguments`. The answer is ``all``
    /// when the flag is absent, has no value after it, or names no mode.
    ///
    /// - Parameter arguments: The command-line arguments to search, usually
    ///   `CommandLine.arguments`.
    /// - Returns: The selected mode, or ``all``.
    public static func parse(from arguments: [String]) -> ServerMode {
        guard let flagIndex = arguments.firstIndex(of: flagName),
            arguments.indices.contains(flagIndex + 1),
            let mode = ServerMode(rawValue: arguments[flagIndex + 1])
        else {
            return .all
        }
        return mode
    }

    /// The tool name ``eliciting`` registers.
    public static let elicitOnCommandToolName = "elicit_on_command"

    /// The slow-build tool name ``longRunning`` registers — `public` because
    /// it is the default argument of a public function; see
    /// ``ScriptedServer/defaultSlowBuildStepCount``.
    public static let slowBuildToolName = "slow_build"

    /// The elicitation prompt the tool of ``eliciting`` sends.
    private static let elicitOnCommandMessage = "What is your favorite color?"

    /// The `requestedSchema` the tool of ``eliciting`` sends: one required,
    /// ordinary string field.
    private static let elicitOnCommandRequestedSchema = Elicitation.RequestSchema(
        properties: ["favoriteColor": .object(["type": .string("string")])],
        required: ["favoriteColor"]
    )

    /// Registers the tool set of this mode on `server`.
    ///
    /// - Parameter server: The server to register tools on.
    public func registerTools(on server: ScriptedServer) async {
        switch self {
        case .echo:
            await server.addEchoTool()
        case .fileSystem:
            await server.addFilesystemTools()
        case .eliciting:
            await server.addElicitingTool(
                named: Self.elicitOnCommandToolName,
                message: Self.elicitOnCommandMessage,
                requestedSchema: Self.elicitOnCommandRequestedSchema
            )
        case .catalog:
            await server.addCatalogShowcaseTool()
        case .dynamic:
            await server.startDynamicToolsetScenario()
        case .longRunning:
            await server.addSlowBuildTool(named: Self.slowBuildToolName)
        case .loopback:
            await server.addLoopbackTools()
        case .all:
            await server.addEchoTool()
            await server.addFilesystemTools()
        }
    }
}
