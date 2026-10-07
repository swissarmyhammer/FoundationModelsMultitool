import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Golden tests for ``CodeParserPlugin`` — the port of the code plugin of
/// `../swissarmyhammer/crates/swissarmyhammer-sem/src/parser/plugins/code/` —
/// for ``VueParserPlugin``, the port of `parser/plugins/vue.rs`, and for the
/// data plugins (JSON, YAML, TOML, CSV, Markdown) and the fallback plugin, the
/// ports of the other files in `parser/plugins/`. All cases run the differ
/// with the default registry.
///
/// Each case in `GitSemanticGoldens/<language>/<case>/` has a before file, an
/// after file, and the expected JSON. A throwaway Rust program wrote each
/// expected JSON with `compute_semantic_diff` of the Rust crate (tree-sitter
/// 0.26.9, tree-sitter-rust 0.24.2, tree-sitter-go 0.25.0, tree-sitter-swift
/// 0.7.2, tree-sitter-java 0.23.5, tree-sitter-c 0.24.2, tree-sitter-cpp
/// 0.23.4, tree-sitter-c-sharp 0.23.5, tree-sitter-ruby 0.23.1,
/// tree-sitter-php 0.24.2, tree-sitter-elixir 0.3.5, tree-sitter-bash
/// 0.25.1, tree-sitter-typescript 0.23.2, tree-sitter-javascript 0.25.0,
/// tree-sitter-python 0.25.0) in the shape of
/// the sah `git` tool (`get diff`), with camelCase field names. For each case
/// with one path, the program also ran the inline mode of that tool
/// (`inline.<ext>`) and found the same changes.
///
/// A change in the `<script>` block of a `.vue` file modifies the block
/// entity too. Thus the Vue script case adds a function: the block is the one
/// `modified` change, and the function is an `added` change.
///
/// Each case whose name ends in `-moved` (for example `function-moved`)
/// gives the old side the path `old/inline.<ext>`:
/// the matcher reports `moved` only when the file path differs, and the
/// inline mode of the tool has one path.
///
/// The Rust matcher walks a `HashMap` in phase 1, thus the order of two
/// `modified` changes is not fixed in Rust. Each case has at most one
/// `modified` change. A change to a nested entity modifies the entity that
/// holds it too. Java and C# have no method outside a type, thus their
/// `function-modified` and `whitespace-and-comments` cases put the method
/// in a `record`: a record is not an entity in Rust, thus the method is the
/// one `modified` change. An Elixir `def` is in a module, thus the Elixir
/// cases of the same names put each `def` in a `quote` block that
/// `Module.create` reads: a `quote` call is not an entity.
@Suite("CodeParserPluginGoldenTests")
struct CodeParserPluginGoldenTests {

    /// The resource folder of the cases.
    private static let goldenFolder = "GitSemanticGoldens"

    /// The end of the name of each case whose old side has another path.
    private static let movedCaseSuffix = "-moved"

    /// The name of the code case whose old side has another path.
    private static let movedCaseName = "function" + movedCaseSuffix

    /// The folder of each language, the file extension of its cases, and its
    /// cases. Some languages have more cases: a TypeScript interface and type
    /// alias, a Python decorated function and nested function, a C++
    /// namespace, a C# property, and an Elixir `defp`. Bash has no types, thus it has only the function cases.
    /// Vue has a change in the script block and a change in the template.
    ///
    /// The data formats (JSON, YAML, TOML, CSV, Markdown) and the fallback
    /// plugin (`text`, a `.txt` file) have their own cases. Some of them give
    /// no change (`files` is 0): a YAML comment, the key order of a TOML
    /// table, and a CSV header (the Rust plugin hashes each row without its
    /// header names).
    private static let languages: [(folder: String, fileExtension: String, caseNames: [String])] = [
        ("typescript", ".ts", typeCaseNames + ["interface", "type-alias"]), ("tsx", ".tsx", typeCaseNames),
        ("javascript", ".js", typeCaseNames), ("jsx", ".jsx", typeCaseNames),
        ("python", ".py", typeCaseNames + ["decorated-function", "nested-function"]),
        ("rust", ".rs", typeCaseNames), ("go", ".go", typeCaseNames), ("swift", ".swift", typeCaseNames),
        ("java", ".java", typeCaseNames), ("c", ".c", typeCaseNames),
        ("cpp", ".cpp", typeCaseNames + ["namespace"]), ("csharp", ".cs", typeCaseNames + ["property"]),
        ("ruby", ".rb", typeCaseNames), ("php", ".php", typeCaseNames),
        ("elixir", ".ex", typeCaseNames + ["private-function"]), ("bash", ".sh", functionCaseNames),
        ("vue", ".vue", ["script-change", "template-change"]),
        ("json", ".json", ["key-added", "key-deleted", "key-modified", "key-moved", "key-renamed", "whitespace-only"]),
        (
            "yaml", ".yaml",
            ["comment-only", "key-added", "key-deleted", "key-modified", "key-moved", "key-renamed", "section-modified"]
        ),
        (
            "toml", ".toml",
            [
                "key-added", "key-deleted", "key-modified", "key-order", "section-added", "section-modified",
                "section-moved", "section-renamed",
            ]
        ),
        ("csv", ".csv", ["header-changed", "row-added", "row-deleted", "row-modified", "row-moved"]),
        (
            "markdown", ".md",
            [
                "preamble-added", "section-added", "section-deleted", "section-modified", "section-moved",
                "section-renamed",
            ]
        ),
        ("text", ".txt", ["lines-added", "lines-deleted", "lines-modified", "lines-moved"]),
    ]

