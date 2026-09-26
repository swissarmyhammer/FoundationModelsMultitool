---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3f2yx7bsgwmjh5dd5hzqw46
  text: |-
    Research:
    - `KeyedProviderLiveTests.swift` has six `@Test` functions and one shared helper `expectHits(from:)`. A private struct `LiveProviderSetting` holds the name and the variables of each provider. Today a missing key fails `#require` with a message that says "This test always runs".
    - `WebConfiguration.fromEnvironment` reads the same variables. An empty variable is not set. `SEARXNG_URL` must also be an `http`/`https` URL with a host.
    - The rule text is in the doc comment of `IntegrationTests/Package.swift` ("The environment rule") and in `web.md` § "Testing" Level 2 ("The environment rule" paragraph and the `KeyedProviderLiveTests` row).
    - `WebResearchScenarioTests.swift` refers to the environment rule for a keyless test that always runs. That text stays correct.
    - There is no `.github/workflows/web.yml` yet.
    Plan: move `LiveProviderSetting` to `Web/Support/LiveProviderSetting.swift` as an internal type with one static value for each provider, an `isSet(in:)` check, and a `ConditionTrait` factory `.enabled(whenSet:in:)`. Add an offline suite `LiveProviderSettingTests` that checks the condition with a given dictionary (no real key), and that each setting agrees with `fromEnvironment`.
  timestamp: 2026-09-26T14:47:27.211350+00:00
- actor: claude-code
  id: 01m3f37axhbe0s9mamhxd9d00b
  text: |-
    Implementation landed (TDD: `LiveProviderSettingTests` came first. The build failed because the helper was private and had no enable condition. Then the new helper made it pass).
    - New `Web/Support/LiveProviderSetting.swift`: the struct moved out of `KeyedProviderLiveTests.swift` and is now internal. It has one static value for each provider (`braveAPI`, `tavily`, `exa`, `serper`, `kagi`, `searxng`, and `all`). It also has `isSet(in:)` (an empty variable is not set, the same as `fromEnvironment()`), `notSetComment` ("<VARIABLE> is not set"), and `notConfiguredComment`. The one shared check is the trait `ConditionTrait.enabled(whenSet:in:)`, which wraps `.enabled(if:_:)`. Its `in:` argument has the process environment as the default value, so a check can give its own dictionary.
    - `KeyedProviderLiveTests.swift`: each of the six `@Test` functions has `.enabled(whenSet: .<provider>)`. The suite doc comment gives the user's exception to `test-integrity/test-partitioning` (2026-09-26, final). The key-leak checks are unchanged. The `#require` stays. It now fails only when a variable is set but `fromEnvironment()` rejects it, for example a `SEARXNG_URL` that is not correct. `KeyedFallbackLiveTests` is unchanged.
    - New `Web/LiveProviderSettingTests.swift` (offline, no real key): checks the condition with `ConditionTrait.evaluate()` (true when set, false when not set), that an empty variable is not set, the `BRAVE_API_KEY` alias, that each setting agrees with `fromEnvironment()`, that the skip comment names each variable, and the list of six providers.
    - `IntegrationTests/Package.swift` and `web.md` Level 2 ("The environment rule" and the `KeyedProviderLiveTests` row) state the rule and the exception. web.md has a new `LiveProviderSettingTests` row.
    - Open point for the user: the Level 2 `--filter` command in web.md (and so a future `web.yml`) does not include `KeyedProviderLiveTests`, `KeyedFallbackLiveTests` or `LiveProviderSettingTests`. This task did not change that command.
    - swiftlint (no_magic_numbers, force rules, function_body_length, line_length 120) found 0 violations, and `swift format lint` found no idiom finding in the three Swift files. The build warning `missing creator for mutated node ... mlx-swift_Cmlx.bundle` comes from the mlx-swift dependency and was there before this change.
  timestamp: 2026-09-26T14:52:03.377064+00:00
- actor: claude-code
  id: 01m3f37gfv911f8y2cbw05hqha
  text: |-
    ### implement — changed
    - evidence: 5 files. Changed: IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Web/KeyedProviderLiveTests.swift, IntegrationTests/Package.swift, web.md. New: IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Web/Support/LiveProviderSetting.swift, IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Web/LiveProviderSettingTests.swift. `swift build --build-tests --package-path IntegrationTests`: build complete. The only warning is the mlx-swift bundle warning that was there before this change. `swift test --package-path IntegrationTests --no-parallel --filter KeyedProviderLiveTests`: 6 tests skipped, 0 failed, and each skip names its variable. Keyless live filter (with KeyedFallbackLiveTests): 14 tests in 7 suites passed, with 2 known issues (the DuckDuckGo challenge page). `LiveProviderSettingTests`: 8 tests passed. Root `swift test`: 1796 tests in 145 suites passed. Each file has fewer than 400 lines (92, 78, 123).
    - next: /review. The task stays in `doing`. Nothing is committed.
  timestamp: 2026-09-26T14:52:09.083918+00:00
