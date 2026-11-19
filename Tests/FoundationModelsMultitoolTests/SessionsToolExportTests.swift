// `SessionsToolExportTests` — the `export session` operation of the
// `sessions` tool (D202 (g)).
//
// Each case uses its own `InMemorySessionDirectory`, a fake exporter, and its
// own temporary folder as the working folder of the session. Each case reads
// the folder after the call, so it proves the write and not only the text of
// the answer. No case waits.

import Foundation
import FoundationModels
import FoundationModelsExtras
import Testing
import ULID

@testable import FoundationModelsMultitool

/// Behavioral tests for the `export session` operation of ``SessionsTool``.
@Suite("SessionsToolExportTests", .ownsTemporaryDirectories)
struct SessionsToolExportTests {

    // MARK: - Constants

    /// The shared fixtures of the `sessions` tool tests.
    private typealias Fixtures = SessionsToolFixtures

    /// The op string of the operation.
    private static let exportOp = "export session"

    /// The title of the caller session.
    private static let callerTitle = "Fix the API tests"

    /// The default file name of the caller session: its slug and `.md`.
    private static let callerFileName = "fix-the-api-tests.md"

    /// The title of the session that the reference cases name.
    private static let otherTitle = "Parser review"

    /// The Markdown that the fake exporter gives.
    private static let markdown = "# Fix the API tests\n\n## User\n\nRun the tests.\n"

    /// The number of lines of ``markdown``.
    private static let markdownLineCount = 5

    /// The text of a file that is in the folder before the call.
    private static let oldText = "old text"

    /// A file name that a case gives in `path`.
    private static let namedFile = "export.md"

    /// The name of the folder of the session in the cases that look at the
    /// folder above it.
    private static let sessionFolderName = "session"

    /// The words of the corrective of a call with no exporter.
    private static let noExporterWords = "Export as Markdown"

    /// The words of the corrective of a session that no one can see.
    private static let unknownSessionWords = "No session has the id"

    /// The text of the failure of the failing exporter.
    private static let failureText = "the history is gone"

    // MARK: - Helpers

    /// A new temporary folder for the session of one case.
    ///
    /// - Returns: The folder.
    private static func makeFolder() -> URL {
        TestSupport.makeTemporaryDirectory(named: "SessionsToolExportTests")
    }

    /// Calls one operation as the caller, with the title ``callerTitle`` and
    /// the working folder `folder`.
    ///
    /// - Parameters:
    ///   - fields: The fields of the operation.
    ///   - exporter: The exporter of the tool, or `nil` for none.
    ///   - folder: The working folder of the caller.
    ///   - directory: The directory of the tool.
    ///   - op: The op string. ``exportOp`` when not given.
    /// - Returns: The answer of the tool.
    /// - Throws: What the tool throws.
    private static func callAsCaller(
        _ fields: [(String, any ConvertibleToGeneratedContent)] = [],
        exporter: (any SessionTranscriptExporter)?,
        folder: URL,
        in directory: InMemorySessionDirectory = InMemorySessionDirectory(),
        op: String = exportOp
    ) async throws -> String {
        let tool = try SessionsTool(directory: directory, exporter: exporter)
        return try await Fixtures.asCaller(in: directory, title: callerTitle, folder: folder) { _ in
            try await tool.call(arguments: Fixtures.payload(op, fields))
        }
    }

    /// The text of the file `name` in `folder`, or `nil` when there is no
    /// such file.
    ///
    /// - Parameters:
    ///   - name: The relative path of the file.
    ///   - folder: The folder.
    /// - Returns: The text.
    private static func text(of name: String, in folder: URL) -> String? {
        try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
    }

    /// The names of the items in `folder`.
    ///
    /// - Parameter folder: The folder.
    /// - Returns: The names, sorted.
    private static func names(in folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }

    // MARK: - The default file

