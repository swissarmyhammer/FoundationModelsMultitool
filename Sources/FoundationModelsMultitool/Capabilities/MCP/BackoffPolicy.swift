// `BackoffPolicy` — the retry schedule of a connect, the factory that builds
// the transport each attempt connects over, and the errors the connect path
// throws.
//
// A behavioral port of the `BackoffPolicy`, `TransportFactory` and
// `MCPServerError` declarations of
// `../FoundationModelsMCP/Sources/FoundationModelsMCP/MCPServer.swift`. The
// `callTimedOut` case of the source error is not ported: it belongs to the
// call path, which a later task rewrites onto the run plane of Router.
//
// **The types are `public`.** A host constructs a `BackoffPolicy` and hands
// it to `MCPServer.connect(via:backoffPolicy:)`, and it catches an
// `MCPServerError` from that call, so both cross the module boundary.

import MCP

/// Configuration for the connect-retry and reconnect backoff of `MCPServer`
/// — see `MCPServer.connect(via:backoffPolicy:)`.
///
/// A failed or timed-out connect attempt is retried with exponential backoff:
/// ``baseDelay`` after the first failure, twice the previous delay after every
/// failure after that, capped at ``maxDelay``, up to ``maxAttempts`` attempts
/// in total, each bounded by ``connectTimeout``. The caller hard-fails only
/// once every attempt is spent. A server reconnects with the same policy it
/// last connected with.
public struct BackoffPolicy: Sendable, Equatable {
    /// How many seconds ``defaultConnectTimeout`` lasts.
    private static let defaultConnectTimeoutSeconds = 10

    /// How many milliseconds ``defaultBackoffBaseDelay`` lasts.
    private static let defaultBackoffBaseDelayMilliseconds = 250

    /// How many seconds ``defaultBackoffMaxDelay`` lasts.
    private static let defaultBackoffMaxDelaySeconds = 30

    /// The default ``connectTimeout`` — see that property.
    public static let defaultConnectTimeout = Duration.seconds(defaultConnectTimeoutSeconds)

    /// The default ``baseDelay`` — see that property.
    public static let defaultBackoffBaseDelay = Duration.milliseconds(
        defaultBackoffBaseDelayMilliseconds)

    /// The default ``maxDelay`` — see that property.
    public static let defaultBackoffMaxDelay = Duration.seconds(defaultBackoffMaxDelaySeconds)

    /// The default ``maxAttempts`` — see that property.
    public static let defaultBackoffMaxAttempts = 5

    /// The maximum wall-clock time one connect attempt may take before it is
    /// abandoned in favor of the next retry. Defaults to 10 seconds.
    public var connectTimeout: Duration

    /// The delay before the second attempt; every attempt after that doubles
    /// the previous delay, capped at ``maxDelay``. Defaults to 250
    /// milliseconds.
    public var baseDelay: Duration

    /// The maximum delay between attempts, however many attempts failed
    /// before. Defaults to 30 seconds.
    public var maxDelay: Duration

    /// The maximum number of connect attempts before the connect fails with
    /// ``MCPServerError/backoffExhausted(serverName:attempts:lastError:)``.
    /// Defaults to 5.
    public var maxAttempts: Int

    /// Creates a backoff policy.
    ///
    /// - Parameters:
    ///   - connectTimeout: The per-attempt timeout. Defaults to 10 seconds.
    ///   - baseDelay: The delay before the second attempt. Defaults to 250
    ///     milliseconds.
    ///   - maxDelay: The delay cap. Defaults to 30 seconds.
    ///   - maxAttempts: The maximum number of attempts. Defaults to 5.
    public init(
        connectTimeout: Duration = BackoffPolicy.defaultConnectTimeout,
        baseDelay: Duration = BackoffPolicy.defaultBackoffBaseDelay,
        maxDelay: Duration = BackoffPolicy.defaultBackoffMaxDelay,
        maxAttempts: Int = BackoffPolicy.defaultBackoffMaxAttempts
    ) {
        self.connectTimeout = connectTimeout
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.maxAttempts = maxAttempts
    }

    /// The default policy: a 10-second per-attempt timeout, a 250 millisecond
    /// initial backoff that doubles up to a 30-second cap, and 5 attempts.
    public static let `default` = BackoffPolicy()
}

/// A closure that produces a fresh `Transport` on demand, called by
/// `MCPServer` one time per connect attempt — the first attempt, every
/// backoff retry, and every later `MCPServer.reconnect()`.
///
/// This is what makes a reconnect work for a transport like `StdioTransport`,
/// whose two file descriptors belong to a subprocess: the sdk's
/// `StdioTransport` wraps file descriptors and never spawns a process, so a
/// dead stdio server comes back only when something respawns it. A retry of
/// `connect()` on the same, already-dead instance can never succeed for such a
/// transport. A factory closes that gap: for stdio, `StdioServerProcess.respawn`
/// spawns a fresh subprocess on every call; for a transport that re-establishes
/// itself when reused (an HTTP transport that redials on `connect()`), a
/// factory can return the same instance every time.
///
/// `MCPServer` never constructs a `Transport` itself outside of this closure.
public typealias TransportFactory = @Sendable () async throws -> any Transport

/// Errors thrown by the own operations of `MCPServer`, distinct from what the
/// wrapped `MCP.Client` or its transport throws.
public enum MCPServerError: Error, Sendable, Equatable {
    /// A caller asked for a ready server — `MCPServer.waitUntilReady()` — and
    /// the state can no longer reach `MCPServerState.ready` without a new
    /// connect: it is `faulted` or `disconnected`. Carries the state at the
    /// time of the call for diagnostics.
    case notReady(MCPServerState)

    /// Every attempt of one `MCPServer.connect(via:backoffPolicy:)` call
    /// failed — carries the name of the server, how many attempts were made,
    /// and a human-readable description of the last underlying failure.
    case backoffExhausted(serverName: String, attempts: Int, lastError: String)

    /// A `MCPServer.connect(via:backoffPolicy:)` factory call failed with an
    /// error whose `NonRetryableConnectError` conformance answers
    /// `isNonRetryable == true` — a stdio server's absent or non-executable
    /// `command` path, say — a permanent configuration problem, not a flaky
    /// connection. Carries the name of the server and a human-readable
    /// description of the underlying failure.
    ///
    /// Unlike ``backoffExhausted(serverName:attempts:lastError:)``, this fires
    /// after exactly one attempt: the connect never retries, and never sleeps
    /// between attempts for, an error classified this way.
    case connectConfigurationFailed(serverName: String, underlying: String)

    /// One single connect attempt inside the retry loop of
    /// `MCPServer.connect(via:backoffPolicy:)` exceeded its
    /// ``BackoffPolicy/connectTimeout``.
    case connectAttemptTimedOut

    /// `MCPServer.reconnect()` was called on a server that no `connect(via:)`
    /// call ever gave a transport factory to, so there is nothing to
    /// reconnect through.
    case neverConnected
}
