// `FilesListTests` — the behavioral suite of the `tools.files.list` verb.
//
// SWE-bench run bench24-1023, django__django-13710: a model called
// `tools.files.list({ path: "django/utils" })` and got "not a function". The
// verb lists the entries of one directory. Each test runs a snippet through
// `MultiTool.call(arguments:)`, thus through the JSC interpreter and the
// `tools.*` bindings — the same path that snippet took.

import Foundation
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Behavioral tests for the `tools.files.list` verb.
@Suite(.ownsTemporaryDirectories) struct FilesListTests {

    /// The name of the temporary directory of one test, thus a leaked
    /// directory is traceable to this suite.
    private static let testDirectoryName = "FilesListTests"

    /// The value a listing snippet returns.
    private struct ListValue: Decodable {
        /// The entries the verb answered, in its own order.
        let entries: [String]
        /// The correction, when the verb answered one.
        let correction: String?
    }

    /// Makes `root` hold `utils/a.py`, `utils/b.py`, `utils/sub/c.py`, and
    /// `top.txt`.
    ///
    /// - Parameter root: the session root.
    /// - Throws: When a file or folder does not write.
    private static func seedTree(in root: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(
            at: root.appendingPathComponent("utils/sub", isDirectory: true),
            withIntermediateDirectories: true)
        for path in ["utils/a.py", "utils/b.py", "utils/sub/c.py", "top.txt"] {
            try Data("x\n".utf8).write(to: root.appendingPathComponent(path, isDirectory: false))
        }
    }

    /// Runs one listing snippet against a surface that holds the files
    /// capability alone, and decodes what it returns.
    ///
    /// - Parameters:
    ///   - call: the argument object of the `tools.files.list` call, as JS.
    ///   - root: the session root.
    ///   - excludePatterns: the host exclude patterns of the capability.
    /// - Returns: the decoded value.
    /// - Throws: When the run throws or the output does not decode.
    private static func list(
        _ call: String, root: URL, excludePatterns: [String] = []
    ) async throws -> ListValue {
        let registry = try MultiTool.Builder()
            .withFiles(root: root, excludePatterns: excludePatterns)
            .buildRegistry()
        let output = try await MultiTool(registry: registry).call(
            arguments: RunCodeArguments(
                code: """
                    const listed = await tools.files.list(\(call));
                    return { entries: listed.entries, correction: listed.correction ?? null };
                    """))
        return try RunOutput.decoded(ListValue.self, from: output)
    }

    @Test("tools.files.list({ path }) answers the entries of that directory, a folder with a trailing slash")
    func listAnswersTheEntriesOfTheDirectory() async throws {
        let root = TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName)
        try Self.seedTree(in: root)

        let value = try await Self.list("{ path: \"utils\" }", root: root)

        #expect(value.correction == nil)
        #expect(value.entries == ["a.py", "b.py", "sub/"])
    }

    @Test("tools.files.list() with no path lists the session root")
    func listWithNoPathListsTheRoot() async throws {
        let root = TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName)
        try Self.seedTree(in: root)

        let value = try await Self.list("{}", root: root)

        #expect(value.correction == nil)
        #expect(value.entries == ["top.txt", "utils/"])
    }

    @Test("an entry the host exclude patterns name is not listed")
    func anExcludedEntryIsNotListed() async throws {
        let root = TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName)
        try Self.seedTree(in: root)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".acp-agent", isDirectory: true),
            withIntermediateDirectories: false)

        let value = try await Self.list("{}", root: root, excludePatterns: [".acp-agent/"])

        #expect(value.entries == ["top.txt", "utils/"])
    }

    @Test(
        "a missing directory, a file, and a path outside the root each answer a correction",
        arguments: ["no-such-dir", "top.txt", "/"])
    func aPathThatIsNotADirectoryInsideTheRootIsCorrective(path: String) async throws {
        let root = TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName)
        try Self.seedTree(in: root)

        let value = try await Self.list("{ path: \"\(path)\" }", root: root)

        #expect(value.correction != nil)
        #expect(value.entries.isEmpty)
    }
}
