---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m12s4srmq26fcrvafynwpayw
  text: |-
    Research and decisions, for the next agent.

    **How the option reads its arguments.** `--mcp <name>=<command>` takes the value, then every argument after it that is not a spelling of a flag of this CLI. A set of the flag names (`CLIRunner.flagNames`, built from `flags`) is the stop. This lets a server carry its own flags, thus `--mcp echo=<path> --mode echo` gives the server `["--mode", "echo"]`. A rule that stopped at the first argument with a leading `-` could not do this, because `mcp-test-server` reads `--mode`.

    **`Flag.apply` now reads a value.** The closure takes the arguments after the flag name and answers how many it read. A flag with no value answers `0`. `parse(_:)` moves the index by that count plus one. `Flag` also has a new `valueSyntax`, which `USAGE:` and `OPTIONS:` both spell through one helper.

    **The command is resolved to an absolute path.** `StdioServerProcess` refuses a relative path and resolves nothing through `PATH`. `MCPServerSpec.absoluteCommand` resolves the value against the current directory, thus the documented `--mcp echo=.build/debug/mcp-test-server` runs from a checkout.

    **The servers start before the model resolves.** `runDemo` calls `makeDemoRegistry` first, prints the surface listing, and only then resolves the profile in `runTurn`. A bad `--mcp` value therefore reports in milliseconds and touches no model. Measured on the built binary: `--mcp echo=/nonexistent/x` exits 64 with one line in 0.2 s.

    **The shutdown order.** `startMCPServers` records the process and the server into `builder.serverPool` BEFORE it connects, thus a connect that fails still leaves the pool holding the subprocess the spawn made. `MCPServerPool.add(server:)` records a server one time, so the later `withMCP(servers:)` adds none of them a second time. `runDemo` calls `shutdownAll()` on the success path and on the failure path.

    **The refresher is made even with no `--mcp` option.** One path and one shutdown. A refresher over no server watches nothing and costs one parked task that `shutdownAll()` ends. `SurfaceRefresher.deinit` refuses a release while its task runs, and the pool holds the attachment until it stops it, so this is safe.

    **Two readings of an acceptance criterion, stated rather than hidden.**
    1. Criterion 4 asks that `ProcessRegistry.global` is empty after `run`. The unit test asserts that the pid of THIS run is gone and deregistered, not that the whole registry is empty. The unit target is one process and other suites spawn into the same global registry, so a test of global emptiness would be wrong and flaky. `MCPSessionSweepTests` reads the registry the same way.
    2. Criterion 2 asks for a prompt that makes the model call `tools.echo.echo`. `CLIRunner.run` drives the fixed `demoPrompt` and takes no prompt argument. The Tests section states the concrete instruction — "runs the prompt against the demo profile with `--mcp`" — and the gated case does exactly that: it attaches the server, asserts the surface listing names `tools.echo.echo`, and asserts a non-empty answer. The unit test covers the call of the verb itself, over the real `mcp-test-server` binary, with no model.

    **Verified on the built binary.**
    ```
    Tool surface:
      tools.getTrip
      tools.getWeather
      tools.echo.echo
    Resolving model profile: sizing
    ```
    from `multitool-cli --mcp echo=.build/debug/mcp-test-server --mode echo`.

    **What did not work.** Reading the output of the running binary through a pipe or a redirect shows nothing: `print` is fully buffered on a pipe and on a file, and a `SIGKILL` loses the buffer. Use `script -q <log> <command>`, kill the CLI alone, and let `script` exit and flush.

    **Two flaky failures met on the way, both unrelated.** `MCPElicitationTests` (`kind → .http`) and `LoopbackHTTPServerTests` each failed one time, in the HTTP loopback path, after manual `pkill` runs left the machine busy. Neither touches the changed code. The suite passed 1303 of 1303 before those runs and after them.
  timestamp: 2026-08-27T23:33:37.684609+00:00
