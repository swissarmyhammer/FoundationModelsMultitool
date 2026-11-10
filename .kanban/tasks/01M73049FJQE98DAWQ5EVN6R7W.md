---
assignees:
- claude-code
depends_on:
- 01M7302A77H9QHS2YHJ0PN6G8D
- 01M73030WWZF8M6HM1S3XS0D60
- 01M7303G0Q7Q2N9GHQ1T8YE77Q
position_column: todo
position_ordinal: '8480'
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
- [ ] `grep -rni -e seatbelt -e sandbox-exec Sources Tests IntegrationTests docs README.md` finds nothing.
- [ ] `docs/GUIDE.md` and `docs/SECURITY.md` state the two modes and the capabilities of each.

## Tests
- [ ] The grep above, run as a shell command, gives no lines.
- [ ] Run `swift build` one time; it builds with no warnings (the comments changed only).

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #step1 #docs