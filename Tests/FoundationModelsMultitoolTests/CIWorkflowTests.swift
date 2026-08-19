import Foundation
import Testing

/// Pins the shipped CI workflow to a fail-fast job order.
///
/// Both jobs in `.github/workflows/ci.yml` use the one runner label
/// `[self-hosted, macOS]`. When no `needs:` edge orders the jobs, GitHub
/// assigns the runner in an arbitrary order, so the long integration job
/// can run first while the fast unit signal waits. CI run `32285751680`
/// measured that order. This suite makes sure the `integration` job
/// declares `needs: unit`, so a later edit cannot remove the edge
/// without a red unit test.
@Suite("CI workflow")
struct CIWorkflowTests {
    @Test("the integration job declares needs: unit")
    func integrationJobDeclaresNeedsUnit() throws {
        let block = try Self.jobBlock(named: "integration")
        let declaresNeedsUnit = block.contains { line in
            line.trimmingCharacters(in: .whitespaces) == "needs: unit"
        }
        #expect(
            declaresNeedsUnit,
            "The integration job in .github/workflows/ci.yml must declare \"needs: unit\"."
        )
    }

    /// The indentation of a job's own keys (`runs-on:`, `needs:`, `steps:`).
    /// A content line with less indentation opens the next job or the next
    /// top-level key, so it ends the current job block.
    private static let jobKeyIndentation = "    "

    /// Reads `.github/workflows/ci.yml` from the repository root through
    /// `RepositoryFile.read(relativePath:)`.
    ///
    /// - Returns: each line of the workflow file.
    /// - Throws: an error when the file cannot be read.
    private static func workflowLines() throws -> [Substring] {
        let text = try RepositoryFile.read(relativePath: ".github/workflows/ci.yml")
        return text.split(separator: "\n", omittingEmptySubsequences: false)
    }

    /// Collects the lines of one job block: the lines under the job's own
    /// key, up to the next content line that stands outside the job.
    ///
    /// - Parameter name: the job key, for example `"integration"`.
    /// - Returns: every line inside that job's block.
    /// - Throws: `CIWorkflowTestsError` when the workflow holds no job with
    ///   that name.
    private static func jobBlock(named name: String) throws -> [Substring] {
        let lines = try Self.workflowLines()
        let jobKey = "  \(name):"
        guard let jobKeyIndex = lines.firstIndex(of: Substring(jobKey)) else {
            throw CIWorkflowTestsError(message: "ci.yml has no job named \"\(name)\".")
        }

        var block: [Substring] = []
        for line in lines[lines.index(after: jobKeyIndex)...] {
            if Self.endsJobBlock(line) { break }
            block.append(line)
        }
        return block
    }

    /// Tells whether a line ends a job block. A blank line and a comment
    /// line continue the block. A content line with less indentation than a
    /// job key ends it.
    private static func endsJobBlock(_ line: Substring) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return false }
        return !line.hasPrefix(Self.jobKeyIndentation)
    }
}

/// A parse failure reading `.github/workflows/ci.yml`.
private struct CIWorkflowTestsError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
