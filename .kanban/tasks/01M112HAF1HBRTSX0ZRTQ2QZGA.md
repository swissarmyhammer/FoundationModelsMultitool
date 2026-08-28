---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m14k8wmtdwzb8bgad7kxrecx
  text: |-
    ### Org import check — clean

    Method (three passes):

    1. **Working copies.** A grep of each checkout under `/Users/wballard/github/swissarmyhammer/` for `import FoundationModelsMCP` in `*.swift`, for `FoundationModelsMCP` in each `Package.swift`, and for `FoundationModelsMCP` in each `Package.resolved`.
    2. **Remote branches.** `git fetch origin` in each of the 21 checkouts of the non-archived org repositories, then a grep of `origin/main` for `import FoundationModelsMCP` and for `.package(...FoundationModelsMCP...)`. This reads what is on the remote, not what is on disk. Control run: the same grep for `import FoundationModelsRouter` on `FoundationModelsMultitool/origin/main` gives 56 files, thus the method finds a hit when a hit is there.
    3. **Organization repository list.** `gh repo list swissarmyhammer` gives 30 repositories. Each non-archived repository has a checkout in the folder. The repositories with no checkout are archived (`apithing`, `claude-agent`, `hence`, `llama-agent`, `markdowndown`, `shardex`, `FoundationModelsFileTool`, `FoundationModelsShelltool`); an archived repository is read-only and no change can break it.

    Result: **no repository of the organization imports or depends on `FoundationModelsMCP`.** Each `import FoundationModelsMCP` in the folder stands inside the `FoundationModelsMCP` repository itself — its own tests and its own `Examples/`. No `Package.swift` outside that repository declares it as a dependency. No `Package.resolved` in the organization names it.

    The sightings outside the MCP repository are all prose or a ban list:

    - `FoundationModelsACPAgent/Package.swift:26` — a comment that names the package in a roster of planned dependencies. Not a dependency declaration. This task edits it.
    - `FoundationModelsACPClient/Tests/FoundationModelsACPClientTests/ForbiddenImportTests.swift:12` — the name in a list of **forbidden** imports. A guard that bans the import; not a consumer.
    - `FoundationModelsOperationTool/Package.swift:13` — a comment that cites the sibling manifest for its tools-version.
    - `FoundationModelsMultitool/Package.swift` (4 places) — doc comments that record where the ported files come from.
    - `FoundationModelsRouter/Tests/.../TurnCancellationTests.swift`, `FoundationModelsSkills/Tests/.../HotReloadLiveTests.swift`, and kanban task files in several repositories — prose that names the package in a comment.

    The archive gate is therefore open.
  timestamp: 2026-08-28T16:29:29.114387+00:00
- actor: claude-code
  id: 01m14ktzyd2pgqzycjjjx646rx
  text: |-
    ### What the phase-4 note check found

    The four decisions of the note of 2026-08-27 are each correct against the code:

    1. **A plain synchronous `Tool`.** `Capabilities/MCP/MCPTool.swift` states it: "`MCPTool` does not conform to `BackgroundTool`." No `RunKind` case was added for MCP; `.process` belongs to the shell verb. `MCPServerError` conforms to `LostRunError` (`BackoffPolicy.swift`), and `MCPServer+Call.swift` throws `MCPServerError.lost` under a transport drop, so `ToolRun` settles the calling run as `.lost` — word for word what the note says.
    2. **A bare-session conformer.** `MCPServer+Elicitation.swift` names three answerers in one order, and answerer 2 is the host handler on a bare session, where the turn waits.
    3. **The turn boundary.** `MultiTool+TurnBoundary.swift` — `extension MultiTool: TurnBoundaryTool`, which applies the staged registry at `turnWillBegin()`.
    4. **ACPAgent.** Confirmed by the org import check above.

    **One sentence of the phase text no longer matches, and the new note corrects it.** The phase text says: "The `ElicitationCoordinator` protocol becomes the host seam of `ToolContext.elicit`, URL mode included." No protocol of that name is in the code. The sibling's `ElicitationCoordinator` and `MCPElicitationTool` are gone. The seam of a bare session is the `MCPServer.ElicitationHandler` closure, and under Router the seam is `ToolContext.elicit(_:)` with the `SessionMailbox`. URL mode did land, as a flow of three messages. The note of 2026-08-28 in `eventplan.md` records this correction, and records that the exit is complete.

    The rest of the phase text holds: `Capabilities/MCP` has the named files, each server registers as a top-level group (`MCPCapability`), and the follow-up pseudo-tools are gone (`MCPServer.swift`: "the three follow-up tools ... is gone").

    ### How the guard was driven red first

    The new suite is a guard, and a guard that cannot fail proves nothing. Each of its two assertions was made to fail before it was left green:

    - **The ban assertion.** A probe line `private let archivedSiblingProbe = "FoundationModelsMCP"` was put into `Package.swift`. The suite failed and named the line: `Package.swift:217: private let archivedSiblingProbe = "FoundationModelsMCP"`. The probe was then removed, and the suite passed. This also proves the comment rule: the manifest holds four comment lines with the same name, and none of them was reported.
    - **The presence assertion.** The needle `swift-sdk` was changed to `swift-sdk-probe`. The suite failed with `Expectation failed: !packageSightings.isEmpty`. The needle was put back, and the suite passed.

    ### Discovery: the nested IntegrationTests package cannot build

    `swift build --package-path IntegrationTests --build-tests` fails with `cannot find 'ToolMounting' in scope`. The cause is local machine state: the nested package holds `FoundationModelsRouter` in the **edited** state, through a symlink at `IntegrationTests/Packages/FoundationModelsRouter` made on 2026-08-26, so it compiles against the sibling working copy, where the type is internal. The root package resolves Router from the remote, where the type is public, and every root test passes. This card changed no manifest and no library source, thus it did not cause the failure. Recorded as task `^jmtpfwv`. The fix removes another session's edit link while that session has uncommitted work in the Router folder, so this card does not touch it.
  timestamp: 2026-08-28T16:39:22.317539+00:00
