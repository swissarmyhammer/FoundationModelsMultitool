import Foundation
import Testing

import FoundationModelsExtras
import FoundationModelsRouter

/// Ungated coverage of the metadata cache that the routers of
/// `LiveRouterFixture` share (card `^kghyac5`).
///
/// A run of this package failed two scenarios before they started:
/// `Router.resolve` could not read the metadata of an already downloaded
/// model from the Hugging Face Hub (`The request timed out.`), and the
/// resolve threw `NoWindowFailure`. Router keeps the parsed metadata in its
/// cache directory, and it reads that entry when the fetch of a moving
/// revision fails. The fixture gave each router a new temporary cache
/// directory, thus that entry was never there.
///
/// These tests need no model, no download, and no network: a stub metadata
/// source gives the metadata, and `UnconfiguredModelLoader` stops each
/// resolve at the load step, after the sizing. A resolve that gets to the
/// load step read the metadata of each model.
@Suite("Router metadata cache of the live fixture")
struct RouterMetadataCacheTests {
    /// The profile of the tests. Its three references name no real repo, and
    /// have no revision, thus Router fetches their metadata first and reads
    /// its cache only when the fetch fails — the path of the pinned models.
    private static let profile = ProfileDefinition(
        name: "multitool-metadata-cache-probe",
        description: "Three stub references, for the test of the shared metadata cache.",
        standard: ["multitool-integration/metadata-cache-standard"],
        flash: ["multitool-integration/metadata-cache-flash"],
        embedding: ["multitool-integration/metadata-cache-embedding"],
        context: nil
    )

    @Test("a resolve whose metadata fetch times out reads the metadata that an earlier resolve cached")
    @MainActor
    func timedOutFetchReadsTheCachedMetadata() async throws {
        let recordingsDir = LiveRouterFixture.makeRecordingsDir()
        defer { try? FileManager.default.removeItem(at: recordingsDir) }

        let online = LiveRouterFixture.makeRouter(
            recordingsDir: recordingsDir, loader: UnconfiguredModelLoader(),
            metadataSource: SizedMetadataSource(), pool: ModelPool())
        await #expect(throws: ModelLoaderError.notConfigured) {
            try await online.resolve(profile: Self.profile, reporting: ResolutionProgress())
        }

        let offline = LiveRouterFixture.makeRouter(
            recordingsDir: recordingsDir, loader: UnconfiguredModelLoader(),
            metadataSource: TimedOutMetadataSource(), pool: ModelPool())
        await #expect(throws: ModelLoaderError.notConfigured) {
            try await offline.resolve(profile: Self.profile, reporting: ResolutionProgress())
        }
    }
}

/// A metadata source whose fetch always times out, as the fetch of the
/// failed run did.
private struct TimedOutMetadataSource: MetadataSource {
    func fetchRawMetadata(repo: String, revision: String?) async throws -> RawRepoMetadata {
        throw URLError(.timedOut)
    }
}
