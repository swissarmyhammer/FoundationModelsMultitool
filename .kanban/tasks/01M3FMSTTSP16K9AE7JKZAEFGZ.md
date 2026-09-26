---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3fn9163dq44h562wgx17c48
  text: |-
    ### research
    - `SelectionConfig.sessionSource` is a public `var`. Thus the library can take the host config and wrap each session in `TracedAgentSession` for the two cases `.factory` and `.session`. The preamble and the capacity limit stay as the host set them.
    - The selection seam is a factory keyed by the ids (`SearchToolsTool.SelectionFactory = @Sendable ([String]) throws -> SelectionConfig`). Reason: a Router guided session gets its grammar at creation, and the grammar needs the id set of the catalog.
    - The Ranker checkout in `.build` has `public static func SelectionTier.idEnumSchema(ids:)`. The CLI grammar helper will call it and not build the schema by hand (reuse rule).
    - A top-level `func idEnumGrammar(ids:)` breaks the Swift rule "A function belongs to a type". The moved helper becomes a static member of `SelectionGrammar` in `MultitoolCLI`.
    - Behavior that stays: `makeSessionToolsAndStaging` calls the selection factory one time with the first catalog ids, and the bundle shape keeps that config across swaps (as before). A per-bundle rebuild would need a throwing `RegistryBundle.init`. That is out of scope here.
    - README.md has no `makeSessionTools(librarian:)` example now. Only doc comments in `ExamplesTests` name it.
    - The test target links `MultitoolCLI` already, so the moved tests can import it.
  timestamp: 2026-09-26T20:07:33.315274+00:00
- actor: claude-code
  id: 01m3fnqz80rggwme937rvvm402
  text: |-
    ### implement — changed
    - evidence: new `Discovery/SearchToolsTool+Seams.swift` (`SelectionFactory`, `SessionFactory`, traced wrappers for `.factory` and `.session`); `SearchToolsTool.init(registry:selection:embedder:limit:sampleSession:)` and `Registry.makeSessionTools(AndStaging)(selection:embedder:sampleSession:)` name only registry, Ranker and Multitool types; `RoutedAgentSession`, `RoutedTextEmbedding`, `SelectionGrammar` moved to `Sources/MultitoolCLI/` as public; new `MultitoolCLI/RouterDiscoverySeams.swift` is the one entry point, and `CLIRunner` uses it. `SelectionGrammar.idEnumGrammar(ids:)` is now a static member that wraps `SelectionTier.idEnumSchema(ids:)`. Tests: `SelectionGrammarTests.swift` became `RouterDiscoverySeamsTests.swift` (grammar, id-grammar per session, preamble guard, embedder dimension, sample session); `SearchToolsToolTests` has 4 new seam tests with no Router; the other call sites pass `selection: nil`.
    - Package.swift: no change. `MultitoolCLI` compiles `import FoundationModelsMetadataRegistry` with no declared product, so the compiler does not need it.
    - README.md: no change. It shows no `makeSessionTools(librarian:)` example.
    - Did not work: a test that took `makeStubProfile().flash` and let the profile go crashed — a Router handle holds its profile weakly. The test now keeps the profile alive. Comparing two `Grammar` values from `idEnumSchema` as text failed, because `JSONSerialization` gives no fixed key order; the test compares the decoded schemas.
    - Acceptance rg over `Discovery/` and `MultiTool.swift`: no match.

    ### test — green
    - evidence: `swift build --build-tests` clean (only the pre-existing SwiftPM `missing creator for mutated node` build-system note); `swift test` — 1800 tests in 144 suites passed, 0 failed, 0 skipped.
    - next: commit
  timestamp: 2026-09-26T20:15:42.848869+00:00
- actor: claude-code
  id: 01m3fpafw42gtnb1jk7hg2s1es
  text: |-
    ### review — findings
    - evidence: `review sha HEAD~1..HEAD` — 1 finding (1 confirmed, 0 refuted): `Tests/FoundationModelsMultitoolTests/SurfaceRefresherTests.swift:205` `completeness/public-output-contract`.
    - next: implement the finding.

    ### finish iteration 1 — findings
    - implement: changed — discovery takes the registry seams; the Router adapters and `RouterDiscoverySeams` are in `MultitoolCLI`.
    - test: green — `swift test` 1800 tests in 144 suites passed.
    - commit: changed — 51309ed refactor(discovery)!: take the metadata-registry seams, and move the Router adapters to the CLI host
    - review: findings — 1 open: `SurfaceRefresherTests.swift:205` `completeness/public-output-contract`.
  timestamp: 2026-09-26T20:25:49.700520+00:00
