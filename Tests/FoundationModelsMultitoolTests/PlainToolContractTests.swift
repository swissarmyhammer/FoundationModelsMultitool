// `PlainToolContractTests` — the plain-`Tool` contract of the six files verbs.
//
// Each files verb (`Read`, `Write`, `Edit`, `Patch`, `Glob`, `Grep`) takes a
// `FileContext` at construction and reads no `ToolContext.current`. Thus the
// verbs work on a bare `LanguageModelSession` that mounts no Router. Before
// this suite, no test held that fact: a later change that read the ambient
// context in a files verb would have broken a bare-session host in silence.
//
// The suite constructs each verb through `FilesCapability(root:)`, the way a
// host does, and calls `call(arguments:)` directly. No `ToolContext` is bound
// in the test task, thus the verb answers with the context it was given and
// with nothing else. The gated `FilesBareSessionTests` in `IntegrationTests/`
// drives the same contract through a real model.

import Foundation
import FoundationModels
import Testing

@testable import FoundationModelsMultitool

/// Pins the plain-`Tool` contract of the six files verbs.
///
/// Two kinds of case hold it. The behavioral cases call each verb with no
/// bound `ToolContext`: a read answers content, a write creates the file, an
/// edit rewrites it, a patch adds a file, a glob and a grep find the seeded
/// file, and a path outside the root answers the corrective text in band
/// rather than throwing. The reflective case reads the source of the Files
/// capability and fails when any file in it spells `ToolContext.current`;
/// that is the cheap guard, and it fails before a verb is called.
@Suite struct PlainToolContractTests {
    // MARK: Test scaffolding

    /// The directory the reflective case scans, from the repository root.
    private static let filesCapabilityDirectory = "Sources/FoundationModelsMultitool/Capabilities/Files"

    /// The expression that reads the ambient context, which no files verb
    /// may spell.
    private static let ambientContextRead = "ToolContext.current"

    /// The name of the file each behavioral case seeds.
    private static let seededFileName = "seed.txt"

    /// The name of the file the patch case adds.
    private static let addedFileName = "added.txt"

    /// The word the seeded file holds, which a read, a grep, and an edit
    /// find.
    private static let seededWord = "seeded"

    /// The word the edit case writes in place of ``seededWord``.
    private static let editedWord = "edited"

    /// The text the seeded file holds.
    private static let seededText = "\(seededWord) line\n"

    /// The text the patch case adds.
    private static let addedText = "added"

    /// The fragment the path guard's outside-the-root correction carries.
    private static let outsideRootFragment = "outside workspace boundaries"

    /// The glob pattern that matches the seeded file.
    private static let textFilePattern = "*.txt"

    /// Create a fresh temporary directory for one test.
    ///
    /// - Returns: the URL of a fresh temporary directory this suite owns.
    private static func makeRoot() -> URL {
        TestSupport.makeTemporaryDirectory(named: "PlainToolContractTests")
    }

    /// Write the seeded file into a directory.
    ///
    /// - Parameter directory: the directory to seed.
    /// - Returns: the absolute path of the seeded file.
    /// - Throws: an error when the file cannot be written.
    private static func seed(in directory: URL) throws -> String {
        let path = TestSupport.path(seededFileName, in: directory)
        try Data(seededText.utf8).write(to: URL(fileURLWithPath: path))
        return path
    }

    /// Find one verb in the tools of a files capability rooted at a
    /// directory.
    ///
    /// The capability is the host's construction path, thus the verb under
    /// test is the verb a host mounts, and not one the suite builds by hand.
    ///
    /// - Parameters:
    ///   - type: the concrete verb type to find.
    ///   - root: the session working directory.
    /// - Returns: the verb of that type.
    /// - Throws: a failed requirement when the capability holds no such verb.
    private static func verb<Verb: Tool>(of type: Verb.Type, in root: URL) throws -> Verb {
        try #require(FilesCapability(root: root).tools.compactMap { $0 as? Verb }.first)
    }

    /// Require that a result carries the outside-the-root correction.
    ///
    /// - Parameter correction: the result's `correction` field.
    /// - Throws: a failed requirement when the correction is absent.
    private static func expectOutsideRoot(correction: String?) throws {
        let message = try #require(correction)
        #expect(message.contains(outsideRootFragment), "expected the outside-the-root correction, got \(message)")
    }