    @Test("export session with no id writes the slug file of the caller in its folder")
    func exportWithNoIDWritesTheSlugFile() async throws {
        let folder = Self.makeFolder()

        _ = try await Self.callAsCaller(exporter: RecordingTranscriptExporter(text: Self.markdown), folder: folder)

        #expect(Self.text(of: Self.callerFileName, in: folder) == Self.markdown)
    }

    @Test("export session with no id exports the caller session")
    func exportWithNoIDExportsTheCaller() async throws {
        let directory = InMemorySessionDirectory()
        let exporter = RecordingTranscriptExporter(text: Self.markdown)
        let tool = try SessionsTool(directory: directory, exporter: exporter)

        let callerID = try await Fixtures.asCaller(in: directory, title: Self.callerTitle, folder: Self.makeFolder()) {
            callerID in
            _ = try await tool.call(arguments: Fixtures.payload(Self.exportOp))
            return callerID
        }

        #expect(await exporter.requests.map(\.session) == [callerID])
    }

    @Test("the answer of export session gives the path of the file")
    func theAnswerGivesThePath() async throws {
        let folder = Self.makeFolder()

        let output = try await Self.callAsCaller(
            exporter: RecordingTranscriptExporter(text: Self.markdown), folder: folder)

        #expect(output.contains(folder.appendingPathComponent(Self.callerFileName).path), "output was: \(output)")
    }

    @Test("the answer of export session gives the number of lines")
    func theAnswerGivesTheNumberOfLines() async throws {
        let output = try await Self.callAsCaller(
            exporter: RecordingTranscriptExporter(text: Self.markdown), folder: Self.makeFolder())

        #expect(output.contains("\(Self.markdownLineCount) lines"), "output was: \(output)")
    }

    @Test("the answer of export session of an empty transcript gives 0 lines")
    func theAnswerOfAnEmptyTranscriptGivesNoLines() async throws {
        let output = try await Self.callAsCaller(exporter: RecordingTranscriptExporter(text: ""), folder: Self.makeFolder())

        #expect(output.contains(": 0 lines"), "output was: \(output)")
    }

    @Test("the answer of export session gives the title of the session")
    func theAnswerGivesTheTitle() async throws {
        let output = try await Self.callAsCaller(
            exporter: RecordingTranscriptExporter(text: Self.markdown), folder: Self.makeFolder())

        #expect(output.contains(Self.callerTitle), "output was: \(output)")
    }

    @Test("the answer of export session does not give the text of the transcript")
    func theAnswerDoesNotGiveTheText() async throws {
        let output = try await Self.callAsCaller(
            exporter: RecordingTranscriptExporter(text: Self.markdown), folder: Self.makeFolder())

        #expect(!output.contains(Self.markdown), "output was: \(output)")
    }

    // MARK: - The id

    @Test("export session with the id, @<short id> or @<slug> exports that session", arguments: SessionReferenceForm.allCases)
    func exportWithAReferenceExportsThatSession(_ form: SessionReferenceForm) async throws {
        let directory = InMemorySessionDirectory()
        let folder = Self.makeFolder()
        let other = Fixtures.summary(title: Self.otherTitle, folder: folder)
        directory.register(other)
        let exporter = RecordingTranscriptExporter(text: Self.markdown)

        _ = try await Self.callAsCaller(
            [("id", form.text(for: other))], exporter: exporter, folder: folder, in: directory)

        #expect(await exporter.requests.map(\.session) == [other.id])
    }

    @Test("export session of a session that the caller cannot see gives a corrective and exports nothing")
    func exportOfAnUnknownSessionIsACorrective() async throws {
        let folder = Self.makeFolder()
        let exporter = RecordingTranscriptExporter(text: Self.markdown)

        let output = try await Self.callAsCaller([("id", ULID().ulidString)], exporter: exporter, folder: folder)

        #expect(output.contains(Self.unknownSessionWords), "output was: \(output)")
        #expect(await exporter.requests.isEmpty)
    }

    // MARK: - replace

