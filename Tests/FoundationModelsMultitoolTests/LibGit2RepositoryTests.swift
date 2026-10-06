import Foundation
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Coverage for the `LibGit2` layer of the git capability (git.md, decision
/// 10): `LibGit2Repository` opens the repository that contains a folder, and
/// a failed libgit2 call becomes a `LibGit2Error` with the libgit2 text.
///
/// Each test makes its own temporary repository or folder, thus the tests are
/// independent and they run in parallel safely.
@Suite("LibGit2RepositoryTests")
struct LibGit2RepositoryTests {

    /// The name of the temporary folder of one test. Thus a leaked folder is
    /// traceable to this suite.
    private static let testDirectoryName = "LibGit2RepositoryTests"

    /// The subfolder of the repository that a test opens from.
    private static let subfolder = "src/deep"

    /// The text that libgit2 1.9 gives when no folder above the start folder
    /// holds a repository.
    private static let notFoundText = "could not find repository"

    /// Discovery searches the parent folders: a subfolder of the work folder
    /// opens the repository above it, and the work folder that libgit2 gives
    /// is the work folder of that repository.
    @Test("discovery from a subfolder opens the repository above it")
    func discoveryFromASubfolderOpensTheRepositoryAboveIt() throws {
        let repository = try TemporaryGitRepository()
        try repository.write("one\n", to: "\(Self.subfolder)/a.txt")
        let start = repository.workDirectory.appendingPathComponent(Self.subfolder, isDirectory: true)

        let opened = try LibGit2Repository(discoveringFrom: start)

        let workDirectory = try #require(opened.workDirectory)
        #expect(resolvedPath(workDirectory.path) == resolvedPath(repository.workDirectory.path))
    }

    /// A failed libgit2 call becomes a Swift error that carries the libgit2
    /// code and the libgit2 text, thus a caller can tell "no repository"
    /// from another fault, and can show why.
    @Test("a libgit2 failure becomes a LibGit2Error with the libgit2 text")
    func aLibGit2FailureBecomesALibGit2ErrorWithTheLibGit2Text() throws {
        let outside = TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName)

        let error = try #require(throws: LibGit2Error.self) {
            try LibGit2Repository(discoveringFrom: outside)
        }

        #expect(error.isNotFound)
        #expect(error.message.contains(Self.notFoundText), "message was: \(error.message)")
        #expect(error.description.contains(error.message))
    }
}
