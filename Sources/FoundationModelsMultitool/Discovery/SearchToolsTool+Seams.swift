// The model seams of `searchTools`.
//
// Discovery does not know which model backs it. The host picks the models and
// gives them as plain FoundationModels and FoundationModelsExtras types: a
// `SelectionConfig` (FoundationModelsRanker, re-exported by
// FoundationModelsMetadataRegistry) with an `any LanguageModel` for the
// selection tier, an `any PooledEmbedding` for the searchers, and an
// `any LanguageModel` for the sample snippet. This package ships no host. The
// integration suite holds the adapters from Router handles to these seams
// (`RouterDiscoverySeams` in `IntegrationTests/`).
//
// The models of these seams must not be the model of the session that calls
// `searchTools` — see `SelectionFactory`.

import FoundationModels
import FoundationModelsMetadataRegistry

extension SearchToolsTool {
    /// Makes the selection tier for one catalog, given the ids of that
    /// catalog.
    ///
    /// The library calls this factory one time for each catalog, when it
    /// builds the searcher, with every id of that catalog. A host can use the
    /// ids to fit the configuration to the catalog, for example to pick a
    /// capacity budget. The selection tier makes a new `LanguageModelSession`
    /// on `SelectionConfig.model` for each prompt, with the assembled prefix
    /// as its instructions. The prompt names the ids that the model can
    /// choose.
    ///
    /// **The selection model must not be the model of the session that calls
    /// `searchTools`.** `searchTools` is synchronous: its body runs inside
    /// the open submission of the calling session, and that submission ends
    /// only when the body returns. A host that queues the work of each model
    /// in order (Router does) cannot start a selection session on that same
    /// model before the submission ends. Such a host refuses the wait at once
    /// — Router gives its `waitInsideOpenSubmission` error — or the wait
    /// never ends. A selection session on a different model waits its turn
    /// on the queue of its own model, and the search completes. Thus, give
    /// the selection tier a model that is different from the model of each
    /// session that mounts `searchTools`. Router's `flash` slot is that model
    /// when `flash` and `standard` name different models.
    ///
    /// When the selection session fails, `searchTools` does not hide it: the
    /// error of the session is the error of the call, and the model reads it.
    ///
    /// - Parameter ids: every id of the catalog, in catalog order.
    /// - Returns: the selection configuration for that catalog.
    /// - Throws: what the host throws while it builds the configuration.
    public typealias SelectionFactory = @Sendable (_ ids: [String]) throws -> SelectionConfig

    /// The selection tier the host's `factory` makes for `ids`, or `nil` when
    /// there is no factory and discovery answers by retrieval alone.
    ///
    /// The one place the selection tier is wired. `init(registry:...)` and
    /// `makeSessionToolsAndStaging` both build it here.
    ///
    /// **No `preamble:` of this package, and that is a decision this package
    /// measured.** This tool used to seed the tier with a wording of its own,
    /// because the ranker default that shipped then spoke of "items" and
    /// closed on "return an empty list if nothing fits": driven over the
    /// files-and-shell catalog with the agent's own ten queries
    /// (`AgentSurfaceDiscoveryTests`, card `^zqz1zan`),
    /// `mlx-community/Qwen3-4B-4bit` answered eight of the ten with
    /// `{"ids":[]}` — every query for a way to write, edit or run — and the
    /// bench run ended with an empty patch. Ranker card `^zxm99zs` moved the
    /// deciding sentence into `String.selectionDefault` itself. Ranker commit
    /// `dbda1ae` then gave the default new words for this model, and the
    /// deciding sentence is now: "Answer with an empty list only when no
    /// candidate is related to the request at all."
    ///
    /// Card `^46j5hqw` then measured the two wordings against each other on
    /// the same model, the same catalog and the same grammar, three rounds of
    /// the ten queries each. The ranker default answered 30 of 30, held the
    /// write, edit or shell verb in every one of queries 4 to 9 in all three
    /// rounds, and assembled a 7,601-character prefix against the local
    /// wording's 7,600. So the local constant was deleted and the default
    /// takes its place. The preamble is now the host's choice. The Router
    /// discovery seams of the integration suite keep the default, and
    /// `RouterDiscoverySeamsTests` there holds the deciding sentence as the
    /// guard the old constant carried.
    ///
    /// - Parameters:
    ///   - factory: the host's selection factory, or `nil`.
    ///   - ids: every id in the catalog, which the factory receives.
    /// - Returns: the selection configuration, or `nil`.
    /// - Throws: what `factory` throws.
    static func makeSelection(_ factory: SelectionFactory?, ids: [String]) throws -> SelectionConfig? {
        try factory?(ids)
    }

    /// The sample-snippet configuration over the host's `model`, or `nil`
    /// when there is no model and discovery answers with the signatures
    /// alone.
    ///
    /// The one place sample generation is wired. `init(registry:...)` and
    /// `makeSessionToolsAndStaging` both build it here.
    ///
    /// - Parameter model: the host's generation model, or `nil`.
    /// - Returns: the sample configuration, or `nil`.
    static func makeSample(model: (any LanguageModel)?) -> SampleSnippetConfig? {
        model.map { SampleSnippetConfig(model: $0) }
    }
}
