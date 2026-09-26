---
assignees:
- claude-code
depends_on:
- 01M3A33HKP5H238CS992MAJYVS
- 01M3A3FMG0S72N2Q515319Z6S4
- 01M3A33SMXZ93N45S1SWCZ6NMR
position_column: todo
position_ordinal: '8e80'
title: 'Web: add the web.yml workflow (web-integration job, daily schedule)'
---
## What
Run the web live package in CI. Design: `web.md` § "Testing / CI".

- Create `.github/workflows/web.yml` with one job `web-integration`. Do not change `ci.yml`.
  - Triggers: `push` to `main`, `pull_request`, `workflow_dispatch`, and `schedule` with `cron: "17 6 * * *"` (daily). The daily run finds markup drift in the keyless providers. A separate file keeps the expensive real-model job of `ci.yml` off the daily schedule.
  - The job has no `needs`. It runs on the macOS 27 runner class that the shared `swift-ci.yaml` uses. Steps: checkout; `swift build --package-path WebIntegrationTests --build-tests`; `swift test --package-path WebIntegrationTests --no-parallel`.
  - The build step on each push and pull request gives the compile coupling that `IntegrationTests/Package.swift:58-66` asks for. The shared workflow has only one package-path input (`integration-package-path`), so the build step is in this job. `web.md` § "CI" records this change from the first design.
  - `env`: map the repository secrets `BRAVE_SEARCH_API_KEY`, `TAVILY_API_KEY`, `EXA_API_KEY`, `SERPER_API_KEY`, `KAGI_API_KEY`. Set `MULTITOOL_WEB_EXPECTED_PROVIDERS` to the provider names (not the secret names) of the secrets that `gh secret list` shows now, for example `braveAPI,tavily`. If no secret exists yet, set it to an empty string and write a comment that names the command to update it.
  - A header comment in STE says why the file is separate and why it reads secrets.

## Acceptance Criteria
- [ ] `.github/workflows/web.yml` has the four triggers, the build line, the test line with `--no-parallel`, each of the five secret mappings, and the `MULTITOOL_WEB_EXPECTED_PROVIDERS` line.
- [ ] `ci.yml` has no change, and the existing `CIWorkflowTests` pass.
- [ ] The DuckDuckGo live suite (`DuckDuckGoHTMLLiveTests`) runs only on the `schedule` trigger. It does not run on `push` or `pull_request`. Decision of 2026-09-26, recorded in `web.md` § "Testing", Level 2, "The DuckDuckGo challenge page", and § "CI" (task ^zfah7d8).

## Tests
- [ ] Create `Tests/FoundationModelsMultitoolTests/WebWorkflowTests.swift`, modelled on `CIWorkflowTests.swift` (read the file with `RepositoryFile.read(relativePath: ".github/workflows/web.yml")`). Pin: `cron:`, `pull_request`, the build line, the test line, each secret mapping, the `MULTITOOL_WEB_EXPECTED_PROVIDERS` line, and that the job has no `needs:` line.
- [ ] In `WebWorkflowTests`, pin that the DuckDuckGo live suite runs only on the `schedule` trigger, and not on `push` or `pull_request`. For example: the test line for `push` and `pull_request` has `--skip DuckDuckGoHTMLLiveTests`, and the step that runs `DuckDuckGoHTMLLiveTests` has the condition `github.event_name == 'schedule'`.
- [ ] Run `swift test --filter "WebWorkflowTests|CIWorkflowTests"`. All pass. Then run `swift test`.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #web