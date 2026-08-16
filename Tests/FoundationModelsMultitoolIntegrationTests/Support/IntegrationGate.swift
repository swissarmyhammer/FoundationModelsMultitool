import Foundation
import HuggingFace
import MLXHuggingFace
import MLXLMCommon
// Load-bearing although this file names no `MLXVLM` symbol: keep it.
// The pinned generation model may be registered in `VLMModelFactory`
// alone, and `MLXLMCommon`'s `ModelFactoryRegistry` finds its trampolines
// with `NSClassFromString` — a module the linker dropped is silently
// absent from that list, and the id then throws `unsupportedModelType`
// after paying for the whole download.
import MLXVLM
import Testing
import Tokenizers

import FoundationModelsRouter
@testable import multitool_cli

/// The opt-in environment variable enabling this gated, real-model suite —
/// plan.md M6.5: "opt-in via env var (e.g. MULTITOOL_INTEGRATION=1)". Unset
/// (the default, and on any network/GPU-less/CI box), the whole suite is
/// skipped, so `swift test` stays green with zero downloads. Mirrors
/// Router's own gate
/// (`../FoundationModelsRouter/Tests/FoundationModelsRouterIntegrationTests/IntegrationTests.swift`'s
/// `FM_ROUTER_INTEGRATION_TESTS`).
let multitoolIntegrationEnvVar = "MULTITOOL_INTEGRATION"

/// Whether the gated real-model suite is enabled for this run.
///
/// **Run this suite with `--no-parallel`.** The command is
/// `MULTITOOL_INTEGRATION=1 swift test --no-parallel`, and the flag is not a
/// preference.
///
/// The reason is not GPU contention — ``LiveProfileTurnstile`` below already
/// admits one live profile at a time, across suite boundaries. The reason is
/// **what the clock counts**. Swift Testing runs suites concurrently by default
/// and starts a test's `.timeLimit` when the test starts; every scenario takes
/// the turnstile from *inside* its own test body, by way of
/// `LiveRouterFixture.resolve()`. So a suite's reported duration is its own
/// work plus however long it queued behind the other suites, and its time limit
/// is spent on both.
///
/// Measured on 2026-08-16, the same commit both ways:
///
///   suite                        parallel   --no-parallel
///   Gated async fan-out             443.5s          71.4s
///   Gated elevation-in-code-mode    371.2s          64.2s
///   Gated search-then-call (x4)     661.0s         283.1s
///   Selection tier prefix-reuse      85.6s          16.5s
///   Gated nested-generation probe   >180s(*)        28.1s
///
/// (*) exceeded its three-minute limit and was recorded as a failure.
///
/// Read those columns as queue time removed, not as work made faster: whole-run
/// wall time was 661s parallel against 852s serial, so the actual generation
/// cost barely moved. What moves is attribution. Under parallel suites a tight
/// limit fires on queueing rather than on the scenario, the failure reads
/// exactly like a hang, and it lands on whichever suite holds the tightest
/// ceiling rather than on whichever scenario is slow. Two suites failed that
/// way before the flag was tried, and both pass with it.
var multitoolIntegrationEnabled: Bool {
    ProcessInfo.processInfo.environment[multitoolIntegrationEnvVar] != nil
}

