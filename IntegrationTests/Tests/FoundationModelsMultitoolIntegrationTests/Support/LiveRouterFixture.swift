import Foundation
// Load-bearing although this file names no `MLXVLM` symbol: keep it.
// The pinned generation model may be registered in `VLMModelFactory`
// alone, and `MLXLMCommon`'s `ModelFactoryRegistry` finds its trampolines
// with `NSClassFromString` — a module the linker dropped is silently
// absent from that list, and the id then throws `unsupportedModelType`
// after paying for the whole download.
import MLXVLM
import Testing

import FoundationModelsExtras
import FoundationModelsMetadataRegistry
import FoundationModelsRouter
import TestConcurrency

/// The deliberately small, tool-calling-capable `mlx-community` models this
/// suite resolves — plan.md M6.5: "small tool-calling-capable instruct
/// models." The suite drives the shipped host contract — the vended tools
/// mounted on a `RoutedSession`, whose own native tool-calling loop runs the
/// turn (the retired `MultiToolAgent`'s prompted-text
/// `ACTION:`/`TASK:`/`CODE:` convention is gone), so the pinned `standard`
/// model must be genuinely trained for native function calling, not merely
/// instruction-following.
///
/// `generation` deliberately does *not* reuse Router's own gated suite's
/// pinned `SmolLM-135M-Instruct-4bit` (`IntegrationTests.swift`'s
/// own `TinyModels`): empirically, on this suite's live-hardware run
/// (`exbtj1n`'s real-model pass), that 135M model could not reliably follow even
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
/// live loader's `maxTokens` is no longer a hardcoded 1024-token cap — the
/// file-private `defaultMaxTokens` in `LiveModelLoader.swift`, which
/// `MLXFoundationModelsSessionBackend` applies whenever a caller supplies
/// none of its own, is now 8192, matching this profile's own `context`.
/// With both upstream fixes in place, `Qwen3.5-2B-mxfp4` *does* now resolve
/// and load successfully — the `text_config` sizing fix is confirmed
/// working end to end (`standard`/`flash` both
/// co-fit at ~2.1GB). But three full integration-suite runs against it showed a
/// clear, consistent *capability* regression versus `Qwen2.5-1.5B-
/// Instruct-4bit`: `SearchThenCallTests` failed almost every scenario/format
/// combination in all three runs (`.incompleteOutput`, `maxTurnsExceeded`,
/// and repair-budget exhaustion on both `.tolerantParse` and `.guided`),
/// with per-scenario runtimes varying wildly (tens of seconds to 25+
/// minutes) — this 2B hybrid-attention `mxfp4` checkpoint is markedly slower
/// per-token and follows the `ACTION:`/`TASK:`/`CODE:` and guided-JSON
/// conventions noticeably less reliably than the settled 1.5B pin. A
/// dedicated check of the former `CLISmokeTests` (isolating a pre-existing,
/// unrelated stale-cache read issue in the persistent `~/Library/Caches/
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
/// loads cleanly (~5.9GB of `*.safetensors`, both shards). Three full real-model
/// runs gave a genuinely mixed picture rather than a clean win or a clean
/// regression: the suite now called `SelectionForkPerCallTests` passed all 3
/// real attempts — which, then as now, graded no prefix reuse; see the
/// paragraph on it far below — and
/// the former `CLISmokeTests` passed 2 of 3 (the third run's failure — and
/// that run's blanket "no *.safetensors weight files in the repo tree" sizing
/// error across every non-embedding resolution — was a one-off, non-reproducing
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
/// **Muse Glimmer replaced the Qwen pair.** Both generation slots took
/// `Muse-Glimmer-30B-mxfp4`, the same model Router's own gated suite pins
/// (`../FoundationModelsRouter/Tests/FoundationModelsRouterIntegrationTests/
/// Support/RealModels.swift`), for a prompt-cache reason the 27B cannot
/// meet: Qwen3.5/3.6 give their linear/GDN layers a `MambaCache`, which is
/// not trimmable, and one non-trimmable entry stops prefix reuse for the
/// whole cache list. Muse Glimmer has no recurrent layers, so every entry in
/// its cache list is trimmable, and its ATEM tool protocol carries a reuse
/// rule written for tool continuations — which is what every scenario in
/// this target is.
///
/// **No suite in this target ever graded that swap, and this paragraph no
/// longer says one did.** It used to close by saying the `MambaCache` left
/// `PrefixReuseTests` "nothing left to measure", which reads as a model
/// choice resting on a measurement made here. That suite could not measure
/// prefix reuse either way, on either model — its successor,
/// `SelectionForkPerCallTests`, records in its own documentation exactly
/// what it cannot see and why. The cache-shape argument rests on the two
/// architectures and on `mlx-swift-lm`'s `f85fc50`, and never rested on
/// anything this target measured.
///
/// Muse Glimmer is a vision-language model, and was driven text-only here
/// deliberately: its processor returns a pure-text input when no image is
/// supplied. Being registered in `VLMModelFactory` alone, it reached the
/// runtime factory registry only because `Package.swift` links `MLXVLM` (see
/// the comment on the test target there) and this file imports it above. That link and
/// that import are still here, and still needed, for any pin with the same
/// property.
///
/// **One model in both slots was the shape until the work-queue Router, and it
/// is not the shape now.** Sharing one `ModelRef` gave one resident model
/// rather than a swap between generation and selection on every search. The
/// work-queue Router refuses the nested selection generation on the model that
/// the outer submission holds open
/// (`GenerationQueueError.waitInsideOpenSubmission(model:)`), so every
/// profile of this target now puts a different model in `standard` and
/// `flash`, and `ProfileSlotSeparationTests`
/// holds that. The history below is kept because it is the record of this
/// suite's runs.
///
/// It did hang, and for a while nobody knew why. An integration scenario sat 15
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
/// 166.5s before the fix and returned in about 28s after it. Seven integration
/// suites that had all deadlocked went green in the same run. The work-queue
/// Router then replaced the gate and the lent permit with the refusal, and
/// `NestedGenerationProbeTests` now asserts that refusal.
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
/// serialized real-model run each, same Router `8db8094`, same fixtures. Both
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
/// Qwen is the faster of the two per scenario: background 39.8s against
/// 64-70s, CLI smoke 51.3s against 61-63s, the nested-generation probe 16.4s
/// against 26-28s, search-then-call 265.6s against 283-299s. Respond
/// self-drain went the other way, 211.7s against 146-169s. Whole-run totals
/// (1863.9s Qwen, 1604s Muse) are not comparable as printed: Qwen's first
/// suite paid 785.4s to bring cold weights off disk, where Muse's had been
/// warmed by repeated runs.
///
/// **This comparison is one run each**, and Muse's own numbers moved run to
/// run, so nothing here is a reliability claim. Which of the two holds the
/// slot is stated in one place only, `generationModel` below; everything
/// above is the evidence behind that choice, never a second pin.
///
/// **And the old `PrefixReuseTests` passing on Qwen3.8 was not evidence of
/// prefix reuse.** That was worth checking rather than banking, and the check
/// came back against the suite: its assertion was `secondElapsed <=
/// firstElapsed`, which a cold first call satisfies on warm-up alone, with no
/// reuse anywhere. Measured, both models pass and neither passes decisively —
/// Muse `first=7.75s second=3.31s`, Qwen3.8 `first=5.81s second=3.58s`.
/// A second call that skipped a real prefill and one that merely followed a
/// warmed model produce the same verdict here.
///
/// The recorded entries could not rescue it either, and that was checked
/// against the shipped build rather than assumed. `TranscriptEvent` meters
/// `tokensIn`, `tokensOut` and `ms` and nothing else — no skipped-token
/// count, no cache-hit count, no prefill time. `tokensIn` is the whole
/// rendered prompt of the turn: Router subtracts two cumulative
/// `usage.input.totalTokenCount` snapshots, and that delta is the turn's own
/// whole render only because every fork on this path is a fresh session
/// starting at zero. Either way it reads the same whether a prefix was
/// reused or re-prefilled. The one figure that would answer the question,
/// `usage.input.cachedTokenCount`, is dropped by Router's live conformer,
/// `MLXFoundationModelsSessionBackend.usageTokenCounts()`, and is the
/// literal `0` at every emission site of the pinned `mlx-swift-lm`, whose
/// FoundationModels executor carries no prompt cache at all. So the suite
/// was renamed to `SelectionForkPerCallTests` and narrowed to what it can
/// hold: the selection tier's cached-root, `fork()`-per-call contract, read
/// off the recording, plus the timing comparison stated as a timing
/// comparison.
///
/// The rigorous instrument is in the fork, not here: `mlx-swift-lm`'s
/// `f85fc50` measures two-round reuse on real weights through
/// `MLXLMCommon.ChatSession` alone, and its verdict on Qwen3.6 was NO on two
/// independent counts. Round 2's render was not a prefix extension of round
/// 1's — they shared 4,703 of 4,705 tokens and still did not extend, because
/// round 1 ends with a `<think>` priming block exactly where round 2 writes
/// the assistant reply — and round 2 fed all 4,748 rendered tokens, skipped
/// none, and spent 11.59s on prefill against a cold control's 11.60s.
///
/// So the `MambaCache` story this file tells is real but incomplete: a
/// non-trimmable cache is the second of two causes, and the chat template is
/// the first. That matters because upstream has since added prompt-cache
/// work, and the fork's own assertions are written to be inverted "when
/// upstream starts caching" — but a template that does not extend defeats
/// reuse whatever the cache does.
///
/// No suite in this target can be cited for "prefix reuse works" on any
/// model, and `SelectionForkPerCallTests` least of all — it holds the
/// `fork()`-per-call mechanism and the fact that the second call is not
/// slower, which is all it can see. Cite `mlx-swift-lm`'s `f85fc50`, or
/// measure it again there.
///
/// **Measured again on Qwen3.8-27B-mxfp4, 2026-10-01 (card `^3vtvrzg`).** The
/// fork's executor now carries a prompt cache for each session, and it logs
/// each plan under `com.apple.FoundationModels-MLX:ExecutorPromptCache`. The
/// log of `SearchThenCallTests/singleCallWeather` (a test the same card later
/// merged into `discoveryUnderDistractors`; `mlx-swift-lm` `a1f77ad`,
/// Router `8821ccc`) read: call 1 `rendered=945 reused=0 fed=945 rule=cold`,
/// call 2 `rendered=1228 reused=1016 fed=212 rule=splice`, call 3
/// `rendered=1412 reused=1284 fed=128 rule=splice`. Thus each turn of a
/// session after the first feeds only its new tokens on the 27B. The Router
/// transcript cannot show it: its `generationCall` entry writes "fed N
/// tokens" for the whole context, because Router reads only
/// `usage.input.totalTokenCount`. The selection tier reuses nothing: each
/// selection call is a guided pass, and a guided pass builds its own cache
/// (`rule=guided`).
///
/// Neither reference carries an `@revision`, so both track their repository's
/// default revision rather than a fixed commit — these are model *choices*,
/// not version locks, whatever the surrounding prose calls them.

