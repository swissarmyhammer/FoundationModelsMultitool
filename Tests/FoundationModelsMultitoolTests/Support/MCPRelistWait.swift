// `MCPRelistWait` — the one wait of the MCP suites for the end of the re-list
// that a `tools/list_changed` notification starts.
//
// Test rule T1: each wait of a test must also end on the failure event, or
// the test must fail before it waits. `MCPServer.catalogUpdates` finishes
// only when the server goes away, thus a read of that stream for the snapshot
// of a re-list does not end when the re-list emits no snapshot. A test thus
// first waits here for the end of the re-list, then checks that the re-list
// emitted the snapshot, and only then reads the stream: the stream keeps each
// snapshot until a reader takes it, thus that read ends.
//
// The wait for the count of notifications is the internal test hook
// `MCPServer.waitUntilToolListChangedGeneration(reaches:)`. That hook ends on
// a cancel, and it has no second event: it stands on the T1 exception list.

@testable import FoundationModelsMultitool

extension MCPTestSupport {
    /// Runs `action`, and waits until `server` counted the `notifications`
    /// `tools/list_changed` notifications that `action` sends.
    ///
    /// The count of `server` is read before `action` runs, thus the wait is
    /// for the notifications of `action` only.
    ///
    /// - Parameters:
    ///   - server: The server that counts the notifications.
    ///   - notifications: How many notifications `action` sends.
    ///   - action: The change that sends the notifications.
    /// - Throws: What `action` throws.
    static func waitForNotifications(
        of server: MCPServer, count notifications: Int, sentBy action: () async throws -> Void
    ) async rethrows {
        let generationBefore = await server.toolListChangedGeneration
        try await action()
        await server.waitUntilToolListChangedGeneration(reaches: generationBefore + notifications)
    }

    /// Runs `action`, and waits until `server` counted the `notifications`
    /// notifications that `action` sends, and the re-list for them ended —
    /// see ``waitForNotifications(of:count:sentBy:)`` and
    /// ``waitForRelistEnd(of:)``.
    ///
    /// - Parameters:
    ///   - server: The server that re-lists.
    ///   - notifications: How many notifications `action` sends.
    ///   - action: The change that sends the notifications.
    /// - Throws: What `action` throws.
    static func waitForRelist(
        of server: MCPServer, after notifications: Int, sentBy action: () async throws -> Void
    ) async rethrows {
        try await waitForNotifications(of: server, count: notifications, sentBy: action)
        await waitForRelistEnd(of: server)
    }

    /// Waits until the re-list task of `server` ended, when one runs.
    ///
    /// The server starts its re-list task, or keeps the one that runs, in
    /// the same actor step that counts a notification. That task re-lists
    /// until no notification arrived during a round trip, emits its snapshot,
    /// and only then ends. It clears its own entry and emits in one actor
    /// step, thus a server with no task in its entry already emitted. Thus
    /// the end of that task is the end of the re-list. The task ends by
    /// itself once its coalesce window ends on the clock of the server.
    ///
    /// - Parameter server: The server that re-lists.
    static func waitForRelistEnd(of server: MCPServer) async {
        let relist = await server.coalescingTask
        await relist?.value
    }
}
