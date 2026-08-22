import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Behavioral tests for `ShellOutputChunkStream` — the live view a host outside
/// this module subscribes to.
///
/// Each test drives the stream itself, and no test starts a child process. The
/// stream takes each chunk from its producer through `send` and `complete`,
/// thus a direct drive states the arrival order of the chunks exactly. A child
/// process cannot: the operating system decides when a pipe gives its bytes,
/// and a test that waits for that decision examines the scheduler and not the
/// stream.
///
/// The behaviors under test are the contract of the file:
///
///   - Each event carries the completion token of its run.
///   - The chunks of one run arrive in the order the producer sent them.
///   - A consumer that reads too slowly loses bytes, and one gap event reports
///     them. The child never waits.
///   - Each run ends with exactly one completion marker, and no event of that
///     run follows it.
///   - A snapshot gives the stored bytes back, and a gap does not touch it.
///
/// Each test makes a stream of its own, thus the tests are independent and they
/// run in parallel safely.
@Suite("OutputChunkStreamTests")
struct OutputChunkStreamTests {

    // MARK: - Fixtures

    /// The completion token of the one run of a test that runs one command.
    ///
    /// A ULID, as `SessionMailbox.makeCompletionToken()` mints. The tests state
    /// the token themselves, thus each expectation names the token it examines.
    private static let firstToken = "01M0NAGFZW81T7W42D3WT1T8MC"

    /// The completion token of the second run of a test that runs two commands.
    private static let secondToken = "01M0NAK9M8RG58Q7BTTWJDYXZ3"

    /// The completion token no test sends output under.
    private static let unknownToken = "01M0NANN3Q94YTJRJN2WCNKM9B"

    /// The cap of the snapshot store of a test that does not fill it. Thus the
    /// test examines the stored bytes and not the cap.
    private static let spaciousCaptureCapBytes = 1_000_000

    /// The cap of the snapshot store of the test that fills it.
    private static let tightCaptureCapBytes = 16

    /// The pending-byte budget of a test that must lose no chunk.
    private static let spaciousPendingCapBytes = 1_000_000

    /// The number of chunks each run of the concurrent test writes.
    private static let concurrentChunkCount = 200

    /// The number of chunks the overflow test writes.
    private static let overflowChunkCount = 100

    /// The number of bytes in each chunk of the overflow test. It is far above
    /// the budget of that test, thus each chunk after the first one goes away.
    private static let overflowChunkBytes = 4096

    /// How long the cancel test lets its consumer reach the suspension point
    /// inside `next()`. A cancel of a task that did not suspend yet does not
    /// exercise the path under test.
    private static let consumerSuspendDelay: Duration = .milliseconds(100)

    /// One kibibyte, which `defaultPendingByteCapIsOneMebibyte` multiplies to
    /// state the default budget in the units a reader knows.
    private static let bytesPerKibibyte = 1024

    // MARK: - Helpers

    /// Collects each event of `stream` in the background, until the stream
    /// ends.
    ///
    /// - Parameter stream: The stream to read.
    /// - Returns: The collecting task. Call `finish()` on the stream to make it
    ///   settle.
    private func collect(_ stream: ShellOutputChunkStream) -> Task<[ShellOutputEvent], Never> {
        Task {
            var events: [ShellOutputEvent] = []
            for await event in stream {
                events.append(event)
            }
            return events
        }
    }

    /// The bytes of each output event of one run and one stream, joined in
    /// delivery order.
    ///
    /// - Parameters:
    ///   - events: The collected events.
    ///   - commandID: The completion token of the run to select.
    ///   - stream: The stream to select.
    /// - Returns: The joined bytes.
    private func joinedBytes(
        _ events: [ShellOutputEvent], commandID: String, stream: ShellOutputStream
    ) -> [UInt8] {
        events.reduce(into: [UInt8]()) { joined, event in
            guard event.commandID == commandID,
                case .output(let eventStream, let bytes) = event.kind,
                eventStream == stream
            else { return }
            joined.append(contentsOf: bytes)
        }
    }

    /// The bytes of the chunk with `index` of the run with `commandID`.
    ///
    /// Each chunk of a run differs from each other chunk of that run, and from
    /// each chunk of the other run. Thus a mixed-up chunk shows in the joined
    /// bytes of a run.
    ///
    /// - Parameters:
    ///   - index: The number of the chunk inside its run, counted from 0.
    ///   - commandID: The completion token of the run.
    /// - Returns: The bytes of that chunk.
    private static func chunk(index: Int, commandID: String) -> [UInt8] {
        Array("\(commandID)-\(index)\n".utf8)
    }

