// `OutputBuffer` — the capture store of one shell run.
//
// eventplan.md § "Consolidation of the siblings" keeps the run plane and the
// content plane apart. The mailbox carries envelopes only, and it never carries
// bulk output. The captured output of a run stays in the store of the
// capability that owns the run. This buffer is that store for the shell
// capability: it takes the bytes the child writes, it keeps them under one byte
// cap, and it gives them back as log lines for `ShellState`.
//
// The buffer holds no identifier of its own, and it mints none. The owner of a
// buffer keys it on the completion-token `String` of its run — the one string
// that is also the `commandID` of `ShellState` and the `correlationID` of the
// Router mailbox. Thus a second kind of identifier cannot start here.
//
// The buffer stays readable while the child process runs. Each read below
// answers with the bytes that arrived before the read, and no read waits for
// the end of the run. Thus `tools.shell.getLines` answers for a run that is
// still going, and also for a run that ended.
//
// The rules of the capture:
//
//   - One `maxSize` cap holds stdout and stderr together. The cumulative
//     `storedByteCount`, and not the momentary `currentSize`, is what `append`
//     counts against that cap — see below. The bytes past the cap go away, but
//     `totalBytesProcessed` counts each byte that arrived.
//   - A truncation prefers a line boundary: the last `\n` inside the part that
//     fits, or else the last start of a UTF-8 code point. Thus a stored buffer
//     never cuts through the middle of a code point.
//   - Binary detection: a null byte inside the first bytes of any chunk marks
//     the whole capture binary, and a binary capture renders as
//     `[Binary content: {n} bytes]` and not as its bytes.
//   - No ANSI text goes away. The store keeps the bytes as they arrived.
//
// There are three ways to read the buffer back:
//
//   - Whole. Write each chunk, then read `stdoutLines` and `stderrLines` one
//     time at the end.
//   - Line by line. `extractCompletedStdoutLines()` and
//     `extractCompletedStderrLines()` take the lines of each stream that are
//     complete (up to the last `\n` that arrived) as the chunks arrive, and
//     they keep a line that is not complete for a later call. `finish()` seals
//     the buffer at the end of the stream: it writes that last part line, or a
//     marker line or a placeholder line in place of it. This is the way the
//     runner puts the output of a command that still runs into `ShellState`.
//   - Byte for byte. `rawStdout` and `rawStderr`, and `extractRawStdout()` and
//     `extractRawStderr()`, give the stored bytes themselves. This path applies
//     no UTF-8 decode, no split into lines, and no placeholder. It is the view
//     for a consumer that must reproduce the output of a command byte for byte
//     — a terminal that shows output which is not valid UTF-8 — and not read it
//     as text.
//
// A drain can take bytes back out of the two streams. Thus the cap cannot count
// `currentSize`, which is the number of bytes that are in the buffer at this
// moment: a drain would then open room under the cap again. `storedByteCount`
// is the cumulative counter the cap uses instead. It only grows, by exactly the
// bytes that went into storage, and a drain does not lower it.
//
// The split of a stored stream into lines is `ShellState.splitLogLines`, which
// is the one home of that split and of that decode. This file calls it, and it
// holds no copy of it. Thus the lines this buffer writes and the lines the log
// scan reads back cannot drift apart.

import Foundation

/// The capture store of the stdout and the stderr of one command, under one
/// byte cap.
struct OutputBuffer: Sendable {

    // MARK: - The constants of the capture

    /// The number of bytes of a chunk that the binary scan reads.
    ///
    /// The value is 8 KiB, and it is written as one number. Do not write it as
    /// a calculation: a calculation makes two numbers that have no name.
    ///
    /// A null byte after this many bytes does not mark the capture binary. A
    /// test of the buffer reads this value, thus the test states the window one
    /// time and not two times.
    static let binaryDetectionSampleBytes = 8_192

    /// The marker line that `finish()` writes after a truncation.
    private static let truncationMarker = "[Output truncated - exceeded size limit]"

