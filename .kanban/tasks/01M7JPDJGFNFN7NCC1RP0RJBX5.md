---
assignees:
- claude-code
depends_on:
- 01M7JPDE7V421HS48XQMHTYQ47
position_column: todo
position_ordinal: '8280'
title: 'MCP servers: the mcpServers GraphQL endpoint'
---
`MCPServersGraph` (GraphQLEndpoint, name `mcpServers`, version 1, scope server), over one `MCPServerRegistry`, in the same form as `SessionsGraph` (MT-10).

- Queries: `mcpServers: [MCPServer!]!`, `mcpServer(name: String!): MCPServer`, `cursor`.
- Mutations: `addMCPServer(input:)`, `updateMCPServer(input:)`, `removeMCPServer(input:)`, `setMCPServerEnabled(input:)`. A secret value in the input goes only through `MCPServerSecrets.store`; the result shows the reference.
- Subscription: `changes(after:)` with the alias `mcpServerChanges`.
- Type `MCPServer`: `name`, `transport` (STDIO or HTTP), `command`, `args`, `env` and `headers` as name and value pairs (the value of a secret is its `keychain:` reference), `url`, `enabled`.
- Viewer: a device of the user and the agent read and change; an external client reads and changes nothing (an MCP server runs a command on the Mac).
- The registry errors become coded errors (`DUPLICATE_NAME`, `NOT_FOUND`, `INVALID_INPUT`).
- A golden schema file.

Depends on the registry and secrets tasks.