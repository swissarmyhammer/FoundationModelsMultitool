---
assignees:
- claude-code
depends_on:
- 01M112EG33CSGN466M9BHVD8C0
- 01M112BHBVEYK3ZZH0RGQRTXXY
- 01M112GT1BAATTYMYSX7VN4NK5
- 01M112FXM6H40D8C5YS0PVNXQQ
position_column: todo
position_ordinal: 8f80
title: 'multitool-cli: attach stdio MCP servers with --mcp'
---
## What
eventplan.md § "We remove OperationTool": "`multitool-cli` becomes the single demo and test binary." Give it the MCP capability so the end-to-end path (stdio subprocess → server → verb → snippet) has one runnable demo and one gated test. The CLI is the reference host for the MCP lifetime: it starts the `SurfaceRefresher` after the session tools and stops it in the sweep.

- Modify `Sources/MultitoolCLI/CLIRunner.swift`: add a repeatable `--mcp <name>=<command> [args...]` option (one server per option; the name is the noun). For each one, construct `StdioServerProcess`, construct and connect an `MCPServer`, and pass the servers to `withMCP(servers:)` in the demo profile. Print the rendered group in the surface listing the CLI already prints.
- After `makeSessionTools`, make the `SurfaceRefresher` and call `start()`. On exit, after the session sweep, call `MCPServerPool.shutdownAll()` (which stops the refresher and ends the subprocesses).
- Modify `Sources/MultitoolCLI/DemoTools.swift` only if the demo profile needs a hook for the servers.
- Update the CLI usage text and the `README.md` CLI section with one example that uses `mcp-test-server`.

## Acceptance Criteria
- [ ] `multitool-cli --mcp echo=.build/debug/mcp-test-server` lists `tools.echo.<verb>` in the surface listing.
- [ ] A prompt that makes the model call `tools.echo.echo` returns the server's answer (gated integration test; the unit test runs the snippet path with the direct-mode registry, without a model).
- [ ] A bad `--mcp` value (no `=`, or a command that does not start) exits with `CLIRunner.ExitCode.usageError` (64) and a one-line message.
- [ ] The process exits with no running server subprocess left behind (`ProcessRegistry.global` is empty after `run`).
- [ ] `swift build` succeeds.

## Tests
- [ ] Extend `Tests/FoundationModelsMultitoolTests/CLIArgumentTests.swift` (`@Suite("CLIRunner")`): parse cases for `--mcp`, the usage-error case, a direct-mode run that calls `tools.echo.echo` over the built `mcp-test-server` executable, and the clean-exit case.
- [ ] Add one gated case to `IntegrationTests/` that runs the prompt against the demo profile with `--mcp`.
- [ ] `swift test --filter CLIArgumentTests` passes.

## Workflow
- Use `/tdd` — write the parse and usage tests first, then implement. #eventplan #phase-4