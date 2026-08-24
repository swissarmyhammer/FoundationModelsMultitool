---
assignees:
- claude-code
depends_on:
- 01M0SVAZ3WJH2BQFJSA6E4X8NW
position_column: todo
position_ordinal: '9480'
title: Remove the ShellPolicy references from the sandbox and runner docs
---
## What

Three doc sites defer to a type that no longer exists. All three are now false.

`Sources/FoundationModelsMultitool/Capabilities/Shell/SeatbeltSandbox.swift`:

- **Lines 6-10**, the file header: *"WHETHER a command runs at all stays the
  decision of `ShellPolicy`. This layer bounds only what a command that already
  went through the policy can do."*
- **Lines 246-248**, the network paragraph: *"To bound which commands can run at
  all — network tools included — stays with `ShellPolicy`."*

`Sources/FoundationModelsMultitool/Capabilities/Shell/ShellRunner.swift`:

- **Lines 288-291**: the command-length and environment-value-length limits
  *"belong to `ShellPolicy`, which the caller runs before this call. The runner
  takes input that is already examined."* Rewrite it to say those checks belong
  to the `tools.shell.execute` verb, which `^xgnygf8` adds, and that the one cap
  the runner owns is `maxOutputSize`.

Rewrite all three so they describe the real posture. The profile itself does not
change — only the text that explains it. What the profile truly gives, measured
from the literal at `SeatbeltSandbox.swift:260-273`:

- `(deny default)` with the least allowances that let `/bin/sh` start.
- **Writing and deleting are bounded** to the granted subpaths. This is the one
  real guard, and the kernel enforces it, thus how a command is spelled does not
  matter.
- **Every read is free**, everywhere. `(allow file-read*)` is unconditional and
  there is no `deny file-read*` of any kind.
- **The network is fully open**: `(allow network*)` and `(allow system-socket)`.

State the consequence plainly, because a reader must not think the sandbox
covers more than it does: a command can read any file the user can read and send
it anywhere. Destruction is bounded; reading and exfiltration are not. Name the
place that would change either one — the profile — and not a policy layer.

Do not add a read policy or a network policy in this task.

## Acceptance Criteria

- [ ] `SeatbeltSandbox.swift` names `ShellPolicy` nowhere.
- [ ] `ShellRunner.swift` names `ShellPolicy` nowhere.
- [ ] The sandbox header states that the sandbox is the only gate.
- [ ] The docs state that reads are free and the network is open, and name the
      exfiltration consequence.
- [ ] The docs name the profile as the place to change either one.
- [ ] `SeatbeltSandbox.profile(for:)` (declared at line 252) emits byte-identical
      text to before this task.

## Tests

- [ ] **Do not write a new profile guard.** One exists:
      `Tests/FoundationModelsMultitoolTests/SeatbeltSandboxTests.swift:135-142`
      already holds the whole profile byte for byte. Assert it stays green,
      which is what proves a doc rewrite changed no behavior.
- [ ] `swift test --filter SeatbeltSandbox` passes.
- [ ] `swift test --filter ShellRunner` passes.
- [ ] `swift test` passes with no new failure and no new warning.

## Workflow
- This task edits comments only. `/tdd` does not apply — the behavior guard is
  the existing profile test, which must be green before and after. #phase-2 #eventplan