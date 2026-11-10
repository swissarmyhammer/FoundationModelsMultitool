// `resolvedPath(_:)` — the one `realpath(3)` resolver of this package.
//
// The git capability compares the work folder of a repository with its root,
// and libgit2 gives real paths (`/private/var/...` on macOS). The resolver of
// Foundation runs the other way: `URL(fileURLWithPath: "/private/tmp")
// .resolvingSymlinksInPath().path` gives back `/tmp`. Thus each side of such a
// comparison goes through `realpath(3)`, and through this one copy of that
// step, so that two copies cannot give two different paths.

import Foundation

/// The `realpath(3)` of `path`, or `path` as it is when it cannot resolve —
/// most often because it does not exist yet.
///
/// **The one resolver of this module, and the one each caller must use.** The
/// path it gives is the physical path, with each symbolic link followed: the
/// path that the kernel resolved, and the path `/bin/pwd` prints. A test that
/// compares a printed directory with an expected one resolves the expected
/// one here.
///
/// - Parameter path: The path to resolve.
/// - Returns: The resolved path, or `path` unchanged.
func resolvedPath(_ path: String) -> String {
    guard let resolved = realpath(path, nil) else { return path }
    defer { free(resolved) }
    return String(cString: resolved)
}
