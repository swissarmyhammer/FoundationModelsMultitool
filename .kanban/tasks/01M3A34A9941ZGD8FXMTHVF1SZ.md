---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3exwnr0b7mqdm49wncm8458
  text: |-
    ### decision — 2026-09-26
    The user decides: all live web tests are in the existing `IntegrationTests/` package (task ^gf2geha removes `WebIntegrationTests/`). This workflow task must change: there is no separate web package. The job that runs the live web tests must get the API key secrets, and the DuckDuckGo live suite must still run only on the daily `schedule` trigger (decision of 2026-09-26, ^zfah7d8). Check if the shared `swift-ci.yaml` workflow can pass secrets and a schedule-only filter; if not, use a separate workflow that runs `swift test --package-path IntegrationTests` with a filter for the web suites. Update this card's description before you implement (pass `tags: ["web"]`).
  timestamp: 2026-09-26T13:18:51.136950+00:00
- actor: claude-code
  id: 01m3eybhap2bw2ytxpb62c9j23
  text: 'Note from ^gf2geha (2026-09-26): the live web suites are now in `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Web/`. `ci.yml` runs the whole `IntegrationTests` package in its integration job on `push` and `pull_request`, thus that job now also runs `DuckDuckGoHTMLLiveTests`. A challenge page is a known issue there and does not fail the job, but the "schedule only" decision needs a change (for example a skip of that suite in the `ci.yml` integration run, if the shared `swift-ci.yaml` can pass one). `ci.yml` already builds `IntegrationTests` in its unit job on each run, thus the compile coupling of the web suites is already there. `web.md` § "CI" now states this.'
  timestamp: 2026-09-26T13:26:58.134370+00:00
- actor: claude-code
  id: 01m3f1jnzf20m77zrqm3nqhh7d
  text: Note from ^wcz6nmr (2026-09-26). The user decision on ^wcz6nmr removes `ExpectedProvidersTests`. No test reads `MULTITOOL_WEB_EXPECTED_PROVIDERS` now. Thus the `MULTITOOL_WEB_EXPECTED_PROVIDERS` line of this card (and the last bullet of web.md § "Testing / CI") has no reader. Also, `KeyedProviderLiveTests` (six tests) ALWAYS runs and FAILS when its key variable is not set. `KeyedFallbackLiveTests` needs no key. The Level 2 `--filter` in web.md does not name `KeyedProviderLiveTests` or `KeyedFallbackLiveTests` yet. A person must decide which of the two keyed suites this workflow runs, and which secrets it maps, before this card starts. ^wcz6nmr did not change web.md § "CI".
  timestamp: 2026-09-26T14:23:17.999477+00:00
- actor: claude-code
  id: 01m3f2trh33wkja7mhmfms923x
  text: |-
    ### decision — 2026-09-26 (final, replaces the earlier CI decisions)
    The user decides: follow the pattern of the sibling repositories.
    - Do NOT add `.github/workflows/web.yml`. `ci.yml` keeps calling the shared `swift-ci.yaml`, and the web live suites run in its existing integration job (`integration-package-path: IntegrationTests`).
    - No API key secrets in CI. The keyed live tests run only when their key is set (new task), so they are skipped in CI.
    - The DuckDuckGo "daily schedule only" rule is DROPPED. DuckDuckGo runs in the normal integration job; its challenge page is a known issue, not a failure.
    - `MULTITOOL_WEB_EXPECTED_PROVIDERS` and `ExpectedProvidersTests` are gone.
    Rewrite this card to: update web.md § "Testing" / "CI" (and the DuckDuckGo decision paragraph) to state these rules; check `ci.yml` and `CIWorkflowTests.swift` need no change, or change only what the rules require; make sure no text names web.yml. Pass `tags: ["web"]` on the update.
  timestamp: 2026-09-26T14:45:11.331120+00:00
depends_on:
- 01M3A33HKP5H238CS992MAJYVS
- 01M3A3FMG0S72N2Q515319Z6S4
- 01M3A33SMXZ93N45S1SWCZ6NMR
- 01M3EXW2YT5AH23TP2PGF2GEHA
- 01M3F2TJB4XSKRRCKW236732BT
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