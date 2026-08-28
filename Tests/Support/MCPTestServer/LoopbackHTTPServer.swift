// `LoopbackHTTPServer` — an in-process HTTP loopback over the scripted server.
//
// This file has no source in `../FoundationModelsMCP`. It joins two halves
// the swift-sdk already ships: `StatefulHTTPServerTransport`, which answers
// one `HTTPRequest` with one `HTTPResponse`, and `HTTPClientTransport`, which
// builds its own `URLSession` from a `URLSessionConfiguration`. The join is a
// `URLProtocol` subclass registered in that configuration, not a socket: each
// request the client session makes is routed to `handleRequest(_:)` of the
// server transport, and the response — a body, or an SSE stream — is relayed
// back to the session. Test support — see the header of `ScriptedServer.swift`.
//
// **Headers relay verbatim.** The default validation pipeline of the server
// transport stays: `OriginValidator.localhost()`, `AcceptHeaderValidator(mode:
// .sseRequired)`, `ContentTypeValidator`, `ProtocolVersionValidator` and
// `SessionValidator`. A `URLRequest` handed to a `URLProtocol` carries every
// header the client set — `Accept`, `Content-Type`, `MCP-Protocol-Version`,
// `MCP-Session-Id` — and no `Host` or `Origin`, so the origin validator reads
// nothing and every other validator reads what the client sent.

import Foundation
import MCP
import Synchronization
import TestConcurrency

