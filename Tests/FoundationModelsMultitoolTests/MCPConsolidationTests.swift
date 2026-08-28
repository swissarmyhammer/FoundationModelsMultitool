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
/// ported file comes from, and those comments are the history of the move.
/// `RepositoryFile.sightings(of:inRelativeFile:skippingCommentLines:)` carries
/// the comment rule and states what it counts as a comment, and the
/// `RepositoryFile` suite pins that rule.
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

    @Test("the manifest declares no FoundationModelsMCP dependency")
    func manifestDeclaresNoArchivedSibling() throws {
        let sightings = try Self.codeSightings(of: Self.archivedSiblingName)
        #expect(
            sightings.isEmpty,
            """
            The manifest names the archived \(Self.archivedSiblingName) package \
            in code. That repository is archived, and its files stand in \
            `Sources/FoundationModelsMultitool/Capabilities/MCP/` now, thus \
            each line named below must go:
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
    /// The scan is
    /// `RepositoryFile.sightings(of:inRelativeFile:skippingCommentLines:)`,
    /// with the comment lines passed over. A comment line declares nothing.
    ///
    /// - Parameter needle: the text to search for, for example a package name.
    /// - Returns: one `path:line: needle` entry for each sighting, in the order
    ///   the lines stand in the file.
    /// - Throws: an error when the manifest cannot be read.
    private static func codeSightings(of needle: String) throws -> [String] {
        try RepositoryFile.sightings(
            of: [needle], inRelativeFile: manifestPath, skippingCommentLines: true)
    }
}
