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
            ] as [String: Any]
        ],
        "required": ["ids"],
    ]
    let data = try JSONSerialization.data(withJSONObject: schema)
    return .jsonSchema(String(decoding: data, as: UTF8.self))
}
