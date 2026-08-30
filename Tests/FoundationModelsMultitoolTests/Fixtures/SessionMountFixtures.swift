import FoundationModels
import FoundationModelsRouter
import ULID

@testable import FoundationModelsMultitool

// MARK: - The mount a Router session applies
//
// `RoutedModel.makeSession` mounts every tool of a session through
// `ToolMounting.makeWrapped` under `ToolMount.synchronous`: a tool that
// declares a background mount backgrounds, and every other tool runs to
// completion. A suite that examines a tool as a session sees it takes the same
// mount. It stands here one time, thus each suite reads one copy.

/// The mount a Router session applies to every tool it holds.
enum SessionMount {
    /// Mounts `tool` on the shared engine of Router over `mailbox`, with
    /// `sink` as the upstream sink, under `ToolMount.synchronous` — the one
    /// configuration `RoutedModel.makeSession` applies.
    ///
    /// The tool's own declared mount wins over the configuration: a
    /// `MultiTool` backgrounds, and a plain `Tool` such as `MCPTool` runs to
    /// completion.
    ///
    /// - Parameters:
    ///   - tool: The tool to mount.
    ///   - context: The session context the engine mounts on. Take one from
    ///     ``makeStubRun(in:)``.
    /// - Returns: The mounted, model-facing tool.
    static func synchronous(
        _ tool: any Tool, on context: ToolContext
    ) -> any Tool {
        context.mount(tool, as: .synchronous)
    }
}
