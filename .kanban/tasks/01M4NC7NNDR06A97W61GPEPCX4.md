---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4nchmben2c5673t3feqaj9m
  text: |-
    ### test — green
    - evidence: `swift test --filter 'OutputBufferTests|OutputChunkStreamTests'` — 57 tests in 2 suites passed, no warnings in project sources.
    - next: commit, push to main, send the hash to the FoundationModelsACPAgent session.
  timestamp: 2026-10-11T11:46:06.318200+00:00
position_column: done
position_ordinal: ffffd780
title: Add per-stream arrivedByteCount to ShellRawOutput
---
Request from the FoundationModelsACPAgent session (their task ^39h13a1).

Problem: a host counts the offset of each stream from the live events (output bytes plus gap counts). When `truncated == true`, `ShellRawOutput.bytes.count` is not that offset, because `OutputBuffer` can cut an over-cap chunk and store a later chunk past the hole. `storedByteCount` covers the two streams, thus it is not a per-stream offset.

Change (additive only):
- Add `arrivedByteCount: Int` to `ShellRawOutput` and to `OutputBuffer.RawOutput`: the count of all bytes of THIS stream that `send` gave to the store, stored or not.
- `OutputBuffer` counts it per stream, under the same lock as the store.
- Keep the old public init so that current callers compile.

Contract to document and test: for each stream, `arrivedByteCount` equals the sum of the `.output` byte counts plus the `.gap` dropped byte counts of that stream for all bytes given to the store before the snapshot, in the truncated case and in the untruncated case.

When done: send the commit hash to the FoundationModelsACPAgent session.