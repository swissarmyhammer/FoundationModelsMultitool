---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m53w42xdnb7f9gad4hzayxpw
  text: 'Correction to the description: "or a before the wait" means "or a `#require` check before the wait". The board read the word as a tag, and the untag removed it from the text.'
  timestamp: 2026-10-17T02:47:41.741920+00:00
depends_on:
- 01M53W36NJG9FFA2XVH7W0EBQ7
position_column: todo
position_ordinal: '8e80'
title: 'T1 group 7: the waits and fixture leaks in IntegrationTests'
---
Split from ^nvxckvr (test rule T1). The list (about 24 cases in IntegrationTests/Tests) is in the comments of ^nvxckvr.

Rule T1: each wait in a test must also end on the failure event, or the test must fail before it waits. Fixtures close also when the test body throws.

Do: fix each case with an existing second event (the call ends, the transport closes, the child process exits, the stream finishes), or a before the wait, and awaited teardown on both paths. A test-only hook in a test helper is permitted. Do not change production code only to add a test hook: bring such a case to the owner. A wait with no existing second event goes on the exception-list card, with file:line and the reason.

Build IntegrationTests with `swift build --build-tests` one time; do not run the integration tests locally (they need real dependencies); CI runs them. No .timeLimit, sleep, poll or retry. Do not delete a test. #elicitation-fixes #t1