---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: 'shell: collect execute output chunks into fewer progress events'
---
## Source

Request from the FoundationModelsACPAgent session (2026-10-07). Its tracking task is `^p8c7snm`. The Router part (merge progress rows in the journal) goes to the Router session. Do not implement this task until the user says so.

## Problem

One background `execute` operation posted about 13663 progress events. The transcript had 13663 rows and was 13 MB.

- Run: `bench/preds.code-context.jsonl` of 2026-10-05, instance `django__django-14667`. Operation `01M46DFX2Y3PSFQ8HH9EJA68FB` ran the full Django test suite (14878 tests) in the background.
- The Django runner writes one unbuffered "." to stderr for each test. 12846 rows hold only `stderr: .`.
- Transcript (read-only): `/Users/wballard/github/swissarmyhammer/FoundationModelsACPAgent/bench/preds.code-context.transcripts/django__django-14667/01M46CBB8BVBAE10G6TH73957Q/transcript.jsonl`.
- Cause: `Execute.reportOutput` (`Sources/FoundationModelsMultitool/Capabilities/Shell/Execute.swift`) posts one progress `OperationEvent` for each output chunk that is not only white space. Thus each test gives one event, and each event costs time in the session actor.

## Work

1. Collect the output chunks of a running `execute` operation for a fixed time (for example 1 s) or up to a fixed byte count, whichever comes first. Then post ONE progress event for the collection.
2. Post the last collection when the command ends, so that no output is lost from the progress stream.
3. The final output of the operation and its line store (`OutputBuffer`, `get lines`, `grep history`) must not change.
4. Use named constants for the time and the byte limit. Write a doc comment that gives the reason (this task).

## Tests

- A test command that writes 10000 single bytes gives a count of progress events that does not grow with the count of writes (for example, fewer than 100).
- The full output is still in the result and in the line store.
- A command that writes one line and ends still gives its progress event.

## Acceptance

- `swift build --build-tests` and `swift test` pass with no new warnings.
- The tests above pass. #shell