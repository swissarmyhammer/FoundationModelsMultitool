// `MCPServer+Discovery` — the paginated `tools/list` round trip, the tools a
// connected server vends, and the one point that emits a catalog snapshot.
//
// A behavioral port of `discoverAllTools()`, `mcpTools()`, `tool(named:)`,
// `catalog`, `makeCatalogSnapshot(epoch:identity:)` and
// `emitCatalogSnapshot()` of
// `../FoundationModelsMCP/Sources/FoundationModelsMCP/MCPServer.swift`.
//
// **What a discovered tool is here.** The source stored each tool as an
// `MCPTool` — the call-path adapter — and converted it to a descriptor for
// the catalog. The call path is not ported, so each tool is stored as the
// `MCPCatalogEntry` the catalog carries, converted from the `MCP.Tool` of the
// wire at discovery time. `mcpTools()` and `tool(named:)` vend that entry.
// `foundationModelsTools()` of the source is gone with `MCPTool`.
//
// **Why the whole list is read on every round trip.** A one-page read
// silently truncates whenever the server paginates its `tools/list`
// response; the loop over `nextCursor` is what stands between a caller and
// that truncation. The conversion happens here, while `connect(via:)` can
// still fail, and not at a vend point: a malformed `inputSchema` faults the
// connect, so a caller never holds a tool it cannot use.
//
// **The surface is internal.** `MCPCatalogEntry` and `MCPToolCatalog` are
// internal — see the header of `MCPToolCatalog.swift` — so the methods that
// vend them are internal too. The rebuild-and-swap task, in this package, is
// the reader.

import MCP
import os

extension MCPServer {
    /// Fetches every tool page from the server through the paginated
    /// `tools/list`, following `nextCursor` until the server returns none,
    /// and converts each `MCP.Tool` to an `MCPCatalogEntry`.
    ///
    /// - Returns: One entry per tool across every page, in page order.
    /// - Throws: What `MCP.Client.listTools(cursor:)` throws, or what
    ///   `MCPCatalogEntry.init(tool:)` throws for a malformed `inputSchema`.
    func discoverAllTools() async throws -> [MCPCatalogEntry] {
        var allTools: [MCP.Tool] = []
        var cursor: String?
        repeat {
            let page = try await client.listTools(cursor: cursor)
            allTools.append(contentsOf: page.tools)
            cursor = page.nextCursor
        } while cursor != nil
        return try allTools.map { try MCPCatalogEntry(tool: $0) }
    }

    /// The tools the most recent successful discovery returned — the
    /// paginated `tools/list` of the connect, or the coalesced re-list a
    /// `tools/list_changed` burst started.
    ///
    /// - Returns: One entry per tool the server declared, in `tools/list`
    ///   page order.
    /// - Throws: ``MCPServerError/notReady(_:)`` when ``state`` is not
    ///   `.ready`.
    func mcpTools() throws -> [MCPCatalogEntry] {
        guard case .ready = state else {
            throw MCPServerError.notReady(state)
        }
        return discoveredTools
    }

    /// Resolves `name` against the CURRENT catalog — ``discoveredTools`` as
    /// of this call, not whatever snapshot a caller last read from
    /// ``catalogUpdates``.
    ///
    /// Unlike ``mcpTools()``, never throws: a tool absent from the current
    /// catalog — because ``state`` never reached `.ready`, or because a
    /// coalesced re-list removed it — resolves to `nil`, for a caller that
    /// cached an earlier reference to notice.
    ///
    /// - Parameter name: The tool name to resolve.
    /// - Returns: The matching entry, or `nil` when no currently-discovered
    ///   tool has that name.
    func tool(named name: String) -> MCPCatalogEntry? {
        discoveredTools.first { $0.name == name }
    }

    /// The current catalog snapshot: ``identity``, ``catalogEpoch``,
    /// ``state``, and every currently-discovered tool.
    ///
    /// Keyed on ``identity`` having been established, not on ``state`` being
    /// `.ready`, so a snapshot taken while the server is `.faulted` after a
    /// prior successful connect still succeeds, and reports the last-known
    /// tools beside the current state.
    ///
    /// - Throws: ``MCPServerError/notReady(_:)`` when no `connect(via:)` call
    ///   ever fully succeeded.
    var catalog: MCPToolCatalog {
        get throws {
            guard let identity else {
                throw MCPServerError.notReady(state)
            }
            return makeCatalogSnapshot(epoch: catalogEpoch, identity: identity)
        }
    }

    /// Builds a snapshot from ``discoveredTools`` and ``state`` as they stand
    /// now — the one construction behind ``catalog`` and
    /// ``emitCatalogSnapshot()``.
    ///
    /// - Parameters:
    ///   - epoch: The generation number of the snapshot.
    ///   - identity: The established identity of the server.
    /// - Returns: The snapshot.
    private func makeCatalogSnapshot(epoch: Int, identity: ServerIdentity) -> MCPToolCatalog {
        MCPToolCatalog(identity: identity, epoch: epoch, state: state, tools: discoveredTools)
    }

    /// Increments ``catalogEpoch`` and yields a new snapshot on
    /// ``catalogUpdates`` — a no-op before the first successful connect,
    /// because there is no ``identity`` to snapshot yet.
    ///
    /// The one emission point: a connect that reaches `.ready`, a connect
    /// that fails after a prior success, and a coalesced re-list all funnel
    /// through here, so ``catalogEpoch`` only ever advances beside an actual
    /// emission.
    func emitCatalogSnapshot() {
        guard let identity else { return }
        catalogEpoch += 1
        catalogContinuation.yield(makeCatalogSnapshot(epoch: catalogEpoch, identity: identity))
    }
}