- actor: claude-code
  id: 01m3f45rp60837txb1tdzypacy
  text: |-
    ### test — green
    - evidence: Root `swift test`: 1796 tests in 145 suites passed. 0 failures. 0 warnings in this repo's code. `swift build --build-tests --package-path IntegrationTests`: build complete, no code warnings. `swift test --package-path IntegrationTests --no-parallel --filter "KeyedProviderLiveTests|LiveProviderSettingTests"`: 14 tests passed. The 6 keyed tests skipped, each with the correct variable name. This is correct, by the user's decision of 2026-09-26 (no keys are set here). Keyless live filter `swift test --package-path IntegrationTests --no-parallel --filter "BraveHTMLLiveTests|DuckDuckGoHTMLLiveTests|KeylessChainLiveTests|FetchLiveTests|GuardLiveTests|WebRunCodeLiveTests|KeyedFallbackLiveTests"`: 14 tests in 7 suites passed, with 2 known issues from a DuckDuckGo challenge page. This is not a failure, per the task instructions.
    - notes: One build-system warning appeared each build: "missing creator for mutated node" for `mlx-swift_Cmlx.bundle`. This comes from the vendored mlx-swift dependency under `.build/checkouts`. It is out of scope for this repo. Report only, per the task instructions. One runtime line appeared during the root `swift test` run: "SWIFT TASK CONTINUATION MISUSE: connect() leaked its continuation without resuming it." This comes from `HangingTransport.connect()` in `Tests/FoundationModelsMultitoolTests/Support/HangingTransport.swift`. Its own doc comment states this line is expected, not a bug: the transport never resumes its continuation on purpose, to prove the connect timeout works when a transport hangs. No code change was needed.
    - next: None. The build is clean.
  timestamp: 2026-09-26T15:08:40.518540+00:00
- actor: claude-code
  id: 01m3f4de3gqxy41dqb9khcgyvn
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit 142a2e7). 0 findings, 0 confirmed, 0 refuted. The engine reviewed 4 files. It did not review 6 `.kanban/` files (ignore rule) or `web.md` (no validator matches it). The commit has no renamed files. The engine gave no `test-integrity/test-partitioning` finding, so the user's written exception was not necessary.
    - next: The task is in done.
  timestamp: 2026-09-26T15:12:51.824283+00:00
- actor: claude-code
  id: 01m3f4dvtj3wjqstgyd172b112
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 5 files (keyed tests enabled only when the key is set; user exception to test-partitioning)
    - test: green — root 1796 passed; keyed filter 14 passed, 6 skipped (no keys); keyless live 14 passed, 2 known issues
    - commit: 142a2e7
    - review: clean — 0 findings; the task is in done
  timestamp: 2026-09-26T15:13:05.874612+00:00
position_column: done
position_ordinal: ffe980
title: 'Web: run each keyed live test only when its API key is set'
---
## What
The user decided on 2026-09-26 (final): each keyed live test in `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Web/KeyedProviderLiveTests.swift` runs when its API key (or `SEARXNG_URL`) is present and not empty in the environment. When the key is missing, the test is SKIPPED, not failed. This is a written exception from the user to the review rule `test-integrity/test-partitioning` for these six tests only. It replaces the earlier decision "always run, fail when missing".

- Put `.enabled(if: <key is set>, "<VARIABLE> is not set")` on each of the six `@Test` functions (braveAPI: `BRAVE_SEARCH_API_KEY` or `BRAVE_API_KEY`; tavily: `TAVILY_API_KEY`; exa: `EXA_API_KEY`; serper: `SERPER_API_KEY`; kagi: `KAGI_API_KEY`; searxng: `SEARXNG_URL`). Use one shared helper for the check. The skip comment names the variable.
- Put a doc comment on the suite that states the user's exception to `test-partitioning` and the date.
- Keep the key-leak checks, and keep `KeyedFallbackLiveTests` (it uses a literal invalid key and always runs).
- Update the rule text in `IntegrationTests/Package.swift` and `web.md` § "Testing" Level 2: a keyed live test runs only when its key is set, by the user's decision; no other test reads the environment to decide if it runs.

## Acceptance Criteria
- [x] With no key set, `swift test --package-path IntegrationTests --no-parallel --filter KeyedProviderLiveTests` gives 6 skipped tests and 0 failures, and each skip names its variable.
- [x] With a key set, that test runs (verify the enable condition with a unit-style check of the helper, not a real key).
- [x] `IntegrationTests/Package.swift` and `web.md` state the rule and the exception.

## Tests
- [x] Run the filter command above with no keys: 6 skipped, 0 failed.
- [x] Run the keyless live filter and root `swift test`: all pass.

## Workflow
- Use `/tdd` where it applies. #web