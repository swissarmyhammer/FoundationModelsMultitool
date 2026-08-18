---
assignees:
- claude-code
position_column: todo
position_ordinal: '8680'
title: multitool-cli says direct mode registers only runCode; it also vends wait
---
Direct mode takes discovery away and nothing else: `Registry.makeSessionTools(librarian:)` mounts `wait` in both modes, and `README.md` says so ("A direct-mode registry vends `runCode` and `wait` alone — direct mode takes discovery away, never detachment"). Three places in `Sources/multitool-cli/CLIRunner.swift` still say only `runCode` is registered:

- `CLIArguments.direct`'s doc: "only `multiTool`/`runCode` is registered with the session, no discovery".
- `CLIRunner.directFlag`'s `descriptionLines`, which is **user-facing `--help` output**: "Run in direct mode: only the runCode tool is registered with the session (no searchTools tool)".
- `runDemo`'s `direct` parameter doc: "only `multiTool` is registered with the session, `searchToolsTool` is omitted".

`CLIRunner.run(...)`'s own summary doc is already right — it says "`runCode` and `wait` alone under `--direct`" — so the file contradicts itself.

Found during the documentation-accuracy sweep on `^yzhpjab`/`^523qwcy`/`^mxjt7y5`. Left out of that sweep deliberately: it is a different cause (what direct mode drops), and the flag's `descriptionLines` is a shipped string a user reads, not a comment, so it was outside that pass's "documentation only, no executable code" constraint.

## Acceptance Criteria

- [ ] `--help` states what direct mode really vends
- [ ] No doc comment in `CLIRunner.swift` contradicts `run(...)`'s own summary
- [ ] `CLIArgumentTests`' usage-text assertions still hold, and ungated `swift test` is green