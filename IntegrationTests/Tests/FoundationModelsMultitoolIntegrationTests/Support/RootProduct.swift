import Foundation
import Testing

// MARK: - The executables of the root build
//
// This nested package builds no executable of its own over the root package,
// and a test target can depend on no executable. Thus an executable that a
// suite here starts as a child process stands in the products directory of the
// ROOT build, and not beside the test bundle of this package. CI builds each
// such product at the repository root before the integration suite runs (the
// `integration-root-products` input of `.github/workflows/ci.yml`).

/// Finds an executable that the root package builds.
enum RootProduct {

    /// The product name of the stdio MCP test server, as `../Package.swift`
    /// declares it.
    static let testServerName = "mcp-test-server"

    /// The product name of the CLI executable, as `../Package.swift` declares
    /// it.
    static let cliName = "multitool-cli"

    /// The path of the products directory of the root build, relative to the
    /// repository root.
    private static let productsDirectoryPath = ".build/debug"

    /// The repository root.
    ///
    /// `#filePath` names this file inside the checkout. Five steps up reach the
    /// repository root.
    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // Support
        .deletingLastPathComponent()  // FoundationModelsMultitoolIntegrationTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // IntegrationTests
        .deletingLastPathComponent()  // the repository root

    /// The path of the executable `name` that the root build writes.
    ///
    /// - Parameter name: The product name of the executable, as
    ///   `../Package.swift` declares it.
    /// - Returns: The path of the executable.
    /// - Throws: When no executable stands there. The failure names the command
    ///   that writes it.
    static func executablePath(named name: String) throws -> String {
        let candidate = repositoryRoot
            .appendingPathComponent(productsDirectoryPath)
            .appendingPathComponent(name)
        try #require(
            FileManager.default.isExecutableFile(atPath: candidate.path),
            """
            no \(name) executable at \(candidate.path); run \
            `swift build --product \(name)` at the repository root first.
            """)
        return candidate.path
    }
}
