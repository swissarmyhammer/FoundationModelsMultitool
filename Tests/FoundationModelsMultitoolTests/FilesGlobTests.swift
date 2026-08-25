// `FilesGlobTests` — the behavioral suite of the `tools.files.glob` verb.
//
// A port of `../FoundationModelsFileTool/Tests/FileToolTests/
// GlobFilesTests.swift`, adapted to the `Tool` call shape: the sibling
// decoded a `GlobFiles` operation out of `GeneratedContent`; here the suite
// constructs `GlobArguments` with the memberwise initializer and calls the
// `Glob` verb directly, the way the Shell suites call their verbs. The cap
// seam stays an engine-level test, as in the sibling, because the verb
// makes its engine with the default cap.

import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Behavioral tests for the ``GlobEngine`` and the `tools.files.glob` verb.
///
/// Every case of the sibling `glob files` suite is here: the git-aware walk
/// that hides a gitignored file by default and shows it when
/// `respectGitIgnore` is off, the non-repository `FileManager` fallback
/// walk, the full broad-pattern matrix (each broad pattern rejected
/// unscoped and permitted when a `path` scopes the walk), case sensitivity
/// in both directions, strict mtime-descending order with explicitly set
/// file dates, the honest `capped` flag through an injected small
/// `maxResults`, the nonexistent-directory correction, the
/// outside-the-root path correction, the pattern-too-long correction, and
/// the invalid-glob-syntax correction.
@Suite struct FilesGlobTests {
    // MARK: Test scaffolding

    /// The pattern-length cap the engine enforces, as the corrective message
    /// names it.
    private static let patternLengthCap = 1000

    /// The small result cap that makes five files overflow the cap.
    private static let smallResultCap = 2

    /// The result cap that one file stays below.
    private static let roomyResultCap = 10

    /// The number of files the cap test writes.
    private static let cappedTestFileCount = 5

    /// The number of seconds between the modification dates of two
    /// successive files, large enough for a filesystem timestamp to keep the
    /// order.
    private static let modificationStride: TimeInterval = 100

    /// Create a fresh temporary directory for one test.
    ///
    /// - Returns: the URL of a fresh temporary directory this suite owns.
    private static func makeDirectory() -> URL {
        TestSupport.makeTemporaryDirectory(named: "FilesGlobTests")
    }

    /// Make the `tools.files.glob` verb over a session rooted at a directory.
    ///
    /// - Parameter root: the session working directory.
    /// - Returns: the verb, over a fresh ``FileContext``.
    private static func makeVerb(root: URL) -> Glob {
        Glob(context: FileContext(root: root))
    }

