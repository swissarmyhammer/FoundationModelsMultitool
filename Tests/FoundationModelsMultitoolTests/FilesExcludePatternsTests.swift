// `FilesExcludePatternsTests` — the host exclude patterns of the files
// capability, seen through the verbs.
//
// The source request: an agent keeps its transcripts under `.acp-agent/` in
// its working folder, and `tools.files.grep` found its own earlier tool
// outputs there. The host gives the exclude patterns when it composes the
// capability, and each search verb then skips the paths they match. A read
// of an explicit path does not change. `ExcludePatternsTests` holds the
// gitignore rules of the matcher one at a time; this suite holds the walks.

import Foundation
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Behavioral tests for the host exclude patterns of the files capability.
@Suite struct FilesExcludePatternsTests {
    // MARK: Test scaffolding

    /// The pattern the ACP agent gives for its own folder.
    private static let agentFolderPatterns = [".acp-agent/"]

    /// The transcript file under the agent folder, relative to the root.
    private static let transcriptPath = ".acp-agent/transcripts/x.jsonl"

    /// The file outside the agent folder, relative to the root.
    private static let notesPath = "notes.jsonl"

    /// The text each fixture file holds, thus each one matches the grep.
    private static let needle = "needle"

    /// The glob pattern that matches both fixture files.
    private static let jsonLinesPattern = "*.jsonl"

    /// The grep output mode that answers the matching files only.
    private static let filesWithMatchesMode = "filesWithMatches"

    /// Create a fresh temporary directory for one test.
    ///
    /// - Returns: the URL of a fresh, canonical temporary directory.
    private static func makeDirectory() -> URL {
        TestSupport.canonicalDirectory(TestSupport.makeTemporaryDirectory(named: "FilesExcludePatternsTests"))
    }

    /// Write a UTF-8 text file, and create each intermediate directory.
    ///
    /// - Parameters:
    ///   - name: the file name; a `/` in it creates nested directories.
    ///   - directory: the directory to create the file under.
    ///   - contents: the UTF-8 text content to write.
    /// - Returns: the URL of the written file.
    @discardableResult
    private static func write(_ name: String, in directory: URL, contents: String = needle) throws -> URL {
        let url = directory.appendingPathComponent(name, isDirectory: false)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
        return url
    }

    /// Make a root that holds the transcript and the notes file.
    ///
    /// - Returns: the root.
    private static func makeAgentTree() throws -> URL {
        let root = makeDirectory()
        try write(transcriptPath, in: root)
        try write(notesPath, in: root)
        return root
    }

    /// Make a session context with exclude patterns.
    ///
    /// - Parameters:
    ///   - root: the session root.
    ///   - excludePatterns: the host exclude patterns.
    /// - Returns: the context.
    private static func makeContext(root: URL, excludePatterns: [String]) -> FileContext {
        FileContext(root: root, excludePatterns: excludePatterns)
    }

    /// Run the glob verb for the JSON Lines files of a root.
    ///
    /// - Parameters:
    ///   - root: the session root.
    ///   - excludePatterns: the host exclude patterns.
    ///   - respectGitIgnore: the argument the model gives, or `nil`.
    /// - Returns: the matching files, as a set.
    private static func globbedFiles(
        root: URL, excludePatterns: [String], respectGitIgnore: Bool? = nil
    ) async throws -> Set<String> {
        let result = try await Glob(context: makeContext(root: root, excludePatterns: excludePatterns))
            .call(arguments: GlobArguments(pattern: jsonLinesPattern, respectGitIgnore: respectGitIgnore))
        #expect(result.correction == nil)
        return Set(result.files)
    }

