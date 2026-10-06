// `GitRepositoryLocation` — where the root of the git capability stands in
// its repository.
//
// git.md § "Decisions", item 8: the repository is the one that contains the
// root, and the root can be a subfolder of it. libgit2 names each file by its
// path in the work folder (a repository path, for example `src/a.txt`), and
// each path in a verb result is relative to the root. This type changes one
// form into the other, in both directions.
//
// git.md § "Spike result", fact 1: libgit2 gives real paths (`/private/var/...`
// on macOS), and `URL.resolvingSymlinksInPath()` removes the `/private`
// prefix. Thus both the work folder and the root go through `realpath` (the
// module resolver `resolvedPath(_:)`) before they are compared, and the
// helpers compare path parts below the work folder, never two absolute paths.

import Foundation

/// The work folder of the repository that contains the root, and the place of
/// the root in it.
///
/// A value: it holds no libgit2 handle (git.md § "Decisions", item 10). A verb
/// opens the repository from ``workDirectory`` inside its own call.
struct GitRepositoryLocation: Equatable, Sendable {

    /// The path part that names the folder itself, in a repository path and
    /// in a root path.
    private static let currentFolder = "."

    /// The path part that names the parent folder.
    private static let parentFolder = ".."

    /// The separator of path parts.
    private static let separator = "/"

    /// The work folder of the repository, as a real path (`realpath`).
    let workDirectory: URL

    /// The path parts of the root below ``workDirectory``. Empty when the
    /// root is the work folder itself.
    private let rootComponents: [String]

    /// Makes the location of `root` in the repository whose work folder is
    /// `workDirectory`, or `nil` when the root is not in that work folder.
    ///
    /// - Parameters:
    ///   - workDirectory: The work folder that libgit2 gives for the
    ///     repository.
    ///   - root: The root of the git capability.
    init?(workDirectory: URL, root: URL) {
        let canonicalWorkDirectory = resolvedPath(workDirectory.path)
        let workComponents = PathContainment.components(of: canonicalWorkDirectory)
        let rootComponents = PathContainment.components(of: resolvedPath(root.path))
        guard rootComponents.starts(with: workComponents) else { return nil }
        self.workDirectory = URL(fileURLWithPath: canonicalWorkDirectory, isDirectory: true)
        self.rootComponents = rootComponents.dropFirst(workComponents.count).map(String.init)
    }

    /// Changes a repository path into a path relative to the root.
    ///
    /// - Parameter repositoryPath: A path relative to the work folder, as
    ///   libgit2 gives it (for example `src/a.txt`).
    /// - Returns: The path relative to the root, `.` for the root itself, or
    ///   `nil` when the path is not below the root. A verb leaves such a path
    ///   out, because the root is the boundary of the capability.
    func rootRelativePath(fromRepositoryPath repositoryPath: String) -> String? {
        let components = PathContainment.components(of: repositoryPath).map(String.init)
        guard components.starts(with: rootComponents) else { return nil }
        return Self.joined(components.dropFirst(rootComponents.count))
    }

    /// Changes a path relative to the root into a repository path.
    ///
    /// The change is lexical: a `.` part is dropped, and a `..` part removes
    /// the part before it. Nothing on disk is read. A verb sends each path
    /// argument through the path guard first, thus a path that goes out of
    /// the root never reaches this helper.
    ///
    /// - Parameter rootRelativePath: A path relative to the root.
    /// - Returns: The path relative to the work folder, as libgit2 reads it,
    ///   `.` for the work folder itself, or `nil` for an absolute path and for
    ///   a path that goes above the work folder.
    func repositoryPath(fromRootRelativePath rootRelativePath: String) -> String? {
        guard !rootRelativePath.hasPrefix(Self.separator) else { return nil }
        var components = rootComponents
        for component in PathContainment.components(of: rootRelativePath) where component != Self.currentFolder {
            if component == Self.parentFolder {
                guard components.popLast() != nil else { return nil }
            } else {
                components.append(String(component))
            }
        }
        return Self.joined(components)
    }

    /// Joins path parts with the separator, or gives `.` for no part.
    ///
    /// - Parameter components: The path parts.
    /// - Returns: The path.
    private static func joined<Components: Collection<String>>(_ components: Components) -> String {
        components.isEmpty ? currentFolder : components.joined(separator: separator)
    }
}
