---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m173keppedkh9j9b3y4hpvsj
  text: |-
    ### finish iteration 1 — stuck
    - The diagnosis in the description is wrong, and the correction changes what this task is. The failure is not local machine state. The Router removed a public symbol that this package calls.
    - `6f0b2a8 refactor(api): demote the mistakenly public Hosting plumbing to internal` changed `public enum ToolMounting` to `enum ToolMounting` in `Sources/FoundationModelsRouter/Hosting/ToolMounting.swift`. The symbol has a consumer outside that package: `Sources/FoundationModelsMultitool/Invocation/RunBinding.swift:148` calls `ToolMounting.makeWrapped(...)`. Five more sites name it in documentation comments: `Capabilities/Shell/Execute.swift:46`, `Capabilities/Shell/Execute.swift:112`, `Surface/APISurface.swift:61`, `MultiTool+Background.swift:8`, `Invocation/RunBinding.swift:110` and `Invocation/RunBinding.swift:157`.
    - Evidence: at `760ae89`, which `Package.resolved` pins, the file declares `public enum ToolMounting`. At `origin/main` of the Router, which is `b26ee0f`, it declares `enum ToolMounting`. `760ae89` is an ancestor of `b26ee0f`.
    - Thus the root build is not safe, it is only lucky. The pin is declared as `branch: "main"`, so the next `swift package update` takes `b26ee0f` and the ROOT package fails to build, and not only the nested `IntegrationTests` package. The edit link did not cause the failure. It read the newer Router code first and showed the break early.
    - The Router working copy holds no source edit now. Only board files are dirty there, and it is 4 commits ahead of `origin/main`.
    - Asked the `foundationmodelsrouter-46` session which way to go: make `ToolMounting.makeWrapped` public again, or name a supported API to call instead. This package cannot decide it, because the symbol belongs to the other package.
    - next: wait for that answer. Do not remove the edit link yet — removing it hides the break behind the stale pin and leaves the pin unable to move.
  timestamp: 2026-08-29T15:53:21.366439+00:00
position_column: todo
position_ordinal: '9980'
title: The nested IntegrationTests package builds against an edited Router working copy, and cannot compile
---
## What
`swift build --package-path IntegrationTests --build-tests` fails today:

```
Sources/FoundationModelsMultitool/Invocation/RunBinding.swift:148:27:
error: cannot find 'ToolMounting' in scope
```

The root package builds and tests clean. Only the nested package fails. The cause is local machine state, and not a file of this repository.

`IntegrationTests/.build/workspace-state.json` holds `FoundationModelsRouter` in the **edited** state:

```
{"name": "edited", "path": "/Users/wballard/github/swissarmyhammer/FoundationModelsRouter"}
```

`IntegrationTests/Packages/FoundationModelsRouter` is a symlink to that folder, made on 2026-08-26. Thus the nested package compiles the root library against the sibling **working copy** of Router, and not against the pinned remote revision. `IntegrationTests/Package.resolved` therefore holds no `foundationmodelsrouter` pin, and `IntegrationTests/.build/checkouts/` holds no Router checkout.

In that working copy, `Sources/FoundationModelsRouter/Hosting/ToolMounting.swift` declares `enum ToolMounting {` — internal, not `public` — so the root library cannot name it. The working copy also carries an uncommitted change to `Router.swift`, thus another session is at work in it now.

The root package resolves Router from the remote at revision `760ae89`, where the type is public, and every one of the 1312 unit tests passes.

`Package.swift` of this package records this failure mode for task `^ev0zca7`: "a published branch is a *snapshot*, and a working copy is whatever another session happens to have saved. Building against a working copy is how this package spent a morning failing on someone else's half-finished edit."

## Why this is its own task
The fix removes another session's edit link, and that session is at work in the Router folder now. Do not remove the link while that work is in flight.

## What to do
- Ask first whether the Router edit link is still wanted. If it is not, run `swift package --package-path IntegrationTests unedit FoundationModelsRouter`, then `swift package --package-path IntegrationTests resolve`.
- Build again: `swift build --package-path IntegrationTests --build-tests`.
- If the edit link is wanted, wait until the Router work lands on `main` and the type is public.

## Acceptance Criteria
- [ ] `swift build --package-path IntegrationTests --build-tests` completes with no error.
- [ ] `IntegrationTests/Package.resolved` holds a `foundationmodelsrouter` pin, or the person who owns the edit link says why the link stays.
- [ ] The gated suite runs: `swift test --package-path IntegrationTests --no-parallel`.

## Found by
Task `^tq2qzga`, the phase-4 exit, on 2026-08-28. That task changed no manifest and no source of the library, thus it did not cause this failure. #eventplan #phase-4 #eventplan-phase-4