import FoundationModelsMetadataRegistry
import FoundationModelsRouter

/// The Router grammar that limits a selection response to a set of ids
/// (plan.md §6 "Ids only, grammar-enforced").
///
/// The schema itself comes from the ranker: `SelectionTier.idEnumSchema(ids:)`
/// derives it from the `Selection` type the tier decodes, puts an `enum` of
/// the ids on each item, and caps the array at `maxItems`. That cap is what
/// stops runaway generation, because the xgrammar pipeline enforces
/// `maxItems` but ignores `uniqueItems` (observed as a deterministic
/// ~6150-token, ~190s runaway on the off-topic second `searchTools` call of
/// the integration suite now named `SelectionForkPerCallTests`). This type
/// only wraps that schema in Router's `Grammar`, which the ranker does not
/// know.
///
/// `MetadataSearcher`'s `.selection` tier still verifies every returned id
/// against its current candidate set (`.unknownSelectedId`), so the grammar
/// only needs to keep the model honest about the response *shape*.
public enum SelectionGrammar {
    /// The xgrammar-ready grammar for `ids`.
    ///
    /// - Parameter ids: the candidate id set to constrain output to.
    /// - Returns: `Grammar.jsonSchema(_:)` over the ranker's id schema.
    /// - Throws: what `SelectionTier.idEnumSchema(ids:)` throws, which is not
    ///   expected for the fixed shape of `Selection`.
    public static func idEnumGrammar(ids: [String]) throws -> Grammar {
        .jsonSchema(try SelectionTier.idEnumSchema(ids: ids))
    }
}
