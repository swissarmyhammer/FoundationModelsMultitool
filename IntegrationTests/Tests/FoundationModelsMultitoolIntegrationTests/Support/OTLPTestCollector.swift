// `OTLPTestCollector` — a loopback HTTP server that records OTLP/HTTP requests.
//
// `CLISignalExitTests` starts the built `multitool-cli` as a child process and
// points `OTEL_EXPORTER_OTLP_ENDPOINT` at this collector. The OTLP exporters
// of swift-otel send each batch as one HTTP/1.1 `POST` with a
// `Content-Length`, to `/v1/traces`, `/v1/logs` or `/v1/metrics`. This
// collector keeps the path and the body of each request, and it answers each
// one with `200 OK` and an empty body, which is an empty export response.
//
// `LoopbackHTTPServer` of `MCPTestServer` does not apply here: it routes the
// requests of a `URLSession` in the same process, and a child process can
// reach only a real socket.

import Foundation
import Network
import os

/// A loopback HTTP server that keeps each OTLP/HTTP request it gets.
final class OTLPTestCollector: Sendable {
    /// The failures of ``start()``.
    enum CollectorError: Error {
        /// The listener failed before it was ready.
        case listenerFailed(String)
    }

    /// The listener of the collector.
    private let listener: NWListener

    /// The requests that the listener got.
    private let requests: OTLPRequestLog

    /// The OTLP endpoint of the collector, for `OTEL_EXPORTER_OTLP_ENDPOINT`.
    let endpoint: String

    /// Makes a collector over a ready listener.
    ///
    /// - Parameters:
    ///   - listener: The listener, in the ready state.
    ///   - requests: The log that the connection handler of the listener
    ///     fills.
    ///   - port: The port that the listener listens on.
    private init(listener: NWListener, requests: OTLPRequestLog, port: NWEndpoint.Port) {
        self.listener = listener
        self.requests = requests
        self.endpoint = "http://127.0.0.1:\(port.rawValue)"
    }

    /// Starts a collector on a free port of the loopback interface.
    ///
    /// - Returns: The collector, ready for requests.
    /// - Throws: ``CollectorError/listenerFailed(_:)`` when the listener
    ///   fails, and what `NWListener` throws.
    static func start() async throws -> OTLPTestCollector {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        let listener = try NWListener(using: parameters, on: .any)
        let requests = OTLPRequestLog()
        // A listener fails with `EINVAL` when it starts with no connection
        // handler, thus the handler is set before the start.
        listener.newConnectionHandler = { connection in requests.serve(connection) }
        let port = try await ready(listener)
        return OTLPTestCollector(listener: listener, requests: requests, port: port)
    }

    /// The bodies of the requests to `path`, in the order they came.
    ///
    /// - Parameter path: The path, for example `/v1/traces`.
    /// - Returns: The bodies.
    func bodies(at path: String) -> [Data] {
        requests.bodies(at: path)
    }

    /// Stops the listener.
    func stop() {
        listener.cancel()
    }

    /// Starts `listener` and waits until it is ready.
    ///
    /// - Parameter listener: The listener to start.
    /// - Returns: The port that the listener listens on.
    /// - Throws: ``CollectorError/listenerFailed(_:)`` when the listener
    ///   fails or stops before it is ready.
    private static func ready(_ listener: NWListener) async throws -> NWEndpoint.Port {
        let states = AsyncStream<NWListener.State> { continuation in
            listener.stateUpdateHandler = { continuation.yield($0) }
        }
        // The listener starts after its handler is set, thus no state is lost.
        listener.start(queue: DispatchQueue(label: "OTLPTestCollector.listener"))
        for await state in states {
            switch state {
            case .ready:
                guard let port = listener.port else { break }
                return port
            case .failed(let error):
                throw CollectorError.listenerFailed("\(error)")
            case .cancelled:
                throw CollectorError.listenerFailed("the listener stopped")
            case .setup, .waiting:
                continue
            @unknown default:
                continue
            }
        }
        throw CollectorError.listenerFailed("the listener gave no state")
    }
}

/// The requests that the connections of an ``OTLPTestCollector`` got, and
/// the answers to them.
private final class OTLPRequestLog: Sendable {
    /// One request that the collector got.
    private struct Request: Sendable {
        /// The path of the request, for example `/v1/traces`.
        let path: String

