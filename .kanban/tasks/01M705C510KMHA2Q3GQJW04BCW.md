---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m7071109y0xq7tn9xp4219pz
  text: |-
    Part 1 fixed in Multitool: Execute posts a heartbeat progress event every 30 s while a command lives, which resets the no-progress window of the runCode that awaits it.
    Part 2 (13964 coder seq 4357-4366) is not in Multitool. The runCode went to the background at 18:19:53 and timed out at 18:21:53, while the 27B model was still writing its turn. The turn committed at 18:23:40 and ended with "Waiting on … (01M6Y66SA9…)". The sub-agent session then ended, although the run had already ended. The terminal result reached the transcript but was never given to the model as a follow-up turn. Router/ACPAgent: a sub-agent that ends with a pending-run status must get the mail of a run that already ended (or that ends later) before the session closes.
  timestamp: 2026-11-09T13:12:41.737532+00:00
position_column: done
position_ordinal: fffffff080
title: 'H: no-progress timeout must not stop a silent live test run; a pending command that ends must reach the model'
---
dotask24 13964 coder seq 4000, 14016 seq 4945: "runCode timed out after 120.0 seconds with no progress" exitCode -1 on full Django suite. 13964 coder seq 4357-4366 never saw that result. Investigate both. #forgive