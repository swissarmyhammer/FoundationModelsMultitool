---
comments:
- actor: wballard
  id: 01kwgj36rqyhaczjdrmjqkqh31
  text: |-
    Implemented via TDD:
    - Tests/FoundationModelsMultitoolTests/BuilderSurfaceTests.swift (8 tests, written first, watched RED against missing types)
    - Tests/FoundationModelsMultitoolTests/Fixtures/BuilderSurfaceFixtures.swift
    - Tests/FoundationModelsMultitoolTests/Goldens/BuilderSurface.ts.txt (hand-derived from ToolAPIRenderer's known output before implementing, then matched on first GREEN run)
    - Sources/FoundationModelsMultitool/Surface/MultiToolBuilder.swift: `public enum MultiTool {}` namespace (Tool conformance deferred to M4a), `MultiToolBuilderError`, `MultiTool.Builder` (final class; addTool/addTools/addGroup never throw, only build() throws)
    - Sources/FoundationModelsMultitool/Surface/APISurface.swift: `APISurface` + `APISurface.Entry` (path/group/descriptor/block), `source`/`standaloneEntries`/`groupedEntries`
    - Sources/FoundationModelsMultitool/Surface/ToolAPIRenderer.swift: widened `isLegalTSIdentifier` from `private` to internal so Builder can reuse it to validate group names (documented why)

    Design decisions beyond the literal acceptance criteria (namespacing per Resolved #5): grouped declarations stay unqualified (dotted `declare function` isn't valid TS), so the namespace is surfaced via a `// tools.<path>` banner line prepended to each entry's block. Also added guards for duplicate names *within* the same group, and a flat-name-vs-group-name collision — natural extensions of "duplicate flat names throw" not explicitly required but consistent with the namespacing contract.

    Verification: `swift build` clean (no new warnings beyond a pre-existing unrelated MLX bundle warning); `swift test` 84/84 passing (was 76/76 before this task; +8 new BuilderSurfaceTests). Adversarial double-check dispatched before handoff.
  timestamp: 2026-07-02T04:41:18.359244+00:00
- actor: wballard
  id: 01kwgj9ctqdercwm8tqk0gd32j
  text: |-
    Adversarial double-check (via really-done) returned REVISE: one gap found — the flat-name-vs-group-name collision path (`standaloneNames.intersection(groupNames)` in `Builder.build()`) had zero test coverage, even though it's real, non-obvious logic. Everything else (golden-file non-tautology, injection safety of the `// tools.<path>` banner, the `isLegalTSIdentifier` access-level widening, API design) passed review clean.

    Fixed: added `standaloneNameCollidingWithGroupNameThrows` to BuilderSurfaceTests.swift, covering both add orders (standalone-then-group and group-then-standalone) to confirm the post-loop check is order-independent.

    Final verification (fresh run): `swift test` → 85/85 passing, 0 failures, 0 warnings from our code (only a pre-existing unrelated MLX bundle build warning). `swift build` clean.

    All acceptance criteria met:
    - Golden surface test for a fixture set (WeatherTool, PlainTextTool, github group) — byte-identical match
    - Duplicate flat name → build() throws, naming the collision
    - addGroup(named: "github", …) → tools.github.<name> entries (surfaced via a `// tools.<path>` banner since dotted `declare function` isn't valid TS)
    - Unrenderable tool → build() throws (propagated ToolAPIRendererError, no lossy stub)

    Leaving task in `doing` for /review per the implement skill's process.
  timestamp: 2026-07-02T04:44:41.175819+00:00
- actor: wballard
  id: 01kwgk0s189m70p69gqc3t4frk
  text: |-
    Worked the three "Review Findings" checklist items (pulled back from review into doing per /implement).

    All three flagged initializers turned out to be the same false-premise pattern flagged in M1 (task v1px1xj): each type (`APISurface.Entry`, `APISurface`, `MultiToolBuilderError`) is `public`, and Swift only synthesizes memberwise inits for `public` structs at `internal` access. Deleting the explicit inits would have made all three unconstructable from outside the module, breaking the `.library` product's public API.

    Verified empirically rather than assuming: temporarily commented out all three explicit inits, added a scratch test file (`TempAccessCheckTests.swift`) using a plain `import FoundationModelsMultitool` (not `@testable`) that constructs each type directly, and ran `swift build --build-tests`. Got exactly the expected failures:
    - `'APISurface' initializer is inaccessible due to 'internal' protection level` (for both `Entry.init` and `APISurface.init`)
    - `'MultiToolBuilderError' initializer is inaccessible due to 'internal' protection level`

    Restored all three inits, added doc comments explaining why each is necessary (matching the wording already established for `ToolDescriptor.init` in ToolDescriptor.swift and `HostFunction.init`/`InterpreterResult.init` in Interpreter.swift from the M1 correction), and deleted the scratch verification file.

    No behavior changes — doc-comment-only diff on APISurface.swift and MultiToolBuilder.swift.

    Final verification: `swift build` clean (no new warnings), `swift test` → 85/85 passing, 0 failures. `git status --short` confirms only the two source files changed plus kanban task metadata — no stray scratch files left behind.

    Leaving task in `doing` per /implement process (does not move to review itself).
  timestamp: 2026-07-02T04:57:27.336526+00:00
- actor: wballard
  id: 01kwgkyfss3c2whqn375cpgwzx
  text: |-
    Worked the second "Review Findings" checklist (2026-07-02 00:04, 3 items), pulled back from review into doing.

    1/2. Consolidated the duplicated "public struct's synthesized initializer is only internal-accessible" doc-comment prose across Entry.init and APISurface.init (APISurface.swift) and MultiToolBuilderError.init (MultiToolBuilder.swift). Applied the established codebase precedent from Interpreter.swift (HostFunction.init = full explanation; InterpreterResult.init = short one-paragraph reference) — same style ToolDescriptor.init already uses. Each of the three inits now has a short paragraph referencing another init (ToolDescriptor.init or Entry.init) rather than restating the full "without this, no module outside FoundationModelsMultitool could construct X, even though..." explanation at length. No behavior changes.

    3. Extracted a private `enqueue(_ tools: [any Tool], as makePending: (any Tool) -> PendingTool) -> Self` helper in MultiTool.Builder (MultiToolBuilder.swift), shared by `addTools` (passes `PendingTool.standalone` as the case-constructor) and `addGroup` (passes a closure building `.grouped(group:tool:)`), eliminating the near-identical iterate/append/return loop bodies.

    Verification: `swift build` clean (only the pre-existing unrelated MLX bundle warning), `swift test` → 85/85 passing, 0 failures. Adversarial double-check dispatched before handoff.
  timestamp: 2026-07-02T05:13:40.921400+00:00
depends_on:
- 01KWFNSGV7FZFCC1HQ5V2CCAQX
position_column: doing
position_ordinal: '80'
title: 'M2.5: Builder + APISurface — model-agnostic tool catalog'
---
## What\n- `Sources/FoundationModelsMultitool/Surface/MultiToolBuilder.swift` — `MultiTool.Builder` with `addTool(_:)` (generic over `T: Tool`, capturing the concrete type for later existential opening), `addTools(_:)`, `addGroup(named:_:)`, `build()`. Pure catalog — NO model wiring.\n- `Sources/FoundationModelsMultitool/Surface/APISurface.swift` — the rendered catalog (list of `ToolDescriptor` + group structure): backs the librarian prefix, `help()`/`docs()`, and a host-listable data view.\n- Namespacing per plan Resolved #5: standalone tools flat at `tools.<name>`; grouped under `tools.<group>.<name>`; duplicate flat names → `build()` throws (fail loud), duplicates across groups are fine.\n- Completeness contract: `build()` throws if any tool fails ToolAPIRenderer's full rendering.\n\n## Acceptance Criteria\n- [ ] Builder with fixture tools produces an `APISurface` whose concatenated declaration blocks match a golden file\n- [ ] Two flat tools with the same `name` → `build()` throws naming the collision\n- [ ] `addGroup(named: \"github\", …)` renders `tools.github.<name>` declarations\n- [ ] A tool that can't be fully rendered → `build()` throws (no lossy stub)\n\n## Tests\n- [ ] `Tests/FoundationModelsMultitoolTests/BuilderSurfaceTests.swift` — golden surface for a fixture set, collision error, group namespacing, completeness failure\n- [ ] `swift test --filter BuilderSurfaceTests` → passes\n\n## Workflow\n- Use `/tdd` — write failing tests first, then implement to make them pass.\n\n## Review Findings (2026-07-01 23:48)\n\n- [x] `Sources/FoundationModelsMultitool/Surface/APISurface.swift:38` — `Entry.init(path:group:descriptor:)`: **KEPT, not deleted.** `Entry` is a `public` nested struct of the `FoundationModelsMultitool` library product. Empirically verified.\n- [x] `Sources/FoundationModelsMultitool/Surface/APISurface.swift:56` — `APISurface.init(entries:)`: **KEPT, not deleted.**\n- [x] `Sources/FoundationModelsMultitool/Surface/MultiToolBuilder.swift:35` — `MultiToolBuilderError.init(kind:name:message:)`: **KEPT, not deleted.**\n\nAll three findings were based on the same false premise the task warned about. No behavior changes — doc comments only. `swift build` clean, `swift test` 85/85 passing.\n\n## Review Findings (2026-07-02 00:04)\n\n- [x] `Sources/FoundationModelsMultitool/Surface/APISurface.swift` — `APISurface.init(entries:)` doc comment duplicated `Entry.init`'s explanation. Consolidated: shortened both `Entry.init` and `APISurface.init` doc comments to the concise one-paragraph reference style already established by `HostFunction.init`/`InterpreterResult.init` (Interpreter.swift) and `ToolDescriptor.init` (ToolDescriptor.swift) — each keeps a short type-specific reason and points to another init rather than restating the full \"without this, no module outside FoundationModelsMultitool could construct X, even though...\" explanation at length.\n- [x] `Sources/FoundationModelsMultitool/Surface/MultiToolBuilder.swift` — `MultiToolBuilderError.init` doc comment duplicated the same explanation. Consolidated to the same concise reference style, pointing to `ToolDescriptor.init`.\n- [x] `Sources/FoundationModelsMultitool/Surface/MultiToolBuilder.swift` — `addTools` and `addGroup` had near-identical loop bodies. Extracted a private `enqueue(_ tools: [any Tool], as makePending: (any Tool) -> PendingTool) -> Self` helper; `addTools` passes `PendingTool.standalone` (enum case used as a function reference), `addGroup` passes a closure building `.grouped(group:tool:)`. Eliminates the duplicated iterate/append/return loop.\n\nVerification: `swift build` clean, `swift test` 85/85 passing. Adversarial double-check (via really-done) returned PASS: confirmed doc comments are non-duplicative and self-sufficient, `enqueue` helper is correct Swift (bare enum-case-as-function-reference and closure capture both valid), diff scoped to only APISurface.swift and MultiToolBuilder.swift, no scope creep.\n