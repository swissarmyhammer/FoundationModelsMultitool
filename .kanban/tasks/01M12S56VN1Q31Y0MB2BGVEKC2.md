---
assignees:
- claude-code
position_column: todo
position_ordinal: '9280'
title: 'CI: build mcp-test-server before the integration job runs CLISmokeTests'
---
## What
`CLISmokeTests.demoAttachesAnMCPServer` (added by `^vsacz8f`) attaches a stdio MCP server with `--mcp`, and the command it names is the `mcp-test-server` executable that the ROOT package builds. The nested `IntegrationTests` package builds no such executable: a test target can depend on no executable, so `swift build --package-path IntegrationTests --build-tests` writes `MCPTestServer.o` alone and no binary. Measured on 2026-08-27: `IntegrationTests/.build/debug/` holds no `mcp-test-server`.

The test therefore reads `<repository root>/.build/debug/mcp-test-server`, which the root `swift build` or `swift test` writes. When no executable stands there, the test fails and names the command that writes it: `swift build --product mcp-test-server`.

That is correct on a developer machine, where the root suite runs first. It is not proven for CI. The workflow runs two jobs: the unit job runs the root `swift test`, and the integration job runs `swift test --package-path IntegrationTests`. The integration job declares `needs: test`, which orders the jobs and shares no filesystem of its own. A runner with a persistent workspace keeps the root `.build`, and a fresh runner does not.

## Acceptance Criteria
- [ ] Read `.github/workflows/ci.yml` and the shared `swissarmyhammer/workflows` `swift-ci.yaml`, and state whether the integration job reaches the root `.build` of the unit job.
- [ ] When it does not, make the integration job run `swift build --product mcp-test-server` at the repository root before the suite, or give the shared workflow an input that does.
- [ ] A CI run of the integration job passes `demoAttachesAnMCPServer`.
- [ ] `README.md` states the build step beside the integration command, when the operator must run it.

## Tests
- [ ] One CI run of the integration job, green.

## Workflow
Read the shared workflow first. Change no test to make it pass. #eventplan #phase-4