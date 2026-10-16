---
assignees:
- claude-code
position_column: done
position_ordinal: fffffa80
title: The kill test in StdioServerProcessTests changes SIGPIPE for the whole test process
---
StdioServerProcessTests.swift:433-434 (old) set signal(SIGPIPE, SIG_DFL) and set it back. This changed the signal disposition for all tests that ran at the same time.

Fix: the two signal lines are removed from killingTheChildExternallySurfacesAsAThrownErrorAndNotASignal. The doc comment now says why no change is necessary. The new test theRequestPipeOfTheChildRaisesNoSIGPIPE reads fcntl(fd, F_GETNOSIGPIPE) on the request descriptor of the child (StdioServerTransport.requestDescriptor) and expects 1. Thus the per-descriptor F_SETNOSIGPIPE of the product is the proof, not a process-wide change.

The new test also passes on the old product, because the product already set F_SETNOSIGPIPE. The hazard was the test itself. No fixed-order test can show a process-wide disposition change as a check.

Part of the freeze card ^3ytqp5q. #bad-test