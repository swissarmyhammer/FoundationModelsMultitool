// `FilesReadTests` — the behavioral suite of the `tools.files.read` verb.
//
// A port of `../FoundationModelsFileTool/Tests/FileToolTests/
// ReadFileTests.swift`, adapted to the `Tool` call shape: the sibling
// decoded a `ReadFile` operation out of `GeneratedContent`; here the suite
// constructs `ReadArguments` with the memberwise initializer and calls the
// `Read` verb directly, the way `FilesGlobTests` calls its verb. The
// sibling's `ReadOutput` accessors do not port: the flat result carries a
// `correction` field, and the suite reads it directly.
//
// One test is not in the sibling: the outside-the-root correction, which
// the card's acceptance criteria name. It follows the pattern of
// `FilesGlobTests.pathOutsideTheSessionRootIsCorrective`.

import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Behavioral tests for the `tools.files.read` verb.
///
/// Every case of the sibling `read file` suite is here: offset / limit /
/// both windowing, each bound violation, absolute anchors under windowing,
/// the whole-file freshness token staying identical across windows, the
/// `plain` opt-out dropping anchors and per-line tags, binary rejection in
/// both formats, the empty file, unicode content, the missing-path
/// correction, and — from this card's acceptance criteria — the
/// outside-the-root correction.
@Suite struct FilesReadTests {
    // MARK: Test scaffolding

    /// The largest accepted `offset`, as the verb's bound and its corrective
    /// message name it.
    private static let maximumOffset = 1_000_000

    /// The largest accepted `limit`, as the verb's bound and its corrective
    /// message name it.
    private static let maximumLimit = 100_000

    /// Write `data` to a file named `name` inside a fresh temporary directory.
    ///
    /// - Parameters:
    ///   - data: the raw bytes to write.
    ///   - name: the file name to create in the temporary directory.
    /// - Returns: the session ``FileContext`` rooted at the temporary
    ///   directory and the absolute path of the written file.
    private static func makeContext(
        writing data: Data,
        named name: String = "sample.txt"
    ) throws -> (context: FileContext, path: String) {
        let root = TestSupport.makeTemporaryDirectory(named: "FilesReadTests")
        let fileURL = root.appendingPathComponent(name, isDirectory: false)
        try data.write(to: fileURL)
        return (FileContext(root: root), fileURL.path)
    }

    /// Write `text` (UTF-8) to a file named `name` inside a fresh temporary directory.
    ///
    /// - Parameters:
    ///   - text: the text content to write, encoded as UTF-8.
    ///   - name: the file name to create in the temporary directory.
    /// - Returns: the session ``FileContext`` rooted at the temporary
    ///   directory and the absolute path of the written file.
    private static func makeContext(
        writing text: String,
        named name: String = "sample.txt"
    ) throws -> (context: FileContext, path: String) {
        try makeContext(writing: Data(text.utf8), named: name)
    }

    /// Call the `tools.files.read` verb over a session context.
    ///
    /// - Parameters:
    ///   - path: the file path to read.
    ///   - context: the session context the verb reads against.
    ///   - offset: the optional 1-based start line.
    ///   - limit: the optional maximum line count.
    ///   - format: the optional output format name.
    /// - Returns: the verb's flat result.
    private static func read(
        path: String,
        in context: FileContext,
        offset: Int? = nil,
        limit: Int? = nil,
        format: String? = nil
    ) async throws -> ReadResult {
        try await Read(context: context)
            .call(arguments: ReadArguments(path: path, offset: offset, limit: limit, format: format))
    }

    // MARK: Whole-file read

    /// A whole-file read tags each line with an absolute `N:HH|` anchor and
    /// carries no window note.
    @Test func readsWholeFileWithHashlineAnchorsByDefault() async throws {
        let sourceLines = ["line one", "line two", "line three"]
        let (context, path) = try Self.makeContext(writing: sourceLines.joined(separator: "\n") + "\n")

        let result = try await Self.read(path: path, in: context)

        #expect(result.correction == nil)
        #expect(result.lines.count == sourceLines.count)
        #expect(result.note == nil)
        for (offset, line) in result.lines.enumerated() {
            #expect(line.hasPrefix("\(offset + 1):"), "expected absolute anchor, got \(line)")
            #expect(line.contains("|"), "expected an anchor delimiter, got \(line)")
        }
    }