/// The generation model of the `standard` slot of `multitoolTinyProfile`:
/// the model that drives the main session of every suite that grades an
/// answer.
///
/// The measurement history above is the evidence behind this choice. This
/// constant is the choice, and the history is never a second pin.
///
/// No `@revision`: this tracks the repository's default revision, so it is a
/// model *choice* rather than a version lock.
let generationModel: ModelRef = "mlx-community/Qwen3.8-27B-mxfp4"

/// The generation model of the `flash` slot of `multitoolTinyProfile`, which
/// the selection tier of `searchTools` runs on.
///
/// **It must not be `generationModel`.** `searchTools` is synchronous, so its
/// selection session runs inside the open submission of the main session on
/// `standard`. Router runs the work of each model on its own FIFO queue, and
/// refuses at once a wait on the queue of the open submission
/// (`GenerationQueueError.waitInsideOpenSubmission`). A selection session on a
/// different model waits its turn on its own queue, and the search completes.
/// `ProfileSlotSeparationTests` holds the two slots apart.
///
/// This model, because `AgentSurfaceDiscoveryTests` grades the selection tier
/// on it.
///
/// No `@revision`, for the same reason as `generationModel`.
let flashModel: ModelRef = "mlx-community/Qwen3-4B-4bit"

/// The embedding model of every profile of this target, unchanged across
/// every generation-model swap and shared with Router's own gated suite, so
/// the weights are already cached.
let embeddingModel: ModelRef = "mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ"

