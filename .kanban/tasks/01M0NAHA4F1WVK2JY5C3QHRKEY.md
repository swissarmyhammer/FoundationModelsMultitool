---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0ntnz9zggyzmf73wex75ry6
  text: |-
    ### Research

    Read the source (`../FoundationModelsShelltool/Sources/ShellTool/SeatbeltSandbox.swift`, 526 lines) and the seam that landed in ^77dasar.

    Discoveries that shape the port:

    1. `SandboxPreflight.swift` is ALREADY here from ^77dasar. It carries `CanaryResult`, `CanarySpawn`, `liveCanarySpawn` and `CanaryGate`. `SeatbeltSandbox` uses each of them as it is. Nothing of the canary machinery gets ported again.
    2. The profile text carries NO path. A path travels only as a `-D NAME=value` pair, and the profile names the parameter. Thus the profile text is a function of the COUNT of roots and of extra write paths, and of nothing else. The exact-text regression test is therefore fully deterministic.
    3. The tests that ^77dasar ported (`SandboxSurfaceTests`, `SandboxPreflightTests`) already cover the identity sandbox and the public seam. What the sibling `CommandSandboxTests.swift` holds and this repository does NOT yet hold is the value semantics of `SandboxedInvocation` — equality AND inequality on each of the two fields. That is what the new `CommandSandboxTests.swift` carries. The sibling `RecordingSandbox` fake belongs to the runner tests, and the runner is not ported yet.
    4. The sibling `SandboxPreflightTests.swift` holds SeatbeltSandbox-specific preflight tests (canary argv, a broken `profileOverride`, a missing wrapper binary, a working directory outside each root, a spawn failure that travels untyped, one gate for each sandbox value). ^77dasar could not port them, because `SeatbeltSandbox` did not exist. They come with this card, in `SeatbeltSandboxTests.swift`. Without them `profileOverride` and `canarySpawn` would be properties that nothing writes.
    5. `TestScratch` (Tests/.../Fixtures/ShellStoreFixtures.swift) makes an owned temporary directory with each symbolic link resolved. It answers the path precondition of `CommandSandbox`.
    6. `/usr/bin/sandbox-exec` is present on this host.
  timestamp: 2026-08-22T22:50:21.375797+00:00
- actor: claude-code
  id: 01m0nvew57d7abceeq16eb4s4p
  text: |-
    ### What happened

    TDD, red first. The two test files went in and `swift build --build-tests`
    showed `cannot find 'SeatbeltSandbox' in scope`. Then the source went in, and
    the tests turned green.

    **A real trap that the red pass found.** Five preflight tests failed with
    `workingDirectoryOutsideRoots`. `TestScratch.makeDirectory` resolves with
    `URL.resolvingSymlinksInPath()`, which gives back `/var/folders/…`, while
    `SeatbeltSandbox.Options` resolves each root with `realpath(3)` and gets
    `/private/var/folders/…`. The two forms name one directory and they do not
    compare equal. The fix is a `makeResolvedDirectory(prefix:)` helper in the test
    file that puts the scratch directory through `realpath(3)`, which is what a
    real caller does.

    That trap shows a WRONG line in the doc comment of `CommandSandbox`, which
    landed with ^77dasar: it tells each caller to use "`realpath(3)` or
    `URL.resolvingSymlinksInPath()`", and the second one does not answer the
    precondition on macOS. `CommandSandbox.swift` is not the file of this card, thus
    the correction is a task of its own: ^aqv2egq.

    ### Choices worth recording

    1. The exact-profile regression test holds the WHOLE profile for one fixed
       configuration — one writable root and one extra write path — as a literal.
       That is deterministic on each host, because a path never reaches profile
       text. It also covers, byte for byte, what the four Shelltool tests covered
       line by line (`deny default`, `/dev/null`, `file-read*`, `network*`); those
       four are kept, and the literal is the pin that turns red on ANY change to
       the confinement.
    2. `SandboxPreflight.swift` came with ^77dasar, and this card uses
       `CanaryResult`, `CanarySpawn`, `liveCanarySpawn` and `CanaryGate` as they
       are. None of it is ported again.
    3. `SeatbeltSandboxTests.swift` also carries the SeatbeltSandbox-specific
       preflight tests from the Shelltool `SandboxPreflightTests.swift`. ^77dasar
       could not port them, because the type did not exist. Without them
       `profileOverride` and `canarySpawn` would be properties that nothing writes.
    4. `CommandSandboxTests.swift` carries the value semantics of
       `SandboxedInvocation` — equality AND inequality on each of the two fields.
       The identity-sandbox tests of the Shelltool file already stand here, in
       `SandboxPreflightTests` and `SandboxSurfaceTests`. The `RecordingSandbox`
       fake of that file belongs to the runner tests, and the runner is not ported.
    5. No `.enabled(if:)` host gate. The package is macOS 27 only, and
       `/usr/bin/sandbox-exec` is part of macOS. A gate would make the suite report
       green on a host where the confinement does not work.
    6. The one test with no assertion was rewritten. "the canary passes" now reads
       "a canary that the real wrapper passes latches the gate", and it asserts
       that a second preflight runs no canary at all.

    ### Style

    Each comment and each doc comment is in ASD-STE100 Simplified Technical
    English, at the density of the neighbouring `Capabilities/Shell/` files.
    Self-check: no numeric literal outside a `static let` (the allowed set is 0, 1,
    -1, 100); no optional that is never absent; no property that nothing writes and
    nothing reads; the repeated `wrap` call goes through one helper; no parameter
    label that says the name of its receiver again; no `import Operations`.
  timestamp: 2026-08-22T23:03:57.351902+00:00
