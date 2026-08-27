// `MCPServerPool` — the servers of one session, and the one call that shuts
// them all down after the session sweep.
//
// eventplan.md § "Consolidation of the siblings": "To kill a server
// subprocess is a host-level act on each in-flight call that it carries. It
// is not a run cancellation." And § "Background tools and the completion
// token": "MCP requests get the advisory cancel and post `.cancelled` before
// the transport closes." The two sentences fix an order at session end:
//
//   1. The session sweep, `SessionMailbox.sweep()`, cancels every parked run.
//      A cancelled `MCPServer.call` sends `notifications/cancelled`.
//   2. The host calls `shutdownAll()` on this pool. `MCPServer.disconnect()`
//      waits for each notice of step 1 to reach the wire, then closes the
//      transport; `StdioServerProcess.shutdown()` then ends the subprocess.
//
// Servers are infrastructure with session lifetime. No mailbox tracks them,
// no `status()` lists them, and they get no `completionToken`. The shell store
// of the same session is released the same way — with the session, and never
// through the run plane — and this pool is the MCP side of that release.
//
// **What records into the pool.** `MultiTool.Builder.withMCP(servers:)`
// records each server it registers into the pool of the builder, thus a host
// that registered its servers through the builder holds every one of them in
// `builder.serverPool`. A `StdioServerProcess` is not visible to `withMCP`:
// the host connects a server through `stdio.respawn`, and it adds the process
// through `add(process:)` itself.
//
// **The attachment.** A later task attaches a surface refresher — the watcher
// of `catalogUpdates` that rebuilds the registry — to the pool. This file does
// not build it; it states the hook: an optional `Stoppable`, stopped first by
// `shutdownAll()`, so nothing re-lists against a server this pool is closing.

/// What a host attaches to an ``MCPServerPool`` so that `shutdownAll()`
/// stops it before it closes the servers.
public protocol Stoppable: Sendable {
    /// Stops the work, and returns once it stopped.
    func stop() async
}

/// The servers of one session, their subprocesses, and one attachment —
/// shut down together by ``shutdownAll()``.
public actor MCPServerPool {
    /// Every server recorded, in the order it was added.
    private var servers: [MCPServer] = []

    /// Every subprocess recorded, in the order it was added.
    private var processes: [StdioServerProcess] = []

    /// The attachment ``shutdownAll()`` stops first, or `nil`.
    private var attachment: (any Stoppable)?

    /// Creates an empty pool.
    public init() {}

    /// Whether the pool holds no server, no subprocess and no attachment.
    public var isEmpty: Bool {
        servers.isEmpty && processes.isEmpty && attachment == nil
    }

    /// Records `server`, so ``shutdownAll()`` disconnects it. A server
    /// already recorded is recorded one time.
    ///
    /// - Parameter server: The server to record.
    public func add(server: MCPServer) {
        guard !servers.contains(where: { $0 === server }) else { return }
        servers.append(server)
    }

    /// Records `process`, so ``shutdownAll()`` shuts it down.
    ///
    /// - Parameter process: The subprocess to record.
    public func add(process: StdioServerProcess) {
        processes.append(process)
    }

    /// Attaches `attachment`, which ``shutdownAll()`` stops before it closes
    /// any server. A later attachment replaces the one before it.
    ///
    /// - Parameter attachment: What to stop first.
    public func attach(attachment: any Stoppable) {
        self.attachment = attachment
    }

    /// Stops the attachment, disconnects each server, and shuts each
    /// subprocess down — in that order — and empties the pool.
    ///
    /// A host calls this after the session sweep. Each `MCPServer.disconnect()`
    /// waits for the advisory cancels the sweep started, thus every one is on
    /// the wire before its transport closes. Calling this on an empty pool
    /// does nothing.
    public func shutdownAll() async {
        await attachment?.stop()
        attachment = nil
        for server in servers {
            await server.disconnect()
        }
        servers = []
        for process in processes {
            await process.shutdown()
        }
        processes = []
    }
}