- actor: claude-code
  id: 01m3fpfz94w1g9y3ghm4ajmjvf
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` — 0 findings (7 attempted, 0 failed); the one prior finding is checked.
    - next: task moved to done.

    ### finish iteration 2 — clean
    - implement: changed — `SurfaceRefresherTests.swift:205` gives `selection: nil, embedder: nil, sampleSession: nil` explicitly.
    - test: green — `swift build --build-tests` clean; `swift test` 1800 tests in 144 suites passed, 0 failed, 0 skipped.
    - commit: changed — b5323c5 test(surface): state every discovery seam in the SurfaceRefresherTests mount
    - review: clean — 0 new findings, 1 of 1 prior finding checked.
  timestamp: 2026-09-26T20:28:49.316469+00:00
depends_on:
- 01M3EVKKTGVDQAKH1X7HD44HRE
position_column: done
position_ordinal: fff280
title: Take the metadata-registry seams in the discovery API, and move the Router adapters to the CLI host
---
## What
User decision (2026-09-26): tool discovery must not depend on Router model types. It uses the seams of FoundationModelsMetadataRegistry, which re-exports them from FoundationModelsRanker: `SelectionConfig` / `SelectionSessionSource` (`.factory(@Sendable (String) -> any AgentSession)` or `.session(any AgentSession)`), `any TextEmbedding`, and `AgentSession`. The host picks the models and adapts them.

Current Router coupling in discovery:
- `MultiTool.Builder.makeSessionTools(librarian: RoutedLLM?, embedder: RoutedEmbedder?, sampleGenerator: RoutedLLM?)` and `makeSessionToolsAndStaging(...)` (`Sources/FoundationModelsMultitool/MultiTool.swift:161-230`).
- `SearchToolsTool.init(registry:librarian:embedder:sampleGenerator:)`, `makeSelection(librarian:ids:)`, `makeEmbedding(from:)`, `makeSample(generator:)` (`Sources/FoundationModelsMultitool/Discovery/SearchToolsTool.swift:190-410`).
- The adapters `Discovery/RoutedAgentSession.swift`, `Discovery/RoutedTextEmbedding.swift` and `Discovery/SelectionGrammar.swift` (a Router `Grammar` from the id set). `Capabilities/MCP/SurfaceRefresher.swift` also calls the builder.

Change:
- [x] Change the builder methods and `SearchToolsTool.init` to take registry seams. For example: `selection: SelectionConfig?`, `embedder: (any TextEmbedding)?`, `sampleSession: (@Sendable (String) -> any AgentSession)?`. The selection tier needs the id set to build its grammar (`SelectionTier.idEnumSchema(ids:)`), and the host cannot know it in advance. If so, take a factory keyed by the ids (for example `@Sendable ([String]) throws -> SelectionConfig?`) and write the reason in its doc comment. Keep the `TracedAgentSession` tracing around each session in the library.
- [x] Move `RoutedAgentSession`, `RoutedTextEmbedding` and `SelectionGrammar` out of `Sources/FoundationModelsMultitool/Discovery/` into `Sources/MultitoolCLI/` (for example `RouterDiscoverySeams.swift`). Make them `public` there, because `IntegrationTests` reaches `MultitoolCLI` as a product. Give one entry point that turns a `RoutedLLM` librarian, a `RoutedEmbedder` and an optional `RoutedLLM` generator into the seams. `CLIRunner` uses it.
- [x] Move their tests with them (`SelectionGrammarTests.swift`, `DiscoveryEmbedderTests.swift`, and the `RoutedAgentSession` cases). Change the other unit-test call sites to the new signatures (`SearchToolsToolTests`, `MultiToolExecutionTests`, `SiblingToolPathTests`, `RegistrySwapTests`, `RouterSessionMountTests`, `ExamplesTests`, `FilesCapabilityTests`, `MCPCapabilityTests`, `ShellCapabilityTests`, `OverBudgetSelectionOrderTests`, `SurfaceRefresherTests`, `Support/CapabilityDiscoveryProbe.swift`). Most pass `nil`.
- [x] Update README.md, where it shows `makeSessionTools(librarian:...)`, and `ExamplesTests`, which checks the README examples. (README.md shows no such call; `ExamplesTests` doc comments are updated.)
- [x] Do not change `IntegrationTests/`. Task 01M3ETV0A0AE2F2MTGWTFHF7T4 changes its call sites.

Do not change `SearchToolsTool.mount` (a Router `ToolMount`). That is how a tool mounts on a session, not a model dependency.

## Acceptance Criteria
- [x] `rg -n 'RoutedLLM|RoutedEmbedder|RoutedSession|Grammar\b' Sources/FoundationModelsMultitool/Discovery Sources/FoundationModelsMultitool/MultiTool.swift` returns no match (doc comments included).
- [x] The public discovery API names only registry, Ranker or Multitool types.
- [x] `multitool-cli` still gets selection, embedding and samples through the adapters in `MultitoolCLI`.
- [x] `swift build --build-tests` and `swift test` pass.

## Tests
- [x] `Tests/FoundationModelsMultitoolTests/SearchToolsToolTests.swift`: a `SelectionConfig` over a stub `AgentSession` (no Router) drives selection end to end.
- [x] `Tests/FoundationModelsMultitoolTests/RouterDiscoverySeamsTests.swift` (new, or the moved suites): the CLI adapter builds a selection config whose sessions carry the id grammar, and an embedding with the embedder's dimension.
- [x] Run `swift build --build-tests && swift test`. Expected result: all tests pass.

## Workflow
- Use `/tdd`. Write failing tests first, then do the implementation that makes them pass.

## Review Findings (2026-09-26 15:15)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 28 file(s) reviewed, 2 not reviewed.

- [x] `Tests/FoundationModelsMultitoolTests/SurfaceRefresherTests.swift:205` `completeness/public-output-contract` — The method signature of `Registry.makeSessionToolsAndStaging` changed to accept three parameters (`selection:`, `embedder:`, `sampleSession:`), but the call at line 205 provides only one argument (`selection: nil`). The other parameters are not supplied in the marked line. Verify whether `embedder:` and `sampleSession:` have default values in the new signature. If they are required, supply all three arguments: `.makeSessionToolsAndStaging(selection: nil, embedder: <value>, sampleSession: <value>)` or `.makeSessionToolsAndStaging(selection: nil, embedder: nil, sampleSession: <factory>)`.