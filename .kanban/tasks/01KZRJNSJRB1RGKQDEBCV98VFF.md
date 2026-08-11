---
assignees:
- claude-code
depends_on:
- 01KZRJPJRK8SP9329DREV0ZCA7
position_column: todo
position_ordinal: '8180'
title: 'runCode always backgrounds: remove waiting from its schema entirely'
---
## The three rules this belongs to

| tool | rule |
|---|---|
| `searchTools` | blocks until done. No wait clock, no work clock, no limit. Only a real error reaches the model |
| `runCode` | always backgrounds, always hands back a token. Waiting is not an option it has |
| `wait` | blocks until that token finishes, or until a timeout **the caller passed** |

The only duration anywhere is the one the model passes to `wait`. Nothing races a clock to decide anything, so a turn has the same shape on a fast machine and a loaded one.

**The gated tests must drive streaming.** On `respond(to:)` none of this exists — it drains, so a backgrounded `runCode` is collected before the caller sees it, a `wait` has nothing left to wait for, and a blocking `searchTools` is indistinguishable from a detaching one. A suite on `respond` would pass while testing none of the three rules.


> more than 'waitseconds 0' get rid of waiting being an option for runCode -- runCode should always background. the model can decide to wait, or just let it run to completion

`runCode` is the backgrounder. It always hands back a token, so waiting is not one of its options — the concept comes **out of its schema**, not set to zero. A model that needs the result calls `wait`; a model that does not lets it run.

## Why one shape, always — the real reason

> clearly the 'returns if it was fast' is just too complicated for you

> and confuses qwen model too

**A tool with two return shapes is unlearnable.** Under "inline if fast, token if slow", the same call sometimes yields a value and sometimes an envelope, decided by a race the model cannot observe. It can never form a stable habit, so it thrashes — and the recorded runs are exactly that: 16 calls, then 5, then 3, alternating `searchTools` and `runCode` with no pattern, because each answer taught it something different from the last.

It is not only the model. Three gated runs were read as three different faults before the shape-variance itself turned out to be the fault; a reader has the same problem the model does.

One shape, every time, is therefore a correctness property rather than a simplification. It also happens to be deterministic — the same call behaves identically on a fast machine and a loaded one, so a scenario cannot pass or fail on timing — but that is the smaller benefit.

## Changes

- `RunCodeArguments`: remove `waitSeconds` and `timeout`, and their `@Guide` text. `code` alone remains. This is a source break on a `public` type — fine, the package has not shipped
- `MultiTool+Detachment.swift`: `detachmentClocks` returns a zero wait — `DetachConfiguration.waitSeconds`' own documentation defines `0` as detach-immediately. Keep answering the work clock, bounded by `configuration.executionTimeLimit`: a backgrounded snippet is exactly what needs a ceiling, since nothing is blocking on it to notice it ran away
- Decide and record whether `MultiTool` still conforms to `DetachmentParameterProviding` once nothing is read from arguments

## The five tests this breaks — contract changes, not regressions

Measured by making the change and running the suite. Two are behavioural and must be understood, not re-asserted:

- [ ] `RouterSessionMountTests.swift:60` — "runCode returns the same value through Router's session mount as it does direct". **Can never hold again**: through the mount `runCode` always returns a token. Rewrite as "the mount returns a token where direct returns the value" — a stronger claim than the one it replaces, and the one that now defines the mount
- [ ] `SuspendedContextTests.swift:66` — "waitSeconds crosses the envelope untouched, including the immediate-detach zero". Encodes the removed contract; goes with the property
- [ ] `SuspendedContextTests.swift:43` — asserts the stock wait clock is `nil`. Becomes: there is no stock wait clock to inherit, because every call detaches
- [ ] `SuspendedContextTests.swift:108` — "a snippet that elevates while its inner call is in flight settles into exactly one terminal event". **Behavioural**: its harness gate did not start when every call detached immediately. Find out why before touching the assertion — this one may be telling us something about the elevation path rather than about the test
- [ ] `SuspendedContextTests.swift:179` — "cancel(completionToken) on a suspended snippet tears its context down within the time limit". **Behavioural**, same caution

## Acceptance Criteria

- [ ] A test asserts the rendered `runCode` schema carries no `waitSeconds` and no `timeout`
- [ ] A test asserts `runCode` hands back a token rather than a value when mounted, and the same snippet returns its value when called directly — the two halves of the same rule
- [ ] The host work ceiling still bounds a runaway snippet with no model-facing clock present: existing watchdog coverage passes unchanged
- [ ] Both behavioural failures are explained on this card before their assertions change, and the explanation says whether the test or the code was wrong
- [ ] Ungated suite green #eventplan