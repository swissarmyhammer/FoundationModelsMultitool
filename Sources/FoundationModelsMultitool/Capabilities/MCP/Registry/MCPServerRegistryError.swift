// `MCPServerRegistryError` — each refusal of `MCPServerRegistry`, with a
// text that tells what to do. A text names the key of a secret, and never
// its value.

import Foundation

/// A change of the MCP servers that the registry refuses.
public enum MCPServerRegistryError: Error, Equatable, Sendable, CustomStringConvertible, LocalizedError {
    /// A server has the name already.
    case duplicateName(String)

    /// No server has the name.
    case unknownServer(String)

    /// The name does not obey the name rule.
    case invalidName(String)

    /// The host keeps the name for one of its own tools.
    case reservedName(String)

    /// The stdio command is not an absolute path.
    case relativeCommand(server: String, command: String)

    /// The url is not an http or https url with a host.
    case invalidURL(server: String, url: String)

    /// A header value, or a secret value, is not a `keychain:<name>`
    /// reference (D101).
    case literalSecret(server: String, key: MCPSecretKey)

    /// The user declined to give a secret, or the host could not ask.
    case secretDeclined(server: String, key: MCPSecretKey)

    /// The change gives a secret value, and the host has no Keychain port.
    case noSecretStore

    /// The change gives the keys of two transports, or the keys of the
    /// other transport than the transport of the server.
    case conflictingTransport(server: String)

    /// The text of the refusal, with what to do.
    public var description: String {
        switch self {
        case .duplicateName(let name):
            "An MCP server with the name \"\(name)\" exists already. Use another name, or edit that server."
        case .unknownServer(let name):
            "No MCP server has the name \"\(name)\". List the MCP servers to get a name."
        case .invalidName(let name):
            "\"\(name)\" is not a valid MCP server name. \(MCPServerRegistry.nameRule)"
        case .reservedName(let name):
            "The name \"\(name)\" is the name of a built-in tool. Use another name."
        case .relativeCommand(let server, let command):
            "The command \"\(command)\" of MCP server \"\(server)\" is not an absolute path. "
                + "Give the full path, for example /usr/local/bin/\(command)."
        case .invalidURL(let server, let url):
            "The url \"\(url)\" of MCP server \"\(server)\" is not an http or https url."
        case .literalSecret(let server, let key):
            "The \(key) of MCP server \"\(server)\" must be a \(MCPSecretKey.keychainPrefix)<name> reference. "
                + "Give the secret through the secret prompt, not as text."
        case .secretDeclined(let server, let key):
            "The user did not give the \(key) of MCP server \"\(server)\". Nothing changed. "
                + "Ask the user before you try again."
        case .noSecretStore:
            "This host cannot store a secret. Nothing changed. Ask the user to add the secret in Settings."
        case .conflictingTransport(let server):
            "The change of MCP server \"\(server)\" mixes the two transports. Give a command with args and env "
                + "(stdio), or a url with headers (http)."
        }
    }

    /// The text of the refusal.
    public var errorDescription: String? {
        description
    }
}
