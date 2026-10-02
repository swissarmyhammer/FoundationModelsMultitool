// `HeldScriptedTool` — a scripted MCP tool whose call holds until the test
// releases it.
//
// A test that must act while a call is in flight held that call with a slow
// tool before: many progress steps, or a long sleep. That is a time window. A
// slow machine can close the window before the test acts, and no test checks
// the speed of the machine (card `^pfvdg5b`). This tool holds each call on a
// `ReleaseGate` in its place. The test waits for the event that the call
// arrived, acts, and then releases the gate. No time sets the order.

import MCP
import MCPTestServer
import Synchronization

/// A scripted MCP tool that records each call that arrives at its handler,
/// and then holds that call until ``release()``.
///
/// `ReleaseGate` holds one waiter, thus a test sends one call at a time to
/// this tool.
final class HeldScriptedTool: Sendable {
    /// The text each call answers after the release.
    static let releasedText = "released"

    /// The name of the tool.
    let name: String

    /// The gate each call waits on.
    private let gate = ReleaseGate()

    /// How many calls arrived at the handler.
    private let arrivals = Mutex(0)

    /// Makes a held tool.
    ///
    /// - Parameter name: The name of the tool.
    init(named name: String) {
        self.name = name
    }

    /// Whether a call arrived at the handler: the server is in the call, and
    /// the call holds.
    var hasArrived: Bool {
        arrivals.withLock { $0 > 0 }
    }

    /// The definition and the handler, for `ScriptedServer.addTool(_:)`.
    var scriptedTool: ScriptedTool {
        ScriptedTool(
            definition: MCP.Tool(
                name: name, description: "Holds each call until the test releases it.",
                inputSchema: JSONSchemaBuilder.emptySchema)
        ) { _ in
            self.arrivals.withLock { $0 += 1 }
            await self.gate.wait()
            return CallTool.Result(content: [.text(text: Self.releasedText, annotations: nil, _meta: nil)])
        }
    }

    /// Ends the hold: the call that waits answers, and each later call
    /// answers at once.
    func release() async {
        await gate.release()
    }
}
