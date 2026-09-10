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
import FoundationModelsMultitool

/// A registry over the large catalog surface, beside the scripted servers
/// behind it, which the caller keeps alive for the length of its test.
public struct LargeCatalogSurface: Sendable {
    /// The built registry, whose surface a search indexes.
    public let registry: MultiTool.Registry

    /// The scripted servers the registry's MCP verbs are served by.
    public let servers: [ScriptedServer]
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
/// - Returns: the registry and the servers behind it.
/// - Throws: what the connect, the capability mounts or `buildRegistry()`
///   throws.
public func makeLargeCatalogSurface(
    root: URL,
    shellStoreDirectoryName: String
) async throws -> LargeCatalogSurface {
    var scriptedServers: [ScriptedServer] = []
    var connectedServers: [MCPServer] = []
    for domain in LargeCatalogDomain.allCases {
        let scripted = ScriptedServer(name: domain.serverName)
        await scripted.addLargeCatalogTools(of: domain)
        let connected = MCPServer(name: domain.serverName)
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