/// The profile this suite resolves once per test.
///
/// **This target names each model in one place: `generationModel`,
/// `flashModel` and `embeddingModel` above, and `plumbingProbeModel` below.**
/// Each profile of this target names its models through those constants, so
/// a model swap is one edit in one file.
///
/// Two models, and they must stay different: `standard` drives the main
/// session, and `flash` runs the selection tier of `searchTools`. See
/// `flashModel`.
///
/// `nil` context, not a number: resolve the model's own context window rather
/// than impose one. A pinned figure is always wrong on the wrong side — too
/// small, and a generation turn loses the tool definitions and the discovery
/// output it must act on. `ProfileDefinition.defaultContext` is the fallback
/// when the lookup fails, so this cannot resolve to nothing.
///
/// The measurement history for every model that has held the slot stays
/// here, above, because it is a record of *this suite's* runs.
let multitoolTinyProfile = ProfileDefinition(
    name: "multitool-tiny",
    description: "Tool-calling-capable models for the integration suite.",
    standard: [generationModel],
    flash: [flashModel],
    embedding: [embeddingModel],
    context: nil
)

/// The small model of the plumbing probes — in `flash` of
/// `plumbingProbeProfile` and in `standard` of `agentDiscoveryProfile` —
/// **not a second generation pin, and never a stand-in for
/// `generationModel`.**
///
/// `generationModel` remains the single place this target names the model a
/// *host* runs, and every suite that grades an answer resolves it
/// through `multitoolTinyProfile` above. This constant is a different kind of
/// thing: it names a model for the suites that grade **plumbing**, where the
/// model's only job is to emit tokens and call the one tool mounted, and where
/// nothing about the verdict depends on how well it answers.
///
/// **The test that decides which constant a suite takes is plumbing versus
/// intelligence.** A suite asserting that a valid, fixture-grounded answer came
/// back is making a capability claim, and a small model would fail it for
/// reasons that say nothing about this package —
/// `SearchThenCallTests` and `InBandCollectionCanaryTests` are of that kind,
/// and `^wnfzwxg` turned on exactly which model produced which answer.
/// `SelectionForkPerCallTests` is excluded for a third reason: cache behaviour
/// is architecture-specific, so a different model there measures a different
/// thing. None of them may take this constant.
///
/// Three suites pass the test today. `NestedGenerationProbeTests` asks whether
/// a nested generation on the held model is refused at once — a question about
/// Router's generation queue, answered identically by any model that gets as
/// far as calling the tool. `OverBudgetSurfaceDiscoveryTests` asks whether a
/// catalog above the selection budget answers matches that are spliced one
/// time, are unique, stand inside the limit and name real paths — properties of
/// this package's own splice, which hold whatever the model picks; that suite
/// grades no pick and asserts on no answer. `UnknownToolHintLiveTests` asks
/// what the did-you-mean hint names for a wrong `tools.*` path, and that path
/// generates nothing at all: its ranker is retrieval-only, so the reading is
/// the embedder's, and every profile of this target names the same
/// `embeddingModel`.
///
/// Qwen3-1.7B rather than a smaller model of another family: the shipped pin is
/// Qwen3.8, so this exercises the same chat/tool template shape the product
/// does, which is the part of the path a probe should not vary by accident.
///
/// No `@revision`, exactly as `generationModel` carries none — a model
/// choice, not a version lock.
let plumbingProbeModel: ModelRef = "mlx-community/Qwen3-1.7B-4bit"