    /// The cases of a function: each language has them.
    private static let functionCaseNames = [
        "function-added", "function-deleted", "function-modified", "function-renamed", movedCaseName,
        "whitespace-and-comments",
    ]

    /// The cases of a language with types: the function cases and a type
    /// with methods.
    private static let typeCaseNames = functionCaseNames + ["type-with-methods"]

    /// One case: a language folder, its file extension, and a case name.
    struct GoldenCase: CustomTestStringConvertible, Sendable {
        let language: String
        let fileExtension: String
        let name: String

        var testDescription: String { "\(language)/\(name)" }
    }

    /// Each case of each language.
    static let cases: [GoldenCase] = languages.flatMap { language in
        language.caseNames.map {
            GoldenCase(language: language.folder, fileExtension: language.fileExtension, name: $0)
        }
    }

    // MARK: Expected JSON model

    /// The expected JSON: the `DiffResponse` of the sah `git` tool.
    struct DiffResponse: Codable, Equatable {

        /// The counts: `DiffSummary` of the tool.
        struct Summary: Codable, Equatable {
            let files: Int
            let added: Int
            let modified: Int
            let deleted: Int
            let moved: Int
            let renamed: Int
        }

        /// One change: `ChangeEntry` of the tool.
        struct Change: Codable, Equatable {
            let changeType: String
            let entityType: String
            let entityName: String
            let filePath: String
            let oldFilePath: String?
            let isStructuralChange: Bool?
            let entityID: String
            let beforeContent: String?
            let afterContent: String?

            /// The JSON keys of the tool: `structuralChange` and `entityId`
            /// are the camelCase names of the Rust fields.
            enum CodingKeys: String, CodingKey {
                case changeType, entityType, entityName, filePath, oldFilePath
                case isStructuralChange = "structuralChange"
                case entityID = "entityId"
                case beforeContent, afterContent
            }
        }

        let summary: Summary
        let changes: [Change]
    }

    /// The response of the Swift differ, in the shape of the expected JSON.
    private static func response(of result: DiffResult) -> DiffResponse {
        DiffResponse(
            summary: DiffResponse.Summary(
                files: result.fileCount, added: result.addedCount, modified: result.modifiedCount,
                deleted: result.deletedCount, moved: result.movedCount, renamed: result.renamedCount),
            changes: result.changes.map { change in
                DiffResponse.Change(
                    changeType: change.changeType.rawValue, entityType: change.entityType,
                    entityName: change.entityName, filePath: change.filePath, oldFilePath: change.oldFilePath,
                    isStructuralChange: change.isStructuralChange, entityID: change.entityID,
                    beforeContent: change.beforeContent, afterContent: change.afterContent)
            })
    }

    /// The text of one file of `golden`.
    private static func text(_ name: String, of golden: GoldenCase) throws -> String {
        try TestResource.bundledText(
            named: name, withExtension: "txt", in: "\(goldenFolder)/\(golden.language)/\(golden.name)")
    }

    // MARK: Golden parity

    /// The Swift differ with the default registry gives the JSON of the Rust
    /// crate for each case.
    @Test("the code plugin diff matches the Rust golden", arguments: cases)
    func theCodePluginDiffMatchesTheRustGolden(_ golden: GoldenCase) throws {
        let filePath = "inline\(golden.fileExtension)"
        let isMoved = golden.name.hasSuffix(Self.movedCaseSuffix)
        let fileChange = SemanticFileChange(
            filePath: filePath, status: isMoved ? .renamed : .modified, oldFilePath: isMoved ? "old/\(filePath)" : nil,
            beforeContent: try Self.text("before", of: golden), afterContent: try Self.text("after", of: golden))
        let expected = try TestResource.bundledJSON(
            DiffResponse.self, named: "expected", in: "\(Self.goldenFolder)/\(golden.language)/\(golden.name)")

        let result = SemanticDiffer.computeSemanticDiff(
            fileChanges: [fileChange], registry: .makeDefault(), commitSHA: nil, author: nil)

        #expect(Self.response(of: result) == expected)
    }
}
