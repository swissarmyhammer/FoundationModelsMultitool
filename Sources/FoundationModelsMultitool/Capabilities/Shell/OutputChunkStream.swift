// `ShellOutputChunkStream` — the live view of the output of a shell run, for a
// host outside this module.
//
// Each other read-back path of the shell capability answers after the fact: the
// `.shell/log` store, `tools.shell.getLines`, `tools.shell.grepHistory`, the
// tail of the execute operation. A host that must show a build log while the
// child writes it needs the bytes now. This file is that one path, and it is
// the one place of the shell capability that carries raw bytes across the
// module boundary.
//
// This is a HOST seam. The model never sees it. A host makes one stream, it
// gives that stream to the shell runner, and it reads the stream with a `for
// await` loop.
//
// eventplan.md § "Consolidation of the siblings" states the identity rule of a
// run: the `commandID` of a shell run is its `correlationID` is its
// `completionToken` — one string. Thus each event here carries that string, and
// this file mints no identifier of a kind of its own. `ShellState` keys its
// records on the same string, and `OutputBuffer` keys its captures on it.
//
// Where the bytes come from: the runner reads one raw `(stream, bytes)` chunk
// at a time from its child, in arrival order, and it gives that chunk to `send`
// before it gives it to the line buffer. Nothing here reads the child, splits a
// line, or puts a chunk in a new order. Thus the order of this stream is the
// order the runner read the chunks in.
//
// This is not an `OutputBuffer`. The line path caps what it takes, because it
// STORES what it takes. The live path stores nothing: the bytes go through to a
// consumer that holds its own scrollback. A cap here would make the live path
// lossy for a second reason, and it would break the one promise the live path
// makes — that the delivered chunks of a run, joined, are the output of that
// run byte for byte. Truncation, binary detection and the placeholder line stay
// with the stored log.
//
// Backpressure is the design constraint of the file. A host reads at its own
// speed, and a host that reads slowly must never stop the child. Thus `send`
// never blocks and never suspends: it puts the event in the queue under a lock,
// and it returns. What bounds the memory is a budget of PENDING BYTES — the
// bytes that went into the queue and that no consumer took yet. While the
// budget is spent, an arriving chunk of bytes GOES AWAY (the new one, and not
// the old one — see `send`), and its size adds to one counter for each pair of
// a run and a stream. That counter becomes one gap event, which stands before
// the next event of that pair that gets through. An event that carries no bytes
// — a gap and a completion marker — never goes away. That is what makes "one
// completion marker for each run" a promise and not an intention.
//
// The snapshot is the other half of the contract. The live view above APPENDS:
// a host draws each chunk onto what it already has, and a gap tells it about
// bytes it will never see. `snapshot(for:)` REPLACES: it gives back everything
// this stream took into storage for a run, as of the call. Thus a host that
// lost bytes to a gap throws its own view away and takes this one instead. The
// same `send` calls feed both, but the store behind the snapshot is a second
// `OutputBuffer` for each run, and the budget never touches it: a chunk that
// goes away from the live queue stays in the store. The two answer different
// questions — "what got through" against "what is stored" — thus they must not
// share a fate. The store has an honest limit of its own, which `send` takes as
// `maxSize` and `ShellRawOutput.truncated` reports.

import Foundation
import Synchronization

/// Which of the two output streams of a run a chunk came from.
public enum ShellOutputStream: Hashable, Sendable, CaseIterable {
    /// The standard output of the child.
    case stdout
    /// The standard error of the child.
    case stderr
}

/// One event of the live view of the output of a run.
public struct ShellOutputEvent: Sendable, Equatable {
    /// What the event reports.
    public enum Kind: Sendable, Equatable {
        /// The bytes exactly as the child wrote them to `stream`, in the order
        /// the runner read them.
        ///
        /// No UTF-8 decode, no truncation and no placeholder touches them.
        case output(stream: ShellOutputStream, bytes: [UInt8])

