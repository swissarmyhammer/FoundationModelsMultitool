import Foundation
import Testing

/// Guards the Router boundary of the library target.
///
/// FoundationModelsExtras owns the tool hosting: `ToolContext`,
/// `BackgroundTool`, `ToolMount`, `SubmissionBoundaryTool`, `LostRunError`,
/// `RunPlane` and the types near them. The library target takes these types
/// from Extras, and it does not depend on FoundationModelsRouter. No shipped
/// target links Router. Only the test support code and the test target link
/// it.
///
/// A Router that re-exports an Extras type lets a library file that imports
/// Router still compile. Thus the build alone does not show the boundary. This
/// suite reads the manifest and the library sources, and it fails when the
/// Router dependency comes back.
///
/// The suite also guards the telemetry boundary. A library uses the telemetry
/// APIs only: `swift-log` and `swift-metrics`, and `swift-distributed-tracing`
/// through FoundationModelsExtras. Only an executable links `swift-otel` and
/// bootstraps an exporter, and this package ships no executable: the one
/// executable target is the stdio MCP test server of the test support code.
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

    @Test("the one executable target is the stdio MCP test server")
    func theOneExecutableTargetIsTheTestServer() throws {
        let executables = try Self.declarations()
            .filter { $0.first == Self.executableDeclarationStart }
            .map { $0.joined(separator: "\n") }
        let testServer = try #require(try Self.targetDeclaration(named: Self.testServerExecutableTargetName))
        #expect(
            executables == [testServer],
            """
            The package ships no executable. Only the stdio MCP test server of \
            the test support code is an executable target. These are:
            \(executables.joined(separator: "\n\n"))
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

    @Test("the library target links the swift-log and swift-metrics products")
    func libraryTargetLinksTheTelemetryAPIs() throws {
        let declaration = try #require(try Self.targetDeclaration(named: Self.libraryTargetName))
        #expect(
            declaration.contains(Self.telemetryProductsName),
            """
            The library target does not link \(Self.telemetryProductsName). The \
            library logs through swift-log and records metrics through \
            swift-metrics:
            \(declaration)
            """)
        let products = try #require(try Self.productGroupDeclaration(named: Self.telemetryProductsName))
        for product in Self.telemetryProductDeclarations {
            #expect(
                products.contains(product),
                """
                \(Self.telemetryProductsName) does not list \(product):
                \(products)
                """)
        }
    }

    @Test("no library target links a swift-otel product")
    func noLibraryTargetLinksOTel() throws {
        let libraryDeclarations = try Self.declarations().filter { $0.first == Self.libraryDeclarationStart }
        #expect(!libraryDeclarations.isEmpty, "The manifest declares no library target.")
        for declaration in libraryDeclarations.map({ $0.joined(separator: "\n") }) {
            #expect(
                !declaration.lowercased().contains(Self.otelMarker),
                """
                A library target links swift-otel. Only an executable bootstraps \
                an exporter; a library uses the telemetry APIs only:
                \(declaration)
                """)
        }
    }

    /// The text that starts the declaration of an executable target.
    private static let executableDeclarationStart = ".executableTarget("

    /// The name the manifest gives to the executable target of the stdio MCP
    /// test server.
    private static let testServerExecutableTargetName = "testServerExecutableName"

    /// The name the manifest gives to the product group of the telemetry
    /// APIs.
    private static let telemetryProductsName = "telemetryProducts"

    /// The product declarations that the telemetry product group must hold.
    private static let telemetryProductDeclarations = [
        #".product(name: "Logging", package: loggingPackage)"#,
        #".product(name: "Metrics", package: metricsPackage)"#,
    ]

    /// The text that starts the declaration of a library target.
    private static let libraryDeclarationStart = ".target("

    /// The lowercase text that each swift-otel package name, product name
    /// and group name holds.
    private static let otelMarker = "otel"

    /// The text that stops the declaration of a product group.
    private static let productGroupEnd = "]"

    /// Gives the code lines of one target declaration of the manifest.
    ///
    /// - Parameter name: the name expression that the declaration writes
    ///   after ``targetNameLabel``, for example `packageName`.
    /// - Returns: the code lines of the declaration, or `nil` when no target
    ///   has that name.
    /// - Throws: an error when the manifest cannot be read.
    private static func targetDeclaration(named name: String) throws -> String? {
        let nameLine = "\(targetNameLabel)\(name),"
        return try declarations().first { $0.contains(nameLine) }?.joined(separator: "\n")
    }

    /// Gives the code lines of each target declaration of the manifest.
    ///
    /// A declaration starts at a line that is one of
    /// ``targetDeclarationStarts`` and holds nothing more, and it stops before
    /// the next such line. A dependency such as `.target(name: packageName),`
    /// holds more on its line, thus it does not start a declaration. The
    /// comment lines are not part of a declaration.
    ///
    /// - Returns: the code lines of each declaration, in manifest order.
    /// - Throws: an error when the manifest cannot be read.
    private static func declarations() throws -> [[String]] {
        try codeLines().reduce(into: [[String]]()) { declarations, line in
            if targetDeclarationStarts.contains(line) {
                declarations.append([line])
            } else if !declarations.isEmpty {
                declarations[declarations.count - 1].append(line)
            }
        }
    }

    /// Gives the code lines of one product group of the manifest, for
    /// example `private let shellProducts: [Target.Dependency] = [`.
    ///
    /// The declaration starts at the line that declares the group, and it
    /// stops at the first line that is ``productGroupEnd``.
    ///
    /// - Parameter name: the name of the group.
    /// - Returns: the code lines of the declaration, or `nil` when the
    ///   manifest declares no group with that name.
    /// - Throws: an error when the manifest cannot be read.
    private static func productGroupDeclaration(named name: String) throws -> String? {
        let lines = try codeLines()
        let groupStart = "private let \(name): [Target.Dependency] = ["
        guard let start = lines.firstIndex(of: groupStart) else { return nil }
        let end = lines[start...].firstIndex(of: productGroupEnd) ?? lines.endIndex
        return lines[start..<end].joined(separator: "\n")
    }

    /// Gives the code lines of the manifest, trimmed, with the comment lines
    /// passed over.
    ///
    /// - Returns: the code lines, in manifest order.
    /// - Throws: an error when the manifest cannot be read.
    private static func codeLines() throws -> [String] {
        try RepositoryFile.read(relativePath: manifestPath)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix(commentMarker) }
    }
}
