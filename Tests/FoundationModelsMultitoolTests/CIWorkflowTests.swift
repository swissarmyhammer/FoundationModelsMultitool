import Foundation
import Testing

/// Pins the shipped CI workflow to the shared swift-ci call.
///
/// `.github/workflows/ci.yml` must delegate to the shared
/// `swissarmyhammer/workflows/.github/workflows/swift-ci.yaml` workflow and
/// must pass the inputs that keep the real-model suite safe: the nested
/// package path `IntegrationTests`, the serial `integration-no-parallel`
/// flag, and a metallib glob. The shared workflow orders the integration
/// job after the unit job with its own `needs: test` edge, so this suite
/// pins the delegation and its inputs, not the edge.
@Suite("CI workflow")
struct CIWorkflowTests {
    @Test("the workflow calls the shared swift-ci workflow")
    func workflowCallsSharedSwiftCI() throws {
        let callsSharedWorkflow = try Self.workflowContainsLine(
            "uses: swissarmyhammer/workflows/.github/workflows/swift-ci.yaml@main"
        )
        #expect(
            callsSharedWorkflow,
            """
            .github/workflows/ci.yml must call \
            swissarmyhammer/workflows/.github/workflows/swift-ci.yaml@main.
            """
        )
    }

    @Test("the shared call names the nested integration package")
    func sharedCallNamesNestedIntegrationPackage() throws {
        let namesNestedPackage = try Self.workflowContainsLine(
            "integration-package-path: IntegrationTests"
        )
        #expect(
            namesNestedPackage,
            """
            The shared call in .github/workflows/ci.yml must pass \
            "integration-package-path: IntegrationTests".
            """
        )
    }

    @Test("the shared call sets integration-no-parallel")
    func sharedCallSetsIntegrationNoParallel() throws {
        let setsNoParallel = try Self.workflowContainsLine(
            "integration-no-parallel: true"
        )
        #expect(
            setsNoParallel,
            """
            The shared call in .github/workflows/ci.yml must pass \
            "integration-no-parallel: true".
            """
        )
    }

    @Test("the shared call passes a metallib glob")
    func sharedCallPassesMetallibGlob() throws {
        let inputKey = "integration-metallib-glob:"
        let globValue = try Self.workflowLines()
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix(inputKey) }?
            .dropFirst(inputKey.count)
            .trimmingCharacters(in: .whitespaces)
        #expect(
            globValue?.isEmpty == false,
            """
            The shared call in .github/workflows/ci.yml must pass a \
            non-empty integration-metallib-glob.
            """
        )
    }

    /// Reads `.github/workflows/ci.yml` from the repository root through
    /// `RepositoryFile.read(relativePath:)`.
    ///
    /// - Returns: each line of the workflow file.
    /// - Throws: an error when the file cannot be read.
    private static func workflowLines() throws -> [Substring] {
        let text = try RepositoryFile.read(relativePath: ".github/workflows/ci.yml")
        return text.split(separator: "\n", omittingEmptySubsequences: false)
    }

    /// Tells whether the workflow holds a line whose trimmed content equals
    /// the expected text.
    ///
    /// - Parameter expected: the line content to search for, without
    ///   indentation.
    /// - Returns: `true` when a line matches.
    /// - Throws: an error when the workflow file cannot be read.
    private static func workflowContainsLine(_ expected: String) throws -> Bool {
        try workflowLines().contains { line in
            line.trimmingCharacters(in: .whitespaces) == expected
        }
    }
}