        /// Bytes of `stream` went away, because the consumer fell behind the
        /// budget of pending bytes. See the backpressure rule of
        /// `ShellOutputChunkStream`.
        ///
        /// The event stands where the hole is, thus the events around it stay
        /// continuous with the output of the child. `droppedByteCount` counts
        /// each byte that went away since the previous delivered event of this
        /// run and this stream.
        case gap(stream: ShellOutputStream, droppedByteCount: Int)

        /// The runner is done with this run. No later event carries its
        /// `commandID`.
        ///
        /// This is what tells "the run ended" from "the run is quiet": a run
        /// that takes a long time can write nothing for minutes. The marker
        /// arrives one time for each run, after each chunk of that run, and it
        /// never goes away.
        ///
        /// It is a statement about the STREAM, and not a promise about the
        /// `CommandRecord` of `ShellState`. In practice the two agree: the run
        /// body finalizes the record on each path out of it, an error included.
        /// Thus a host reads the marker as its cue to read the record back for
        /// the authoritative status.
        case completed
    }

    /// The completion token of the run the event belongs to.
    ///
    /// It is the `correlationID` of each event the run posts, and it is the
    /// token that `status`, `wait` and `cancel` take. Thus a host that holds an
    /// event and a response of the execute operation matches them directly,
    /// with no table between them.
    public let commandID: String

    /// What the event reports.
    public let kind: Kind

    /// Puts `kind` with the run it belongs to.
    ///
    /// - Parameters:
    ///   - commandID: The completion token of the run.
    ///   - kind: What the event reports.
    public init(commandID: String, kind: Kind) {
        self.commandID = commandID
        self.kind = kind
    }
}

/// The stored bytes of one stream, exactly as the child wrote them, with the
/// state of the capture that says how to read them.
///
/// This is the public form of `OutputBuffer.RawOutput`, which
/// `ShellOutputChunkStream.snapshot(for:)` gives back. `OutputBuffer` is
/// internal, thus the snapshot cannot hand its type out and this type stands in
/// place of it, field for field.
public struct ShellRawOutput: Sendable, Equatable {
    /// The bytes of the stream, exactly as the child wrote them. No UTF-8
    /// decode, no split into lines, and no binary placeholder touches them.
    public let bytes: [UInt8]

    /// Tells if a chunk of this capture carried binary content (a null byte).
    ///
    /// Information only: the bytes continue to come back after the flag is set.
    public let binaryDetected: Bool

    /// Tells if the store dropped output to stay under its own cap.
    ///
    /// After it is `true`, `bytes` holds a part of what the child wrote, and
    /// that part is **not necessarily the first part**. See
    /// `OutputBuffer.RawOutput.truncated` for why the promise is this weak.
    public let truncated: Bool

    /// The cumulative bytes this capture took into storage for the two streams
    /// together — the same counter as `OutputBuffer.storedByteCount`. Thus it
    /// can be larger than `bytes.count` after the other stream stored anything.
    public let storedByteCount: Int

    /// Puts the stored bytes of one stream with the state of the capture.
    ///
    /// - Parameters:
    ///   - bytes: The bytes of the stream, exactly as the child wrote them.
    ///   - binaryDetected: Tells if this capture saw binary content.
    ///   - truncated: Tells if the store hit its own cap.
    ///   - storedByteCount: The cumulative stored bytes of the two streams.
    public init(bytes: [UInt8], binaryDetected: Bool, truncated: Bool, storedByteCount: Int) {
        self.bytes = bytes
        self.binaryDetected = binaryDetected
        self.truncated = truncated
        self.storedByteCount = storedByteCount
    }
}

/// The stored raw output of one run — the "replace" half of the contract of
/// `ShellOutputChunkStream`, which `snapshot(for:)` gives back.
public struct ShellOutputSnapshot: Sendable, Equatable {
    /// The stored bytes of the standard output, with the state of the capture.
    public let stdout: ShellRawOutput

    /// The stored bytes of the standard error, with the state of the capture.
    public let stderr: ShellRawOutput