/// The model in the `standard` slot of `plumbingProbeProfile`: `flashModel`.
///
/// **It must not be `plumbingProbeModel`, which holds `flash`.** `searchTools`
/// is synchronous: it runs the selection tier on `flash` from inside a tool
/// call of the session on `standard`. When one model serves both slots, that
/// nested generation needs the model that the outer submission holds open, and
/// the work-queue Router refuses it at once with
/// `GenerationQueueError.waitInsideOpenSubmission(model:)`. A later Router may
/// refuse such a profile at `Router.resolve`. `ProfileSlotSeparationTests`
/// holds every profile of this target to two different models.
///
/// Why this model: it is a small tool-calling model of the same Qwen3 family
/// as `plumbingProbeModel`, and it is already in the local cache from every
/// `multitoolTinyProfile` run, so the change costs no download. Its only job
/// in a probe is to emit tokens and call the one tool mounted.
let plumbingProbeStandardModel: ModelRef = flashModel

/// The profile the plumbing probes resolve.
///
/// `standard` is `plumbingProbeStandardModel` and `flash` is
/// `plumbingProbeModel`: two different models, for the reason
/// `plumbingProbeStandardModel` states. `flash` keeps the model the plumbing
/// suites were measured on, because the selection tier on `flash` is what
/// `OverBudgetSurfaceDiscoveryTests`, `RetrievalTextSurfaceDiscoveryTests` and
/// `NoDescriptionSurfaceDiscoveryTests` read. The shared embedding model and a
/// `nil` context, so the model's own window is resolved, as
/// `multitoolTinyProfile` does.
///
/// The embedding model is `embeddingModel` unchanged: it is already
/// resident from every other real-model run on this machine, so naming it here costs
/// nothing and naming a second one would cost a download for no reading.
let plumbingProbeProfile = ProfileDefinition(
    name: "multitool-plumbing-probe",
    description: "Small models for the gated probes that grade plumbing rather than capability.",
    standard: [plumbingProbeStandardModel],
    flash: [plumbingProbeModel],
    embedding: [embeddingModel],
    context: nil
)