/// The deliberately small, tool-calling-capable `mlx-community` models this
/// suite resolves — plan.md M6.5: "small tool-calling-capable instruct
/// models." The suite drives Apple's own native tool-calling loop through a
/// real `LanguageModelSession` (the retired `MultiToolAgent`'s prompted-text
/// `ACTION:`/`TASK:`/`CODE:` convention is gone), so the pinned `standard`
/// model must be genuinely trained for native function calling, not merely
/// instruction-following.
///
/// `generation` deliberately does *not* reuse Router's own gated suite's
/// pinned `SmolLM-135M-Instruct-4bit` (`IntegrationTests.swift`'s
/// own `TinyModels`): empirically, on this suite's live-hardware run
/// (`exbtj1n`'s gated pass), that 135M model could not reliably follow even
/// the single-tool `ACTION:`/`TASK:`/`CODE:` convention — its `tolerantParse`
/// turns degenerated into unrelated hallucinated prose (and, in one repair
/// scenario, thousands of repeated `0` characters) rather than ever emitting
/// an `ACTION:` line, and its `.guided` turns looped calling `searchTools` with
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
///
/// **Native-tool-calling era: the pins split per slot.** After the suite's
/// port to the native `LanguageModelSession` design, `Qwen2.5-1.5B-Instruct-
/// 4bit` proved unable to ground its `runCode` snippets in the discovered
/// `tools.*` surface at all — across every instruction variant tried on real
/// hardware it `console.log`ged invented answers, `fetch`ed imaginary
/// external APIs, or hardcoded made-up data, and the snippet scan now called
/// `NativeTranscript.typedToolPaths(in:)` came back empty in every run (tasks
/// `9hchxj6`/`k4mj1gm`) — that pin never so much as *wrote* a `tools.*` call
/// site, let alone ran one, so the lexical scan and the `ScenarioCallLog`
/// recorder that now grades grounding agree on it. Swapping
/// `generation` to the natively tool-calling-trained
/// `Qwen3-4B-Instruct-2507-4bit` (~2.3GB) qualitatively fixed grounding —
/// its snippets genuinely call the discovered `tools.*` functions — taking
/// `SearchThenCallTests` from a stable 0/4 to a stochastic 1-3/4 per run.
/// But the same 4B is *worse* at the selection tier's grammar-constrained
/// id picking (it returns empty `{"ids": []}` selections where the 1.5B
/// picks correctly and decisively), so the pins split per slot: `standard`
/// (the main tool-calling session) runs the tool-calling pin, `flash` (the
/// selection tier) keeps the 1.5B — each model where it is empirically
/// strong.
///
/// **Outcome-based rescoring dethroned the 4B.** When the suite's
/// assertions moved from route (tool ordering, exact call sets) to outcome
/// (a valid, fixture-grounded answer — see `runNativeIntegrationScenario`),
/// the 4B's apparent 3/4 collapsed to 0/4: it reliably invokes the right
/// `tools.*` functions, then mis-destructures their declared return shapes
/// (reading `.temperature` off the result against the declared `tempC`),
/// reads `undefined`, and answers "I'm unable to retrieve…" — approved
/// route, invalid answer, every run. `Qwen3-30B-A3B-Instruct-2507-4bit`
/// (~17GB, 3.3B active, the same 2507 instruct recipe) scores 2/4 under
/// outcome assertions with genuinely valid answers — the weather fixture's
/// exact 31°C, a genuinely invoked booking confirmation for repair — and its
/// failures are honest clarifying-question deflections, never
/// hallucinations. `standard` therefore moves to the 30B; decode speed is
/// comparable (3.3B active).
///
/// **Tool-owned contract promoted a dense 27B.** After the tool-use
/// contract moved onto the tools themselves — the full behavioral essence in
/// the `searchTools`/`runCode` descriptions, which is now the whole of it (task
/// `k4mj1gm`, then `tkrdwb8`) — a model sweep under the shipped config found
/// `Qwen3.6-27B-mxfp4` scoring a clean
/// 4/4, every scenario opening with `searchTools`, no wrong-guessing,
/// announce-then-stop, or over-refusal. It doubles the 30B-A3B's 2/4, and
/// being a dense model it follows through reliably where the 3.3B-active
/// MoE varies run to run (the 35B-A3B hovered at 3-4/4). At mxfp4 it is
/// ~half the weight and memory bandwidth of the 27B-mxfp8 that also hit 4/4
/// but took ~4x the wall time. `standard` therefore moves to the dense 27B.
///
/// `selection` uses the same dense 27B as `generation` (human-directed
/// 2026-08-10). The selection tier answers *which* catalog entries a
/// `searchTools` query wants, and it was the one slot still served by the old
/// 1.5B — a model two capability generations below the one whose answers it
/// feeds. Sharing one `ModelRef` across both slots also means one resident
/// model rather than a swap between generation and selection on every search.
///
/// **Muse Glimmer replaces the Qwen pair.** Both generation slots now name
/// `Muse-Glimmer-30B-mxfp4`, the same model Router's own gated suite pins
/// (`../FoundationModelsRouter/Tests/FoundationModelsRouterIntegrationTests/
/// Support/RealModels.swift`), for a prompt-cache reason the 27B cannot
/// meet: Qwen3.5/3.6 give their linear/GDN layers a `MambaCache`, which is
/// not trimmable, and one non-trimmable entry stops prefix reuse for the
/// whole cache list — so `PrefixReuseTests` had nothing left to measure.
/// Muse Glimmer has no recurrent layers, so every entry in its cache list is
/// trimmable, and its ATEM tool protocol carries a reuse rule written for
/// tool continuations — which is what every scenario in this target is.
/// It is a vision-language model driven text-only here, deliberately: its
/// processor returns a pure-text input when no image is supplied. Being
/// registered in `VLMModelFactory` alone, it reaches the runtime factory
/// registry only because `Package.swift` links `MLXVLM` (see
/// `liveLoaderMLXProducts`) and this file imports it below.
///
/// **One model in both slots, and the hang that argued against it is fixed.**
/// Sharing one `ModelRef` is what the human asked for and what the code below
/// does: one resident model rather than a swap between generation and selection
/// on every search.
///
/// It did hang, and for a while nobody knew why. A gated scenario sat 15
/// minutes at 0% CPU with 18.8GB resident, 98% of system memory free and zero
/// swap, every thread parked and the MLX scheduler on a condition variable,
/// with the recorded transcript stopping at the selection fork. That bought a
/// temporary split onto two models, and a run of wrong explanations.
///
/// **The cause was Router's `generationGate`, and it is now understood, fixed
/// and covered.** A resident container carries one `AsyncSemaphore(value: 1)`.
/// `beginTurn()` takes its single permit and holds it for the whole turn,
/// tool rounds included. `searchTools` generates from *inside* a tool call on
/// that same container, so it waited for a permit only the turn's end could
/// free, and the turn could not end until the tool returned. Sampled directly
/// with `@testable import FoundationModelsRouter`: `permits=0 waiters=1` for
/// the life of the run, across 33 samples.
///
/// Router fixed it on their `^1zt7vyg` by lending the permit to a nested turn
/// on another session rather than releasing it, so the count stays exact.
/// Verified from here: `NestedGenerationProbeTests` — which holds no grammar
/// anywhere, and so isolates the gate and nothing else — parked 165.4s and
/// 166.5s before the fix and returns in about 28s after it. Seven gated suites
/// that had all deadlocked went green in the same run.
///
/// **Two earlier explanations were wrong, and are recorded so they are not
/// tried again.** The first blamed a `SerialAccessContainer` lock held across
/// tool rounds; the fork refuted it with `ToolBodyContainerReentryTests`
/// (`mlx-swift-lm` `ca8e22f`), a real container, session and tool body
/// generating on the same model, passing in 0.077s against a proven-non-vacuous
/// guard. The second blamed the guided/xgrammar path's shared per-model caches,
/// on the reasoning that the selection tier runs under a grammar; the probe
/// carries no grammar at all and hung identically, which ended that one.
///
/// `discoveryUnderDistractors` remains the test any selection pin has to pass.
///
/// **Qwen3.8-27B-mxfp4 measured against Muse, 2026-08-16.** One full
/// serialized gated run each, same Router `8db8094`, same fixtures. Both
/// answered every scenario validly and grounded, so the outcome grading does
/// not separate them. The route diagnostics do:
///
///   scenario                    Muse calls/thrash   Qwen calls/thrash
///   singleCallWeather                  3 / 0               3 / 0
///   fanOutOverTwoStockTools            3 / 0               4 / 0
///   composeChain                       4 / 0               6 / 1
///   discoveryUnderDistractors          4 / 0               6 / 1
///   repairFromTripProneTool            3 / 0               8 / 1
///
/// Both are clean on over-refusal, answering without calling,
/// announce-then-stop, invented paths and wrong-form answers, and both open
/// every scenario with `searchTools`. But `thrash` fires above twice the
/// two-call floor — the budget for one repair cycle — and Qwen exceeds it on
/// three scenarios of five while Muse exceeds it on none. On the repair
/// scenario Qwen spent 8 calls against Muse's 3.
///
/// Qwen is the faster of the two per scenario: elevation 39.8s against
/// 64-70s, CLI smoke 51.3s against 61-63s, the nested-generation probe 16.4s
/// against 26-28s, search-then-call 265.6s against 283-299s. Respond
/// self-drain went the other way, 211.7s against 146-169s. Whole-run totals
/// (1863.9s Qwen, 1604s Muse) are not comparable as printed: Qwen's first
/// suite paid 785.4s to bring cold weights off disk, where Muse's had been
/// warmed by repeated runs.
///
/// **Two things this comparison does not establish.** It is one run each, and
/// Muse's own numbers moved run to run. And `PrefixReuseTests` passing on
/// Qwen3.8 needs explaining rather than banking: the pin moved to Muse
/// because Qwen3.5/3.6 gave their linear/GDN layers a non-trimmable
/// `MambaCache`, which left that suite nothing to measure. Either the
/// architecture changed or the suite is not measuring what this file claims.
/// Settle that before treating the prefix-reuse result as a reason to stay.
///
/// Neither reference carries an `@revision`, so both track their repository's
/// default revision rather than a fixed commit — these are model *choices*,
/// not version locks, whatever the surrounding prose calls them.

