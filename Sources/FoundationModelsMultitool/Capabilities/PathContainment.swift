// `PathContainment` — the one component-wise path-containment check of this
// package.
//
// Three call sites answer the same question: is a path the root itself, or a
// descendant of it? `PathGuard.ensureWorkspaceBoundary` bounds a file path to
// the workspace roots, `SeatbeltSandbox` bounds a working directory to its
// writable roots, and the test target's `TestSupport` bounds a candidate to a
// test root. Each one formerly carried its own private copy of the
// comparison. This file holds the single implementation, thus the guards
// cannot drift apart.
//
// Containment is decided on whole path components, and never on the prefix
// of a text. A string-prefix check wrongly reports `/a/bc` as inside `/a/b`,
// because the two share text. These guards are security boundaries, thus the
// weak form is not acceptable anywhere.

/// The component-wise path-containment check the package guards share.
///
/// Containment is decided on whole path components, and never on the prefix
/// of a text: `/a/bc` is not inside `/a/b`, though the two share text.
///
/// This check does not resolve `.` or `..`, does not touch the file system,
/// and does not require an absolute path. A caller that needs one of those
/// guarantees establishes it first: `PathGuard` canonicalizes both sides,
/// `SeatbeltSandbox` refuses a relative or traversal path outright, and
/// `TestSupport` standardizes both URLs.
enum PathContainment {
    /// The non-empty path components of `path`.
    ///
    /// An empty component — from a separator at the end, or from two
    /// separators together — is dropped, thus `/a/b/` and `/a//b` break
    /// down the same way as `/a/b`.
    ///
    /// - Parameter path: the path to break down.
    /// - Returns: the components that are not empty, in order.
    static func components(of path: String) -> [Substring] {
        path.split(separator: "/", omittingEmptySubsequences: true)
    }

    /// Whether `path` is `root` itself, or sits below it.
    ///
    /// - Parameters:
    ///   - path: the path to test for containment.
    ///   - root: the directory `path` must sit inside.
    /// - Returns: `true` when the components of `path` start with the
    ///   components of `root`.
    static func path(_ path: String, isContainedBy root: String) -> Bool {
        components(of: path).starts(with: components(of: root))
    }
}