/// The flash model of the `acp-agent` default profile — `AgentConfiguration
/// .defaultFlash` in `FoundationModelsACPAgent` — which is the model that
/// answered eight of ten `searchTools` calls with an empty selection on the
/// SWE-bench run card `^zqz1zan` records.
///
/// **Not a third generation pin.** `generationModel` names the model
/// a host runs, and `plumbingProbeModel` names the model the plumbing probes
/// resolve. This constant names the model one suite grades the *selection
/// tier* on: `AgentSurfaceDiscoveryTests` asks whether that tier, given the
/// whole files-and-shell catalog and the agent's own recorded queries, selects the
/// write, edit and shell entries. That is a capability claim about this one
/// model, so no other suite may take this constant, and this suite may take no
/// other model — a pass on the 27B says nothing about the 4B the agent ships.
///
/// No `@revision`, exactly as the two constants above carry none — a model
/// choice, not a version lock.
let agentFlashModel: ModelRef = flashModel

/// The profile `AgentSurfaceDiscoveryTests` resolves, built over
/// `agentFlashModel`.
///
/// `flash` is `agentFlashModel`, the model that suite grades. `standard` is
/// `plumbingProbeModel`, a different model, because `searchTools` runs the
/// selection tier on `flash` from inside a tool call of the session on
/// `standard`: when one model serves both slots, the work-queue Router refuses
/// that nested generation with
/// `GenerationQueueError.waitInsideOpenSubmission(model:)`, and a later Router
/// may refuse such a profile at `Router.resolve`. The agent's own profile puts
/// two different models in the two slots too. `plumbingProbeModel` because it
/// is small and already in the local cache; that suite calls `searchTools`
/// directly and grades no generation on `standard`.
///
/// The shared embedding model, so the profile names an embedder the way the
/// agent's profile does. `nil` context so the model's own window is resolved,
/// the same shape `multitoolTinyProfile` and `plumbingProbeProfile` take.
let agentDiscoveryProfile = ProfileDefinition(
    name: "multitool-agent-discovery",
    description: "The acp-agent flash model, for the suite that grades the selection tier on it.",
    standard: [plumbingProbeModel],
    flash: [agentFlashModel],
    embedding: [embeddingModel],
    context: nil
)

/// The one-at-a-time turnstile every integration scenario passes through before it
/// puts a live profile on the GPU.
///
/// Swift Testing runs *suites* in parallel; `.serialized` only orders the tests
/// **inside** one suite. With five integration suites in this target, five live
/// profiles would otherwise resolve and generate at once, and measured on real
/// hardware that is not merely slow — it is wrong. In a five-at-once run every
/// scenario degraded together: `searchTools` stopped preceding `runCode` in all of
/// them, snippets called function names that exist in no fixture
/// (`getInventory`, plus `getTrip` and `getWeather` — invented names when that
/// run was measured, real fixture names since the 2026-08-07 rename recorded on
/// task `tkrdwb8`), and the replies came back fluent but ungrounded. The
/// same suites run three-at-once, or one at a time, called the real fixtures
/// and answered from them. One live scenario at a time is
/// therefore a correctness requirement of this target, not a courtesy — and it
/// is a rule of the target rather than a limit of `Router`, whose residency is
/// pooled and reference-counted and holds more than one profile resident quite
/// happily. It is the same requirement `SearchThenCallTests`' own
/// `.serialized` holds inside one suite, extended across suite boundaries
/// where a suite trait cannot reach.
///
/// One ``ConcurrencyGate``, the shared gate of the test support code. The unit
/// test process holds its HTTP loopbacks with another one of them.
///
/// **Run this suite with `--no-parallel`.** The command is
/// `swift test --package-path IntegrationTests --no-parallel`, and the flag is
/// not a preference.
///
/// The reason is not GPU contention — this turnstile already
/// admits one live profile at a time, across suite boundaries. The reason is
/// **what the clock counts**. Swift Testing runs suites concurrently by default
/// and starts a test's `.timeLimit` when the test starts; every scenario takes
/// the turnstile from *inside* its own test body, by way of
/// `LiveRouterFixture.resolve()`. So a suite's reported duration is its own
/// work plus however long it queued behind the other suites, and its hang
/// guard counts both.
///
/// Measured on 2026-08-16, the same commit both ways:
///
///   suite                        parallel   --no-parallel
///   Gated async fan-out             443.5s          71.4s
///   Gated background-in-code-mode   371.2s          64.2s
///   Gated search-then-call (x4)     661.0s         283.1s
///   Selection tier fork()-per-call   85.6s          16.5s
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
let liveProfileTurnstile = ConcurrencyGate()