    /// Run the grep verb for the needle.
    ///
    /// - Parameters:
    ///   - root: the session root.
    ///   - excludePatterns: the host exclude patterns.
    ///   - path: the path the model gives, or `nil` for the root.
    /// - Returns: the files with a match, as a set.
    private static func greppedFiles(
        root: URL, excludePatterns: [String], path: String? = nil
    ) async throws -> Set<String> {
        let result = try await Grep(context: makeContext(root: root, excludePatterns: excludePatterns))
            .call(arguments: GrepArguments(pattern: needle, path: path, outputMode: filesWithMatchesMode))
        #expect(result.correction == nil)
        return Set(try #require(result.files))
    }

    // MARK: Glob

    /// The glob skips the excluded folder and still finds the other file.
    @Test func globSkipsTheExcludedFolder() async throws {
        let root = try Self.makeAgentTree()
        let files = try await Self.globbedFiles(root: root, excludePatterns: Self.agentFolderPatterns)
        #expect(files == [Self.notesPath])
    }

    /// `respectGitIgnore: false` does not turn the host patterns off.
    @Test func globSkipsTheExcludedFolderWhenRespectGitIgnoreIsFalse() async throws {
        let root = try Self.makeAgentTree()
        try TestSupport.runGit(["init", "--quiet"], in: root)
        let files = try await Self.globbedFiles(
            root: root, excludePatterns: Self.agentFolderPatterns, respectGitIgnore: false)
        #expect(files == [Self.notesPath])
    }

    /// With no exclude patterns the glob finds both files, as before.
    @Test func globWithNoPatternsFindsEachFile() async throws {
        let root = try Self.makeAgentTree()
        let files = try await Self.globbedFiles(root: root, excludePatterns: [])
        #expect(files == [Self.transcriptPath, Self.notesPath])
    }

    /// A negated pattern puts a file back into the glob.
    @Test func globHonorsANegatedPattern() async throws {
        let root = Self.makeDirectory()
        try Self.write("a.jsonl", in: root)
        try Self.write("keep.jsonl", in: root)
        let files = try await Self.globbedFiles(root: root, excludePatterns: [Self.jsonLinesPattern, "!keep.jsonl"])
        #expect(files == ["keep.jsonl"])
    }

    // MARK: Grep

    /// The grep skips the excluded folder and still finds the other file.
    /// There is no repository, thus the walk is the plain walk — the walk
    /// that `respectGitIgnore: false` also takes.
    @Test func grepSkipsTheExcludedFolder() async throws {
        let root = try Self.makeAgentTree()
        let files = try await Self.greppedFiles(root: root, excludePatterns: Self.agentFolderPatterns)
        #expect(files == [Self.notesPath])
    }

    /// In a repository the grep skips the excluded folder also when git
    /// tracks the file, which `git ls-files --exclude` cannot do.
    @Test func grepSkipsATrackedFileInTheExcludedFolder() async throws {
        let root = try Self.makeAgentTree()
        try TestSupport.runGit(["init", "--quiet"], in: root)
        try TestSupport.runGit(["add", "."], in: root)
        let files = try await Self.greppedFiles(root: root, excludePatterns: Self.agentFolderPatterns)
        #expect(files == [Self.notesPath])
    }

    /// With no exclude patterns the grep finds both files, as before.
    @Test func grepWithNoPatternsFindsEachFile() async throws {
        let root = try Self.makeAgentTree()
        let files = try await Self.greppedFiles(root: root, excludePatterns: [])
        #expect(files == [Self.transcriptPath, Self.notesPath])
    }

    /// A grep with a `path` that names one excluded file searches that file,
    /// the same as for a gitignored file: an explicit path does not change.
    @Test func grepOfAnExplicitExcludedFileSearchesIt() async throws {
        let root = try Self.makeAgentTree()
        let files = try await Self.greppedFiles(
            root: root, excludePatterns: Self.agentFolderPatterns, path: Self.transcriptPath)
        #expect(files == [Self.transcriptPath])
    }

    // MARK: Read

    /// A read of an excluded file by its explicit path still works.
    @Test func readOfAnExplicitExcludedFileWorks() async throws {
        let root = try Self.makeAgentTree()
        let result = try await Read(context: Self.makeContext(root: root, excludePatterns: Self.agentFolderPatterns))
            .call(arguments: ReadArguments(path: Self.transcriptPath, offset: nil, limit: nil, format: "plain"))
        #expect(result.correction == nil)
        #expect(result.lines == [Self.needle])
    }

    // MARK: The shared walk

    /// The shared walk skips the excluded folder with `respectGitIgnore`
    /// false, thus each search verb that walks keeps the host patterns on.
    @Test func walkSkipsTheExcludedFolderWhenRespectGitIgnoreIsFalse() throws {
        let root = try Self.makeAgentTree()
        let walked = FileWalker.walkAndFilter(
            walkRoot: root,
            sessionRoot: root,
            respectGitIgnore: false,
            excludePatterns: ExcludePatterns(Self.agentFolderPatterns),
            accept: { _, _ in true },
            build: { _, sessionRelativePath in sessionRelativePath }
        )
        #expect(walked == [Self.notesPath])
    }

    /// The patterns match the path relative to the session root, also when
    /// the walk starts in a subfolder.
    @Test func walkMatchesThePathRelativeToTheSessionRoot() throws {
        let root = try Self.makeAgentTree()
        let walked = FileWalker.walkAndFilter(
            walkRoot: root.appendingPathComponent(".acp-agent", isDirectory: true),
            sessionRoot: root,
            respectGitIgnore: true,
            excludePatterns: ExcludePatterns(["/.acp-agent/transcripts/"]),
            accept: { _, _ in true },
            build: { _, sessionRelativePath in sessionRelativePath }
        )
        #expect(walked.isEmpty)
    }

    // MARK: Composition

    /// The capability initializer gives the patterns to its verbs.
    @Test func capabilityGivesThePatternsToItsVerbs() async throws {
        let root = try Self.makeAgentTree()
        let capability = FilesCapability(root: root, excludePatterns: Self.agentFolderPatterns)
        let glob = try #require(capability.tools.compactMap { $0 as? Glob }.first)
        let result = try await glob.call(arguments: GlobArguments(pattern: Self.jsonLinesPattern))
        #expect(result.files == [Self.notesPath])
    }

    /// `withFiles(excludePatterns:)` gives the patterns to the verbs a
    /// snippet calls.
    @Test func builderGivesThePatternsToTheSnippetVerbs() async throws {
        let root = try Self.makeAgentTree()
        let registry = try MultiTool.Builder()
            .withFiles(root: root, excludePatterns: Self.agentFolderPatterns)
            .buildRegistry()
        let output = try await MultiTool(registry: registry).call(
            arguments: RunCodeArguments(
                code: """
                    const grep = await tools.files.grep({ pattern: "\(Self.needle)", outputMode: "\(Self.filesWithMatchesMode)" });
                    if (grep.correction) { return grep.correction; }
                    return grep.files;
                    """))
        #expect(try RunOutput.decoded([String].self, from: output) == [Self.notesPath])
    }
}
