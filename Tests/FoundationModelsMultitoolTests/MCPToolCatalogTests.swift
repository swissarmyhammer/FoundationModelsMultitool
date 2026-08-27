import Foundation
import FoundationModels
import MCP
import Testing

@testable import FoundationModelsMultitool

/// Coverage for the catalog value types of `MCPToolCatalog.swift` and
/// `MCPServerIdentity.swift`: what an ``MCPCatalogEntry`` keeps from an
/// `MCP.Tool`, its content-derived ``MCPCatalogEntry/fingerprint``, the
/// add/remove/change classification of ``MCPToolCatalog/diff(from:)``, and
/// the `Sendable` conformance each catalog type holds.
///
/// A port of the sibling `FoundationModelsMCP` suites `CatalogType` and
/// `LiveCatalog`, renamed so that `swift test --filter MCPToolCatalogTests`
/// selects it. Every case here builds its catalogs from `MCP.Tool` literals,
/// with no live server.
///
/// The cases that need a live `MCPServer` stand in `LiveCatalogTests.swift`
/// and `MCPServerDiscoveryTests.swift` of this target; the headers of those
/// two files name the cases of the source that are not ported.
@Suite("MCPToolCatalogTests")
struct MCPToolCatalogTests {

    // MARK: - Shared test-data constants

    /// How many times the "stable across repeated computation" test builds
    /// an entry from one tool.
    private static let repeatedComputationCount = 5

    /// The epoch of the earlier snapshot in each diff test.
    private static let earlierEpoch = 1

    /// The epoch of the later snapshot in each diff test.
    private static let laterEpoch = 2

    /// The identity every snapshot of this suite carries.
    private static let identity = ServerIdentity(name: "server")

    /// A minimal object-shaped `inputSchema` — one required string property —
    /// used by every test that does not care about schema shape beyond "some
    /// object".
    private static let simpleInputSchema: Value = .object([
        "type": .string("object"),
        "properties": .object([
            "message": .object(["type": .string("string")])
        ]),
        "required": .array([.string("message")]),
    ])

    /// A second, structurally different object-shaped `inputSchema` — a
    /// different required property — used by tests proving the fingerprint
    /// is sensitive to a schema change under the same tool name.
    private static let differentInputSchema: Value = .object([
        "type": .string("object"),
        "properties": .object([
            "count": .object(["type": .string("integer")])
        ]),
        "required": .array([.string("count")]),
    ])

    /// An object-shaped `outputSchema` — one string property — used by the
    /// test proving the entry keeps the output schema verbatim.
    private static let simpleOutputSchema: Value = .object([
        "type": .string("object"),
        "properties": .object([
            "result": .object(["type": .string("string")])
        ]),
    ])

    /// An `inputSchema` whose `$ref` names no `$defs` entry. `SchemaConverter`
    /// parses it, and `emit(_:)` then throws, because `GenerationSchema`
    /// cannot resolve the reference.
    private static let danglingReferenceSchema: Value = .object([
        "type": .string("object"),
        "properties": .object([
            "target": .object(["$ref": .string("#/$defs/Missing")])
        ]),
    ])

    /// Builds an `MCP.Tool` fixture, defaulting to ``simpleInputSchema``.
    ///
    /// - Parameters:
    ///   - name: The tool's name. Defaults to `"search"`.
    ///   - inputSchema: The tool's raw `inputSchema`. Defaults to
    ///     ``simpleInputSchema``.
    ///   - annotations: The tool's annotations. Defaults to empty.
    /// - Returns: The constructed `MCP.Tool`.
    private static func makeTool(
        name: String = "search",
        inputSchema: Value = simpleInputSchema,
        annotations: MCP.Tool.Annotations = nil
    ) -> MCP.Tool {
        MCP.Tool(
            name: name,
            description: "Searches things",
            inputSchema: inputSchema,
            annotations: annotations
        )
    }

    /// Builds an ``MCPToolCatalog`` snapshot at ``earlierEpoch`` with one
    /// entry per name in `toolNames`, all sharing ``simpleInputSchema``.
    ///
    /// - Parameter toolNames: The names of the tools to include, in order.
    /// - Returns: The constructed catalog.
    private static func makeCatalog(toolNames: [String]) throws -> MCPToolCatalog {
        MCPToolCatalog(
            identity: identity,
            epoch: earlierEpoch,
            state: .ready,
            tools: try toolNames.map { try MCPCatalogEntry(tool: Self.makeTool(name: $0)) }
        )
    }

    /// Builds an ``MCPToolCatalog`` snapshot from ready-made entries.
    ///
    /// - Parameters:
    ///   - epoch: The snapshot's generation number.
    ///   - tools: The entries the snapshot carries.
    /// - Returns: The constructed catalog.
    private static func makeCatalog(epoch: Int, tools: [MCPCatalogEntry]) -> MCPToolCatalog {
        MCPToolCatalog(identity: identity, epoch: epoch, state: .ready, tools: tools)
    }

    // MARK: - What an entry keeps

