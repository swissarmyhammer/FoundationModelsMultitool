import Foundation
import Testing

/// Guards the Router boundary of the library target.
///
/// FoundationModelsExtras owns the tool hosting: `ToolContext`,
/// `BackgroundTool`, `ToolMount`, `SubmissionBoundaryTool`, `LostRunError`,
/// `RunPlane` and the types near them. The library target takes these types
/// from Extras, and it does not depend on FoundationModelsRouter. Of the
/// shipped targets, Router is a dependency of the application only, which is
/// the `MultitoolCLI` target.
///
/// A Router that re-exports an Extras type lets a library file that imports
/// Router still compile. Thus the build alone does not show the boundary. This
/// suite reads the manifest and the library sources, and it fails when the
/// Router dependency comes back.
///
/// The suite reads the CODE of the manifest and not its comments, because the
/// comments of the manifest tell the history of the Router dependency.
@Suite("PackageManifestTests")
struct PackageManifestTests {
    /// The manifest of this package, named from the repository root.
    private static let manifestPath = "Package.swift"

    /// The directory of the library target, named from the repository root.
    private static let librarySourcesPath = "Sources/FoundationModelsMultitool"

    /// The name the manifest gives to the library target.
    private static let libraryTargetName = "packageName"

    /// The name the manifest gives to the application library target.
    private static let applicationTargetName = "cliLibraryTargetName"

    /// The dependency declaration of the Router product, as the manifest
    /// writes it.
    private static let routerProductDeclaration = ".product(name: routerDependencyName"

    /// The import statement that the library sources must not hold.
    private static let routerImport = "import FoundationModelsRouter"

    /// The texts that start the declaration of a target in the manifest.
    private static let targetDeclarationStarts = [".target(", ".executableTarget(", ".testTarget("]

    /// The label that names a target in its declaration.
    private static let targetNameLabel = "name: "

    /// The text that starts a comment line of the manifest.
    private static let commentMarker = "//"

    @Test("the library target declares no FoundationModelsRouter dependency")
    func libraryTargetDeclaresNoRouter() throws {
        let declaration = try #require(try Self.targetDeclaration(named: Self.libraryTargetName))
        #expect(
            !declaration.contains(Self.routerProductDeclaration),
            """
            The library target links the Router product. FoundationModelsExtras \
            owns the tool hosting, thus the library takes it from there:
            \(declaration)
            """)
    }

    @Test("the MultitoolCLI target declares the FoundationModelsRouter dependency")
    func applicationTargetDeclaresRouter() throws {
        let declaration = try #require(try Self.targetDeclaration(named: Self.applicationTargetName))
        #expect(
            declaration.contains(Self.routerProductDeclaration),
            """
            The application target does not link the Router product. The \
            application makes the routed session, thus it needs Router:
            \(declaration)
            """)
    }

    @Test("no library source file imports FoundationModelsRouter")
    func librarySourcesImportNoRouter() throws {
        let sightings = try RepositoryFile.sightings(
            of: [Self.routerImport], inRelativeDirectory: Self.librarySourcesPath)
        #expect(
            sightings.isEmpty,
            """
            A library file imports Router. Import FoundationModelsExtras for \
            the tool hosting types:
            \(sightings.joined(separator: "\n"))
            """)
    }

    /// Gives the code lines of one target declaration of the manifest.
    ///
    /// A declaration starts at a line that is one of
    /// ``targetDeclarationStarts`` and holds nothing more, and it stops before
    /// the next such line. A dependency such as `.target(name: packageName),`
    /// holds more on its line, thus it does not start a declaration. The
    /// comment lines are not part of a declaration.
    ///
    /// - Parameter name: the name expression that the declaration writes
    ///   after ``targetNameLabel``, for example `packageName`.
    /// - Returns: the code lines of the declaration, or `nil` when no target
    ///   has that name.
    /// - Throws: an error when the manifest cannot be read.
    private static func targetDeclaration(named name: String) throws -> String? {
        let codeLines = try RepositoryFile.read(relativePath: manifestPath)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix(commentMarker) }
        let declarations = codeLines.reduce(into: [[String]]()) { declarations, line in
            if targetDeclarationStarts.contains(line) {
                declarations.append([line])
            } else if !declarations.isEmpty {
                declarations[declarations.count - 1].append(line)
            }
        }
        let nameLine = "\(targetNameLabel)\(name),"
        return declarations.first { $0.contains(nameLine) }?.joined(separator: "\n")
    }
}
