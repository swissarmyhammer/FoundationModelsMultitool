---
comments:
- actor: claude-code
  id: 01m23xnqmtc5141fj7t5xchn6c
  text: |-
    ### Direction from the user (2026-09-09)

    Two hints for the fix. Obey them when the research supports them.

    1. The fix can be necessary in the ranker, not only in this package. If the selection tier in `FoundationModelsRanker` answers empty, or its retrieval order is the cause, push the fix down into the ranker.
    2. If the tool surface is short enough, do not do a search at all. Put all the tool entries in the prompt and let the flash model select with pure LLM prompting. Measure the size of the rendered catalog for the surface the agent had (files writable, shell on). If it fits in the prompt, bypass the retrieval tier and give the whole catalog to the selection model.
  timestamp: 2026-09-09T20:27:43.130119+00:00
- actor: claude-code
  id: 01m23xp9cvbr694ayf2e4s3bch
  text: |-
    ### Direction from the user, part 2 (2026-09-09)

    The reason for hint 2: keep the context load of the full tool catalog inside a separate session. The main agent session must not hold the catalog. The forked selection session (`AgentSession.fork role=selection`) holds the full catalog in its prompt and answers with the selected ids only. The main session sees only the answer.
  timestamp: 2026-09-09T20:28:01.307613+00:00
- actor: claude-code
  id: 01m23ycx91yqq7p675173vq6s8
  text: |-
    ### Direction from the user, part 3 (2026-09-09)

    If the fix needs a change in `FoundationModelsRanker`, add kanban tasks in the Ranker repository for that change. Do not edit the Ranker checkout under `.build/checkouts`. The user starts a separate agent in the Ranker repository to do those tasks. Write on this card the short ids and titles of the Ranker tasks you add, so the finish loop can report them to the user.
  timestamp: 2026-09-09T20:40:22.561547+00:00
- actor: claude-code
  id: 01m23ywcra664bxynbxgx74dhn
  text: |-
    ### Research 1: where an embedder can go, and where the profile's embedder is

    Files in this package:

    - `Sources/FoundationModelsMultitool/Discovery/SearchToolsTool.swift` lines 152-156: `makeSearcher(over:selection:)` calls `MetadataSearcher(items:mode:selection:)`. That is the sync convenience initializer at `MetadataSearcher.swift` lines 139-154 (checkout `FoundationModelsMetadataRegistry`). Line 150 passes `embedder: nil`.
    - `Sources/FoundationModelsMultitool/RegistryBundle.swift` line 90: the hint searcher is `MetadataSearcher(items: registry.surface.entries, mode: .retrieval)`, no embedder. Lines 94-96: the discovery searcher comes from `SearchToolsTool.makeSearcher`. `RegistryBundle.init` (lines 84-98) is synchronous. `RegistryHolder.applyStaged()` builds a new bundle on each surface swap with the same `RegistryBundleShape` (`RegistryBundle.swift` lines 30-37).
    - `Sources/FoundationModelsMultitool/MultiTool.swift` lines 185-223: `makeSessionToolsAndStaging(librarian:sampleGenerator:)` builds the bundle with `DiscoverySearch.configured(selection:)`. It takes no embedder. `SurfaceRefresher.swift` lines 19-22 state the rule: this factory is synchronous and starts no task.

    The initializers of `MetadataSearcher` (checkout, `MetadataSearcher.swift`):

    - Lines 179-195: `init(items:mode:weights:embedder:selection:onDiagnostic:) async`. It takes `embedder: (any TextEmbedding)?` and calls `MetadataIndex.build(items:embedder:onDiagnostic:)` (`Catalog/MetadataIndex.swift` lines 237-250). `build` embeds every rendered block in one `embedder.embed(textsToEmbed)` call. This is why the initializer is `async`.
    - Lines 217-234: `init(index:mode:weights:embedder:selection:onDiagnostic:)` is synchronous. It accepts an embedder together with an index that has no embeddings yet.
    - Lines 346-395: `update(items:)` does the embed catch-up. With the same content and pending embeddings it embeds, merges the vectors, and keeps the selection tier (no rebuild, lines 362-366 and 381-394).
    - Lines 590-612: `computeCosineScores` emits `.embeddingUnavailable` when `embedder == nil` or when no item has an embedding. With `weights.cosine == 0` it emits nothing (line 600). The log line `no embedder configured or catalog not yet embedded` is `Catalog/Diagnostics.swift` lines 70-73.

    The embedder seam:

    - `FoundationModelsRanker/TextEmbedding.swift` lines 15-26: `protocol TextEmbedding { var dimension: Int; func embed(_ texts: [String]) async throws -> [[Float]] }`.
    - Router's `RoutedEmbedder` (`FoundationModelsRouter/RoutedEmbedder.swift` lines 11-46) has `dimension` and `embed(texts:)`. It does not conform to `TextEmbedding`. No conformance exists in this package. `FoundationModelsCodeContext/Sources/FoundationModelsCodeContext/Embedding/RoutedEmbedderAdapter.swift` (45 lines) is the adapter pattern the family uses: a struct that forwards `dimension` and `embed(_:)` to `embed(texts:)`.

    Where the profile's embedder is available:

    - ACP agent: `FoundationModelsACPAgent/Sources/FoundationModelsACPAgent/Tools/ToolCatalog.swift` lines 124-140, `sessionSurface(context:)`. Line 126-127 calls `built.registry.makeSessionToolsAndStaging(librarian: context.profile.flash)`. `context.profile` is a `LanguageModelProfile`, which holds `.embedding` (`RoutedEmbedder`, `FoundationModelsRouter/LanguageModelProfile.swift` line 178). The embedder is resolved and resident, and it is never passed.
    - Multitool CLI: `Sources/MultitoolCLI/CLIRunner.swift` line 414 names the embedding model, line 450 puts it in `demoProfile`, line 860 calls `makeSessionToolsAndStaging(librarian: profile.flash)`. Same gap.
  timestamp: 2026-09-09T20:48:49.930490+00:00
