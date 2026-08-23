---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0nbag9g1tg6kawzrfpqt0q5
  text: |
    ### research — done

    Facts found before the first edit:

    - `MultiTool.Builder` (Sources/FoundationModelsMultitool/Surface/MultiToolBuilder.swift) keeps a private `PendingTool` enum with `.standalone(any Tool)` and `.grouped(group:tool:)`. `addTools(_:)` and `addGroup(named:_:)` both call the private `enqueue(_:as:)` helper. `buildRegistry()` does all validation: legal TypeScript identifier for a group name, unique name inside one group, unique standalone name, and no standalone name equal to a group name.
    - The `.grouped` arm already gives the exact behaviour the card needs for a noun: it renders `tools.<noun>.<Tool.name>`, it throws `MultiToolBuilderError(kind: .illegalGroupName)` for an illegal noun, and it throws `MultiToolBuilderError(kind: .duplicateName)` for a repeated verb inside one noun. So the change is additive: `register(noun:tool:)` records one `.grouped` item, `withCapability(_:)` loops over `capability.tools`, and `addGroup(named:_:)` moves onto `register(noun:tool:)`.
    - `any Tool` is `Sendable` — `MultiTool.Registry` is `public struct Registry: Sendable` and stores `[String: any Tool]`. So `protocol Capability: Sendable` with `var tools: [any Tool] { get }` compiles.
    - No `Capability`, `withCapability`, or `register(noun:` symbol is in the tree today. Only eventplan.md names them.
    - Test fixtures in this target live in `Tests/FoundationModelsMultitoolTests/Fixtures/*.swift`, one file for each suite (for example `BuilderSurfaceFixtures.swift`). `StringArgument` and `PlainTextOutput` are shared fixture types in `ToolAPIRendererFixtures.swift`.
    - No `ARCHITECTURE.md` is in the repository, so there is no architecture document to obey or to update.

    Rules read before editing (`dump validators` over a `.swift` path): code-hygiene, code-security, completeness, duplication, reuse, swift, test-integrity — 55 rules. The ones that touch this change: missing-docs-swift (a doc comment on each `public` declaration), duplication and reuse (`addGroup` must call the new primitive, not copy it), test-partitioning (the new tests are unit tests in the root package), and the Swift naming and access-control rules.
  timestamp: 2026-08-22T18:21:56.912915+00:00
- actor: claude-code
  id: 01m0nbpevzhnqv56p1dq4tdvjq
  text: |
    ### implementation — landed

    TDD order, as the card asks:

    1. RED. Wrote `Tests/FoundationModelsMultitoolTests/CapabilityRegistrationTests.swift` and `Tests/FoundationModelsMultitoolTests/Fixtures/CapabilityRegistrationFixtures.swift` first. `swift build --build-tests` failed with `cannot find type 'Capability' in scope` at the conformance line. The failure was the missing type, and not a typing error.
    2. GREEN. Added `Sources/FoundationModelsMultitool/Surface/Capability.swift` and the two builder methods. `swift test --filter CapabilityRegistrationTests` reports 4 tests, 4 passed.
    3. Full suite. `swift test` reports 373 tests in 33 suites, all passed, no new warning. The only `warning:` line in the whole log is the vendored mlx-swift-lm `missing creator for mutated node` build-graph note, which was there before this change.

    What the code does now:

    - `register(noun:tool:)` records one `.grouped(group: noun, tool: tool)` item. It is the primitive, and `addGroup(named:_:)` and `withCapability(_:)` both come through it.
    - The private `enqueue(_:as:)` helper became `enqueue(_:by:)`, and its closure changed from `(any Tool) -> PendingTool` to `(any Tool) -> Void`. Reason: `addGroup` and `withCapability` would otherwise hold two copies of the same three-line loop, which the duplication rule forbids. With the new shape one loop serves three callers, and each caller passes its own public primitive — `addTool(_:)` for a flat entry, `register(noun:tool:)` for a two-segment entry. The helper is private and has no caller outside this file.
    - `buildRegistry()` is unchanged. The `.grouped` arm already gives the noun the legal-identifier check and the unique-verb-inside-one-noun check.

    Reading of Acceptance Criterion 4, so the review can check it and not guess. The criterion says "Two capabilities that declare the same noun fail at `buildRegistry()`". The `## What` section says "`buildRegistry()` keeps the validation that exists", and the `## Tests` section pins the failure case as two capabilities with the same noun **and the same verb**. So the code rejects a duplicate PATH (`tools.demo.first` given two meanings), and two capabilities that give the same noun with different verbs merge into that one namespace — exactly as two `addGroup(named:_:)` calls with the same group have always merged. The error the test asserts names the verb (`first`), not the noun, which agrees with this reading. A noun-level rejection would break `addGroup`'s documented merge, and Acceptance Criterion 5 says `addGroup` keeps its behavior.

    Doc comments that named the old set of methods were corrected, because they are public and were made wrong by this change: `MultiToolBuilderError` ("never raised by ..."), `Kind.illegalGroupName` (a noun is the same segment as a group name), the `Builder` example and its `final class` note, and the `PendingTool` note about add order.

    Files: `Sources/FoundationModelsMultitool/Surface/Capability.swift` (new), `Sources/FoundationModelsMultitool/Surface/MultiToolBuilder.swift` (edited), `Tests/FoundationModelsMultitoolTests/CapabilityRegistrationTests.swift` (new), `Tests/FoundationModelsMultitoolTests/Fixtures/CapabilityRegistrationFixtures.swift` (new). No test that exists was changed; `git status` shows one modified source file only.
  timestamp: 2026-08-22T18:28:28.671998+00:00
