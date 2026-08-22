import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Behavioral tests for `OutputBuffer` — the capture store of one shell run.
///
/// The buffer takes the bytes a child process writes, it keeps them under one
/// byte cap, and it gives them back as log lines. eventplan.md
/// § "Consolidation of the siblings" makes this store the content plane of a
/// run. Thus a read of the buffer answers with the bytes that arrived before
/// the read, and no read waits for the end of the run.
///
/// Each test makes a buffer of its own, thus the tests are independent and
/// they run in parallel safely.
///
/// The two tests that start `/bin/cat` write a file into a temporary directory
/// and read the output of a local command of the operating system. A local
/// command is not an external system, thus these two tests stay unit tests and
/// they need no integration package.
@Suite("OutputBufferTests")
struct OutputBufferTests {

    // MARK: - Fixtures

    /// Owns the temporary directories the two child-process tests make. Thus
    /// the directories go away when the test ends.
    private let scratch = TestScratch()

    /// The name prefix of the temporary directory of one test. Thus a leaked
    /// directory is traceable to this suite.
    private static let testDirectoryNamePrefix = "outputbuffer-tests"

    /// The name of the file the child-process tests give to `/bin/cat`.
    private static let fixtureFileName = "fixture.bin"

    /// The path of the command the child-process tests start.
    ///
    /// The tests name the absolute path, thus the test does not depend on the
    /// `PATH` of the person or of the machine that runs it.
    private static let catExecutablePath = "/bin/cat"

    /// The cap of a buffer that its test does not fill. Thus the test examines
    /// the capture and not the cap.
    private static let spaciousCapBytes = 1000

    /// The cap of each test that examines a buffer with little room left.
    private static let tightCapBytes = 10

    /// The cap of the shared-cap test. It is larger than the stdout write of
    /// that test, and smaller than the two writes together.
    private static let sharedCapBytes = 20

    /// The cap of the code-point-boundary test.
    ///
    /// The write of that test holds no `\n` inside the cap. Thus the cut falls
    /// back to the last start of a code point.
    private static let codePointCapBytes = 8

    /// A cap that is much larger than `OutputBuffer.binaryDetectionSampleBytes`.
    /// Thus the two sample-window tests examine the window and not the cap.
    private static let sampleWindowCapBytes = 2 * OutputBuffer.binaryDetectionSampleBytes

    /// The cap of the two child-process tests. It is much larger than the
    /// fixture each one writes, thus the capture holds every byte.
    private static let childOutputCapBytes = 1 << 20

    /// The text the truncation tests hold under the cap.
    private static let twoLineText = "line1\nline2\n"

    /// The lines of `twoLineText`, as the buffer gives them back.
    private static let twoLineTexts = ["line1", "line2"]

    /// The text the truncation tests write. It is one line longer than the cap
    /// holds.
    private static let threeLineText = "line1\nline2\nline3\n"

    /// The cap that holds `twoLineText` exactly, and no byte more.
    private static let twoLineCapBytes = twoLineText.utf8.count

    /// The text of the marker line that `finish()` writes after a truncation.
    ///
    /// This suite states the text itself, thus a change of the text in
    /// `OutputBuffer` makes these tests fail. That is what a pinned text must
    /// do.
    private static let truncationMarkerText = "[Output truncated - exceeded size limit]"

    /// The number of repetitions of each byte value in the small child
    /// fixture. The fixture is then 1 KiB, which one read of the pipe gives.
    private static let smallFixtureRepeatCount = 4

    /// The number of repetitions of each byte value in the large child
    /// fixture. The fixture is then 256 KiB, which needs several reads of the
    /// pipe.
    private static let largeFixtureRepeatCount = 1024

    /// The bytes of the binary golden case.
    private static let binaryGoldenInput: [UInt8] = [0x00, 0x01] + bytes("abc\n")

    /// The bytes of the golden case that no UTF-8 decode accepts. The bytes
    /// hold no null byte, thus the capture stays text.
    private static let undecodableGoldenInput: [UInt8] = bytes("a") + [0xFF, 0x80] + bytes("b\n")

    /// The lossy decode of `undecodableGoldenInput`: one replacement character
    /// for each byte that does not decode.
    private static let undecodableGoldenText = "a\u{FFFD}\u{FFFD}b\n"