    @Test("an entry keeps the name, title, description, input schema, output schema, annotations, and icons")
    func entryKeepsEveryFieldOfTheTool() throws {
        let icon = MCP.Icon(src: "https://example.com/search.png", mimeType: "image/png")
        let annotations = MCP.Tool.Annotations(title: "Search", readOnlyHint: true)
        let tool = MCP.Tool(
            name: "search",
            title: "Search",
            description: "Searches things",
            inputSchema: Self.simpleInputSchema,
            annotations: annotations,
            outputSchema: Self.simpleOutputSchema,
            icons: [icon]
        )

        let entry = try MCPCatalogEntry(tool: tool)

        #expect(entry.name == "search")
        #expect(entry.title == "Search")
        #expect(entry.description == "Searches things")
        #expect(entry.inputSchema == Self.simpleInputSchema)
        #expect(entry.outputSchema == Self.simpleOutputSchema)
        #expect(entry.annotations == annotations)
        #expect(entry.icons == [icon])
    }

    @Test("an entry keeps an empty description, no output schema, and no icons when the tool declares none")
    func entryDefaultsAbsentFields() throws {
        let tool = MCP.Tool(name: "bare", description: nil, inputSchema: Self.simpleInputSchema)

        let entry = try MCPCatalogEntry(tool: tool)

        #expect(entry.title == nil)
        #expect(entry.description == "")
        #expect(entry.outputSchema == nil)
        #expect(entry.icons.isEmpty)
        #expect(entry.annotations.isEmpty)
    }

    @Test("an entry converts the input schema into a GenerationSchema that names the same properties")
    func entryConvertsTheInputSchema() throws {
        let entry = try MCPCatalogEntry(tool: Self.makeTool())

        // `GenerationSchema` is opaque, and `JSONEncoder` is the one reader
        // FoundationModels gives it, so the encoded JSON is the assertion
        // surface — the same one `AppleEncoderParityTests` reads.
        let data = try JSONEncoder().encode(entry.parameters)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let properties = try #require(object["properties"] as? [String: Any])
        #expect(properties.keys.sorted() == ["message"])
    }

