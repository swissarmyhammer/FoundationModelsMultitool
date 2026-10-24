// `ShowCommitAndReadNamesTests` — three more plain mistakes of a model that a
// `tools.*` call accepts ("Postel's rule": be liberal in what you accept).
//
// SWE-bench run bench24-1023b, django__django-14999:
// 1. seq 24055: `tools.git.show({ sha })` with no path. The model wants the
//    whole commit, the same as `git show <sha>`, and got "missing its required
//    argument \"path\"".
// 2. seq 23629: `tools.files.readFile({ path: "tox.ini" })`, and the other
//    usual names of `files.read`.
// 3. `tools.files.read("…", { offset: 300, limit: 110 })` named `tools.name`
//    in its error, and the hint then sent the model to `getRenameEdits`. The
//    path-and-options form now reads the range, with no hint text.

import Foundation
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

@Suite(.ownsTemporaryDirectories) struct ShowCommitAndReadNamesTests {

    /// The name of the temporary directory of one test.
    private static let testDirectoryName = "ShowCommitAndReadNamesTests"

    // MARK: - git.show with no path

    /// The text that the second commit gives `src/a.txt`.
    private static let secondText = "one\nTWO\n"

    /// A repository with two commits of `src/a.txt`, and the sha of HEAD.
    private static func repositoryWithTwoCommits() throws -> (TemporaryGitRepository, String) {
        let repository = try TemporaryGitRepository()
        try repository.write("one\ntwo\n", to: "src/a.txt")
        try repository.commit(message: "first")
        try repository.write(secondText, to: "src/a.txt")
        try repository.write("new\n", to: "b.txt")
        let sha = try repository.commit(message: "Fixed #33333 -- second\n\nThe body of the message.")
        return (repository, sha)
    }

    /// Runs `code` on a surface with the git capability over `repository`.
    private static func runGit(_ code: String, in repository: TemporaryGitRepository) async throws -> String {
        let registry = try MultiTool.Builder().withGit(root: repository.workDirectory).buildRegistry()
        return try await MultiTool(registry: registry).call(arguments: RunCodeArguments(code: code))
    }

    /// The part of a show result that the tests read.
    private struct ShowValue: Decodable {
        let ref: String
        let content: String?
        let correction: String?
    }

