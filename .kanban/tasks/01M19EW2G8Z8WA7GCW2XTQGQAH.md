---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m1bzdsv90vnqe1pxhx5yh5pc
  text: |-
    ### implement — changed

    **1312 of 1316 pass, in 10.8 seconds.** The baseline before any of this was 1316 in about 24 seconds, thus the suite is faster than it was as well as free of the Router's internals.

    Commits: `7adb698`, `6d7c640`, `81e5c6c`, `bf0c815`.

    **Done.** This package names `ToolMounting` and `SessionMailbox` in no code. 23 test files moved to the Router's published API:

    - A `ToolContext` comes from a real session over a stub `ModelLoader`. Standing one up takes 6 ms, thus the stub is not a cost. A fixture keys off that context where it keyed off a mailbox it owned.
    - `.progress` and `.elicitation` events are read through a `TranscriptRecorder` this package supplies to `Router.init(recorder:)`. Operation events come off `partial.entry?.segments`: a structure segment that is not one fails to decode and drops, thus this package names neither `OperationEventSegment` nor its schema name.
    - A terminal event is read off `SessionEvent.runSettled`, **subscribed before the run settles**. That stream is live and has no replay, and `close()` finishes every open subscription.
    - A sweep is `RoutedSession.close()`.
    - An elicitation is answered through `RoutedSession.respond(elicitationId:response:)` and `complete(elicitationId:)`. The answerer watches the journal, because a consumer cannot inject a sink.

    **Three defects of my own were found and fixed, each by measuring rather than reading.**

    1. The stub router had no recorder, so nothing was journaled and about 24 assertions observed nothing at all. They failed only because they expected content; an assertion expecting emptiness would have stayed green over a broken read.
    2. `settledEvents` tested its deadline inside the `for await` body, which runs only when an event arrives. With no event it never returned. That is what made full runs reach the 1700-second timeout.
    3. A single-run test waited for two terminals and burned the whole deadline on every run.

    **Blocked: four assertions, one cause.**

    `MCPServerCallTests:400`, `HostAndEmitterTests:82`, `ShellSessionSweepTests:263`, `SuspendedContextTests:138`.

    `ToolContext.mount` re-stamps twice — the run's context stamps the run's token, then `MountedRunUpstreamSink` stamps the mounting context's token over it. Measured: a scripted run's own token `01M1BYNARGPQG5SKHKG0MRYQHA` appeared on neither its `.progress` nor its `.completed` event; the outer token `01M1BYNARFGAGYBN42VDH26D5D` appeared on both. The old fixtures passed a sink straight to `ToolMounting.makeWrapped`, which never applied the second stamp.

    The Router owns this. Its session called the hardcoded sink in `ToolContext.mount` a design regression it introduced, and its user chose the fix: `mount(_:op:as:postingTo:)`, a caller-supplied sink, plus making `OperationEventSink` public. Card `^bbbkas1` there.

    next: wait for that push, then take the four call sites onto `postingTo:` and drop the `FoundationModelsExtras` import from the two fixtures that took the conformance that way. Nothing else is open.
  timestamp: 2026-08-31T13:16:34.025059+00:00
- actor: claude-code
  id: 01m1c219yxw8ve403q22fgnes2
  text: |-
    ### implement — changed

    **1316 of 1316, in 6.5 seconds.** The baseline before this work was 1316 in about 24 seconds, thus the suite is faster as well as free of the Router's internals. Commit `81bc941`, on the Router's `main` at `5a8075b`.

    Every acceptance criterion is met. This package names `ToolMounting` and `SessionMailbox` in no code, and constructs no `ToolContext`.

    The four assertions that were blocked now supply their own sink through `ToolContext.mount(_:op:as:postingTo:)`, which the Router published after this package showed that its facade had removed a capability `ToolMounting.makeWrapped` allowed. `MCPServerCallTests:400` is the proof: two concurrent calls on one engine, each carrying its own `completionToken`, distinguishable. It could not be written at all under the re-stamping mount.

    Validated on the Router's branch at `d576a72` before it merged, then again on `main`. The temporary pin is removed.

    **One finding was reported to the Router rather than worked around.** The terminal of a run swept by `close()` does not reach the mounted run's caller-supplied sink; it reaches the journal, because the sweep is the mailbox acting and not the run posting. Measured: after `close()`, the sink held `[.progress]` and the journal held `[.completed]`, both on the run's own token `01M1C1R4H4VWK7MJTKYVP322JQ`, while the mounting run was `01M1C1R4H3G4WSP07XB1EG5V2H`. A second consequence went with it: the journal's correlation depends on which overload mounted the run, because a caller-supplied sink removes the re-stamping layer from the path. The Router recorded both as a documentation defect.

    next: nothing. The card is complete.
  timestamp: 2026-08-31T14:02:10.269533+00:00
position_column: done
position_ordinal: ffa580
title: Mount inner tools.* calls through ToolContext.mount instead of ToolMounting.makeWrapped
---
## What

The Router gives a new public entry point, `ToolContext.mount(_:op:as:)`, in
commit `799c308` "feat(hosting): add a public mount entry point to ToolContext".
It replaces the call to `ToolMounting.makeWrapped`, which the Router made
internal in `6f0b2a8`.