    /// Puts the two streams of one run into one snapshot.
    ///
    /// - Parameters:
    ///   - stdout: The stored bytes and state of the standard output.
    ///   - stderr: The stored bytes and state of the standard error.
    public init(stdout: ShellRawOutput, stderr: ShellRawOutput) {
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// The live view a host takes of the output of each shell run of the runner it
/// is attached to.
///
/// Make one, give it to the shell capability, and read it:
///
/// ```swift
/// let live = ShellOutputChunkStream()
/// Task {
///     for await event in live {
///         switch event.kind {
///         case .output(let stream, let bytes): render(bytes, from: stream, of: event.commandID)
///         case .gap(_, let dropped): note("\(dropped) bytes went away")
///         case .completed: finish(event.commandID)
///         }
///     }
/// }
/// ```
///
/// **One consumer.** The stream hands each event out one time, in arrival
/// order. Two loops that read at the same time divide the events between them,
/// and neither one sees all of them. Run exactly one loop.
///
/// **How it ends.** Two things end the stream for good, and they are one state
/// (`isFinished`) and not two: a call to `finish()`, and a cancel of the task
/// of the consumer while it reads. After either one, each `send` and each
/// `complete` does nothing. A host that stops listening, and that no cancel
/// stopped, must call `finish()` — `defaultMaxPendingBytes` states what a
/// stream that nobody finishes keeps.
///
/// **Order.** The stream gives the events out in the order the runner read the
/// chunks. Inside one stream (stdout or stderr) of one run, that is always the
/// order the child wrote to that stream: one reader drains it in sequence.
/// Across the two streams of one run, the order is the order the two readers
/// reached the shared queue in, which ordinary task scheduling decides.
/// Concurrent runs mix with the same limit. Use `ShellOutputEvent.commandID` to
/// tell the runs apart.
///
/// **Backpressure — bytes go away, the child never waits.** See the header of
/// this file. A slow read costs bytes and not the progress of the child: after
/// `maxPendingBytes` of undelivered bytes pile up, an arriving chunk goes away
/// and one gap event reports it. The stream neither grows without bound nor
/// pushes back on the child. Thus a host that never reads at all does no harm
/// to the run — it simply sees nothing.
public final class ShellOutputChunkStream: AsyncSequence, Sendable {
    /// The type of event this stream gives out.
    public typealias Element = ShellOutputEvent

    /// The budget of pending bytes this stream takes when the caller states
    /// none: 1 MiB.
    ///
    /// The value is written as one number. Do not write it as a calculation: a
    /// calculation makes two numbers that have no name.
    ///
    /// It is large enough that a host which keeps up never sees a gap, and
    /// small enough that a host which falls behind costs an ordinary amount of
    /// memory.
    ///
    /// The budget bounds the BYTES only. An event that carries no payload — a
    /// gap and a completion marker — never goes away. Thus a stream that a host
    /// subscribes to and then walks away from — never read, never finished —
    /// also keeps up to three small events for each run, with no end. Nothing
    /// bounds that part except the number of runs, and that is why a host which
    /// stops listening must call `finish()`. A host whose reading task is
    /// CANCELLED owes nothing: the cancel ends the stream by itself — see
    /// `Iterator.next()`.
    public static let defaultMaxPendingBytes = 1_048_576

    /// The bytes that may stand delivered and unread before an arriving chunk
    /// starts to go away.
    ///
    /// The stream examines the budget BEFORE it adds the arriving chunk. Thus a
    /// chunk that is larger than the whole budget still arrives, and does not
    /// go away for ever. What the stream holds therefore peaks at
    /// `maxPendingBytes` plus the largest single chunk, less one byte. With the
    /// pipe-sized chunks of the runner that excess is small. With a very small
    /// budget it is not, and the bound above is the one to reason with.
    public let maxPendingBytes: Int

    /// Makes a stream with the budget of pending bytes it must hold.
    ///
    /// - Parameter maxPendingBytes: The bytes that may stand delivered and
    ///   unread before a chunk goes away. The default is
    ///   `defaultMaxPendingBytes`. It must be positive: a budget of zero or
    ///   less would make each chunk go away for ever, and the stream would give
    ///   nothing but gaps.
    public init(maxPendingBytes: Int = ShellOutputChunkStream.defaultMaxPendingBytes) {
        precondition(maxPendingBytes > 0, "maxPendingBytes must be positive, got \(maxPendingBytes)")
        self.maxPendingBytes = maxPendingBytes
        let (base, continuation) = AsyncStream<ShellOutputEvent>.makeStream()
        self.base = base
        self.continuation = continuation
    }

    deinit {
        continuation.finish()
    }

    /// Tells if the stream ended, and thus gives no further event.
    ///
    /// `finish()` sets it, and so does a cancel of the task of the CONSUMER
    /// while that task reads: `AsyncStream` reads a cancel as the end of the
    /// stream, and no call gives the stream back. Thus the two are one state
    /// and not two. A host that holds a subscription reads this to tell "quiet"
    /// from "gone".
    public var isFinished: Bool { state.withLock { $0.isFinished } }

    /// Ends the stream: the `for await` loop that reads it returns, and each
    /// later `send` and `complete` does nothing.
    ///
    /// A second call does nothing more.
    public func finish() {
        state.withLock { $0.isFinished = true }
        continuation.finish()
    }

    /// The stored raw stdout and stderr of the run with `commandID`, or `nil`
    /// when this stream saw no output under that token.
    ///
    /// This is the "replace" half of the contract the header of this file
    /// states. It answers with everything the stream took into storage for the
    /// run, up to the cap of that store (see `ShellRawOutput.truncated`), and
    /// it pays no attention to what the live view let go under backpressure.
    /// Call it at any point in the life of a run — while the child still runs,
    /// after a gap, or long after the completion marker. A read of a snapshot
    /// takes nothing out of the store, thus a second call answers the same way.
    ///
    /// - Parameter commandID: The completion token of the run to read back.
    /// - Returns: The stored raw output of that run, or `nil` for a token this
    ///   stream never saw.
    public func snapshot(for commandID: String) -> ShellOutputSnapshot? {
        state.withLock { pending in
            guard let buffer = pending.rawBuffers[commandID] else { return nil }
            return ShellOutputSnapshot(
                stdout: Self.projectRawOutput(buffer.rawStdout),
                stderr: Self.projectRawOutput(buffer.rawStderr))
        }
    }

    /// Puts an internal `OutputBuffer.RawOutput` into the public
    /// `ShellRawOutput`, field for field.
    ///
    /// - Parameter raw: The internal record to convert.
    /// - Returns: The public form of that record.
    private static func projectRawOutput(_ raw: OutputBuffer.RawOutput) -> ShellRawOutput {
        ShellRawOutput(
            bytes: raw.bytes, binaryDetected: raw.binaryDetected,
            truncated: raw.truncated, storedByteCount: raw.storedByteCount)
    }

    /// Starts to read the events of this stream.
    ///
    /// - Returns: An iterator over the events, in delivery order.
    public func makeAsyncIterator() -> Iterator {
        Iterator(base: base.makeAsyncIterator(), owner: self)
    }

    /// The iterator that `makeAsyncIterator()` gives out.
    ///
    /// It holds the iterator of the underlying `AsyncStream` for one reason: to
    /// count a read against the budget of pending bytes. A read here is what
    /// makes room for the next chunk.
    public struct Iterator: AsyncIteratorProtocol {
        fileprivate var base: AsyncStream<ShellOutputEvent>.AsyncIterator
        fileprivate let owner: ShellOutputChunkStream

        /// The next event, or `nil` after the stream ended.
        ///
        /// `nil` covers the two ways the stream can end — `finish()`, and a
        /// cancel of this task while it waits here. The underlying
        /// `AsyncStream` does not tell the two apart, and it need not: after
        /// either one the stream is spent and it can give nothing more. Thus
        /// `nil` is where the stream is MARKED finished, which is what stops
        /// the producer from keeping budget for bytes that no consumer can take
        /// or release. Without that mark a cancelled consumer would hold the
        /// budget for the life of the object.
        ///
        /// - Returns: The next event in delivery order, or `nil` at the end.
        public mutating func next() async -> ShellOutputEvent? {
            guard let event = await base.next() else {
                owner.finish()
                return nil
            }
            owner.releaseBudget(for: event)
            return event
        }
    }

    // MARK: - The producer side

    /// Offers one raw chunk to the consumer. The chunk goes away when the
    /// budget of pending bytes is spent.
    ///
    /// It never blocks and it never suspends.
    ///
    /// The chunk that goes away is the ARRIVING one, and not a chunk that is
    /// already in the queue. That is what keeps a gap honest: each event the
    /// consumer did not take yet stands BEFORE the hole, thus the gap that
    /// stands before the next accepted chunk stands exactly where the missing
    /// bytes were. A stream that dropped the oldest event instead would put the
    /// hole behind events that already stand past it, and no position of a
    /// marker could state that.
    ///
    /// - Parameters:
    ///   - commandID: The completion token of the run that wrote the bytes.
    ///   - stream: Which of the two streams of that run the bytes came from.
    ///   - bytes: The bytes, exactly as the child wrote them.
    ///   - maxSize: The cap of the store behind `snapshot(for:)` for this run,
    ///     which is the captured-output cap of the runner. The stream reads it
    ///     the first time it sees this run, and each later call uses the store
    ///     it already made. There is no default: the runner owns that cap, and
    ///     a default here would make a second home for it.
    func send(commandID: String, stream: ShellOutputStream, bytes: [UInt8], maxSize: Int) {
        guard !bytes.isEmpty else { return }
        let key = GapKey(commandID: commandID, stream: stream)
        let events = state.withLock { pending -> [ShellOutputEvent] in
            guard !pending.isFinished else { return [] }

            // The store behind the snapshot. It takes each chunk, before the
            // budget test below, thus a chunk that goes away from the live
            // queue stays here — see the header of this file. The write goes
            // through the `default:` subscript of the dictionary, and not
            // through a read, a change and a write back. Thus an append stays
            // amortized O(1), and it does not copy the whole capture for each
            // chunk.
            Self.append(
                bytes, from: stream,
                to: &pending.rawBuffers[commandID, default: OutputBuffer(maxSize: maxSize)])

            guard pending.byteCount < maxPendingBytes else {
                pending.droppedBytes[key, default: 0] += bytes.count
                return []
            }
            pending.byteCount += bytes.count
            return Self.owedGap(for: key, draining: &pending.droppedBytes)
                + [ShellOutputEvent(commandID: commandID, kind: .output(stream: stream, bytes: bytes))]
        }
        deliver(events)
    }

    /// Delivers the completion marker of `commandID`, after any gap the two
    /// streams of that run still owe.
    ///
    /// The marker never goes away, and the call never blocks.
    ///
    /// - Parameter commandID: The completion token of the run that ended.
    func complete(commandID: String) {
        let events = state.withLock { pending -> [ShellOutputEvent] in
            guard !pending.isFinished else { return [] }
            var owed: [ShellOutputEvent] = []
            for stream in ShellOutputStream.allCases {
                owed += Self.owedGap(
                    for: GapKey(commandID: commandID, stream: stream),
                    draining: &pending.droppedBytes)
            }
            return owed + [ShellOutputEvent(commandID: commandID, kind: .completed)]
        }
        deliver(events)
    }

    /// Writes `bytes` into the stream of `buffer` that `stream` names.
    ///
    /// `OutputBuffer` gives one write method for each of its two streams, thus
    /// this is where the stream of an event becomes a choice of method. It
    /// takes the buffer as `inout`, thus the caller writes the subscript of the
    /// dictionary one time and the write stays in place.
    ///
    /// - Parameters:
    ///   - bytes: The bytes to store.
    ///   - stream: Which of the two streams of the run wrote them.
    ///   - buffer: The capture of that run.
    private static func append(
        _ bytes: [UInt8], from stream: ShellOutputStream, to buffer: inout OutputBuffer
    ) {
        switch stream {
        case .stdout: buffer.appendStdout(bytes)
        case .stderr: buffer.appendStderr(bytes)
        }
    }

    // MARK: - Storage

    /// The key of the drop accounting: one pair of a run and a stream. A gap
    /// belongs to one stream of one run, and never to a whole run.
    private struct GapKey: Hashable, Sendable {
        /// The completion token of the run whose bytes went away.
        let commandID: String
        /// The stream they went away from.
        let stream: ShellOutputStream
    }

    /// Everything the producer and the consumer share, under one lock.
    ///
    /// How many bytes stand in the queue and unread, what went away and is not
    /// reported yet, whether the host stopped listening, and the store behind
    /// the snapshot.
    private struct PendingState: Sendable {
        /// The bytes that went into the queue and that no consumer took yet.
        var byteCount = 0

        /// The bytes that went away and that no gap reported yet, for each pair
        /// of a run and a stream.
        var droppedBytes: [GapKey: Int] = [:]

        /// Tells if `finish()` ran. Each later send does nothing.
        var isFinished = false

        /// The raw capture of each run, which `send` fills without regard for
        /// the budget of the live delivery. This is the store behind
        /// `snapshot(for:)`. See the header of this file.
        ///
        /// It stays for the life of this stream: nothing here removes the entry
        /// of a run. `complete(commandID:)` does not remove it, and only
        /// `finish()` stops the store from growing, by refusing each later run
        /// as well. Thus a host that runs many commands through one long-lived
        /// stream keeps each of their captures (each one up to its own
        /// `maxSize`) in memory for as long as the stream lives. `ShellState`
        /// is different: it holds small records only, and it leaves the output
        /// on disk. A host that cares must finish and replace the stream from
        /// time to time, or keep `maxSize` small.
        var rawBuffers: [String: OutputBuffer] = [:]
    }

    private let base: AsyncStream<ShellOutputEvent>
    private let continuation: AsyncStream<ShellOutputEvent>.Continuation
    private let state = Mutex(PendingState())

    /// The gap event that `key` owes, and which this call clears.
    ///
    /// It is empty when nothing went away for that pair of a run and a stream
    /// since its last delivered event.
    ///
    /// - Parameters:
    ///   - key: The pair of a run and a stream to report on.
    ///   - dropped: The drop counters to take the entry out of.
    /// - Returns: The one gap event that is owed, or an empty array.
    private static func owedGap(
        for key: GapKey, draining dropped: inout [GapKey: Int]
    ) -> [ShellOutputEvent] {
        guard let byteCount = dropped.removeValue(forKey: key) else { return [] }
        return [
            ShellOutputEvent(
                commandID: key.commandID,
                kind: .gap(stream: key.stream, droppedByteCount: byteCount))
        ]
    }

    /// Gives `events` to the consumer, in order.
    ///
    /// The call stands outside the lock. The decision of WHAT to deliver is the
    /// part that needs the lock, and the enqueue itself does not.
    ///
    /// - Parameter events: The events to enqueue, in delivery order.
    private func deliver(_ events: [ShellOutputEvent]) {
        for event in events {
            continuation.yield(event)
        }
    }

    /// Gives the bytes of an event back to the budget, after the consumer took
    /// that event.
    ///
    /// It is the counterpart of the `send` that spent them, and it is the one
    /// thing that makes room for a new chunk.
    ///
    /// - Parameter event: The event the consumer just took.
    fileprivate func releaseBudget(for event: ShellOutputEvent) {
        guard case .output(_, let bytes) = event.kind else { return }
        state.withLock { $0.byteCount -= bytes.count }
    }
}
