---
assignees:
- claude-code
position_column: done
position_ordinal: fffffc80
title: Test helpers call waitUntilExit with pipes on a cooperative pool thread
---
Three test helpers started a Process, then called waitUntilExit (and read pipes) from async test code:
- [x] TestSupport.swift:195-201 runGit: pipes that nothing read, then waitUntilExit.
- [x] ShellRunnerTests.swift:224-232 processIDs(matching:): readDataToEndOfFile, then waitUntilExit.
- [x] OutputBufferTests.swift:160-169 catFixtureChunks: reads, then waitUntilExit.

Fix: each helper is async and uses Subprocess.run (the pattern of ShellRunner and SandboxPreflight). Output that the test does not use is discarded. The exit comes through an event. Each caller now awaits the helper (FilesGlobTests, FilesGrepTests, FilesExcludePatternsTests, GitCommitTests, LibGit2CommitDetailTests, FileWalkerTests, ShellRunnerTests, OutputBufferTests).

No fixed-order check shows these hazards on the old code. The existing tests that use the helpers are the proof that the behavior did not change.

Part of the freeze card ^3ytqp5q. #bad-test