    /// The bit that a byte of one-byte (ASCII) UTF-8 does not carry. A byte
    /// with this bit clear is a code point of one byte.
    private static let utf8SingleByteMask: UInt8 = 0x80

    /// The two high bits that the first byte of a UTF-8 code point of more than
    /// one byte carries. A byte with the first bit set and the second bit clear
    /// continues a code point, thus it is not a place to cut.
    private static let utf8LeadByteMask: UInt8 = 0xC0

    // MARK: - The state of the capture

    /// The cap on the stored bytes, which stdout and stderr share.
    let maxSize: Int

    /// The stdout bytes that are in the buffer now.
    private var stdoutData: [UInt8] = []

    /// The stderr bytes that are in the buffer now.
    private var stderrData: [UInt8] = []

    /// Tells if the buffer dropped output to stay under `maxSize`.
    private(set) var truncated = false

    /// Tells if a chunk carried binary content (a null byte).
    private(set) var binaryDetected = false

    /// The number of bytes that arrived, the dropped bytes included.
    private(set) var totalBytesProcessed = 0

    /// The cumulative number of bytes that went into storage: the bytes a drain
    /// took out, plus the bytes that are in `stdoutData` and `stderrData` now.
    ///
    /// It only grows, and a drain of the two streams does not lower it. This,
    /// and not `currentSize`, is what `append` counts against `maxSize`. Thus
    /// the cap stays enforced across the drains (see the header of this file).
    private(set) var storedByteCount = 0

    /// Makes a buffer with the byte cap it must hold.
    ///
    /// - Parameter maxSize: The cap on the stored bytes, for the two streams
    ///   together.
    init(maxSize: Int) {
        self.maxSize = maxSize
    }

    /// The number of bytes that are in the two streams now.
    var currentSize: Int { stdoutData.count + stderrData.count }

    /// Tells if the bytes that are in the buffer now reach the cap.
    ///
    /// A drain lowers `currentSize`, thus this can become false again while
    /// `append` still refuses more bytes: `append` counts the cumulative
    /// `storedByteCount`.
    var isAtLimit: Bool { currentSize >= maxSize }

    // MARK: - Writing

    /// Appends `data` to the stdout stream, under the shared cap and with the
    /// binary scan.
    ///
    /// - Parameter data: The bytes the child wrote to stdout.
    /// - Returns: The number of bytes that went into storage.
    @discardableResult
    mutating func appendStdout(_ data: [UInt8]) -> Int {
        append(data, to: \.stdoutData)
    }

    /// Appends `data` to the stderr stream, under the shared cap and with the
    /// binary scan.
    ///
    /// - Parameter data: The bytes the child wrote to stderr.
    /// - Returns: The number of bytes that went into storage.
    @discardableResult
    mutating func appendStderr(_ data: [UInt8]) -> Int {
        append(data, to: \.stderrData)
    }

    /// Appends `data` to the stream at `keyPath`.
    ///
    /// The cap counts the cumulative `storedByteCount`, and not `currentSize`:
    /// a drain can already have taken bytes back out of the two streams, and
    /// the cap must hold against each byte that ever went into storage (see the
    /// header of this file).
    ///
    /// - Parameters:
    ///   - data: The bytes that arrived.
    ///   - keyPath: The stream to write to.
    /// - Returns: The number of bytes that went into storage.
    private mutating func append(
        _ data: [UInt8], to keyPath: WritableKeyPath<OutputBuffer, [UInt8]>
    ) -> Int {
        totalBytesProcessed += data.count

        if !binaryDetected {
            binaryDetected = Self.isBinary(data)
        }

        let available = max(0, maxSize - storedByteCount)
        if available == 0 {
            truncated = true
            return 0
        }

        let bytesToAppend = min(data.count, available)
        let overflows = bytesToAppend < data.count
        if overflows {
            truncated = true
        }

        let actual = overflows ? Self.safeTruncationPoint(data, upTo: bytesToAppend) : bytesToAppend
        self[keyPath: keyPath].append(contentsOf: data[0..<actual])
        storedByteCount += actual
        return actual
    }

