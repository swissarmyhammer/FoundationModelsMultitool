---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0sx79z9dtypf2qf2knwcx39
  text: |
    Picked up ^98zgzyq. Research done.

    Discoveries:
    - `grep -rn ShellPolicy Sources Tests` finds exactly the 3 sites the card names: `SeatbeltSandbox.swift` header, `SeatbeltSandbox.swift` network bullet in the `profile(for:)` doc, and `ShellRunner.swift` in the `run(_:)` doc. Nothing else in `Sources/` or `Tests/` names the type. (`eventplan.md` names it twice; `^pqe3khv` owns that file.)
    - A FOURTH site in `SeatbeltSandbox.swift` defers to the deleted layer without naming it: the `wrap` doc says the working directory "comes from a parameter that the MODEL writes, and the policy only looks in it for `"../"`". No policy exists any more, thus the sentence is false in the same way as the three the card names. Same cause, same file, so it is corrected too.
    - `grep -niE 'polic(y|ies)'` over the Shell directory finds three other uses that are NOT this cause and stay as they are: "open the policy" at `SeatbeltSandbox.swift:50` means widen the Seatbelt profile; "this is not a read policy ... not a network policy" on `Options` is a design statement, not a deferral; the two "backpressure policy" uses in `ShellRunner.swift` are about the output stream. `ShellDotfolder.swift` also says "policy", and that file belongs to `^5325spr`.
    - The behaviour guard the card names is `SeatbeltSandboxTests.fixedProfile`, which holds the whole profile literal. No second copy is written.
  timestamp: 2026-08-24T12:51:44.233512+00:00
- actor: claude-code
  id: 01m0sxcsk10fxf313x8r89bvx6
  text: |
    Implementation landed. Comments only — the diff touches no statement, and the profile literal is byte for byte what it was.

    What changed in `SeatbeltSandbox.swift`:
    - The file header now says the layer is the ONLY gate, lists the two holes (each read is free everywhere, the network is fully open), names the consequence (a command can read each file the user can read and send it anywhere; destruction is bounded, reading and exfiltration are not), and names `profile(for:)` as the one place to change either one.
    - The summary paragraph of `profile(for:)` now says these rules are the whole gate, thus this is the place to change what a command reads and what it reaches on the network.
    - The network bullet drops `ShellPolicy` and states the exfiltration consequence beside the free reads.
    - The `wrap` doc no longer says "the policy only looks in it for `../`". It now says no layer above examines the working directory the model writes, which is why the containment check is load bearing.

    What changed in `ShellRunner.swift`:
    - The two length limits now belong to the `tools.shell.execute` verb (`^xgnygf8`), and the runner owns `maxOutputSize` alone.

    Verification, run in this order:
    - Before the edit: `swift test --filter SeatbeltSandbox` — 22 tests, 1 suite, pass. That is the baseline for the byte-for-byte profile guard.
    - `swift build --build-tests` — Build complete, no new warning.
    - After the edit: `swift test --filter SeatbeltSandbox` — 22 tests pass; `swift test --filter ShellRunner` — 27 tests pass.
    - `swift test` — 554 tests in 45 suites pass, which is the same count `^6e4x8nw` recorded. No new failure, no new warning. The one line the build prints, `missing creator for mutated node: ... mlx-swift_Cmlx.bundle`, is a SwiftPM build-system line that stands before this change as well.
    - `grep -rn "ShellPolicy" Sources Tests Package.swift` finds nothing.

    ### implement — changed
    - evidence: 2 files — /Users/wballard/github/swissarmyhammer/FoundationModelsMultitool/Sources/FoundationModelsMultitool/Capabilities/Shell/SeatbeltSandbox.swift, /Users/wballard/github/swissarmyhammer/FoundationModelsMultitool/Sources/FoundationModelsMultitool/Capabilities/Shell/ShellRunner.swift (32 insertions, 18 deletions, comments only); swift test 554 tests / 45 suites pass
    - next: /review
  timestamp: 2026-08-24T12:54:44.065102+00:00
depends_on:
- 01M0SVAZ3WJH2BQFJSA6E4X8NW
position_column: doing
position_ordinal: '8380'
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

- [x] `SeatbeltSandbox.swift` names `ShellPolicy` nowhere.
- [x] `ShellRunner.swift` names `ShellPolicy` nowhere.
- [x] The sandbox header states that the sandbox is the only gate.
- [x] The docs state that reads are free and the network is open, and name the
      exfiltration consequence.
- [x] The docs name the profile as the place to change either one.
- [x] `SeatbeltSandbox.profile(for:)` (declared at line 252) emits byte-identical
      text to before this task.

## Tests

- [x] **Do not write a new profile guard.** One exists:
      `Tests/FoundationModelsMultitoolTests/SeatbeltSandboxTests.swift:135-142`
      already holds the whole profile byte for byte. Assert it stays green,
      which is what proves a doc rewrite changed no behavior.
- [x] `swift test --filter SeatbeltSandbox` passes.
- [x] `swift test --filter ShellRunner` passes.
- [x] `swift test` passes with no new failure and no new warning.

## Workflow
- This task edits comments only. `/tdd` does not apply — the behavior guard is
  the existing profile test, which must be green before and after. #phase-2 #eventplan