- actor: claude-code
  id: 01m23ywxe8fftjsrngnkm3ypkw
  text: |-
    ### Research 3: the selection tier in FoundationModelsRanker

    Files in the checkout `.build/checkouts/FoundationModelsRanker/Sources/FoundationModelsRanker/Selection/`:

    - `SelectionTier.swift` lines 142-163, `search(intent:limit:)`. Under budget (`assembledPrefix.count <= config.capacityCharacterLimit`, line 144) it forks the cached root session (line 148) and sends `prompt(prefix:intent:)` (line 150). For a `.factory` source that prompt is `"# Task\n\n<intent>"` (lines 221-229). The whole catalog is in the session instructions: `assemblePrefix` (lines 356-395) renders the preamble, `# Candidates`, and one `## <id>` heading above each entry's `summaryBlock`. For `APISurface.Entry` the summary block is the full `block` (`Surface/APISurface+SearchableMetadata.swift` lines 17-26).
    - Line 157: `retrievalRanking(intent)` runs after the model call. Under budget it only attaches `score` and `signals` to the selected ids. It never changes which ids come back. No `.retrievalCut` is emitted under budget.
    - Lines 312-341, `matches(forIDs:limit:allowedIDs:retrievalMatches:)`: an empty `ids` array gives an empty result and no diagnostic.
    - `SelectionConfig.swift` line 47: `defaultCapacityCharacterLimit = 32_000`. Lines 163-166: the default preamble `.selectionDefault` is: "Given a task, return ONLY the items needed — fewest that suffice, in call order when order matters. Do not invent ids; return an empty list if nothing fits." `SearchToolsTool.makeSelection` (this package, lines 249-313) uses `SelectionConfig(model:)` and so this default preamble. It does not use the API-librarian preamble `.librarianDefault` (`FoundationModelsMetadataRegistry/SelectionPreamble.swift` lines 12-16).
    - `Selection.swift` lines 17-27: `@Generable struct Selection { var ids: [String] }`. The guide text says "empty if nothing in the candidate set fits the intent."
    - The grammar is built in this package: `Sources/FoundationModelsMultitool/Discovery/SelectionGrammar.swift` lines 24-50, `idEnumGrammar(ids:)`. It is an object with one `ids` array of enum strings, `uniqueItems: true`, `maxItems: ids.count`, and no `minItems`. So `{"ids":[]}` is a legal output of the grammar.
    - `SearchToolsTool.makeSelection` line 306 makes the session with `librarian.makeGuidedSession(grammar: grammar, instructions: instructions)`. The grammar constrains the first token to `{`, so the model cannot think before it answers.

    Answer to the question of item 3: an empty selection is a legal answer at three levels. The preamble invites it ("return an empty list if nothing fits"), the `Selection` guide invites it, and the grammar permits it. The prompt asks the model to choose by putting the intent under a `# Task` heading, with the catalog in the instructions.

    ### Catalog size for the surface the agent had (files writable, shell on)

    Measured with a probe test over `MultiTool.Builder().withFiles(root:, readOnly: false).withShell(storeDirectory:)`:

    - entries = 9: `files.read`, `files.write`, `files.edit`, `files.patch`, `files.glob`, `files.grep`, `shell.execute`, `shell.getLines`, `shell.grepHistory`.
    - `SelectionTier.assemblePrefix(preamble: .selectionDefault, catalog:)` = 17,063 characters (17,175 UTF-8 bytes). `APISurface.source` alone = 16,750 characters.
    - Budget = 32,000 characters. The catalog is under budget by 14,937 characters.

    So the agent's ten calls already took the whole-catalog path. The selection model saw all nine entries in its instructions on each call, and answered empty eight times. The retrieval tier did not cut anything. Hint 2 of the user is already the shape of the code under budget; the defect is in what the flash model answers when it holds the whole catalog.
  timestamp: 2026-09-09T20:49:07.016240+00:00