    @Test("the snippet of seq 24055: show with a sha and no path gives the whole commit")
    func showWithNoPathGivesTheWholeCommit() async throws {
        let (repository, sha) = try Self.repositoryWithTwoCommits()

        let output = try await Self.runGit(
            #"const r = await tools.git.show({ sha: "\#(sha)" }); return r;"#, in: repository)

        #expect(!output.contains("missing its required argument"), "output was: \(output)")
        let value = try RunOutput.decoded(ShowValue.self, from: output)
        #expect(value.correction == nil, "output was: \(output)")
        #expect(value.ref == sha, "output was: \(output)")
        let content = try #require(value.content, "output was: \(output)")
        #expect(content.hasPrefix("commit \(sha)\n"), "output was: \(output)")
        #expect(content.contains("    Fixed #33333 -- second\n"), "output was: \(output)")
        #expect(content.contains("    The body of the message.\n"), "output was: \(output)")
        #expect(content.contains("diff --git a/src/a.txt b/src/a.txt"), "output was: \(output)")
        #expect(content.contains("-two\n+TWO\n"), "output was: \(output)")
        #expect(content.contains("diff --git a/b.txt b/b.txt"), "output was: \(output)")
        #expect(content.contains("+new\n"), "output was: \(output)")
    }

    @Test("show takes sha, commit, rev, revision, and ref for the ref", arguments: ["sha", "commit", "rev", "revision", "ref"])
    func eachNameOfTheRefIsAccepted(name: String) async throws {
        let (repository, sha) = try Self.repositoryWithTwoCommits()

        let output = try await Self.runGit(
            #"return await tools.git.show({ \#(name): "HEAD~1", path: "src/a.txt" });"#, in: repository)

        let value = try RunOutput.decoded(ShowValue.self, from: output)
        #expect(value.correction == nil, "output was: \(output)")
        #expect(value.content == "one\ntwo\n", "output was: \(output)")
        #expect(value.ref == "HEAD~1", "output was: \(output) (HEAD is \(sha))")
    }

    @Test("show with a single string still reads it as the path")
    func showWithAStringReadsThePath() async throws {
        let (repository, _) = try Self.repositoryWithTwoCommits()

        let output = try await Self.runGit(#"return await tools.git.show("src/a.txt");"#, in: repository)

        let value = try RunOutput.decoded(ShowValue.self, from: output)
        #expect(value.content == Self.secondText, "output was: \(output)")
    }

    @Test("show with no path and no ref gives the commit at HEAD")
    func showWithNothingGivesHead() async throws {
        let (repository, sha) = try Self.repositoryWithTwoCommits()

        let output = try await Self.runGit("return await tools.git.show({});", in: repository)

        let value = try RunOutput.decoded(ShowValue.self, from: output)
        #expect(value.content?.hasPrefix("commit \(sha)\n") == true, "output was: \(output)")
    }

    @Test("show with no path and an unknown ref is a correction")
    func showWithAnUnknownRefIsACorrection() async throws {
        let (repository, _) = try Self.repositoryWithTwoCommits()

        let output = try await Self.runGit(#"return await tools.git.show({ sha: "nosuchref" });"#, in: repository)

        let value = try RunOutput.decoded(ShowValue.self, from: output)
        #expect(value.content == nil, "output was: \(output)")
        #expect(value.correction?.contains("nosuchref") == true, "output was: \(output)")
    }

    // MARK: - files.read names and the path-and-options form

    /// Runs `code` on a surface with the files capability over a root that
    /// holds `tox.ini` and a 500-line `django/db/migrations/operations/models.py`.
    private static func runFiles(_ code: String) async throws -> String {
        let root = TestSupport.makeTemporaryDirectory(named: testDirectoryName)
        let files = [
            "tox.ini": "[tox]\nenvlist = py3\n",
            "django/db/migrations/operations/models.py": (1...500).map { "line \($0)" }.joined(separator: "\n") + "\n",
        ]
        for (path, content) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(content.utf8).write(to: url)
        }
        let registry = try MultiTool.Builder().withFiles(root: root).buildRegistry()
        return try await MultiTool(registry: registry).call(arguments: RunCodeArguments(code: code))
    }

    /// The part of a read result the tests read.
    private struct ReadValue: Decodable {
        let lines: [String]
    }

    @Test("the snippet of seq 23629 reads tox.ini")
    func readFileReadsTheFile() async throws {
        let output = try await Self.runFiles(#"return await tools.files.readFile({ path: "tox.ini" });"#)

        let lines = try RunOutput.decoded(ReadValue.self, from: output).lines
        #expect(lines.first?.hasSuffix("[tox]") == true, "output was: \(output)")
    }

    @Test(
        "each usual name of files.read reads the file",
        arguments: ["readFile", "readText", "cat", "open", "get", "view"])
    func eachNameOfReadReadsTheFile(name: String) async throws {
        let output = try await Self.runFiles(#"return await tools.files.\#(name)({ path: "tox.ini" });"#)

        let lines = try RunOutput.decoded(ReadValue.self, from: output).lines
        #expect(lines.first?.hasSuffix("[tox]") == true, "output was: \(output)")
    }

    @Test("the path-and-options snippet of django__django-14999 reads the range, with no hint text")
    func aPathAndOptionsReadTheRangeWithNoHint() async throws {
        let output = try await Self.runFiles(
            #"""
            return await tools.files.read("django/db/migrations/operations/models.py", { offset: 300, limit: 110 });
            """#)

        #expect(!output.contains("must be a JS object"), "output was: \(output)")
        #expect(!output.contains("tools.name"), "output was: \(output)")
        #expect(!output.contains("getRenameEdits"), "output was: \(output)")
        #expect(!output.contains("instead."), "output was: \(output)")
        let lines = try RunOutput.decoded(ReadValue.self, from: output).lines
        #expect(lines.count == 110, "output was: \(output)")
        #expect(lines.first?.hasSuffix("line 300") == true, "output was: \(output)")
    }
}
