// `MCPServerEntry` — one MCP server of the host, as the host stores it: a
// name, one transport, and an on or off switch.
//
// The registry changes the servers one at a time (`MCPServerRegistry`), and
// the host stores them through its `MCPServerStorage` port. Multitool does not
// own the file of the host.

import Foundation

/// One MCP server of the host: the name, the transport and the switch.
///
/// The name is the id of the server. It is also the noun of its tools, as
/// `tools.<name>.<verb>`. A rename changes it.
///
/// An env value or a header value is a literal or a `keychain:<name>`
/// reference (D101). A header value must be a reference, because a header
/// carries a token.
public struct MCPServerEntry: Codable, Equatable, Hashable, Sendable {
    /// How the host reaches a server.
    public enum Transport: Codable, Equatable, Hashable, Sendable {
        /// A subprocess that speaks MCP on stdio. The command is an absolute
        /// path, and `env` adds to the environment of the host.
        case stdio(command: String, args: [String], env: [String: String])

        /// A remote endpoint that speaks MCP over http or https. The
        /// headers carry the authorization.
        case http(url: String, headers: [String: String])

        /// The name of the transport: `stdio` or `http`.
        public var kind: String {
            switch self {
            case .stdio: "stdio"
            case .http: "http"
            }
        }
    }

    /// The name: the id of the server and the noun of its tools.
    public var name: String

    /// How the host reaches the server.
    public var transport: Transport

    /// True when the host connects the server and mounts its tools.
    public var enabled: Bool

    /// Makes a server entry.
    ///
    /// - Parameters:
    ///   - name: The name.
    ///   - transport: The transport.
    ///   - enabled: True to connect the server. The default is true.
    public init(name: String, transport: Transport, enabled: Bool = true) {
        self.name = name
        self.transport = transport
        self.enabled = enabled
    }
}

/// The key of one secret of a server: a header name or an env name.
public enum MCPSecretKey: Codable, Equatable, Hashable, Sendable, CustomStringConvertible {
    /// A header of an http server.
    case header(String)

    /// An env variable of a stdio server.
    case env(String)

    /// The prefix of a reference to a secret in the Keychain (D101).
    public static let keychainPrefix = "keychain:"

    /// The words of the key in a text: `header Authorization` or
    /// `env TOKEN`.
    public var description: String {
        switch self {
        case .header(let name): "header \(name)"
        case .env(let name): "env \(name)"
        }
    }

    /// The name of the Keychain item of this key of a server:
    /// `mcp.<server>.header.<name>` or `mcp.<server>.env.<name>`. A host
    /// that stores a secret uses this name, so each host makes the same
    /// reference.
    ///
    /// - Parameter server: The name of the server.
    /// - Returns: The name of the Keychain item.
    public func keychainItemName(server: String) -> String {
        switch self {
        case .header(let name): "mcp.\(server).header.\(name)"
        case .env(let name): "mcp.\(server).env.\(name)"
        }
    }

    /// The reference to the Keychain item of this key of a server:
    /// `keychain:` and ``keychainItemName(server:)``.
    ///
    /// - Parameter server: The name of the server.
    /// - Returns: The reference.
    public func keychainReference(server: String) -> String {
        Self.keychainPrefix + keychainItemName(server: server)
    }

    /// Tells if `value` is a `keychain:<name>` reference with a name.
    ///
    /// - Parameter value: An env value or a header value.
    /// - Returns: True for a reference.
    public static func isReference(_ value: String) -> Bool {
        value.hasPrefix(keychainPrefix) && value.count > keychainPrefix.count
    }
}