- actor: claude-code
  id: 01m0nvf5phgy0t2gnabej35181
  text: |-
    ### implement — changed
    - evidence: 3 files — Sources/FoundationModelsMultitool/Capabilities/Shell/SeatbeltSandbox.swift (new, 570 lines), Tests/FoundationModelsMultitoolTests/SeatbeltSandboxTests.swift (new, 17 tests), Tests/FoundationModelsMultitoolTests/CommandSandboxTests.swift (new, 3 tests). `touch Sources/.../Shell/*.swift && swift build --build-tests` shows only the known mlx-swift_Cmlx.bundle warning. `swift test` — 500 tests in 42 suites passed, 0 failures, 0 new warnings. `swift test --filter Seatbelt` — 17 tests passed.
    - next: /review. New task ^aqv2egq holds the wrong resolver line on `CommandSandbox`.
  timestamp: 2026-08-22T23:04:07.121276+00:00
- actor: claude-code
  id: 01m0nvyaq7rywc61eb1193nbrn
  text: |
    ### review — findings
    - evidence: `review sha HEAD~1..HEAD` (commit 2536b78), 3 files. counts: 1 finding, 1 confirmed, 0 refuted, 7 attempted. Tests/FoundationModelsMultitoolTests/SeatbeltSandboxTests.swift:218 — `reuse/reuse`.
    - next: /implement — remove the duplicated `realpath(3)` wrapping from the test helper. Make `Options.resolved` internal, or add one module-level realpath wrapper, and call it. Remove the cause from the whole file, not the one line. Task stays in review.
  timestamp: 2026-08-22T23:12:23.783519+00:00
- actor: claude-code
  id: 01m0nvyywpdpwesh4a5br1tv8f
  text: |
    ### finish iteration 1 — findings
    - implement: changed — 3 new files (Capabilities/Shell/SeatbeltSandbox.swift, SeatbeltSandboxTests.swift with 17 tests, CommandSandboxTests.swift with 3 tests)
    - test: green — a forced rebuild reports no compiler warning; `swift test` gives 500 tests in 42 suites passed, 0 failures, 0 skipped, over two runs because some tests spawn a real `sandbox-exec` canary
    - commit: 2536b78 — feat(shell): add SeatbeltSandbox
    - review: findings — 1 confirmed, at Tests/FoundationModelsMultitoolTests/SeatbeltSandboxTests.swift:218
    - verified good: the security-relevant parts each raised nothing — the profile text stays byte for byte, a path cannot leave a granted root by traversal, by relativity or by a shared text prefix, and each failure path fails closed with no route to an unconfined spawn.
    - next: implement the one finding — one shared resolver that the source and the test both call, so the test cannot drift from what the sandbox enforces
  timestamp: 2026-08-22T23:12:44.438644+00:00