- actor: claude-code
  id: 01m23yx84nrmfj1ft53tv36a52
  text: |-
    ### Research 4: the keyword tier alone (`mode: .retrieval`, BM25 + trigram, no embedder), limit 9

    The catalog has 9 entries, so every entry is in the top 9. The ranks that matter are the top positions. Scores are the fused `[0, 1]` score; `bm25` and `tri` are the raw signals.

    | # | query | rank of write / edit / shell.execute | top 3 |
    |---|---|---|---|
    | 1 | Search the astropy codebase for files, read code, and run tests | write 8, edit 6, execute 4 | glob 0.968, grep 0.968, read 0.948 |
    | 2 | list files and read file contents | write 4, edit 6, execute 9 | grep 0.992, read 0.984, glob 0.976 |
    | 3 | grep search for text pattern in files | write 8, edit 6, execute 7 | grep 1.000, patch 0.968, glob 0.968 |
    | 4 | run a shell command or python script, execute code | execute 1 (bm25 10.01, tri 1.51), edit 4, write 5 | execute 1.000, getLines 0.984, grepHistory 0.968 |
    | 5 | run pytest tests, execute | execute 1 (bm25 4.32, tri 1.66), write 5, edit 6 | execute 1.000, getLines 0.984, grepHistory 0.953 |
    | 6 | write file, edit file, create file | write 1 (bm25 5.07, tri 1.74), edit 2 (bm25 5.26, tri 1.43), execute 9 | write 0.992, edit 0.992, read 0.953 |
    | 7 | edit code, modify source file, patch | edit 2 (bm25 3.18, tri 1.06), write 3 (bm25 2.42), execute 6 | patch 1.000, edit 0.984, write 0.953 |
    | 8 | apply changes to a file, save file contents | write 2 (bm25 1.00, tri 0.55), edit 6, execute 8 | read 0.992, write 0.969, glob 0.960 |
    | 9 | file operations: create, write, append, delete, move | write 1 (bm25 3.46, tri 1.06), edit 4, execute 9 | write 0.992, patch 0.984, read 0.961 |
    | 10 | create a new text file with given content on disk | write 4 (bm25 2.60, tri 0.48), edit 5, execute 7 | read 0.984, patch 0.976, grep 0.976 |

    Result: for queries 4 and 5 the keyword tier ranks `shell.execute` first. For queries 6 and 9 it ranks `files.write` first, and for query 7 it ranks `files.patch` first and `files.edit` second. For query 8 `files.write` is second. For query 10 `files.write` is fourth, behind `read`, `patch` and `grep`. The keyword tier alone finds the write, edit or shell entry in the top 3 for queries 4, 5, 6, 7, 8 and 9. The cosine signal is `0.0` on every row because no embedder is configured.
  timestamp: 2026-09-09T20:49:17.973615+00:00
- actor: claude-code
  id: 01m2404yy4jfcgvavrgex1epxp
  text: |-
    ### Direction from the user, part 4 (2026-09-09)

    1. Think about what uses `FoundationModelsRanker` and `FoundationModelsMetadataRegistry`. Do not put code in this package that belongs in those packages. Do not make a copy of a selection prompt, a tier, or a searcher that the ranker or the registry already owns. If the correct home of the fix is in one of those packages, add a kanban task in that repository and write its short id and title on this card.
    2. The user thinks the metadata registry must change its design: not retrieve, then prompt, then rank. One large prompt that picks. For tools, put only the descriptions in that prompt, not the full parameter text. For skills, do the same. That keeps the prompt small and the selection direct. Record on this card what the current search path does, what the one-prompt design would remove, and which package must change. If the change is in the registry or the ranker, add the kanban task there.
  timestamp: 2026-09-09T21:10:59.268214+00:00
- actor: claude-code
  id: 01m240jzx6es6zgjgfpq3jksvy
  text: |-
    ### Research 2: the empty selection, reproduced on the real flash model, and its cause

    Test: `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/AgentSurfaceDiscoveryTests.swift` (gated, nested package). Model: `mlx-community/Qwen3-4B-4bit` (`agentDiscoveryProfile` in `Support/LiveRouterFixture.swift`). Surface: `MultiTool.Builder().withFiles(root:, readOnly: false).withShell(storeDirectory:)`, mounted with `registry.makeSessionTools(librarian: profile.flash)`, the call the agent makes. The raw ids are read off the Router recording (`NativeTranscript.selections(in:slot: .flash)`).

    Before the fix (RED run): entries=9, prefixCharacters=17,063 with `.selectionDefault`, budget=32,000. The whole catalog was in the selection session.

    | # | query | matches | raw answer |
    |---|---|---|---|
    | 1 | Search the astropy codebase for files, read code, and run tests | 0 | `{"ids":[]}` |
    | 2 | list files and read file contents | 2 | files.glob, files.read |
    | 3 | grep search for text pattern in files | 0 | `{"ids":[]}` |
    | 4 | run a shell command or python script, execute code | 0 | `{"ids":[]}` |
    | 5 | run pytest tests, execute | 0 | `{"ids":[]}` |
    | 6 | write file, edit file, create file | 0 | `{"ids":[]}` |
    | 7 | edit code, modify source file, patch | 0 | `{"ids":[]}` |
    | 8 | apply changes to a file, save file contents | 0 | `{"ids":[]}` |
    | 9 | file operations: create, write, append, delete, move | 0 | `{"ids":[]}` |
    | 10 | create a new text file with given content on disk | 1 | files.write |

    This is the table of the agent's log, line for line: two of ten.

    Cause, measured with a temporary experiment suite (deleted) that changed only the preamble of `SelectionConfig` and kept the grammar, the `# Task` prompt and the entry blocks:

    | variant | preamble | answered |
    |---|---|---|
    | V0 | `.selectionDefault` (ranker) | 2 of 10 |
    | V1 | `.librarianDefault` (registry) | 10 of 10, but over-selects: 9 of 9 ids for q5 and for q9 |
    | V2 | "The candidates below are the functions a program can call ... Prefer the closest candidates over an empty answer; answer with an empty list only when no candidate is related to the task at all." | 10 of 10: q4 execute; q5 execute; q6 write, edit, read; q7 edit, patch; q8 edit; q9 write, edit, patch, glob, read; q10 write |
    | V3 | `.selectionDefault` plus one sentence: never an empty list when a candidate is related | 10 of 10 |
    | V4, V5 | two other wordings of the same rule | 10 of 10 |

    Each selection call took 0.9 s to 3.2 s.

    Of the three causes on the card, cause 1 holds: the instructions. Cause 2 (the block text) does not hold: the same blocks answered 10 of 10 under V2. Cause 3 (the grammar permits an empty array) is true, but it is not the cause: the grammar was the same in the 2-of-10 and the 10-of-10 runs. The retrieval order is not the cause under budget: the tier sends the whole catalog to the model and runs retrieval only after the answer, to attach scores (Research 3).
  timestamp: 2026-09-09T21:18:39.014307+00:00