    // MARK: - Reading the whole capture as text

    /// The stdout as text: the binary placeholder for a binary capture, and a
    /// UTF-8 decode with replacement for text.
    var stdout: String { formatted(stdoutData) }

    /// The stderr as text, the way `stdout` gives the stdout.
    var stderr: String { formatted(stderrData) }

    /// The stdout as the log lines that `ShellState` reads back.
    var stdoutLines: [String] { logLines(from: stdoutData) }

    /// The stderr as the log lines that `ShellState` reads back.
    var stderrLines: [String] { logLines(from: stderrData) }

    // MARK: - Reading the bytes themselves

    /// The bytes of one stream, exactly as the child wrote them, with the state
    /// of the capture that says how to present them.
    ///
    /// No UTF-8 decode and no placeholder touches the bytes. That is what makes
    /// them usable where the bytes themselves are the requirement — a terminal
    /// that shows output which is not valid UTF-8 (see the third way to read
    /// the buffer, in the header of this file). The three state fields travel
    /// with the bytes, thus a consumer that holds a drained chunk can judge it
    /// with no second look at the buffer it came from.
    ///
    /// That judgement is for one chunk. The choice of a read pattern is not:
    /// the raw drain and the line drain take the same bytes out of the same
    /// stream (see `extractRawStdout()`), and this buffer keeps no second copy.
    /// Thus a consumer chooses one time for each capture: it drains the chunks
    /// as they arrive, or it leaves the buffer alone and reads `rawStdout` and
    /// `rawStderr` as one view of the whole output. A consumer that drained
    /// cannot make that whole view again from this buffer.
    struct RawOutput: Sendable, Equatable {
        /// The bytes of the stream, exactly as the child wrote them.
        var bytes: [UInt8]
        /// Tells if a chunk of this capture carried binary content — the same
        /// flag as `OutputBuffer.binaryDetected`. It is information only on
        /// this path: the raw path continues to give bytes back after the flag
        /// is set, and the line path does not.
        var binaryDetected: Bool
        /// Tells if the buffer dropped output to stay under `maxSize` — the
        /// same flag as `OutputBuffer.truncated`. After it is set, this capture
        /// is no longer byte for byte, and a consumer must stop reading the
        /// chunks as one continuous run: what is stored is a part of what the
        /// child wrote, and it is **not necessarily the first part**. Often it
        /// is in fact a clean first part (a whole over-cap chunk went away, or
        /// a chunk cut at its last `\n`), and that is exactly why a consumer
        /// must code against the weaker promise: `append` moves an over-cap
        /// chunk back to a safe boundary, which can store fewer bytes than the
        /// cap had room for, and a later chunk can then land on the far side of
        /// the hole that leaves.
        var truncated: Bool
        /// The cumulative bytes that went into storage for the two streams —
        /// the same counter as `OutputBuffer.storedByteCount`. Thus it is
        /// larger than `bytes.count` after a drain, and also after the other
        /// stream stored bytes.
        var storedByteCount: Int
    }

    /// The stdout bytes that are in the buffer now, with the binary state and
    /// the truncation state of the capture.
    ///
    /// A read of this does not drain: the buffer stays exactly as it was, which
    /// is what makes it different from `extractRawStdout()`.
    var rawStdout: RawOutput { rawOutput(from: stdoutData) }

    /// The stderr counterpart of `rawStdout`.
    var rawStderr: RawOutput { rawOutput(from: stderrData) }

    // MARK: - The drain of the completed lines

    /// Takes the stdout bytes that completed since the last drain — each byte
    /// up to and with the last `\n` that is in the buffer — and gives them back
    /// as log lines.
    ///
    /// A line that is not complete (it has no `\n` yet) stays in the buffer for
    /// a later call or for `finish()`. The call gives nothing back after
    /// `binaryDetected` is set: binary content does not flow line by line, and
    /// `finish()` writes the one placeholder line instead (see the header of
    /// this file).
    ///
    /// - Returns: The lines that completed, in order.
    @discardableResult
    mutating func extractCompletedStdoutLines() -> [String] {
        extractCompletedLines(from: \.stdoutData)
    }