    // MARK: Read

    /// A read with no bound context answers the seeded content.
    @Test func readAnswersContentWithNoContextBound() async throws {
        let root = Self.makeRoot()
        let path = try Self.seed(in: root)

        let result = try await Self.verb(of: Read.self, in: root)
            .call(arguments: ReadArguments(path: path, offset: nil, limit: nil, format: nil))

        #expect(result.correction == nil)
        #expect(result.lines.contains { $0.contains(Self.seededWord) })
    }

    /// A read of a path outside the root answers the correction in band.
    @Test func readOutsideTheRootIsCorrective() async throws {
        let root = Self.makeRoot()
        let outsidePath = try Self.seed(in: Self.makeRoot())

        let result = try await Self.verb(of: Read.self, in: root)
            .call(arguments: ReadArguments(path: outsidePath, offset: nil, limit: nil, format: nil))

        try Self.expectOutsideRoot(correction: result.correction)
    }

    // MARK: Write

    /// A write with no bound context creates the file.
    @Test func writeCreatesTheFileWithNoContextBound() async throws {
        let root = Self.makeRoot()
        let path = TestSupport.path(Self.seededFileName, in: root)

        let result = try await Self.verb(of: Write.self, in: root)
            .call(arguments: WriteArguments(path: path, content: Self.seededText))

        #expect(result.correction == nil)
        #expect(result.bytesWritten == Self.seededText.utf8.count)
        #expect(TestSupport.text(at: path) == Self.seededText)
    }

    /// A write to a path outside the root answers the correction in band and
    /// writes nothing.
    @Test func writeOutsideTheRootIsCorrective() async throws {
        let root = Self.makeRoot()
        let outsidePath = TestSupport.path(Self.seededFileName, in: Self.makeRoot())

        let result = try await Self.verb(of: Write.self, in: root)
            .call(arguments: WriteArguments(path: outsidePath, content: Self.seededText))

        try Self.expectOutsideRoot(correction: result.correction)
        #expect(TestSupport.text(at: outsidePath) == nil)
    }

    // MARK: Edit

    /// An edit with no bound context rewrites the seeded file.
    @Test func editRewritesTheFileWithNoContextBound() async throws {
        let root = Self.makeRoot()
        let path = try Self.seed(in: root)

        let result = try await Self.verb(of: Edit.self, in: root)
            .call(
                arguments: EditArguments(
                    path: path, find: [Self.seededWord], replace: [Self.editedWord], replacesAll: nil,
                    occurrence: nil))

        #expect(result.correction == nil)
        #expect(result.status == EditOutcomeProjection.appliedStatus)
        #expect(TestSupport.text(at: path)?.contains(Self.editedWord) == true)
    }

    /// An edit of a path outside the root answers the correction in band and
    /// leaves the file byte-identical.
    @Test func editOutsideTheRootIsCorrective() async throws {
        let root = Self.makeRoot()
        let outsidePath = try Self.seed(in: Self.makeRoot())

        let result = try await Self.verb(of: Edit.self, in: root)
            .call(
                arguments: EditArguments(
                    path: outsidePath, find: [Self.seededWord], replace: [Self.editedWord], replacesAll: nil,
                    occurrence: nil))

        try Self.expectOutsideRoot(correction: result.correction)
        #expect(TestSupport.text(at: outsidePath) == Self.seededText)
    }

    // MARK: Patch

    /// A patch with no bound context adds the file.
    @Test func patchAddsTheFileWithNoContextBound() async throws {
        let root = Self.makeRoot()
        let path = TestSupport.path(Self.addedFileName, in: root)

        let result = try await Self.verb(of: Patch.self, in: root)
            .call(arguments: PatchArguments(patch: Self.addFileEnvelope(path: path)))

        #expect(result.correction == nil)
        #expect(result.status == EditOutcomeProjection.appliedStatus)
        #expect(TestSupport.text(at: path)?.contains(Self.addedText) == true)
    }