- actor: claude-code
  id: 01m0nwbe8nhrywp0svxtqy7gkw
  text: |-
    ### Re-implement pass — the one open finding

    **The finding.** `SeatbeltSandboxTests.swift:218` reimplemented the `realpath(3)`
    wrapping that `Options.resolved` already held.

    **The fix.** One shared resolver. `Options.resolved` (private, nested) is gone.
    In its place `SeatbeltSandbox.swift` now holds one module-level function,
    `resolvedPath(_:)`, at file scope beside the type. `Options.init` maps each
    writable root and each extra write path through it, and the test helper
    `makeResolvedDirectory(prefix:)` calls that same function. The test can no
    longer disagree with what the sandbox enforces, because there is one copy of the
    resolution.

    The choice of a module-level function follows the shape of the neighbouring
    `SandboxPreflight.swift`, which already holds `liveCanarySpawn` and its
    constants at file scope.

    **TDD.** Red first: the three new tests went in, and
    `swift build --build-tests` gave `cannot find 'resolvedPath' in scope` five
    times. Then the source change turned them green.

    **New tests (3).** The shared resolver had no test of its own before this pass,
    and neither did the resolution that `Options` performs:
    1. "the shared resolver gives the form Seatbelt matches, where the resolver of
       Foundation does not" — pins `/tmp` → `/private/tmp` through `resolvedPath`,
       AND `/private/tmp` → `/tmp` through `URL.resolvingSymlinksInPath()`. That
       turns the trap of the first pass into an executable claim.
    2. "a path the resolver cannot resolve stays as it is" — the documented
       fallback. To drop such a path would quietly make the confinement smaller.
    3. "each configured path goes through the shared resolver" — `Options` resolves
       BOTH lists, and the expectation itself calls `resolvedPath`.

    **The whole-file audit.**
    - Path resolution: `resolvedPath` is now the ONE `realpath(3)` site in the whole
      `Sources/` tree. Verified by grep for `realpath`, `String(cString:)` and
      `free(` — one implementation.
    - Path comparison: `path(_:isInside:)` and `normalizedComponents(of:)` have one
      copy each in the source, and the test file reimplements neither. It states
      expectations as literal paths, which is the pin, not a copy of the logic.
    - Other test helpers: `occurrences(of:in:)`, `writeLine(of:)` and
      `invocation(from:…)` have no counterpart in the source. `CanarySpawnCounter`
      is a fake, not a copy.
    - The constants that the test holds as literals — `/usr/bin/sandbox-exec`,
      `/usr/bin/true`, `-p`, `-D`, the whole profile text — are KEPT as literals on
      purpose. They are the pins of the contract: a source that changes makes them
      fail loudly. The resolver was the opposite case, where two copies disagree in
      silence. That difference is why one was shared and the others were not.
    - The type doc of `SeatbeltSandbox` repeated the Foundation-resolver example
      that now stands on `resolvedPath`. It now points at the function instead.

    **Still open elsewhere, not this card.** `CommandSandbox.swift` still tells each
    caller to use "`realpath(3)` or `URL.resolvingSymlinksInPath()`", and the second
    one does not answer the precondition on macOS. That is ^aqv2egq.

    **Verification.** `touch Sources/.../Shell/*.swift && swift build --build-tests`
    reports only the known `mlx-swift_Cmlx.bundle` warning of the build system.
    `swift test --filter Seatbelt` — 20 tests passed. `swift test` twice — 503 tests
    in 42 suites passed both times, 0 failures, 0 skipped. Two runs, because the
    seatbelt tests spawn a real canary child.
  timestamp: 2026-08-22T23:19:33.397409+00:00
