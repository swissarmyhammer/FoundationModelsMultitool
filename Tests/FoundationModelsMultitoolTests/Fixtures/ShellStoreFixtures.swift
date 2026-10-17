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
///
/// A suite whose helpers are `static` cannot reach a stored property. Such a
/// suite takes the `ownsTemporaryDirectories` trait (see
/// `Support/TemporaryDirectoryScope.swift`) instead: the trait binds one
/// `TestScratch` to ``current`` for each test, and removes its paths when the
/// test ends.
final class TestScratch: Sendable {

    /// The scratch of the test that runs now, when the
    /// `ownsTemporaryDirectories` trait holds the test, and `nil` when no
    /// trait holds it.
    static let current = TaskLocal<TestScratch?>(wrappedValue: nil)

    /// Each path this test owns, in the order the test received it.
    private let ownedPaths = Mutex<[String]>([])

    /// Removes each path this test received.
    deinit {
        removeAll()
    }

    /// A unique path under the process temporary directory, which nothing
    /// made yet.
    ///
    /// - Parameter prefix: A short name that states the role of the path.
    ///   Thus a leaked path is traceable to the suite that made it, and is not
    ///   anonymous in `$TMPDIR`.
    /// - Returns: The path, in the `/var` spelling of the temporary directory.
    static func uniqueTemporaryPath(prefix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
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
        let candidate = own(Self.uniqueTemporaryPath(prefix: prefix))
        try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
        return candidate.resolvingSymlinksInPath()
    }

    /// Makes this test the owner of `url`, a directory or a file.
    ///
    /// Take the ownership before the path exists. Thus there is no moment in
    /// which the path exists with no owner.
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
    /// Best effort. A test that already failed has no use for a second failure
    /// about its own cleanup, and a path that the test removed itself must not
    /// become one.
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