/// One resolved, live `Router` + `LanguageModelProfile` pair, together with
/// the recording root its sessions write their JSONL transcript under —
/// everything an integration scenario needs to vend a `RoutedSession` over
/// `profile.standard` (the wiring a host makes), to back
/// `searchToolsTool`'s own selection tier with `profile.flash`, and then to
/// read back the selection tier's own recorded trace
/// (`NativeTranscript.selections(in:slot:)`). Both sessions are Router-vended,
/// so both are recorded here.
struct LiveRouterFixture {
    /// The router that resolved `profile` — its `id` roots the recording
    /// tree `transcriptEvents()` reads back.
    let router: Router
    /// The resolved, resident profile. Its models stay resident after this
    /// fixture is unreferenced, because `LiveModelResidency` keeps one hold of
    /// each of them for the test process; see ``tearDown()``.
    let profile: LanguageModelProfile
    /// The durable transcripts root passed to `Router.init(recordingsDir:)`.
    /// Stands under ``recordingsRoot`` — inside the workspace, never under the
    /// ephemeral temporary directory — so the recorded run survives the
    /// process for a CI artifact-upload step or a local investigation to
    /// read. Card `^hht0009` is the reason: a 30-minute zero-activity CI hang
    /// left no transcript to read, because the recordings lived in a
    /// temporary directory no CI step uploads.
    private let recordingsDir: URL
    /// The pooled embedder of `profile.embedding`, made by name over
    /// `ModelPool.shared` after the resolve. The Router resolved the profile
    /// into the same pool, so its first embed call adds a hold of the
    /// resident model and loads no second copy.
    private let embedder: PooledEmbedder

    /// The discovery seams over ``profile``: the librarian on `profile.flash`
    /// and the pooled embedder of `profile.embedding`, with no sample
    /// generator.
    ///
    /// Each scenario mounts discovery through it, the same way that a Router
    /// host does. Discovery takes seams and not Router handles (task
    /// `^kzaefgz`), and `RouterDiscoverySeams` is the one adapter between the
    /// two.
    var discoverySeams: RouterDiscoverySeams {
        RouterDiscoverySeams(librarian: profile.flash, embedder: embedder)
    }

