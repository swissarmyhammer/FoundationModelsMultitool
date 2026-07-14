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
/// model qualifies.
///
/// `generation` deliberately does *not* reuse Router's own gated suite's
/// pinned `SmolLM-135M-Instruct-4bit` (`IntegrationTests.swift`'s
/// `TinyModels`): empirically, on this suite's live-hardware run
/// (`exbtj1n`'s gated pass), that 135M model could not reliably follow even
/// the single-tool `ACTION:`/`TASK:`/`CODE:` convention — its `tolerantParse`
/// turns degenerated into unrelated hallucinated prose (and, in one repair
/// scenario, thousands of repeated `0` characters) rather than ever emitting
/// an `ACTION:` line, and its `.guided` turns looped calling `findAPIs` with
/// a nonsense `task` value instead of ever reaching a `final`/`runCode` turn.
/// A first step up, `Qwen2.5-0.5B-Instruct-4bit`, was a large improvement
/// (reliable `ACTION:` lines, coherent single-tool scenarios) but still
/// occasionally ran on past a natural stop point on harder multi-turn
/// scenarios and, under `.guided`, sometimes populated the wrong optional
/// field (`text` instead of `code`) for a `runCode` turn.
/// `Qwen2.5-1.5B-Instruct-4bit` was, for a time, the settled choice: still
/// squarely in plan.md's "few-hundred-MB-to-low-GB instruct model" range
/// (~870MB in 4-bit), and empirically the most reliable of the three at this
/// suite's full ReAct-style search-then-call loop. Router's own suite only
/// needs a model to produce *any* non-empty response (`endToEnd()` asserts a
/// non-empty reply, valid guided schema-parse, embed dimension — never
/// coherent multi-step reasoning), so its far lower capability bar tolerates
/// a model this suite's tool orchestration cannot; hence the diverging pin.
///
/// A first retry to `mlx-community/Qwen3.5-2B-mxfp4` failed outright at
/// Router's pre-flight co-fit sizing step, before any download or inference:
/// that repo's `config.json` is VLM-shaped (nested `text_config`, hybrid
/// linear/full-attention layers) and `FoundationModelsRouter`'s
/// `RepoMetadata` parser (at the time) only read top-level
/// `num_hidden_layers`/`num_attention_heads`, so it threw
/// `RepoMetadataError.metadataUnavailable` for both the `standard` and
/// `flash` slots — a hard regression, not a partial improvement, so that
/// attempt was reverted.
///
/// This retry: `FoundationModelsRouter`'s `RepoMetadata` (`Sizing/
/// RepoMetadata.swift`) now falls back to `text_config` when the top level
/// lacks those fields (mirroring HF transformers' `get_text_config()`
/// semantics, including hybrid `layer_types` KV-cache accounting), and its
/// live loader's `maxTokens` is no longer a hardcoded 1024-token cap —
/// `LiveModelLoader`'s `defaultMaxTokens` is now 8192, matching this
/// profile's own `context`. With both upstream fixes in place, `Qwen3.5-2B-
/// mxfp4` *does* now resolve and load successfully — the `text_config`
/// sizing fix is confirmed working end to end (`standard`/`flash` both
/// co-fit at ~2.1GB). But three full gated-suite runs against it showed a
/// clear, consistent *capability* regression versus `Qwen2.5-1.5B-
/// Instruct-4bit`: `SearchThenCallTests` failed almost every scenario/format
/// combination in all three runs (`.incompleteOutput`, `maxTurnsExceeded`,
/// and repair-budget exhaustion on both `.tolerantParse` and `.guided`),
/// with per-scenario runtimes varying wildly (tens of seconds to 25+
/// minutes) — this 2B hybrid-attention `mxfp4` checkpoint is markedly slower
/// per-token and follows the `ACTION:`/`TASK:`/`CODE:` and guided-JSON
/// conventions noticeably less reliably than the settled 1.5B pin. A
/// dedicated `CLISmokeTests` check (isolating a pre-existing, unrelated
/// stale-cache read issue in the persistent `~/Library/Caches/
/// FoundationModelsRouter` repo-metadata cache, cleared to get a clean
/// read) confirmed this isn't just a cache artifact: even resolved and
/// loaded cleanly, the model twice answered the demo prompt without ever
/// calling `runCode` — once asking a clarifying question, once hallucinating
/// "Sydney" — rather than composing the described `tools.*` calls. Given
/// this, the pin reverts to `Qwen2.5-1.5B-Instruct-4bit`, the previously
/// verified-reliable choice; see `exbtj1n`'s task comments for the full
/// repeated-run results this retry produced. `embedding` is unaffected and
/// still shares Router's own pinned ref.
///
/// A further retry stepped up within the same fixed Qwen3.5 architecture
/// family to `mlx-community/Qwen3.5-9B-4bit` — same `text_config`-nested
/// VLM-shaped config as the 2B `mxfp4` checkpoint (so it resolves via the
/// same now-fixed Router sizing path), but a meaningfully larger backbone,
/// on the theory that the 2B's failures were a raw-capability shortfall
/// rather than an architecture-family mismatch. Confirmed: it resolves and
/// loads cleanly (~5.9GB of `*.safetensors`, both shards). Three full gated
/// runs gave a genuinely mixed picture rather than a clean win or a clean
/// regression: `PrefixReuseTests` passed all 3 real attempts and
/// `CLISmokeTests` passed 2 of 3 (the third run's failure — and that run's
/// blanket "no *.safetensors weight files in the repo tree" sizing error
/// across every non-embedding resolution — was a one-off, non-reproducing
/// artifact, most likely transient HF API/rate-limit pressure from a burst
/// of resolution calls right after a 485-second first test, not a Router or
/// model defect: a manual, repeated `curl` against the same tree-listing
/// endpoint immediately afterward succeeded every time, and neither of the
/// other 2 runs reproduced it). Discounting that one-off run, the real
/// signal is in `SearchThenCallTests`: `.tolerantParse` did markedly better
/// than the settled 1.5B pin (7 of 8 across the 2 clean runs — including the
/// hardest ~20-distractor discovery scenario passing both times, once in
/// 692s), but `.guided` did not improve (2 of 8) and failed repeatedly on
/// the same already-documented blank-`task`-field schema gap. Wall time
/// exploded: whole-suite runs took 16 and 29 minutes (individual scenarios
/// up to 692s), dwarfing the 1.5B pin's turnaround and stretching well past
/// plan.md M6.5's "small tool-calling-capable instruct model" framing for a
/// ~5.9GB checkpoint. Given no full clean run (same as the 1.5B pin's own
/// history), a real but format-scoped improvement offset by a real
/// format-scoped non-improvement, a new (likely infra, not model) flakiness
/// surface observed under load, and a large cost increase in wall time and
/// resident memory for that mixed result, this pin reverts to
/// `Qwen2.5-1.5B-Instruct-4bit` rather than keep the 9B model — see
/// `exbtj1n`'s task comments for the full repeated-run data. The
/// `.tolerantParse`-specific improvement is worth revisiting if a future
/// milestone ever scopes real-model runs to `.tolerantParse` only, or once
/// `.guided`'s conditional-field grammar gap is closed.
private enum TinyModels {
    static let generation: ModelRef = "mlx-community/Qwen2.5-1.5B-Instruct-4bit"
    static let embedding: ModelRef = "mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ"
}

