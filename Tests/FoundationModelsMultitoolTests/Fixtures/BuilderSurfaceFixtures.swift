import FoundationModels

// MARK: - M2.5 `MultiTool.Builder` / `APISurface` fixtures (plan.md
// "Adding tools is the easy path" + Component 2/7)
//
// Reuses `WeatherTool` / `PlainTextTool` / `StringArgument` /
// `PlainTextOutput` from `ToolAPIRendererFixtures.swift` (same test
// target) for the standalone half of the golden surface, and adds small
// "group" fixture tools under plan.md's own worked example names
// (`tools.github.createIssue`, `tools.github.search`).

/// The `Arguments` of `GithubCreateIssueTool` — one required `title`.
@Generable
struct CreateIssueArguments {
    @Guide(description: "the issue title.")
    var title: String
}

/// A group fixture tool — `tools.github.createIssue`, plan.md's own
/// worked example name for `addGroup(named: "github", …)`.
struct GithubCreateIssueTool: Tool {
    let name = "createIssue"
    let description = "Creates a GitHub issue."

    func call(arguments: CreateIssueArguments) async throws -> PlainTextOutput {
        PlainTextOutput(text: "created")
    }
}

/// The `Arguments` of `GithubSearchTool` / `GitlabSearchTool` — one
/// required `query`.
@Generable
struct SearchArguments {
    @Guide(description: "the search query.")
    var query: String
}

/// A second group fixture tool — `tools.github.search`, plan.md's other
/// worked example name for the same group.
struct GithubSearchTool: Tool {
    let name = "search"
    let description = "Searches GitHub issues."

    func call(arguments: SearchArguments) async throws -> PlainTextOutput {
        PlainTextOutput(text: "results")
    }
}

/// A different group's `search` tool — same bare name as
/// `GithubSearchTool`, different group. Proves "duplicates across groups
/// are fine" (plan.md Resolved #5): `tools.github.search` and
/// `tools.gitlab.search` are both legal, distinct paths.
struct GitlabSearchTool: Tool {
    let name = "search"
    let description = "Searches GitLab issues."

    func call(arguments: SearchArguments) async throws -> PlainTextOutput {
        PlainTextOutput(text: "results")
    }
}

/// A tool whose `name` isn't a legal TypeScript identifier — proves
/// `MultiTool.Builder.build()`'s completeness contract: a tool that can't
/// be fully rendered by `ToolAPIRenderer` makes `build()` throw rather
/// than emit a lossy stub.
struct IllegalNameTool: Tool {
    let name = "bad name!"
    let description = "A tool whose name can't be rendered."

    func call(arguments: StringArgument) async throws -> PlainTextOutput {
        PlainTextOutput(text: arguments.value)
    }
}