- actor: claude-code
  id: 01m0nwhx8ffey4rqesxcwj8p3p
  text: |-
    ### implement — changed
    - evidence: 2 files — Sources/FoundationModelsMultitool/Capabilities/Shell/SeatbeltSandbox.swift (new module-level `resolvedPath(_:)`; the private nested `Options.resolved` is gone; `Options.init` maps both lists through the shared function; two doc comments corrected), Tests/FoundationModelsMultitoolTests/SeatbeltSandboxTests.swift (`makeResolvedDirectory` now calls `resolvedPath`; 4 new tests; 3 new constants). Build: `touch Sources/.../Shell/*.swift && swift build --build-tests` reports only the known `mlx-swift_Cmlx.bundle` warning of the build system. Tests: `swift test --filter Seatbelt` — all pass; `swift test` twice — 504 tests in 42 suites passed each time, 0 failures, 0 skipped.
    - finding: `SeatbeltSandboxTests.swift:218` `reuse/reuse` is now `- [x]`. `resolvedPath` is the ONE `realpath(3)` site in the whole `Sources/` tree, and the test calls that same function.
    - next: /review. Task stays in `doing`, and it is not committed.
  timestamp: 2026-08-22T23:23:05.359497+00:00
- actor: claude-code
  id: 01m0nwvv3dam0qsgj41mn2rs8a
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (65862a6) — 0 findings, 0 confirmed, 0 refuted, 7 attempted, 0 failed. 2 files reviewed, 0 not reviewed. The finding of the first pass at `Tests/FoundationModelsMultitoolTests/SeatbeltSandboxTests.swift:218` is closed: `resolvedPath(_:)` at `Sources/FoundationModelsMultitool/Capabilities/Shell/SeatbeltSandbox.swift:34` is the one `realpath(3)` site of the module; `Options.init` puts `writableRoots` and `extraWritePaths` through it; the test helper calls it and no longer copies the pattern.
    - next: none — task moved to done.
  timestamp: 2026-08-22T23:28:30.829910+00:00
- actor: claude-code
  id: 01m0nwwvatwjjjabdx9fkhtnyq
  text: |
    ### finish iteration 2 — clean
    - implement: changed — 2 files (Capabilities/Shell/SeatbeltSandbox.swift, SeatbeltSandboxTests.swift), 4 new tests
    - test: green — a forced rebuild reports no compiler warning; `swift test` gives 504 tests in 42 suites passed, 0 failures, 0 skipped, over two runs
    - commit: 65862a6 — refactor(seatbelt): use one path resolver for sandbox and tests
    - review: clean — 0 findings. `resolvedPath(_:)` is the one `realpath(3)` site in the repository; its body matches the private step it replaced step for step; both grant lists go through it; and the fallback for a path that does not resolve fails closed — it can make a grant miss the vnode path, and it can never make a grant match a path the host did not ask for.
    - next: done
  timestamp: 2026-08-22T23:29:03.834423+00:00
- actor: claude-code
  id: 01m0nx1hbf6xqpp6a5cn23pk1f
  text: |-
    ### Rules check against the diff

    The validator dump for `.swift` is 10,874 lines, and a sub agent read it and
    reported each rule that bears on this change. Every applicable rule was checked
    against the diff, and each one holds. No further edit was necessary.

    - `swift/access-control` — "Library code defaults to `internal`". `resolvedPath`
      is `internal`, which is the stated default. The change WIDENS access
      (private → internal), thus the "trace every call site" gate, which covers a
      narrowing, does not apply.
    - `swift/doc-parameter-naming` — "`- Parameter` entries name the internal
      (local) parameter, never the external argument label." `resolvedPath(_ path:)`
      has no separate label, thus `path` is the only documentable name, and the doc
      comment writes `- Parameter path:`. The same holds for
      `makeResolvedDirectory(prefix:)`.
    - `swift/naming-clarity` — "Compensate for weak type information: precede a
      weakly typed parameter (`String` included) with a noun describing its role."
      The base name carries that noun — `resolvedPath` — which is the shape of the
      DO example of the rule, `addObserver(_ observer:)`.
    - `swift/fluent-usage` — "Side-effect-free operations are noun phrases."
      `resolvedPath` is a noun phrase, and the function is pure.
    - `swift/casing` — `resolvedPath`, `symbolicLinkedTemporary`,
      `resolvedTemporary` and `absentPath` are each `lowerCamelCase`.
    - `swift/idioms` — "Don't repeat the enclosing type's name in a static member."
      A free function has no enclosing type, thus this is one more reason the
      module-level shape beats a `static` on `Options`.
    - `missing-docs-swift` — `warning: [open, public]`, thus an `internal`
      declaration is never reported. The doc comment is written anyway, at the
      density of the file.
    - `dead-code-swift` — the run uses `--build-tests`, thus the test target counts
      as a caller. `resolvedPath` has a caller in the source AND in the test.
    - `duplication` / `reuse` — this change is the fix the rule prescribes: "No
      shared function exists yet. Extract one from the changed code, and
      parameterize the difference." `completeness/invariant-propagation` then
      exempts it: "A shared helper already centralizes the handling and the change
      went there, so all callers inherit it."
    - `magic-numbers-swift` — the new constants are `static let`, and the rule
      measures a `static let` silent. No numeric literal was added.
    - `no-test-cheating` — each new test carries an assertion. `assertion-census`
      holds no swift-testing vocabulary, thus it reports "no census mapping" for
      this file, which is not a finding.
    - `test-partitioning` — the new tests sit in the unit target, no environment
      variable gates any of them, and `realpath(3)` on the local file system is not
      one of the external systems the rule lists (the network, a database, a spawned
      server, a real service).
    - `no-hard-code` — each literal stands in the expected-value position of an
      assertion, which is the carve-out the rule grants.
    - `completeness/public-output-contract` — no public declaration was removed,
      re-signed, or hidden. `Options.resolved` was `private`.

    Two facts worth keeping for the next agent:
    1. NO rule in the whole dump mentions ASD-STE100 or plain language. That
       requirement comes from `~/.claude/CLAUDE.md`, and not from a validator.
    2. `swift/idioms` states that whitespace, indentation and import ordering are
       the job of `swift-format` and not review findings. A bare `swift-format lint`
       in this tree reports the 2-space default against the 4-space style of the
       repository, and a committed file that nothing changed reports 116 such lines.
       Do not chase those.
  timestamp: 2026-08-22T23:31:37.455426+00:00
