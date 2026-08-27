// `MCPToolCatalog` — a versioned snapshot of every tool one MCP server
// declares, and the delta between two snapshots.
//
// A behavioral port of `../FoundationModelsMCP/Sources/FoundationModelsMCP/
// ToolCatalog.swift`. eventplan.md § "Consolidation of the siblings" moves
// "the `ToolCatalog`" into this folder. The rebuild-and-swap task is the
// reader: it diffs the snapshot a re-list produced against the snapshot the
// registry was built from, and it swaps only when the delta is not empty.
//
// **The names differ from the sibling's.** This package already declares
// `ToolDescriptor` in `Surface/ToolDescriptor.swift`, the registry entry of
// each verb, and the sibling declared a `ToolDescriptor` of its own for the
// catalog. So the three types are renamed: `ToolCatalog` is `MCPToolCatalog`,
// `ToolDescriptor` is `MCPCatalogEntry`, and `ToolCatalogDiff` is
// `MCPToolCatalogDiff`. `ToolAnnotations` stays a typealias of
// `MCP.Tool.Annotations`.
//
// **What is not ported.** The sibling's `init(mcpTool:)` reused the
// `GenerationSchema` an already-converted `MCPTool` held. `MCPTool` comes in
// a later task, and this catalog reads `MCP.Tool` only, so every entry
// converts its own `inputSchema` through `SchemaConverter`.
//
// **Why the fingerprint is a SHA-256 digest, and not `Hasher`.** Swift's
// `Hasher` is seeded per process, so two snapshots taken in two runs can
// never compare by hash. The digest is stable: two entries with the same
// name, `inputSchema`, and annotations carry the same fingerprint in any
// process, and a persisted log can be compared against a live catalog. The
// fingerprint is advisory for consumer indexing only, never a gate on a
// call: a schema-changed tool's call still goes through, and the server
// validates it.
//
// **The types are internal.** The Shell capability keeps its types internal,
// and this folder does the same: `MCPServer`, which comes in a later task, is
// the production writer, and the tests reach the types with
// `@testable import`.

import CryptoKit
import Foundation
import FoundationModels
import MCP

/// A tool's display-facing and operational hints, verbatim from the
/// swift-sdk's `MCP.Tool.Annotations` — see that type's own documentation
/// for the exact hint semantics (`readOnlyHint`, `destructiveHint`,
/// `idempotentHint`, `openWorldHint`, and a display `title`).
///
/// Reused rather than reinvented: the wire shape the swift-sdk already
/// decodes from a server's `tools/list` response is exactly the shape the
/// catalog carries, so a parallel type here would only duplicate it.
typealias ToolAnnotations = MCP.Tool.Annotations

/// A single tool's catalog-facing metadata: name, display title, description,
/// the server's raw `inputSchema` and `outputSchema` verbatim, the input
/// schema converted for constrained generation, operational
/// ``ToolAnnotations``, icons, and a content-derived ``fingerprint`` other
/// snapshots can diff against.
///
/// A plain `Sendable` value type — see ``MCPToolCatalog``'s own documentation
/// for why the catalog surface is snapshot values rather than a live
/// reference type.
struct MCPCatalogEntry: Sendable {
    /// The tool's name, exactly as declared by the server.
    let name: String

    /// The tool's human-readable display title, or `nil` if the server
    /// declared none.
    let title: String?

    /// The tool's description, or an empty string if the server declared
    /// none.
    let description: String

    /// The tool's raw JSON Schema `inputSchema`, exposed **verbatim** — never
    /// the converted ``parameters`` — for callers that need full schema
    /// fidelity.
    let inputSchema: Value

    /// The tool's raw JSON Schema `outputSchema`, exposed **verbatim**, or
    /// `nil` if the server declared none. `ToolContentRenderer` reads it to
    /// render a `structuredContent` result.
    let outputSchema: Value?

    /// The tool's argument schema, converted from ``inputSchema`` via
    /// `SchemaConverter` — the schema a `LanguageModelSession` constrains
    /// generation against.
    let parameters: GenerationSchema