/// Serves one ``ScriptedServer`` over HTTP inside the test process.
///
/// ``start()`` returns the endpoint and the `URLSessionConfiguration` a
/// client passes to `HTTPClientTransport(endpoint:configuration:)`. Every
/// request that session sends to the endpoint reaches the
/// `StatefulHTTPServerTransport` of this loopback without a socket.
///
/// A started loopback is held by a process-wide registry, which the
/// `URLProtocol` consults, until ``stop()`` removes it. The caller of
/// ``start()`` calls ``stop()`` at the end of its test.
///
/// ``start()`` and ``stop()`` also take and give back one process-wide gate.
/// As a result, only one loopback of the whole process can hold an open SSE
/// stream at any one time. See `concurrencyGate` for more on this.
public actor LoopbackHTTPServer {
    /// The path of every loopback endpoint.
    private static let endpointPath = "/mcp"

    /// The scheme of every loopback endpoint.
    private static let endpointScheme = "http"

    /// The prefix of the host label that identifies one loopback.
    private static let hostPrefix = "loopback-"

    /// The HTTP method of a standalone SSE stream request.
    private static let eventStreamMethod = "GET"

    /// The request and resource timeout of the `URLSessionConfiguration`
    /// ``start()`` returns.
    ///
    /// A loopback never reaches a real network. Each request routes to
    /// `LoopbackURLProtocol`, in the same process, over `Task`s on the
    /// shared cooperative thread pool. Foundation's default request
    /// timeout is 60 seconds. That value fits a call to a real, remote
    /// server that has truly stalled. It does not fit a same-process
    /// transport, which has no real network delay of its own. Under the
    /// full parallel `swift test` run, that shared pool can delay a relayed
    /// message past 60 seconds on its own, with no request truly stuck.
    /// That delay showed up as a false `NSURLErrorTimedOut` failure. This
    /// longer timeout gives a delayed message more room to arrive, without
    /// hiding a request that will truly never finish.
    private static let requestTimeout: TimeInterval = 120

    /// The started loopbacks, by the host of their endpoint. A `Mutex`, and
    /// not an actor, because `URLProtocol.canInit(with:)` is synchronous.
    private static let registry = Mutex<[String: LoopbackHTTPServer]>([:])

    /// The one gate that makes ``start()`` and ``stop()`` run one at a time,
    /// for the whole test process. As a result, only one loopback can hold an
    /// open SSE stream at any one time.
    ///
    /// A `.serialized` `@Suite` trait puts the tests of ONE suite in order. It
    /// does not put one suite in order against another suite. Two suites can
    /// each connect over `.http` — for example, `LoopbackHTTPServerTests` and
    /// `MCPElicitationTests`. By default, these two suites can still run at the
    /// same time. Each one then holds its own open SSE stream through
    /// `URLSession`, on the shared cooperative thread pool. Several open
    /// streams at once — across suites, not only inside one suite — push that
    /// pool past the point where a server-to-client message stalls and does not
    /// arrive. See the header of this file, and `LoopbackHTTPServerTests`, for
    /// more on this. This gate holds every loopback of the process to one
    /// active loopback at a time. That is the same limit every suite that opens
    /// a loopback already treats as safe. The gate does this by making
    /// ``start()`` wait for the prior loopback's ``stop()`` to finish first.
    private static let concurrencyGate = ConcurrencyGate()

    /// The scripted server this loopback serves.
    private let scripted: ScriptedServer

    /// The server transport every request is routed to.
    private let transport: StatefulHTTPServerTransport

    /// The host of the endpoint, and the key of this loopback in the registry.
    private let host: String

    /// Whether a standalone SSE stream (a `GET`) is being served.
    ///
    /// A server-initiated message goes to that stream only, so a test that
    /// elicits or notifies waits for this reading before it calls.
    public private(set) var isServingEventStream = false

    /// Creates a loopback over `scripted`, not yet started.
    ///
    /// - Parameter scripted: The server to serve.
    public init(serving scripted: ScriptedServer) {
        self.scripted = scripted
        self.transport = StatefulHTTPServerTransport()
        self.host = Self.hostPrefix + UUID().uuidString.lowercased()
    }

    /// Starts the scripted server on the server transport, registers this
    /// loopback, and returns what a client needs to reach it.
    ///
    /// - Returns: The endpoint, and a session configuration whose
    ///   `protocolClasses` routes the endpoint to this loopback.
    /// - Throws: What `ScriptedServer.start(transport:)` throws.
    public func start() async throws -> (endpoint: URL, configuration: URLSessionConfiguration) {
        await Self.concurrencyGate.acquire()
        do {
            try await scripted.start(transport: transport)
        } catch {
            await Self.concurrencyGate.release()
            throw error
        }
        Self.registry.withLock { $0[host] = self }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LoopbackURLProtocol.self]
        configuration.timeoutIntervalForRequest = Self.requestTimeout
        configuration.timeoutIntervalForResource = Self.requestTimeout
        return (endpoint: endpoint, configuration: configuration)
    }

    /// Removes this loopback from the registry, and ends the session of the
    /// server transport. This closes every open stream. It then releases
    /// `concurrencyGate`, so the next loopback's ``start()`` can proceed.
    public func stop() async {
        _ = Self.registry.withLock { $0.removeValue(forKey: host) }
        isServingEventStream = false
        await transport.disconnect()
        await Self.concurrencyGate.release()
    }

    /// The URL a client connects to.
    private var endpoint: URL {
        var components = URLComponents()
        components.scheme = Self.endpointScheme
        components.host = host
        components.path = Self.endpointPath
        guard let url = components.url else {
            preconditionFailure("A loopback endpoint of host \(host) did not form a URL")
        }
        return url
    }

    /// The registered loopback the request of `url` is for, if any.
    ///
    /// - Parameter url: The URL of a request the client session makes.
    /// - Returns: The loopback, or `nil` when no started loopback owns the
    ///   host of `url`.
    static func loopback(for url: URL?) -> LoopbackHTTPServer? {
        guard let host = url?.host else { return nil }
        return registry.withLock { $0[host] }
    }

    /// Routes one request to the server transport.
    ///
    /// - Parameter request: The request, converted from the `URLRequest`.
    /// - Returns: What the server transport answered.
    func handle(_ request: HTTPRequest) async -> HTTPResponse {
        let response = await transport.handleRequest(request)
        if request.method == Self.eventStreamMethod, case .stream = response {
            isServingEventStream = true
        }
        return response
    }
}