    @Test("an entry throws when the input schema holds a $ref to no $defs entry")
    func entryThrowsOnDanglingReference() {
        #expect(throws: (any Error).self) {
            try MCPCatalogEntry(tool: Self.makeTool(inputSchema: Self.danglingReferenceSchema))
        }
    }

    // MARK: - Fingerprint stability

    @Test("fingerprint is equal for two entries built from identical name, inputSchema, and annotations")
    func fingerprintStableForIdenticalEntries() throws {
        let first = try MCPCatalogEntry(tool: Self.makeTool())
        let second = try MCPCatalogEntry(tool: Self.makeTool())

        #expect(first.fingerprint == second.fingerprint)
    }

    @Test("fingerprint is stable across repeated computation, not just repeated construction")
    func fingerprintStableAcrossRepeatedComputation() throws {
        let tool = Self.makeTool()
        let fingerprints = try (0..<Self.repeatedComputationCount).map { _ in
            try MCPCatalogEntry(tool: tool).fingerprint
        }

        #expect(Set(fingerprints).count == 1)
    }

    // MARK: - Fingerprint sensitivity

    @Test("fingerprint differs when only the inputSchema changes, with the same name")
    func fingerprintDiffersWhenInputSchemaChanges() throws {
        let unchanged = try MCPCatalogEntry(tool: Self.makeTool(inputSchema: Self.simpleInputSchema))
        let changed = try MCPCatalogEntry(tool: Self.makeTool(inputSchema: Self.differentInputSchema))

        #expect(unchanged.name == changed.name)
        #expect(unchanged.fingerprint != changed.fingerprint)
    }

    @Test("fingerprint differs when only annotations change, with the same name and inputSchema")
    func fingerprintDiffersWhenAnnotationsChange() throws {
        let readOnly = try MCPCatalogEntry(
            tool: Self.makeTool(annotations: MCP.Tool.Annotations(readOnlyHint: true)))
        let destructive = try MCPCatalogEntry(
            tool: Self.makeTool(annotations: MCP.Tool.Annotations(destructiveHint: true)))

        #expect(readOnly.name == destructive.name)
        #expect(readOnly.fingerprint != destructive.fingerprint)
    }

    @Test("fingerprint differs when only the name changes, with the same inputSchema")
    func fingerprintDiffersWhenNameChanges() throws {
        let first = try MCPCatalogEntry(tool: Self.makeTool(name: "search"))
        let second = try MCPCatalogEntry(tool: Self.makeTool(name: "find"))

        #expect(first.fingerprint != second.fingerprint)
    }

    // MARK: - The snapshot itself

    @Test("a catalog keeps its identity, epoch, state, and tools in tools/list order")
    func catalogKeepsItsFields() throws {
        let catalog = try Self.makeCatalog(toolNames: ["alpha", "beta"])

        #expect(catalog.identity == Self.identity)
        #expect(catalog.identity.name == "server")
        #expect(catalog.epoch == Self.earlierEpoch)
        #expect(catalog.state == .ready)
        #expect(catalog.tools.map(\.name) == ["alpha", "beta"])
    }

    @Test("a faulted state carries the failure text, and compares by it")
    func faultedStateCarriesItsReason() {
        let faulted = MCPServerState.faulted("boom")

        #expect(faulted == .faulted("boom"))
        #expect(faulted != .faulted("other"))
        #expect(faulted != .connecting)
        #expect(faulted != .ready)
    }

    // MARK: - diff(from:) classification

    @Test("diff(from:) classifies a tool present only in the newer snapshot as added")
    func diffClassifiesAddedTool() throws {
        let previous = try Self.makeCatalog(toolNames: ["alpha"])
        let current = try Self.makeCatalog(toolNames: ["alpha", "beta"])

        let delta = current.diff(from: previous)

        #expect(delta.added.map(\.name) == ["beta"])
        #expect(delta.removed.isEmpty)
        #expect(delta.changed.isEmpty)
    }

    @Test("diff(from:) classifies a tool present only in the older snapshot as removed")
    func diffClassifiesRemovedTool() throws {
        let previous = try Self.makeCatalog(toolNames: ["alpha", "beta"])
        let current = try Self.makeCatalog(toolNames: ["alpha"])

        let delta = current.diff(from: previous)

        #expect(delta.removed.map(\.name) == ["beta"])
        #expect(delta.added.isEmpty)
        #expect(delta.changed.isEmpty)
    }

    @Test("diff(from:) classifies a same-named tool with a changed inputSchema as changed")
    func diffClassifiesChangedTool() throws {
        let previous = Self.makeCatalog(
            epoch: Self.earlierEpoch,
            tools: [try MCPCatalogEntry(tool: Self.makeTool(name: "alpha", inputSchema: Self.simpleInputSchema))]
        )
        let current = Self.makeCatalog(
            epoch: Self.laterEpoch,
            tools: [try MCPCatalogEntry(tool: Self.makeTool(name: "alpha", inputSchema: Self.differentInputSchema))]
        )

        let delta = current.diff(from: previous)

        #expect(delta.changed.map(\.after.name) == ["alpha"])
        #expect(delta.added.isEmpty)
        #expect(delta.removed.isEmpty)
        let change = try #require(delta.changed.first)
        #expect(change.before.fingerprint != change.after.fingerprint)
        #expect(change.before.inputSchema == Self.simpleInputSchema)
        #expect(change.after.inputSchema == Self.differentInputSchema)
    }

    @Test("diff(from:) reports no changes between two snapshots with identical tools")
    func diffReportsNoChangesForIdenticalSnapshots() throws {
        let previous = try Self.makeCatalog(toolNames: ["alpha", "beta"])
        let current = try Self.makeCatalog(toolNames: ["alpha", "beta"])

        let delta = current.diff(from: previous)

        #expect(delta.added.isEmpty)
        #expect(delta.removed.isEmpty)
        #expect(delta.changed.isEmpty)
    }

    @Test("diff(from:) classifies add, remove, and change together in a single mixed snapshot")
    func diffClassifiesMixedDelta() throws {
        let previous = Self.makeCatalog(
            epoch: Self.earlierEpoch,
            tools: [
                try MCPCatalogEntry(tool: Self.makeTool(name: "unchanged")),
                try MCPCatalogEntry(tool: Self.makeTool(name: "removed")),
                try MCPCatalogEntry(tool: Self.makeTool(name: "reschema", inputSchema: Self.simpleInputSchema)),
            ]
        )
        let current = Self.makeCatalog(
            epoch: Self.laterEpoch,
            tools: [
                try MCPCatalogEntry(tool: Self.makeTool(name: "unchanged")),
                try MCPCatalogEntry(tool: Self.makeTool(name: "reschema", inputSchema: Self.differentInputSchema)),
                try MCPCatalogEntry(tool: Self.makeTool(name: "added")),
            ]
        )

        let delta = current.diff(from: previous)

        #expect(delta.added.map(\.name) == ["added"])
        #expect(delta.removed.map(\.name) == ["removed"])
        #expect(delta.changed.map(\.after.name) == ["reschema"])
    }

    // MARK: - Sendable conformance (compile-time)

    /// Compile-time proof that a catalog type is `Sendable` with no
    /// reference-type leakage: this only compiles if the argument type truly
    /// conforms, so a regression that widens any catalog type's stored
    /// properties to something non-`Sendable` fails the build, not just an
    /// assertion.
    ///
    /// - Parameter value: Any `Sendable` value, discarded.
    private func requireSendable(_ value: some Sendable) {
        _ = value
    }

    @Test("ServerIdentity, MCPCatalogEntry, MCPToolCatalog, and MCPToolCatalogDiff are all Sendable")
    func catalogTypesAreSendable() async throws {
        let entry = try MCPCatalogEntry(tool: Self.makeTool())
        let catalog = try Self.makeCatalog(toolNames: ["alpha"])
        let diff = catalog.diff(from: catalog)

        requireSendable(Self.identity)
        requireSendable(entry)
        requireSendable(catalog)
        requireSendable(diff)

        // Also provable by crossing an actual concurrency boundary: this
        // would fail to compile if any of these types were not Sendable.
        await Task {
            requireSendable(entry)
            requireSendable(catalog)
            requireSendable(diff)
        }.value
    }
}
