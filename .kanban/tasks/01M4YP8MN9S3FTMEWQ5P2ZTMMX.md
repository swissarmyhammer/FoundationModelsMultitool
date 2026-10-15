---
assignees:
- claude-code
position_column: done
position_ordinal: ffffea80
title: ScriptedElicitationSink watch task can wait for all time after the close
---
The watch task of the test fixture ScriptedElicitationSink is not a session task, so close() does not end it. After the close, it can wait for all time. Make the watch task end when the session closes, or when the test ends. #mail-step-5 #bad-test