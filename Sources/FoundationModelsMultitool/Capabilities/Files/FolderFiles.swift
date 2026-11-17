// `FolderFiles` — the public listing of the files of a folder that the ignore
// rules of git do not exclude, for a host that shows the files of a work
// folder (for example the Files view of an app).
//
// It is the same walk as the glob and grep verbs (`FileWalker`). In the work
// folder of a repository, libgit2 reads the tracked files and the untracked
// files that the ignore rules do not exclude, in the process. Thus an ignored
// folder such as `node_modules/` or `.build/` is not walked. No `git` child
// process starts. Outside a repository, a plain `FileManager` walk is used.

import Foundation

/// The files of a folder that the ignore rules of git do not exclude.
public enum FolderFiles {

    /// Lists the regular files under a folder.
    ///
    /// In the work folder of a git repository, the list holds the tracked
    /// files and the untracked files that the ignore rules (`.gitignore`,
    /// `.git/info/exclude` and the global excludes file) do not exclude.
    /// libgit2 reads them in the process, and no `git` process starts.
    /// Outside a repository, the list holds each regular file under the
    /// folder. The list never holds a symbolic link, a folder, or a file in a
    /// `.git` folder.
    ///
    /// - Parameters:
    ///   - folder: The folder to list.
    ///   - includeHidden: True to keep a path that has a component that
    ///     starts with a dot (for example `.github/ci.yml` or `.env`). The
    ///     default is false.
    /// - Returns: The paths relative to `folder`, sorted. A folder that does
    ///   not exist gives an empty list.
    public static func list(in folder: URL, includeHidden: Bool = false) async -> [String] {
        let root = FileWalker.canonicalDirectory(folder)
        guard FileWalker.isDirectory(root.path) else {
            return []
        }
        return await FileWalker.collectFiles(walkRoot: root, respectGitIgnore: true)
            .compactMap { FileWalker.relativePath(ofAbsolute: $0, under: root.path) }
            .filter { path in
                let components = path.split(separator: "/")
                return !components.contains(".git") && (includeHidden || !components.contains { $0.hasPrefix(".") })
            }
            .sorted()
    }
}
