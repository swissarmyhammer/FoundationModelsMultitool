// The object types, the input objects and the coded errors of the
// `mcpServers` GraphQL endpoint.

import Foundation
import FoundationModelsExtras
import GraphQL

// MARK: - Output types

/// The `MCPServerTransport` enum: how the host reaches a server.
enum MCPServersGraphTransport: String, Codable, CaseIterable, Sendable {
    /// A subprocess that speaks MCP on stdio.
    case stdio = "STDIO"

    /// A remote endpoint that speaks MCP over http or https.
    case http = "HTTP"
}

/// The `MCPServerSetting` type: one env variable or one header.
struct MCPServersGraphSetting: Codable, Sendable {
    /// The name of the variable or the header.
    let name: String

    /// The value. For a secret, the `keychain:<name>` reference.
    let value: String

    /// True when the value is a `keychain:` reference.
    let secret: Bool

    /// The settings of a map, sorted by name.
    ///
    /// - Parameter map: The map.
    /// - Returns: The settings.
    static func sorted(_ map: [String: String]) -> [Self] {
        map.sorted { $0.key < $1.key }.map {
            Self(name: $0.key, value: $0.value, secret: MCPSecretKey.isReference($0.value))
        }
    }
}

/// The `MCPServer` type: one MCP server of the host.
struct MCPServersGraphServer: Codable, Sendable {
    /// The name: the id of the server and the noun of its tools.
    let name: String

    /// True when the host connects the server.
    let enabled: Bool

    /// The transport.
    let transport: MCPServersGraphTransport

    /// The stdio command, or `nil` for an http server.
    let command: String?

    /// The stdio arguments; none for an http server.
    let args: [String]

    /// The stdio env, sorted by name; none for an http server.
    let env: [MCPServersGraphSetting]

    /// The http url, or `nil` for a stdio server.
    let url: String?

    /// The http headers, sorted by name; none for a stdio server.
    let headers: [MCPServersGraphSetting]

    /// Makes the object of an entry.
    ///
    /// - Parameter entry: The entry.
    init(_ entry: MCPServerEntry) {
        name = entry.name
        enabled = entry.enabled
        switch entry.transport {
        case .stdio(let command, let args, let env):
            transport = .stdio
            self.command = command
            self.args = args
            self.env = MCPServersGraphSetting.sorted(env)
            url = nil
            headers = []
        case .http(let url, let headers):
            transport = .http
            command = nil
            args = []
            env = []
            self.url = url
            self.headers = MCPServersGraphSetting.sorted(headers)
        }
    }
}

/// The `MCPServerChangeKind` enum.
enum MCPServersGraphChangeKind: String, Codable, CaseIterable, Sendable {
    /// A new server.
    case added = "ADDED"

    /// A changed server.
    case updated = "UPDATED"

    /// A removed server.
    case removed = "REMOVED"
}

/// The `MCPServerChange` type: one change of one server, with the whole
/// server after the change, so a client updates one row with no new read.
struct MCPServersGraphChange: Sendable {
    /// The cursor that resumes the subscription after this change.
    let cursor: String

    /// The time of the change.
    let at: DateTime

    /// The kind of the change.
    let kind: MCPServersGraphChangeKind

    /// The name of the server after the change.
    let name: String

    /// The name of the server before the change: it differs after a rename.
    let previousName: String

    /// The server after the change, or before a remove.
    let server: MCPServersGraphServer

    /// The name of the server that the change added, or none (rule 9).
    var added: [ToolkitID] {
        kind == .added ? [ToolkitID(name)] : []
    }

    /// The name of the server that the change changed, or none (rule 9).
    var changed: [ToolkitID] {
        kind == .updated ? [ToolkitID(name)] : []
    }

    /// The name of the server that the change removed, or none (rule 9).
    var removed: [ToolkitID] {
        kind == .removed ? [ToolkitID(name)] : []
    }

    /// Makes the change of one entry of the change log.
    ///
    /// - Parameter entry: The entry.
    init(_ entry: ChangeLogEntry<MCPServerChange>) {
        cursor = entry.cursor
        at = DateTime(entry.at)
        server = MCPServersGraphServer(entry.event.entry)
        name = entry.event.entry.name
        switch entry.event {
        case .added(let added):
            kind = .added
            previousName = added.name
        case .updated(_, let previous):
            kind = .updated
            previousName = previous
        case .removed(let removed):
            kind = .removed
            previousName = removed.name
        }
    }
}

// MARK: - Arguments and input objects

/// The arguments of `Query.mcpServer`.
struct MCPServersGraphNameArguments: Codable, Sendable {
    /// The name of the server.
    let name: String
}

/// The arguments of `Subscription.changes`.
struct MCPServersGraphChangesArguments: Codable, Sendable {
    /// The cursor to resume after, or `nil` for the changes from now on.
    let after: String?
}

/// The arguments of a mutation: one input object.
struct MCPServersGraphMutationArguments<Input: Codable & Sendable>: Codable, Sendable {
    /// The input object.
    let input: Input
}

/// The `MCPServerSettingInput` input object: one env variable or header.
struct MCPServersGraphSettingInput: Codable, Sendable {
    /// The name of the variable or the header.
    let name: String

    /// The value.
    let value: String

    /// The map of a list of settings, or `nil` for no list.
    ///
    /// - Parameter settings: The settings.
    /// - Returns: The map. A later setting with the same name wins.
    static func map(_ settings: [Self]?) -> [String: String]? {
        settings.map { Dictionary($0.map { ($0.name, $0.value) }) { _, later in later } }
    }
}

