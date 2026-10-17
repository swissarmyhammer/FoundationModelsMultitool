---
assignees:
- claude-code
position_column: todo
position_ordinal: 8c80
title: Decline an MCP server URL-mode question whose url is not an absolute http or https URL
---
Found on ^c9nevn0 (group D (a)). The MCP server URL-mode path in MCPServer+Elicitation.swift checks only `URL(string: url.url)` and declines with invalidURLReason only when that gives nil. Thus a server request with url "foo" or "javascript:x" goes on to the host.

Do: use the same rule as the elicit() url check (Fetch.httpURL(_:): an absolute http or https URL with a host) for the server URL-mode request, and decline with invalidURLReason on `_meta.reason` when the URL does not obey it.

The fix starts with a fixed-order test that fails on the current code (RED): a scripted MCP server sends a URL-mode question with "foo" and with "javascript:x"; the result on the wire is a decline with invalidURLReason, and the host gets no request. Rule T1. No time limit, sleep, poll or retry. One full run. #elicitation-fixes