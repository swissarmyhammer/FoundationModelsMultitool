// `OutputProgressCollector` — collects the output of one `execute` run into
// few `progress` events.
//
// Card `^2ny3k6k` is the reason for this file. `Execute` posted one `progress`
// event for each chunk of output. A child that writes one byte at a time — the
// Django test runner writes one unbuffered "." to stderr for each test — thus
// posted one event for each byte: one run of 14878 tests gave 13663 events and
// a transcript of 13 MB, and each event cost time in the session actor.
//
// This type collects the chunks of one run into a COLLECTION, and it posts one
// event for each collection. A collection closes on the first of three
// things: it holds ``collectionByteLimit`` bytes, ``collectionInterval`` went
// by since its first chunk, or the run ended. Thus the count of events grows
// with the time and the bytes of a run, and not with its count of writes.
//
// The collection touches the progress events only. The line store
// (`ShellState`, which `tools.shell.getLines` and `tools.shell.grepHistory`
// read) and the report of the run take their bytes on other paths, and this
// type reaches neither of them.
//
// **The interval is a pace, and not a time limit.** It closes a collection; it
// stops nothing. The time limit of a run stays the one `ShellRunner` arms, and
// this file adds no second clock over the same question. The interval sleeps
// on the clock of the runner, thus a test that gives the runner a clock it
// controls also controls when a collection closes.
//
// **One order for every post.** Two things close a collection: the chunk that
// fills it, which the drain of the run delivers, and the end of its interval,
// which a timer task delivers. Each post is a task that first waits for the
// post before it, thus the events reach the session in the order the
// collections closed, whichever of the two closed them.

import Foundation
import FoundationModelsExtras

/// Collects the output chunks of one run, and posts one `progress` event for
/// each collection.
///
/// Give each chunk to ``collect(_:)`` in arrival order, and call ``finish()``
/// one time after the last chunk. The context is the one the call of the verb
/// captured at its start, or `nil` on a bare session, where every post is a
/// no-op.
actor OutputProgressCollector {

    /// The longest time one collection stays open, from its first chunk: one
    /// second.
    ///
    /// Card `^2ny3k6k`: a run that writes all the time posts about one event
    /// in this time, and not one event for each write. One second keeps the
    /// live view of a run current for a person who reads it.
    static let collectionInterval = Duration.seconds(1)

    /// The most bytes one collection holds before it closes: 64 KiB.
    ///
    /// Card `^2ny3k6k`: the bound on the size of one event. A run that writes
    /// fast fills a collection before its interval ends, and this limit keeps
    /// each of its events to an ordinary size. The value is written as one
    /// number. Do not write it as a calculation: a calculation makes two
    /// numbers that have no name.
    static let collectionByteLimit = 65_536

    /// The session context each event posts to, or `nil` on a bare session.
    private let context: ToolContext?

    /// The clock the interval of a collection sleeps on: the clock of the
    /// runner.
    private let clock: any Clock<Duration>

    /// The output of the open collection.
    private var collection = OutputCollection()

    /// The number of the open collection. A timer carries the number of the
    /// collection it was started for, thus a timer that ends after its
    /// collection closed for another reason closes nothing.
    private var collectionNumber = 0

    /// The timer of the open collection, or `nil` while the open collection
    /// holds no output.
    private var intervalTimer: Task<Void, Never>?

    /// The last post this collector started, or `nil` before the first one.
    /// Each new post waits for it.
    private var lastPost: Task<Void, Never>?

    /// Makes a collector for one run.
    ///
    /// - Parameters:
    ///   - context: The session context each event posts to, or `nil` on a
    ///     bare session.
    ///   - clock: The clock the interval of a collection sleeps on.
    init(context: ToolContext?, clock: any Clock<Duration>) {
        self.context = context
        self.clock = clock
    }

    /// Adds one event of the live view of the run to the open collection.
    ///
    /// A chunk that brings the collection to the byte limit closes it, and
    /// this call then waits until that post and every post before it ended.
    /// That wait is what keeps the backpressure of the live view: the drain
    /// that calls here does not read on while the session is behind.
    ///
    /// - Parameter event: The next event of the live view, in arrival order.
    func collect(_ event: ShellOutputEvent) async {
        collection.add(event.kind)
        if collection.byteCount >= Self.collectionByteLimit {
            await closeCollection()?.value
        } else if intervalTimer == nil, !collection.isEmpty {
            intervalTimer = makeIntervalTimer(for: collectionNumber)
        }
    }

    /// Closes the last collection, and waits until each post ended.
    ///
    /// Call it one time, after the last event of the run. Thus no output of
    /// the run is lost from the progress events, and each event stands before
    /// the terminal event the caller posts next.
    func finish() async {
        await closeCollection()?.value
    }

    /// Closes the open collection, and starts its post.
    ///
    /// - Returns: The last post, which this call started or an earlier call
    ///   started, or `nil` when no post was ever started.
    private func closeCollection() -> Task<Void, Never>? {
        intervalTimer?.cancel()
        intervalTimer = nil
        collectionNumber += 1
        let closed = collection
        collection = OutputCollection()
        guard let detail = closed.detail else { return lastPost }
        lastPost = Task { [lastPost, context] in
            await lastPost?.value
            await context?.progress(detail)
        }
        return lastPost
    }

    /// Closes the collection `number`, when it is still the open one.
    ///
    /// - Parameter number: The number of the collection whose interval ended.
    private func intervalDidEnd(for number: Int) {
        guard number == collectionNumber else { return }
        _ = closeCollection()
    }

    /// Starts the timer that closes the collection `number` when its interval
    /// ends.
    ///
    /// A cancelled sleep ends the timer and closes nothing: the collection
    /// closed for another reason first.
    ///
    /// - Parameter number: The number of the open collection.
    /// - Returns: The timer.
    private func makeIntervalTimer(for number: Int) -> Task<Void, Never> {
        Task { [clock] in
            guard (try? await clock.sleep(for: Self.collectionInterval)) != nil else { return }
            self.intervalDidEnd(for: number)
        }
    }
}

