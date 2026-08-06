---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01kzbd405atp45ebh8sederzaf
  text: |-
    Picked up. Research notes:

    - Code has moved since the description was written: ^wpq0q6d routed both of `settle(_:in:)`'s failure paths through a shared private `rejectWithMessage(message:reject:in:)`. The success branch still uses `try?` + the hardcoded `"\(name): could not convert the result to JSON."`.
    - Taking resolution option 1 (fix, not document): `do`/`catch` around `try jsValue(from:in:)` and interpolate the real error, matching `install(hostFunction:into:)`'s `"\(name): \(error)"`.
    - Reachability probe (scratchpad Swift program against JavaScriptCore, 8 sabotage variants): `jsValue(from:in:)`'s only throw sites today are **provably unreachable**. `JSONEncoder().encode(InterpreterValue)` never throws (non-finite `.number` degrades to null; every other case is JSON-safe), and the `guard let` chain can never fail — `-[JSValue objectForKeyedSubscript:]` and `-[JSValue callWithArguments:]` return an *undefined* `JSValue`, never `nil`, even when the receiver is `undefined`/`null`/a non-function (they route through `valueFromNotifyException`). Measured: with `delete JSON.parse`, `JSON.parse = undefined`, `delete globalThis.JSON`, `JSON = null`, `JSON = 42`, or a throwing `JSON.parse`, `parse.call(...)` came back non-nil-but-undefined every time.
    - Consequence: with `JSON.parse` sabotaged, the bridge silently **resolves the promise with `undefined`** instead of rejecting. So the fix alone is untestable, and the branch is not merely "close to unreachable" — it is unreachable.
    - Making it honestly testable needs one more (correctness) change: add `!parsed.isUndefined` to `jsValue(from:in:)`'s guard, exactly mirroring its inverse `jsonValue(of:in:)`, which already guards `!stringified.isUndefined` on its own `stringify.call(...)` result. `JSON.parse` of the output of `JSONEncoder` never legitimately returns `undefined`, so no existing behaviour changes.
    - Test vehicle: a snippet that starts the async call, then replaces `JSON.parse` with a stub returning `undefined` (a *non-throwing* sabotage — the throwing variants notify a TypeError into the context, which `evaluate` captures and rethrows ahead of the rejection, hiding the message under test), then awaits and catches. Pins the exact text `weatherAsync: JSON.parse is unavailable.`
  timestamp: 2026-08-06T11:25:14.794233+00:00
- actor: claude-code
  id: 01kzbd8xbfwcb9zfv0c9hm3p28
  text: |-
    Implemented option 1 (fix, not document), TDD order — test first, watched it fail for the predicted reason (`result.returnValue → .string("unreachable")`: the promise **resolved with `undefined`** instead of rejecting), then fixed.

    Three edits in `Sources/FoundationModelsMultitool/Interpreter/JSCInterpreter.swift`:

    1. `settle(_:in:)` success branch — `try?` replaced with `do`/`catch` around `try jsValue(from:in:)`, rejecting via the shared `rejectWithMessage` with `"\(settlement.name): \(error)"`. Identical shape to `install(hostFunction:into:)`'s `"\(hostFunction.name): \(error)"`. Doc comment extended to state that both failure modes now carry that shape.
    2. `jsValue(from:in:)` — added `!parsed.isUndefined` to the existing guard. Required, not incidental: without it the branch under test is unreachable *and* the failure is silent. `-[JSValue objectForKeyedSubscript:]`/`-[JSValue callWithArguments:]` never return `nil` (they route a failed `JSValueToObject` through `valueFromNotifyException`, which yields an *undefined* `JSValue`), so the three `let` bindings can never fail and a replaced `JSON.parse` quietly converted every result to `undefined`. This mirrors the inverse function `jsonValue(of:in:)`, which already guards `!stringified.isUndefined` on its own `stringify.call(...)`. `JSON.parse` never returns `undefined` for `JSONEncoder` output, so no existing behaviour changes; the "JSON.parse is unavailable." message text is unchanged.
    3. `rejectWithMessage` doc — "a non-JSON-encodable success value" reworded to "a success value that could not be converted back into the sandbox", which is what the path actually means now.

    Regression test `asyncResultConversionFailureRejectsWithUnderlyingError` in `Tests/FoundationModelsMultitoolTests/JSCInterpreterTests.swift` drives it end to end through the public `run`: the snippet starts `weatherAsync()`, replaces `JSON.parse` with a stub returning `undefined`, then awaits and catches. Pins the full text `weatherAsync: JSON.parse is unavailable.` — no `contains`, no prefix match. It is a genuine conversion failure, not a fake: `jsValue(from:in:)` really throws, through the same path the sync bridge would.

    Blast radius: `jsValue(from:in:)` has exactly two call sites (`install(hostFunction:into:)` line 540 and `settle(_:in:)`), both already inside `do`/`catch`; the sync bridge inherits the same corrected behaviour.

    Not done: the two throw sites are still unreachable from an `InterpreterValue` alone — `JSONEncoder().encode` cannot fail for any case of that enum. Only a snippet sabotaging the sandbox's `JSON` surface reaches them, which is exactly what the test does.
  timestamp: 2026-08-06T11:27:55.759240+00:00
