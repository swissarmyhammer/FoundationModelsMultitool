---
assignees:
- claude-code
depends_on:
- 01M112GT1BAATTYMYSX7VN4NK5
- 01M112FXM6H40D8C5YS0PVNXQQ
- 01M112G8MMPH6QN1XQJVSACZ8F
position_column: todo
position_ordinal: '9180'
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
- [ ] No checkout under the org folder imports or depends on `FoundationModelsMCP`; the scan result is on this task.
- [ ] The ACPAgent manifest comment names the consolidated package.
- [ ] `eventplan.md`'s phase-4 note matches what landed.
- [ ] `github.com/swissarmyhammer/FoundationModelsMCP` is archived.
- [ ] `git tag --list` shows `consolidation-4-mcp`, and the tag is on `origin`.

## Tests
- [ ] Add `Tests/FoundationModelsMultitoolTests/MCPConsolidationTests.swift`: assert that `Package.swift` of this package has no `FoundationModelsMCP` dependency, and that the `swift-sdk` product is present (the same reflective pattern as `DependencyReachTests`).
- [ ] `swift test --filter MCPConsolidationTests` passes.
- [ ] Full `swift test` passes, and the `IntegrationTests/` gated suite passes on hardware.

## Workflow
- Use `/tdd` — write the manifest test first, then do the checks and the archive. #eventplan #phase-4