/// The output of one collection, as the parts of one `progress` event.
///
/// Chunks of one stream that arrive one after the other join into one part
/// before the decode. Thus 10000 chunks of one "." become one part of 10000
/// dots, and a UTF-8 character that two chunks divide decodes whole.
private struct OutputCollection {

    /// One part of a collection.
    private enum Part {
        /// The bytes that one stream wrote, one chunk after the other.
        case output(stream: ShellOutputStream, bytes: [UInt8])

        /// Bytes of one stream that went away from the live view.
        case gap(stream: ShellOutputStream, droppedByteCount: Int)
    }

    /// The parts of the collection, in arrival order.
    private var parts: [Part] = []

    /// The bytes of output the collection holds.
    private(set) var byteCount = 0

    /// Tells if the collection holds no part.
    var isEmpty: Bool { parts.isEmpty }

    /// Adds one event of the live view.
    ///
    /// The completion marker adds nothing: the end of the run is the call to
    /// `OutputProgressCollector.finish()`, and not a part of an event.
    ///
    /// - Parameter kind: What the event reports.
    mutating func add(_ kind: ShellOutputEvent.Kind) {
        switch kind {
        case .output(let stream, let bytes):
            append(bytes, from: stream)
        case .gap(let stream, let droppedByteCount):
            parts.append(.gap(stream: stream, droppedByteCount: droppedByteCount))
        case .completed:
            return
        }
    }

    /// The text of the one `progress` event of this collection, or `nil` when
    /// the collection has nothing to report.
    ///
    /// Each part is one line, which names the stream. A part that decodes to
    /// nothing but white space is passed over: it says the child wrote a line
    /// ending, which is not news. A gap is reported, because output that went
    /// away is exactly what a reader must not mistake for output that never
    /// came.
    var detail: String? {
        let lines = parts.compactMap(Self.line(for:))
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// Adds `bytes` to the last part when that part holds output of the same
    /// stream, or as a new part when it does not.
    ///
    /// The last part comes out of the array before its bytes grow. Thus the
    /// copy of the bytes here is the only reference to their storage, and the
    /// append writes in place. A part that stayed in the array would make
    /// each append copy all the bytes of the part, and 10000 single-byte
    /// chunks would then copy about 50 million bytes.
    ///
    /// - Parameters:
    ///   - bytes: The bytes of one chunk.
    ///   - stream: The stream that wrote them.
    private mutating func append(_ bytes: [UInt8], from stream: ShellOutputStream) {
        byteCount += bytes.count
        guard case .output(let lastStream, var joined) = parts.last, lastStream == stream else {
            parts.append(.output(stream: stream, bytes: bytes))
            return
        }
        parts.removeLast()
        joined.append(contentsOf: bytes)
        parts.append(.output(stream: stream, bytes: joined))
    }

    /// The line one part gives the event, or `nil` for output that is only
    /// white space.
    ///
    /// - Parameter part: The part to write out.
    /// - Returns: The line.
    private static func line(for part: Part) -> String? {
        switch part {
        case .output(let stream, let bytes):
            let text = String(decoding: bytes, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : "\(name(of: stream)): \(text)"
        case .gap(let stream, let droppedByteCount):
            return "\(name(of: stream)): \(droppedByteCount) bytes of output went away"
        }
    }

    /// What one output stream of a child is called in a `progress` event.
    ///
    /// - Parameter stream: The stream a chunk came from.
    /// - Returns: The name the event carries.
    private static func name(of stream: ShellOutputStream) -> String {
        switch stream {
        case .stdout: return "stdout"
        case .stderr: return "stderr"
        }
    }
}
