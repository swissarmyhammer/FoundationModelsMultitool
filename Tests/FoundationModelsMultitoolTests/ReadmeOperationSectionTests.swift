import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Guards the `## Operation tools` section of `README.md` against drift from
/// the renderer and from the dry run.
///
/// The section shows the rendered declarations of the notes fixture
/// (`Fixtures/OperationToolFixtures.swift`) and one snippet a model can write
/// over them. The golden `Goldens/OperationSurface.ts.txt` is the text the
/// renderer writes for that fixture, so each `declare function` line of the
/// section must be a line of the golden. `TypedMockDryRun` is the gate a
/// sample snippet passes before `searchTools` shows it, so the snippet of the
/// section must pass that gate over the same verbs.
@Suite("ReadmeOperationSectionTests")
struct ReadmeOperationSectionTests {
    // MARK: - Shared test constants

    /// The README, from the repository root.
    private static let readmePath = "README.md"

    /// The heading that opens the section under test.
    private static let sectionHeading = "## Operation tools"

    /// The golden of the five-verb fixture, from the repository root.
    private static let goldenPath = "Tests/FoundationModelsMultitoolTests/Goldens/OperationSurface.ts.txt"

    /// The text that opens a rendered declaration line.
    private static let declarationPrefix = "declare function "

    /// The fence that opens the JavaScript snippet of the section.
    private static let snippetFenceOpen = "```js\n"

    /// The fence that closes a fenced block.
    private static let fenceClose = "\n```"

    /// The number of operations the fixture declares, and thus the number of
    /// `declare function` lines the section must show.
    private static let verbCount = 5

    // MARK: - Helpers

    /// The `## Operation tools` section of the README: the text from its
    /// heading to the next `## ` heading, or to the end of the file.
    ///
    /// - Returns: The section text.
    /// - Throws: When the README does not read, or has no such section.
    private static func section() throws -> Substring {
        try RepositoryFile.section(headed: sectionHeading, inRelativeFile: readmePath)
    }

    /// The `declare function` lines of the section, with their indentation
    /// removed.
    ///
    /// - Returns: The lines, in section order.
    /// - Throws: What ``section()`` throws.
    private static func declarationLines() throws -> [String] {
        try section().split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix(declarationPrefix) }
    }

    /// The JavaScript snippet of the section, without its fence.
    ///
    /// - Returns: The snippet text.
    /// - Throws: What ``section()`` throws, or when the section has no
    ///   fenced `js` block.
    private static func snippet() throws -> String {
        let section = try section()
        let open = try #require(
            section.range(of: snippetFenceOpen), "The \"\(sectionHeading)\" section has no fenced js snippet.")
        let body = section[open.upperBound...]
        let close = try #require(body.range(of: fenceClose), "The fenced js snippet does not close.")
        return String(body[..<close.lowerBound])
    }

    // MARK: - The declarations

    @Test("every declare function line of the section is a line of the operation golden")
    func declarationsAreLinesOfTheGolden() throws {
        let golden = try RepositoryFile.read(relativePath: Self.goldenPath)
        let goldenLines = Set(golden.split(separator: "\n").map(String.init))

        let declarations = try Self.declarationLines()

        #expect(declarations.count == Self.verbCount)
        let missing = declarations.filter { !goldenLines.contains($0) }
        #expect(missing.isEmpty, "README lines that are not in the golden: \(missing)")
    }

    // MARK: - The snippet

    @Test("the js snippet of the section passes the typed-mock dry run over the fixture verbs")
    func snippetPassesTheDryRunOverTheFixtureVerbs() throws {
        let failure = TypedMockDryRunTests.failure(for: try Self.snippet(), against: try TypedMockDryRunTests.notesEntries())

        #expect(failure == nil, "dry run failure: \(failure ?? "")")
    }
}
