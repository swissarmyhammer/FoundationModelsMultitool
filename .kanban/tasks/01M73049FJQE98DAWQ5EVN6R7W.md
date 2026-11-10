---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m7372bt797atb88hhcft8r6g
  text: |-
    Research: PathContainment.swift and ShellDotfolder.swift had no Seatbelt text at HEAD 8771d2fd; earlier MT-15 cards removed it. The only tracked hits were docs/GUIDE.md (two lines) and the Execute.swift `workingDirectory` comment ("a sandbox rooted at the session"). The UPSTREAM_ASKS.md Ask 4 and Ask 6 references are not the Seatbelt item, so they stay (Execute.swift keeps "Ask 6", which is the working-directory ask).

    Facts checked in code: MultiTool.Builder.init(mode:sandboxProbe:) (MultiToolBuilder.swift); validateToolMode() calls mode.validate(probe:) first, then refuses ShellCapability and MCPCapability over StdioServerProcess with MultiToolBuilderError kind .notAvailable(mode:) and a hint per capability (RegistrySource.swift); build() calls buildRegistry(); StdioServerProcess.respawn() throws notAvailable(mode:) in sandboxed mode; ShellRunner runs /bin/sh -c.

    Correction: the git capability of this package is read-only and has no push verb. The docs therefore say "a host that pushes a repository cannot push over SSH; HTTPS with a token works (D101)".

    Acceptance grep: with no exclusion it still prints lines from IntegrationTests/.build/checkouts/FoundationModelsExtras/.kanban/tasks/01M72ZZT85BK4KZN98GED16ZZC.{md,jsonl}. That directory is the gitignored SwiftPM checkout of the sibling repo, not a file of this repo. `grep -rni --exclude-dir=.build ...` (and `git grep`) give no lines.

    swift build: Build complete, no compiler warning. The build system prints one line "warning: missing creator for mutated node: ... mlx-swift_Cmlx.bundle/Contents/MacOS"; it is from the mlx-swift dependency bundle, not from this change. swift build ran more than one time by mistake (the later runs were no-op builds to show that line).
  timestamp: 2026-11-10T17:11:08.871055+00:00
- actor: claude-code
  id: 01m7372h975n7wf89nf72aft64
  text: |-
    ### implement — changed
    - evidence: 4 files — docs/GUIDE.md (shell line, new "Modes" section), docs/SECURITY.md (new "Tool modes and the shell" section), README.md (link text), Sources/FoundationModelsMultitool/Capabilities/Shell/Execute.swift (comment). `grep -rni --exclude-dir=.build -e seatbelt -e sandbox-exec Sources Tests IntegrationTests docs README.md` gives no lines; swift build: Build complete, no compiler warning. swift test not run (comments and docs only).
    - next: /review
  timestamp: 2026-11-10T17:11:14.471548+00:00
- actor: claude-code
  id: 01m73764jkj9kb977b7tzzd3mk
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (b3c6e19b): counts findings 0, confirmed 0, refuted 0. The engine reviewed Execute.swift. No validator matches README.md, docs/GUIDE.md or docs/SECURITY.md, so I checked those docs against the code by hand. Each claim agrees with the code: `init(mode: ToolMode = .open, sandboxProbe: SandboxProbe = .live)`; `build()` and `rebuildRegistry()` go through `RegistrySource.buildRegistry()`, which calls `validateToolMode()` -> `mode.validate(probe:)` first; the `sandboxed` refusal throws `MultiToolBuilderError(kind: .notAvailable(mode:), name: noun)` with a hint for the shell and a hint for stdio MCP; `StdioServerProcess.respawn()` throws `StdioServerProcessError.notAvailable(mode:)` in `sandboxed` mode; `SandboxProbe.live` and `.fixed(_:)` exist in FoundationModelsExtras. `git grep -i -e seatbelt -e sandbox-exec -- Sources Tests IntegrationTests docs README.md` gives no lines (the only disk hits are in the gitignored IntegrationTests/.build checkout). The Execute.swift comment keeps "UPSTREAM_ASKS.md Ask 6", which is the working-directory ask, not the Seatbelt item.
    - next: none. The task is in done.
  timestamp: 2026-11-10T17:13:12.531036+00:00
- actor: claude-code
  id: 01m7376qwsgva017grzp704tge
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 4 files (docs/GUIDE.md, docs/SECURITY.md, README.md, Execute.swift comment)
    - test: green — swift build complete, 0 compiler warnings; no code changed, so no swift test; git grep seatbelt/sandbox-exec on tracked files: 0 lines
    - commit: b3c6e19b (pushed to origin/main)
    - review: clean — 0 findings; docs checked by hand against the code
  timestamp: 2026-11-10T17:13:32.313353+00:00
depends_on:
- 01M7302A77H9QHS2YHJ0PN6G8D
- 01M73030WWZF8M6HM1S3XS0D60
- 01M7303G0Q7Q2N9GHQ1T8YE77Q
position_column: done
position_ordinal: fffffff580
title: 'MT-15: Docs for the modes and for no Seatbelt'
---
## What
Change the docs to agree with MT-15.

- `docs/GUIDE.md` line 9 ("a sandboxed `execute`") and line 15 ("Every shell command runs under a seatbelt sandbox"): the shell runs `/bin/sh -c` with the rights of the user. Add a short section "Modes": `open` has all capabilities; `sandboxed` has files, git, snapshots, web, environment and HTTP MCP servers, with no shell and no stdio MCP servers; `buildRegistry()` refuses `open` in a sandboxed process (EXTRAS-12). Git in `sandboxed` mode cannot push over SSH; HTTPS with a token works (D101).
- `docs/SECURITY.md`: add the same modes rule, and say that there is no command sandbox. Until Step 4 (D174) the shell of OpenTestudo has no guard.
- `README.md` line 51: the link text names the sandbox contract; keep it correct.
- `Sources/FoundationModelsMultitool/Capabilities/PathContainment.swift` lines 6 and 25: remove the text about `SeatbeltSandbox`. `PathContainment` and `PathGuard` stay (D21).
- Remove each other comment that names Seatbelt, `sandbox-exec` or the `UPSTREAM_ASKS.md` Seatbelt item (for example `Capabilities/Shell/Execute.swift` near line 105, `Capabilities/Shell/ShellDotfolder.swift`).

## Acceptance Criteria
- [x] `grep -rni -e seatbelt -e sandbox-exec Sources Tests IntegrationTests docs README.md` finds nothing.
- [x] `docs/GUIDE.md` and `docs/SECURITY.md` state the two modes and the capabilities of each.

## Tests
- [x] The grep above, run as a shell command, gives no lines.
- [x] Run `swift build` one time; it builds with no warnings (the comments changed only).

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #step1 #docs