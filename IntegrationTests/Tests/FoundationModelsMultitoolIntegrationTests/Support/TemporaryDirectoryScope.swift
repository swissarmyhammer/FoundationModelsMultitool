import Foundation
import Synchronization
import Testing

// MARK: - The temporary folders of one test of this package
//
// Test rule T1: a fixture closes also when the test body throws. A temporary
// folder that `LiveRouterFixture.makeTempDir()` makes is a fixture, and many
// helpers of this package make one deep inside a scenario, for example
// `makeFilesAndShellSurface(over:adding:)` and `makeStubProfile(embeddingModel:pool:)`.
// The trait in this file gives each test one `ScratchFolders` through a
// task-local value, and removes the folders of that test when the test ends.
//
// The root package has the same trait (`TemporaryDirectoryScope` with
// `TestScratch`), but it stands in the unit test target, and a package can
// import only the products of another package. No test-support product of
// the root package holds a folder scope, and to move it into one changes
// each unit test file that uses it. Thus this package keeps this small copy.

/// The temporary folders of one test, removed when the test ends.
final class ScratchFolders: Sendable {

    /// The folders of the test that runs now, when the
    /// `ownsTemporaryDirectories` trait holds the test, and `nil` when no
    /// trait holds it.
    static let current = TaskLocal<ScratchFolders?>(wrappedValue: nil)

    /// Each path this test owns, in the order the test received it.
    private let ownedPaths = Mutex<[String]>([])

    /// Makes this test the owner of `url`.
    ///
    /// Take the ownership before the folder exists. Thus there is no moment
    /// in which the folder exists with no owner.
    ///
    /// - Parameter url: The path that this test owns from now on.
    /// - Returns: `url`, unchanged.
    @discardableResult
    func own(_ url: URL) -> URL {
        ownedPaths.withLock { $0.append(url.path) }
        return url
    }

    /// Removes each path this test received, and forgets it.
    ///
    /// Best effort. A test that already failed has no use for a second
    /// failure about its own cleanup.
    func removeAll() {
        let paths = ownedPaths.withLock { owned in
            defer { owned.removeAll() }
            return owned
        }
        for path in paths {
            try? FileManager.default.removeItem(atPath: path)
        }
    }
}

/// A suite trait that gives each test of the suite one ``ScratchFolders``,
/// and removes each folder of it when the test ends.
///
/// The scope removes the folders in a `defer`. Thus the folders go away when
/// the test body returns, and also when it throws or a `#require` fails. The
/// removal is synchronous, thus no work of the cleanup runs after the test
/// ended.
struct TemporaryDirectoryScope: SuiteTrait, TestTrait, TestScoping {

    /// Each test and each nested suite of the suite gets the trait.
    var isRecursive: Bool { true }

    /// The scope of one test case. A suite gets no scope of its own, because
    /// the folders belong to the tests and not to the suite.
    ///
    /// - Parameters:
    ///   - test: The test or the suite that is about to run.
    ///   - testCase: The test case that is about to run, or `nil` for a
    ///     suite.
    /// - Returns: This trait for a test case, and `nil` for a suite.
    func scopeProvider(for test: Test, testCase: Test.Case?) -> Self? {
        testCase == nil ? nil : self
    }

    /// Runs one test case with its own ``ScratchFolders`` as
    /// ``ScratchFolders/current``, and removes each folder of it after the
    /// test case, on each path.
    ///
    /// - Parameters:
    ///   - test: The test that runs.
    ///   - testCase: The test case that runs.
    ///   - function: The body of the test case.
    /// - Throws: What the body of the test case threw.
    func provideScope(
        for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void
    ) async throws {
        let folders = ScratchFolders()
        defer { folders.removeAll() }
        try await ScratchFolders.current.withValue(folders) {
            try await function()
        }
    }
}

extension Trait where Self == TemporaryDirectoryScope {

    /// Each temporary folder that a test of the suite makes through
    /// `LiveRouterFixture.makeTempDir()` is removed when the test ends, also
    /// when the test throws.
    static var ownsTemporaryDirectories: Self { Self() }
}
