// `LargeCatalogSurface` — the mounted surface the large catalog builds.
//
// Test support — see the header of `ScriptedServer.swift`.
//
// `LargeCatalogToolKit.swift` beside this file declares the verbs. This file
// mounts them: it connects one scripted server for each domain and then builds
// the registry through the same `MultiTool.Builder` chain a host writes.
//
// Two suites measure a catalog above the selection budget, and they stand in
// two packages: `OverBudgetSelectionOrderTests` in the root package, which
// holds the order rule with a scripted model, and
// `OverBudgetSurfaceDiscoveryTests` in the nested `IntegrationTests` package,
// which drives the same size of surface with a real one. A package cannot
// import another package's test target, so a mount both of them read must
// stand in a product. This target is the product both of them already link,
// and it already holds the verbs.

import Foundation
import FoundationModelsExtras
import FoundationModelsMultitool

/// A registry over the large catalog surface, beside the scripted servers
/// behind it, which the caller keeps alive for the length of its test.
public struct LargeCatalogSurface: Sendable {
    /// The built registry, whose surface a search indexes.
    public let registry: MultiTool.Registry

    /// The scripted servers the registry's MCP verbs are served by.
    public let servers: [ScriptedServer]

    /// The `MCPServer` of one domain that the mount makes by default: the
    /// public initializer with `.interactive` presence, because a person can
    /// answer in this surface. Its connect attempts are timed on the real
    /// clock.
    ///
    /// - Parameter name: The server name of the domain.
    /// - Returns: The server, not yet connected.
    public static func makeInteractiveServer(name: String) -> MCPServer {
        MCPServer(name: name, userPresence: .interactive)
    }

    /// Mounts the large surface, gives it to `body`, and then disconnects each
    /// `MCPServer` of the mount, also when `body` throws (test rule T1).
    ///
    /// ``makeLargeCatalogSurface(root:shellStoreDirectoryName:domains:describing:makeServer:)``
    /// does not return its connected servers. Thus this function wraps
    /// `makeServer` and records each server that it makes. When the mount
    /// throws, this function disconnects the servers that it made before the
    /// throw.
    ///
    /// - Parameters:
    ///   - root: The session root, as the mount takes it. The caller owns that
    ///     directory and removes it when its test ends.
    ///   - shellStoreDirectoryName: The name of the shell store directory, as
    ///     the mount takes it.
    ///   - domains: The domains to connect a server for, as the mount takes
    ///     them.
    ///   - describing: Whether each connected verb publishes a description,
    ///     as the mount takes it.
    ///   - makeServer: Builds the `MCPServer` of each domain, as the mount
    ///     takes it.
    ///   - body: The work of the test on the mount.
    /// - Returns: What `body` returned.
    /// - Throws: What the mount or `body` throws, after each disconnect.
    public static func withMounted<Result>(
        root: URL,
        shellStoreDirectoryName: String,
        domains: [LargeCatalogDomain] = LargeCatalogDomain.allCases,
        describing: Bool = true,
        makeServer: (_ name: String) -> MCPServer = LargeCatalogSurface.makeInteractiveServer(name:),
        _ body: (LargeCatalogSurface) async throws -> Result
    ) async throws -> Result {
        var madeServers: [MCPServer] = []
        let mounted: LargeCatalogSurface
        do {
            mounted = try await makeLargeCatalogSurface(
                root: root, shellStoreDirectoryName: shellStoreDirectoryName, domains: domains,
                describing: describing,
                makeServer: { name in
                    let server = makeServer(name)
                    madeServers.append(server)
                    return server
                })
        } catch {
            await DisconnectScope.disconnect(madeServers)
            throw error
        }
        return try await DisconnectScope.disconnecting(madeServers) {
            try await body(mounted)
        }
    }
}

/// Mounts the large surface: the files and shell capabilities of a host, plus
/// one connected MCP server for each ``LargeCatalogDomain``.
///
/// The production mount, never a reimplementation of its wiring — the same
/// `MultiTool.Builder` chain a host writes. The catalog it builds assembles a
/// selection prefix above the shipped budget, so a search over it takes the
/// path where the selection tier splits the catalog into slices and prompts
/// one slice at a time. Nothing here lowers a budget: the size is what forty
/// ordinary verb descriptions weigh beside the two local capabilities.
///
/// - Parameters:
///   - root: the session root the files capability reads and writes under.
///     The caller owns that directory and removes it when its test ends.
///   - shellStoreDirectoryName: the name of the shell store directory the
///     shell capability keeps its state in, inside `root`.
///   - domains: the domains to connect a server for. Every domain, the
///     default, is the catalog above the selection budget. A caller that
///     measures something other than the size names fewer.
///   - describing: whether each connected verb publishes a description —
///     see ``ScriptedServer/addLargeCatalogTools(of:describing:)``. `false`
///     builds the surface of a server that gives none.
///   - makeServer: builds the `MCPServer` of each domain, not yet connected,
///     from the server name of the domain. The default is
///     ``LargeCatalogSurface/makeInteractiveServer(name:)``. A unit test
///     passes a maker whose connect-attempt clock it holds, so no connect of
///     the mount can time out on a busy machine.
/// - Returns: the registry and the servers behind it.
/// - Throws: what the connect, the capability mounts or `buildRegistry()`
///   throws.
public func makeLargeCatalogSurface(
    root: URL,
    shellStoreDirectoryName: String,
    domains: [LargeCatalogDomain] = LargeCatalogDomain.allCases,
    describing: Bool = true,
    makeServer: (_ name: String) -> MCPServer = LargeCatalogSurface.makeInteractiveServer(name:)
) async throws -> LargeCatalogSurface {
    var scriptedServers: [ScriptedServer] = []
    var connectedServers: [MCPServer] = []
    for domain in domains {
        let scripted = ScriptedServer(name: domain.serverName)
        await scripted.addLargeCatalogTools(of: domain, describing: describing)
        let connected = makeServer(domain.serverName)
        try await connected.connect(via: scripted.startOnInMemoryPair())
        scriptedServers.append(scripted)
        connectedServers.append(connected)
    }
    let registry = try await MultiTool.Builder()
        .withFiles(root: root, readOnly: false)
        .withShell(
            storeDirectory: root.appendingPathComponent(shellStoreDirectoryName, isDirectory: true))
        .withMCP(servers: connectedServers)
        .buildRegistry()
    return LargeCatalogSurface(registry: registry, servers: scriptedServers)
}