    /// The line that stands in place of the bytes of a binary capture.
    ///
    /// This suite states the text itself, for the reason `truncationMarkerText`
    /// states.
    ///
    /// - Parameter byteCount: The number of bytes the capture stored.
    /// - Returns: The one line a binary capture gives.
    private static func binaryPlaceholder(byteCount: Int) -> String {
        "[Binary content: \(byteCount) bytes]"
    }

    /// The UTF-8 bytes of `text`.
    ///
    /// - Parameter text: The text to encode.
    /// - Returns: One byte for each byte of the UTF-8 form.
    private static func bytes(_ text: String) -> [UInt8] {
        Array(text.utf8)
    }

    /// A fixture that holds `count` repetitions of each byte value from `0`
    /// through `255`.
    ///
    /// It holds null bytes, thus the buffer marks it binary. It holds bytes
    /// that no UTF-8 decode accepts, and it holds `\n` bytes. Thus one value
    /// examines each part of the raw path.
    ///
    /// - Parameter count: The number of repetitions of the full byte range.
    /// - Returns: The bytes of the fixture.
    private static func everyByteValue(repeating count: Int) -> [UInt8] {
        let allValues = Array(UInt8.min...UInt8.max)
        return (0..<count).flatMap { _ in allValues }
    }

    /// Starts `/bin/cat` on a temporary file that holds `fixture`, and gives
    /// back the chunks the pipe delivered, in the order they arrived.
    ///
    /// A file and `cat`, and not `printf`: the child then writes exactly the
    /// bytes of the fixture, and no escape rule of a shell can change them. A
    /// null byte is the byte that a shell most easily loses.
    ///
    /// - Parameter fixture: The bytes the child must write.
    /// - Returns: One array for each read of the pipe, in the order of arrival.
    /// - Throws: When the directory, the file, or the child does not start.
    private func catFixtureChunks(_ fixture: [UInt8]) throws -> [[UInt8]] {
        let directory = try scratch.makeDirectory(prefix: Self.testDirectoryNamePrefix)
        let url = directory.appendingPathComponent(Self.fixtureFileName)
        try Data(fixture).write(to: url)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.catExecutablePath)
        process.arguments = [url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()

        var chunks: [[UInt8]] = []
        while true {
            let data = pipe.fileHandleForReading.availableData
            if data.isEmpty { break }
            chunks.append(Array(data))
        }
        process.waitUntilExit()
        return chunks
    }

    // MARK: - Basic capture

    @Test("Output under the cap is captured byte for byte")
    func underTheCapTheOutputIsCapturedByteForByte() {
        var buffer = OutputBuffer(maxSize: Self.spaciousCapBytes)
        let input = "hello world\n"
        let written = buffer.appendStdout(Self.bytes(input))

        #expect(written == input.utf8.count)
        #expect(buffer.currentSize == input.utf8.count)
        #expect(!buffer.truncated)
        #expect(!buffer.binaryDetected)
        #expect(buffer.stdout == input)
        #expect(buffer.stdoutLines == ["hello world"])
    }

    @Test("totalBytesProcessed counts each byte, the dropped bytes included")
    func totalBytesProcessedCountsEachByteTheDroppedBytesIncluded() {
        var buffer = OutputBuffer(maxSize: Self.tightCapBytes)
        let input = Self.bytes("0123456789ABCDEF")
        buffer.appendStdout(input)

        #expect(input.count > Self.tightCapBytes)
        #expect(buffer.totalBytesProcessed == input.count)
        #expect(buffer.currentSize <= Self.tightCapBytes)
        #expect(buffer.truncated)
    }

    // MARK: - One cap for stdout and stderr together

    @Test("One cap holds stdout and stderr together")
    func oneCapHoldsStdoutAndStderrTogether() {
        var buffer = OutputBuffer(maxSize: Self.sharedCapBytes)
        let first = Self.bytes("aaaaaaaaaa\n")
        let second = Self.bytes("bbbbbbbbbbbbbbbbbbbb\n")
        buffer.appendStdout(first)
        let written = buffer.appendStderr(second)

        // Only the room the stdout write left is available to stderr.
        #expect(written <= Self.sharedCapBytes - first.count)
        #expect(buffer.currentSize <= Self.sharedCapBytes)
        #expect(buffer.truncated)
    }

    // MARK: - Truncation at a line boundary

    @Test("A write that reaches the cap exactly is not truncated")
    func aWriteThatReachesTheCapExactlyIsNotTruncated() {
        var buffer = OutputBuffer(maxSize: Self.twoLineCapBytes)
        let input = Self.bytes(Self.twoLineText)
        let written = buffer.appendStdout(input)

        #expect(written == input.count)
        #expect(!buffer.truncated)
        #expect(buffer.isAtLimit)
        #expect(buffer.stdoutLines == Self.twoLineTexts)
    }