/// What ``LoopbackURLProtocol`` fails a request with.
enum LoopbackHTTPError: Error {
    /// The request named no started loopback, or no URL.
    case noLoopback

    /// The response of the server transport did not form an `HTTPURLResponse`.
    case invalidResponse
}

/// The `URLProtocol` that routes a request of a client session to the
/// ``LoopbackHTTPServer`` that owns its host.
///
/// `@unchecked Sendable`: the loader owns this instance and calls
/// `startLoading()` and `stopLoading()` one after the other. The one state
/// this class adds, the relay task, is behind a `Mutex`, so the task started
/// by one call is what the other call cancels.
final class LoopbackURLProtocol: URLProtocol, @unchecked Sendable {
    /// The HTTP version every relayed response reports.
    private static let httpVersion = "HTTP/1.1"

    /// How many bytes one read of a request body stream takes.
    private static let bodyReadBufferSize = 4096

    /// The HTTP method of a `URLRequest` that names none.
    private static let defaultMethod = "GET"

    /// The task that relays the response, or `nil` before `startLoading()`.
    private let relay = Mutex<Task<Void, Never>?>(nil)

    override class func canInit(with request: URLRequest) -> Bool {
        LoopbackHTTPServer.loopback(for: request.url) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url, let loopback = LoopbackHTTPServer.loopback(for: url) else {
            client?.urlProtocol(self, didFailWithError: LoopbackHTTPError.noLoopback)
            return
        }
        let httpRequest = HTTPRequest(
            method: request.httpMethod ?? Self.defaultMethod,
            headers: request.allHTTPHeaderFields ?? [:],
            body: Self.body(of: request),
            path: url.path
        )
        let task = Task {
            let response = await loopback.handle(httpRequest)
            await self.deliver(response, for: url)
        }
        relay.withLock { $0 = task }
    }

    override func stopLoading() {
        let task = relay.withLock { running -> Task<Void, Never>? in
            defer { running = nil }
            return running
        }
        task?.cancel()
    }

    /// The body of `request`: `httpBody` when set, otherwise the whole of
    /// `httpBodyStream`, which is how the loader hands a body to a protocol.
    ///
    /// - Parameter request: The request of the client session.
    /// - Returns: The body, or `nil` when the request carries none.
    private static func body(of request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }
        stream.open()
        defer { stream.close() }
        var body = Data()
        var buffer = [UInt8](repeating: 0, count: bodyReadBufferSize)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            body.append(buffer, count: count)
        }
        return body
    }

    /// Relays `response` to the client of this protocol: the status and
    /// headers first, then the body — every chunk of an SSE stream as it
    /// arrives — then the end of the load.
    ///
    /// - Parameters:
    ///   - response: What the server transport answered.
    ///   - url: The URL of the request, which the `HTTPURLResponse` names.
    private func deliver(_ response: HTTPResponse, for url: URL) async {
        guard
            let urlResponse = HTTPURLResponse(
                url: url, statusCode: response.statusCode,
                httpVersion: Self.httpVersion, headerFields: response.headers)
        else {
            client?.urlProtocol(self, didFailWithError: LoopbackHTTPError.invalidResponse)
            return
        }
        client?.urlProtocol(self, didReceive: urlResponse, cacheStoragePolicy: .notAllowed)
        switch response {
        case .stream(let stream, _):
            await relayStream(stream)
        case .accepted, .ok, .data, .error:
            if let body = response.bodyData {
                client?.urlProtocol(self, didLoad: body)
            }
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    /// Relays every chunk of `stream` as it arrives, then ends the load.
    ///
    /// A cancelled relay — `stopLoading()` ran — reports nothing more: the
    /// loader stopped listening.
    ///
    /// - Parameter stream: The SSE stream of the server transport.
    private func relayStream(_ stream: AsyncThrowingStream<Data, any Error>) async {
        do {
            for try await chunk in stream {
                client?.urlProtocol(self, didLoad: chunk)
            }
            guard !Task.isCancelled else { return }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            guard !Task.isCancelled else { return }
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}
