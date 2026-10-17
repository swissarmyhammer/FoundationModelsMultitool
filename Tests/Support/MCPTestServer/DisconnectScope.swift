// `DisconnectScope` — the scoped teardown of connected `MCPServer` values.
//
// Test support — see the header of `ScriptedServer.swift`.
//
// Test rule T1: a fixture closes also when the test body throws. Swift has no
// `defer` that can wait for an `async` call, thus a test that connects a
// server gives its body to ``DisconnectScope/disconnecting(_:after:)``, which
// awaits each disconnect on each path. The unit test target has its own
// `MCPTestSupport.withConnection(of:_:)`, which also closes an `MCP.Client`,
// but it stands in the unit test target. This product is the place that the
// nested `IntegrationTests` package and the large catalog mount reach.

import FoundationModelsMultitool

/// The awaited teardown of the `MCPServer` values that a test connected.
public enum DisconnectScope {

    /// Runs `body`, and then disconnects each server in `servers`, also when
    /// `body` throws.
    ///
    /// `MCPServer.disconnect()` is idempotent. Thus `body` can disconnect a
    /// server itself.
    ///
    /// - Parameters:
    ///   - servers: The connected servers to disconnect.
    ///   - body: The work of the test on the servers.
    /// - Returns: What `body` returned.
    /// - Throws: What `body` threw, after each disconnect.
    public static func disconnecting<Result>(
        _ servers: [MCPServer], after body: () async throws -> Result
    ) async throws -> Result {
        let result: Result
        do {
            result = try await body()
        } catch {
            await disconnect(servers)
            throw error
        }
        await disconnect(servers)
        return result
    }

    /// Disconnects each server in `servers`, one after the other.
    ///
    /// - Parameter servers: The servers to disconnect.
    public static func disconnect(_ servers: [MCPServer]) async {
        for server in servers {
            await server.disconnect()
        }
    }
}
