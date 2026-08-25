// `FilesGrepTests` — the behavioral suite of the `tools.files.grep` verb.
//
// A port of `../FoundationModelsFileTool/Tests/FileToolTests/
// GrepFilesTests.swift`, adapted to the `Tool` call shape: the sibling
// decoded a `GrepFiles` operation out of `GeneratedContent`; here the suite
// constructs `GrepArguments` with the memberwise initializer and calls the
// `Grep` verb directly, the way `FilesGlobTests` calls its verb. The
// engine's `caseSensitive:` spelling keeps two engine-level tests, because
// the verb speaks the inverse `caseInsensitive` dialect. The sibling's
// deprecated `caseInsensitive:` engine overload does not port, thus its
// pinning test does not port either; the inversion now lives at the verb
// boundary and `verbInvertsCaseInsensitiveOntoTheEngineFlag` pins it.

import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Behavioral tests for the ``GrepEngine`` and the `tools.files.grep` verb.
///
/// Every case of the sibling `grep files` suite is here: a basic line match
/// in the default `content` mode, the invalid-regex correction,
/// case-insensitive matching through the `caseInsensitive` flag, the
/// file-type filter with the unknown-type correction that lists the known
/// types, the filename `glob` filter, all three output modes and their
/// distinct shapes, context assembly at zero / two / negative lines with
/// the hunk boundary between non-adjacent groups and the file-boundary
/// clamp, the null-byte binary skip, the single-file short-circuit, the
/// nonexistent-path correction, and the git-aware walk that never descends
/// into a gitignored directory.
@Suite struct FilesGrepTests {
    // MARK: Test scaffolding

    /// Create a fresh temporary directory for one test.
    ///
    /// - Returns: the URL of a fresh temporary directory this suite owns.
    private static func makeDirectory() -> URL {
        TestSupport.makeTemporaryDirectory(named: "FilesGrepTests")
    }

    /// Make the `tools.files.grep` verb over a session rooted at a directory.
    ///
    /// - Parameter root: the session working directory.
    /// - Returns: the verb, over a fresh ``FileContext``.
    private static func makeVerb(root: URL) -> Grep {
        Grep(context: FileContext(root: root))
    }

