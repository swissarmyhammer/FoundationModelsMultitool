import Foundation
import FoundationModels
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

// SWE-bench run noqueue24. Two snippets read a list result the way the model
// meant it rather than the way it is shaped:
//
// - django__django-13447, seq 212: `trim(s1)` reads `s.file`, `s.startLine`
//   and `s.text` off the whole `getSymbol` result, as if a `maxResults: 1`
//   query gave one symbol. The result is `{ query, symbols: [...] }`, so
//   `s.text` was `undefined`.
// - django__django-13710, seq 1351: `grep.matches[0]` on a `grepCode` that
//   matched nothing, then `m.startLine`. The list is empty; the shape is right.

/// The arguments of the stand-in `getSymbol` and `grepCode`.
@Generable
struct SymbolReadArguments {
    @Guide(description: "The symbol or the pattern.")
    var query: String?
    @Guide(description: "The pattern.")
    var pattern: String?
    @Guide(description: "The file glob.")
    var filePattern: String?
    @Guide(description: "The most results.")
    var maxResults: Int?
}

/// One symbol, with the fields of FoundationModelsCodeContext `SymbolMatch`.
@Generable
struct SymbolReadMatch {
    @Guide(description: "The name.")
    var name: String
    @Guide(description: "The qualified path.")
    var qualifiedPath: String
    @Guide(description: "The file.")
    var filePath: String
    @Guide(description: "The first line.")
    var startLine: Int
    @Guide(description: "The last line.")
    var endLine: Int
    @Guide(description: "The source.")
    var text: String
}

/// The result of the stand-in `getSymbol`: FoundationModelsCodeContext
/// `GetSymbolResult`.
@Generable
struct SymbolReadResult {
    @Guide(description: "The query.")
    var query: String
    @Guide(description: "The symbols.")
    var symbols: [SymbolReadMatch]
}

/// One grep match, with the fields of FoundationModelsCodeContext
/// `GrepCodeMatch`.
@Generable
struct SymbolReadGrepMatch {
    @Guide(description: "The file.")
    var filePath: String
    @Guide(description: "The first line.")
    var startLine: Int
    @Guide(description: "The text.")
    var text: String
}

/// The result of the stand-in `grepCode`.
@Generable
struct SymbolReadGrepResult {
    @Guide(description: "The pattern.")
    var pattern: String
    @Guide(description: "The matches.")
    var matches: [SymbolReadGrepMatch]
}

/// A stand-in for `code_context.getSymbol`: one symbol for each query, whose
/// name is the last part of the query, except `Nothing.there`, which matches
/// nothing.
struct SymbolReadGetSymbolTool: Tool {
    let name = "getSymbol"
    let description = "Gets a symbol and its source."
    func call(arguments: SymbolReadArguments) async throws -> SymbolReadResult {
        let query = arguments.query ?? ""
        guard query != "Nothing.there" else { return SymbolReadResult(query: query, symbols: []) }
        let name = String(query.split(separator: ".").last ?? "")
        let symbol = SymbolReadMatch(
            name: name, qualifiedPath: query, filePath: "django/contrib/admin/sites.py",
            startLine: 10, endLine: 20, text: "def \(name)(self, request):\n    pass")
        return SymbolReadResult(query: query, symbols: [symbol])
    }
}

/// A stand-in for `code_context.grepCode` that matches nothing.
struct SymbolReadEmptyGrepTool: Tool {
    let name = "grepCode"
    let description = "Greps the indexed code."
    func call(arguments: SymbolReadArguments) async throws -> SymbolReadGrepResult {
        SymbolReadGrepResult(pattern: arguments.pattern ?? "", matches: [])
    }
}

@Suite("SymbolResultReadAsItemTests")
struct SymbolResultReadAsItemTests {
    /// The snippet of django__django-13447 seq 212, byte for byte.
    private static let trimSnippet = """
        const s1 = await tools.code_context.getSymbol({ query: "AdminSite.index", maxResults: 1 });
        const s2 = await tools.code_context.getSymbol({ query: "AdminSite.app_index", maxResults: 1 });
        const s3 = await tools.code_context.getSymbol({ query: "AdminSite.get_app_list", maxResults: 1 });
        const s4 = await tools.code_context.getSymbol({ query: "AdminSite.each_context", maxResults: 1 });
        function trim(s){ if(!s) return null; return { file: s.file, startLine: s.startLine, endLine: s.endLine, text: s.text.slice(0, 3500) }; }
        return { s1: trim(s1), s2: trim(s2), s3: trim(s3), s4: trim(s4) };
        """

    /// The snippet of django__django-13710 seq 1351, byte for byte.
    private static let emptyGrepSnippet = """
        const grep = await tools.code_context.grepCode({ pattern: "class ForeignObjectRel", filePattern: "django/db/models/fields/related.py", maxResults: 3 });
        const m = grep.matches[0];
        const file = await tools.files.read({ path: "django/db/models/fields/related.py", offset: m.startLine, limit: 40 });
        return file.lines.join("\\n");
        """

    private struct Trimmed: Decodable, Equatable {
        let file: String
        let startLine: Int
        let endLine: Int
        let text: String
    }