    @Test("A write past the cap cuts at the last line boundary that fits")
    func aWritePastTheCapCutsAtTheLastLineBoundaryThatFits() {
        var buffer = OutputBuffer(maxSize: Self.twoLineCapBytes)
        buffer.appendStdout(Self.bytes(Self.threeLineText))

        #expect(buffer.truncated)
        #expect(buffer.currentSize <= Self.twoLineCapBytes)
        // The cut lands on a line boundary, thus no part of "line3" is stored.
        #expect(buffer.stdoutLines == Self.twoLineTexts)
    }

    // MARK: - A read while the buffer fills

    @Test("A read before the run ends gives the lines written so far")
    func aReadBeforeTheRunEndsGivesTheLinesWrittenSoFar() {
        var buffer = OutputBuffer(maxSize: Self.spaciousCapBytes)
        buffer.appendStdout(Self.bytes("first\n"))

        // The read happens now, while the child still writes. It does not wait
        // for the end of the run, and no call to `finish()` came before it.
        #expect(buffer.stdoutLines == ["first"])
        #expect(buffer.extractCompletedStdoutLines() == ["first"])

        buffer.appendStdout(Self.bytes("second\n"))
        #expect(buffer.extractCompletedStdoutLines() == ["second"])
    }

    @Test("A write over the cap truncates, and the buffer reports it")
    func aWriteOverTheCapTruncatesAndTheBufferReportsIt() {
        var buffer = OutputBuffer(maxSize: Self.twoLineCapBytes)
        let input = Self.bytes(Self.threeLineText)
        let written = buffer.appendStdout(input)

        #expect(written < input.count)
        #expect(buffer.truncated)
        #expect(buffer.totalBytesProcessed == input.count)
        #expect(buffer.storedByteCount == written)
        #expect(buffer.finish().stdout.last == Self.truncationMarkerText)
    }

    // MARK: - Binary detection

    @Test("A null byte makes the capture binary and replaces its output")
    func aNullByteMakesTheCaptureBinaryAndReplacesItsOutput() {
        var buffer = OutputBuffer(maxSize: Self.spaciousCapBytes)
        let input: [UInt8] = [0x00, 0x01, 0x02, 0xFF] + Self.bytes("abc")
        buffer.appendStdout(input)

        let placeholder = Self.binaryPlaceholder(byteCount: input.count)
        #expect(buffer.binaryDetected)
        #expect(buffer.stdout == placeholder)
        #expect(buffer.stdoutLines == [placeholder])
    }

    @Test("A live placeholder counts the stored bytes of both streams")
    func aLivePlaceholderCountsTheStoredBytesOfBothStreams() {
        var buffer = OutputBuffer(maxSize: Self.spaciousCapBytes)
        let stdoutInput: [UInt8] = [0x00] + Self.bytes("abc\n")
        let stderrInput = Self.bytes("more\n")
        buffer.appendStdout(stdoutInput)
        buffer.appendStderr(stderrInput)

        // The live `stdout` and `stderr` properties report the same count as
        // `finish()` reports for the same event, and not the resident byte
        // count of one stream.
        let placeholder = Self.binaryPlaceholder(byteCount: stdoutInput.count + stderrInput.count)
        #expect(buffer.stdout == placeholder)
        #expect(buffer.stderr == placeholder)

        let final = buffer.finish()
        #expect(final.stdout == [placeholder])
        // The binary branch of `finish()` puts the two streams into the one
        // stdout line above. Thus stderr is empty here, and it holds no second
        // copy of the placeholder.
        #expect(final.stderr == [])
    }

    @Test("Plain text is not marked binary")
    func plainTextIsNotMarkedBinary() {
        var buffer = OutputBuffer(maxSize: Self.spaciousCapBytes)
        buffer.appendStdout(Self.bytes("normal\ttext with tabs\r\nand crlf\n"))

        #expect(!buffer.binaryDetected)
    }

    @Test("A null byte inside the sample window is found")
    func aNullByteInsideTheSampleWindowIsFound() {
        var buffer = OutputBuffer(maxSize: Self.sampleWindowCapBytes)
        // A null byte on the last byte the scan reads is still found.
        var input = [UInt8](
            repeating: UInt8(ascii: "a"), count: OutputBuffer.binaryDetectionSampleBytes)
        input[input.count - 1] = 0
        buffer.appendStdout(input)

        #expect(buffer.binaryDetected)
    }

