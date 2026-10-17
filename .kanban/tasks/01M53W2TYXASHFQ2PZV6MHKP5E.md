---
assignees:
- claude-code
depends_on:
- 01M53W296FG93NMJT89T9DC8NB
position_column: todo
position_ordinal: '9080'
title: 'T1 group 2: MCP test fixtures — servers that are never disconnected'
---
Split from ^nvxckvr (test rule T1). The list (most of the about 230 cases in the MCP test files other than MCPElicitationTests) is in the comments of ^nvxckvr.

Rule T1: fixtures close also when the test body throws.

Do: each MCP test that connects a server disconnects it on both paths, awaited. Use the shared awaited helper (withConnection(of:_:) / ensuring, from ^etqn9dn and ^nvxckvr) or move it to a shared test support file. No `defer { Task { ... } }`. Keep the checks of each test the same.

No .timeLimit, sleep, poll or retry. Do not delete a test. Do not change production code only to add a test hook: bring such a case to the owner. One full run. #elicitation-fixes #t1