    /// The stderr counterpart of `extractCompletedStdoutLines()`.
    ///
    /// - Returns: The lines that completed, in order.
    @discardableResult
    mutating func extractCompletedStderrLines() -> [String] {
        extractCompletedLines(from: \.stderrData)
    }

    /// Takes the completed lines of the stream at `keyPath`.
    ///
    /// It finds the last `\n` of the stream, it splits each byte up to and with
    /// that `\n` into log lines, and it keeps the remainder — the line that is
    /// not complete, if there is one — in the buffer. The drain moves bytes out
    /// of the stream only. It does not touch `storedByteCount`, thus the cap
    /// stays enforced cumulatively.
    ///
    /// - Parameter keyPath: The stream to drain.
    /// - Returns: The lines that completed, in order.
    private mutating func extractCompletedLines(
        from keyPath: WritableKeyPath<OutputBuffer, [UInt8]>
    ) -> [String] {
        guard !binaryDetected else { return [] }
        let data = self[keyPath: keyPath]
        guard let cut = data.lastIndex(of: ShellState.newlineByte) else { return [] }

        let lines = ShellState.splitLogLines(data[data.startIndex...cut])
        self[keyPath: keyPath] = Array(data[data.index(after: cut)...])
        return lines
    }

    // MARK: - The drain of the bytes themselves

    /// Takes each stdout byte that is in the buffer now, and gives it back with
    /// the state of the capture — the byte-for-byte counterpart of
    /// `extractCompletedStdoutLines()`, for a consumer that sends the chunks to
    /// a terminal and not the lines to the shell log.
    ///
    /// It is different from the line drain in the two ways that byte fidelity
    /// needs:
    ///
    ///   - It takes *each* byte, a line that is not complete included. A
    ///     terminal shows a half-written line as it arrives, thus there is
    ///     nothing to keep back — and thus, unlike the line drain, this drain
    ///     owes nothing at the end of the stream: the last call after the last
    ///     chunk is the whole of its sealing step. There is no raw counterpart
    ///     to `finish()`, because a byte-for-byte view has no place for a
    ///     marker line or a placeholder line. That last call must come *before*
    ///     any call to `finish()`, which is itself a third drain of these same
    ///     bytes, and one that destroys what it takes — see `finish()`.
    ///   - It continues to give bytes back after `binaryDetected` is set.
    ///     Output that is not valid UTF-8 is what this path exists to carry,
    ///     thus the flag travels on the `RawOutput` instead of stopping the
    ///     stream the way it stops the line path.
    ///
    /// The two drains take the same bytes out of the same stream, thus a stream
    /// has one drain and not two: the path that takes a byte is the only path
    /// that sees it. Choose one path for each stream and stay with it.
    ///
    /// Like the line drain, this drain moves bytes out of the stream only. It
    /// does not touch `storedByteCount`, thus the cap stays enforced
    /// cumulatively (see the header of this file).
    ///
    /// - Returns: The bytes that were in the stdout stream, with the state of
    ///   the capture.
    mutating func extractRawStdout() -> RawOutput {
        extractRaw(from: \.stdoutData)
    }

    /// The stderr counterpart of `extractRawStdout()`.
    ///
    /// - Returns: The bytes that were in the stderr stream, with the state of
    ///   the capture.
    mutating func extractRawStderr() -> RawOutput {
        extractRaw(from: \.stderrData)
    }

    /// Takes each byte of the stream at `keyPath`: it makes the view of the
    /// stream first, and it empties the stream after. Thus the next call gives
    /// back the bytes that arrive after this call only.
    ///
    /// - Parameter keyPath: The stream to drain.
    /// - Returns: The bytes that were in the stream, with the state of the
    ///   capture.
    private mutating func extractRaw(
        from keyPath: WritableKeyPath<OutputBuffer, [UInt8]>
    ) -> RawOutput {
        let snapshot = rawOutput(from: self[keyPath: keyPath])
        self[keyPath: keyPath] = []
        return snapshot
    }