    /// The tool's operational hints, verbatim from the server.
    let annotations: ToolAnnotations

    /// The tool's icons, or an empty array if the server declared none.
    let icons: [MCP.Icon]

    /// A stable content hash of ``name``, ``inputSchema``, and
    /// ``annotations`` — equal for two entries with identical content,
    /// different if any of the three changes (even with the same ``name``).
    ///
    /// A hex-encoded SHA-256 digest of a key-sorted JSON encoding of the
    /// three, deliberately not Swift's randomly-seeded `Hasher` — so two
    /// independently-constructed catalog snapshots (in the same process, a
    /// later run, or a persisted log) can be compared for tool-level change
    /// using only their fingerprints, without holding onto the prior
    /// snapshot's actual ``MCPCatalogEntry`` values. Advisory for consumer
    /// indexing only: never a gate on whether a call is allowed to proceed —
    /// a schema-changed tool's call still goes through, and the server
    /// validates it.
    let fingerprint: String

    /// Creates an entry by converting `tool.inputSchema` via
    /// `SchemaConverter`.
    ///
    /// - Parameter tool: The source MCP tool definition to adapt.
    /// - Throws: Whatever `SchemaConverter.emit(_:)` throws if
    ///   `tool.inputSchema` parses into an invalid `DynamicGenerationSchema`
    ///   type graph (e.g. a `$ref` with no matching `$defs` entry, or a
    ///   duplicate type name).
    init(tool: MCP.Tool) throws {
        let conversion = SchemaConverter.parse(tool.inputSchema, name: tool.name)
        self.name = tool.name
        self.title = tool.title
        self.description = tool.description ?? ""
        self.inputSchema = tool.inputSchema
        self.outputSchema = tool.outputSchema
        self.parameters = try SchemaConverter.emit(conversion)
        self.annotations = tool.annotations
        self.icons = tool.icons ?? []
        self.fingerprint = Self.computeFingerprint(
            name: tool.name, inputSchema: tool.inputSchema, annotations: tool.annotations)
    }

    /// The `Encodable` triple ``computeFingerprint(name:inputSchema:annotations:)``
    /// hashes — its own type only exists to give `JSONEncoder` one value to
    /// encode in a single call, so the encoder's `.sortedKeys` formatting
    /// applies recursively to every nested object inside `inputSchema` too,
    /// not just this payload's own top-level keys.
    private struct FingerprintPayload: Encodable {
        /// The tool's name. Read by the synthesized `Encodable` conformance;
        /// periphery sees no caller.
        // periphery:ignore
        let name: String

        /// The tool's raw `inputSchema`. Read by the synthesized `Encodable`
        /// conformance; periphery sees no caller.
        // periphery:ignore
        let inputSchema: Value

        /// The tool's operational hints. Read by the synthesized `Encodable`
        /// conformance; periphery sees no caller.
        // periphery:ignore
        let annotations: ToolAnnotations
    }