    @Test("export session over an existing file with no replace gives a corrective that names the path and replace")
    func exportOverAnExistingFileIsACorrective() async throws {
        let folder = Self.makeFolder()
        let file = folder.appendingPathComponent(Self.callerFileName)
        try Self.oldText.write(to: file, atomically: true, encoding: .utf8)

        let output = try await Self.callAsCaller(
            exporter: RecordingTranscriptExporter(text: Self.markdown), folder: folder)

        #expect(output.contains(file.path) && output.contains("replace"), "output was: \(output)")
    }

    @Test("export session over an existing file with no replace keeps the file")
    func exportOverAnExistingFileKeepsTheFile() async throws {
        let folder = Self.makeFolder()
        try Self.oldText.write(to: folder.appendingPathComponent(Self.callerFileName), atomically: true, encoding: .utf8)

        _ = try await Self.callAsCaller(exporter: RecordingTranscriptExporter(text: Self.markdown), folder: folder)

        #expect(Self.text(of: Self.callerFileName, in: folder) == Self.oldText)
    }

    @Test("export session with replace true replaces an existing file")
    func exportWithReplaceReplacesTheFile() async throws {
        let folder = Self.makeFolder()
        try Self.oldText.write(to: folder.appendingPathComponent(Self.callerFileName), atomically: true, encoding: .utf8)

        _ = try await Self.callAsCaller(
            [("replace", true)], exporter: RecordingTranscriptExporter(text: Self.markdown), folder: folder)

        #expect(Self.text(of: Self.callerFileName, in: folder) == Self.markdown)
    }

    // MARK: - path

    @Test("export session with a relative path writes that file in the session folder")
    func exportWithARelativePathWritesThatFile() async throws {
        let folder = Self.makeFolder()
        let path = "notes/\(Self.namedFile)"

        _ = try await Self.callAsCaller(
            [("path", path)], exporter: RecordingTranscriptExporter(text: Self.markdown), folder: folder)

        #expect(Self.text(of: path, in: folder) == Self.markdown)
    }

    @Test("export session with a path that goes up out of the session folder gives a corrective and writes nothing")
    func exportWithAPathOutOfTheFolderIsACorrective() async throws {
        let parent = Self.makeFolder()
        let folder = parent.appendingPathComponent(Self.sessionFolderName)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let output = try await Self.callAsCaller(
            [("path", "../\(Self.namedFile)")], exporter: RecordingTranscriptExporter(text: Self.markdown),
            folder: folder)

        #expect(output.contains("session folder"), "output was: \(output)")
        #expect(Self.names(in: parent) == [Self.sessionFolderName])
    }

    @Test("export session with an absolute path gives a corrective and writes nothing")
    func exportWithAnAbsolutePathIsACorrective() async throws {
        let folder = Self.makeFolder()
        let outside = Self.makeFolder().appendingPathComponent(Self.namedFile)

        let output = try await Self.callAsCaller(
            [("path", outside.path)], exporter: RecordingTranscriptExporter(text: Self.markdown), folder: folder)

        #expect(output.contains("session folder"), "output was: \(output)")
        #expect(!FileManager.default.fileExists(atPath: outside.path))
    }

    @Test("export session with a path that the folder cannot hold gives a corrective")
    func exportThatCannotWriteIsACorrective() async throws {
        let folder = Self.makeFolder()
        let blocker = "blocker"
        try Self.oldText.write(to: folder.appendingPathComponent(blocker), atomically: true, encoding: .utf8)

        let output = try await Self.callAsCaller(
            [("path", "\(blocker)/\(Self.namedFile)")], exporter: RecordingTranscriptExporter(text: Self.markdown),
            folder: folder)

        #expect(output.contains("could not write"), "output was: \(output)")
    }

    // MARK: - format

    @Test("export session with the format html gives a corrective that names markdown and writes nothing")
    func exportWithAnUnknownFormatIsACorrective() async throws {
        let folder = Self.makeFolder()

        let output = try await Self.callAsCaller(
            [("format", "html")], exporter: RecordingTranscriptExporter(text: Self.markdown), folder: folder)

        #expect(output.contains("markdown"), "output was: \(output)")
        #expect(Self.names(in: folder).isEmpty)
    }

