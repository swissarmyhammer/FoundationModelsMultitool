---
assignees:
- claude-code
depends_on:
- 01KZ6MYJSSSF41HXMC2YAHBKG5
position_column: todo
position_ordinal: '9180'
title: '[MultiTool] Proxy trap on pending results'
---
Repo: this repo. Basis: eventplan.md §"Async Javascript", "A forgotten `await` has four shapes" — this is the third shape's catch. Split from the promise-pump task by the plan double-check (independent, purely additive ergonomics).

## What
In `Sources/FoundationModelsMultitool/Interpreter/JSCInterpreter.swift`: wrap each promise the bridge creates in a JS `Proxy` whose `get` trap throws a precise, model-repairable error for every property except `then`, `catch`, and `finally`. The error names the call that produced the promise and the property that was accessed, and asks "did you forget `await`?". This catches property access on a pending result; the remaining uncatchable shape (truthiness/arithmetic on a promise) stays covered only by description text and the repair loop, as the plan records.

The proxied promise must still behave as a first-class thenable: `await`, `Promise.all`, `.then/.catch/.finally` chains, and the settle-before-return registry all keep working through the proxy.

## Acceptance Criteria
- [ ] `const r = tools.x.y(...); return r.value` (no await) throws an error naming `tools.x.y` and `value` and containing the "did you forget `await`?" hint
- [ ] `await`ing a proxied promise, `Promise.all` over proxied promises, and `.then` chains all work unchanged
- [ ] The error is an `InterpreterError` rendered through the standard repair-loop text (`ResultRenderer` "Fix the snippet and call runCode again.")
- [ ] `swift test` green

## Tests
- [ ] New cases in `Tests/FoundationModelsMultitoolTests/JSCInterpreterTests.swift`: trap message content (call name, property name, hint); `then`/`catch`/`finally` exemptions; proxied-promise thenable behavior through `Promise.all`; rendered repair text
- [ ] `swift test --filter JSCInterpreter` green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #phase-1