import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Golden tests for ``CodeParserPlugin`` — the port of the code plugin of
/// `../swissarmyhammer/crates/swissarmyhammer-sem/src/parser/plugins/code/`.
///
/// Each case in `GitSemanticGoldens/<language>/<case>/` has a before file, an
/// after file, and the expected JSON. A throwaway Rust program wrote each
/// expected JSON with `compute_semantic_diff` of the Rust crate (tree-sitter
/// 0.26.9, tree-sitter-rust 0.24.2, tree-sitter-go 0.25.0, tree-sitter-swift
/// 0.7.2) in the shape of the sah `git` tool (`get diff`), with camelCase
/// field names. For each case with one path, the program also ran the
/// inline mode of that tool (`inline.<ext>`) and found the same JSON.
///
/// The `function-moved` case gives the old side the path `old/inline.<ext>`:
/// the matcher reports `moved` only when the file path differs, and the
/// inline mode of the tool has one path.
///
/// The Rust matcher walks a `HashMap` in phase 1, thus the order of two
/// `modified` changes is not fixed in Rust. Each case has at most one
/// `modified` change.
@Suite("CodeParserPluginGoldenTests")
struct CodeParserPluginGoldenTests {

    /// The resource folder of the cases.
    private static let goldenFolder = "GitSemanticGoldens"

    /// The name of the case whose old side has another path.
    private static let movedCaseName = "function-moved"

    /// The folder of each language, and the file extension of its cases.
    private static let languages: [(folder: String, fileExtension: String)] = [
        ("rust", ".rs"), ("go", ".go"), ("swift", ".swift"),
    ]

    /// The cases of each language.
    private static let caseNames = [
        "function-added", "function-deleted", "function-modified", "function-renamed", movedCaseName,
        "type-with-methods", "whitespace-and-comments",
    ]

    /// One case: a language folder, its file extension, and a case name.
    struct GoldenCase: CustomTestStringConvertible, Sendable {
        let language: String
        let fileExtension: String
        let name: String

        var testDescription: String { "\(language)/\(name)" }
    }

    /// Each case of each language.
    static let cases: [GoldenCase] = languages.flatMap { language in
        caseNames.map { GoldenCase(language: language.folder, fileExtension: language.fileExtension, name: $0) }
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
        let fileChange = SemanticFileChange(
            filePath: filePath, status: golden.name == Self.movedCaseName ? .renamed : .modified,
            oldFilePath: golden.name == Self.movedCaseName ? "old/\(filePath)" : nil,
            beforeContent: try Self.text("before", of: golden), afterContent: try Self.text("after", of: golden))
        let expected = try TestResource.bundledJSON(
            DiffResponse.self, named: "expected", in: "\(Self.goldenFolder)/\(golden.language)/\(golden.name)")

        let result = SemanticDiffer.computeSemanticDiff(
            fileChanges: [fileChange], registry: .makeDefault(), commitSHA: nil, author: nil)

        #expect(Self.response(of: result) == expected)
    }
}