- actor: claude-code
  id: 01m240k8mrppxxejxkbecdf6ec
  text: |-
    ### Counts after the fix, on `mlx-community/Qwen3-4B-4bit`

    `swift test --package-path IntegrationTests --no-parallel --filter AgentSurfaceDiscoveryTests`: passed, 14.9 s for the model load and the ten calls.

    Catalog: entries=9, prefixCharacters=17,263 (the new preamble is 356 chars), budget=32,000, ids = files.read, files.write, files.edit, files.patch, files.glob, files.grep, shell.execute, shell.getLines, shell.grepHistory. The whole catalog stays in the forked selection session; the main session gets the selected blocks only.

    | # | query | matches | paths | raw answer |
    |---|---|---|---|---|
    | 1 | Search the astropy codebase for files, read code, and run tests | 3 | files.glob, files.read, shell.execute | same |
    | 2 | list files and read file contents | 2 | files.glob, files.read | same |
    | 3 | grep search for text pattern in files | 1 | files.grep | same |
    | 4 | run a shell command or python script, execute code | 1 | shell.execute | same |
    | 5 | run pytest tests, execute | 1 | shell.execute | same |
    | 6 | write file, edit file, create file | 3 | files.write, files.edit, files.read | files.write, files.edit, files.read, files.write (the duplicate is dropped) |
    | 7 | edit code, modify source file, patch | 2 | files.edit, files.patch | same |
    | 8 | apply changes to a file, save file contents | 1 | files.edit | same |
    | 9 | file operations: create, write, append, delete, move | 5 | files.write, files.edit, files.patch, files.glob, files.read | same |
    | 10 | create a new text file with given content on disk | 1 | files.write | same |

    Ten of ten answered. Queries 4 to 9 each hold the write, edit or shell entry, as the test asserts.

    Embedder: in the window of this run the unified log holds zero `no embedder configured` lines and one `[FoundationModelsMetadataRegistry:MetadataDiagnostic] embedding catch-up: 9/9 item(s) pending` line, which is the one-time embed of the catalog at the first search. (The root unit suite, which builds searchers with no embedder on purpose, still logs the diagnostic; that is the expected keyword-only path.)
  timestamp: 2026-09-09T21:18:47.960648+00:00
