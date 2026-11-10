// `MCPHandshakeDropTests` — a stdio server that exits before it answers
// `initialize`.
//
// The `MCP.Client` of the SDK ends its wait for the answer to `initialize`
// only on its own `disconnect()` or on a cancel. Before this fix, the end of
// the stream of the server came to `handleTransportDrop`, which failed only
// the tool calls in flight. Thus `connect(via:)` waited with no end, and the
// state stayed `.connecting`.
//
// Now a drop during the handshake tears down the client of that attempt, and
// `connect(via:)` throws. No test uses a clock: each test waits for the end of
// the connect. Before the fix, these tests did not end.

import Foundation
import FoundationModelsExtras
import MCP
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

@Suite("MCPHandshakeDrop")
struct MCPHandshakeDropTests {
    /// The name of each server and each process of this suite.
    private static let serverName = "handshakeDropServer"

    /// The shell that runs each script.
    private static let shell = "/bin/sh"

    /// A server that exits at once, before it reads a line.
    private static let exitAtOnce = "exit 0"

    /// A server that reads the `initialize` request, then exits with no
    /// answer.
    private static let readThenExit = "read line; exit 0"

    /// A server that reads the `initialize` request, then exits with a
    /// failure and no answer.
    private static let readThenFail = "read line; exit 1"

    /// A server that answers `initialize` with a result that has the id and
    /// the protocol version of the request, then reads each line until the
    /// `tools/list` request, and exits with no answer. Thus the transport
    /// drops during the discovery of the tools, after the `initialize` step.
    private static let answerInitializeThenExitAtToolsList = answerInitialize + #"""
        while read line; do
          case "$line" in
            *tools/list*) exit 0 ;;
          esac
        done
        """#

    /// The control of ``answerInitializeThenExitAtToolsList``: the same
    /// answer to `initialize`, then an answer to `tools/list` with no tools,
    /// then a wait until the input ends. A connect to this server gets to
    /// `.ready`. Thus the answer to `initialize` is correct, and the drop of
    /// the script above comes during the discovery.
    private static let answerInitializeAndToolsList = answerInitialize + #"""
        while read line; do
          case "$line" in
            *tools/list*)
              id=$(printf '%s' "$line" | sed -E 's/.*"id":("[^"]*"|[0-9]+).*/\1/')
              printf '{"jsonrpc":"2.0","id":%s,"result":{"tools":[]}}\n' "$id" ;;
          esac
        done
        """#

    /// The first part of each script that answers `initialize`: reads the
    /// request, and writes a result with the id and the protocol version of
    /// the request.
    private static let answerInitialize = #"""
        read line
        id=$(printf '%s' "$line" | sed -E 's/.*"id":("[^"]*"|[0-9]+).*/\1/')
        version=$(printf '%s' "$line" | sed -E 's/.*"protocolVersion":"([^"]*)".*/\1/')
        printf '{"jsonrpc":"2.0","id":%s,"result":{"protocolVersion":"%s","capabilities":{"tools":{}},"serverInfo":{"name":"drop","version":"1"}}}\n' "$id" "$version"

        """#

    /// Connects a server over a stdio process that runs `script`, and gives
    /// the server after the connect ended.
    ///
    /// - Parameter script: the script that the shell runs as the server.
    /// - Returns: the server, and the error of the connect, or `nil` when
    ///   the connect did not throw.
    private static func connect(
        toScript script: String
    ) async throws -> (server: MCPServer, error: (any Error)?) {
        let stdio = try StdioServerProcess(
            command: shell, args: ["-c", script], name: serverName, registry: ProcessRegistry())
        let server = MCPTestSupport.makeServer(name: serverName)
        do {
            try await server.connect(via: stdio.respawn)
        } catch {
            return (server, error)
        }
        return (server, nil)
    }

    /// Whether `state` is `.faulted`.
    ///
    /// - Parameter state: the state to read.
    /// - Returns: `true` for `.faulted`.
    private static func isFaulted(_ state: MCPServerState) -> Bool {
        if case .faulted = state { return true }
        return false
    }

    @Test(
        "a stdio server that exits before it answers initialize or tools/list makes connect throw, and the state is faulted",
        arguments: [exitAtOnce, readThenExit, readThenFail, answerInitializeThenExitAtToolsList])
    func exitBeforeInitializeFaults(script: String) async throws {
        let (server, error) = try await Self.connect(toScript: script)

        #expect(error != nil)
        let state = await server.state
        #expect(Self.isFaulted(state))
        await server.disconnect()
    }

    @Test("a stdio server that answers initialize and tools/list gets to ready")
    func answeringServerIsReady() async throws {
        let (server, error) = try await Self.connect(toScript: Self.answerInitializeAndToolsList)

        #expect(error == nil)
        let state = await server.state
        #expect(state == .ready)
        await server.disconnect()
    }
}
