import Foundation
import Testing

/// Guards the exit of phase 4 of eventplan.md § "Phases": the MCP capability
/// stands in this package, and the `FoundationModelsMCP` repository is
/// archived.
///
/// An archived repository still answers on the network, thus a manifest can
/// name it again and still resolve. A guard is what stops that: this suite
/// reads the manifest and fails when the archived sibling comes back as a
/// dependency, and it fails when the wire library that replaced the sibling
/// goes away.
///
/// The suite reads the CODE of the manifest and not its comments. The manifest
/// names `FoundationModelsMCP` in four doc comments that record where each
/// ported file comes from, and those comments are the history of the move. A
/// line whose first text is `//` is a comment; every other line is code. The
/// rule is conservative: a name inside a block comment, or after code on the
/// same line, reads as code and is reported. The manifest carries neither
/// shape today, so the reader who meets such a report moves the comment onto a
/// line of its own.
///
/// This suite does not repeat `DependencyReachTests`. That suite calls
/// `MCP.Tool` and `MCP.Client`, thus it shows that the module resolves,
/// compiles and links. This one shows what the manifest DECLARES, which is the
/// fact an archive can break.
@Suite("MCPConsolidationTests")
struct MCPConsolidationTests {
    /// The manifest of this package, named from the repository root.
    private static let manifestPath = "Package.swift"

    /// The archived sibling package the MCP capability came from.
    ///
    /// eventplan.md § "Phases", phase 4: "Exit: we archive the
    /// FoundationModelsMCP repository."
    private static let archivedSiblingName = "FoundationModelsMCP"

    /// The wire library package the MCP capability speaks through.
    ///
    /// It stands under the `modelcontextprotocol` organization. The manifest
    /// names it in `mcpPackage`.
    private static let wirePackageName = "swift-sdk"

    /// The product of ``wirePackageName`` that the library target and the unit
    /// test target each link.
    ///
    /// The manifest declares it one time, in `mcpProducts`.
    private static let wireProductDeclaration = #".product(name: "MCP", package: mcpPackage)"#

    /// The text that opens a comment line of a Swift file.
    private static let commentMarker = "//"

    @Test("the manifest declares no FoundationModelsMCP dependency")
    func manifestDeclaresNoArchivedSibling() throws {
        let sightings = try Self.codeSightings(of: Self.archivedSiblingName)
        #expect(
            sightings.isEmpty,
            """
            The manifest names the archived \(Self.archivedSiblingName) package \
            in code. That repository is archived, and its files stand in \
            `Sources/FoundationModelsMultitool/Capabilities/MCP/` now, thus \
            each line below must go:
            \(sightings.joined(separator: "\n"))
            """
        )
    }

    @Test("the manifest declares the swift-sdk package and its MCP product")
    func manifestDeclaresTheWirePackage() throws {
        let packageSightings = try Self.codeSightings(of: Self.wirePackageName)
        #expect(
            !packageSightings.isEmpty,
            """
            The manifest names no \(Self.wirePackageName) package. The MCP \
            capability speaks through it, thus the capability cannot build \
            without it.
            """
        )

        let productSightings = try Self.codeSightings(of: Self.wireProductDeclaration)
        #expect(
            !productSightings.isEmpty,
            """
            The manifest declares no \(Self.wireProductDeclaration). Each \
            target that imports `MCP` needs that product.
            """
        )
    }

    /// Names each code line of the manifest that holds `needle`.
    ///
    /// A comment line holds no declaration, so the scan passes over it — see
    /// the note on the suite for what counts as a comment.
    ///
    /// - Parameter needle: the text to search for, for example a package name.
    /// - Returns: one `path:line: text` entry for each sighting, in the order
    ///   the lines stand in the file.
    /// - Throws: an error when the manifest cannot be read.
    private static func codeSightings(of needle: String) throws -> [String] {
        try RepositoryFile.read(relativePath: manifestPath)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .filter { !isComment($0.element) && $0.element.contains(needle) }
            .map { "\(manifestPath):\($0.offset + 1): \($0.element)" }
    }

    /// Says whether one line of a Swift file is a comment.
    ///
    /// - Parameter line: the line, with its indentation.
    /// - Returns: `true` when the first text of the line is `//`.
    private static func isComment(_ line: Substring) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix(commentMarker)
    }
}
