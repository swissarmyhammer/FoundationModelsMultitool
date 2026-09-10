import Foundation
import FoundationModelsMetadataRegistry
import Testing

@testable import FoundationModelsMultitool

/// The name of the shell store directory inside the session root.
private let filesAndShellStoreDirectoryName = ".shell"

/// The nine-entry files-and-shell surface the `acp-agent` had, mounted with
/// the production `searchTools` over it.
///
/// The two gated discovery suites drive the same surface — one with the ten
/// queries of card `^zqz1zan`, one with the held-out queries of card
/// `^kn9ay20` — so the mount stands here rather than in either of them.
struct FilesAndShellSurface {

    /// The built registry, whose `surface.entries` are the nine catalog
    /// entries the selection model holds.
    let registry: MultiTool.Registry

    /// The production `searchTools` mounted over ``registry``.
    let searchTools: SearchToolsTool
}

/// Mounts the files-and-shell surface, writable, and takes the production
/// `searchTools` off it.
///
/// The mount is the same call the agent's `ToolCatalog.sessionSurface` makes,
/// with the profile's embedding handle passed the way card `^zqz1zan`'s fix
/// asks every host to pass it — never a reimplementation of that wiring.
///
/// - Parameter fixture: the resolved fixture whose `flash` slot is the
///   librarian and whose embedding handle is the embedder.
/// - Returns: the registry and the mounted tool.
/// - Throws: whatever the build throws, and a requirement failure when the
///   built session tools hold no `searchTools`.
func makeFilesAndShellSurface(over fixture: LiveRouterFixture) throws -> FilesAndShellSurface {
    let root = LiveRouterFixture.makeTempDir()
    let registry = try MultiTool.Builder()
        .withFiles(root: root, readOnly: false)
        .withShell(storeDirectory: root.appendingPathComponent(filesAndShellStoreDirectoryName, isDirectory: true))
        .buildRegistry()
    let searchTools = try #require(
        registry.makeSessionTools(librarian: fixture.profile.flash, embedder: fixture.profile.embedding)
            .compactMap { $0 as? SearchToolsTool }
            .first
    )
    return FilesAndShellSurface(registry: registry, searchTools: searchTools)
}

/// Prints the size of the catalog the selection model holds in its
/// instructions for `registry`, against the budget it is measured by.
///
/// - Parameters:
///   - registry: the registry whose surface the selection tier assembles its
///     prefix from.
///   - scenario: the label the printed line carries.
func reportCatalogSize(of registry: MultiTool.Registry, reportedAs scenario: String) {
    let entries = registry.surface.entries
    let prefix = selectionPrefix(of: registry)
    reportGatedResult(
        scenario: scenario,
        line: "entries=\(entries.count) prefixCharacters=\(prefix.count) "
            + "budget=\(SelectionConfig.defaultCapacityCharacterLimit) ids=\(entries.map(\.path))"
    )
}