    @Test("A null byte past the sample window is not found")
    func aNullBytePastTheSampleWindowIsNotFound() {
        var buffer = OutputBuffer(maxSize: Self.sampleWindowCapBytes)
        // The scan does not read the byte after the window, thus it finds no
        // null byte there.
        var input = [UInt8](
            repeating: UInt8(ascii: "a"), count: OutputBuffer.binaryDetectionSampleBytes + 1)
        input[OutputBuffer.binaryDetectionSampleBytes] = 0
        buffer.appendStdout(input)

        #expect(!buffer.binaryDetected)
    }

    // MARK: - The lines agree with the log scan of the store

    @Test("A line drops its trailing carriage return")
    func aLineDropsItsTrailingCarriageReturn() {
        var buffer = OutputBuffer(maxSize: Self.spaciousCapBytes)
        buffer.appendStdout(Self.bytes("carriage\r\nplain\n"))

        #expect(buffer.stdoutLines == ["carriage", "plain"])
    }

    // MARK: - The drain of the completed lines

    @Test("The line drain holds the partial line back until it completes")
    func theLineDrainHoldsThePartialLineBackUntilItCompletes() {
        var buffer = OutputBuffer(maxSize: Self.spaciousCapBytes)
        buffer.appendStdout(Self.bytes("first\nsecond-par"))
        #expect(buffer.extractCompletedStdoutLines() == ["first"])
        // The line that follows holds no `\n` yet, thus there is nothing more
        // to take.
        #expect(buffer.extractCompletedStdoutLines() == [])

        buffer.appendStdout(Self.bytes("tial\nthird\n"))
        #expect(buffer.extractCompletedStdoutLines() == ["second-partial", "third"])
    }

    @Test("The stderr drain is independent of the stdout drain")
    func theStderrDrainIsIndependentOfTheStdoutDrain() {
        var buffer = OutputBuffer(maxSize: Self.spaciousCapBytes)
        buffer.appendStdout(Self.bytes("out-only\n"))
        buffer.appendStderr(Self.bytes("err-only\n"))

        #expect(buffer.extractCompletedStderrLines() == ["err-only"])
        #expect(buffer.extractCompletedStdoutLines() == ["out-only"])
    }

    @Test("The line drain gives nothing before the first newline arrives")
    func theLineDrainGivesNothingBeforeTheFirstNewlineArrives() {
        var buffer = OutputBuffer(maxSize: Self.spaciousCapBytes)
        buffer.appendStdout(Self.bytes("no newline at all"))

        #expect(buffer.extractCompletedStdoutLines() == [])
    }

    // MARK: - The cumulative count of the stored bytes

    @Test("storedByteCount is cumulative and a drain does not lower it")
    func storedByteCountIsCumulativeAndADrainDoesNotLowerIt() {
        var buffer = OutputBuffer(maxSize: Self.spaciousCapBytes)
        let input = Self.bytes("abc\n")
        buffer.appendStdout(input)
        buffer.extractCompletedStdoutLines()

        // The drain takes the bytes out of the buffer...
        #expect(buffer.currentSize == 0)
        // ...but the cumulative counter still holds them.
        #expect(buffer.storedByteCount == input.count)
    }

    @Test("The cap stays enforced across the drains")
    func theCapStaysEnforcedAcrossTheDrains() {
        // The drain of the first write lowers `currentSize` to 0. The cap
        // counts the cumulative bytes, thus a command that writes many lines
        // cannot make room again by a drain.
        var buffer = OutputBuffer(maxSize: Self.tightCapBytes)
        let first = Self.bytes("aaaaa\n")
        buffer.appendStdout(first)
        buffer.extractCompletedStdoutLines()
        #expect(buffer.currentSize == 0)

        let written = buffer.appendStdout(Self.bytes("bbbbbbbbbb\n"))
        #expect(written <= Self.tightCapBytes - first.count)
        #expect(buffer.truncated)
    }

    @Test("The binary flag stops the line drain of both streams")
    func theBinaryFlagStopsTheLineDrainOfBothStreams() {
        var buffer = OutputBuffer(maxSize: Self.spaciousCapBytes)
        let binaryInput: [UInt8] = [0x00] + Self.bytes("bin\n")
        buffer.appendStdout(binaryInput)
        #expect(buffer.binaryDetected)
        #expect(buffer.extractCompletedStdoutLines() == [])

        buffer.appendStderr(Self.bytes("more\n"))
        #expect(buffer.extractCompletedStderrLines() == [])
    }