- actor: claude-code
  id: 01m0nbqadcwdpsctrgy5y50btc
  text: |
    ### implement — changed
    - evidence: 4 files — Sources/FoundationModelsMultitool/Surface/Capability.swift (new), Sources/FoundationModelsMultitool/Surface/MultiToolBuilder.swift, Tests/FoundationModelsMultitoolTests/CapabilityRegistrationTests.swift (new), Tests/FoundationModelsMultitoolTests/Fixtures/CapabilityRegistrationFixtures.swift (new). `swift test --filter CapabilityRegistrationTests`: 4 tests, 4 passed. `swift test`: 373 tests in 33 suites, all passed, 0 new warnings.
    - next: /review. The card stays in `doing`, and it is not committed.
  timestamp: 2026-08-22T18:28:56.876926+00:00
- actor: claude-code
  id: 01m0nctvhw4wgdyahk35r5t8v1
  text: |-
    ### review — stuck
    - evidence: `review sha HEAD~1..HEAD` (dee43b2), 4 files, 0 findings, 0 confirmed, 0 refuted. The engine found no defect in the diff.
    - blocker: acceptance criterion 4 and eventplan.md § "Registration of capabilities: noun/verb" do not agree with the code. eventplan.md says "Registration rejects a duplicate noun", and its example is an MCP server named `files` against the files capability — a collision of the noun only, with different verbs. `buildRegistry()` merges that case; it does not reject it. The implementer changed the criterion to "the same noun with the same verb". Only a person changes a rule.
    - next: a person selects option 1 (add ownership of the noun in phase 2, put the task back in `doing`) or option 2 (correct criterion 4, and make a new task for the ownership of the noun). See "## Review Blocker" in the description. The task stays in `review`.
  timestamp: 2026-08-22T18:48:21.308959+00:00
