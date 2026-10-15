---
assignees:
- claude-code
position_column: done
position_ordinal: ffffe980
title: 'RunCodeToolTimeoutTests spinningSnippetEndsAtTheEngineClock: close on the throw path depends on the JSC cancel'
---
If the test throws before the engine clock ends the run, the close of the session waits until the cancel stops the JavaScriptCore loop. Make the throw path end the run in a fixed order (for example, advance the engine clock on every path before the close). The success path has no problem. #mail-step-5 #bad-test