/// The tiny co-fitting profile this suite resolves once per test — mirrors
/// Router's own `tinyProfile`. `context` is sized to comfortably fit this
/// suite's largest rendered prompt — the ~20-distractor discovery scenario's
/// assembled selection prefix plus its guided id-enum grammar's completion —
/// with headroom to spare; the co-fitting trio's combined KV footprint is
/// negligible next to the hardware this gated suite requires.
let multitoolTinyProfile = ProfileDefinition(
    name: "multitool-integration-tiny",
    description: "Deliberately tiny, tool-calling-capable models for the gated M6.5 integration suite.",
    standard: [TinyModels.generation],
    flash: [TinyModels.generation],
    embedding: [TinyModels.embedding],
    context: 8192
)

/// One resolved, live `Router` + `LanguageModelProfile` pair, together with
/// the recording root its sessions write their JSONL transcript under —
/// everything a gated scenario needs to build a native `MLXLanguageModel` +
/// `LanguageModelSession` over `profile.standard` (via `CLIRunner
/// .makeMLXLanguageModel(for:)`, `findAPIsTool`'s own selection tier over
/// `profile.flash`, and then read back the selection tier's own recorded
/// trace (`NativeTranscript.selections(in:slot:)`) — the main session itself
/// is never Router-vended, so it is never recorded here.
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
    /// - Throws: whatever `Router.resolve(profile:reporting:)` throws — including
    ///   `GenerationError.notWiredForLiveInference` if the live decode path
    ///   isn't wired up in this environment (plan.md M6.5's typed skip
    ///   reason).
    @MainActor
    static func resolve() async throws -> LiveRouterFixture {
        // `swift test`'s binary layout defeats mlx-swift's default metallib
        // lookup (see `MetalLibraryTestBootstrap`'s documentation) — must run
        // before any live model resolution touches the GPU device.
        _ = MetalLibraryTestBootstrap.ensureColocatedMetallib
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
        let profile = try await router.resolve(profile: multitoolTinyProfile, reporting: progress)
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
