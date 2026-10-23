// `ForgivingCallsTests` — the plain mistakes of a model that a `tools.*` call
// accepts rather than refuses ("Postel's rule": be liberal in what you
// accept).
//
// Each test runs the code a model wrote in SWE-bench runs bench24-1023 and
// bench24-1023b, as it wrote it, through `MultiTool.call(arguments:)` — thus
// through the JSC interpreter, the `tools.*` bindings and `ToolInvoker`. Each
// of those snippets failed and cost the model a round trip.

import Foundation
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

@Suite(.ownsTemporaryDirectories) struct ForgivingCallsTests {

    /// The name of the temporary directory of one test, thus a leaked
    /// directory is traceable to this suite.
    private static let testDirectoryName = "ForgivingCallsTests"

    /// The content of `pyproject.toml` in the fixture tree.
    private static let pyprojectContent = "[build-system]\nrequires = [\"setuptools\"]\n"

    /// The content of `tox.ini` in the fixture tree.
    private static let toxContent = "[tox]\nenvlist = py3\n"

    /// The files of the fixture tree, by path relative to the root.
    private static let fixtureFiles: [String: String] = [
        "tests/admin_views/test_adminsite.py": "import unittest\n",
        "django/contrib/admin/options.py": "class ModelAdmin:\n    verbose_name = 'x'\n",
        "django/contrib/admin/templates/admin/base.html": "<html></html>\n",
        "django/contrib/admin/templates/admin/index.html": "<html></html>\n",
        "django/utils/text.py": "def slugify(): pass\n",
        "django/utils/html.py": "def escape(): pass\n",
        "pyproject.toml": pyprojectContent,
        "tox.ini": toxContent,
    ]

    /// A session root that holds ``fixtureFiles``.
    ///
    /// - Returns: the root.
    /// - Throws: When a file does not write.
    private static func makeRoot() throws -> URL {
        let root = TestSupport.makeTemporaryDirectory(named: testDirectoryName)
        for (path, content) in fixtureFiles {
            let url = root.appendingPathComponent(path, isDirectory: false)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(content.utf8).write(to: url)
        }
        return root
    }

    /// Runs one snippet against a surface that holds the files capability.
    ///
    /// - Parameter code: the snippet, as the model wrote it.
    /// - Returns: the rendered output, as the model would read it.
    /// - Throws: whatever `MultiTool.call(arguments:)` throws.
    private static func run(_ code: String) async throws -> String {
        let registry = try MultiTool.Builder().withFiles(root: try makeRoot()).buildRegistry()
        return try await MultiTool(registry: registry).call(arguments: RunCodeArguments(code: code))
    }

    // MARK: - 1. A synonym of an argument name

    /// The part of a read result these tests read.
    private struct ReadValue: Decodable {
        let lines: [String]
    }

