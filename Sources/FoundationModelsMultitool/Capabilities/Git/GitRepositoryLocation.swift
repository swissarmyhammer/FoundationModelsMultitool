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
        return Self.appending(PathContainment.components(of: rootRelativePath), to: rootComponents)
            .map { Self.joined($0) }
    }

    /// Changes the URL of a file in the work folder into a repository path.
    ///
    /// The file and ``workDirectory`` are both compared as real paths
    /// (`realpath`, git.md § "Spike result", fact 1), thus a URL in the
    /// `/var/...` spelling finds its place in a `/private/var/...` work
    /// folder. A verb gives this helper the URL that the path guard gave.
    ///
    /// The file and its folders can be absent from the disk: a verb that
    /// reads a file at an older ref names a file, or a folder, that a later
    /// commit removed. `realpath` cannot resolve an absent part, thus the
    /// helper resolves the deepest folder that the disk holds, and adds the
    /// absent parts after it.
    ///
    /// - Parameter file: The URL of a file.
    /// - Returns: The path relative to the work folder, as libgit2 reads it,
    ///   or `nil` when the file is not below the work folder.
    func repositoryPath(ofFile file: URL) -> String? {
        let workComponents = PathContainment.components(of: workDirectory.path).map(String.init)
        guard let fileComponents = Self.realComponents(of: file),
            fileComponents.count > workComponents.count, fileComponents.starts(with: workComponents)
        else {
            return nil
        }
        return Self.joined(fileComponents.dropFirst(workComponents.count))
    }

    /// The parts of the real path of a file.
    ///
    /// The parts start with `realpath` of the deepest part of the path that
    /// the disk holds: the file itself, or, for an absent file, its deepest
    /// folder on the disk. The absent parts follow, and a `.` or `..` part
    /// among them folds the same way as in
    /// ``repositoryPath(fromRootRelativePath:)``: the disk cannot resolve an
    /// absent part, and an absent part is not a symlink.
    ///
    /// - Parameter file: The URL of a file.
    /// - Returns: The parts of the real path, or `nil` when a `..` part goes
    ///   above the filesystem root.
    private static func realComponents(of file: URL) -> [String]? {
        let components = PathContainment.components(of: file.path)
        let heldCount =
            (0...components.count).last { count in
                FileManager.default.fileExists(atPath: absolutePath(of: components.prefix(count)))
            } ?? 0
        let realPrefix = PathContainment.components(of: resolvedPath(absolutePath(of: components.prefix(heldCount))))
        return appending(components.dropFirst(heldCount), to: realPrefix.map(String.init))
    }

    /// Adds path parts after a folder, one at a time: a `.` part is dropped,
    /// and a `..` part removes the part before it.
    ///
    /// - Parameters:
    ///   - components: The path parts to add.
    ///   - folder: The parts of the folder.
    /// - Returns: The parts, or `nil` when a `..` part goes above the first
    ///   part of `folder`.
    private static func appending<Components: Sequence<Substring>>(
        _ components: Components,
        to folder: [String]
    ) -> [String]? {
        var result = folder
        for component in components where component != currentFolder {
            if component == parentFolder {
                guard result.popLast() != nil else { return nil }
            } else {
                result.append(String(component))
            }
        }
        return result
    }

    /// The absolute path of some path parts.
    ///
    /// - Parameter components: The path parts, from the filesystem root.
    /// - Returns: The path, `/` for no part.
    private static func absolutePath<Components: Collection<Substring>>(of components: Components) -> String {
        separator + components.joined(separator: separator)
    }

    /// Joins path parts with the separator, or gives `.` for no part.
    ///
    /// - Parameter components: The path parts.
    /// - Returns: The path.
    private static func joined<Components: Collection<String>>(_ components: Components) -> String {
        components.isEmpty ? currentFolder : components.joined(separator: separator)
    }
}