- actor: claude-code
  id: 01m240m7gtkk5zdh4xrzxsw67b
  text: |-
    ### The fix in this package, and the check against direction part 4, point 1

    **Defect 2, the empty selection.** `SearchToolsTool.selectionPreamble` (`Sources/FoundationModelsMultitool/Discovery/SearchToolsTool.swift`) is passed as `SelectionConfig(model:preamble:)` in `makeSelection(librarian:ids:)`. The grammar, the prompt and the blocks are unchanged. Unit test `selectionTierIsSeededWithTheFunctionPreamble` in `Tests/FoundationModelsMultitoolTests/SearchToolsToolTests.swift`. The doc comment of the constant carries the measurement.

    Check against point 1: `SelectionConfig.preamble` is the seam the ranker offers a consumer, and the registry uses the same seam for its own `.librarianDefault`. The text is a new wording for function catalogs, not a copy of a ranker or registry preamble. But the default of the ranker is what every other consumer gets, and on a 4B model it answers nothing. That is a ranker defect, so ranker card `^zxm99zs` carries the measurement and asks for a default that answers; when it lands, this package can delete its constant. The doc comment of the constant says so.

    **Defect 1, no embedder.**

    - `Discovery/RoutedTextEmbedding.swift` (new): `RoutedEmbedder` presented as the ranker's `TextEmbedding`. This is the Router-to-Ranker adapter pattern this package already holds for sessions (`RoutedAgentSession`). The ranker and the registry removed their Router adapters on purpose (ranker card "Delete RoutedAgentSession and RoutedEmbedderAdapter", registry card "Remove the live-Router embedder path"), so the adapter's home is the consumer.
    - `Discovery/CatalogSearcher.swift` (new): a `MetadataSearcher` built synchronously over an unembedded `MetadataIndex`, plus the `CatalogEmbedding` actor that runs `MetadataSearcher.update(items:)` one time before the first search. The bundle build stays synchronous and starts no task (the rule in `SurfaceRefresher.swift`). Check against point 1: the one-time catch-up is a behavior the searcher can own. Registry card `^8c4wtra` asks `MetadataSearcher` to do it itself; when it lands, this file is deleted. The doc comment of the type says so.
    - `RegistryBundle.swift`: `RegistryBundleShape.embedder`; the discovery searcher (`.auto`) and the hint searcher (`.retrieval`) both take it, so `runCode`'s did-you-mean ranker ranks with it as well.
    - `MultiTool.swift`: `makeSessionTools(librarian:embedder:sampleGenerator:)` and `makeSessionToolsAndStaging(librarian:embedder:sampleGenerator:)`, `embedder: RoutedEmbedder? = nil`. The default keeps the ACP agent compiling until its own card lands.
    - `SearchToolsTool.swift`: `init(registry:librarian:embedder:limit:sampleGenerator:)`, `makeSearcher(over:selection:embedder:)`, `makeEmbedding(from:)`.
    - `UnknownToolHint.swift`: `hint(message:snippet:surface:searcher:)` takes a `CatalogSearcher`.
    - `Sources/MultitoolCLI/CLIRunner.swift`: passes `profile.embedding`.
    - Tests: `Tests/FoundationModelsMultitoolTests/DiscoveryEmbedderTests.swift` (new, six tests with a `RecordingEmbedder` from `Fixtures/EmbeddingFixtures.swift`; `StubRouterFixtures.makeStubProfile` gives a stub profile with an embedding slot), `UnknownToolHintTests.swift` updated.

    Root unit suite: `swift test`, 1407 tests in 110 suites, 0 failures, 0 warnings. Nested gated suite: `AgentSurfaceDiscoveryTests`, passed on the real flash model.
  timestamp: 2026-09-09T21:19:19.578521+00:00
- actor: claude-code
  id: 01m240mwy7w5jgmv4md6gc3c10
  text: |-
    ### Direction part 4, point 2: the search path today, what one prompt that picks removes, and which package changes

    **The path today** (`FoundationModelsRanker/Selection/SelectionTier.swift` lines 142-163, checkout of 2026-09-09; `FoundationModelsMetadataRegistry` `MetadataSearcher.search` in modes `.selection` and `.auto` forwards to it):

    1. Under budget (prefix <= 32,000 chars): fork the cached root session that holds the whole catalog, send `# Task\n\n<intent>`, decode the ids. Then `retrievalRanking(intent)` runs BM25 + trigram + cosine over the whole catalog, only to attach `score` and `signals` to the selected ids. So under budget the path is prompt, then rank. The rank pass is what needs the embedder, and it is where `no embedder configured` came from.
    2. Over budget: `retrievalRanking` first, cut to the top M, a one-off session over those candidates, prompt, decode, rank. So over budget the path is retrieve, then prompt, then rank.
    3. The prefix holds one `## <id>` heading above each entry's `summaryBlock`. For `APISurface.Entry` the summary is the full block: the JSDoc with `@param`, `@returns`, `@example` and the `declare function` line (`Sources/FoundationModelsMultitool/Surface/APISurface+SearchableMetadata.swift` lines 17-19 leave `renderSummaryBlock()` at the protocol default).

    **What the one-prompt design removes:**

    - The retrieval pass after the answer under budget, and with it the need for an embedder and a BM25 index on the selection path. The order of the answer becomes the model's order.
    - The retrieval cut over budget. Over budget the ranker must decide: several prompts with the ids merged, or a larger budget.
    - The parameter text from the prompt. Measured over the agent's surface (9 entries): the full prefix is 17,263 chars; the description-only summaries are 7,232 chars in total, so a description-only prefix is about 7,600 chars, 44% of today's prefix and 24% of the budget. Per entry: read 695, write 583, edit 843, patch 1,576, glob 633, grep 843, execute 935, getLines 527, grepHistory 579.

    **Which package changes:**

    - `FoundationModelsRanker`: `SelectionTier.search` (the two retrieval passes and the over-budget design). Task `^kqp9e5e`.
    - `FoundationModelsRanker`: the default preamble. Task `^zxm99zs`.
    - `FoundationModelsMetadataRegistry`: nothing for the one-prompt design itself. `SearchableMetadata.renderSummaryBlock()` is already the seam for a description-only summary, and the modes `.selection`/`.auto` forward to the ranker. The registry change on this card is the embed catch-up, task `^8c4wtra`.
    - `FoundationModelsMultitool` (this package): `APISurface.Entry.renderSummaryBlock()` returns the description only; `ToolDescriptor` gets a `description` field so no JSDoc is parsed. Task `^0z0te3n` on this board. The main session is untouched: `SearchToolsTool` splices the full block for the selected ids, and the full catalog stays in the forked selection session (direction part 2).
    - Skills: the same rule applies to the item that conforms skills to `SearchableMetadata`/`SearchItem`; that conformance is not in this package or in the registry checkout, so the card for it goes in the package that owns the skill item.

    **Why the current fix stays.** It is the smallest change that makes the agent's ten queries answer on its own model today, it changes no ranker or registry file, and it is on the seams those packages offer (`SelectionConfig.preamble`, `TextEmbedding`, `MetadataSearcher.update(items:)`). The one-prompt design removes the retrieval pass that needs the embedder; until the ranker lands `^kqp9e5e`, the pass runs on every search, and running it with the profile's embedder is better than running it keyword-only with a diagnostic on every call.

    **Tasks added for this card:**

    - FoundationModelsRanker `^kqp9e5e`: SelectionTier: one prompt that picks. Remove the retrieval ranking after the answer and the retrieval cut before it.
    - FoundationModelsRanker `^zxm99zs`: SelectionConfig: the default preamble makes a 4B model answer an empty list for a function catalog.
    - FoundationModelsMetadataRegistry `^8c4wtra`: MetadataSearcher: embed the catalog at the first search when the searcher was built synchronously with an embedder.
    - FoundationModelsACPAgent `^fksm5k5`: ToolCatalog.sessionSurface: pass the profile's embedding handle to makeSessionToolsAndStaging, then rerun astropy__astropy-12907.
    - FoundationModelsMultitool `^0z0te3n`: APISurface.Entry.renderSummaryBlock(): put only the description of each tool in the selection prompt.

    The four sibling tasks were written as `.kanban/tasks/<id>.md` and `.jsonl` files in the sibling repositories, in the shape of the existing task files, because the kanban tool of this session is bound to this repository's board.
  timestamp: 2026-09-09T21:19:41.511639+00:00