    // MARK: - The budget

    @Test func defaultPendingByteCapIsOneMebibyte() {
        let oneMebibyte = Self.bytesPerKibibyte * Self.bytesPerKibibyte
        #expect(ShellOutputChunkStream.defaultMaxPendingBytes == oneMebibyte)
    }

    // MARK: - The tags and the order

    /// Each event carries the completion token of its run and the stream of its
    /// bytes, and the events arrive in the order the producer sent them.
    @Test func deliveredChunksCarryTheirCompletionTokenAndStreamTags() async {
        let stream = ShellOutputChunkStream()
        let collector = collect(stream)

        stream.send(
            commandID: Self.firstToken, stream: .stdout, bytes: Array("out".utf8),
            maxSize: Self.spaciousCaptureCapBytes)
        stream.send(
            commandID: Self.firstToken, stream: .stderr, bytes: Array("err".utf8),
            maxSize: Self.spaciousCaptureCapBytes)
        stream.complete(commandID: Self.firstToken)
        stream.finish()

        let events = await collector.value
        #expect(
            events == [
                ShellOutputEvent(
                    commandID: Self.firstToken,
                    kind: .output(stream: .stdout, bytes: Array("out".utf8))),
                ShellOutputEvent(
                    commandID: Self.firstToken,
                    kind: .output(stream: .stderr, bytes: Array("err".utf8))),
                ShellOutputEvent(commandID: Self.firstToken, kind: .completed),
            ])
    }

    /// Two runs that write at the same time keep their chunks apart: the joined
    /// bytes of each run hold each chunk of that run, in order, and no chunk of
    /// the other run.
    ///
    /// The two producers run in parallel, thus their chunks interleave in the
    /// stream. The completion token is what tells them apart again.
    @Test func twoConcurrentRunsKeepTheirChunksApartByCompletionToken() async {
        let tokens = [Self.firstToken, Self.secondToken]

        // A budget larger than everything the two runs write, thus no chunk
        // goes away and the joined bytes hold each chunk.
        let stream = ShellOutputChunkStream(maxPendingBytes: Self.spaciousPendingCapBytes)
        let collector = collect(stream)

        await withTaskGroup(of: Void.self) { group in
            for token in tokens {
                group.addTask {
                    for index in 0..<Self.concurrentChunkCount {
                        stream.send(
                            commandID: token, stream: .stdout,
                            bytes: Self.chunk(index: index, commandID: token),
                            maxSize: Self.spaciousCaptureCapBytes)
                    }
                    stream.complete(commandID: token)
                }
            }
        }
        stream.finish()

        let events = await collector.value
        for token in tokens {
            let expected = (0..<Self.concurrentChunkCount).flatMap {
                Self.chunk(index: $0, commandID: token)
            }
            #expect(joinedBytes(events, commandID: token, stream: .stdout) == expected)
            #expect(events.filter { $0.commandID == token && $0.kind == .completed }.count == 1)
        }
    }

    // MARK: - The end of a run

    /// The stream of a run terminates after the last chunk of that run: the
    /// completion marker arrives one time, it stands after each chunk of the
    /// run, and no event of the run follows it.
    @Test func theStreamOfARunTerminatesAfterItsLastChunk() async {
        let stream = ShellOutputChunkStream()
        let collector = collect(stream)

        for index in 0..<Self.concurrentChunkCount {
            stream.send(
                commandID: Self.firstToken, stream: .stdout,
                bytes: Self.chunk(index: index, commandID: Self.firstToken),
                maxSize: Self.spaciousCaptureCapBytes)
        }
        stream.complete(commandID: Self.firstToken)
        stream.finish()

        let events = await collector.value
        let ofRun = events.filter { $0.commandID == Self.firstToken }
        #expect(ofRun.filter { $0.kind == .completed }.count == 1)
        #expect(ofRun.last?.kind == .completed)
        #expect(ofRun.count == Self.concurrentChunkCount + 1)
    }

    /// A run that writes nothing still announces its end. The marker is what
    /// tells "the run ended" from "the run is quiet".
    @Test func aRunThatWritesNothingStillGetsItsCompletionMarker() async {
        let stream = ShellOutputChunkStream()
        let collector = collect(stream)

        stream.complete(commandID: Self.firstToken)
        stream.finish()

        let events = await collector.value
        #expect(events == [ShellOutputEvent(commandID: Self.firstToken, kind: .completed)])
    }

    // MARK: - Backpressure

    /// After the budget is spent, each arriving chunk goes away, and one gap
    /// event reports the bytes of all of them together.
    @Test func chunksOverThePendingByteCapGoAwayAndOneGapReportsThem() async {
        // A budget of exactly one chunk: the first send spends it, and with no
        // consumer the 4 + 2 bytes behind it find it spent and go away.
        let firstChunk: [UInt8] = [1, 2, 3, 4]
        let secondChunk: [UInt8] = [5, 6, 7, 8]
        let thirdChunk: [UInt8] = [9, 10]
        let stream = ShellOutputChunkStream(maxPendingBytes: firstChunk.count)

        stream.send(
            commandID: Self.firstToken, stream: .stdout, bytes: firstChunk,
            maxSize: Self.spaciousCaptureCapBytes)
        stream.send(
            commandID: Self.firstToken, stream: .stdout, bytes: secondChunk,
            maxSize: Self.spaciousCaptureCapBytes)
        stream.send(
            commandID: Self.firstToken, stream: .stdout, bytes: thirdChunk,
            maxSize: Self.spaciousCaptureCapBytes)
        stream.complete(commandID: Self.firstToken)
        stream.finish()

        let events = await collect(stream).value
        #expect(
            events == [
                ShellOutputEvent(
                    commandID: Self.firstToken, kind: .output(stream: .stdout, bytes: firstChunk)),
                ShellOutputEvent(
                    commandID: Self.firstToken,
                    kind: .gap(
                        stream: .stdout,
                        droppedByteCount: secondChunk.count + thirdChunk.count)),
                ShellOutputEvent(commandID: Self.firstToken, kind: .completed),
            ])
    }

    /// The gap event stands where the hole is: after each event the consumer
    /// already has, and before the next chunk that gets through.
    @Test func theGapEventStandsBeforeTheNextChunkThatGetsThrough() async {
        // A budget of exactly one chunk: the first send spends it, the second
        // finds it spent, and a read of the first one gives the budget back.
        let firstChunk: [UInt8] = [1, 2, 3, 4]
        let droppedChunk: [UInt8] = [5, 6, 7, 8]
        let laterChunk: [UInt8] = [9, 10, 11, 12]
        let stream = ShellOutputChunkStream(maxPendingBytes: firstChunk.count)

        stream.send(
            commandID: Self.firstToken, stream: .stdout, bytes: firstChunk,
            maxSize: Self.spaciousCaptureCapBytes)
        stream.send(
            commandID: Self.firstToken, stream: .stdout, bytes: droppedChunk,
            maxSize: Self.spaciousCaptureCapBytes)

        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()
        #expect(first?.kind == .output(stream: .stdout, bytes: firstChunk))

        stream.send(
            commandID: Self.firstToken, stream: .stdout, bytes: laterChunk,
            maxSize: Self.spaciousCaptureCapBytes)
        stream.complete(commandID: Self.firstToken)
        stream.finish()

        var rest: [ShellOutputEvent] = []
        while let event = await iterator.next() { rest.append(event) }
        #expect(
            rest == [
                ShellOutputEvent(
                    commandID: Self.firstToken,
                    kind: .gap(stream: .stdout, droppedByteCount: droppedChunk.count)),
                ShellOutputEvent(
                    commandID: Self.firstToken, kind: .output(stream: .stdout, bytes: laterChunk)),
                ShellOutputEvent(commandID: Self.firstToken, kind: .completed),
            ])
    }

    /// The budget is one pool, and each run and each stream draws from it. The
    /// report is not one pool: each pair of a run and a stream gets a gap of
    /// its own, which counts the bytes of that pair alone.
    @Test func aGapCountsOneRunAndOneStreamAlone() async {
        // A budget of exactly the first send: that send spends it, and with no
        // consumer each later send finds it spent.
        let firstChunk: [UInt8] = [1, 2]
        let firstStdoutDropped: [UInt8] = [3, 4, 5]
        let firstStderrDropped: [UInt8] = [6]
        let secondStdoutDropped: [UInt8] = [7, 8]
        let stream = ShellOutputChunkStream(maxPendingBytes: firstChunk.count)

        stream.send(
            commandID: Self.firstToken, stream: .stdout, bytes: firstChunk,
            maxSize: Self.spaciousCaptureCapBytes)
        stream.send(
            commandID: Self.firstToken, stream: .stdout, bytes: firstStdoutDropped,
            maxSize: Self.spaciousCaptureCapBytes)
        stream.send(
            commandID: Self.firstToken, stream: .stderr, bytes: firstStderrDropped,
            maxSize: Self.spaciousCaptureCapBytes)
        stream.send(
            commandID: Self.secondToken, stream: .stdout, bytes: secondStdoutDropped,
            maxSize: Self.spaciousCaptureCapBytes)
        stream.complete(commandID: Self.firstToken)
        stream.complete(commandID: Self.secondToken)
        stream.finish()

        let events = await collect(stream).value
        let gaps = events.filter { if case .gap = $0.kind { return true } else { return false } }
        #expect(
            gaps == [
                ShellOutputEvent(
                    commandID: Self.firstToken,
                    kind: .gap(stream: .stdout, droppedByteCount: firstStdoutDropped.count)),
                ShellOutputEvent(
                    commandID: Self.firstToken,
                    kind: .gap(stream: .stderr, droppedByteCount: firstStderrDropped.count)),
                ShellOutputEvent(
                    commandID: Self.secondToken,
                    kind: .gap(stream: .stdout, droppedByteCount: secondStdoutDropped.count)),
            ])
    }

    /// The completion marker carries no bytes, thus the budget never stops it —
    /// also when each chunk of the run but the first one went away.
    @Test func theCompletionMarkerSurvivesAQueueThatOverflowed() async {
        // Far below the size of one chunk, thus each chunk after the first one
        // goes away.
        let pendingCapBytes = 1
        let chunkBytes = Array(repeating: UInt8.zero, count: Self.overflowChunkBytes)
        let stream = ShellOutputChunkStream(maxPendingBytes: pendingCapBytes)

        for _ in 0..<Self.overflowChunkCount {
            stream.send(
                commandID: Self.firstToken, stream: .stdout, bytes: chunkBytes,
                maxSize: Self.spaciousCaptureCapBytes)
        }
        stream.complete(commandID: Self.firstToken)
        stream.finish()

        let events = await collect(stream).value
        // The stream examines the budget before it adds the chunk, thus a chunk
        // that is larger than the whole budget still arrives. Each chunk after
        // it goes away, and the gap counts each one.
        #expect(
            events == [
                ShellOutputEvent(
                    commandID: Self.firstToken, kind: .output(stream: .stdout, bytes: chunkBytes)),
                ShellOutputEvent(
                    commandID: Self.firstToken,
                    kind: .gap(
                        stream: .stdout,
                        droppedByteCount: (Self.overflowChunkCount - 1) * Self.overflowChunkBytes)),
                ShellOutputEvent(commandID: Self.firstToken, kind: .completed),
            ])
    }

    // MARK: - The end of the stream

    /// A cancel of the task of the consumer ends the underlying `AsyncStream`,
    /// and no call gives it back. The stream must read that as its own end. If
    /// it does not, the producer keeps budget for bytes that no consumer can
    /// take, and the budget stays spent for the life of the object.
    @Test func aCancelOfTheConsumerTaskEndsTheStream() async throws {
        let stream = ShellOutputChunkStream()

        let consuming = Task { for await _ in stream {} }
        try await Task.sleep(for: Self.consumerSuspendDelay)
        consuming.cancel()
        _ = await consuming.value

        #expect(stream.isFinished, "a cancelled consumer leaves the stream spent; say so")

        // And each later call of the producer must do nothing at all.
        stream.send(
            commandID: Self.firstToken, stream: .stdout, bytes: [1, 2, 3, 4],
            maxSize: Self.spaciousCaptureCapBytes)
        stream.complete(commandID: Self.firstToken)
        #expect(stream.isFinished)
    }

    /// `finish()` ends the read loop of a host that stops listening, and each
    /// later call of the producer does nothing.
    @Test func finishEndsTheReadLoopAndEachLaterCallDoesNothing() async {
        let stream = ShellOutputChunkStream()
        let collector = collect(stream)
        let beforeFinish: [UInt8] = [1]

        stream.send(
            commandID: Self.firstToken, stream: .stdout, bytes: beforeFinish,
            maxSize: Self.spaciousCaptureCapBytes)
        stream.finish()
        stream.send(
            commandID: Self.firstToken, stream: .stdout, bytes: [2],
            maxSize: Self.spaciousCaptureCapBytes)
        stream.complete(commandID: Self.firstToken)

        let events = await collector.value
        // Stated as what arrives, thus a stream that gives nothing at all
        // cannot pass this test: the chunk before `finish()` arrives, and
        // nothing after it does.
        #expect(
            events == [
                ShellOutputEvent(
                    commandID: Self.firstToken, kind: .output(stream: .stdout, bytes: beforeFinish))
            ])
        #expect(stream.isFinished)
    }

    // MARK: - The snapshot

    /// A snapshot gives the bytes of the two streams back, exactly as the
    /// producer sent them.
    @Test func aSnapshotGivesTheSentBytesBackByteForByte() {
        let stream = ShellOutputChunkStream()
        let outBytes = Array("alpha\nbeta\r\nno-newline-tail".utf8)
        let errBytes = Array("oops\n".utf8)

        stream.send(
            commandID: Self.firstToken, stream: .stdout, bytes: outBytes,
            maxSize: Self.spaciousCaptureCapBytes)
        stream.send(
            commandID: Self.firstToken, stream: .stderr, bytes: errBytes,
            maxSize: Self.spaciousCaptureCapBytes)

        let snapshot = stream.snapshot(for: Self.firstToken)
        #expect(snapshot?.stdout.bytes == outBytes)
        #expect(snapshot?.stderr.bytes == errBytes)
        #expect(snapshot?.stdout.truncated == false)
        #expect(snapshot?.stdout.binaryDetected == false)
        stream.finish()
    }

    /// A snapshot of bytes that no UTF-8 decode accepts gives them back with no
    /// change. The raw path applies no decode and writes no placeholder.
    @Test func aSnapshotOfBytesThatAreNotUTF8GivesThemBackWithNoChange() {
        let bytes = Array(UInt8.min...UInt8.max)
        let stream = ShellOutputChunkStream()

        stream.send(
            commandID: Self.firstToken, stream: .stdout, bytes: bytes,
            maxSize: Self.spaciousCaptureCapBytes)

        let snapshot = stream.snapshot(for: Self.firstToken)
        #expect(snapshot?.stdout.bytes == bytes)
        // The fixture holds a null byte, thus the capture is binary. The bytes
        // still come back.
        #expect(snapshot?.stdout.binaryDetected == true)
        #expect(snapshot?.stdout.truncated == false)
        stream.finish()
    }

    /// A gap does not touch the snapshot store: the store holds each byte the
    /// producer sent, and the live view holds only what got through.
    @Test func aSnapshotHoldsEachByteThatAGapTookFromTheLiveView() async {
        // A budget of exactly one chunk, thus the second chunk goes away from
        // the live view alone.
        let firstChunk = Array("first\n".utf8)
        let droppedChunk = Array("second\n".utf8)
        let stream = ShellOutputChunkStream(maxPendingBytes: firstChunk.count)

        stream.send(
            commandID: Self.firstToken, stream: .stdout, bytes: firstChunk,
            maxSize: Self.spaciousCaptureCapBytes)
        stream.send(
            commandID: Self.firstToken, stream: .stdout, bytes: droppedChunk,
            maxSize: Self.spaciousCaptureCapBytes)
        stream.complete(commandID: Self.firstToken)
        stream.finish()

        let events = await collect(stream).value
        #expect(joinedBytes(events, commandID: Self.firstToken, stream: .stdout) == firstChunk)

        let snapshot = stream.snapshot(for: Self.firstToken)
        #expect(snapshot?.stdout.bytes == firstChunk + droppedChunk)
    }

    /// The snapshot store has a cap of its own, and it reports when it hits it.
    @Test func aSnapshotReportsTheCapOfItsOwnStore() {
        // The first chunk fills the cap exactly, thus `OutputBuffer` stores it
        // whole and the count below is exact and not a bound. The second chunk
        // finds no room, thus nothing of it goes into the store.
        let fillingChunk = Array(
            repeating: UInt8(ascii: "x"), count: Self.tightCaptureCapBytes)
        let refusedChunk = Array("over\n".utf8)
        let stream = ShellOutputChunkStream()

        stream.send(
            commandID: Self.firstToken, stream: .stdout, bytes: fillingChunk,
            maxSize: Self.tightCaptureCapBytes)
        stream.send(
            commandID: Self.firstToken, stream: .stdout, bytes: refusedChunk,
            maxSize: Self.tightCaptureCapBytes)

        let snapshot = stream.snapshot(for: Self.firstToken)
        #expect(snapshot?.stdout.truncated == true)
        #expect(snapshot?.stdout.bytes == fillingChunk)
        #expect(snapshot?.stdout.storedByteCount == Self.tightCaptureCapBytes)
        stream.finish()
    }

    /// A snapshot of a token the stream never saw is `nil`. Thus a host tells
    /// "no such run" from "the run wrote nothing".
    @Test func aSnapshotOfAnUnknownTokenIsNil() {
        let stream = ShellOutputChunkStream()

        stream.send(
            commandID: Self.firstToken, stream: .stdout, bytes: [1],
            maxSize: Self.spaciousCaptureCapBytes)

        #expect(stream.snapshot(for: Self.unknownToken) == nil)
        stream.finish()
    }
}