- actor: claude-code
  id: 01m0ncw7r8pasf9yn15spgy5qv
  text: |
    ### finish iteration 1 — stuck
    - implement: changed — 4 files (Capability.swift, MultiToolBuilder.swift, CapabilityRegistrationTests.swift, Fixtures/CapabilityRegistrationFixtures.swift)
    - test: green — `swift test`, 373 tests in 33 suites passed, 0 failures, 0 skipped
    - commit: dee43b2 — feat(surface): add Capability protocol and Builder.withCapability
    - review: stuck — 0 findings from `review sha HEAD~1..HEAD`; blocked on a rule conflict, not on a defect
    - blocker: eventplan.md § "Registration of capabilities: noun/verb" says "Nouns are unique. Registration rejects a duplicate noun", and it gives an MCP server named `files` against the files capability as the example. The code merges two capabilities that give the same noun with different verbs, so that example does not fail loudly today. A rejection at the level of the noun would stop the merge that `addGroup(named:_:)` documents.
    - next: a person decides. Option A — add ownership of the noun in this task: `withCapability(_:)` claims a noun, a second capability that claims a claimed noun fails, and `addGroup` keeps its merge because a group claims nothing. Option B — correct acceptance criterion 4 to "the same noun and the same verb", and make a new task for the ownership of the noun. Option B with no new task removes a guarantee that eventplan.md makes.
  timestamp: 2026-08-22T18:49:06.568776+00:00
- actor: claude-code
  id: 01m0r7d3kwr7pn0d316xv8gwmr
  text: |
    ### rule conflict — resolved by a person

    The person selected option 2 of the review blocker of 2026-08-22.

    - Acceptance criterion 4 is corrected to "the same noun **and the same verb**".
      That is what `buildRegistry()` does and what the `## Tests` section pins.
    - Ownership of the noun — the guarantee that eventplan.md § "Registration of
      capabilities: noun/verb" makes — moves to new task `^pjtbs15` (Make
      withCapability(_:) claim ownership of its noun). The guarantee is not lost.
    - The `#stuck` tag is removed, and the `## Review Blocker` section is replaced
      by a `## Rule Conflict — resolved` section.

    No code changes with this decision. The task returns to the review gate, to be
    reviewed against the corrected criterion.
  timestamp: 2026-08-23T21:11:11.228771+00:00
- actor: claude-code
  id: 01m0r7r1srff0zz9rg6wbqzbsd
  text: |
    ### review — clean

    - evidence: `review sha dee43b2~1..dee43b2`, 4 files, 0 findings, 0 confirmed, 0 refuted, 7 rules attempted. All 5 acceptance criteria and all 5 test items in the description are marked `- [x]`. No `## Review Findings` section is open.
    - criterion 4: reviewed against the corrected text ("the same noun **and** the same verb"). The test `duplicateNounAndVerbThrows` in `Tests/FoundationModelsMultitoolTests/CapabilityRegistrationTests.swift` asserts `MultiToolBuilderError(kind: .duplicateName, name: "first")`. The code agrees with the corrected criterion.
    - ownership of the noun: not raised. A person moved it to task `^pjtbs15`. It is not a defect of this task.
    - one rule did not judge: the tool rule `code-hygiene/dead-code-swift` failed, because `swift build --build-tests` fails in this working tree. The cause is the untracked file `Tests/FoundationModelsMultitoolTests/ShellRunnerTests.swift` ("cannot find 'ShellRunner' in scope"), which is in-flight work of a different task. No file of this diff is a cause of the build failure.
    - the gap was closed by hand, and not by a guess: each symbol that the diff adds has a live reference. `Capability` and `withCapability(_:)` are public API and the new tests use them; `register(noun:tool:)` has two callers (`withCapability(_:)` and `addGroup(named:_:)`) and a test; the private `enqueue(_:by:)` has three callers in its own file. There is no dead code in the diff.
    - next: none. The task is in `done`.
  timestamp: 2026-08-23T21:17:09.816727+00:00
- actor: claude-code
  id: 01m0r7s2rt6gstbtyx9pkswn7s
  text: |
    ### finish iteration 2 — clean
    - decision: a person selected option 2 of the review blocker. Acceptance criterion 4 is corrected to "the same noun and the same verb". Ownership of the noun moved to new task `^pjtbs15`.
    - implement: no-change — the decision changes a rule, not the code. `dee43b2` stands as written.
    - test: not run this iteration — no code changed since the green run of iteration 1 (`swift test`, 373 tests in 33 suites, 0 failures).
    - commit: none — no code changed. `dee43b2` is the checkpoint.
    - review: clean — `review sha dee43b2~1..dee43b2`, 4 files, 0 findings, 0 confirmed, 0 refuted, 7 rules attempted. The review moved the task to `done`.
    - note: the rule `code-hygiene/dead-code-swift` could not judge, because `swift build --build-tests` fails in this working tree at the untracked file `Tests/FoundationModelsMultitoolTests/ShellRunnerTests.swift` (`cannot find 'ShellRunner' in scope`). That file belongs to another task and is not part of this diff. The reviewer closed the gap by a reference check of each symbol the diff adds. No dead code.
    - next: none. The task is done.
  timestamp: 2026-08-23T21:17:43.578760+00:00
