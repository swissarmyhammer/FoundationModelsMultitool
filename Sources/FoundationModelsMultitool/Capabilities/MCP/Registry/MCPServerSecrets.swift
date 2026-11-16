// `MCPServerSecrets` — the port through which `MCPServerRegistry` puts a
// secret of an MCP server into the Keychain of the host (D101). The host
// supplies it: ACPAgent writes to its `SecretStore`.
//
// The store of the servers holds only `keychain:<name>` references. A secret
// value goes from a client (the app, through the `mcpServers` endpoint) or
// from the user (through the form of the host) to this port, and never into
// an entry, a change event, an error text, a log record or a tool result. The
// model never gives a secret value: it names the key, and the host asks the
// user.

import Foundation

/// The Keychain of the host, for the secrets of the MCP servers.
public protocol MCPServerSecrets: Sendable {
    /// Stores a secret value and gives its reference.
    ///
    /// - Parameters:
    ///   - value: The secret value.
    ///   - server: The name of the server.
    ///   - key: The header or the env variable of the secret.
    /// - Returns: The `keychain:<name>` reference. A host uses
    ///   ``MCPSecretKey/keychainReference(server:)``.
    /// - Throws: An error of the Keychain.
    func store(_ value: String, server: String, key: MCPSecretKey) async throws -> String

    /// Asks the user for a secret value outside the transcript, stores it,
    /// and gives its reference.
    ///
    /// - Parameters:
    ///   - server: The name of the server.
    ///   - key: The header or the env variable of the secret.
    /// - Returns: The `keychain:<name>` reference, or `nil` when the user
    ///   declines or the host cannot ask.
    /// - Throws: An error of the Keychain.
    func request(server: String, key: MCPSecretKey) async throws -> String?
}

extension MCPServerEntry {
    /// This server with a reference in place of each secret key.
    ///
    /// - Parameter references: The reference of each key.
    /// - Returns: The server with the references.
    /// - Throws: ``MCPServerRegistryError/conflictingTransport(server:)``
    ///   for a header of a stdio server or an env variable of an http server.
    func setting(references: [MCPSecretKey: String]) throws(MCPServerRegistryError) -> MCPServerEntry {
        var entry = self
        for (key, reference) in references.sorted(by: { $0.key.description < $1.key.description }) {
            switch (entry.transport, key) {
            case (.stdio(let command, let args, var env), .env(let variable)):
                env[variable] = reference
                entry.transport = .stdio(command: command, args: args, env: env)
            case (.http(let url, var headers), .header(let header)):
                headers[header] = reference
                entry.transport = .http(url: url, headers: headers)
            default:
                throw .conflictingTransport(server: name)
            }
        }
        return entry
    }

    /// The deterministic reference of each key, from the name scheme of
    /// ``MCPSecretKey/keychainReference(server:)``.
    ///
    /// - Parameter keys: The keys.
    /// - Returns: The reference of each key.
    func schemeReferences(of keys: some Sequence<MCPSecretKey>) -> [MCPSecretKey: String] {
        Dictionary(uniqueKeysWithValues: keys.map { ($0, $0.keychainReference(server: name)) })
    }
}

extension MCPServerRegistry {
    /// Adds a server, and first stores each secret value through the
    /// secret port. The entry, the storage and the change hold only the
    /// references.
    ///
    /// The registry checks the server with the references of the name scheme
    /// before it stores a value, so a refused server stores no secret.
    ///
    /// - Parameters:
    ///   - entry: The server.
    ///   - secrets: The secret value of each key.
    /// - Returns: The server, with the references.
    /// - Throws: ``MCPServerRegistryError`` for a refusal, the
    ///   `noSecretStore` refusal when a value comes and the host gave no
    ///   port, and each error of the port or the storage.
    @discardableResult
    public func add(_ entry: MCPServerEntry, secrets: [MCPSecretKey: String]) async throws -> MCPServerEntry {
        try await validate(try entry.setting(references: entry.schemeReferences(of: secrets.keys)))
        let references = try await storeSecrets(secrets, server: entry.name)
        return try await add(try entry.setting(references: references))
    }

    /// Changes one server, and first stores each secret value through the
    /// secret port. Each secret key goes into the headers or the env after
    /// the change, next to the keys that stay.
    ///
    /// - Parameters:
    ///   - name: The name of the server.
    ///   - update: The change.
    ///   - secrets: The secret value of each key.
    /// - Returns: The server after the change, with the references.
    /// - Throws: ``MCPServerRegistryError`` for a refusal, and each error of
    ///   the port or the storage.
    @discardableResult
    public func update(
        named name: String, with update: MCPServerUpdate, secrets: [MCPSecretKey: String]
    ) async throws -> MCPServerEntry {
        let newName = update.name ?? name
        let probe = try await changed(named: name, with: update)
        _ = try probe.setting(references: probe.schemeReferences(of: secrets.keys))
        let references = try await storeSecrets(secrets, server: newName)
        return try await self.update(named: name, with: update, references: references)
    }

    /// Asks the user for each secret through the secret port, for a change
    /// by the model. The model never sees a value.
    ///
    /// - Parameters:
    ///   - keys: The keys.
    ///   - server: The name of the server after the change.
    /// - Returns: The reference of each key.
    /// - Throws: ``MCPServerRegistryError/secretDeclined(server:key:)`` when
    ///   the user declines one, `noSecretStore` when the host gave no port,
    ///   and each error of the port.
    public func requestSecrets(_ keys: [MCPSecretKey], server: String) async throws -> [MCPSecretKey: String] {
        guard !keys.isEmpty else {
            return [:]
        }
        let port = try secretPort()
        var references: [MCPSecretKey: String] = [:]
        for key in keys {
            guard let reference = try await port.request(server: server, key: key) else {
                throw MCPServerRegistryError.secretDeclined(server: server, key: key)
            }
            references[key] = reference
        }
        return references
    }

    /// Stores each secret value through the port.
    ///
    /// - Parameters:
    ///   - secrets: The value of each key.
    ///   - server: The name of the server.
    /// - Returns: The reference of each key.
    /// - Throws: `noSecretStore` when a value comes and the host gave no
    ///   port, and each error of the port.
    private func storeSecrets(
        _ secrets: [MCPSecretKey: String], server: String
    ) async throws -> [MCPSecretKey: String] {
        guard !secrets.isEmpty else {
            return [:]
        }
        let port = try secretPort()
        var references: [MCPSecretKey: String] = [:]
        for (key, value) in secrets.sorted(by: { $0.key.description < $1.key.description }) {
            references[key] = try await port.store(value, server: server, key: key)
        }
        return references
    }

    /// The secret port of the host.
    ///
    /// - Returns: The port.
    /// - Throws: ``MCPServerRegistryError/noSecretStore`` when the host gave
    ///   none.
    private func secretPort() throws(MCPServerRegistryError) -> any MCPServerSecrets {
        guard let secrets else {
            throw .noSecretStore
        }
        return secrets
    }
}
