---
assignees:
- claude-code
depends_on:
- 01KZ6N0G06Q27NNK51PZFF76MX
position_column: todo
position_ordinal: '9380'
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
- [ ] Either: `settle(_:in:)`'s success-branch conversion failure interpolates the real `try jsValue(from:in:)` thrown error (matching the sync bridge's `"\(name): \(error)"` shape), OR the divergence is documented as an intentional, accepted exception with a comment explaining why.
- [ ] If code changes: a `JSCInterpreterTests` regression test pins the corrected message text for this failure mode.
- [ ] Full `swift test` green. #phase-1