    /// Write a file, create each intermediate directory, and set an optional
    /// modification date.
    ///
    /// - Parameters:
    ///   - name: the file name; a `/` in it creates nested directories.
    ///   - directory: the directory to create the file under.
    ///   - contents: the UTF-8 text content to write.
    ///   - modified: the modification date to set, or `nil` to keep the
    ///     filesystem default.
    private static func write(
        _ name: String,
        in directory: URL,
        contents: String = "content",
        modified: Date? = nil
    ) throws {
        let url = directory.appendingPathComponent(name, isDirectory: false)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url)
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        }
    }

    // MARK: Gitignore awareness

    /// A gitignored file does not appear in the matches: the default walk is
    /// git-aware inside a repository.
    @Test func gitignoredFileIsAbsentByDefault() async throws {
        let root = Self.makeDirectory()
        try TestSupport.runGit(["init", "--quiet"], in: root)
        try Self.write(".gitignore", in: root, contents: "*.log\n")
        try Self.write("keep.txt", in: root)
        try Self.write("debug.log", in: root)

        let result = try await Self.makeVerb(root: root)
            .call(arguments: GlobArguments(pattern: "*.log"))

        #expect(result.correction == nil)
        #expect(!result.files.contains("debug.log"))
        #expect(result.total == 0)
    }

    /// With `respectGitIgnore` off, the walk shows the gitignored file.
    @Test func gitignoredFileIsPresentWhenRespectGitIgnoreIsFalse() async throws {
        let root = Self.makeDirectory()
        try TestSupport.runGit(["init", "--quiet"], in: root)
        try Self.write(".gitignore", in: root, contents: "*.log\n")
        try Self.write("keep.txt", in: root)
        try Self.write("debug.log", in: root)

        let result = try await Self.makeVerb(root: root)
            .call(arguments: GlobArguments(pattern: "*.log", respectGitIgnore: false))

        #expect(result.correction == nil)
        #expect(result.files.contains("debug.log"))
    }

    /// Tracked and untracked files that no ignore rule covers stay visible.
    @Test func gitTrackedAndUntrackedNonIgnoredFilesAreVisible() async throws {
        let root = Self.makeDirectory()
        try TestSupport.runGit(["init", "--quiet"], in: root)
        try Self.write(".gitignore", in: root, contents: "*.log\n")
        try Self.write("keep.txt", in: root)
        try Self.write("notes.txt", in: root)
        try Self.write("debug.log", in: root)

        let result = try await Self.makeVerb(root: root)
            .call(arguments: GlobArguments(pattern: "*.txt"))

        #expect(Set(result.files) == ["keep.txt", "notes.txt"])
    }

    /// A search scoped to a subdirectory answers with paths relative to the
    /// session root, not to the subdirectory.
    @Test func gitScopedSubdirectoryReturnsSessionRelativePaths() async throws {
        let root = Self.makeDirectory()
        try TestSupport.runGit(["init", "--quiet"], in: root)
        try Self.write("sub/a.txt", in: root)
        try Self.write("sub/deep/b.txt", in: root)
        try Self.write("top.txt", in: root)
        let subdirectory = root.appendingPathComponent("sub", isDirectory: true)

        let result = try await Self.makeVerb(root: root)
            .call(arguments: GlobArguments(pattern: "**/*.txt", path: subdirectory.path))

        #expect(Set(result.files) == ["sub/a.txt", "sub/deep/b.txt"])
    }

    // MARK: Non-repository fallback

    /// Outside a repository, the plain `FileManager` walk finds the files.
    @Test func nonRepositoryFallbackWalkFindsFiles() async throws {
        let root = Self.makeDirectory()
        try Self.write("foo.txt", in: root)
        try Self.write("bar.txt", in: root)

        let result = try await Self.makeVerb(root: root)
            .call(arguments: GlobArguments(pattern: "*.txt"))

        #expect(Set(result.files) == ["foo.txt", "bar.txt"])
    }

    /// A relative-path pattern with `**` matches the nested files and the
    /// top-level files alike.
    @Test func relativePathPatternMatchesNestedFiles() async throws {
        let root = Self.makeDirectory()
        try Self.write("src/deep/nested.swift", in: root)
        try Self.write("top.swift", in: root)

        let result = try await Self.makeVerb(root: root)
            .call(arguments: GlobArguments(pattern: "**/*.swift", path: root.path))

        #expect(Set(result.files) == ["src/deep/nested.swift", "top.swift"])
    }

    // MARK: Broad-pattern matrix

    /// The broad patterns the engine rejects when no `path` scopes the walk.
    private static let broadPatterns = ["*", "**", "**/*", "*.*", "**/*.swift"]

    /// Each broad pattern comes back as a correction when no `path` scopes
    /// the walk, and the correction tells the model to give a `path`.
    @Test func broadPatternsAreRejectedWhenUnscoped() async throws {
        let root = Self.makeDirectory()
        try Self.write("a.txt", in: root)
        try Self.write("b.swift", in: root)

        for pattern in Self.broadPatterns {
            let result = try await Self.makeVerb(root: root)
                .call(arguments: GlobArguments(pattern: pattern))
            let correction = try #require(result.correction, "expected \(pattern) to be rejected unscoped")
            #expect(correction.contains("path"), "expected guidance to scope with a path, got: \(correction)")
            #expect(result.files.isEmpty)
            #expect(result.total == 0)
            #expect(!result.capped)
        }
    }

    /// Each broad pattern is permitted when a `path` scopes the walk.
    @Test func broadPatternsAreAllowedWhenScopedByPath() async throws {
        let root = Self.makeDirectory()
        try Self.write("a.txt", in: root)
        try Self.write("b.swift", in: root)

        for pattern in Self.broadPatterns {
            let result = try await Self.makeVerb(root: root)
                .call(arguments: GlobArguments(pattern: pattern, path: root.path))
            #expect(result.correction == nil, "expected \(pattern) to be allowed when scoped")
        }
    }

    // MARK: Case sensitivity

    /// Matching is case-insensitive when `caseSensitive` is absent.
    @Test func caseInsensitiveMatchingIsTheDefault() async throws {
        let root = Self.makeDirectory()
        try Self.write("README.md", in: root)

        let result = try await Self.makeVerb(root: root)
            .call(arguments: GlobArguments(pattern: "readme.md"))

        #expect(result.files == ["README.md"])
    }

    /// With `caseSensitive` on, a case mismatch is no match.
    @Test func caseSensitiveMatchingRejectsMismatchedCase() async throws {
        let root = Self.makeDirectory()
        try Self.write("README.md", in: root)

        let result = try await Self.makeVerb(root: root)
            .call(arguments: GlobArguments(pattern: "readme.md", caseSensitive: true))

        #expect(result.correction == nil)
        #expect(result.files.isEmpty)
    }

    // MARK: Ordering

    /// The matches come back sorted by modification time, newest first.
    @Test func resultsAreOrderedByModificationTimeNewestFirst() async throws {
        let root = Self.makeDirectory()
        let now = Date()
        let names = ["a.txt", "b.txt", "c.txt"]
        for (index, name) in names.enumerated() {
            try Self.write(name, in: root, modified: now.addingTimeInterval(Double(index) * Self.modificationStride))
        }

        let result = try await Self.makeVerb(root: root)
            .call(arguments: GlobArguments(pattern: "*.txt"))

        #expect(result.files == names.reversed())
    }

    // MARK: Result cap

    /// When the matches overflow the cap, exactly the cap's worth of the
    /// newest matches comes back and the `capped` flag says so. The cap is
    /// the engine's injectable seam, thus this test drives the engine.
    @Test func capIsHonoredWithHonestCappedFlag() throws {
        let root = Self.makeDirectory()
        let now = Date()
        for index in 1...Self.cappedTestFileCount {
            try Self.write(
                "f\(index).txt", in: root,
                modified: now.addingTimeInterval(Double(index) * Self.modificationStride))
        }

        let output = GlobEngine(maxResults: Self.smallResultCap)
            .run(pattern: "*.txt", in: FileContext(root: root))
        let matches = try #require(output.successResult)

        #expect(matches.total == Self.cappedTestFileCount)
        #expect(matches.capped)
        #expect(matches.files.count == Self.smallResultCap)
        #expect(matches.files == ["f5.txt", "f4.txt"])
    }

    /// Below the cap, the `capped` flag stays off and the total agrees with
    /// the files.
    @Test func belowCapReportsNotCapped() throws {
        let root = Self.makeDirectory()
        try Self.write("only.txt", in: root)

        let output = GlobEngine(maxResults: Self.roomyResultCap)
            .run(pattern: "*.txt", in: FileContext(root: root))
        let matches = try #require(output.successResult)

        #expect(matches.total == 1)
        #expect(!matches.capped)
        #expect(matches.files == ["only.txt"])
    }

    // MARK: Corrective outcomes

    /// A search directory that does not exist comes back as a correction, not
    /// as a thrown error.
    @Test func nonexistentDirectoryIsCorrective() async throws {
        let root = Self.makeDirectory()
        let missing = root.appendingPathComponent("does-not-exist", isDirectory: true)

        let result = try await Self.makeVerb(root: root)
            .call(arguments: GlobArguments(pattern: "*.txt", path: missing.path))
        let correction = try #require(result.correction)

        #expect(!correction.isEmpty)
    }

    /// A path outside the session root comes back as a correction: the
    /// search root stays bounded through the session's path guard.
    @Test func pathOutsideTheSessionRootIsCorrective() async throws {
        let root = Self.makeDirectory()
        let outside = Self.makeDirectory()

        let result = try await Self.makeVerb(root: root)
            .call(arguments: GlobArguments(pattern: "*.txt", path: outside.path))
        let correction = try #require(result.correction)

        #expect(!correction.isEmpty)
    }

    /// A pattern past the length cap comes back as a correction that names
    /// the cap.
    @Test func patternTooLongIsCorrective() async throws {
        let root = Self.makeDirectory()
        let pattern = String(repeating: "a", count: Self.patternLengthCap + 1)

        let result = try await Self.makeVerb(root: root)
            .call(arguments: GlobArguments(pattern: pattern, path: root.path))
        let correction = try #require(result.correction)

        #expect(correction.contains("\(Self.patternLengthCap)"))
    }

    /// A pattern that is not valid glob syntax comes back as a correction.
    @Test func invalidPatternSyntaxIsCorrective() async throws {
        let root = Self.makeDirectory()

        let result = try await Self.makeVerb(root: root)
            .call(arguments: GlobArguments(pattern: "[", path: root.path))
        let correction = try #require(result.correction)

        #expect(!correction.isEmpty)
    }

    // MARK: Verb wiring

    /// The verb applies the defaults, echoes the pattern, and answers the
    /// matches with no correction.
    @Test func verbAppliesDefaultsAndAnswersTheMatches() async throws {
        let root = Self.makeDirectory()
        try Self.write("foo.txt", in: root)

        let result = try await Self.makeVerb(root: root)
            .call(arguments: GlobArguments(pattern: "*.txt"))

        #expect(result.files == ["foo.txt"])
        #expect(result.pattern == "*.txt")
        #expect(result.total == 1)
        #expect(!result.capped)
        #expect(result.correction == nil)
    }
}
