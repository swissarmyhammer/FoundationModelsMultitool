import Foundation
import FoundationModelsMetadataRegistry
import Testing

@testable import FoundationModelsMultitool

/// The name of the shell store directory inside the session root.
private let filesAndShellStoreDirectoryName = ".shell"

/// The nine-entry files-and-shell surface the `acp-agent` had, mounted with
/// the production `searchTools` over it.
///
/// The gated discovery suites drive the same surface — one with the ten
/// queries of card `^zqz1zan`, one with the held-out queries of card
/// `^kn9ay20`, one with the wrong `tools.*` paths of card `^2rwvx3h` — so the
/// mount stands here rather than in any of them.
struct FilesAndShellSurface {

    /// The built registry, whose `surface.entries` are the nine catalog
    /// entries the selection model holds.
    let registry: MultiTool.Registry

    /// The production `searchTools` mounted over ``registry``.
    let searchTools: SearchToolsTool

    /// The did-you-mean ranker `runCode` resolves an invented `tools.*` path
    /// against — `MultiTool.RegistryBundle.hintSearcher`, taken off the holder
    /// the same mount vends.
    ///
    /// A second searcher, and never the one ``searchTools`` forwards to: it
    /// runs in `.retrieval` mode with no selection tier, so a wrong guess is
    /// repaired with no generation at all. Taken off the mounted holder rather
    /// than built here, so a suite reads the searcher a host really gets.
    let hintSearcher: MetadataSearcher<APISurface.Entry>
}

/// Mounts the files-and-shell surface, writable, and takes the production
/// `searchTools` and the production did-you-mean ranker off it.
///
/// The mount is the same call the agent's `ToolCatalog.sessionSurface` makes,
/// with the profile's embedding handle passed the way card `^zqz1zan`'s fix
/// asks every host to pass it — never a reimplementation of that wiring. It is
/// the `AndStaging` half of that call, because the staging it vends *is* the
/// `MultiTool.RegistryHolder` the mounted tools share, and the holder is the
/// one place a caller reads the bundle a run really gets.
///
/// - Parameter fixture: the resolved fixture whose `flash` slot is the
///   librarian and whose embedding handle is the embedder.
/// - Returns: the registry, the mounted tool and the mounted hint searcher.
/// - Throws: whatever the build throws, and a requirement failure when the
///   built session tools hold no `searchTools`.
func makeFilesAndShellSurface(over fixture: LiveRouterFixture) throws -> FilesAndShellSurface {
    let root = LiveRouterFixture.makeTempDir()
    let registry = try MultiTool.Builder()
        .withFiles(root: root, readOnly: false)
        .withShell(storeDirectory: root.appendingPathComponent(filesAndShellStoreDirectoryName, isDirectory: true))
        .buildRegistry()
    let mounted = try registry.makeSessionToolsAndStaging(
        librarian: fixture.profile.flash, embedder: fixture.profile.embedding)
    let searchTools = try #require(mounted.tools.compactMap { $0 as? SearchToolsTool }.first)
    let holder = try #require(mounted.staging as? MultiTool.RegistryHolder)
    return FilesAndShellSurface(
        registry: registry, searchTools: searchTools, hintSearcher: holder.current.hintSearcher)
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
