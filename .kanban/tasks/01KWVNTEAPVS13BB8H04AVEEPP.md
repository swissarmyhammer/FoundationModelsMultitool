---
comments:
- actor: claude-code
  id: 01kxe3xkrenz0fw92xb55stt3b
  text: |-
    Implemented via /tdd + /implement.

    What changed:
    - Moved Sources/FoundationModelsMultitool/Agent/FindAPITool.swift -> Sources/FoundationModelsMultitool/Discovery/FindAPIsTool.swift, replacing the old `FindAPITool` (plain struct, `dispatch(task:)`) with `public struct FindAPIsTool: Tool` — a real FoundationModels.Tool conformer (`name = "findAPIs"`, `description`, `call(arguments: FindAPIsArguments) async throws -> String`). New `public struct FindAPIsArguments` (@Generable, `task: String`) is the native Arguments type.
    - Two initializers: `init(searcher: MetadataSearcher<APISurface.Entry>, limit: Int)` (low-level, test-facing, also used by MultiToolAgent) and `init(registry: MultiTool.Registry, librarian: RoutedLLM?, limit: Int? = nil) throws` (production/standalone entry point — builds a `.auto`-mode MetadataSearcher, wiring the selection tier through `librarian`'s `RoutedLLM.makeGuidedSession` only when non-nil; `.auto` degrades to retrieval-only when `librarian` is nil).
    - Moved Sources/FoundationModelsMultitool/Agent/SelectionGrammar.swift -> Sources/FoundationModelsMultitool/Discovery/SelectionGrammar.swift verbatim, `idEnumGrammar(ids:)` unchanged.
    - MultiToolAgent.swift: renamed `findAPITool`/`FindAPITool` -> `findAPIsTool`/`FindAPIsTool` throughout (fields, both initializers, doc comments), call site changed to `findAPIsTool.call(arguments: FindAPIsArguments(task: task))`. Deliberately left `makeFindAPISearcher(registry:librarian:)` (still `.selection` mode) untouched — MultiToolAgent still wires a pre-built `.selection`-mode searcher into `FindAPIsTool.init(searcher:limit:)` rather than the new `init(registry:librarian:)` convenience initializer, to keep its existing production behavior/tests byte-identical (minimal-diff, per task's "adapt MultiToolAgent... or add an adapter" latitude).
    - Doc-comment-only fixes (old name -> new name) in APISurface.swift, APISurface+SearchableMetadata.swift, Package.swift, MultiToolAgentTests.swift.
    - Tests: deleted FindAPIToolTests.swift, added FindAPIsToolTests.swift (5 tests) — standalone splice, grouped/qualified-path splice, empty-selection message (all migrated from the old suite onto the new Tool-shaped API), plus two new tests for `.auto` mode's retrieval-only fallback (no selection tier configured) and the production registry+librarian initializer with `librarian: nil`.

    Verification (really-done, all fresh-run):
    - `swift build` clean.
    - `swift build --build-tests` clean (unit + gated integration targets both compile).
    - `swift test --skip FoundationModelsMultitoolIntegrationTests`: 239/239 passed, 21 suites, zero failures/warnings.
    - `swift test --filter FindAPIsTool`: 5/5 passed.
    - `swift test --filter MultiToolAgentTests`: 11/11 passed (existing coverage untouched).
    - `swift test --filter SelectionGrammarTests`: 4/4 passed.
    - Adversarial double-check agent: PASS, no findings (independently re-ran all verification commands, confirmed no dependency on MultiToolAgent/TurnFormat/AgentStep, confirmed byte-identical format() behavior, confirmed no stray old-name references, confirmed all-caps API acronym naming convention followed consistently).

    No blockers. Task left in `doing` per /implement contract — ready for /review.
  timestamp: 2026-07-13T16:10:47.950846+00:00
- actor: claude-code
  id: 01kxe4044pv09m8q3ndt572z4d
  text: '/test verification (independent subagent): swift build/build-tests/test all green. 239 tests passed in main suite, 11 gated integration tests skipped as expected (no live model), 0 failures. Confirms the implementer''s report. Proceeding to /commit checkpoint.'
  timestamp: 2026-07-13T16:12:10.262471+00:00
depends_on:
- 01KWVJG70NFB1AYW3P812RTN85
position_column: doing
position_ordinal: '80'
title: Extract findAPIs into a standalone FoundationModels.Tool, decoupled from MultiToolAgent
---
## What
Part of the MultiToolAgent removal pivot (see board). Today, `findAPIs` discovery only exists as an internal step in `MultiToolAgent`'s hand-rolled ReAct loop: `Sources/FoundationModelsMultitool/Agent/FindAPITool.swift`'s `FindAPITool` struct has a bespoke `dispatch(task:) async throws -> String` method, called only from `MultiToolAgent`'s turn dispatch, and `Sources/FoundationModelsMultitool/Agent/SelectionGrammar.swift`'s `idEnumGrammar(ids:)` builds the grammar its selection tier needs.

**These two files' core logic must survive this pivot** — do NOT delete them as part of the later `MultiToolAgent` removal task; this task extracts and repackages them first.

Rebuild `findAPIs` as a real `FoundationModels.Tool` conformer (own `name`, `description`, `Arguments`/`Output` types, `call(arguments:) async throws -> Output`) so it can be registered directly alongside `MultiTool` with a real `LanguageModelSession(tools: [multiTool, findAPIsTool])` — per the user's decision, discovery must be "automatic": cheap retrieval (BM25/signals+RRF) first, then LLM-driven selection over the narrowed candidates when a selection tier is configured — i.e. reuse `MetadataSearcher<APISurface.Entry>`'s existing `.auto` mode (`SearchMode.swift` in `FoundationModelsMetadataRegistry`: "Selection when a selection tier is configured, retrieval otherwise"), not `.selection` mode unconditionally — this is what makes the retrieval-vs-selection split automatic based on catalog size/configuration rather than always paying for an extra LLM call.

The selection tier's own LLM backing (when configured) should keep using Router's own `RoutedSession`/`fork()` (per-call cached-prefix reuse) — NOT `LanguageModelSession`, since `FoundationModelsRouter`'s own plan.md notes the FoundationModels interop path "does not expose our cache-level fork()." This is a deliberate two-model split: the *main* loop drives on `LanguageModelSession` (real native tool-calling), while `findAPIsTool`'s own internal selection call drives on a Router-resolved `RoutedSession` — mirroring the old "librarian on the flash slot" split, just decoupled from the main loop's turn machinery.

Move/rename the extracted logic out of `Agent/` (that whole directory is being retired) — e.g. `Sources/FoundationModelsMultitool/Discovery/FindAPIsTool.swift` and `Sources/FoundationModelsMultitool/Discovery/SelectionGrammar.swift` (exact naming/location at implementer's discretion, but out of `Agent/`).

**IMPORTANT — `MultiToolAgent.swift` is NOT deleted until a later task (`7840f24`), and this task is NOT gated behind that deletion.** `MultiToolAgent` holds `private let findAPITool: FindAPITool?`, constructs it via `FindAPITool(searcher:limit:)`, and calls `.dispatch(task:)` in its turn loop. Rebuilding `FindAPITool` into a `FoundationModels.Tool` conformer with a `call(arguments:)` shape (and moving it out of `Agent/`) WILL break `MultiToolAgent.swift`'s compile unless you also update its call site here: either adapt `MultiToolAgent` to call the new `FindAPIsTool` API directly (constructing `Arguments`/decoding `Output` inline), or add a small private adapter inside `MultiToolAgent.swift` itself that bridges old-shape calls to the new type, so `MultiToolAgent.swift` keeps compiling and its existing tests keep passing until it's fully deleted in `7840f24`. Don't leave this as a compile break for a later task to discover.

## Acceptance Criteria
- [ ] A `FindAPIsTool: FoundationModels.Tool` conformer exists, independently constructible from a `MultiTool.Registry` (or equivalent) plus a selection-tier backing (a Router-resolved model/session), with no dependency on `MultiToolAgent`, `TurnFormat`, or `AgentStep`.
- [ ] Its `call(arguments:)` runs `MetadataSearcher<APISurface.Entry>` in `.auto` mode: retrieval-only when no selection tier is configured, retrieval-then-selection when one is.
- [ ] `SelectionGrammar.swift`'s `idEnumGrammar(ids:)` is preserved and reused for the selection tier's grammar, unchanged in behavior.
- [ ] The tool's rendered output (splicing matched entries' `block`s + examples) matches today's `FindAPITool.format`'s behavior, including whatever qualified-path fix landed from task `12rtn85`.
- [ ] `MultiToolAgent.swift` is updated (not left broken) to compile and pass its existing tests against the new `FindAPIsTool` shape.
- [ ] `swift build` and full `swift test` remain green.

## Tests
- [ ] New unit tests for the extracted `FindAPIsTool`, offline/no-live-model — reuse or adapt the existing scripted-selection-tier test double pattern (`RootSessionRespondCalledDirectlySession`/`makeScriptedSelectionSearcher` in `Fixtures/MultiToolAgentFixtures.swift`, or new fixtures under a `Discovery`-scoped fixtures file) covering: a standalone tool's match splices correctly, a grouped tool's match splices with a qualified example, an empty selection formats as "no matching functions", and `.auto` mode without a configured selection tier still returns retrieval-only results.
- [ ] `swift test --filter FindAPIsTool` (or whatever the new suite is named) passes.
- [ ] `MultiToolAgentTests.swift`'s existing coverage still passes against the updated call site.
- [ ] Full `swift test` passes with no regressions.

## Workflow
- Use `/tdd` — write the new standalone-Tool tests first against the not-yet-extracted logic (watch them fail to compile/fail), then move+adapt `FindAPITool`/`SelectionGrammar`'s logic to make them pass, then fix `MultiToolAgent`'s call site to keep it green.