    /// Resolves a profile over a real, live `LiveModelLoader` — its Extras
    /// `MLXModelLoader` downloads from the Hugging Face Hub with its own
    /// tokenizer loader, mirroring Router's own gated
    /// `IntegrationTests.endToEnd()`.
    ///
    /// Takes ``liveProfileTurnstile`` before resolving anything, so at
    /// most one integration scenario in the target generates at a time;
    /// ``tearDown()`` gives it back. A resolution that throws gives it back
    /// itself, since its caller is left with no fixture to tear down.
    ///
    /// Each call makes a new `Router`, thus each scenario gets its own
    /// recordings directory. The models come from `ModelPool.shared`, and
    /// `LiveModelResidency` keeps each model resident after its first
    /// resolve, thus a later resolve of the same model loads nothing. Every
    /// router reads one repository-metadata cache, ``routerCacheRoot``.
    ///
    /// - Parameter definition: the profile to resolve. Defaults to
    ///   `multitoolTinyProfile`, the configuration a host really gets, which is
    ///   what every suite grading an *answer* must resolve. A probe grading
    ///   plumbing passes `plumbingProbeProfile` instead — see that constant for
    ///   which suites may, and why the rest may not.
    /// - Returns: the resolved fixture.
    /// - Throws: whatever `Router.resolve(profile:reporting:)` throws — including
    ///   `GenerationError.notWiredForLiveInference` if the live decode path
    ///   isn't wired up in this environment (plan.md M6.5's typed skip
    ///   reason).
    @MainActor
    static func resolve(
        _ definition: ProfileDefinition = multitoolTinyProfile
    ) async throws -> LiveRouterFixture {
        // `swift test`'s binary layout defeats mlx-swift's default metallib
        // lookup (see `MetalLibraryTestBootstrap`'s documentation) — must run
        // before any live model resolution touches the GPU device.
        _ = MetalLibraryTestBootstrap.ensureColocatedMetallib
        await liveProfileTurnstile.acquire()
        do {
            let recordingsDir = Self.makeRecordingsDir()
            let router = Self.makeRouter(recordingsDir: recordingsDir, loader: LiveModelLoader())
            let progress = ResolutionProgress()
            let profile = try await router.resolve(profile: definition, reporting: progress)
            try await LiveModelResidency.shared.keep(LiveModelResidency.poolKeys(of: profile))
            // What this run actually resolved, printed because a real-model run's
            // whole purpose is to measure the configuration a host really gets
            // — and until now the only time any of it reached the log was when
            // resolution *failed* and `ResolutionFailure.description` rendered
            // it. A green run said nothing, so the context rung a profile
            // settled on and the footprint it was charged were invisible
            // exactly when they were true.
            //
            // The context is read off `standard` alone deliberately: Router
            // documents `SlotResolution.contextTokens` as profile-wide — "one
            // profile-wide parameter, not a per-slot one" — so a second reading
            // would be the same number wearing a different label.
            //
            // Both generation slots are printed because each profile of this
            // target names a different model in each, and a reader of the log
            // needs to see both models that one run held resident.
            // `RoutedLLM.resolution` is `package`-protected, so a consumer
            // reads neither the context window nor the per-candidate charge.
            // This line is a diagnostic and never an assertion, thus it reports
            // what is public and drops what is not. Built in named pieces
            // because one chained interpolation of this length times the type
            // checker out.
            let standardLine =
                "standard=\(profile.standard.chosen.stringValue) "
                + "footprint=\(profile.standard.footprintBytes)B"
            let flashLine =
                "flash=\(profile.flash.chosen.stringValue) "
                + "footprint=\(profile.flash.footprintBytes)B"
            reportTraceLine(
                "RESOLVED [\(definition.name)] \(standardLine) | \(flashLine)"
                    // The recordings directory of THIS resolution, printed so a
                    // log reader — a person over a CI log above all — can pair
                    // each scenario with the transcript directory that recorded
                    // it. Several fixtures resolve per run, so without this
                    // line the uploaded recordings are a pile of UUID-named
                    // directories with no map back to the scenarios.
                    + " recordings=\(recordingsDir.path)"
            )
            let embedder = RouterDiscoverySeams.acquireEmbedder(for: profile.embedding)
            return LiveRouterFixture(
                router: router, profile: profile, recordingsDir: recordingsDir, embedder: embedder)
        } catch {
            await liveProfileTurnstile.release()
            throw error
        }
    }

    /// Gives ``liveProfileTurnstile`` back to the next waiting scenario.
    /// Call once a scenario is done with this fixture, on every exit path
    /// (success, assertion failure, or thrown error).
    ///
    /// The three resident models stay resident after this call, because
    /// `LiveModelResidency` keeps one hold of each model for the whole test
    /// process. The next scenario that names the same model thus loads
    /// nothing. The handles and the sessions of this fixture are still freed
    /// by ARC once nothing references them, so a scenario must keep no handle
    /// and no session past its own test function.
    func tearDown() async {
        await liveProfileTurnstile.release()
    }

    /// Makes the `Router` of one fixture.
    ///
    /// ``resolve(_:)`` makes each live router here. A test of the router
    /// configuration gives its own loader, metadata source, and pool, and
    /// gets the same cache directory as a live router.
    ///
    /// - Parameters:
    ///   - recordingsDir: The durable transcripts root of the router.
    ///   - loader: The download and load step.
    ///   - metadataSource: The fetch of the sizing metadata. The default
    ///     reads the Hugging Face Hub.
    ///   - pool: The resident-model pool to resolve into. The default is
    ///     the pool of the process.
    /// - Returns: The router, which records every transcript in full, and
    ///   caches the sizing metadata under ``routerCacheRoot``.
    static func makeRouter(
        recordingsDir: URL,
        loader: any ModelLoader,
        metadataSource: any MetadataSource = HuggingFaceMetadataSource(),
        pool: ModelPool = .shared
    ) -> Router {
        Router(
            cacheDir: routerCacheRoot,
            recordingsDir: recordingsDir,
            recordingLevel: .full,
            metadataSource: metadataSource,
            loader: loader,
            pool: pool
        )
    }