- actor: claude-code
  id: 01m240qjhj3yv4wmgjr6m0v6vm
  text: |-
    ### implement — changed

    - evidence: Two defects fixed in this package. (1) Selection: `SearchToolsTool.selectionPreamble` seeds the selection tier through `SelectionConfig(model:preamble:)`; on `mlx-community/Qwen3-4B-4bit` the ten agent queries went from 2 of 10 answered (eight `{"ids":[]}`, the agent's log line for line) to 10 of 10, with `shell.execute` for queries 4 and 5 and `files.write`/`files.edit` for queries 6 to 10. (2) Embedder: `makeSessionTools(librarian:embedder:sampleGenerator:)` and `makeSessionToolsAndStaging(librarian:embedder:sampleGenerator:)` take the profile's `RoutedEmbedder`; `RoutedTextEmbedding` adapts it to the ranker's `TextEmbedding`; `CatalogSearcher`/`CatalogEmbedding` embed the catalog one time at the first search so the bundle build stays synchronous; both searchers (discovery and hint) rank with it; the CLI passes `profile.embedding`. In the window of the real-model run the unified log holds zero `no embedder configured` lines and one `embedding catch-up: 9/9 item(s) pending` line. Files changed: `Sources/FoundationModelsMultitool/Discovery/SearchToolsTool.swift`, `Discovery/UnknownToolHint.swift`, `Discovery/CatalogSearcher.swift` (new), `Discovery/RoutedTextEmbedding.swift` (new), `MultiTool.swift`, `RegistryBundle.swift`, `RegistryHolder.swift`, `Capabilities/MCP/SurfaceRefresher.swift`, `Sources/MultitoolCLI/CLIRunner.swift`. Tests added: `Tests/FoundationModelsMultitoolTests/DiscoveryEmbedderTests.swift` (6 tests), `Fixtures/EmbeddingFixtures.swift`, one test in `SearchToolsToolTests.swift`, `StubRouterFixtures.makeStubProfile`, `UnknownToolHintTests.swift` updated; gated `IntegrationTests/.../AgentSurfaceDiscoveryTests.swift` (new) with `agentDiscoveryProfile` in `Support/LiveRouterFixture.swift`. Counts: root `swift test` 1407 tests in 110 suites, 0 failures, 0 warnings; nested `AgentSurfaceDiscoveryTests` passed on the real flash model (14.9 s); catalog prefix 17,263 chars of a 32,000 budget; description-only summaries measured at 7,232 chars. Done-when items 1 to 3 checked; items 4 and 5 stay unchecked with the reason on the card (both need `FoundationModelsACPAgent`). Tasks added: ranker `^kqp9e5e` and `^zxm99zs`, registry `^8c4wtra`, ACP agent `^fksm5k5`, this board `^0z0te3n`. No commit, no push, no worktree, no ralph. The task stays in `doing`.
    - next: /review on this card; then `^fksm5k5` in FoundationModelsACPAgent (pass the embedder, rerun `astropy__astropy-12907`) closes items 4 and 5; ranker `^kqp9e5e`/`^zxm99zs` and registry `^8c4wtra` carry the one-prompt design and let this package delete `CatalogSearcher` and `selectionPreamble`; `^0z0te3n` puts descriptions only in the selection prompt.
  timestamp: 2026-09-09T21:21:09.170279+00:00
- actor: claude-code
  id: 01m24141k4m88k35c9jwq57j92
  text: |-
    ### test — green
    - evidence: `swift test` at the root: 1407 tests in 110 suites, 0 failures, 0 skipped tests. `swift build --package-path IntegrationTests`: build complete, 0 errors. `swift test --package-path IntegrationTests --no-parallel --filter AgentSurfaceDiscoveryTests`: 1 test in 1 suite passed. Queries 4 to 9 each found the write, edit, or shell entry, as the task requires.\n\nOne build message showed on each run, at the root and in the nested package: `warning: missing creator for mutated node: ('.../mlx-swift_Cmlx.bundle/Contents/MacOS')`. This message comes from the build tool (SwiftPM/llbuild), not from a Swift or C++ file. It names the `Cmlx` resource folder of the `mlx-swift` dependency. This dependency is a checkout under `.build/checkouts`. A person on this project told this session not to edit a package checkout; a change to `.build/checkouts` also does not stay, because a fresh package resolve replaces it. No file in this package, and no file in `IntegrationTests`, can remove this message. The message showed before this task's code changes too, since it comes from a dependency the code changes did not touch. No test failed, and no test result changed because of it.
    - next: Tell a person about this build message and ask if the project should accept it as known, or open a task with the `mlx-swift` project to fix it. Until then, treat it as expected, not as a new defect.
  timestamp: 2026-09-09T21:27:57.796863+00:00
- actor: claude-code
  id: 01m2415mhqkzb2gna3vk4wd3py
  text: |-
    ### commit — changed
    - evidence: 33ff1d6 — 26 files changed, 1114 insertions(+), 64 deletions(-)
    - next: send the task to review.
  timestamp: 2026-09-09T21:28:49.975369+00:00
- actor: claude-code
  id: 01m241yx3qfg5h22n9tkhsnjdq
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit 33ff1d6, local backend). 0 findings over HEAD~1..HEAD. 16 files reviewed, 14 validator runs attempted, 0 failed. 10 files under `.kanban/` were not reviewed because `.reviewignore` excludes them. The card holds no earlier `## Review Findings` section, so no earlier finding is open. The task moved from `review` to `done`.
    - next: No work is open on this card in this package. Done-when items 4 and 5 stay unchecked on purpose; task `^fksm5k5` in `FoundationModelsACPAgent` closes them. Ranker tasks `^kqp9e5e` and `^zxm99zs`, registry task `^8c4wtra`, and task `^0z0te3n` on this board carry the follow-on work.
  timestamp: 2026-09-09T21:42:37.943856+00:00