position_column: done
position_ordinal: e480
title: Add the Capability protocol and Builder.withCapability(_:)
---
## What

eventplan.md § "Registration of capabilities: noun/verb" gives the registration
shape that phase 2 needs. Today `MultiTool.Builder` has only `addTool` (a flat
`tools.<name>` entry) and `addGroup(named:_:)` (a `tools.<noun>.<verb>` entry).
There is no `Capability` type.

Add the capability shape on top of the `addGroup` machinery that exists. Flat
entries stay legal in this phase. Do not remove `addTool`.

- New file `Sources/FoundationModelsMultitool/Surface/Capability.swift`:
  - `public protocol Capability: Sendable` with `var noun: String { get }` and
    `var tools: [any Tool] { get }`.
  - `Tool.name` supplies the verb. The capability supplies only the noun.
- Edit `Sources/FoundationModelsMultitool/Surface/MultiToolBuilder.swift`:
  - `public func register(noun: String, tool: any Tool) -> Self` — the
    registration primitive. It records one `.grouped(group: noun, tool: tool)`
    pending item.
  - `public func withCapability(_ capability: any Capability) -> Self` — it
    calls `register(noun:tool:)` one time for each element of
    `capability.tools`.
  - `addGroup(named:_:)` stays and now calls `register(noun:tool:)`.
- `buildRegistry()` keeps the validation that exists. A duplicate
  `<noun>.<verb>` path must fail at `buildRegistry()`, not at dispatch.

## Acceptance Criteria

- [x] `Capability` is public, and it declares `noun` and `tools`.
- [x] `Builder.register(noun:tool:)` renders the tool at
      `tools.<noun>.<Tool.name>`.
- [x] `Builder.withCapability(_:)` registers each tool of the capability under
      the one noun.
- [x] Two capabilities that declare the same noun **and the same verb** fail at
      `buildRegistry()` with `MultiToolBuilderError`. Ownership of the noun —
      two capabilities that share a noun but declare different verbs — is not
      in the scope of this task. It is a separate task.
- [x] `addTool` and `addGroup(named:_:)` keep their behavior. No test that
      exists changes.

## Tests

- [x] New `Tests/FoundationModelsMultitoolTests/CapabilityRegistrationTests.swift`:
      a fixture capability with noun `"demo"` and two tools renders exactly
      `demo.first` and `demo.second` in `APISurface.entries`.
- [x] Same file: a capability whose noun is not a legal TypeScript identifier
      throws `MultiToolBuilderError(kind: .illegalGroupName)`.
- [x] Same file: two capabilities with the same noun and the same verb throw
      `MultiToolBuilderError(kind: .duplicateName)`.
- [x] `swift test --filter CapabilityRegistrationTests` passes.
- [x] `swift test` passes with no new failure and no new warning.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Rule Conflict — resolved 2026-08-23

The review of 2026-08-22 stopped this task, because acceptance criterion 4 and
eventplan.md did not agree. A person has made the decision.

**Decision: the criterion was too strong for phase 2.** Criterion 4 now reads
"the same noun and the same verb", which is what the code does and what the
`## Tests` section pins.

The guarantee that eventplan.md § "Registration of capabilities: noun/verb"
makes — "Nouns are unique. Registration rejects a duplicate noun" — is not
lost. It moves to a new task for ownership of the noun.

This task is no longer stuck. Review it against the corrected criterion 4. #eventplan #phase-2