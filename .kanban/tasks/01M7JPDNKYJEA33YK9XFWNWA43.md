---
assignees:
- claude-code
depends_on:
- 01M7JPDJGFNFN7NCC1RP0RJBX5
position_column: done
position_ordinal: ffffffff8680
title: 'MCP servers: the mcpServers tool for the model (D100)'
---
`MCPServersTool` (public struct over `OperationTool`, the same form as `SessionsTool`), with `graphQLEndpoints` = [MCPServersGraph] over the same registry.

Operations: `list mcp servers`, `show mcp server`, `add mcp server`, `edit mcp server`, `remove mcp server`, `enable mcp server`, `disable mcp server` (with the aliases "turn on" and "turn off" where the resolver allows them).

- The model never gives a secret value: it names the header or env keys that need a secret, and the tool calls `MCPServerSecrets.request` for each one. A result never holds a value.
- An add or an edit that changes a command, args or url runs a program or reaches a server that the user did not choose. The tool asks the user to approve it through an elicitation before it saves; a decline gives a corrective.
- Each answer is plain text; each error is a corrective text.

Depends on the endpoint task.