/// The secret value of each key of an input object.
///
/// - Parameters:
///   - headers: The header secrets.
///   - env: The env secrets.
/// - Returns: The value of each key.
func mcpServersGraphSecrets(
    headers: [MCPServersGraphSettingInput]?, env: [MCPServersGraphSettingInput]?
) -> [MCPSecretKey: String] {
    let headerPairs = (headers ?? []).map { (MCPSecretKey.header($0.name), $0.value) }
    let envPairs = (env ?? []).map { (MCPSecretKey.env($0.name), $0.value) }
    return Dictionary(headerPairs + envPairs) { _, later in later }
}

/// The `AddMCPServerInput` input object.
struct MCPServersGraphAddInput: Codable, Sendable {
    /// The name.
    let name: String

    /// The stdio command, or `nil` for an http server.
    let command: String?

    /// The stdio arguments.
    let args: [String]?

    /// The plain stdio env values.
    let env: [MCPServersGraphSettingInput]?

    /// The http url, or `nil` for a stdio server.
    let url: String?

    /// The http headers: each value is a `keychain:` reference.
    let headers: [MCPServersGraphSettingInput]?

    /// The secret header values, which go to the Keychain.
    let headerSecrets: [MCPServersGraphSettingInput]?

    /// The secret env values, which go to the Keychain.
    let envSecrets: [MCPServersGraphSettingInput]?

    /// True to connect the server. The default is true.
    let enabled: Bool?

    /// The entry of this input.
    ///
    /// - Returns: The entry.
    /// - Throws: ``MCPServerRegistryError/conflictingTransport(server:)``
    ///   when the input gives both a command and a url, or neither.
    func entry() throws(MCPServerRegistryError) -> MCPServerEntry {
        switch (command, url) {
        case (let command?, nil):
            return MCPServerEntry(
                name: name,
                transport: .stdio(
                    command: command, args: args ?? [], env: MCPServersGraphSettingInput.map(env) ?? [:]),
                enabled: enabled ?? true)
        case (nil, let url?) where args == nil && env == nil:
            return MCPServerEntry(
                name: name, transport: .http(url: url, headers: MCPServersGraphSettingInput.map(headers) ?? [:]),
                enabled: enabled ?? true)
        default:
            throw .conflictingTransport(server: name)
        }
    }
}

/// The `UpdateMCPServerInput` input object.
struct MCPServersGraphUpdateInput: Codable, Sendable {
    /// The name of the server.
    let name: String

    /// The new name.
    let newName: String?

    /// The new stdio command.
    let command: String?

    /// The new stdio arguments.
    let args: [String]?

    /// The new plain stdio env values: they replace the whole env.
    let env: [MCPServersGraphSettingInput]?

    /// The new http url.
    let url: String?

    /// The new http headers: they replace all headers.
    let headers: [MCPServersGraphSettingInput]?

    /// The secret header values, which go to the Keychain.
    let headerSecrets: [MCPServersGraphSettingInput]?

    /// The secret env values, which go to the Keychain.
    let envSecrets: [MCPServersGraphSettingInput]?

    /// The new switch.
    let enabled: Bool?

    /// The change of this input.
    var update: MCPServerUpdate {
        MCPServerUpdate(
            name: newName, command: command, args: args, env: MCPServersGraphSettingInput.map(env), url: url,
            headers: MCPServersGraphSettingInput.map(headers), enabled: enabled)
    }
}

/// The `RemoveMCPServerInput` input object.
struct MCPServersGraphRemoveInput: Codable, Sendable {
    /// The name of the server.
    let name: String
}

/// The `SetMCPServerEnabledInput` input object.
struct MCPServersGraphEnableInput: Codable, Sendable {
    /// The name of the server.
    let name: String

    /// True to turn the server on.
    let enabled: Bool
}

// MARK: - Coded errors

/// A call that the `mcpServers` endpoint refuses, with the text of the
/// registry.
struct MCPServersRefusal: CodedError {
    /// The code of each refusal.
    enum Kind: String, CaseIterable, Sendable {
        /// A server has the name already.
        case duplicateName = "DUPLICATE_NAME"

        /// The name is not valid or is reserved.
        case invalidName = "INVALID_NAME"

        /// A field of the input breaks a rule.
        case invalidInput = "INVALID_INPUT"

        /// The user gave no secret.
        case secretDeclined = "SECRET_DECLINED"

        /// The host cannot store a secret.
        case noSecretStore = "NO_SECRET_STORE"

        /// An external client reads and changes no MCP server.
        case untrustedClient = "UNTRUSTED_CLIENT"
    }

    /// The code of each refusal, for the conformance check.
    static let codes = Kind.allCases.map(\.rawValue)

    /// The text of the refusal of an external client.
    static let untrustedText =
        "An external client cannot read or change the MCP servers: an MCP server runs a program on this Mac."

    /// The kind.
    let kind: Kind

    /// The text.
    let message: String

    /// The code in `extensions.code`.
    var code: String {
        kind.rawValue
    }

    /// The coded error of a refusal of the registry.
    ///
    /// - Parameter error: The refusal.
    /// - Returns: The `NOT_FOUND` of the toolkit for an unknown server, or a
    ///   refusal with the text of the registry.
    static func coded(_ error: MCPServerRegistryError) -> any CodedError {
        let kind: Kind
        switch error {
        case .unknownServer(let name):
            return GraphQLToolkitError.notFound(kind: "mcpServer", id: name)
        case .duplicateName:
            kind = .duplicateName
        case .invalidName, .reservedName:
            kind = .invalidName
        case .relativeCommand, .invalidURL, .literalSecret, .conflictingTransport:
            kind = .invalidInput
        case .secretDeclined:
            kind = .secretDeclined
        case .noSecretStore:
            kind = .noSecretStore
        }
        return MCPServersRefusal(kind: kind, message: error.description)
    }
}