depends_on:
- 01M0NAGV7MBVT0VCBMG77DASAR
position_column: done
position_ordinal: e380
title: Port SeatbeltSandbox
---
## What

Port the macOS seatbelt confinement that conforms to `CommandSandbox`. It
bounds where a command writes and deletes. Reads stay unrestricted, and the
network stays available.

- Create `Sources/FoundationModelsMultitool/Capabilities/Shell/SeatbeltSandbox.swift`
  from `../FoundationModelsShelltool/Sources/ShellTool/SeatbeltSandbox.swift`
  (526 lines).
- Keep the generated profile text byte for byte. A change to the profile is a
  change to the confinement.
- `ShellPolicy` keeps the decision of *whether* a command runs. The sandbox
  bounds only the damage a command that runs can do.
- Do not import `Operations`.

## Acceptance Criteria

- [x] `SeatbeltSandbox` is in
      `Sources/FoundationModelsMultitool/Capabilities/Shell/`, and it conforms
      to `CommandSandbox`.
- [x] The profile that `wrap(...)` generates is identical to the profile that
      Shelltool generates for the same input.
- [x] A command under the sandbox cannot write outside the permitted
      directories.
- [x] The file does not import `Operations`.

## Tests

- [x] New `Tests/FoundationModelsMultitoolTests/SeatbeltSandboxTests.swift`,
      ported from
      `../FoundationModelsShelltool/Tests/ShellToolTests/SeatbeltSandboxTests.swift`.
- [x] New `Tests/FoundationModelsMultitoolTests/CommandSandboxTests.swift`,
      ported from
      `../FoundationModelsShelltool/Tests/ShellToolTests/CommandSandboxTests.swift`.
- [x] A regression test asserts on the exact profile text for one fixed input.
- [x] `swift test --filter Seatbelt` passes.
- [x] `swift test` passes with no new failure and no new warning.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #phase-2 #eventplan

## Review Findings (2026-08-22 18:07)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 3 file(s) reviewed, 0 not reviewed.

- [x] `Tests/FoundationModelsMultitoolTests/SeatbeltSandboxTests.swift:218` `reuse/reuse` — Reimplements realpath wrapping logic that already exists in SeatbeltSandbox.swift:130-134 (`Options.resolved`); lines 218-220 duplicate the identical pattern rather than reusing it. Refactor to make Options.resolved internal (or create a module-level realpath wrapper) so this test helper can call it instead of duplicating the pattern.