```swift
extension ToolContext {
    public func mount<T: Tool>(
        _ tool: T,
        op: String? = nil,
        as configuration: ToolMount = .synchronous
    ) -> any Tool<T.Arguments, T.Output>
}
```

It calls `makeWrapped(tool:inheriting:...)` with itself, thus it keeps all
seven behaviours this package needs: mount arbitration where the tool's own
`BackgroundTool.mount` wins over the `as:` argument, decorator dispatch by
output type, the completion token, the `ToolContext.$current` binding, the
event funnel, the journal records, and cancellation with the clock of the
mount.

**This task cannot start before the Router pushes `799c308`.** The CI of this
package resolves the Router again on each run and takes the head of the `main`
branch. The local checkout is stale at `760ae89`.

## Why this is necessary

The `main` branch of this package is red now. CI run 33261362318 gives:

```
RunBinding.swift:184:29: error: cannot find type 'OperationEventSink' in scope
RunBinding.swift:148:27: error: cannot find 'ToolMounting' in scope
```

Commit `8ee74ce` corrects the first error. Only this task corrects the second.

## What to do

**Site 1 — `Sources/FoundationModelsMultitool/Invocation/RunBinding.swift`.**
The body of `invoke(_:arguments:journalOp:)` becomes two lines inside the
span:

```swift
let engine = context.mount(tool, op: journalOp, as: innerMount)
return try await engine.call(arguments: arguments)
```

- Delete the `sink:` argument. The Router supplies its own private
  `MountedRunUpstreamSink`, which forwards through `context.post(_:)`.
- Delete `AmbientUpstreamSink`. Its semantics are the same as the sink the
  Router now supplies, thus no package outside the Router writes that type
  again. Keep what its documentation comment teaches about correlation: move
  the part that is still true to `invoke`.
- Delete the `guard let engine = mounted as? ...` and its unreachable branch.
  The return type is already `any Tool<T.Arguments, T.Output>`.
- Delete `import FoundationModelsExtras` from this file, which `8ee74ce`
  added. `OperationEventSink` and `OperationEvent` are not named in this file
  after `AmbientUpstreamSink` goes. Do not delete it from the other files.
  `OperationEvent` stays in use at `Invocation/SandboxNoticeOutbox.swift:35`,
  `Capabilities/Shell/Execute.swift:414` and
  `MultiTool+SandboxGlobals.swift:521`.

**Site 2 — `Tests/FoundationModelsMultitoolTests/Fixtures/ShellRunPlaneFixtures.swift:37`.**
`ShellRunPlane.mounted(_:inheriting:)` mounts an `Execute` verb the same way.
`Execute` has `Arguments == ExecuteArguments` and `Output == String`, thus the
return type of `mount` is already the declared return type. The helper stops
needing `#require`, stops needing the cast, and stops being `throws`. Correct
the callers that write `try`.

Keep that fixture. It proves mount arbitration still works from outside the
Router: it gives `RunBinding.innerCallMount`, and the verb's own `mount` must
still win and reach the background.

## Acceptance Criteria

- [x] `RunBinding.invoke` mounts through `context.mount`, and this package
      names `ToolMounting` nowhere. Verified: no code hit in `Sources` or
      `Tests`.
- [x] `AmbientUpstreamSink` is deleted, and nothing names it. One stale doc
      comment in `RegisteredJournalOpTests.swift` outlived the type and was
      corrected; its reasoning still holds, because the sink
      `ToolContext.mount` supplies also implements `post(event:)` alone.
- [x] `RunBinding.swift` does not import `FoundationModelsExtras`, and the
      three other files that use `OperationEvent` still build.
- [x] `swift build` gives no error and no new warning. The one warning is
      the pre-existing `mlx-swift` build-manifest warning, from a third-party
      package and not from this one.
- [ ] CI of `main` is green. **NOT VERIFIED.** The work is committed but not
      pushed, thus no CI run has judged it. This is the one criterion this
      card cannot claim.

## Tests

- [x] `Tests/FoundationModelsMultitoolTests/RunBindingTests.swift` passes with
      no change to what it asserts.
- [x] The `ShellRunPlane` fixture keeps proving that a verb which declares
      `BackgroundTool.mount` reaches the background although the call site
      gives `runToCompletion`.
- [x] `swift test` passes with 1316 tests or more, 0 failures, 0 skipped.
      Measured: **1316 of 1316, 0 failures, 0 skipped, 6.5 seconds**, against
      the Router's `main` at `5a8075b`.

## How the work differed from this plan

The plan covered two call sites. The real work covered 23 test files, because
`ToolMounting` was not the only symbol the Router had demoted: `SessionMailbox`,
the `OperationEventSink` typealias, `MergedTranscript`, `OperationEventSegment`
and `RoutedLLM.resolution` went with it.

Two things the plan could not have known:

1. A fixture cannot own a `SessionMailbox` any more, so it owns a session over
   a stub `ModelLoader` and keys off the `ToolContext` that session binds.
2. `ToolContext.mount` re-stamps every event onto the mounting run, so four
   assertions about per-run correlation became inexpressible. The Router called
   that a regression its facade introduced, and published
   `mount(_:op:as:postingTo:)` to correct it. Those four now supply their own
   sink.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #eventplan