// `MCPServerStorage` — the port through which `MCPServerRegistry` reads and
// writes the MCP servers of the host. The host supplies it: ACPAgent writes
// the servers to its user settings layer. `InMemoryMCPServerStorage` is the
// storage of a test.

import Synchronization

/// The storage of the MCP servers of a host.
///
/// The registry reads the whole list before each change and writes the whole
/// list after it, so a change of another writer between two changes stays.
public protocol MCPServerStorage: Sendable {
    /// The servers, in their stored order.
    ///
    /// - Returns: The servers.
    /// - Throws: An error of the host storage.
    func loadServers() async throws -> [MCPServerEntry]

    /// Replaces the stored servers.
    ///
    /// - Parameter servers: The servers, in order.
    /// - Throws: An error of the host storage.
    func saveServers(_ servers: [MCPServerEntry]) async throws
}

/// A storage in memory, for a test or a host with no persistence.
public final class InMemoryMCPServerStorage: MCPServerStorage {
    /// The servers.
    private let servers: Mutex<[MCPServerEntry]>

    /// Makes a storage that holds `servers`.
    ///
    /// - Parameter servers: The first servers. The default is none.
    public init(_ servers: [MCPServerEntry] = []) {
        self.servers = Mutex(servers)
    }

    /// The servers, in their stored order.
    ///
    /// - Returns: The servers.
    public func loadServers() async throws -> [MCPServerEntry] {
        servers.withLock { $0 }
    }

    /// Replaces the stored servers.
    ///
    /// - Parameter servers: The servers, in order.
    public func saveServers(_ servers: [MCPServerEntry]) async throws {
        self.servers.withLock { $0 = servers }
    }
}