- actor: claude-code
  id: 01kzbd93etwq7dn7p0ebq6yk3j
  text: |-
    ### implement — changed
    - evidence: 2 files — Sources/FoundationModelsMultitool/Interpreter/JSCInterpreter.swift, Tests/FoundationModelsMultitoolTests/JSCInterpreterTests.swift; `swift build` clean (only the known pre-existing mlx-swift "missing creator for mutated node" manifest warning); `swift test` 194 tests in 18 suites passed, 0 failures, 0 warnings (gated MULTITOOL_INTEGRATION suites skipped as always)
    - next: ready for /review
  timestamp: 2026-08-06T11:28:02.010648+00:00
depends_on:
- 01KZ6N0G06Q27NNK51PZFF76MX
position_column: doing
position_ordinal: '80'
title: '[JSCInterpreter] Async host-function JSON-conversion-failure rejection loses the underlying error text'
---
Discovered while implementing ^zff76mx ("[MultiTool] Remove the blocking bridge; tools.* return promises"), via an adversarial double-check review, while verifying that async-bridge error messages are byte-for-byte identical to the retired v1 sync bridge's.

## What
In `Sources/FoundationModelsMultitool/Interpreter/JSCInterpreter.swift`:

- The sync bridge, `install(hostFunction:into:)`, catches *any* failure uniformly — including a `jsValue(from:in:)` conversion failure on the host function's own successful result — and reports `"\(hostFunction.name): \(error)"`, interpolating the real underlying error.
- The async bridge's `settle(_:in:)` success branch instead hardcodes a generic message when the same conversion fails:

```swift
case .success(let value):
    guard let jsResult = try? jsValue(from: value, in: context) else {
        let reason = JSValue(
            newErrorFromMessage: "\(settlement.name): could not convert the result to JSON.",
            in: context
        )
        settlement.reject.call(withArguments: [reason as Any])
        return
    }
    ...
```

So for this one failure mode (an async host function's successful `InterpreterValue` result failing to convert to JSON), the rejection message text diverges from what the old sync bridge would have produced for the equivalent failure — the real underlying error text is discarded in favor of a fixed string.

In practice this path is close to unreachable (every `InterpreterValue` an `Interpreter` conformer produces is already JSON-safe by construction — see `InterpreterValue.encode`'s non-finite-number degradation, and `ResultRenderer.serialize`'s own doc comment making the same "unreachable in practice, kept as a defensive fallback" argument), but the divergence is real and should either be fixed or the "identical message text" claim scoped to exclude it.

## Acceptance Criteria
- [x] Either: `settle(_:in:)`'s success-branch conversion failure interpolates the real `try jsValue(from:in:)` thrown error (matching the sync bridge's `"\(name): \(error)"` shape), OR the divergence is documented as an intentional, accepted exception with a comment explaining why.
- [x] If code changes: a `JSCInterpreterTests` regression test pins the corrected message text for this failure mode.
- [x] Full `swift test` green. #phase-1