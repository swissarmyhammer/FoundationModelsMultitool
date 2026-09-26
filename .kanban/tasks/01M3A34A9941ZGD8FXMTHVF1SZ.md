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
- actor: claude-code
  id: 01m3f4fqw7zkqar5nnzwmy3hqc
  text: |-
    Research (implement, 2026-09-26):
    - Outside `.kanban/`, only `web.md` names `web.yml`, `web-integration`, the secrets, `MULTITOOL_WEB_EXPECTED_PROVIDERS`, and the daily-only rule (the file map line, the DuckDuckGo decision paragraph, and § "CI").
    - `.github/workflows/ci.yml` already calls the shared `swift-ci.yaml` with `integration-package-path: IntegrationTests` and `integration-no-parallel: true`. Its integration job runs every suite of `IntegrationTests/`, thus it also runs the live web suites in `Web/`. It maps no secret.
    - `CIWorkflowTests` pins only the `uses:` line and the five `with:` inputs. It reads no comment text. `WebDocumentationTests` reads `README.md` and `docs/SECURITY.md`, not `web.md` or `ci.yml`.
    - The ci.yml comment "The real-model suite is a nested package" does not tell that the package now also holds the live web suites. I update that comment only; no input changes.
  timestamp: 2026-09-26T15:14:07.367399+00:00
- actor: claude-code
  id: 01m3f4k7bfe1vwyfvapb3e9nbx
  text: |-
    ### implement — changed
    - evidence: 2 files — web.md (file map line of web.yml removed; Level 2 filter names all nine web suites, plus a sentence that the whole IntegrationTests run includes them; DuckDuckGo paragraph now says it runs in the normal integration job; § "CI" rewritten: no separate workflow, no secrets, keyed tests skipped in CI, DuckDuckGo on each trigger), .github/workflows/ci.yml (comment only, above `integration-package-path`; no input changed). CIWorkflowTests.swift has no change: it pins only the inputs. `rg -n "web\.yml|MULTITOOL_WEB_EXPECTED_PROVIDERS|ExpectedProvidersTests" --glob '!.kanban/**'` finds nothing (exit 1). `swift test --filter "CIWorkflowTests|WebDocumentationTests"`: 8 tests in 2 suites passed. Root `swift test`: 1796 tests in 145 suites passed, 0 failed.
    - note: the root build prints one SwiftPM build-system line "warning: missing creator for mutated node: .../mlx-swift_Cmlx.bundle/Contents/MacOS". It comes from the mlx-swift bundle build, not from this change (this change touches no Swift source).
    - next: /review
  timestamp: 2026-09-26T15:16:01.519440+00:00
- actor: claude-code
  id: 01m3f4ytevsp0djwzrmsm4bxny
  text: |-
    ### test — green
    - evidence: `swift test` — 1796 tests passed, 0 failed, 0 skipped, in 145 suites. `swift build --build-tests --package-path IntegrationTests` — build complete, 0 warnings from repository code.
    - method: ran `swift package clean`, then a full rebuild of the root package and of `IntegrationTests`, to make sure no warning could hide in a cached build.
    - note: the build shows 4 warnings from the vendored `mlx-swift` dependency, under `.build/checkouts/mlx-swift/Source/Cmlx` and `IntegrationTests/.build/checkouts/mlx-swift/Source/Cmlx` (message: "constexpr if is a C++17 extension"). These files are not part of this repository. This report states them but does not change them.
    - next: none. The build is clean.
  timestamp: 2026-09-26T15:22:21.531792+00:00
depends_on:
- 01M3A33HKP5H238CS992MAJYVS
- 01M3A3FMG0S72N2Q515319Z6S4
- 01M3A33SMXZ93N45S1SWCZ6NMR
- 01M3EXW2YT5AH23TP2PGF2GEHA
- 01M3F2TJB4XSKRRCKW236732BT
position_column: doing
position_ordinal: '80'
title: 'Web: run the live web suites in the existing CI integration job'
---
## What
Run the live web suites (Level 2) in the existing CI integration job. Follow the pattern of the sibling repositories. Design: `web.md` § "Testing" and § "CI". Decision: the comment "decision — 2026-09-26 (final, replaces the earlier CI decisions)".

- Do NOT add `.github/workflows/web.yml`. `ci.yml` keeps calling the shared `swift-ci.yaml`. The live web suites are in `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Web/`, thus the existing integration job (`integration-package-path: IntegrationTests`) runs them.
- No API key secrets in CI. A keyed live test runs only when its key is set (task ^36732bt), thus CI skips the six tests of `KeyedProviderLiveTests`.
- The DuckDuckGo "daily schedule only" rule is dropped. `DuckDuckGoHTMLLiveTests` runs in the normal integration job. Its challenge page is a known issue, not a failure.
- `MULTITOOL_WEB_EXPECTED_PROVIDERS` and `ExpectedProvidersTests` are gone.
- Update `web.md` § "Testing" (Level 2 and the DuckDuckGo decision paragraph) and § "CI" to state these rules. Remove each mention of `web.yml`, of a separate web job, of secrets, of `MULTITOOL_WEB_EXPECTED_PROVIDERS`, and of the daily-only rule. The Level 2 filter command names all web suites.
- Change `ci.yml` and `CIWorkflowTests.swift` only where these rules need it (for example a comment in `ci.yml` that names the live web suites).

## Acceptance Criteria
- [x] No file `.github/workflows/web.yml`.
- [x] `web.md` § "CI" states: the integration job of `ci.yml` runs the live web suites, CI maps no API key secret, the keyed live tests are skipped in CI, and DuckDuckGo runs in the normal job.
- [x] The Level 2 filter command in `web.md` names each web suite, including `KeyedProviderLiveTests`, `KeyedFallbackLiveTests`, and `LiveProviderSettingTests`.
- [x] `rg -n "web\.yml|MULTITOOL_WEB_EXPECTED_PROVIDERS|ExpectedProvidersTests" --glob '!.kanban/**'` finds nothing.
- [x] The inputs of the shared call in `ci.yml` do not change.

## Tests
- [x] `swift test --filter "CIWorkflowTests|WebDocumentationTests"` passes.
- [x] The root `swift test` passes. #web