    // MARK: - The seal at the end of the stream

    @Test("finish() writes the trailing line that holds no newline")
    func finishWritesTheTrailingLineThatHoldsNoNewline() {
        var buffer = OutputBuffer(maxSize: Self.spaciousCapBytes)
        buffer.appendStdout(Self.bytes("complete\nno-newline-yet"))
        #expect(buffer.extractCompletedStdoutLines() == ["complete"])

        let final = buffer.finish()
        #expect(final.stdout == ["no-newline-yet"])
        #expect(final.stderr == [])
    }

    @Test("finish() writes the truncation marker as a line of its own")
    func finishWritesTheTruncationMarkerAsALineOfItsOwn() {
        var buffer = OutputBuffer(maxSize: Self.twoLineCapBytes)
        buffer.appendStdout(Self.bytes(Self.threeLineText))
        buffer.extractCompletedStdoutLines()
        #expect(buffer.truncated)

        let final = buffer.finish()
        #expect(final.stdout.last == Self.truncationMarkerText)
    }

    @Test("finish() gives one placeholder line with the cumulative count")
    func finishGivesOnePlaceholderLineWithTheCumulativeCount() {
        var buffer = OutputBuffer(maxSize: Self.spaciousCapBytes)
        let stdoutInput: [UInt8] = [0x00] + Self.bytes("abc\n")
        let stderrInput = Self.bytes("more\n")
        buffer.appendStdout(stdoutInput)
        buffer.appendStderr(stderrInput)

        let final = buffer.finish()
        let placeholder = Self.binaryPlaceholder(byteCount: stdoutInput.count + stderrInput.count)
        #expect(final.stdout == [placeholder])
        #expect(final.stderr == [])
    }

    // MARK: - The raw bytes

    @Test("The raw view of a new buffer is empty and its state is clean")
    func theRawViewOfANewBufferIsEmptyAndItsStateIsClean() {
        // `let`, and not `var`: a read of the raw view does not change the
        // buffer. The test compares whole `RawOutput` values, thus it pins
        // each field at one time.
        let buffer = OutputBuffer(maxSize: Self.spaciousCapBytes)
        let clean = OutputBuffer.RawOutput(
            bytes: [], binaryDetected: false, truncated: false, storedByteCount: 0)

        #expect(buffer.rawStdout == clean)
        #expect(buffer.rawStderr == clean)
    }

    @Test("The raw view carries bytes that no UTF-8 decode accepts")
    func theRawViewCarriesBytesThatNoUTF8DecodeAccepts() {
        // `0xFF` is never a byte of UTF-8, and `0x80` continues a code point
        // that no byte started. The bytes hold no null byte, thus the capture
        // is still text for the binary scan, and the `String` view decodes
        // with replacement instead of the placeholder.
        var buffer = OutputBuffer(maxSize: Self.spaciousCapBytes)
        buffer.appendStdout(Self.undecodableGoldenInput)

        #expect(!buffer.binaryDetected)
        #expect(buffer.rawStdout.bytes == Self.undecodableGoldenInput)
        // The view the model reads does not change: one replacement character
        // for each byte that does not decode.
        #expect(buffer.stdout == Self.undecodableGoldenText)
        #expect(buffer.stdoutLines == ["a\u{FFFD}\u{FFFD}b"])
    }

    @Test("The raw view carries binary bytes that the String view hides")
    func theRawViewCarriesBinaryBytesThatTheStringViewHides() {
        let input: [UInt8] = [0x00, 0x01, 0x02, 0xFF] + Self.bytes("abc")
        var buffer = OutputBuffer(maxSize: Self.spaciousCapBytes)
        buffer.appendStdout(input)

        #expect(buffer.binaryDetected)
        #expect(buffer.rawStdout.bytes == input)
        // The safe rendering of the same capture does not change.
        #expect(buffer.stdout == Self.binaryPlaceholder(byteCount: input.count))
    }

    @Test("A read of the raw view does not drain it")
    func aReadOfTheRawViewDoesNotDrainIt() {
        var buffer = OutputBuffer(maxSize: Self.spaciousCapBytes)
        let input = Self.bytes("stays\n")
        buffer.appendStdout(input)

        #expect(buffer.rawStdout.bytes == input)
        #expect(buffer.rawStdout.bytes == input)
        #expect(buffer.currentSize == input.count)
    }