- actor: claude-code
  id: 01m2420055hg147vqqyzsn95qe
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 9 source files changed, 5 new files (CatalogSearcher.swift, RoutedTextEmbedding.swift, DiscoveryEmbedderTests.swift, EmbeddingFixtures.swift, AgentSurfaceDiscoveryTests.swift); 10 of 10 queries answered on Qwen3-4B-4bit (was 2 of 10)
    - test: green — swift test 1407 passed, 0 failed, 0 skipped; IntegrationTests build complete; AgentSurfaceDiscoveryTests 1 passed
    - commit: 33ff1d6
    - review: clean — 0 findings over HEAD~1..HEAD; task moved to done
    - open: Done-when items 4 and 5 need FoundationModelsACPAgent task ^fksm5k5. Follow-on tasks: ranker ^kqp9e5e and ^zxm99zs, registry ^8c4wtra, this board ^0z0te3n.
  timestamp: 2026-09-09T21:43:13.829386+00:00
position_column: done
position_ordinal: ffb880
title: 'searchTools finds no write, edit or shell tool: the discovery searcher has no embedder and the selection tier answers empty'
---
## What happened

On 2026-09-09 `acp-agent` ran the SWE-bench instance `astropy__astropy-12907` (bench harness in `FoundationModelsACPAgent`, 14:26 to 14:59, one turn, 3600 s limit). The agent configuration had `tools.files.readOnly: false` and `tools.shell: {}`, thus write, edit and shell were on. The agent made 93 tool calls and ended with an EMPTY patch. It never wrote a file, never edited a file, never ran a shell command, and never ran a test.

The reason is `searchTools`. The model asked ten times for a tool. Eight answers were empty. The unified log (`log show --predicate 'process == "acp-agent"'`, subsystem `com.swissarmyhammer.multitool`) gives each query and its match count:

| # | task the model gave to searchTools | matches |
|---|---|---|
| 1 | Search the astropy codebase for files, read code, and run tests | 0 |
| 2 | list files and read file contents | 2 |
| 3 | grep search for text pattern in files | 0 |
| 4 | run a shell command or python script, execute code | 0 |
| 5 | run pytest tests, execute | 0 |
| 6 | write file, edit file, create file | 0 |
| 7 | edit code, modify source file, patch | 0 |
| 8 | apply changes to a file, save file contents | 0 |
| 9 | file operations: create, write, append, delete, move | 0 |
| 10 | create a new text file with given content on disk | 1 |

