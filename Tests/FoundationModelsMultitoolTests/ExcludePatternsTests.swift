// `ExcludePatternsTests` — the rules of the host exclude patterns, one at a
// time, with no disk.
//
// Each case gives a path relative to the session root and asks whether the
// patterns exclude it. The expected answers are the answers of git for the
// same lines in a root `.gitignore` on a macOS volume (where git sets
// `core.ignorecase`).

import Testing

@testable import FoundationModelsMultitool

/// Unit tests for ``ExcludePatterns``, the gitignore-syntax matcher of the
/// host exclude patterns.
@Suite struct ExcludePatternsTests {

    /// The folder of the agent that the host excludes in the source request.
    private static let agentFolderPattern = ".acp-agent/"

    /// A transcript file under the agent folder.
    private static let transcriptPath = ".acp-agent/transcripts/x.jsonl"

    // MARK: No patterns

    /// An empty list excludes no path.
    @Test func noPatternsExcludeNothing() {
        let patterns = ExcludePatterns([])
        #expect(!patterns.excludes(relativePath: Self.transcriptPath))
        #expect(!patterns.excludes(relativePath: "notes.txt"))
    }

    // MARK: Folder patterns

    /// A folder pattern excludes each file under that folder, at each depth.
    @Test func folderPatternExcludesEachFileUnderTheFolder() {
        let patterns = ExcludePatterns([Self.agentFolderPattern])
        #expect(patterns.excludes(relativePath: Self.transcriptPath))
        #expect(patterns.excludes(relativePath: "sub/.acp-agent/log.txt"))
        #expect(!patterns.excludes(relativePath: "notes.txt"))
    }

    /// A folder pattern does not exclude a file that has the same name.
    @Test func folderPatternDoesNotExcludeAFileOfTheSameName() {
        let patterns = ExcludePatterns(["build/"])
        #expect(!patterns.excludes(relativePath: "docs/build"))
        #expect(patterns.excludes(relativePath: "docs/build/out.txt"))
    }

    /// A pattern with a slash in the middle is anchored to the session root.
    @Test func patternWithAMiddleSlashIsAnchoredToTheRoot() {
        let patterns = ExcludePatterns(["docs/generated"])
        #expect(patterns.excludes(relativePath: "docs/generated/a.md"))
        #expect(!patterns.excludes(relativePath: "sub/docs/generated/a.md"))
    }

    /// A leading slash anchors a pattern to the session root.
    @Test func leadingSlashAnchorsThePatternToTheRoot() {
        let patterns = ExcludePatterns(["/out.txt"])
        #expect(patterns.excludes(relativePath: "out.txt"))
        #expect(!patterns.excludes(relativePath: "sub/out.txt"))
    }

    /// A trailing `/**` excludes what is in the folder, but not a file with
    /// the name of the folder.
    @Test func trailingDoubleStarExcludesTheContentOfTheFolderOnly() {
        let patterns = ExcludePatterns(["cache/**"])
        #expect(patterns.excludes(relativePath: "cache/a/b.bin"))
        #expect(!patterns.excludes(relativePath: "cache"))
    }

    // MARK: Wildcards

    /// A wildcard pattern with no slash matches the name at each depth.
    @Test func wildcardPatternMatchesTheNameAtEachDepth() {
        let patterns = ExcludePatterns(["*.log"])
        #expect(patterns.excludes(relativePath: "debug.log"))
        #expect(patterns.excludes(relativePath: "a/b/trace.log"))
        #expect(!patterns.excludes(relativePath: "a/b/trace.txt"))
    }

    // MARK: Negation

    /// A negated pattern puts back a file that an earlier pattern excludes.
    @Test func negatedPatternPutsBackAFile() {
        let patterns = ExcludePatterns(["*.log", "!keep.log"])
        #expect(patterns.excludes(relativePath: "debug.log"))
        #expect(!patterns.excludes(relativePath: "keep.log"))
    }

    /// The last pattern that matches decides, thus a later pattern excludes
    /// the file again.
    @Test func theLastMatchingPatternDecides() {
        let patterns = ExcludePatterns(["*.log", "!keep.log", "keep.log"])
        #expect(patterns.excludes(relativePath: "keep.log"))
    }

    /// A negated pattern cannot put back a file when a parent folder is
    /// excluded, the same as in gitignore.
    @Test func negatedPatternCannotPutBackAFileUnderAnExcludedFolder() {
        let patterns = ExcludePatterns([Self.agentFolderPattern, "!.acp-agent/keep.txt"])
        #expect(patterns.excludes(relativePath: ".acp-agent/keep.txt"))
    }

    // MARK: Lines that are not patterns

    /// A blank line and a comment line match no path.
    @Test func blankAndCommentLinesMatchNothing() {
        let patterns = ExcludePatterns(["", "   ", "# notes.txt"])
        #expect(!patterns.excludes(relativePath: "notes.txt"))
        #expect(!patterns.excludes(relativePath: "# notes.txt"))
    }

    /// The spaces at the end of a pattern are not part of the pattern.
    @Test func trailingSpacesAreNotPartOfThePattern() {
        let patterns = ExcludePatterns(["*.log   "])
        #expect(patterns.excludes(relativePath: "debug.log"))
    }

    /// A backslash before a leading `#` or `!` makes that character a literal.
    @Test func backslashMakesALeadingHashOrBangLiteral() {
        let patterns = ExcludePatterns(["\\#notes.txt", "\\!important.txt"])
        #expect(patterns.excludes(relativePath: "#notes.txt"))
        #expect(patterns.excludes(relativePath: "!important.txt"))
    }

    /// A pattern that does not compile matches nothing, the same as git.
    @Test func patternThatDoesNotCompileMatchesNothing() {
        let patterns = ExcludePatterns(["[abc"])
        #expect(!patterns.excludes(relativePath: "[abc"))
        #expect(!patterns.excludes(relativePath: "a"))
    }

    // MARK: Case

    /// A pattern matches without regard to case, the same as git with
    /// `core.ignorecase`, which git sets on a macOS volume.
    @Test func patternMatchesWithoutRegardToCase() {
        let patterns = ExcludePatterns([Self.agentFolderPattern, "*.log"])
        #expect(patterns.excludes(relativePath: ".ACP-Agent/transcripts/x.jsonl"))
        #expect(patterns.excludes(relativePath: "TRACE.LOG"))
    }
}