    /// Write a UTF-8 text file, and create each intermediate directory.
    ///
    /// - Parameters:
    ///   - name: the file name; a `/` in it creates nested directories.
    ///   - directory: the directory to create the file under.
    ///   - contents: the UTF-8 text content to write.
    /// - Returns: the URL of the written file.
    @discardableResult
    private static func write(_ name: String, in directory: URL, contents: String) throws -> URL {
        let url = directory.appendingPathComponent(name, isDirectory: false)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url)
        return url
    }

    /// Write a file of raw bytes.
    ///
    /// - Parameters:
    ///   - name: the file name.
    ///   - directory: the directory to create the file under.
    ///   - bytes: the raw bytes to write.
    private static func writeBytes(_ name: String, in directory: URL, bytes: [UInt8]) throws {
        let url = directory.appendingPathComponent(name, isDirectory: false)
        try Data(bytes).write(to: url)
    }

    // MARK: Basic matching

    /// A plain pattern answers the one matching line, with its address and
    /// its counts.
    @Test func basicMatchReturnsTheMatchingLine() async throws {
        let root = Self.makeDirectory()
        try Self.write("a.txt", in: root, contents: "alpha\nbeta\ngamma\n")

        let result = try await Self.makeVerb(root: root)
            .call(arguments: GrepArguments(pattern: "beta", contextLines: 0))

        #expect(result.correction == nil)
        let matches = try #require(result.matches)
        #expect(matches.count == 1)
        #expect(matches[0].file == "a.txt")
        #expect(matches[0].line == 2)
        #expect(matches[0].text == "beta")
        #expect(matches[0].isMatch)
        #expect(result.matchCount == 1)
        #expect(result.fileCount == 1)
    }

    /// A regular-expression pattern matches each line it covers.
    @Test func regexPatternMatchesAcrossLines() async throws {
        let root = Self.makeDirectory()
        try Self.write("a.txt", in: root, contents: "foo123\nbar\nbaz456\n")

        let result = try await Self.makeVerb(root: root)
            .call(arguments: GrepArguments(pattern: "[0-9]+", contextLines: 0))

        #expect(result.matchCount == 2)
        #expect(Set((result.matches ?? []).map(\.line)) == [1, 3])
    }

    // MARK: Corrective outcomes

    /// A pattern that is not a valid regular expression comes back as a
    /// correction beside zero counts, not as a thrown error.
    @Test func invalidRegexIsCorrective() async throws {
        let root = Self.makeDirectory()
        try Self.write("a.txt", in: root, contents: "text\n")

        let result = try await Self.makeVerb(root: root)
            .call(arguments: GrepArguments(pattern: "(unterminated"))
        let correction = try #require(result.correction)

        #expect(!correction.isEmpty)
        #expect(result.matches == nil)
        #expect(result.files == nil)
        #expect(result.matchCount == 0)
        #expect(result.fileCount == 0)
    }

    /// A search path that does not exist comes back as a correction.
    @Test func nonexistentPathIsCorrective() async throws {
        let root = Self.makeDirectory()
        let missing = root.appendingPathComponent("does-not-exist", isDirectory: false)

        let result = try await Self.makeVerb(root: root)
            .call(arguments: GrepArguments(pattern: "x", path: missing.path))
        let correction = try #require(result.correction)

        #expect(!correction.isEmpty)
    }

    // MARK: Case sensitivity

    /// With `caseInsensitive` on, a case mismatch still matches.
    @Test func caseInsensitiveMatchingFindsMixedCase() async throws {
        let root = Self.makeDirectory()
        try Self.write("a.txt", in: root, contents: "Hello World\n")

        let result = try await Self.makeVerb(root: root)
            .call(arguments: GrepArguments(pattern: "WORLD", caseInsensitive: true, contextLines: 0))

        #expect(result.matchCount == 1)
    }

    /// Matching is case-sensitive when `caseInsensitive` is absent.
    @Test func caseSensitiveMatchingIsTheDefault() async throws {
        let root = Self.makeDirectory()
        try Self.write("a.txt", in: root, contents: "Hello World\n")

        let result = try await Self.makeVerb(root: root)
            .call(arguments: GrepArguments(pattern: "WORLD", contextLines: 0))

        #expect(result.matchCount == 0)
    }

    /// The engine's own `caseSensitive` flag controls matching in both
    /// directions, thus the flag's polarity agrees with its name.
    @Test func engineCaseSensitiveFlagControlsMatching() throws {
        let root = Self.makeDirectory()
        try Self.write("a.txt", in: root, contents: "Hello World\n")

        let insensitive = GrepEngine().run(
            pattern: "WORLD", caseSensitive: false, contextLines: 0, in: FileContext(root: root))
        let sensitive = GrepEngine().run(
            pattern: "WORLD", caseSensitive: true, contextLines: 0, in: FileContext(root: root))

        #expect(try #require(insensitive.successResult).matchCount == 1)
        #expect(try #require(sensitive.successResult).matchCount == 0)
    }

    /// The engine surfaces a recoverable failure through
    /// ``GrepOutput/correctiveMessage``, never through a throw.
    @Test func engineCorrectiveSurfacesThroughCorrectiveMessage() throws {
        let root = Self.makeDirectory()
        try Self.write("a.txt", in: root, contents: "text\n")

        let output = GrepEngine().run(pattern: "(unterminated", in: FileContext(root: root))
        let message = try #require(output.correctiveMessage)

        #expect(!message.isEmpty)
        #expect(output.successResult == nil)
    }

    // MARK: Type filter

    /// The `type` filter keeps only the files of the named type.
    @Test func typeFilterRestrictsToMatchingExtensions() async throws {
        let root = Self.makeDirectory()
        try Self.write("code.swift", in: root, contents: "// TODO fix\n")
        try Self.write("notes.txt", in: root, contents: "TODO fix\n")

        let result = try await Self.makeVerb(root: root)
            .call(
                arguments: GrepArguments(
                    pattern: "TODO", path: root.path, type: "swift", contextLines: 0))

        #expect(result.matchCount == 1)
        #expect((result.matches ?? []).allSatisfy { $0.file == "code.swift" })
    }

    /// The `type` lookup ignores case, the same way the `outputMode` lookup
    /// does: a non-canonical spelling resolves to the same extensions as the
    /// canonical lowercase form.
    @Test func typeFilterResolvesCaseInsensitively() async throws {
        let root = Self.makeDirectory()
        try Self.write("code.swift", in: root, contents: "// TODO fix\n")
        try Self.write("notes.txt", in: root, contents: "TODO fix\n")

        let result = try await Self.makeVerb(root: root)
            .call(
                arguments: GrepArguments(
                    pattern: "TODO", path: root.path, type: "SWIFT", contextLines: 0))

        #expect(result.correction == nil)
        #expect(result.matchCount == 1)
        #expect((result.matches ?? []).allSatisfy { $0.file == "code.swift" })
    }

    /// An unknown `type` comes back as a correction that names the rejected
    /// value and lists every known type.
    @Test func unknownTypeIsCorrectiveListingKnownTypes() async throws {
        let root = Self.makeDirectory()
        try Self.write("code.swift", in: root, contents: "TODO\n")

        let result = try await Self.makeVerb(root: root)
            .call(arguments: GrepArguments(pattern: "TODO", path: root.path, type: "cobol"))
        let correction = try #require(result.correction)

        // Pinned byte for byte: the correction is model-facing text, thus its
        // wording, its punctuation, and the sorted spelling of every known
        // type are all part of the verb's observable output.
        #expect(
            correction == "The `type` parameter is not a known file type: cobol. Known types are: "
                + "c, cpp, css, go, html, java, js, json, md, py, rust, sh, "
                + "swift, toml, ts, txt, xml, yaml."
        )
    }

    // MARK: Glob filter

    /// The `glob` filter keeps only the files whose name matches.
    @Test func globFilterRestrictsToMatchingFilenames() async throws {
        let root = Self.makeDirectory()
        try Self.write("a.swift", in: root, contents: "match\n")
        try Self.write("b.txt", in: root, contents: "match\n")

        let result = try await Self.makeVerb(root: root)
            .call(
                arguments: GrepArguments(
                    pattern: "match", path: root.path, glob: "*.txt", contextLines: 0))

        #expect(result.matchCount == 1)
        #expect((result.matches ?? []).allSatisfy { $0.file == "b.txt" })
    }

    /// The `glob` filename filter matches without case sensitivity: a
    /// mixed-case filename matches a lowercase pattern, the same way the
    /// `tools.files.glob` verb matches (the engine passes
    /// `caseSensitive: false` to the filename filter).
    @Test func globFilterMatchesFilenamesCaseInsensitively() async throws {
        let root = Self.makeDirectory()
        try Self.write("TestFile.TXT", in: root, contents: "match\n")
        try Self.write("other.swift", in: root, contents: "match\n")

        let result = try await Self.makeVerb(root: root)
            .call(
                arguments: GrepArguments(
                    pattern: "match", path: root.path, glob: "*.txt", contextLines: 0))

        #expect(result.correction == nil)
        #expect(result.matchCount == 1)
        #expect((result.matches ?? []).allSatisfy { $0.file == "TestFile.TXT" })
    }

    // MARK: Output modes

    /// The `filesWithMatches` mode answers the file list and no line.
    @Test func filesWithMatchesModeReturnsFileListOnly() async throws {
        let root = Self.makeDirectory()
        try Self.write("a.txt", in: root, contents: "match\n")
        try Self.write("b.txt", in: root, contents: "match\n")

        let result = try await Self.makeVerb(root: root)
            .call(
                arguments: GrepArguments(
                    pattern: "match", path: root.path, outputMode: "filesWithMatches"))

        #expect(result.matches == nil)
        let files = try #require(result.files)
        #expect(Set(files) == ["a.txt", "b.txt"])
        #expect(result.fileCount == 2)
        #expect(result.matchCount == 2)
    }

    /// The `count` mode answers the totals and nothing else.
    @Test func countModeReturnsCountsOnly() async throws {
        let root = Self.makeDirectory()
        try Self.write("a.txt", in: root, contents: "match\nmatch\n")
        try Self.write("b.txt", in: root, contents: "match\n")

        let result = try await Self.makeVerb(root: root)
            .call(arguments: GrepArguments(pattern: "match", path: root.path, outputMode: "count"))

        #expect(result.matches == nil)
        #expect(result.files == nil)
        #expect(result.matchCount == 3)
        #expect(result.fileCount == 2)
    }

    /// The `outputMode` lookup ignores case, the same way the `type` filter
    /// does.
    @Test func outputModeResolvesCaseInsensitivelyLikeTheTypeFilter() async throws {
        let root = Self.makeDirectory()
        try Self.write("a.txt", in: root, contents: "match\n")

        let result = try await Self.makeVerb(root: root)
            .call(
                arguments: GrepArguments(
                    pattern: "match", path: root.path, outputMode: "FILESWITHMATCHES"))

        #expect(result.matches == nil)
        #expect(result.files == ["a.txt"])
    }

    /// An unknown `outputMode` comes back as a correction that names the
    /// canonical spellings.
    @Test func unknownOutputModeIsCorrectiveNamingTheCanonicalSpellings() async throws {
        let root = Self.makeDirectory()
        try Self.write("a.txt", in: root, contents: "match\n")

        let result = try await Self.makeVerb(root: root)
            .call(
                arguments: GrepArguments(pattern: "match", path: root.path, outputMode: "nonsense"))
        let correction = try #require(result.correction)

        // Pinned byte for byte, and in particular naming the modes in their
        // canonical camelCase rather than in whatever case-folded form the
        // lookup happens to use internally.
        #expect(correction == "The `outputMode` parameter must be one of: content, count, filesWithMatches.")
    }

    /// The `content` mode is the default when `outputMode` is absent.
    @Test func contentModeIsTheDefault() async throws {
        let root = Self.makeDirectory()
        try Self.write("a.txt", in: root, contents: "match\n")

        let result = try await Self.makeVerb(root: root)
            .call(arguments: GrepArguments(pattern: "match", path: root.path))

        #expect(result.matches != nil)
    }

    // MARK: Context assembly

    /// A `contextLines` of zero answers the match lines alone.
    @Test func contextLinesZeroReturnsOnlyMatchLines() async throws {
        let root = Self.makeDirectory()
        try Self.write("a.txt", in: root, contents: "one\ntwo\nthree\nfour\nfive\n")

        let result = try await Self.makeVerb(root: root)
            .call(arguments: GrepArguments(pattern: "three", contextLines: 0))

        let matches = try #require(result.matches)
        #expect(matches.map(\.line) == [3])
        #expect(matches.map(\.isMatch) == [true])
    }

    /// A `contextLines` of two carries the surrounding lines, each flagged
    /// as context, and only the match line counts.
    @Test func contextLinesTwoIncludesSurroundingContextFlaggedNotMatch() async throws {
        let root = Self.makeDirectory()
        try Self.write("a.txt", in: root, contents: "one\ntwo\nthree\nfour\nfive\n")

        let result = try await Self.makeVerb(root: root)
            .call(arguments: GrepArguments(pattern: "three", contextLines: 2))

        let matches = try #require(result.matches)
        #expect(matches.map(\.line) == [1, 2, 3, 4, 5])
        #expect(matches.filter(\.isMatch).map(\.line) == [3])
        #expect(matches.filter { !$0.isMatch }.map(\.line) == [1, 2, 4, 5])
        // Only the match line counts toward the total.
        #expect(result.matchCount == 1)
    }

    /// A negative `contextLines` degrades to match lines only, thus the
    /// counted match line is never dropped from the content.
    @Test func negativeContextLinesDegradeToMatchLinesOnly() async throws {
        let root = Self.makeDirectory()
        try Self.write("a.txt", in: root, contents: "one\ntwo\nthree\n")

        let result = try await Self.makeVerb(root: root)
            .call(arguments: GrepArguments(pattern: "two", contextLines: -1))

        let matches = try #require(result.matches)
        #expect(matches.map(\.line) == [2])
        #expect(matches.map(\.isMatch) == [true])
        #expect(result.matchCount == 1)
    }

    /// A context window is clamped at the first and the last line of the
    /// file.
    @Test func contextIsClampedAtFileBoundaries() async throws {
        let root = Self.makeDirectory()
        try Self.write("a.txt", in: root, contents: "one\ntwo\nthree\n")

        let firstLine = try await Self.makeVerb(root: root)
            .call(arguments: GrepArguments(pattern: "one", contextLines: 2))
        let firstLines = try #require(firstLine.matches).map(\.line)
        #expect(firstLines == [1, 2, 3])

        let lastLine = try await Self.makeVerb(root: root)
            .call(arguments: GrepArguments(pattern: "three", contextLines: 2))
        let lastLines = try #require(lastLine.matches).map(\.line)
        #expect(lastLines == [1, 2, 3])
    }

    /// Non-adjacent match windows stay separate hunks, and the gap between
    /// them is omitted.
    @Test func nonAdjacentMatchesFormSeparateHunksWithAGap() async throws {
        let root = Self.makeDirectory()
        try Self.write(
            "a.txt",
            in: root,
            contents: "a\nm1\nc\nd\ne\nf\ng\nm2\ni\n"
        )

        let result = try await Self.makeVerb(root: root)
            .call(arguments: GrepArguments(pattern: "^m", contextLines: 1))

        // Match lines 2 and 8 give windows [1,3] and [7,9], which never
        // touch: the gap (lines 4, 5, 6) is the hunk boundary.
        let hunkLines = try #require(result.matches).map(\.line)
        #expect(hunkLines == [1, 2, 3, 7, 8, 9])
        #expect(result.matchCount == 2)
    }

    /// Overlapping match windows merge into one contiguous hunk.
    @Test func adjacentMatchWindowsMergeIntoOneHunk() async throws {
        let root = Self.makeDirectory()
        try Self.write(
            "a.txt",
            in: root,
            contents: "m1\nb\nm2\nd\ne\n"
        )

        let result = try await Self.makeVerb(root: root)
            .call(arguments: GrepArguments(pattern: "^m", contextLines: 1))

        // Windows [1,3] and [2,4] overlap, so the hunk is contiguous [1,4].
        let matches = try #require(result.matches)
        #expect(matches.map(\.line) == [1, 2, 3, 4])
        #expect(matches.filter(\.isMatch).map(\.line) == [1, 3])
    }

    // MARK: Binary skip

    /// A file whose first bytes hold a NUL is binary and is skipped.
    @Test func binaryFileIsSkipped() async throws {
        let root = Self.makeDirectory()
        try Self.writeBytes(
            "bin.dat", in: root, bytes: Array("match".utf8) + [0x00] + Array("match".utf8))

        let result = try await Self.makeVerb(root: root)
            .call(arguments: GrepArguments(pattern: "match", path: root.path, contextLines: 0))

        #expect(result.matchCount == 0)
    }

    // MARK: Single-file short-circuit

    /// A `path` that names a single file greps that file directly.
    @Test func singleFilePathGrepsThatFileDirectly() async throws {
        let root = Self.makeDirectory()
        let file = try Self.write("only.txt", in: root, contents: "needle here\nno match\n")

        let result = try await Self.makeVerb(root: root)
            .call(arguments: GrepArguments(pattern: "needle", path: file.path, contextLines: 0))

        #expect(result.matchCount == 1)
        #expect((result.matches ?? []).allSatisfy { $0.file == "only.txt" })
    }

    // MARK: Gitignore awareness

    /// An unscoped search never descends into a gitignored directory.
    @Test func gitignoredDirectoryIsNeverSearchedUnscoped() async throws {
        let root = Self.makeDirectory()
        try TestSupport.runGit(["init", "--quiet"], in: root)
        try Self.write(".gitignore", in: root, contents: "build/\n")
        try Self.write("keep.txt", in: root, contents: "match\n")
        try Self.write("build/generated.txt", in: root, contents: "match\n")

        let result = try await Self.makeVerb(root: root)
            .call(arguments: GrepArguments(pattern: "match", contextLines: 0))

        #expect(result.fileCount == 1)
        #expect((result.matches ?? []).allSatisfy { $0.file == "keep.txt" })
    }

    // MARK: Verb wiring

    /// Pins the wire-to-engine inversion in the verb: the `caseInsensitive`
    /// argument and the engine's `caseSensitive` flag are opposites, and the
    /// verb boundary is the only place the negation happens, thus a stray
    /// `!` there would silently invert the tool's behavior.
    @Test func verbInvertsCaseInsensitiveOntoTheEngineFlag() async throws {
        let root = Self.makeDirectory()
        try Self.write("a.txt", in: root, contents: "Hello World\n")

        let insensitive = try await Self.makeVerb(root: root)
            .call(arguments: GrepArguments(pattern: "WORLD", caseInsensitive: true))
        let sensitive = try await Self.makeVerb(root: root)
            .call(arguments: GrepArguments(pattern: "WORLD", caseInsensitive: false))
        let defaulted = try await Self.makeVerb(root: root)
            .call(arguments: GrepArguments(pattern: "WORLD"))

        #expect(insensitive.matchCount == 1)
        #expect(sensitive.matchCount == 0)
        // An absent flag defaults to case-sensitive, like an explicit `false`.
        #expect(defaulted.matchCount == 0)
    }

    /// The verb applies the defaults and answers the content with no
    /// correction and a non-negative duration.
    @Test func verbAppliesDefaultsAndAnswersContent() async throws {
        let root = Self.makeDirectory()
        try Self.write("a.txt", in: root, contents: "hello\n")

        let result = try await Self.makeVerb(root: root)
            .call(arguments: GrepArguments(pattern: "hello"))

        #expect(result.matchCount == 1)
        #expect(result.matches != nil)
        #expect(result.correction == nil)
        #expect(result.elapsedMs >= 0)
    }
}