    /// Computes ``fingerprint``: a hex-encoded SHA-256 digest of `name`,
    /// `inputSchema`, and `annotations`, encoded together as JSON with
    /// alphabetically-sorted object keys so the result never depends on
    /// `Value.object`'s dictionary iteration order.
    ///
    /// - Parameters:
    ///   - name: The tool's name.
    ///   - inputSchema: The tool's raw `inputSchema`.
    ///   - annotations: The tool's operational hints.
    /// - Returns: A stable, hex-encoded digest — identical across processes
    ///   and runs for identical input, different if any parameter changes.
    private static func computeFingerprint(
        name: String, inputSchema: Value, annotations: ToolAnnotations
    ) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // A non-conforming float can only occur here via a hand-built Value
        // literal (e.g. in a test) — JSON itself can't represent NaN or
        // infinity, so any inputSchema sourced from a real tools/list decode
        // never contains one. Configuring a string fallback (rather than the
        // default `.throw`) keeps this computation total either way.
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        let payload = FingerprintPayload(name: name, inputSchema: inputSchema, annotations: annotations)
        guard let data = try? encoder.encode(payload) else {
            fatalError(
                "FingerprintPayload encoding should never throw: name and inputSchema/annotations "
                    + "are plain value types with no custom encode(to:), and the only throwing path "
                    + "(non-conforming Double) is defused by .convertToString above")
        }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// A versioned, point-in-time snapshot of everything one MCP server exposes:
/// its stable ``ServerIdentity``, a per-server ``epoch`` that increases every
/// time a new snapshot replaces this one, the server's current
/// ``MCPServerState``, and every tool it currently declares.
///
/// The catalog is a stream of versioned snapshots, never transmitted deltas:
/// each snapshot is self-contained and idempotent (a consumer can start
/// fresh from any one snapshot with no prior state), and ``diff(from:)``
/// derives an add/remove/change delta between two snapshots locally, on
/// demand.
struct MCPToolCatalog: Sendable {
    /// This server's stable identity — see ``ServerIdentity``.
    let identity: ServerIdentity

    /// A per-server generation number, incremented every time a new snapshot
    /// replaces this one (a fresh discovery, a coalesced `list_changed`
    /// re-list, a reconnect, or a readiness-state change) — never reset for
    /// the life of the owning `MCPServer`.
    let epoch: Int

    /// The server's readiness at the moment this snapshot was taken.
    let state: MCPServerState

    /// Every tool the server currently declares, in `tools/list` page order.
    let tools: [MCPCatalogEntry]

    /// Classifies every tool that changed between `previous` and this
    /// snapshot: tools present here but not in `previous`
    /// (``MCPToolCatalogDiff/added``), tools present in `previous` but not
    /// here (``MCPToolCatalogDiff/removed``), and tools present in both under
    /// the same ``MCPCatalogEntry/name`` whose ``MCPCatalogEntry/fingerprint``
    /// differs (``MCPToolCatalogDiff/changed``) — e.g. the server re-declared
    /// the same tool with a different `inputSchema` or annotations.
    ///
    /// - Parameter previous: The earlier snapshot to diff against.
    /// - Returns: The classified delta.
    func diff(from previous: MCPToolCatalog) -> MCPToolCatalogDiff {
        let previousByName = Dictionary(
            previous.tools.map { ($0.name, $0) }, uniquingKeysWith: { _, latest in latest })
        let currentNames = Set(tools.map(\.name))

        var added: [MCPCatalogEntry] = []
        var changed: [MCPToolCatalogDiff.ChangedTool] = []
        for tool in tools {
            guard let prior = previousByName[tool.name] else {
                added.append(tool)
                continue
            }
            if prior.fingerprint != tool.fingerprint {
                changed.append(MCPToolCatalogDiff.ChangedTool(before: prior, after: tool))
            }
        }
        let removed = previous.tools.filter { !currentNames.contains($0.name) }

        return MCPToolCatalogDiff(added: added, removed: removed, changed: changed)
    }
}

/// The add/remove/change delta ``MCPToolCatalog/diff(from:)`` derives between
/// two ``MCPToolCatalog`` snapshots of the same server.
struct MCPToolCatalogDiff: Sendable {
    /// One same-named tool whose ``MCPCatalogEntry/fingerprint`` changed
    /// between two snapshots, carrying both the earlier and later entry so a
    /// consumer can report exactly what changed.
    struct ChangedTool: Sendable {
        /// The tool's entry in the earlier snapshot.
        let before: MCPCatalogEntry

        /// The tool's entry in the later snapshot.
        let after: MCPCatalogEntry
    }

    /// Every tool present in the newer snapshot under a `name` absent from
    /// the older one.
    let added: [MCPCatalogEntry]

    /// Every tool present in the older snapshot under a `name` absent from
    /// the newer one.
    let removed: [MCPCatalogEntry]

    /// Every same-named tool present in both snapshots whose
    /// ``MCPCatalogEntry/fingerprint`` differs between them.
    let changed: [ChangedTool]
}
