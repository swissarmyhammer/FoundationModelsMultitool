---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01kz9y221fnq5xtembfjdv2vce
  text: |-
    ### implement — in progress

    TDD: added new tests under `// MARK: - Proxy trap on pending results` in Tests/FoundationModelsMultitoolTests/JSCInterpreterTests.swift (trap message content, then/catch/finally exemption, `.catch` through the proxy, `Promise.all` over two proxied results, rendered repair text via `ResultRenderer`). Confirmed RED first (2 of the 6 new tests failed as expected pre-implementation; the other 4 passed trivially since pre-existing await/then/catch/Promise.all behavior was already correct and unaffected by the trap not yet existing).

    Implemented in Sources/FoundationModelsMultitool/Interpreter/JSCInterpreter.swift:
    - New `wrapInForgotAwaitProxy(_:callName:in:)`: wraps the bridge's `thenable` in a JS `Proxy`. `get` trap: `then`/`Self.internalPromisePropertyName` forwarded unwrapped (required — both are non-configurable/non-writable own properties of the target, and ECMA-262's `[[Get]]` Proxy invariant requires `SameValue`; a bound/wrapped copy trips a real JSC `TypeError`, confirmed empirically while iterating). `catch`/`finally` forwarded *bound to the underlying `thenable`* via `Function.prototype.bind` (safe — inherited from `Promise.prototype`, not own properties, so the invariant doesn't apply) — necessary because JSC's real `Promise.prototype.finally` calls `SpeciesConstructor(this, ...)` which reads `this.constructor`, and without the bind `this` would be the Proxy, hitting the trap and throwing on `"constructor"`. Everything else throws a JS `Error` naming the call and the property with a "did you forget `await`?" hint.
    - `install(asyncHostFunction:into:registry:)` refactored into itself (now a flat `do`/`try`/`catch`) plus two new extracted helpers `makeTrackedPromise` and `makeThenable`, plus a hoisted `defineHiddenProperty` helper — triggered by a self-review cognitive-complexity finding after wiring in the proxy call.

    Self-review (`review working`) loop: first pass found 2 duplication findings (both pre-existing code paths I'd touched — the two `defineProperty.call` sites and the two `settle` reject-with-error sites) — fixed both via `defineHiddenProperty`/`rejectWithMessage` helpers. Second pass found 1 cognitive-complexity finding on `install(asyncHostFunction:into:registry:)` — fixed via the `makeTrackedPromise`/`makeThenable` extraction. Third+ passes clean (ran 5 times total for stability; one run surfaced a duplication finding in `WatchdogState` — pre-existing code with zero overlap with this diff, at line numbers unchanged since before this task's edits — did not reproduce on immediate re-run, treated as reviewer noise unrelated to this diff, out of scope per "no unrelated refactors while implementing").

    `swift build`: clean, only the known pre-existing mlx-swift build-manifest warning. `swift test`: 189 tests passed, 6 gated MULTITOOL_INTEGRATION tests skipped (not run, per standing guidance not to chain multi-minute gated runs). Dispatched a `double-check` sub-agent to adversarially verify the Proxy-invariant reasoning, the refactor's message-text preservation, and test quality before reporting back.

    step: implement
    outcome: changed
    evidence: 2 files — Sources/FoundationModelsMultitool/Interpreter/JSCInterpreter.swift, Tests/FoundationModelsMultitoolTests/JSCInterpreterTests.swift
    task: ^wpq0q6d
  timestamp: 2026-08-05T21:42:48.111916+00:00
- actor: claude-code
  id: 01kz9zy12f4rcr7hcsqf5xa2k9
  text: |-
    ### double-check — REVISE, acted on fully

    The adversarial `double-check` agent independently re-derived the Proxy-invariant reasoning against real JSC (not the doc comments), ran `swift build`/`swift test --filter JSCInterpreterTests` itself, and confirmed the refactor preserved every pre-existing error message byte-for-byte. It returned REVISE with 4 findings, all real, none a true conflict — fixed all four:

    1. **Process-crash bug** in `installConsole`: `.map { $0.isUndefined ? "undefined" : $0.toString() }` force-unwraps `JSValue.toString()`'s `String!` result, which the agent proved (via an isolated JSC repro) returns `nil` — crashing the whole host process — exactly when the argument's conversion hits this new trap (i.e. `console.log(someTool())`, one of the most common things a model does when it forgets `await`). Fixed: `$0.toString() ?? "[unrepresentable value]"`. Added a regression test (`consoleLogOnPendingResultThrowsForgotAwaitErrorInsteadOfCrashing`) asserting a thrown `InterpreterError`, not a crash.
    2. **Doc comment said the opposite of what the code does**: the `install(asyncHostFunction:into:registry:)` doc comment claimed `then` is returned *bound* — backwards; it's `catch`/`finally` that are bound, `then` is forwarded unwrapped (required by the `[[Get]]` invariant). Corrected.
    3. **Doc comment overclaimed the trap's blind spot**: claimed arithmetic (not just truthiness) never reaches a `get`. The agent proved otherwise against JSC — `r + 1`, `` `${r}` ``, `r == x`, destructuring all reach `ToPrimitive` → `Get(@@toPrimitive)`, which this trap does catch, incidentally. Corrected the doc, and added a regression test (`arithmeticCoercionOfPendingResultThrowsForgotAwaitError`) proving it's caught with a proper "did you forget await" message, not silently mishandled.
    4. **Symbol-keyed property access produced an unnamed error**: `propertyName ?? "a non-string property"` doesn't name the property, and Symbol keys (`@@toPrimitive` — reached by every coercion path above) are common, not a rare corner. Added `describeNonExemptProperty`, which renders a `Symbol` key via the global `String` function (`SymbolDescriptiveString`, e.g. `"Symbol(Symbol.toPrimitive)"`) — safe, unlike `JSValue.toString()`, which throws for a `Symbol` per spec.

    Re-ran the self-review loop after these fixes: round 1 found 2 Swift-naming findings (unlabeled first parameters on `defineHiddenProperty`/`rejectWithMessage`, both introduced during the earlier complexity-driven refactor) — fixed by labeling both. Three consecutive clean `review working` runs after that.

    `swift build`: clean, only the known pre-existing mlx-swift warning. `swift test`: 191 tests passed (42 in `JSCInterpreterTests`, including 7 for this task — the original 5 plus the 2 regression tests this double-check pass added), 6 gated `MULTITOOL_INTEGRATION` tests skipped as expected. Checked off every Acceptance Criteria and Tests checkbox in the description.

    step: implement
    outcome: changed
    evidence: 2 files — Sources/FoundationModelsMultitool/Interpreter/JSCInterpreter.swift, Tests/FoundationModelsMultitoolTests/JSCInterpreterTests.swift
    task: ^wpq0q6d
  timestamp: 2026-08-05T22:15:33.199946+00:00
depends_on:
- 01KZ6MYJSSSF41HXMC2YAHBKG5
position_column: doing
position_ordinal: '8180'
title: '[MultiTool] Proxy trap on pending results'
---
Repo: this repo. Basis: eventplan.md §"Async Javascript", "A forgotten `await` has four shapes" — this is the third shape's catch. Split from the promise-pump task by the plan double-check (independent, purely additive ergonomics).

## What
In `Sources/FoundationModelsMultitool/Interpreter/JSCInterpreter.swift`: wrap each promise the bridge creates in a JS `Proxy` whose `get` trap throws a precise, model-repairable error for every property except `then`, `catch`, and `finally`. The error names the call that produced the promise and the property that was accessed, and asks "did you forget `await`?". This catches property access on a pending result; the remaining uncatchable shape (truthiness/arithmetic on a promise) stays covered only by description text and the repair loop, as the plan records.

The proxied promise must still behave as a first-class thenable: `await`, `Promise.all`, `.then/.catch/.finally` chains, and the settle-before-return registry all keep working through the proxy.

## Acceptance Criteria
- [x] `const r = tools.x.y(...); return r.value` (no await) throws an error naming `tools.x.y` and `value` and containing the "did you forget `await`?" hint
- [x] `await`ing a proxied promise, `Promise.all` over proxied promises, and `.then` chains all work unchanged
- [x] The error is an `InterpreterError` rendered through the standard repair-loop text (`ResultRenderer` "Fix the snippet and call runCode again.")
- [x] `swift test` green

## Tests
- [x] New cases in `Tests/FoundationModelsMultitoolTests/JSCInterpreterTests.swift`: trap message content (call name, property name, hint); `then`/`catch`/`finally` exemptions; proxied-promise thenable behavior through `Promise.all`; rendered repair text
- [x] `swift test --filter JSCInterpreter` green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #phase-1