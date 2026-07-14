import Foundation
import FoundationModelsRouter

/// Derives an xgrammar JSON Schema constraining a `{"ids": [...]}` selection
/// response to exactly `ids` (plan.md §6 "Ids only, grammar-enforced") — the
/// selection-tier rewire's standalone, GPU-free grammar helper.
///
/// `FoundationModelsMetadataRegistry`'s own equivalent,
/// `SelectionTier.idEnumGrammar(ids:)`, is package-internal on purpose — the
/// registry's documented integrator path
/// (`../FoundationModelsMetadataRegistry/Examples/LiveRouterSupport/LiveRouterSupport.swift`'s
/// own `idEnumGrammar(ids:)`) is to build the equivalent schema by hand, the
/// same way any integrator outside the package would. `MetadataSearcher`'s
/// `.selection` tier still verifies every returned id against its current
/// candidate set regardless of how the grammar was built
/// (`.unknownSelectedId`), so this hand-built schema only needs to keep the
/// model honest about the response *shape* — an object with one `ids` array
/// of enum-constrained strings.
///
/// - Parameter ids: the candidate id set to constrain output to.
/// - Returns: the xgrammar-ready `Grammar.jsonSchema(_:)`.
/// - Throws: an encoding error if `ids` can't be serialized to JSON (not
///   expected for a plain array of strings).
func idEnumGrammar(ids: [String]) throws -> Grammar {
    let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "ids": [
                "type": "array",
                "items": ["type": "string", "enum": ids],
                "uniqueItems": true,
                // A hard structural cap on the array's length: a selection
                // can never legitimately contain more ids than there are
                // candidates. This is the constraint that actually stops
                // runaway generation — the xgrammar pipeline enforces
                // `maxItems` but silently ignores `uniqueItems`, so without
                // it the compiled grammar permits an unbounded-length array
                // of repeated enum members (observed as a deterministic
                // ~6150-token, ~190s runaway on `PrefixReuseTests`' off-topic
                // second `findAPIs` call). Mirrors the same fix in the
                // registry's own `SelectionTier.idEnumGrammar(ids:)`.
                "maxItems": ids.count,
            ] as [String: Any]
        ],
        "required": ["ids"],
    ]
    let data = try JSONSerialization.data(withJSONObject: schema)
    return .jsonSchema(String(decoding: data, as: UTF8.self))
}