    @Test("The raw view carries the binary and truncation state with the bytes")
    func theRawViewCarriesTheBinaryAndTruncationStateWithTheBytes() {
        var buffer = OutputBuffer(maxSize: Self.twoLineCapBytes)
        let input: [UInt8] = [0x00] + Self.bytes(Self.threeLineText)
        buffer.appendStdout(input)

        // Pinned exactly, and not as a bound: the null byte in front moves the
        // safe cut to the `\n` after "line1". A bound would also hold if a
        // fault stored no byte at all.
        let expected: [UInt8] = [0x00] + Self.bytes("line1\n")
        let raw = buffer.rawStdout
        #expect(raw.binaryDetected)
        #expect(raw.truncated)
        #expect(raw.bytes == expected)
        #expect(raw.storedByteCount == expected.count)
    }

    @Test("Truncation can leave a subset with a hole, and not a first part")
    func truncationCanLeaveASubsetWithAHoleAndNotAFirstPart() {
        // The cap does not make a clean cut. `append` moves an over-cap write
        // back to a safe boundary, which can store fewer bytes than the cap
        // had room for. A later write then fits into the room that is left, on
        // the far side of the hole. Thus `truncated` says "no longer byte for
        // byte", and it does not say "what you have is the first part of what
        // the child wrote".
        var buffer = OutputBuffer(maxSize: Self.tightCapBytes)
        buffer.appendStdout(Self.bytes("abcdefghij\nk"))
        buffer.appendStdout(Self.bytes("\nZZZ"))

        let raw = buffer.rawStdout
        #expect(raw.truncated)
        #expect(raw.bytes == Self.bytes("abcdefghi\n"))
        // The child wrote "abcdefghij\nk" and then "\nZZZ". The stored bytes
        // pass over the `j`, thus they are not the first part of that.
        #expect(!Self.bytes("abcdefghij\nk\nZZZ").starts(with: raw.bytes))
    }

    @Test("The stderr raw view reports the shared state with no bytes of its own")
    func theStderrRawViewReportsTheSharedStateWithNoBytesOfItsOwn() {
        // The cap and the binary flag belong to the capture, and not to one
        // stream: stdout alone can fill the cap and set both flags, and the
        // raw view of stderr must report that honestly instead of looking
        // clean because it holds nothing.
        var buffer = OutputBuffer(maxSize: Self.codePointCapBytes)
        buffer.appendStdout([0x00] + Self.bytes("abcdefghij"))

        // The stdout write holds no `\n` inside the cap, thus the cut falls
        // back to the last start of a code point, which cuts at that byte and
        // drops it. Seven bytes are stored, and not the full eight of the cap.
        let expected: [UInt8] = [0x00] + Self.bytes("abcdef")
        let raw = buffer.rawStderr
        #expect(raw.bytes == [])
        #expect(raw.binaryDetected)
        #expect(raw.truncated)
        #expect(raw.storedByteCount == expected.count)
        #expect(buffer.rawStdout.bytes == expected)
    }

    // MARK: - The drain of the raw bytes

    @Test("The raw drain takes each resident byte, the partial line included")
    func theRawDrainTakesEachResidentByteThePartialLineIncluded() {
        var buffer = OutputBuffer(maxSize: Self.spaciousCapBytes)
        let input = Self.bytes("first\nno-newline-yet")
        buffer.appendStdout(input)

        // The line drain holds the partial line back until it completes. The
        // raw drain does not: a terminal shows a half-written line as it
        // arrives.
        #expect(buffer.extractRawStdout().bytes == input)
        #expect(buffer.extractRawStdout().bytes == [])
    }

    @Test("The raw drain continues after the binary flag")
    func theRawDrainContinuesAfterTheBinaryFlag() {
        var buffer = OutputBuffer(maxSize: Self.spaciousCapBytes)
        let input: [UInt8] = [0x00] + Self.bytes("bin\n")
        buffer.appendStdout(input)
        #expect(buffer.binaryDetected)

        // The line drain stops here. The raw path is what carries these bytes
        // onward, and the flag goes with them.
        let raw = buffer.extractRawStdout()
        #expect(raw.bytes == input)
        #expect(raw.binaryDetected)
    }