The two hits gave the sandbox `read` and `glob`. The 54 `runCode` calls of the run used only those two bindings: read 23 times, glob 6 times. The model asked five times, in five wordings, for a way to change a file, and was told each time that no tool exists. `tools.files.write`, `tools.files.edit` and the shell capability exist in this package (`Capabilities/Files/Write.swift`, `Capabilities/Files/Edit.swift`, `Capabilities/Shell/ShellCapability.swift`).

## What the log says about the search path

1. Each `searchTools` call logged `[FoundationModelsMetadataRegistry:MetadataDiagnostic] no embedder configured or catalog not yet embedded; results are keyword-only (BM25 + trigram).` The agent profile names an embedding model (`mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ`, `AgentConfiguration.defaultEmbedding`), and it never reaches the discovery searcher. `Discovery/SearchToolsTool.swift:155` builds `MetadataSearcher(items: entries, mode: .auto, selection: selection)`. That convenience initializer (`MetadataSearcher.swift:139`) passes `embedder: nil` (line 150). `RegistryBundle.swift:90` builds the hint searcher the same way, with no embedder.

2. Each call then forked a selection session (`AgentSession.fork role=selection`, `AgentSession.respond ... promptCharacters=33..58`). The selection session ran 1.1 s to 2.4 s each time, which is a real flash-model call, grammar-constrained to the catalog ids (`SearchToolsTool.makeSelection(librarian:ids:)`, lines 249-313). No `retrieval cut` diagnostic and no `unknown id` diagnostic appeared, thus the whole catalog went to the selection model and the model answered with an empty selection eight times.

So two things are wrong, and the card is to fix both:

- The retrieval tier has no embedder although the profile has one. Keyword-only BM25 + trigram over the entry blocks is what the selection tier gets as its candidate order, and the diagnostic says so on every call.
- The selection tier, given the whole catalog and the query "write file, edit file, create file", selects nothing. Either the instructions of the selection prompt make the model refuse, or the rendered entry blocks (`APISurface.Entry.block`) do not present `files.write` and `files.edit` in words a 4B model matches to "write a file", or the grammar-constrained answer allows an empty array and the model takes it.

## Research to do first, and to record on this card

1. Read `SearchToolsTool.swift` lines 100-240 and `RegistryBundle.swift` lines 60-100. Record where an embedder could be passed, and where the agent's `profile.embedding` model is available (ACP agent: `SessionSetup.swift`, `AgentComposition`). Record whether `MetadataSearcher` has an initializer that takes an embedder (`MetadataSearcher.swift:179`, `embedder: (any TextEmbedding)?`) and what `MetadataIndex.build(items:embedder:)` needs.
2. Reproduce the empty selection without SWE-bench. Build the surface the agent had (files on, not read-only, shell on) and call `searchTools` with the ten task strings above. Print the rendered catalog blocks the selection model saw, the selection instructions, and the raw grammar-constrained answer. Record which of the three causes above holds.
3. Read the selection tier in `FoundationModelsRanker` (`SelectionTier`, its instructions text, the id-enum grammar). Record whether an empty selection is a legal answer and how the prompt asks the model to choose.
4. Check the keyword tier alone: with `mode: .retrieval`, do the ten queries rank `tools.files.write`, `tools.files.edit` and the shell entry in the top 9? Record the scores.

## The fix, in the shape the research supports

- Give the discovery searcher and the hint searcher the profile's embedder, thus the diagnostic stops and cosine scores join the ranking. The multitool CLI already names the embedding model (`MultitoolCLI/CLIRunner.swift:414`), thus the wiring exists for one path and not the other.
- Make a query for "write file" find `tools.files.write` and a query for "run a shell command" find the shell entry, on the flash model, with the selection tier. If the entry blocks are the cause, change the block text. If the instructions are the cause, change the instructions. If an empty answer is the cause, make the tier fall back to the retrieval ranking instead of answering nothing.

## Done when

- [x] The research comments above are on this card, with file names and line numbers, and the raw selection answers of the ten queries are pasted.
- [x] A test in this package runs the ten task strings above against a surface with files (writable) and shell on, and asserts that queries 4, 5, 6, 7, 8 and 9 each return at least one match, with the write, edit or shell entry among them.
- [x] The same test passes on the real flash model (`mlx-community/Qwen3-4B-4bit`) with the selection tier, and the match counts are pasted on this card.
- [ ] The `no embedder configured` diagnostic does not appear in an `acp-agent` run when the profile names an embedding model. Not done here: the agent must pass `context.profile.embedding` to `makeSessionToolsAndStaging`, which is in `FoundationModelsACPAgent`. Task `^fksm5k5` in that repository. This package's own hosts (the CLI, the gated test) log no such line.
- [ ] A rerun of `uv run bench/swebench_run.py bench/preds.jsonl -i astropy__astropy-12907` in `FoundationModelsACPAgent` shows write or edit calls in the tool log, and the patch is not empty. Paste the searchTools table of that run. Not done here: the rerun runs in `FoundationModelsACPAgent` after task `^fksm5k5`. #defect #discovery #search-tools