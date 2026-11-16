---
assignees:
- claude-code
depends_on:
- 01M7JPDAHVBEZTAPYAQTA3GEBF
position_column: todo
position_ordinal: '8180'
title: 'MCP servers: secrets through a host secret port, never in a result'
---
D101: the store holds only `keychain:<name>` references for secrets.

- `MCPServerSecrets` port (public protocol, the host supplies it): `store(_ value: String, server: String, key: MCPSecretKey) async throws -> String` gives the reference; `request(server: String, key: MCPSecretKey) async throws -> String?` asks the user for the value outside the transcript (a host form), stores it, and gives the reference, or nil for a decline. `MCPSecretKey`: a header name or an env name.
- The registry gets `add`/`update` forms that take secret values and write them through the port first; then only the references go into the entry and the storage.
- No secret value goes into an error text, a change event, a log record or a description.

Tests: a stub port records the values; the storage and each event hold only references; a decline gives a clear error. Depends on the registry task.