    /// Reads back this fixture's whole recorded run as a totally-ordered
    /// event stream — `TranscriptEvent.merged(under:)` over this router's
    /// own recording root (`recordings/<routerId>/`).
    ///
    /// - Returns: every recorded event, ordered by `(ts, seq)`.
    /// - Throws: if a transcript file can't be read or decoded.
    func transcriptEvents() throws -> [TranscriptEvent] {
        try TranscriptEvent.merged(under: recordingsDir.appendingPathComponent(router.id.description))
    }

    /// The durable root every fixture's recordings directory stands under:
    /// `<IntegrationTests package>/.build/recordings`, derived from this
    /// file's own compile-time path. `#filePath` is valid at run time because
    /// this package builds and tests on the same machine, locally and in CI
    /// alike.
    ///
    /// Inside the workspace on purpose (card `^hht0009`): a recordings root
    /// under `FileManager.default.temporaryDirectory` does not survive a CI
    /// runner and is subject to the platform's temporary-directory sweep, so
    /// a hung run left no transcript to read. Under `.build/` the tree is
    /// already git-ignored (the root `.gitignore` ignores `.build/`), a CI
    /// artifact-upload step can name `IntegrationTests/.build/recordings`
    /// directly, and `swift package clean`/`.build` removal is the deliberate
    /// way to clear old runs. `RecordingsLocationTests` holds this location.
    static var recordingsRoot: URL {
        packageBuildDirectory.appendingPathComponent("recordings", isDirectory: true)
    }

    /// The one cache directory of every Router this fixture makes:
    /// `<IntegrationTests package>/.build/router-cache`.
    ///
    /// Router keeps the parsed sizing metadata of each model here. When the
    /// metadata fetch of a reference with no pinned commit fails, Router reads
    /// the entry that an earlier resolve wrote (card `^kghyac5`: a fetch that
    /// timed out failed two scenarios before they started, because each
    /// router had a new temporary cache directory and thus no entry). The
    /// fetch is still the first read, thus a good network still gives the
    /// current metadata.
    ///
    /// Under `.build/` for the reasons of ``recordingsRoot``: git ignores it,
    /// and `swift package clean` removes it. Not the user caches directory of
    /// the shipped host, because a test of this package writes stub entries,
    /// and those must not reach the cache that a host reads.
    /// `RouterMetadataCacheTests` holds this behavior.
    static var routerCacheRoot: URL {
        packageBuildDirectory.appendingPathComponent("router-cache", isDirectory: true)
    }

    /// `<IntegrationTests package>/.build`, derived from this file's own
    /// compile-time path. `#filePath` is valid at run time because this
    /// package builds and tests on the same machine, locally and in CI alike.
    private static var packageBuildDirectory: URL {
        URL(fileURLWithPath: #filePath)     // …/Support/LiveRouterFixture.swift
            .deletingLastPathComponent()    // …/Support
            .deletingLastPathComponent()    // …/FoundationModelsMultitoolIntegrationTests
            .deletingLastPathComponent()    // …/Tests
            .deletingLastPathComponent()    // …/IntegrationTests
            .appendingPathComponent(".build", isDirectory: true)
    }

    /// The name prefix of every directory this fixture creates — one spelling
    /// for the temporary directories and the durable recordings
    /// directories alike, so a directory listing reads as one family.
    private static let fixtureDirectoryPrefix = "FMMultitoolIntegration-"

    /// Creates a unique temporary directory, for state that must NOT outlive
    /// the run — a capability store a scenario configures for the surface it
    /// mounts.
    static func makeTempDir() -> URL {
        makeUniqueDirectory(under: FileManager.default.temporaryDirectory)
    }

    /// Creates a unique recordings directory under ``recordingsRoot``, for
    /// the one output that must outlive the run: the recorded transcripts a
    /// hang investigation reads.
    static func makeRecordingsDir() -> URL {
        makeUniqueDirectory(under: recordingsRoot)
    }

    /// Creates one uniquely named directory under `parent`, creating `parent`
    /// itself when it is not there yet.
    ///
    /// - Parameter parent: the directory the new directory stands in.
    /// - Returns: the created directory.
    private static func makeUniqueDirectory(under parent: URL) -> URL {
        let dir = parent
            .appendingPathComponent("\(fixtureDirectoryPrefix)\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
