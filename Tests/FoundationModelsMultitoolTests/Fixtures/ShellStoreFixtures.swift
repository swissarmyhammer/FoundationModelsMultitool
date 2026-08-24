import Foundation
import Synchronization

// MARK: - Shell scratch fixtures
//
// The shell capability writes to disk — an output buffer, a history file, the
// working directory a command runs in, the subpaths a sandbox grants. Thus
// each test that drives one needs a directory of its own, and each directory
// must go away when that test ends. `TestScratch` owns those directories.

/// The temporary directories of one test, removed when that test ends.
///
/// Hold it as a stored property of the suite:
///
/// ```swift
/// @Suite struct SomeTests {
///     private let scratch = TestScratch()
///
///     private func makeRoot() throws -> URL {
///         try scratch.makeDirectory(prefix: "some-tests")
///     }
/// }
/// ```
///
/// swift-testing makes a new suite value for each `@Test`, and it releases that
/// value when the test returns — passed, failed, or thrown. Thus a
/// `TestScratch` held on the suite is deinitialized at the moment its
/// directories stop being necessary, and a test that makes several directories
/// registers none of them by hand.
///
/// The directory becomes owned inside the same call that makes it. Thus there
/// is no moment in which a directory exists with no owner. That moment is what
/// a `defer` written at the end of a setup step gets wrong: a step that throws
/// when three directories of five exist leaks all three, and the leak shows
/// only on the failing path.
///
/// A reference type, and `Sendable`, because swift-testing runs the tests of
/// one suite in parallel and thus makes the suite type `Sendable`.
final class TestScratch: Sendable {

    /// Each path this test owns, in the order the test received it.
    private let ownedPaths = Mutex<[String]>([])

    /// Removes each directory this test received.
    ///
    /// Best effort. A test that already failed has no use for a second failure
    /// about its own cleanup, and a directory that the test removed itself must
    /// not become one.
    deinit {
        for path in ownedPaths.withLock({ $0 }) {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    /// Makes a unique temporary directory that this test owns.
    ///
    /// - Parameter prefix: A short name that states the role of the directory.
    ///   Thus a leaked directory is traceable to the suite that made it, and is
    ///   not anonymous in `$TMPDIR`.
    /// - Returns: The new directory, with each symbolic link resolved. The
    ///   resolved form is what a test compares with, because the shell
    ///   capability resolves the paths it takes.
    /// - Throws: When the directory does not create.
    func makeDirectory(prefix: String) throws -> URL {
        let candidate = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)

        let resolved = candidate.resolvingSymlinksInPath()
        ownedPaths.withLock { $0.append(resolved.path) }
        return resolved
    }
}
