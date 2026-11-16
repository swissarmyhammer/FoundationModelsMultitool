---
assignees:
- claude-code
position_column: done
position_ordinal: ffffffff8380
title: 'MCP servers: item registry over a host storage port'
---
Request of testudoapp-75 (the user: "C R U D each marketplace and MCP server, not rewrite a whole list"). Multitool owns the MCP capability, so it gives the item API. Multitool does not own config.yaml.

Make, in Capabilities/MCP:
- `MCPServerEntry` (public, Codable, Equatable, Sendable): `name`, `transport` (`.stdio(command:args:env:)` or `.http(url:headers:)`), `enabled`.
- `MCPServerStorage` port (public protocol): `loadServers() async throws -> [MCPServerEntry]` and `saveServers(_:) async throws`. The host backs it (ACPAgent: its user settings layer). `InMemoryMCPServerStorage` for tests.
- `MCPServerRegistry` (public actor) over the port: `list()`, `server(named:)`, `add(_:)`, `update(named:with:)` (rename, command, args, env, url, headers, enabled), `remove(named:)`, `setEnabled(_:named:)`, `changes() -> AsyncStream<MCPServerChange>` (added, updated with the old name, removed). Each change reads the storage again, changes one item, and saves, so a change by another writer is not lost.
- Validation and clear errors (`MCPServerRegistryError`): duplicate name, unknown server, invalid name (the noun rules of the registry), a reserved name that the host gives (for example `files`, `shell`), a relative stdio command, a url that is not http or https, a header value that is not a `keychain:` reference (D101).

Tests (TDD, InMemoryMCPServerStorage): each operation, each error, a rename, the change events, and a second writer between two changes.