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
/// The suite guards one more fact of the same shape: this package takes the
/// wire library from a fork, and the repository the fork comes from also still
/// answers on the network. A manifest that goes back to it resolves and builds,
/// and it silently drops the correction the fork carries — see
/// ``MCPConsolidationTests/wirePackageURLDeclaration``.
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
    /// The manifest names it in `mcpPackage`. This package takes it from the
    /// `swissarmyhammer` fork of it, and no longer from the
    /// `modelcontextprotocol` original — see ``wirePackageURLDeclaration``.
    private static let wirePackageName = "swift-sdk"

    /// The product of ``wirePackageName`` that the library target and the unit
    /// test target each link.
    ///
    /// The manifest declares it one time, in `mcpProducts`.
    private static let wireProductDeclaration = #".product(name: "MCP", package: mcpPackage)"#

    /// The URL the manifest must take ``wirePackageName`` from.
    ///
    /// The fork carries the correction of card `^qba8j6x`. The original
    /// `HTTPClientTransport` keeps one `lastEventID` for all of its SSE
    /// streams together. Thus a stream that connects again asks the server for
    /// the events of a different stream. A manifest that goes back to the
    /// `modelcontextprotocol` original drops that correction, and the defect
    /// comes back with no other sign. This suite is what stops that.
    ///
    /// The text is the source the manifest holds, and not the URL the source
    /// builds: the manifest names the package with `mcpPackage`, as
    /// ``wireProductDeclaration`` above is also the source and not a value.
    /// The version requirement stands outside this text on purpose, because
    /// which revision of the fork this package builds against is free to
    /// change.
    private static let wirePackageURLDeclaration =
        #"url: "https://github.com/swissarmyhammer/\(mcpPackage).git""#

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
        try Self.expectManifestHolds(
            Self.wirePackageName,
            because: """
                The MCP capability speaks through that package, thus the \
                capability cannot build without it.
                """)

        try Self.expectManifestHolds(
            Self.wireProductDeclaration,
            because: "Each target that imports `MCP` needs that product.")
    }

    @Test("the manifest takes the swift-sdk package from the fork")
    func manifestTakesTheWirePackageFromTheFork() throws {
        try Self.expectManifestHolds(
            Self.wirePackageURLDeclaration,
            because: """
                The fork carries the correction of the `HTTPClientTransport` \
                defect of card `^qba8j6x`, thus a manifest that goes back to \
                the `modelcontextprotocol` original brings the defect back.
                """)
    }

    /// Fails when no code line of the manifest holds `text`.
    ///
    /// Each check above of a text the manifest must hold has this one shape.
    /// The text and the reason are the whole difference between them.
    ///
    /// - Parameters:
    ///   - text: the manifest text to search for.
    ///   - reason: why the manifest must hold that text. The failure message
    ///     ends with it.
    /// - Throws: an error when the manifest cannot be read.
    private static func expectManifestHolds(_ text: String, because reason: String) throws {
        let sightings = try codeSightings(of: text)
        #expect(!sightings.isEmpty, "The manifest holds no \(text) in code. \(reason)")
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