    /// The result's hash is the whole-file freshness token over the full bytes.
    @Test func wholeFileHashMatchesHashlineToken() async throws {
        let text = "alpha\nbeta\ngamma\n"
        let (context, path) = try Self.makeContext(writing: text)

        let result = try await Self.read(path: path, in: context)

        #expect(result.correction == nil)
        #expect(result.hash == Hashline.wholeFileHash(bytes: Data(text.utf8)))
    }

    // MARK: Windowing

    /// An `offset` skips the leading lines and the note reports the window.
    @Test func offsetSkipsLeadingLines() async throws {
        let (context, path) = try Self.makeContext(writing: "one\ntwo\nthree\n")
        let windowStart = 2

        let result = try await Self.read(path: path, in: context, offset: windowStart)

        let expectedAnchors = ["2:", "3:"]
        #expect(result.lines.count == expectedAnchors.count)
        for (line, anchor) in zip(result.lines, expectedAnchors) {
            #expect(line.hasPrefix(anchor), "expected anchor \(anchor), got \(line)")
        }
        #expect(result.note == "showing lines 2\u{2013}3 of 3")
    }

    /// A `limit` truncates the trailing lines and the note reports the window.
    @Test func limitTruncatesTrailingLines() async throws {
        let (context, path) = try Self.makeContext(writing: "one\ntwo\nthree\n")
        let windowLength = 2

        let result = try await Self.read(path: path, in: context, limit: windowLength)

        let expectedAnchors = ["1:", "2:"]
        #expect(result.lines.count == expectedAnchors.count)
        for (line, anchor) in zip(result.lines, expectedAnchors) {
            #expect(line.hasPrefix(anchor), "expected anchor \(anchor), got \(line)")
        }
        #expect(result.note == "showing lines 1\u{2013}2 of 3")
    }

    /// `offset` and `limit` together select one window.
    @Test func offsetAndLimitSelectWindow() async throws {
        let (context, path) = try Self.makeContext(writing: "one\ntwo\nthree\nfour\n")
        let windowStart = 2

        let result = try await Self.read(path: path, in: context, offset: windowStart, limit: 1)

        #expect(result.lines.count == 1)
        let line = try #require(result.lines.first)
        #expect(line.hasPrefix("2:"))
        #expect(line.hasSuffix("|two"))
        #expect(result.note == "showing lines 2\u{2013}2 of 4")
    }

    /// A windowed read keeps the absolute line numbers of the full file.
    @Test func anchorsCarryAbsoluteLineNumbersUnderWindowing() async throws {
        let totalLines = 100
        let windowStart = 60
        let windowLength = 3
        let text = (1...totalLines).map { "line \($0)" }.joined(separator: "\n") + "\n"
        let (context, path) = try Self.makeContext(writing: text)

        let result = try await Self.read(path: path, in: context, offset: windowStart, limit: windowLength)

        let expectedNumbers = Array(windowStart..<(windowStart + windowLength))
        #expect(result.lines.count == expectedNumbers.count)
        for (line, number) in zip(result.lines, expectedNumbers) {
            #expect(line.hasPrefix("\(number):"), "expected absolute anchor \(number):, got \(line)")
        }
        #expect(result.lines.first?.hasSuffix("|line \(windowStart)") == true)
        #expect(result.note == "showing lines 60\u{2013}62 of 100")
    }