/// The profile this suite resolves once per test.
///
/// **`CLIRunner.demoProfile` itself — this suite keeps no pin of its own.**
/// The models, the slot layout and the `nil` context all come from the value
/// the CLI ships, so a gated run measures the configuration a host really
/// gets and a model swap is one edit in one file
/// (`CLIRunner.generationModel`).
///
/// It was two definitions until 2026-08-16, and nothing held them together:
/// the CLI named its models and this file named its own, so the suite was
/// free to grade a configuration no host had. The measurement history for
/// every model that has held the slot stays here, above, because it is a
/// record of *this suite's* runs; only the choice moved.
let multitoolTinyProfile = CLIRunner.demoProfile

/// The one-at-a-time turnstile every gated scenario passes through before it
/// puts a live profile on the GPU.
///
/// Swift Testing runs *suites* in parallel; `.serialized` only orders the tests
/// **inside** one suite. With five gated suites in this target, five live
/// profiles would otherwise resolve and generate at once, and measured on real
/// hardware that is not merely slow — it is wrong. In a five-at-once run every
/// scenario degraded together: `searchTools` stopped preceding `runCode` in all of
/// them, snippets called function names that exist in no fixture
/// (`getInventory`, plus `getTrip` and `getWeather` — invented names when that
/// run was measured, real fixture names since the 2026-08-07 rename recorded on
/// task `tkrdwb8`), and the replies came back fluent but ungrounded. The
/// same suites run three-at-once, or one at a time, called the real fixtures
/// and answered from them. One resident profile at a time is
/// therefore a correctness requirement of this target, not a courtesy — and it
/// is the same property `SearchThenCallTests`' own `.serialized` documents
/// ("only one profile is resident at a time per `Router`"), extended across
/// suite boundaries where a suite trait cannot reach.
///
/// A counting semaphore of one, written as an actor: both operations are
/// decisions on the actor's own state, and a waiter parks on a continuation
/// rather than blocking a thread.
actor LiveProfileTurnstile {
    /// The one turnstile the whole target shares.
    static let shared = LiveProfileTurnstile()

    /// Whether a profile currently holds the turnstile.
    private var isOccupied = false

    /// The scenarios parked until the holder leaves, in arrival order.
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Takes the turnstile, waiting for the current holder to leave if there is
    /// one. The caller owes a matching ``leave()``.
    func enter() async {
        guard isOccupied else {
            isOccupied = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    /// Gives the turnstile up, handing it straight to the longest-waiting
    /// scenario if any is parked.
    func leave() {
        guard waiters.isEmpty else {
            waiters.removeFirst().resume()
            return
        }
        isOccupied = false
    }
}

/// One resolved, live `Router` + `LanguageModelProfile` pair, together with
/// the recording root its sessions write their JSONL transcript under —
/// everything a gated scenario needs to build a native `MLXLanguageModel` +
/// `LanguageModelSession` over `profile.standard` (via `CLIRunner
/// .makeMLXLanguageModel(for:)`, `searchToolsTool`'s own selection tier over
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
    /// Takes ``LiveProfileTurnstile/shared`` before resolving anything, so at
    /// most one gated scenario in the target has a profile resident at a time;
    /// ``tearDown()`` gives it back. A resolution that throws gives it back
    /// itself, since its caller is left with no fixture to tear down.
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
        await LiveProfileTurnstile.shared.enter()
        do {
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
        } catch {
            await LiveProfileTurnstile.shared.leave()
            throw error
        }
    }

    /// Releases the resolved profile, evicting its three resident models, and
    /// gives ``LiveProfileTurnstile/shared`` back to the next waiting scenario.
    /// Call once a scenario is done with this fixture, on every exit path
    /// (success, assertion failure, or thrown error).
    func tearDown() async {
        await profile.release()
        await LiveProfileTurnstile.shared.leave()
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