    @Test("files.read({ file }) reads the file, as files.read({ path }) does")
    func aFileArgumentStandsForPath() async throws {
        let output = try await Self.run(
            #"const r = await tools.files.read({ file: "tests/admin_views/test_adminsite.py" }); return r;"#)

        #expect(!output.contains("missing its required argument"), "output was: \(output)")
        let value = try RunOutput.decoded(ReadValue.self, from: output)
        #expect(value.lines.count == 1)
        #expect(value.lines.first?.hasSuffix("import unittest") == true)
    }

    @Test(
        "each usual synonym of path is accepted",
        arguments: ["filePath", "file_path", "filename", "dir", "directory", "folder", "Path"])
    func eachSynonymOfPathIsAccepted(synonym: String) async throws {
        let output = try await Self.run(
            #"const r = await tools.files.list({ \#(synonym): "django/utils" }); return r.entries;"#)

        #expect(try RunOutput.decoded([String].self, from: output) == ["html.py", "text.py"])
    }

    // MARK: - 2. files.search for files.grep

    /// The part of a grep result these tests read.
    private struct GrepValue: Decodable {
        let matchCount: Int
    }

    @Test("files.search runs files.grep")
    func filesSearchRunsGrep() async throws {
        let output = try await Self.run(
            #"const r = await tools.files.search({ pattern: "verbose_name", path: "django/contrib/admin/options.py" }); return r;"#
        )

        #expect(!output.contains("is not a function"), "output was: \(output)")
        #expect(try RunOutput.decoded(GrepValue.self, from: output).matchCount == 1)
    }

    @Test("query and regex stand for the pattern of a search", arguments: ["query", "regex"])
    func queryAndRegexStandForPattern(synonym: String) async throws {
        let output = try await Self.run(
            #"const r = await tools.files.search({ \#(synonym): "verbose_name", path: "django/contrib/admin/options.py" }); return r;"#
        )

        #expect(try RunOutput.decoded(GrepValue.self, from: output).matchCount == 1)
    }

    // MARK: - 3. A bare verb, and a single string argument

    /// The part of a list result these tests read.
    private struct ListValue: Decodable {
        let entries: [String]
    }

    @Test("tools.ls(\".\") lists the root, as files.list does")
    func bareLsListsTheRoot() async throws {
        let output = try await Self.run(#"return (await tools.ls("."))"#)

        #expect(!output.contains("is not a function"), "output was: \(output)")
        #expect(
            try RunOutput.decoded(ListValue.self, from: output).entries
                == ["django/", "pyproject.toml", "tests/", "tox.ini"])
    }

    @Test("tools.list, and tools.files.ls, list a directory too")
    func otherListNamesList() async throws {
        let output = try await Self.run(
            #"return [(await tools.list("django/utils")).entries, (await tools.files.ls("django/utils")).entries];"#)

        #expect(try RunOutput.decoded([[String]].self, from: output) == [["html.py", "text.py"], ["html.py", "text.py"]])
    }

    @Test("a bare verb that one group holds calls that verb")
    func aBareUniqueVerbCallsIt() async throws {
        let output = try await Self.run(
            #"const r = await tools.grep({ pattern: "verbose_name", path: "django" }); return r;"#)

        #expect(try RunOutput.decoded(GrepValue.self, from: output).matchCount == 1)
    }

    @Test("a single string argument is the main argument of the verb")
    func aStringArgumentIsTheMainArgument() async throws {
        let output = try await Self.run(
            #"const r = await tools.files.read("tox.ini"); const g = await tools.files.grep("verbose_name"); return [r.lines.length, g.matchCount];"#
        )

        #expect(try RunOutput.decoded([Int].self, from: output) == [2, 1])
    }

    // MARK: - 4. A read result used as its text

    /// The value of the read-as-text snippet.
    private struct TextValue: Decodable {
        let py: String
        let tox: String
    }

    @Test("string methods on a read result work on the content of the file")
    func aReadResultActsAsItsText() async throws {
        let output = try await Self.run(
            #"const py = await tools.files.read({ path: "pyproject.toml" }); const tox = await tools.files.read({ path: "tox.ini" }); return { py: py.slice(0, 2000), tox: tox.slice(0, 1500) };"#
        )

        #expect(!output.contains("is not a function"), "output was: \(output)")
        let value = try RunOutput.decoded(TextValue.self, from: output)
        #expect(value.py == String(Self.pyprojectContent.dropLast()))
        #expect(value.tox == String(Self.toxContent.dropLast()))
    }

    @Test("a read result answers length, includes, split, and template use on its text")
    func aReadResultAnswersOtherStringUses() async throws {
        let output = try await Self.run(
            #"const r = await tools.files.read({ path: "tox.ini" }); return [r.includes("envlist"), r.split("\n").length, `${r}`.startsWith("[tox]"), r.length > 0, r.lines.length];"#
        )

        #expect(try RunOutput.decoded([AnyScalar].self, from: output) == [.bool(true), .number(2), .bool(true), .bool(true), .number(2)])
    }

    // MARK: - 5. A list-shaped result used as its array

    /// The value of the glob-as-array snippet.
    private struct GlobValue: Decodable {
        let glob1: [String]
        let glob2: [String]
    }

    @Test("array methods on a glob result work on its files")
    func aGlobResultActsAsItsArray() async throws {
        let output = try await Self.run(
            #"""
            const glob1 = (await tools.files.glob({ pattern: "pyproject.toml" })).files;
            const glob2 = await tools.files.glob({ pattern: "django/contrib/admin/templates/admin/**" }); return { glob1, glob2: glob2.slice(0, 40) };
            """#)

        #expect(!output.contains("is not a function"), "output was: \(output)")
        let value = try RunOutput.decoded(GlobValue.self, from: output)
        #expect(value.glob1 == ["pyproject.toml"])
        #expect(
            value.glob2.sorted() == [
                "django/contrib/admin/templates/admin/base.html",
                "django/contrib/admin/templates/admin/index.html",
            ])
    }

    @Test("grep and list results answer map, filter, length, indexing, and for-of")
    func grepAndListResultsActAsTheirArrays() async throws {
        let output = try await Self.run(
            #"""
            const g = await tools.files.grep({ pattern: "def ", path: "django/utils" });
            const l = await tools.files.list({ path: "django/utils" });
            const seen = []; for (const e of l) { seen.push(String(e)); }
            return [g.filter((m) => m.isMatch).length, l.length, String(l[0]), l.map((e) => e.name), seen];
            """#)

        #expect(
            try RunOutput.decoded([AnyNested].self, from: output) == [
                .number(2), .number(2), .string("html.py"), .strings(["html.py", "text.py"]),
                .strings(["html.py", "text.py"]),
            ])
    }

    @Test("each entry of a list result has a name, and still reads as the string it was")
    func aListEntryHasAName() async throws {
        let output = try await Self.run(
            #"const ls = await tools.files.list({ path: "django" }); return [ls.entries.map(e => e.name), ls.entries, ls.entries.includes("utils/"), ls.entries[0].endsWith("/")];"#
        )

        #expect(
            try RunOutput.decoded([AnyNested].self, from: output) == [
                .strings(["contrib", "utils"]), .strings(["contrib/", "utils/"]), .bool(true), .bool(true),
            ])
    }
}

/// One scalar of a mixed JSON array a snippet returns.
private enum AnyScalar: Decodable, Equatable {
    case bool(Bool)
    case number(Double)
    case string(String)

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }
}

/// One element of a mixed JSON array a snippet returns: a scalar, or an array
/// of strings.
private enum AnyNested: Decodable, Equatable {
    case bool(Bool)
    case number(Double)
    case string(String)
    case strings([String])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode([String].self) {
            self = .strings(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }
}
