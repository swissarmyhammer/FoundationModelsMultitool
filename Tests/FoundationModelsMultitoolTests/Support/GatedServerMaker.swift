// `GatedServerMaker` — the server maker a test gives to a `CLIRunner` run.
//
// `CLIRunner` builds the `MCPServer` of each `--mcp` option through a server
// maker. The default maker uses the public initializer, and so each connect
// attempt of a production run is timed on the real clock. A test gives this
// maker instead. It builds each server through `MCPTestSupport.makeServer`,
// whose connect-attempt clock is a `GatedClock` that no test opens. Thus no
// connect attempt of the run times out, however slow the machine is (card
// `^zbhjc99`: no test checks the speed of the machine).

import Synchronization

@testable import FoundationModelsMultitool

/// Builds each `MCPServer` that a `CLIRunner` run attaches, with a
/// connect-attempt clock that no test opens, and records each server it
/// built, in the order it built them.
///
/// State lives behind a `Mutex`, because `CLIRunner` calls ``makeServer(name:)``
/// through a `@Sendable` closure.
final class GatedServerMaker: Sendable {
    /// One server ``makeServer(name:)`` built, beside the name it was given.
    ///
    /// The name stands here because `MCPServer.name` is isolated to the
    /// actor, and a test reads the record outside it.
    struct Built: Sendable {
        /// The name the server was built with.
        let name: String

        /// The server, not yet connected when it was built.
        let server: MCPServer
    }

    /// Every server ``makeServer(name:)`` built, in call order.
    private let records = Mutex<[Built]>([])

    /// Every server ``makeServer(name:)`` built, in call order.
    var built: [Built] {
        records.withLock { $0 }
    }

    /// Builds one server through ``MCPTestSupport/makeServer(name:clock:clientQueueClock:connectAttemptClock:callTimeout:renderBudget:elicitationHandler:logger:)``,
    /// and records it.
    ///
    /// - Parameter name: The name of the server — the `<name>` of its
    ///   `--mcp` option.
    /// - Returns: The server, not yet connected.
    func makeServer(name: String) -> MCPServer {
        let server = MCPTestSupport.makeServer(name: name)
        records.withLock { $0.append(Built(name: name, server: server)) }
        return server
    }
}