    /// A patch that adds a file outside the root answers the correction in
    /// band and writes nothing.
    @Test func patchOutsideTheRootIsCorrective() async throws {
        let root = Self.makeRoot()
        let outsidePath = TestSupport.path(Self.addedFileName, in: Self.makeRoot())

        let result = try await Self.verb(of: Patch.self, in: root)
            .call(arguments: PatchArguments(patch: Self.addFileEnvelope(path: outsidePath)))

        try Self.expectOutsideRoot(correction: result.correction)
        #expect(TestSupport.text(at: outsidePath) == nil)
    }

    /// The envelope that adds one file holding ``addedText``.
    ///
    /// - Parameter path: the absolute path of the file to add.
    /// - Returns: the complete `*** Begin Patch` … `*** End Patch` envelope.
    private static func addFileEnvelope(path: String) -> String {
        "*** Begin Patch\n*** Add File: \(path)\n+\(addedText)\n*** End Patch\n"
    }

    // MARK: Glob

    /// A glob with no bound context finds the seeded file.
    @Test func globFindsTheFileWithNoContextBound() async throws {
        let root = Self.makeRoot()
        _ = try Self.seed(in: root)

        let result = try await Self.verb(of: Glob.self, in: root)
            .call(
                arguments: GlobArguments(
                    pattern: Self.textFilePattern, path: root.path, caseSensitive: nil, respectGitIgnore: nil))

        #expect(result.correction == nil)
        #expect(result.files == [Self.seededFileName])
    }

    /// A glob of a directory outside the root answers the correction in
    /// band.
    @Test func globOutsideTheRootIsCorrective() async throws {
        let root = Self.makeRoot()
        let outside = Self.makeRoot()
        _ = try Self.seed(in: outside)

        let result = try await Self.verb(of: Glob.self, in: root)
            .call(
                arguments: GlobArguments(
                    pattern: Self.textFilePattern, path: outside.path, caseSensitive: nil,
                    respectGitIgnore: nil))

        try Self.expectOutsideRoot(correction: result.correction)
    }

    // MARK: Grep

    /// A grep with no bound context finds the seeded line.
    @Test func grepFindsTheLineWithNoContextBound() async throws {
        let root = Self.makeRoot()
        _ = try Self.seed(in: root)

        let result = try await Self.verb(of: Grep.self, in: root)
            .call(arguments: Self.grepArguments(path: root.path))

        #expect(result.correction == nil)
        #expect(result.matchCount == 1)
        #expect(result.matches?.first?.file == Self.seededFileName)
    }

    /// A grep of a directory outside the root answers the correction in
    /// band.
    @Test func grepOutsideTheRootIsCorrective() async throws {
        let root = Self.makeRoot()
        let outside = Self.makeRoot()
        _ = try Self.seed(in: outside)

        let result = try await Self.verb(of: Grep.self, in: root)
            .call(arguments: Self.grepArguments(path: outside.path))

        try Self.expectOutsideRoot(correction: result.correction)
    }

    /// The grep arguments that search a directory for ``seededWord`` with
    /// every other parameter at its default.
    ///
    /// - Parameter path: the directory to search.
    /// - Returns: the verb's arguments.
    private static func grepArguments(path: String) -> GrepArguments {
        GrepArguments(
            pattern: seededWord, path: path, glob: nil, type: nil, caseInsensitive: nil, contextLines: nil,
            outputMode: nil)
    }

    // MARK: The reflective guard

    /// No source file of the Files capability reads the ambient context.
    ///
    /// The behavioral cases above prove the contract for the arguments they
    /// pass. This case proves it for every path of every verb at once: a verb
    /// that spelled `ToolContext.current` anywhere would fail here, before a
    /// bare-session host found the change. The folder is read through
    /// `#filePath`, the way the golden tests read their fixtures, thus the
    /// scan reads the checkout under test and no other.
    @Test func filesVerbsReadNoAmbientContext() throws {
        let sightings = try RepositoryFile.sightings(
            of: [Self.ambientContextRead], inRelativeDirectory: Self.filesCapabilityDirectory)

        #expect(
            sightings.isEmpty,
            """
            A files verb reads the ambient context. Each verb must answer from \
            the `FileContext` it holds, so that a bare `LanguageModelSession` \
            with no Router can mount it. Each line below must go:
            \(sightings.joined(separator: "\n"))
            """)
    }
}
