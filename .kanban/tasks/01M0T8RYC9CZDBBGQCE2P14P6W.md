---
comments:
- actor: claude-code
  id: 01m0tnq79bd9bma7ekqvp88h95
  text: |-
    Research done. Facts found before the edit:

    - Precondition met. `FoundationModelsExtras` `origin/main` holds `Sources/FoundationModelsExtras/ProcessRegistry.swift` at commit `090e38a`, and `public final class ProcessRegistry: Sendable` carries `public init()`, `public func register(_:)`, `public func deregister(_:)`, `public var registeredPids`, `public func sweep(_:)` and `public static var global`. The shapes of `register` and `deregister` are the same as the local copy, thus the two call sites in `ShellRunner.run` do not change.
    - The local copy is used by more files than the card names. `ProcessRegistry()` also stands in three test files beside the registry tests: `ShellRunnerTests.swift`, `ShellExecuteTests.swift` and `ShellHistoryOpsTests.swift`. Each takes `@testable import FoundationModelsMultitool` only, thus each needs `import FoundationModelsExtras` after the type moves out of this package. This is an import line, and no assertion changes.
    - `Sources/.../Capabilities/Shell/Execute.swift` also names `ProcessRegistry`, in one doc comment. The acceptance criterion says `rg -l "ProcessRegistry" Sources` must name `ShellRunner.swift` ONLY, thus that sentence must stop naming the type.
    - `Interpreter/JSCInterpreter.swift` does not hold the text `ProcessRegistry`, thus it never enters that grep. It is not touched.
    - Extras declares tools 6.2 and macOS 27; this package declares tools 6.1 and macOS 27. Extras brings Stencil and Yams as its own pinned dependencies.
    - `FoundationModelsRouter` declares no `ProcessRegistry`, thus the import adds no ambiguity at the one use site.
  timestamp: 2026-08-24T19:59:51.595670+00:00
- actor: claude-code
  id: 01m0tpwqrzem6aktxthttgc164
  text: |-
    Implementation landed. What happened, and the two things the next agent should know:

    1. `swift package resolve` took 10 seconds, and not the 28 minutes an earlier session met. No SwiftPM lock stood under `.build`. Extras resolved at `main (c713295)`, which carries `090e38a`.

    2. The nested integration package needed a LOCAL pin refresh, and this is not a defect of the repository. `swift build --package-path IntegrationTests --build-tests` first failed with `type 'RunKind' has no member 'process'` at `Execute.swift:161` — a line this card never touched. The cause: `IntegrationTests/Package.resolved` is git-ignored, and on this machine it pinned `FoundationModelsRouter` at `37f1339`, while the root package resolves `226ff41`. The older Router carries no `RunKind.process`, thus the same build breaks at HEAD with or without this card. `swift package update --package-path IntegrationTests FoundationModelsRouter` moved that pin to `226ff41`, and the build then completed. Nothing of the repository changed: both `Package.resolved` files stand under `.gitignore:17`, and CI resolves each run from nothing.

    The integration suite ran with `--no-parallel`. The card names `swift test --package-path IntegrationTests`, and `IntegrationTests/Package.swift` states that the flag is mandatory rather than a preference: each scenario queues behind `LiveProfileTurnstile` for the one resident live profile, thus a parallel run spends each test's time limit on queue time and a queued suite fails the way a hang fails. The run is the card's run plus that flag.

    Test counts, which prove the deletion: the run before this card measured 572 tests in 47 suites, and the run after it measures 568 tests in 46 suites — exactly the 4 tests and the 1 suite of `ShellProcessRegistryTests`.
  timestamp: 2026-08-24T20:20:20.895775+00:00
- actor: claude-code
  id: 01m0tpx1d1xbwfxtp5g502nv41
  text: |-
    ### implement — changed
    - evidence: 8 files — Package.swift (+extrasDependencyName, dependency, product on the library target and the test target); DELETED Sources/FoundationModelsMultitool/Capabilities/Shell/ProcessRegistry.swift; DELETED Tests/FoundationModelsMultitoolTests/ShellProcessRegistryTests.swift; Sources/.../Shell/ShellRunner.swift (+import FoundationModelsExtras, registry doc corrected); Sources/.../Shell/Execute.swift (one doc sentence no longer names the type); Tests/.../ShellRunnerTests.swift, ShellExecuteTests.swift, ShellHistoryOpsTests.swift (+import FoundationModelsExtras, no assertion changed). Verified: `rg -l "ProcessRegistry" Sources` names ShellRunner.swift alone and not JSCInterpreter.swift; `swift package resolve` 10s; `swift build` clean; `swift test` 568 tests in 46 suites, 0 failures, and no `ShellProcessRegistryTests`; `swift test --filter ShellRunnerTests` 27 tests pass, the group-kill test and the register/deregister test among them; `swift build --package-path IntegrationTests --build-tests` clean; `swift test --package-path IntegrationTests --no-parallel` 65 tests in 12 suites pass in 12m22s.
    - next: /review
  timestamp: 2026-08-24T20:20:30.753690+00:00
- actor: claude-code
  id: 01m0tq117e603e2bn5c02j6427
  text: |-
    ### test — green
    - evidence: `swift test` (run 1): 568 tests, 46 suites, all pass. `swift test` (run 2): 568 tests, 46 suites, all pass. No stray `sleep` process after either run (checked with `ps aux`). `swift test --filter ShellRunnerTests`: 27 tests, 1 suite, all pass, including "the group kill at the time limit leaves no survivor in the process tree" and "an echo round trip captures one line and exits zero".
    - note: one `warning:` line appears in build output ("missing creator for mutated node" for the vendored `mlx-swift_Cmlx.bundle`). It is a SwiftPM/llbuild build-system diagnostic about the third-party `mlx-swift` dependency's resource bundle, not a warning in this package's own Swift source. No compiler warnings from any file in `Sources/` or `Tests/`.
    - next: ready for review.
  timestamp: 2026-08-24T20:22:41.646155+00:00