    @Test("The raw drain does not change storedByteCount and does not open the cap")
    func theRawDrainDoesNotChangeStoredByteCountAndDoesNotOpenTheCap() {
        var buffer = OutputBuffer(maxSize: Self.tightCapBytes)
        let first = Self.bytes("aaaaa\n")
        buffer.appendStdout(first)
        buffer.extractRawStdout()
        #expect(buffer.currentSize == 0)
        // The drain of the resident bytes must not make room under the cap.
        #expect(buffer.storedByteCount == first.count)

        // Exact, and not a bound: four bytes of room are left, and the safe
        // cut moves that back to three. Thus a fault that stored no byte could
        // not hide behind a bound.
        let roomLeft = Self.tightCapBytes - first.count
        let written = buffer.appendStdout(Self.bytes("bbbbbbbbbb\n"))
        #expect(written == roomLeft - 1)
        #expect(buffer.storedByteCount == first.count + written)
        #expect(buffer.truncated)
    }

    @Test("The raw drain and the line drain share one drain for each stream")
    func theRawDrainAndTheLineDrainShareOneDrainForEachStream() {
        var buffer = OutputBuffer(maxSize: Self.spaciousCapBytes)
        let input = Self.bytes("once\n")
        buffer.appendStdout(input)

        #expect(buffer.extractRawStdout().bytes == input)
        // The path that takes a byte is the only path that sees it.
        #expect(buffer.extractCompletedStdoutLines() == [])
    }

    @Test("finish() drops the raw bytes that no call drained")
    func finishDropsTheRawBytesThatNoCallDrained() {
        var buffer = OutputBuffer(maxSize: Self.spaciousCapBytes)
        buffer.appendStdout(Self.bytes("never-drained\n"))

        // `finish()` is the third drain of the same resident bytes, and it
        // destroys what it does not give back as lines. Thus the last raw
        // drain of a consumer must come BEFORE `finish()`, and not after it.
        #expect(buffer.finish().stdout == ["never-drained"])
        #expect(buffer.extractRawStdout().bytes == [])
    }

    @Test("The raw drain keeps stdout and stderr apart")
    func theRawDrainKeepsStdoutAndStderrApart() {
        var buffer = OutputBuffer(maxSize: Self.spaciousCapBytes)
        buffer.appendStdout(Self.bytes("out-1\n"))
        buffer.appendStderr(Self.bytes("err-1\n"))
        buffer.appendStdout(Self.bytes("out-2\n"))
        buffer.appendStderr(Self.bytes("err-2\n"))

        #expect(buffer.rawStdout.bytes == Self.bytes("out-1\nout-2\n"))
        #expect(buffer.rawStderr.bytes == Self.bytes("err-1\nerr-2\n"))

        // The drain of one stream does not touch the bytes of the other, thus
        // the bytes of one stream never reach the raw view of the other.
        #expect(buffer.extractRawStdout().bytes == Self.bytes("out-1\nout-2\n"))
        #expect(buffer.rawStdout.bytes == [])
        #expect(buffer.extractRawStderr().bytes == Self.bytes("err-1\nerr-2\n"))
    }

    // MARK: - The raw bytes of a real child process

    @Test("The bytes of a child process reach the raw view unchanged")
    func theBytesOfAChildProcessReachTheRawViewUnchanged() throws {
        let fixture = Self.everyByteValue(repeating: Self.smallFixtureRepeatCount)
        var buffer = OutputBuffer(maxSize: Self.childOutputCapBytes)
        for chunk in try catFixtureChunks(fixture) {
            buffer.appendStdout(chunk)
        }

        #expect(buffer.rawStdout.bytes == fixture)
        // The same capture still renders as the placeholder for the model.
        #expect(buffer.binaryDetected)
        #expect(buffer.stdout == Self.binaryPlaceholder(byteCount: fixture.count))
    }

    @Test("The raw drains join to the full output of the child")
    func theRawDrainsJoinToTheFullOutputOfTheChild() throws {
        let fixture = Self.everyByteValue(repeating: Self.largeFixtureRepeatCount)
        var buffer = OutputBuffer(maxSize: Self.childOutputCapBytes)
        let chunks = try catFixtureChunks(fixture)
        #expect(chunks.count > 1, "the fixture must be large enough for several reads")

        var streamed: [UInt8] = []
        for chunk in chunks {
            buffer.appendStdout(chunk)
            streamed += buffer.extractRawStdout().bytes
        }
        streamed += buffer.extractRawStdout().bytes
        #expect(streamed == fixture)
    }

    // MARK: - The golden of the String views

