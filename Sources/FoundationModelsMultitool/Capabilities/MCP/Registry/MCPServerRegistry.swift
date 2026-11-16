// `MCPServerRegistry` — the item API over the MCP servers of the host: list,
// get, add, update, remove and switch one server at a time, with no rewrite
// of the whole list by a client (the user: "C R U D each ... MCP server, not
// rewrite a whole list").
//
// The registry holds no copy of the servers. Each change reads the storage
// of the host, changes one server, checks the rules, and saves. Thus a change
// of another writer between two changes stays. Each change that saves gives
// one `MCPServerChange` to each subscriber of `changes()`, with the server
// after the change, so a client can update one row. A refused change saves
// nothing and gives no change.

import Foundation

/// A change of one field or more of one MCP server. A field that is `nil`
/// does not change.
///
/// A `command`, `args` or `env` belongs to the stdio transport, and a `url`
/// or `headers` belongs to the http transport. A `command` changes an http
/// server to a stdio server, and a `url` changes a stdio server to an http
/// server. The other keys of the new transport start empty unless the change
/// gives them.
public struct MCPServerUpdate: Equatable, Sendable {
    /// The new name, or `nil`.
    public var name: String?

    /// The new stdio command, or `nil`.
    public var command: String?

    /// The new stdio arguments, or `nil`.
    public var args: [String]?

    /// The new stdio env, or `nil`. It replaces the whole env.
    public var env: [String: String]?

    /// The new http url, or `nil`.
    public var url: String?

    /// The new http headers, or `nil`. They replace all headers.
    public var headers: [String: String]?

    /// The new switch, or `nil`.
    public var enabled: Bool?

    /// Makes a change.
    ///
    /// - Parameters:
    ///   - name: The new name.
    ///   - command: The new stdio command.
    ///   - args: The new stdio arguments.
    ///   - env: The new stdio env.
    ///   - url: The new http url.
    ///   - headers: The new http headers.
    ///   - enabled: The new switch.
    public init(
        name: String? = nil, command: String? = nil, args: [String]? = nil, env: [String: String]? = nil,
        url: String? = nil, headers: [String: String]? = nil, enabled: Bool? = nil
    ) {
        self.name = name
        self.command = command
        self.args = args
        self.env = env
        self.url = url
        self.headers = headers
        self.enabled = enabled
    }

    /// True when the change gives a command, args or url: a change that
    /// makes the host run another program or reach another server.
    public var changesWhatRuns: Bool {
        command != nil || args != nil || url != nil
    }

    /// `entry` with this change.
    ///
    /// - Parameter entry: The server before the change.
    /// - Returns: The server after the change.
    /// - Throws: ``MCPServerRegistryError/conflictingTransport(server:)``
    ///   when the change gives keys of two transports, or keys of the other
    ///   transport with no command or url to change to it.
    func applied(to entry: MCPServerEntry) throws(MCPServerRegistryError) -> MCPServerEntry {
        let stdioKeys = command != nil || args != nil || env != nil
        let httpKeys = url != nil || headers != nil
        guard !(stdioKeys && httpKeys) else {
            throw .conflictingTransport(server: entry.name)
        }
        var changed = entry
        changed.name = name ?? entry.name
        changed.enabled = enabled ?? entry.enabled
        switch entry.transport {
        case .stdio(let oldCommand, let oldArgs, let oldEnv):
            if httpKeys {
                guard let url else {
                    throw .conflictingTransport(server: entry.name)
                }
                changed.transport = .http(url: url, headers: headers ?? [:])
            } else {
                changed.transport = .stdio(
                    command: command ?? oldCommand, args: args ?? oldArgs, env: env ?? oldEnv)
            }
        case .http(let oldURL, let oldHeaders):
            if stdioKeys {
                guard let command else {
                    throw .conflictingTransport(server: entry.name)
                }
                changed.transport = .stdio(command: command, args: args ?? [], env: env ?? [:])
            } else {
                changed.transport = .http(url: url ?? oldURL, headers: headers ?? oldHeaders)
            }
        }
        return changed
    }
}

