import Foundation
import FoundationModelsRouter
import Testing

@testable import FoundationModelsMultitool

/// Coverage for `idEnumGrammar(ids:)` (plan.md §6 "Ids only,
/// grammar-enforced"): the hand-built xgrammar JSON Schema constraining a
/// `.selection`-tier guided response to exactly a given candidate id set —
/// mirrors `FoundationModelsMetadataRegistry`'s documented integrator path
/// (`Examples/LiveRouterSupport/LiveRouterSupport.swift`'s own
/// `idEnumGrammar(ids:)`), copied here because `SelectionTier`'s own
/// equivalent is package-internal to the registry.
@Suite("idEnumGrammar")
struct SelectionGrammarTests {
    /// Decodes the schema JSON out of a built `Grammar`, failing the test if
    /// the grammar isn't a `.jsonSchema` case or the source isn't valid JSON.
    ///
    /// - Parameter grammar: the grammar to decode.
    /// - Returns: the parsed schema as a `[String: Any]` dictionary.
    private static func decodeSchema(_ grammar: Grammar) throws -> [String: Any] {
        guard case .jsonSchema(let source) = grammar else {
            Issue.record("expected a .jsonSchema grammar")
            return [:]
        }
        let object = try JSONSerialization.jsonObject(with: Data(source.utf8))
        guard let dictionary = object as? [String: Any] else {
            Issue.record("expected the schema source to decode to a JSON object")
            return [:]
        }
        return dictionary
    }

    @Test("the schema's top-level type is object with ids required")
    func schemaTopLevelShapeIsObjectRequiringIds() throws {
        let schema = try Self.decodeSchema(idEnumGrammar(ids: ["alpha.beta", "gamma.delta"]))

        #expect(schema["type"] as? String == "object")
        #expect(schema["required"] as? [String] == ["ids"])
    }

    @Test("the schema's ids property is a uniqueItems array of the given enum ids")
    func schemaIdsPropertyIsUniqueEnumArray() throws {
        let ids = ["alpha.beta", "gamma.delta", "epsilon.zeta"]
        let schema = try Self.decodeSchema(idEnumGrammar(ids: ids))

        let properties = try #require(schema["properties"] as? [String: Any])
        let idsSchema = try #require(properties["ids"] as? [String: Any])
        #expect(idsSchema["type"] as? String == "array")
        #expect(idsSchema["uniqueItems"] as? Bool == true)

        let items = try #require(idsSchema["items"] as? [String: Any])
        #expect(items["type"] as? String == "string")
        #expect(items["enum"] as? [String] == ids)
    }

    @Test("an empty ids input still produces a well-formed schema with an empty enum")
    func emptyIdsProducesWellFormedSchemaWithEmptyEnum() throws {
        let schema = try Self.decodeSchema(idEnumGrammar(ids: []))

        #expect(schema["type"] as? String == "object")
        #expect(schema["required"] as? [String] == ["ids"])
        let properties = try #require(schema["properties"] as? [String: Any])
        let idsSchema = try #require(properties["ids"] as? [String: Any])
        let items = try #require(idsSchema["items"] as? [String: Any])
        #expect(items["enum"] as? [String] == [])
    }

    // MARK: - Selection sessions are constrained to exactly the surface's entry paths

    @Test("idEnumGrammar(ids:) fed a real registry's entry paths — MultiToolAgent.makeFindApiSearcher's own derivation — constrains the enum to exactly those paths, qualified paths included")
    func idEnumGrammarConstrainedToSurfaceEntryPaths() throws {
        let registry = try MultiTool.Builder()
            .addTool(TripCitiesTool())
            .addGroup(named: "github", [GithubCreateIssueTool()])
            .buildRegistry()

        let schema = try Self.decodeSchema(idEnumGrammar(ids: registry.surface.entries.map(\.path)))

        let properties = try #require(schema["properties"] as? [String: Any])
        let idsSchema = try #require(properties["ids"] as? [String: Any])
        let items = try #require(idsSchema["items"] as? [String: Any])
        #expect(items["enum"] as? [String] == ["tripCities", "github.createIssue"])
    }
}