    private struct TrimAnswer: Decodable {
        let s1: Trimmed
        let s2: Trimmed
        let s3: Trimmed
        let s4: Trimmed
    }

    /// Runs `code` with the files group beside the stand-in `code_context`
    /// verbs.
    private static func run(_ code: String) async throws -> String {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let registry = try MultiTool.Builder()
            .withFiles(root: root)
            .addGroup(named: "code_context", [SymbolReadGetSymbolTool(), SymbolReadEmptyGrepTool()] as [any Tool])
            .buildRegistry()
        return try await MultiTool(registry: registry).call(arguments: RunCodeArguments(code: code))
    }

    @Test("the snippet of the run: a getSymbol result read as one symbol answers from its first symbol")
    func aGetSymbolResultReadAsOneSymbolAnswersFromItsFirst() async throws {
        let output = try await Self.run(Self.trimSnippet)
        let answer = try RunOutput.decoded(TrimAnswer.self, from: output)

        let expected = Trimmed(
            file: "django/contrib/admin/sites.py", startLine: 10, endLine: 20,
            text: "def index(self, request):\n    pass")
        #expect(answer.s1 == expected, "output was: \(output)")
        #expect(answer.s4.text.hasPrefix("def each_context("), "output was: \(output)")
    }

    @Test("a symbol answers its source as text, source, code, body and snippet", arguments: ["text", "source", "code", "body", "snippet"])
    func aSymbolAnswersItsSourceUnderEachName(field: String) async throws {
        let output = try await Self.run(
            #"const r = await tools.code_context.getSymbol({ query: "AdminSite.index" }); return [r.symbols[0].\#(field), r.\#(field)];"#)

        let source = "def index(self, request):\n    pass"
        #expect(try RunOutput.decoded([String].self, from: output) == [source, source], "output was: \(output)")
    }

    @Test("a getSymbol result keeps its own fields and its list")
    func aGetSymbolResultKeepsItsOwnFields() async throws {
        let output = try await Self.run(
            #"const r = await tools.code_context.getSymbol({ query: "AdminSite.index" }); return [r.query, r.length, r[0].name, r.symbols.length];"#)

        #expect(output.contains(#"["AdminSite.index",1,"index",1]"#), "output was: \(output)")
    }

    @Test("an empty getSymbol result read as one symbol is still undefined, so `if (!s)` still sees no symbol")
    func anEmptyResultAnswersNoField() async throws {
        let output = try await Self.run(
            #"const r = await tools.code_context.getSymbol({ query: "Nothing.there" }); return [r.text === undefined, r.startLine === undefined];"#)

        #expect(output.contains("[true,true]"), "output was: \(output)")
    }

    @Test("the snippet of the run: `[0]` of an empty list names the empty list in the error")
    func anItemOfAnEmptyListNamesTheEmptyList() async throws {
        let output = try await Self.run(Self.emptyGrepSnippet)

        #expect(output.contains("evaluating 'm.startLine'"), "output was: \(output)")
        #expect(output.contains("`m` is undefined"), "output was: \(output)")
        #expect(output.contains("`grep.matches[0]`"), "output was: \(output)")
        #expect(output.contains(EmptyListHint.emptyPhrase), "output was: \(output)")
    }
}

@Suite("EmptyListHint")
struct EmptyListHintTests {
    @Test("a field read on a name that holds `[0]` of a list names that list", arguments: [
        ("const m = grep.matches[0];\nreturn m.startLine;", "m", "grep.matches[0]"),
        ("let first = refs[0]\nfirst.file", "first", "refs[0]"),
        ("var hit = (await tools.files.grep({ pattern: \"x\" })).matches[0]; hit.line", "hit",
         "(await tools.files.grep({ pattern: \"x\" })).matches[0]"),
    ])
    func aFieldOnAFirstItemNamesItsList(snippet: String, name: String, source: String) throws {
        let hint = try #require(
            EmptyListHint.hint(
                message: "undefined is not an object (evaluating '\(name).startLine')", snippet: snippet))

        #expect(hint.contains("`\(name)` is undefined"))
        #expect(hint.contains("`\(source)`"))
        #expect(hint.contains(EmptyListHint.emptyPhrase))
    }

    @Test("a direct `[0].field` read names the list", arguments: ["grep.matches[0]", "refs[0]"])
    func aDirectFirstItemReadNamesItsList(expression: String) throws {
        let hint = try #require(
            EmptyListHint.hint(
                message: "undefined is not an object (evaluating '\(expression).startLine')",
                snippet: "return \(expression).startLine;"))

        #expect(hint.contains("`\(expression)`"))
        #expect(hint.contains(EmptyListHint.emptyPhrase))
    }

    @Test("an undefined value that came from no `[0]` gets no hint")
    func anUndefinedFromElsewhereGetsNoHint() {
        #expect(
            EmptyListHint.hint(
                message: "undefined is not an object (evaluating 's.text.slice')",
                snippet: "function trim(s){ return s.text.slice(0, 10); }") == nil)
        #expect(EmptyListHint.hint(message: "Can't find variable: Buffer", snippet: "const m = a[0];") == nil)
    }
}
