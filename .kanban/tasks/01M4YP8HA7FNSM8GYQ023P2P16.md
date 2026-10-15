---
assignees:
- claude-code
position_column: todo
position_ordinal: 8b80
title: ShellExecuteTests outputGoesOutWhenItsCollectionIntervalEnds can hang on a throw path
---
If a step throws before stop(), the async let waits on a shell gate that the test never opens. Thus the test does not end. The fault was there before the session close change. Open the gate on every path. #mail-step-5 #bad-test