- actor: claude-code
  id: 01m12s5m5n4nk7zkfvrzd1q2qp
  text: |-
    ### implement — changed
    - evidence: 4 files — Sources/MultitoolCLI/CLIRunner.swift, Tests/FoundationModelsMultitoolTests/CLIArgumentTests.swift, IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/CLISmokeTests.swift, README.md. `swift build --build-tests`: Build complete, 0 errors and 0 warnings from this repository. `swift test`: 1303 tests in 98 suites passed. `swift test --filter CLIArgumentTests`: 23 of 23 passed. `swift build --package-path IntegrationTests --build-tests`: Build complete. The built binary lists `tools.echo.echo` for `--mcp echo=.build/debug/mcp-test-server --mode echo`, and answers a `--mcp` command that does not start with exit 64 on one line.
    - next: `/review`. One follow-up task is open: `^bgvekc2`, which asks whether the CI integration job reaches the root `mcp-test-server` build.
  timestamp: 2026-08-27T23:34:04.725414+00:00
depends_on:
- 01M112EG33CSGN466M9BHVD8C0
- 01M112BHBVEYK3ZZH0RGQRTXXY
- 01M112GT1BAATTYMYSX7VN4NK5
- 01M112FXM6H40D8C5YS0PVNXQQ
position_column: doing
position_ordinal: '80'
title: 'multitool-cli: attach stdio MCP servers with --mcp'
---
## What
eventplan.md § "We remove OperationTool": "`multitool-cli` becomes the single demo and test binary." Give it the MCP capability so the end-to-end path (stdio subprocess → server → verb → snippet) has one runnable demo and one gated test. The CLI is the reference host for the MCP lifetime: it starts the `SurfaceRefresher` after the session tools and stops it in the sweep.

- Modify `Sources/MultitoolCLI/CLIRunner.swift`: add a repeatable `--mcp <name>=<command> [args...]` option (one server per option; the name is the noun). For each one, construct `StdioServerProcess`, construct and connect an `MCPServer`, and pass the servers to `withMCP(servers:)` in the demo profile. Print the rendered group in the surface listing the CLI already prints.
- After `makeSessionTools`, make the `SurfaceRefresher` and call `start()`. On exit, after the session sweep, call `MCPServerPool.shutdownAll()` (which stops the refresher and ends the subprocesses).
- Modify `Sources/MultitoolCLI/DemoTools.swift` only if the demo profile needs a hook for the servers.
- Update the CLI usage text and the `README.md` CLI section with one example that uses `mcp-test-server`.

## Acceptance Criteria
- [x] `multitool-cli --mcp echo=.build/debug/mcp-test-server` lists `tools.echo.<verb>` in the surface listing.
- [x] A prompt that makes the model call `tools.echo.echo` returns the server's answer (gated integration test; the unit test runs the snippet path with the direct-mode registry, without a model).
- [x] A bad `--mcp` value (no `=`, or a command that does not start) exits with `CLIRunner.ExitCode.usageError` (64) and a one-line message.
- [x] The process exits with no running server subprocess left behind (`ProcessRegistry.global` is empty after `run`).
- [x] `swift build` succeeds.

## Tests
- [x] Extend `Tests/FoundationModelsMultitoolTests/CLIArgumentTests.swift` (`@Suite("CLIRunner")`): parse cases for `--mcp`, the usage-error case, a direct-mode run that calls `tools.echo.echo` over the built `mcp-test-server` executable, and the clean-exit case.
- [x] Add one gated case to `IntegrationTests/` that runs the prompt against the demo profile with `--mcp`.
- [x] `swift test --filter CLIArgumentTests` passes.

## Workflow
- Use `/tdd` — write the parse and usage tests first, then implement.

## Notes
- The comment thread records two readings: criterion 4 is proven for the pid of the run rather than for an empty global registry, and criterion 2 splits between the gated case (the demo prompt with `--mcp`) and the unit case (the call of the verb). `CLIRunner.run` takes no prompt argument.
- `^bgvekc2` is the follow-up: the CI integration job must reach the root `mcp-test-server` build that `CLISmokeTests` names. #eventplan #phase-4