/// One change of the MCP servers. Each case carries the server, so a client
/// updates one row with no new read.
public enum MCPServerChange: Equatable, Sendable {
    /// A new server.
    case added(MCPServerEntry)

    /// A changed server: its fields after the change, and its name before
    /// the change, which differs after a rename.
    case updated(MCPServerEntry, previousName: String)

    /// A removed server, as it was before the remove.
    case removed(MCPServerEntry)

    /// The server of the change.
    public var entry: MCPServerEntry {
        switch self {
        case .added(let entry), .updated(let entry, _), .removed(let entry): entry
        }
    }
}

/// The MCP servers of a host, changed one at a time.
public actor MCPServerRegistry {
    /// The rule of a server name, for the text of a refusal.
    public static let nameRule =
        "A name has 1 to 64 characters: lower-case letters, digits, - and _. The first character is a letter."

    /// The most characters of a name.
    static let maximumNameLength = 64

    /// The storage of the host.
    private let storage: any MCPServerStorage

    /// The names that the host keeps for its own tools.
    private let reservedNames: Set<String>

    /// The subscribers of ``changes()``.
    private var subscribers: [UUID: AsyncStream<MCPServerChange>.Continuation] = [:]

    /// Makes a registry over the storage of a host.
    ///
    /// - Parameters:
    ///   - storage: The storage.
    ///   - reservedNames: The names that the host keeps for its own tools,
    ///     for example `files` and `shell`. A server cannot have one.
    public init(storage: any MCPServerStorage, reservedNames: Set<String> = []) {
        self.storage = storage
        self.reservedNames = reservedNames
    }

    // MARK: - Read

    /// The servers, in their stored order.
    ///
    /// - Returns: The servers.
    /// - Throws: An error of the storage.
    public func list() async throws -> [MCPServerEntry] {
        try await storage.loadServers()
    }

    /// The server with the name.
    ///
    /// - Parameter name: The name.
    /// - Returns: The server, or `nil` when no server has the name.
    /// - Throws: An error of the storage.
    public func server(named name: String) async throws -> MCPServerEntry? {
        try await storage.loadServers().first { $0.name == name }
    }

    // MARK: - Change

    /// Adds a server after the other servers.
    ///
    /// - Parameter entry: The server.
    /// - Returns: The server.
    /// - Throws: ``MCPServerRegistryError`` for a server that breaks a rule
    ///   or that has the name of another server, and each error of the
    ///   storage.
    @discardableResult
    public func add(_ entry: MCPServerEntry) async throws -> MCPServerEntry {
        try check(entry)
        var servers = try await storage.loadServers()
        guard !servers.contains(where: { $0.name == entry.name }) else {
            throw MCPServerRegistryError.duplicateName(entry.name)
        }
        servers.append(entry)
        try await storage.saveServers(servers)
        publish(.added(entry))
        return entry
    }

    /// Changes the given fields of one server, in its place.
    ///
    /// - Parameters:
    ///   - name: The name of the server.
    ///   - update: The change.
    /// - Returns: The server after the change.
    /// - Throws: ``MCPServerRegistryError`` for an unknown server, a change
    ///   that breaks a rule, or a new name that another server has; and each
    ///   error of the storage.
    @discardableResult
    public func update(named name: String, with update: MCPServerUpdate) async throws -> MCPServerEntry {
        var servers = try await storage.loadServers()
        let index = try Self.index(of: name, in: servers)
        let changed = try update.applied(to: servers[index])
        try check(changed)
        if changed.name != name, servers.contains(where: { $0.name == changed.name }) {
            throw MCPServerRegistryError.duplicateName(changed.name)
        }
        servers[index] = changed
        try await storage.saveServers(servers)
        publish(.updated(changed, previousName: name))
        return changed
    }

    /// Removes one server.
    ///
    /// - Parameter name: The name of the server.
    /// - Returns: The removed server.
    /// - Throws: ``MCPServerRegistryError/unknownServer(_:)``, and each error
    ///   of the storage.
    @discardableResult
    public func remove(named name: String) async throws -> MCPServerEntry {
        var servers = try await storage.loadServers()
        let removed = servers.remove(at: try Self.index(of: name, in: servers))
        try await storage.saveServers(servers)
        publish(.removed(removed))
        return removed
    }

    /// Turns one server on or off.
    ///
    /// - Parameters:
    ///   - enabled: True to turn it on.
    ///   - name: The name of the server.
    /// - Returns: The server after the change.
    /// - Throws: ``MCPServerRegistryError/unknownServer(_:)``, and each error
    ///   of the storage.
    @discardableResult
    public func setEnabled(_ enabled: Bool, named name: String) async throws -> MCPServerEntry {
        try await update(named: name, with: MCPServerUpdate(enabled: enabled))
    }

    // MARK: - Changes

    /// A new stream of the changes after this call. The stream ends when the
    /// subscriber stops it.
    ///
    /// - Returns: The stream.
    public func changes() -> AsyncStream<MCPServerChange> {
        let (stream, continuation) = AsyncStream.makeStream(of: MCPServerChange.self)
        let id = UUID()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.unsubscribe(id) }
        }
        return stream
    }

    /// Removes one subscriber.
    ///
    /// - Parameter id: The subscriber.
    private func unsubscribe(_ id: UUID) {
        subscribers[id] = nil
    }

    /// Gives a change to each subscriber.
    ///
    /// - Parameter change: The change.
    private func publish(_ change: MCPServerChange) {
        for continuation in subscribers.values {
            continuation.yield(change)
        }
    }

    // MARK: - Rules

    /// The index of the server with the name.
    ///
    /// - Parameters:
    ///   - name: The name.
    ///   - servers: The servers.
    /// - Returns: The index.
    /// - Throws: ``MCPServerRegistryError/unknownServer(_:)``.
    private static func index(of name: String, in servers: [MCPServerEntry]) throws(MCPServerRegistryError) -> Int {
        guard let index = servers.firstIndex(where: { $0.name == name }) else {
            throw .unknownServer(name)
        }
        return index
    }

    /// Checks each rule of a server.
    ///
    /// - Parameter entry: The server.
    /// - Throws: ``MCPServerRegistryError`` for the first rule that the
    ///   server breaks.
    private func check(_ entry: MCPServerEntry) throws(MCPServerRegistryError) {
        guard Self.isValidName(entry.name) else {
            throw .invalidName(entry.name)
        }
        guard !reservedNames.contains(entry.name) else {
            throw .reservedName(entry.name)
        }
        switch entry.transport {
        case .stdio(let command, _, _):
            guard command.hasPrefix("/") else {
                throw .relativeCommand(server: entry.name, command: command)
            }
        case .http(let url, let headers):
            guard Self.isWebURL(url) else {
                throw .invalidURL(server: entry.name, url: url)
            }
            if let key = headers.keys.sorted().first(where: { !MCPSecretKey.isReference(headers[$0] ?? "") }) {
                throw .literalSecret(server: entry.name, key: .header(key))
            }
        }
    }

    /// Tells if a name obeys ``nameRule``.
    ///
    /// - Parameter name: The name.
    /// - Returns: True for a valid name.
    static func isValidName(_ name: String) -> Bool {
        let letters: ClosedRange<Unicode.Scalar> = "a"..."z"
        let digits: ClosedRange<Unicode.Scalar> = "0"..."9"
        guard let first = name.unicodeScalars.first, name.unicodeScalars.count <= maximumNameLength,
            letters.contains(first)
        else {
            return false
        }
        return name.unicodeScalars.allSatisfy { letters.contains($0) || digits.contains($0) || $0 == "-" || $0 == "_" }
    }

    /// Tells if a text is an http or https url with a host.
    ///
    /// - Parameter text: The text.
    /// - Returns: True for a web url.
    static func isWebURL(_ text: String) -> Bool {
        guard let components = URLComponents(string: text), let scheme = components.scheme?.lowercased(),
            let host = components.host, !host.isEmpty
        else {
            return false
        }
        return scheme == "http" || scheme == "https"
    }
}