- actor: claude-code
  id: 01m14kv9k5qpvg2qvdqzcye2sr
  text: |-
    ### implement — changed
    - evidence: org import check clean across every repository of the organization (working copies, `origin/main` of the 21 non-archived checkouts, and the `gh repo list` roster), thus the archive gate opened. `gh repo archive swissarmyhammer/FoundationModelsMCP --yes` ran, and `gh repo view` answers `archived=true`. Files changed, 3: `Tests/FoundationModelsMultitoolTests/MCPConsolidationTests.swift` (new), `eventplan.md` (the note of 2026-08-28, 21 lines), and `../FoundationModelsACPAgent/Package.swift` (the manifest comment, in the sibling repository). Local annotated tag `consolidation-4-mcp` created on `be6ea1f`. `swift build --build-tests`: clean. `swift test`: 1312 tests in 101 suites, all passed.
    - next: `/review`. Two items stay open, and the card records them: the commit step must move the tag onto the commit that lands this card (`git tag -f -a consolidation-4-mcp`), and the push of that tag to `origin` is the user's step. The `IntegrationTests/` gated suite cannot run until task `^jmtpfwv` is answered. The edit of `../FoundationModelsACPAgent/Package.swift` stands uncommitted in that repository; this session commits nothing.
  timestamp: 2026-08-28T16:39:32.197501+00:00
depends_on:
- 01M112GT1BAATTYMYSX7VN4NK5
- 01M112FXM6H40D8C5YS0PVNXQQ
- 01M112G8MMPH6QN1XQJVSACZ8F
position_column: doing
position_ordinal: '80'
title: 'Phase 4 exit: org import check, archive FoundationModelsMCP, tag consolidation-4-mcp'
---
## What
eventplan.md § "Phases", phase 4: "Exit: we archive the FoundationModelsMCP repository. ACPAgent, its one org consumer, moves first." The exit criterion of each phase is a deletion.

Finding from planning (2026-08-27): `FoundationModelsACPAgent/Package.swift` does not depend on FoundationModelsMCP. Its manifest names the package in a comment only (line 26). Thus the consumer move is a check and a comment edit, not a migration.

- Check each checkout under `/Users/wballard/github/swissarmyhammer/` for `FoundationModelsMCP` in `Package.swift`, `Package.resolved`, and `import FoundationModelsMCP` in sources. Record the result as a comment on this task. A consumer that is found becomes a new task; do not migrate it here.
- Edit the comment in `FoundationModelsACPAgent/Package.swift` line 26 so it names `FoundationModelsMultitool` and not the archived packages (FileTool, Shelltool, MCP).
- Confirm the phase-4 note in `eventplan.md` (added by the first task) still matches what landed. Correct any decision that changed during the phase, in ASD-STE100.
- Archive the repository: `gh repo archive swissarmyhammer/FoundationModelsMCP --yes`. This is outward-facing; confirm with the user before you run it.
- Tag this repository `consolidation-4-mcp` at the commit that lands the last phase-4 task, and push the tag.

## Acceptance Criteria
- [x] No checkout under the org folder imports or depends on `FoundationModelsMCP`; the scan result is on this task.
- [x] The ACPAgent manifest comment names the consolidated package.
- [x] `eventplan.md`'s phase-4 note matches what landed.
- [x] `github.com/swissarmyhammer/FoundationModelsMCP` is archived.
- [ ] `git tag --list` shows `consolidation-4-mcp`, and the tag is on `origin`.

## Tests
- [x] Add `Tests/FoundationModelsMultitoolTests/MCPConsolidationTests.swift`: assert that `Package.swift` of this package has no `FoundationModelsMCP` dependency, and that the `swift-sdk` product is present (the same reflective pattern as `DependencyReachTests`).
- [x] `swift test --filter MCPConsolidationTests` passes.
- [ ] Full `swift test` passes, and the `IntegrationTests/` gated suite passes on hardware.

## Workflow
- Use `/tdd` — write the manifest test first, then do the checks and the archive.

## Open items of this card

**The tag.** `git tag --list` shows `consolidation-4-mcp`. The tag is annotated, and it stands on `be6ea1f`, which is HEAD as this card was implemented. Two steps are open:

1. The commit step must move the tag onto the commit that lands this card:
   `git tag -f -a consolidation-4-mcp` with the same message.
2. The push to `origin` is the user's step. This session does not push this repository.

**The gated suite.** Full `swift test` of the root package passes: 1312 tests in 101 suites, zero failures and zero warnings from this repository's own source. The `IntegrationTests/` suite cannot run today, because the nested package does not build. The cause is local machine state and not a file of this repository — see task `^jmtpfwv`. #eventplan #phase-4