    // MARK: - The seal at the end of the stream

    /// The lines the buffer still owes to the log when `finish()` seals it: the
    /// line of each stream that is not complete (when the capture is not binary
    /// and not truncated), or the marker line or the placeholder line.
    ///
    /// Each array usually holds one line. The runner writes them with
    /// `ShellState.appendLines`, exactly as it writes any other drain.
    struct FinalLines: Sendable, Equatable {
        /// The stdout lines the buffer owes at the end of the stream.
        var stdout: [String] = []
        /// The stderr lines the buffer owes at the end of the stream.
        var stderr: [String] = []
    }

    /// Seals the buffer at the end of the stream. No call to `append`, to a
    /// line drain, or to a raw drain is expected after it.
    ///
    /// This is the third drain of the same bytes, and it destroys them: the
    /// branch that runs drops what it does not give back as lines. Thus a
    /// consumer of the raw path must take its last `extractRawStdout()` and
    /// `extractRawStderr()` *before* this call. What is still in the buffer
    /// goes away, and no call gives it back.
    ///
    /// - When the capture is binary, the bytes of the two streams go away and
    ///   the answer holds one `[Binary content: {n} bytes]` line. The count is
    ///   the cumulative `storedByteCount`, and not the byte count of one stream
    ///   at this moment, which holds only what no drain took yet.
    /// - In each other case, the remaining bytes of each stream split into log
    ///   lines — however many lines that is. Under the line drain that is the
    ///   one line that is not complete, because each line before it already
    ///   went out. A buffer that no call drained gives its whole capture here.
    ///   After a truncation, the marker line follows the lines of the stream
    ///   that has a last line, stdout first, and it goes to stdout when neither
    ///   stream has one.
    ///
    /// - Returns: The lines the buffer owes at the end of the stream.
    mutating func finish() -> FinalLines {
        if binaryDetected {
            stdoutData = []
            stderrData = []
            return FinalLines(stdout: [binaryPlaceholderLine])
        }

        var result = FinalLines()
        result.stdout = drainLines(from: \.stdoutData)
        result.stderr = drainLines(from: \.stderrData)

        if truncated {
            let marker = Self.truncationMarker
            if result.stdout.isEmpty, !result.stderr.isEmpty {
                result.stderr.append(marker)
            } else {
                result.stdout.append(marker)
            }
        }

        return result
    }

    /// Takes each byte of the stream at `keyPath` and gives it back as log
    /// lines. The stream is empty after the call.
    ///
    /// - Parameter keyPath: The stream to drain.
    /// - Returns: One line for each line of the stream, and no line for an
    ///   empty stream.
    private mutating func drainLines(
        from keyPath: WritableKeyPath<OutputBuffer, [UInt8]>
    ) -> [String] {
        let data = self[keyPath: keyPath]
        guard !data.isEmpty else { return [] }
        self[keyPath: keyPath] = []
        return ShellState.splitLogLines(data)
    }

    // MARK: - Helpers

    /// The place to cut inside `data[0..<limit]`: the byte after the last `\n`,
    /// or else the last byte that starts a UTF-8 code point, or else `limit`.
    ///
    /// - Parameters:
    ///   - data: The bytes that arrived.
    ///   - limit: The number of bytes that fit under the cap.
    /// - Returns: The number of bytes to store.
    private static func safeTruncationPoint(_ data: [UInt8], upTo limit: Int) -> Int {
        guard limit > 0 else { return 0 }
        if let lastNewline = data[..<limit].lastIndex(of: ShellState.newlineByte) {
            return lastNewline + 1
        }
        for index in stride(from: limit - 1, through: 0, by: -1)
        where startsCodePoint(data[index]) {
            return index
        }
        return limit
    }

