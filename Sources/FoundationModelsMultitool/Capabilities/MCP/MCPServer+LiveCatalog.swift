// `MCPServer+LiveCatalog` — the coalesced re-list a burst of
// `tools/list_changed` notifications starts.
//
// A behavioral port of the section `// MARK: - Live catalog: coalesced
// tools/list_changed re-list` of
// `../FoundationModelsMCP/Sources/FoundationModelsMCP/MCPServer.swift`:
// `handleToolListChangedNotification()`, `coalesceAndRelist()` and
// `relistOnce()`. eventplan.md § "Consolidation of the siblings": "an MCP
// `tools/list_changed` starts a full rebuild" — the snapshot this re-list
// emits on `catalogUpdates` is what that rebuild consumes.
//
// **Why one watcher, and why it re-checks.** A server that changes several
// tools at once sends several notifications back to back. The first one
// starts one watcher; every later one advances a generation counter the
// watcher reads back. The watcher sleeps out the coalesce window one time on
// the injected clock, then re-lists until a whole round trip completes with
// no new notification during it, and emits exactly one snapshot for the whole
// burst.
//
// **What cancellation does.** `disconnect()` cancels the watcher. A watcher
// that finds itself cancelled after its window re-lists nothing and emits
// nothing: there is no client to ask, and the next connect discovers afresh.

import MCP
import os

extension MCPServer {
    /// How many milliseconds ``toolListChangedCoalesceWindow`` lasts.
    private static let toolListChangedCoalesceWindowMilliseconds = 50

    /// How long a burst of `tools/list_changed` notifications must go quiet
    /// before `coalesceAndRelist()` re-lists — measured on `clock`, so a
    /// virtual clock in a test exercises the whole window with no real delay.
    private static let toolListChangedCoalesceWindow = Duration.milliseconds(
        toolListChangedCoalesceWindowMilliseconds)

    /// What one inbound `notifications/tools/list_changed` reaches: advances
    /// ``toolListChangedGeneration`` and, when no watcher is running, starts
    /// one.
    ///
    /// A burst that arrives back to back starts one watcher; every further
    /// notification only advances the generation, which the running watcher
    /// observes on its next check — so a burst of any size produces exactly
    /// one re-list once it goes quiet.
    func handleToolListChangedNotification() {
        toolListChangedGeneration += 1
        logger.debug(
            "MCPServer \(self.identityNameForDiagnostics, privacy: .public) received tools/list_changed"
        )
        guard !isCoalescingToolListChanged else { return }
        isCoalescingToolListChanged = true
        coalescingTask = Task { await self.coalesceAndRelist() }
    }

    /// Waits out ``toolListChangedCoalesceWindow`` one time, then re-lists
    /// until a whole round trip completes with no further notification during
    /// it, and emits one snapshot when the last round trip succeeded.
    ///
    /// The initial sleep catches a burst that arrives before this task even
    /// runs; the repeat-until-stable loop catches stragglers that arrive
    /// DURING a round trip — a real cross-actor exchange, never zero-latency,
    /// so a concurrently arriving notification has genuine room to reach
    /// ``handleToolListChangedNotification()`` before the loop re-checks the
    /// generation.
    private func coalesceAndRelist() async {
        try? await clock.sleep(for: Self.toolListChangedCoalesceWindow)
        guard !Task.isCancelled else {
            finishCoalescing()
            return
        }
        var observedGeneration: Int
        var lastRelistSucceeded = false
        repeat {
            observedGeneration = toolListChangedGeneration
            lastRelistSucceeded = await relistOnce()
        } while observedGeneration != toolListChangedGeneration
        finishCoalescing()
        if lastRelistSucceeded {
            emitCatalogSnapshot()
        }
    }

    /// Clears the watcher state ``handleToolListChangedNotification()`` set,
    /// so the next notification starts a new watcher — the one exit every
    /// path of `coalesceAndRelist()` goes through.
    private func finishCoalescing() {
        isCoalescingToolListChanged = false
        coalescingTask = nil
    }

    /// Runs one discovery round trip and, on success, replaces
    /// ``discoveredTools``.
    ///
    /// A failure is logged and otherwise swallowed, and leaves
    /// ``discoveredTools`` and ``catalogEpoch`` as they were: unlike a
    /// failed `connect(via:)`, a transient `tools/list` failure mid-burst
    /// does not change ``state`` or fault the connection.
    ///
    /// - Returns: `true` when discovery succeeded and ``discoveredTools`` was
    ///   replaced; `false` when it failed and nothing changed.
    private func relistOnce() async -> Bool {
        do {
            discoveredTools = try await discoverAllTools()
            return true
        } catch {
            logger.warning(
                "MCPServer \(self.identityNameForDiagnostics, privacy: .public) failed to re-list tools after tools/list_changed: \(String(describing: error), privacy: .public)"
            )
            return false
        }
    }
}