    /// The freshness token reflects the full file, not the window, so it is
    /// identical across windows of one file.
    @Test func wholeFileTokenIsIdenticalAcrossWindows() async throws {
        let rowCount = 20
        let windowStart = 5
        let windowLength = 4
        let text = (1...rowCount).map { "row \($0)" }.joined(separator: "\n") + "\n"
        let (context, path) = try Self.makeContext(writing: text)

        let whole = try await Self.read(path: path, in: context)
        let windowed = try await Self.read(path: path, in: context, offset: windowStart, limit: windowLength)

        #expect(whole.hash == windowed.hash)
        #expect(windowed.hash == Hashline.wholeFileHash(bytes: Data(text.utf8)))
    }

    // MARK: Plain opt-out

    /// The `plain` format returns raw text with no anchor and no per-line tag.
    @Test func plainFormatHasNoAnchorsOrPerLineTags() async throws {
        let (context, path) = try Self.makeContext(writing: "aaa\nbbb\nccc\n")
        let windowStart = 2

        let result = try await Self.read(path: path, in: context, offset: windowStart, limit: 1, format: "plain")

        #expect(result.lines == ["bbb"])
        #expect(result.note == "showing lines 2\u{2013}2 of 3")
    }

    /// A whole-file `plain` read returns each line verbatim.
    @Test func plainFormatReadsWholeFileVerbatim() async throws {
        let (context, path) = try Self.makeContext(writing: "first\nsecond\n")

        let result = try await Self.read(path: path, in: context, format: "plain")

        #expect(result.lines == ["first", "second"])
        #expect(result.note == nil)
    }

    // MARK: Bound violations

    /// An `offset` past the bound comes back as a correction naming the bound.
    @Test func offsetBeyondBoundIsCorrective() async throws {
        let (context, path) = try Self.makeContext(writing: "one\n")

        let result = try await Self.read(path: path, in: context, offset: Self.maximumOffset + 1)
        let message = try #require(result.correction)

        #expect(message.contains("\(Self.maximumOffset)"))
    }

    /// An `offset` of zero comes back as a correction naming the bound.
    @Test func offsetOfZeroIsCorrective() async throws {
        let (context, path) = try Self.makeContext(writing: "one\n")

        let result = try await Self.read(path: path, in: context, offset: 0)
        let message = try #require(result.correction)

        #expect(message.contains("\(Self.maximumOffset)"))
    }

    /// A `limit` of zero comes back as a correction naming the bound.
    @Test func limitOfZeroIsCorrective() async throws {
        let (context, path) = try Self.makeContext(writing: "one\n")

        let result = try await Self.read(path: path, in: context, limit: 0)
        let message = try #require(result.correction)

        #expect(message.contains("\(Self.maximumLimit)"))
    }

    /// A `limit` past the bound comes back as a correction naming the bound.
    @Test func limitBeyondBoundIsCorrective() async throws {
        let (context, path) = try Self.makeContext(writing: "one\n")

        let result = try await Self.read(path: path, in: context, limit: Self.maximumLimit + 1)
        let message = try #require(result.correction)

        #expect(message.contains("\(Self.maximumLimit)"))
    }

    /// An unknown `format` comes back as the correction that names the
    /// accepted values.
    @Test func unknownFormatIsCorrective() async throws {
        let (context, path) = try Self.makeContext(writing: "one\n")

        let result = try await Self.read(path: path, in: context, format: "xml")
        let message = try #require(result.correction)

        #expect(message == "The `format` parameter must be one of: hashline, plain.")
    }

    /// The `format` name resolves without regard to case.
    @Test func formatResolvesCaseInsensitively() async throws {
        let (context, path) = try Self.makeContext(writing: "aaa\nbbb\n")

        let result = try await Self.read(path: path, in: context, format: "Plain")

        #expect(result.lines == ["aaa", "bbb"])
    }

    // MARK: Binary rejection

    /// Bytes that are never valid UTF-8, so decoding must fail.
    private static let binaryBytes = Data([0xFF, 0xFE, 0x00, 0x01, 0xFF, 0x80])

