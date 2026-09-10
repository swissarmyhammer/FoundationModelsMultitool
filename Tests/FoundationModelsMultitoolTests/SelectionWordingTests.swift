import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Holds every entry of the nine-entry files-and-shell surface to naming the
/// work a person brings to it, and not only the mechanism it implements.
///
/// **Why this suite exists.** `APISurface.Entry.summaryBlock` is the whole of
/// what the selection tier reads about a tool: the `// tools.<path>` banner and
/// the tool's `description`, with no parameter line and no signature. A
/// description that says only what the verb does — "starts one shell command in
/// the background and answers at once with its completion token" — gives the
/// selection model nothing to match a plain-language request against. Card
/// `^p06rh7z` measured that: over fifteen queries written from a task
/// description alone, `shell.getLines` and `shell.grepHistory` were never
/// selected once in 45 calls, and "i want to run the project test suite now"
/// answered `{"ids":[]}` because no description on the surface named a test
/// suite, a build or a script.
///
/// **What it holds.** Each entry must carry, in the text the selection tier
/// reads, the everyday words for the work it answers. The phrases are the work,
/// never a query: they name the tasks a reader of the tool would bring, so a
/// description rewritten back into implementation terms fails here.
///
/// The gated `HeldOutSurfaceDiscoveryTests` measures whether the wording works
/// on a live model. This suite is the fast guard that the wording is still
/// there at all.
@Suite("SelectionWordingTests")
struct SelectionWordingTests {

    /// One entry of the surface, and the everyday words its selection block
    /// must carry.
    private struct RequiredWording {

        /// The rendered call path of the entry, as `surface.entries` reports it.
        let path: String

        /// The phrases the entry's selection block must hold, each matched
        /// without regard to case.
        let phrases: [String]
    }

    /// Owns the temporary directory this test makes. Thus it goes away when the
    /// test ends, and the directories do not collect in `$TMPDIR` run after run.
    private let scratch = TestScratch()

    /// The name prefix of the temporary directory of one test. Thus a leaked
    /// directory is traceable to this suite.
    private static let testDirectoryNamePrefix = "selection-wording-tests"

    /// The name of the shell store folder inside the directory of one test.
    private static let shellStoreDirectoryName = ".shell"

    /// The everyday words each entry of the files-and-shell surface must carry
    /// in the text the selection tier reads.
    ///
    /// Read each row as the request a person writes. `shell.execute` must name
    /// the test suite, the build and the deleting that no files verb does;
    /// `shell.getLines` and `shell.grepHistory` must name what a command
    /// printed, because that output is not a file and a reader who wants it
    /// otherwise lands on `files.read`; `files.write` must name replacing a
    /// whole file, and `files.edit` must say it changes a part, because a
    /// request to rewrite a module went to `files.edit`.
    private static let requiredWording = [
        RequiredWording(
            path: "files.read", phrases: ["on disk", "printed"]),
        RequiredWording(
            path: "files.write", phrases: ["create a new file", "whole contents", "never removes a file"]),
        RequiredWording(
            path: "files.edit", phrases: ["part of a file", "already exists"]),
        RequiredWording(
            path: "files.patch", phrases: ["several files", "delete a file", "rename"]),
        RequiredWording(
            path: "files.glob", phrases: ["by name", "which files you have changed"]),
        RequiredWording(
            path: "files.grep", phrases: ["inside files", "what you have changed"]),
        RequiredWording(
            path: "shell.execute",
            phrases: ["test suite", "build", "script", "delete", "version control", "git status"]),
        RequiredWording(
            path: "shell.getLines", phrases: ["printed", "log", "not a file"]),
        RequiredWording(
            path: "shell.grepHistory", phrases: ["printed", "error"]),
    ]

    /// The nine-entry files-and-shell surface, rendered over a temporary root
    /// this test owns.
    ///
    /// The same mount the two gated discovery suites drive, so the text this
    /// suite reads is the text the selection tier reads there.
    ///
    /// - Returns: The rendered surface.
    /// - Throws: When the directory, the store or the surface does not prepare.
    private func makeSurface() throws -> APISurface {
        let root = try scratch.makeDirectory(prefix: Self.testDirectoryNamePrefix)
        return try MultiTool.Builder()
            .withFiles(root: root, readOnly: false)
            .withShell(
                storeDirectory: root.appendingPathComponent(
                    Self.shellStoreDirectoryName, isDirectory: true))
            .buildRegistry()
            .surface
    }

    @Test("every entry of the files-and-shell surface names the work it is for")
    func everyEntryNamesTheWorkItIsFor() throws {
        let surface = try makeSurface()
        for wording in Self.requiredWording {
            let entry = try #require(
                surface.entries.first { $0.path == wording.path },
                "the surface renders no entry at \(wording.path)")
            for phrase in wording.phrases {
                #expect(
                    entry.summaryBlock.localizedCaseInsensitiveContains(phrase),
                    """
                    the selection block of \(wording.path) does not name "\(phrase)", \
                    thus the selection model reads no everyday word for that work
                    """
                )
            }
        }
    }
}
