import Foundation
import Synchronization
import Testing

/// The `ownsTemporaryDirectories` trait removes each folder of a test when
/// the test ends: when its body returns, and also when its body throws.
///
/// Each test calls the scope of the trait directly, thus it can look at the
/// disk after the scope ended.
@Suite struct TemporaryDirectoryScopeTests {

    /// The name prefix of each folder that these tests make.
    private static let folderPrefix = "TemporaryDirectoryScopeTests"

    /// The error that a body throws to take the throw path of the scope.
    private struct BodyFailure: Error {}

    /// The folder that a body made, kept for the check after the scope.
    private final class MadeFolder: Sendable {

        /// The folder, or `nil` before the body made it.
        private let folder = Mutex<URL?>(nil)

        /// Keeps `url` as the folder that the body made.
        ///
        /// - Parameter url: The folder that the body made.
        func keep(_ url: URL) {
            folder.withLock { $0 = url }
        }

        /// The folder that the body made.
        ///
        /// - Returns: The folder, or `nil` when the body made none.
        func url() -> URL? {
            folder.withLock { $0 }
        }
    }

    /// Runs `body` in the scope of the trait, for the test that runs now.
    ///
    /// - Parameter body: The work to run in the scope.
    /// - Throws: What `body` threw.
    private static func inScope(_ body: @Sendable () async throws -> Void) async throws {
        let test = try #require(Test.current)
        try await TemporaryDirectoryScope().provideScope(
            for: test, testCase: Test.Case.current, performing: body)
    }

    /// Makes one folder through `TestSupport.makeTemporaryDirectory(named:)`,
    /// and keeps it in `made`.
    ///
    /// - Parameter made: Where the folder is kept.
    private static func makeFolder(keptIn made: MadeFolder) {
        let folder = TestSupport.makeTemporaryDirectory(named: folderPrefix)
        made.keep(folder)
        #expect(FileManager.default.fileExists(atPath: folder.path))
    }

    @Test("a folder made in the scope is removed when the body returns")
    func aFolderIsRemovedWhenTheBodyReturns() async throws {
        let made = MadeFolder()
        try await Self.inScope { Self.makeFolder(keptIn: made) }

        let folder = try #require(made.url())
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }

    @Test("a folder made in the scope is removed when the body throws")
    func aFolderIsRemovedWhenTheBodyThrows() async throws {
        let made = MadeFolder()
        await #expect(throws: BodyFailure.self) {
            try await Self.inScope {
                Self.makeFolder(keptIn: made)
                throw BodyFailure()
            }
        }

        let folder = try #require(made.url())
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }
}
