---
assignees:
- claude-code
position_column: done
position_ordinal: fffffb80
title: 'FileWalker git ls-files reads stdout, then stderr, then waits: a large stderr deadlocks the walk'
---
Sources/FoundationModelsMultitool/Capabilities/Files/FileWalker.swift:142-153 (old) used Process, read stdout to the end, then stderr, then called waitUntilExit, on a cooperative pool thread. When git writes more than the pipe buffer (64 KiB) to stderr before it closes stdout, git and the walk wait on each other.

Fix: FileWalker.listedFiles(byRunning:arguments:in:) is async and uses Subprocess.run. It reads stdout, discards stderr, and waits for the exit through an event, not a blocking wait. collectFiles and walkAndFilter are async; GlobEngine, GrepEngine, Glob, Grep and RemoveDirectory await them. The behavior does not change: exit 0 gives the NUL-split list, other results give nil and the plain walk.

Tests: FileWalkerTests.aListingProgramThatFillsItsStandardErrorStillGivesItsListing (a /bin/sh child writes 128 KiB to stderr, then the list) and aListingProgramThatFailsGivesNoListing (exit 1 gives nil). Both pass on the new code.

No non-hanging check on the old code is possible: the old order deadlocks whenever the child must drain stderr before it closes stdout, and a child that does not do this passes the old code. Thus the big-stderr test was not in the RED run.

Part of the freeze card ^3ytqp5q. #bug