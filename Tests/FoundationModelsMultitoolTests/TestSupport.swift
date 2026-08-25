import Darwin
import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Shared scaffolding for the file-capability suites of this test target.
///
/// Collects the helpers those suites share, thus one implementation governs
/// the behavior each suite depends on. Each suite calls into this namespace
/// with its own arguments, and no suite carries a near-identical copy.
///
/// `TestScratch` (see `Fixtures/ShellStoreFixtures.swift`) also makes
/// temporary directories, and it removes them when the test ends. The file
/// suites use `makeTemporaryDirectory` instead, for two reasons. First, the
/// operating system reclaims the temporary tree, thus per-test cleanup is not
/// necessary. Second, the returned URL keeps the unresolved `/var` spelling,
/// which is the form the canonicalization checks through
/// `canonicalDirectory` start from.
enum TestSupport {
    /// The name infix an atomic writer gives to its staging files.
    ///
    /// `temporaryFileLeftovers(in:)` scans for this infix, thus a rename of
    /// the staging pattern changes one constant and no scan.
    private static let stagingFileInfix = ".tmp."

    /// Create a fresh, empty temporary directory and return its URL.
    ///
    /// The directory is created under the process temporary directory with a
    /// unique name, thus concurrent tests never collide. The operating system
    /// reclaims the temporary tree regardless of per-test cleanup. The
    /// `named` prefix makes the directory identifiable on disk as belonging
    /// to a particular suite.
    ///
    /// - Parameter name: a human-readable prefix, typically the name of the
    ///   calling suite, prepended to the unique directory name.
    /// - Returns: the URL of the freshly created temporary directory.
    static func makeTemporaryDirectory(named name: String) -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// The `realpath`-canonicalized form of an existing directory URL.
    ///
    /// A file operation that reports a path canonicalizes it with `realpath`,
    /// which resolves the firmlink that makes the `/var` prefix of the
    /// process temporary directory read back as `/private/var`. A suite that
    /// compares a path an operation *reports* against one it *builds* from
    /// the temporary root must canonicalize that root first. Without that
    /// step the two spell the same file differently.
    ///
    /// - Parameter url: an existing directory URL.
    /// - Returns: the canonicalized URL, or `url` when it cannot be resolved.
    static func canonicalDirectory(_ url: URL) -> URL {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        return url.path.withCString { path in
            guard let resolved = realpath(path, &buffer) else { return url }
            return URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
        }
    }

    /// Whether `candidate` resolves to a path *contained within* `root` — the
    /// root itself, or a genuine descendant of it — rather than merely
    /// sharing the string prefix of the root.
    ///
    /// Both URLs are standardized (collapsing `.` / `..` components), then
    /// `PathContainment` decides on whole path components. The component
    /// comparison is what rejects a *sibling* that shares the prefix of the
    /// root: for root `/tmp/test`, `/tmp/test/a` is contained but
    /// `/tmp/test-evil` is not — a bare `hasPrefix(root)` would wrongly admit
    /// the latter. A suite that must keep a path inside a root routes the
    /// check through here, thus the check and the package guards agree.
    ///
    /// - Parameters:
    ///   - candidate: the path to test for containment.
    ///   - root: the directory `candidate` must stay within.
    /// - Returns: `true` when `candidate` is `root` or a descendant of it,
    ///   and `false` in each other case.
    static func path(candidate: URL, isContainedBy root: URL) -> Bool {
        PathContainment.path(
            candidate.standardizedFileURL.path,
            isContainedBy: root.standardizedFileURL.path)
    }

    /// The absolute path of `name` directly under `root`, without creating it.
    ///
    /// - Parameters:
    ///   - name: the file name within `root`.
    ///   - root: the directory to resolve `name` against.
    /// - Returns: the resolved absolute path.
    // The ported suites of tasks ^bhgtf8t, ^7r99xf5, and ^vb4dvzp call this helper.
    // periphery:ignore
    static func path(_ name: String, in root: URL) -> String {
        root.appendingPathComponent(name, isDirectory: false).path
    }

    /// The POSIX permission bits (`mode & 0o777`) of a path.
    ///
    /// - Parameter path: the absolute path to inspect.
    /// - Returns: the permission bits, or `nil` when the attributes are
    ///   unreadable.
    static func permissionBits(_ path: String) -> Int? {
        try? FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
    }

    /// Set or clear the user-immutable (`UF_IMMUTABLE`) flag on a file.
    ///
    /// A file locked immutable makes a later `removeItem` — or a `rename`
    /// *onto* it — fail with `EPERM`, while its mode bits and the
    /// writability of its parent directory stay untouched. Thus a permission
    /// preflight on the file still passes, a staged write still lands in the
    /// parent directory, and the failure shows only when an operation commits
    /// or unlinks. That is how a test provokes a late failure without an
    /// early rejection. The owner can toggle the user flag without root.
    ///
    /// - Parameters:
    ///   - path: the file to lock or unlock.
    ///   - immutable: `true` to lock, `false` to unlock.
    /// - Returns: `true` when the flag change succeeded.
    // The ported suites of tasks ^bhgtf8t and ^7r99xf5 call this helper.
    // periphery:ignore
    @discardableResult
    static func setImmutable(_ path: String, to immutable: Bool) -> Bool {
        chflags(path, immutable ? UInt32(UF_IMMUTABLE) : 0) == 0
    }

    /// Run a `git` subcommand in a directory, and fail the test on a nonzero exit.
    ///
    /// The git-aware suites prepare a repository fixture the same way, thus
    /// the launch, the drain, and the exit check live here one time and no
    /// suite carries a near-identical copy.
    ///
    /// - Parameters:
    ///   - arguments: the `git` subcommand and its arguments.
    ///   - directory: git's working directory.
    static func runGit(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = directory
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "git \(arguments.joined(separator: " ")) failed")
    }

    /// The names of directory entries whose name marks them as a leftover
    /// temporary file.
    ///
    /// Scans `directory` for entries whose name contains the staging infix an
    /// atomic writer uses, thus a test can assert that an atomic write or a
    /// staged multi-file commit left nothing behind on a failure.
    ///
    /// - Parameter directory: the directory URL to scan.
    /// - Returns: the names of any temporary-file leftovers.
    // The ported suites of tasks ^bhgtf8t, ^p238zzp, and ^v5xap97 call this helper.
    // periphery:ignore
    static func temporaryFileLeftovers(in directory: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.contains(stagingFileInfix) }
    }
}