    @Test("export session reads the format MARKDOWN in capitals")
    func exportReadsTheFormatInAnyCase() async throws {
        let folder = Self.makeFolder()

        _ = try await Self.callAsCaller(
            [("format", "MARKDOWN")], exporter: RecordingTranscriptExporter(text: Self.markdown), folder: folder)

        #expect(Self.text(of: Self.callerFileName, in: folder) == Self.markdown)
    }

    // MARK: - thoughts

    @Test("export session with thoughts true asks the exporter for the thoughts")
    func exportWithThoughtsAsksForTheThoughts() async throws {
        let exporter = RecordingTranscriptExporter(text: Self.markdown)

        _ = try await Self.callAsCaller([("thoughts", true)], exporter: exporter, folder: Self.makeFolder())

        #expect(await exporter.requests.map(\.includeThoughts) == [true])
    }

    @Test("export session with no thoughts asks the exporter for no thoughts")
    func exportWithNoThoughtsAsksForNoThoughts() async throws {
        let exporter = RecordingTranscriptExporter(text: Self.markdown)

        _ = try await Self.callAsCaller(exporter: exporter, folder: Self.makeFolder())

        #expect(await exporter.requests.map(\.includeThoughts) == [false])
    }

    // MARK: - The correctives of the server

    @Test("export session with no exporter gives a corrective that names the UI command, and writes nothing")
    func exportWithNoExporterIsACorrective() async throws {
        let folder = Self.makeFolder()

        let output = try await Self.callAsCaller(exporter: nil, folder: folder)

        #expect(output.contains(Self.noExporterWords), "output was: \(output)")
        #expect(Self.names(in: folder).isEmpty)
    }

    @Test("export session whose exporter fails gives a corrective with the error, and writes nothing")
    func exportWhoseExporterFailsIsACorrective() async throws {
        let folder = Self.makeFolder()
        let exporter = FailingTranscriptExporter(failure: TranscriptExportFailure(description: Self.failureText))

        let output = try await Self.callAsCaller(exporter: exporter, folder: folder)

        #expect(output.contains(Self.failureText), "output was: \(output)")
        #expect(Self.names(in: folder).isEmpty)
    }

    @Test("export session with no ToolContext gives a corrective")
    func exportWithNoCallerIsACorrective() async throws {
        let tool = try SessionsTool(
            directory: InMemorySessionDirectory(), exporter: RecordingTranscriptExporter(text: Self.markdown))

        let output = try await tool.call(arguments: Fixtures.payload(Self.exportOp))

        #expect(output.contains(Self.exportOp), "output was: \(output)")
    }

    // MARK: - Aliases

    @Test("save session with a file and overwrite writes the named file over an existing one")
    func theAliasesOfExportSessionWork() async throws {
        let folder = Self.makeFolder()
        try Self.oldText.write(to: folder.appendingPathComponent(Self.namedFile), atomically: true, encoding: .utf8)

        _ = try await Self.callAsCaller(
            [("file", Self.namedFile), ("overwrite", true)], exporter: RecordingTranscriptExporter(text: Self.markdown),
            folder: folder, op: "save session")

        #expect(Self.text(of: Self.namedFile, in: folder) == Self.markdown)
    }

    // MARK: - The endpoint

    @Test("endpoint(of:exporter:) keeps the exporter with the one endpoint of the directory")
    func theEndpointKeepsTheExporter() async throws {
        let directory = InMemorySessionDirectory()
        let exporter = RecordingTranscriptExporter(text: Self.markdown)
        let first = SessionsGraph.endpoint(of: directory, exporter: exporter)

        let later = SessionsGraph.endpoint(of: directory)

        #expect(later === first && (later.exporter as? RecordingTranscriptExporter) === exporter)
    }
}