    /// One pinned case of the `String` and `[String]` views the model reads.
    /// Thus the raw path beside them cannot change what the model sees.
    private struct StringAccessorGolden {
        /// The name the report gives when the case fails.
        let name: String
        /// The byte cap of the buffer.
        let maxSize: Int
        /// The bytes the case writes to stdout.
        let stdoutInput: [UInt8]
        /// The bytes the case writes to stderr.
        let stderrInput: [UInt8]
        /// The expected `OutputBuffer.stdout`.
        let stdout: String
        /// The expected `OutputBuffer.stderr`.
        let stderr: String
        /// The expected `OutputBuffer.stdoutLines`.
        let stdoutLines: [String]
        /// The expected `OutputBuffer.stderrLines`.
        let stderrLines: [String]
        /// The expected answer of `OutputBuffer.finish()`.
        let finalLines: OutputBuffer.FinalLines
    }

    /// The pinned behavior of the `String` views, across each axis that
    /// decides it: plain text, CRLF, bytes that do not decode but are not
    /// binary, binary content, and truncation.
    private static let stringAccessorGoldens: [StringAccessorGolden] = [
        StringAccessorGolden(
            name: "plain text on both streams",
            maxSize: spaciousCapBytes,
            stdoutInput: bytes("alpha\nbeta\n"),
            stderrInput: bytes("warn\n"),
            stdout: "alpha\nbeta\n",
            stderr: "warn\n",
            stdoutLines: ["alpha", "beta"],
            stderrLines: ["warn"],
            finalLines: OutputBuffer.FinalLines(stdout: ["alpha", "beta"], stderr: ["warn"])
        ),
        StringAccessorGolden(
            name: "CRLF line endings",
            maxSize: spaciousCapBytes,
            stdoutInput: bytes("carriage\r\nplain\n"),
            stderrInput: [],
            stdout: "carriage\r\nplain\n",
            stderr: "",
            stdoutLines: ["carriage", "plain"],
            stderrLines: [],
            finalLines: OutputBuffer.FinalLines(stdout: ["carriage", "plain"])
        ),
        StringAccessorGolden(
            name: "bytes that do not decode, and no null byte",
            maxSize: spaciousCapBytes,
            stdoutInput: undecodableGoldenInput,
            stderrInput: [],
            stdout: undecodableGoldenText,
            stderr: "",
            stdoutLines: ["a\u{FFFD}\u{FFFD}b"],
            stderrLines: [],
            finalLines: OutputBuffer.FinalLines(stdout: ["a\u{FFFD}\u{FFFD}b"])
        ),
        StringAccessorGolden(
            name: "a null byte makes the capture one placeholder",
            maxSize: spaciousCapBytes,
            stdoutInput: binaryGoldenInput,
            stderrInput: [],
            stdout: binaryPlaceholder(byteCount: binaryGoldenInput.count),
            // An empty stderr still reports the placeholder through the
            // `String` view, and it gives no log line. That difference is
            // pinned on purpose.
            stderr: binaryPlaceholder(byteCount: binaryGoldenInput.count),
            stdoutLines: [binaryPlaceholder(byteCount: binaryGoldenInput.count)],
            stderrLines: [],
            finalLines: OutputBuffer.FinalLines(
                stdout: [binaryPlaceholder(byteCount: binaryGoldenInput.count)])
        ),
        StringAccessorGolden(
            name: "truncation cuts at a line boundary and adds its marker line",
            maxSize: twoLineCapBytes,
            stdoutInput: bytes(threeLineText),
            stderrInput: [],
            stdout: twoLineText,
            stderr: "",
            stdoutLines: twoLineTexts,
            stderrLines: [],
            finalLines: OutputBuffer.FinalLines(stdout: twoLineTexts + [truncationMarkerText])
        ),
    ]

    @Test("The String views agree with their golden output")
    func theStringViewsAgreeWithTheirGoldenOutput() {
        for golden in Self.stringAccessorGoldens {
            var buffer = OutputBuffer(maxSize: golden.maxSize)
            buffer.appendStdout(golden.stdoutInput)
            buffer.appendStderr(golden.stderrInput)

            #expect(buffer.stdout == golden.stdout, "\(golden.name): stdout")
            #expect(buffer.stderr == golden.stderr, "\(golden.name): stderr")
            #expect(buffer.stdoutLines == golden.stdoutLines, "\(golden.name): stdoutLines")
            #expect(buffer.stderrLines == golden.stderrLines, "\(golden.name): stderrLines")
            #expect(buffer.finish() == golden.finalLines, "\(golden.name): finish()")
        }
    }
}