position_column: doing
position_ordinal: '80'
title: Use the shared ProcessRegistry from FoundationModelsExtras; delete the local copy
---
## What

`FoundationModelsExtras` gets a `public` `ProcessRegistry`. That is task
`y418mzx` on the `FoundationModelsExtras` board. This package holds one of four
copies of that type. Delete this copy and use the shared type.

Do this task only after `y418mzx` is done and is on the `main` branch of
`FoundationModelsExtras`. This package resolves that dependency from a branch.

The copy is
`Sources/FoundationModelsMultitool/Capabilities/Shell/ProcessRegistry.swift`,
154 lines. Remove the comments and the blank lines, and it differs from the
ACPClient copy by one line only: an explicit `init() {}`. One file uses it:

- `Capabilities/Shell/ShellRunner.swift:315` — `registry.register(pid)`
- `Capabilities/Shell/ShellRunner.swift:325` — `registry.deregister(pid)`
- `Capabilities/Shell/ShellRunner.swift:85` and `:88` — doc comments that name
  `ProcessRegistry.global`

`Interpreter/JSCInterpreter.swift:977` has `registry.register(resolve:reject:name:)`.
That is a different type. Do not touch it.

### 1. Add the dependency

`Package.swift` builds family dependencies through the helper
`swissArmyHammerPackage(name:branch:)` at line 60, which defaults to
`mainBranch` (line 31), and it names each dependency with a constant, such as
`routerDependencyName`. Follow that style:

- Add a constant `let extrasDependencyName = "FoundationModelsExtras"`.
- Add `swissArmyHammerPackage(name: extrasDependencyName)` to `dependencies`.
- Add `.product(name: extrasDependencyName, package: extrasDependencyName)` to
  the library target and to the test target, which starts at line 290.

### 2. Delete the copy and import the shared type

- Delete
  `Sources/FoundationModelsMultitool/Capabilities/Shell/ProcessRegistry.swift`.
- Add `import FoundationModelsExtras` to
  `Sources/FoundationModelsMultitool/Capabilities/Shell/ShellRunner.swift`.
- The two call sites do not change. `register` and `deregister` keep their
  names and their shapes.
- The free function `sweep(_:)`, the private global, and the `atexit` installer
  go away with the file. The shared type owns them now.

There is one behavior change, and it is the purpose of this task. Today this
package installs an `atexit` sweep over a global registry of its own. After the
change, every consumer in the host process shares one registry and one sweep.

### 3. Delete the local tests of the type

Delete `Tests/FoundationModelsMultitoolTests/ShellProcessRegistryTests.swift`.
The behavior tests of the type move to `FoundationModelsExtras` with the type,
in task `y418mzx`. Do not delete `ShellRunnerTests.swift`.

### 4. Rewrite the comments that name a sibling package

The copied files in this capability carry comments that call themselves a
behavioral port of `../FoundationModelsShelltool`. The registry file goes away
with its comments. Check `ShellRunner.swift:85` and `:88`, and correct any
sentence that says this package holds its own copy of the registry.

## Acceptance Criteria

- [ ] `Sources/FoundationModelsMultitool/Capabilities/Shell/ProcessRegistry.swift`
      does not exist.
- [ ] `Tests/FoundationModelsMultitoolTests/ShellProcessRegistryTests.swift`
      does not exist.
- [ ] `Package.swift` has an `extrasDependencyName` constant, adds the package
      through `swissArmyHammerPackage(name:)`, and gives the product to the
      library target and the test target.
- [ ] `ShellRunner.swift` has `import FoundationModelsExtras`.
- [ ] `rg -l "ProcessRegistry" Sources` names `ShellRunner.swift` only, and does
      not name `JSCInterpreter.swift`.
- [ ] No comment in `Capabilities/Shell` says this package holds its own copy
      of the registry.

## Tests

- [ ] `Tests/FoundationModelsMultitoolTests/ShellRunnerTests.swift` (926 lines)
      is the regression test for this task. It spawns real processes and counts
      them in the process tree. Two of its tests exercise the registry path
      directly: "the group kill at the time limit leaves no survivor in the
      process tree", and "an echo round trip captures one line and exits zero".
      Every test must pass with no change to its assertions. That proves the
      shared registry behaves the same in the register, deregister, and reap
      path.
- [ ] Do not port the deleted registry tests into this package. They live in
      `FoundationModelsExtras` with the type.
- [ ] Run `swift package resolve` first, so the new dependency resolves.
- [ ] Run `swift build`. It must succeed.
- [ ] Run `swift test`. Every remaining test must pass, and the output must not
      name `ShellProcessRegistryTests`.
- [ ] Run `swift test --package-path IntegrationTests` as well. A root
      `swift test` cannot reach that nested package, and CI runs it through the
      `integration-package-path: IntegrationTests` input to the shared
      `swift-ci` workflow. Its tests cover model scenarios, not the shell
      capability, but they build against this package. The new dependency must
      not break them. A green root run alone does not prove that.

## Workflow

- Wait for task `y418mzx` on the `FoundationModelsExtras` board. This package
  cannot build until that type is `public` on `main`.
- `/tdd` does not apply. This task adds no behavior. It removes a duplicate.
  `ShellRunnerTests` is the existing test that must stay green.