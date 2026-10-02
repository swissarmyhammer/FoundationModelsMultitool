import Foundation
import FoundationModels
import FoundationModelsMetadataRegistry
import Testing

@testable import FoundationModelsMultitool

/// The name of the shell store directory inside the session root.
private let filesAndShellStoreDirectoryName = ".shell"

/// The nine-entry files-and-shell surface the `acp-agent` had, mounted with
/// the production `searchTools` over it.
///
/// The gated discovery suites drive the same surface — one with the recorded
/// queries of card `^zqz1zan`, one with the recorded and the held-out queries
/// in each retrieval setting, one with the wrong `tools.*` paths of card
/// `^2rwvx3h` — so the mount stands here rather than in any of them.
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

extension FilesAndShellSurface {

    /// Drives one graded group through ``searchTools`` and holds each answer
    /// to the rules the code of this package controls.
    ///
    /// Prints the size of the catalog, one line for each query and one line
    /// for the group, with the correct and the wrong counts. Asserts nothing
    /// on those counts: they measure the model. Asserts that each path a
    /// query declares is a path of the catalog, and that each answer holds
    /// only catalog paths, each one time, inside the limit — see
    /// ``DiscoveryAnswerCheck``. A call that throws fails the test, so each
    /// query also answers without an error.
    ///
    /// - Parameters:
    ///   - queries: the group to drive, in the order it is listed.
    ///   - fixture: the resolved fixture whose recording the raw ids are read
    ///     off.
    ///   - scenario: the label the printed lines carry.
    /// - Throws: whatever the tool call or the transcript read throws.
    func driveGradedGroup(
        of queries: [GradedDiscoveryQuery], recordedBy fixture: LiveRouterFixture, reportedAs scenario: String
    ) async throws {
        reportCatalogSize(of: registry, reportedAs: scenario)
        let check = DiscoveryAnswerCheck(surfaceOf: registry)
        check.expectEveryDeclaredPathIsInTheCatalog(of: queries)
        let group = try await gradeDiscoveryGroup(
            of: queries, through: searchTools, recordedBy: fixture, reportedAs: scenario)
        check.expectNoFault(in: group, answering: queries)
    }
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
/// - Parameters:
///   - fixture: the resolved fixture whose `flash` slot is the librarian and
///     whose embedding handle is the embedder.
///   - tools: standalone tools mounted beside the nine entries, in this
///     order, so a suite can grade discovery of its own tool among these
///     distractors. Empty by default, which mounts the nine entries alone.
/// - Returns: the registry, the mounted tool and the mounted hint searcher.
/// - Throws: whatever the build throws, and a requirement failure when the
///   built session tools hold no `searchTools`.
func makeFilesAndShellSurface(
    over fixture: LiveRouterFixture, adding tools: [any Tool] = []
) throws -> FilesAndShellSurface {
    let root = LiveRouterFixture.makeTempDir()
    let registry = try MultiTool.Builder()
        .withFiles(root: root, readOnly: false)
        .withShell(storeDirectory: root.appendingPathComponent(filesAndShellStoreDirectoryName, isDirectory: true))
        .addTools(tools)
        .buildRegistry()
    let seams = fixture.discoverySeams
    let mounted = try registry.makeSessionToolsAndStaging(selection: seams.selection, embedder: seams.embedder)
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