    /// A binary (non-UTF-8) file is rejected with a correction in each
    /// format, and no content is decoded.
    @Test(arguments: [nil, "plain"] as [String?])
    func binaryFileIsRejected(format: String?) async throws {
        let (context, path) = try Self.makeContext(writing: Self.binaryBytes, named: "blob.bin")

        let result = try await Self.read(path: path, in: context, format: format)
        let message = try #require(result.correction)

        #expect(
            message
                == "The file is not valid UTF-8 text and appears to be binary, so it cannot be read as text: \(path)")
        #expect(result.lines.isEmpty, "binary content must never be decoded into a result")
        #expect(result.hash.isEmpty, "binary content must never carry a freshness token")
    }

    // MARK: Empty and unicode content

    /// An empty file reads as no lines, no note, and the empty-bytes token.
    @Test func emptyFileReadsAsNoLines() async throws {
        let (context, path) = try Self.makeContext(writing: "")

        let result = try await Self.read(path: path, in: context)

        #expect(result.correction == nil)
        #expect(result.lines.isEmpty)
        #expect(result.note == nil)
        #expect(result.hash == Hashline.wholeFileHash(bytes: Data()))
    }

    /// Unicode content survives the read byte for byte.
    @Test func unicodeContentIsPreserved() async throws {
        let text = "h\u{00E9}llo \u{1F30D}\n\u{0441}\u{0432}\u{0456}\u{0442}\n"
        let (context, path) = try Self.makeContext(writing: text)

        let result = try await Self.read(path: path, in: context)

        let expectedSuffixes = ["|h\u{00E9}llo \u{1F30D}", "|\u{0441}\u{0432}\u{0456}\u{0442}"]
        #expect(result.lines.count == expectedSuffixes.count)
        for (line, suffix) in zip(result.lines, expectedSuffixes) {
            #expect(line.hasSuffix(suffix), "expected suffix \(suffix), got \(line)")
        }
        #expect(result.hash == Hashline.wholeFileHash(bytes: Data(text.utf8)))
    }

    // MARK: Line-ending fidelity

    /// A read over content mixing every terminator (`\r\n`, `\r`, `\n`) plus
    /// an unterminated final line must tag contiguous absolute anchors line
    /// for line, guarding that the verb's physical-line split stays in
    /// lockstep with ``Hashline``'s line model across all terminator kinds.
    @Test func mixedLineEndingsTagContiguousAbsoluteAnchors() async throws {
        let (context, path) = try Self.makeContext(writing: "a\r\nb\rc\nd")

        let result = try await Self.read(path: path, in: context)

        let expectedSuffixes = ["|a", "|b", "|c", "|d"]
        #expect(result.lines.count == expectedSuffixes.count)
        for (offset, line) in result.lines.enumerated() {
            #expect(line.hasPrefix("\(offset + 1):"), "expected contiguous absolute anchor, got \(line)")
        }
        for (line, suffix) in zip(result.lines, expectedSuffixes) {
            #expect(line.hasSuffix(suffix), "expected suffix \(suffix), got \(line)")
        }
        #expect(result.note == nil)
    }

    // MARK: Corrective paths

    /// A path that names no file comes back as a correction, not as a
    /// thrown error.
    @Test func missingPathIsCorrective() async throws {
        let root = TestSupport.makeTemporaryDirectory(named: "FilesReadTests")
        let missing = root.appendingPathComponent("does-not-exist.txt", isDirectory: false)
        let context = FileContext(root: root)

        let result = try await Self.read(path: missing.path, in: context)
        let message = try #require(result.correction)

        #expect(!message.isEmpty)
    }

    /// A path outside the session root comes back as a correction: the read
    /// stays bounded through the session's path guard.
    @Test func pathOutsideTheRootIsCorrective() async throws {
        let root = TestSupport.makeTemporaryDirectory(named: "FilesReadTests")
        let (_, outsidePath) = try Self.makeContext(writing: "secret\n")
        let context = FileContext(root: root)

        let result = try await Self.read(path: outsidePath, in: context)
        let message = try #require(result.correction)

        #expect(!message.isEmpty)
        #expect(result.lines.isEmpty)
    }
}
