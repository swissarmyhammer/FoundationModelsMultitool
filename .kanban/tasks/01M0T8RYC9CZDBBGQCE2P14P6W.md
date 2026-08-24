---
position_column: todo
position_ordinal: '9480'
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