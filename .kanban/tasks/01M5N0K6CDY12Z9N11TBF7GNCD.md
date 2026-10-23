---
assignees:
- claude-code
position_column: done
position_ordinal: ffffffc380
title: 'shell.execute: a relative workingDirectory resolves against the root, not the process cwd'
---
From SWE-bench run bench24-1023 (django__django-13447 seq 664-668). `workingDirectory: ".red-check-wt"` was refused as outside the roots although `<root>/.red-check-wt` exists: `ShellRunner.effectiveWorkingDirectory` passed the relative path through, and both the spawn and `resolvedSandboxDirectories` resolved it against the PROCESS cwd (the parent of the root in the acp-agent).

Fix: a relative `workingDirectory` resolves against `defaultWorkingDirectory` (the root; the same base as the default cwd), else the process cwd.

Test first: with the process cwd a parent of the root, a relative workingDirectory inside the root is accepted by the sandbox preflight and the command runs there.

#bug