    /// Tells if `byte` starts a UTF-8 code point.
    ///
    /// A byte of one-byte UTF-8 carries no high bit, and the first byte of a
    /// code point of more than one byte carries the two high bits. A byte that
    /// carries the first bit only continues a code point, thus a cut there
    /// would break that code point.
    ///
    /// - Parameter byte: The byte to examine.
    /// - Returns: `true` when a cut at this byte keeps each code point whole.
    private static func startsCodePoint(_ byte: UInt8) -> Bool {
        byte & utf8SingleByteMask == 0 || byte & utf8LeadByteMask == utf8LeadByteMask
    }

    /// Tells if `data` looks binary: it holds a null byte inside the first
    /// `binaryDetectionSampleBytes` bytes.
    ///
    /// - Parameter data: The bytes to scan.
    /// - Returns: `true` for binary content.
    private static func isBinary(_ data: [UInt8]) -> Bool {
        guard !data.isEmpty else { return false }
        let sampleCount = min(data.count, binaryDetectionSampleBytes)
        for index in 0..<sampleCount where data[index] == 0 {
            return true
        }
        return false
    }

    /// The line that stands in place of the bytes of a binary capture.
    ///
    /// The count is always the cumulative `storedByteCount`. Thus a live read
    /// (`stdout`, `stderr`) and `finish()` report the same count for the same
    /// event, and this is the one home of the text of that line.
    private var binaryPlaceholderLine: String {
        "[Binary content: \(storedByteCount) bytes]"
    }

    /// Tells if `data` must render as the binary placeholder.
    ///
    /// The flag of the capture decides first, because a null byte in one stream
    /// makes the whole capture binary. A scan of `data` answers for a stream
    /// that holds a null byte which no `append` of this buffer saw.
    ///
    /// - Parameter data: The bytes of one stream.
    /// - Returns: `true` when the placeholder stands in place of the bytes.
    private func showsAsBinary(_ data: [UInt8]) -> Bool {
        binaryDetected || Self.isBinary(data)
    }

    /// The stored bytes as text: the binary placeholder for a binary capture,
    /// and a UTF-8 decode with replacement for text.
    ///
    /// - Parameter data: The bytes of one stream.
    /// - Returns: The text of that stream.
    private func formatted(_ data: [UInt8]) -> String {
        guard !showsAsBinary(data) else { return binaryPlaceholderLine }
        return String(decoding: data, as: UTF8.self)
    }

    /// The stored bytes as the log lines that `ShellState` reads back.
    ///
    /// A binary stream gives its one placeholder line. Text goes to
    /// `ShellState.splitLogLines`, which is the one home of the split and of
    /// the decode.
    ///
    /// - Parameter data: The bytes of one stream.
    /// - Returns: One string for each line, and no line for an empty stream.
    private func logLines(from data: [UInt8]) -> [String] {
        // An empty stream gives no log line, also when the *other* stream set
        // the binary flag: there is nothing here for a placeholder to stand in
        // place of.
        guard !data.isEmpty else { return [] }
        guard !showsAsBinary(data) else { return [binaryPlaceholderLine] }
        return ShellState.splitLogLines(data)
    }

    /// Puts `data` with the state of the capture that each `RawOutput` carries.
    ///
    /// This is the one place a `RawOutput` is made: `rawStdout`, `rawStderr`,
    /// `extractRawStdout()` and `extractRawStderr()` each reach it. Thus the
    /// four report the same state for the same moment. The bytes go through
    /// with no change: this is the one read-back path with no formatting step
    /// at all — `formatted(_:)` and `logLines(from:)` each have one.
    ///
    /// - Parameter data: The bytes of one stream.
    /// - Returns: The bytes with the state of the capture.
    private func rawOutput(from data: [UInt8]) -> RawOutput {
        RawOutput(
            bytes: data, binaryDetected: binaryDetected, truncated: truncated,
            storedByteCount: storedByteCount)
    }
}