        /// The body of the request: an OTLP protobuf message.
        let body: Data
    }

    /// The number of bytes in one kibibyte.
    private static let bytesPerKibibyte = 1024

    /// The largest number of kibibytes that one receive of a connection reads.
    private static let receiveChunkKibibytes = 64

    /// The largest number of bytes that one receive of a connection reads.
    private static let receiveChunkSize = receiveChunkKibibytes * bytesPerKibibyte

    /// The separator between the name and the value of an HTTP header field.
    private static let headerFieldSeparator: Character = ":"

    /// The number of parts of a header field that has a value: the name and
    /// the value.
    private static let headerFieldPartCount = 2

    /// The bytes that end the header of an HTTP request.
    private static let headerEnd = Data("\r\n\r\n".utf8)

    /// The separator of the lines of an HTTP header.
    private static let lineSeparator = "\r\n"

    /// The name of the header that gives the length of the body, in lower
    /// case.
    private static let contentLengthHeader = "content-length"

    /// The answer to each request: `200 OK` with an empty body.
    private static let okResponse = Data(
        "HTTP/1.1 200 OK\r\nContent-Type: application/x-protobuf\r\nContent-Length: 0\r\n\r\n".utf8)

    /// The queue of each connection.
    private let queue = DispatchQueue(label: "OTLPTestCollector.connections")

    /// The requests, in the order they came.
    private let received = OSAllocatedUnfairLock<[Request]>(initialState: [])

    /// The bodies of the requests to `path`, in the order they came.
    ///
    /// - Parameter path: The path, for example `/v1/traces`.
    /// - Returns: The bodies.
    func bodies(at path: String) -> [Data] {
        received.withLock { $0.filter { $0.path == path }.map(\.body) }
    }

    /// Starts `connection` and answers each request on it.
    ///
    /// - Parameter connection: A new connection of the listener.
    func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, pending: Data())
    }

    /// Reads from `connection`, keeps each full request, and answers it.
    ///
    /// - Parameters:
    ///   - connection: The connection to read.
    ///   - pending: The bytes that came before and are not a full request yet.
    private func receive(on connection: NWConnection, pending: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: Self.receiveChunkSize) {
            [self] data, _, isComplete, error in
            var buffer = pending + (data ?? Data())
            while let request = Self.takeRequest(from: &buffer) {
                received.withLock { $0.append(request) }
                connection.send(content: Self.okResponse, completion: .contentProcessed { _ in })
            }
            guard !isComplete, error == nil else {
                connection.cancel()
                return
            }
            receive(on: connection, pending: buffer)
        }
    }

    /// Takes the first full request out of `buffer`.
    ///
    /// - Parameter buffer: The bytes that came on one connection. The bytes of
    ///   the request are removed from it.
    /// - Returns: The request, or `nil` when `buffer` does not hold a full
    ///   request yet.
    private static func takeRequest(from buffer: inout Data) -> Request? {
        guard let headerRange = buffer.range(of: headerEnd) else { return nil }
        let header = String(decoding: buffer[buffer.startIndex..<headerRange.lowerBound], as: UTF8.self)
        let lines = header.components(separatedBy: lineSeparator)
        let path = lines.first?.split(separator: " ").dropFirst().first.map(String.init) ?? ""
        let bodyStart = headerRange.upperBound
        let bodyEnd = bodyStart + contentLength(in: lines.dropFirst())
        guard buffer.endIndex >= bodyEnd else { return nil }
        let request = Request(path: path, body: Data(buffer[bodyStart..<bodyEnd]))
        buffer = Data(buffer[bodyEnd...])
        return request
    }

    /// The value of the `Content-Length` header.
    ///
    /// - Parameter headerLines: The header lines after the request line.
    /// - Returns: The length of the body, or `0` when no line gives it.
    private static func contentLength(in headerLines: ArraySlice<String>) -> Int {
        let lengthField = headerLines
            .map { $0.split(separator: headerFieldSeparator, maxSplits: 1) }
            .first { $0.count == headerFieldPartCount && $0.first?.lowercased() == contentLengthHeader }
        return lengthField?.last.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } ?? 0
    }
}
