import Foundation
import HuggingFace
import MLXHuggingFace
import MLXLMCommon
import Testing
import Tokenizers

import FoundationModelsRouter

/// The opt-in environment variable enabling this gated, real-model suite —
/// plan.md M6.5: "opt-in via env var (e.g. MULTITOOL_INTEGRATION=1)". Unset
/// (the default, and on any network/GPU-less/CI box), the whole suite is
/// skipped, so `swift test` stays green with zero downloads. Mirrors
/// Router's own gate
/// (`../FoundationModelsRouter/Tests/FoundationModelsRouterIntegrationTests/IntegrationTests.swift`'s
/// `FM_ROUTER_INTEGRATION_TESTS`).
let multitoolIntegrationEnvVar = "MULTITOOL_INTEGRATION"

/// Whether the gated real-model suite is enabled for this run.
var multitoolIntegrationEnabled: Bool {
    ProcessInfo.processInfo.environment[multitoolIntegrationEnvVar] != nil
}

/// The deliberately small, tool-calling-capable `mlx-community` models this
/// suite resolves — plan.md M6.5: "small tool-calling-capable instruct
/// models." `MultiToolAgent`'s tool-calling is plain prompted text (the
/// `ACTION:`/`TASK:`/`CODE:` convention, or a guided JSON turn) rather than a
/// model's own native function-calling API, so any capable small instruct
/// model qualifies — the *same* generation/embedding refs Router's own gated
/// suite already downloads for its `standard`/`flash`/`embedding` slots
/// (`IntegrationTests.swift`'s `TinyModels`), reused here so a machine that
/// already ran Router's suite shares the cached weights rather than fetching
/// a second set.
private enum TinyModels {
    static let generation: ModelRef = "mlx-community/SmolLM-135M-Instruct-4bit"
    static let embedding: ModelRef = "mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ"
}

/// The tiny co-fitting profile this suite resolves once per test — mirrors
/// Router's own `tinyProfile`. A modest `context` keeps every slot's KV
/// footprint small so the trio comfortably co-fits.
let multitoolTinyProfile = ProfileDefinition(
    name: "multitool-integration-tiny",
    description: "Deliberately tiny, tool-calling-capable models for the gated M6.5 integration suite.",
    standard: [TinyModels.generation],
    flash: [TinyModels.generation],
    embedding: [TinyModels.embedding],
    context: 2048
)

/// One resolved, live `Router` + `LanguageModelProfile` pair, together with
/// the recording root its sessions write their JSONL transcript under —
/// everything a gated scenario needs to run `MultiToolAgent.respond(to:)` (or
/// drive a `MetadataSearcher<APISurface.Entry>` in `.selection` mode
/// directly) and then read the resulting trace back via `TranscriptAnalyzer`.
struct LiveRouterFixture {
    /// The router that resolved `profile` — its `id` roots the recording
    /// tree `transcriptEvents()` reads back.
    let router: Router
    /// The resolved, resident profile — release via `tearDown()`.
    let profile: LanguageModelProfile
    /// The durable transcripts root passed to `Router.init(recordingsDir:)`.
    private let recordingsDir: URL

    /// Resolves `multitoolTinyProfile` over a real, live `LiveModelLoader` —
    /// the `#hubDownloader()`/`#huggingFaceTokenizerLoader()` macros build a
    /// real Hugging Face Hub client + tokenizer loader, mirroring Router's
    /// own gated `IntegrationTests.endToEnd()`.
    ///
    /// - Returns: the resolved fixture.
    /// - Throws: whatever `Router.resolve(_:reporting:)` throws — including
    ///   `GenerationError.notWiredForLiveInference` if the live decode path
    ///   isn't wired up in this environment (plan.md M6.5's typed skip
    ///   reason).
    @MainActor
    static func resolve() async throws -> LiveRouterFixture {
        let cacheDir = Self.makeTempDir()
        let recordingsDir = Self.makeTempDir()
        let loader = LiveModelLoader(
            downloader: #hubDownloader(),
            tokenizerLoader: #huggingFaceTokenizerLoader()
        )
        let router = Router(
            cacheDir: cacheDir,
            recordingsDir: recordingsDir,
            recordingLevel: .full,
            loader: loader
        )
        let progress = ResolutionProgress()
        let profile = try await router.resolve(multitoolTinyProfile, reporting: progress)
        return LiveRouterFixture(router: router, profile: profile, recordingsDir: recordingsDir)
    }

    /// Releases the resolved profile, evicting its three resident models.
    /// Call once a scenario is done with this fixture, on every exit path
    /// (success, assertion failure, or thrown error).
    func tearDown() async {
        await profile.release()
    }

    /// Reads back this fixture's whole recorded run as a totally-ordered
    /// event stream — `MergedTranscript.merged(under:)` over this router's
    /// own recording root (`recordings/<routerId>/`).
    ///
    /// - Returns: every recorded event, ordered by `(ts, seq)`.
    /// - Throws: if a transcript file can't be read or decoded.
    func transcriptEvents() throws -> [TranscriptEvent] {
        try MergedTranscript.merged(under: recordingsDir.appendingPathComponent(router.id.description))
    }

    /// Creates a unique temporary directory.
    private static func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FMMultitoolIntegration-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
