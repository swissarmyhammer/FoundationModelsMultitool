// `ShellDotfolder` — where the files of each layer of the `shell` dotfolder
// stand.
//
// The policy has two artifacts on disk, and the two must agree about the
// layers or the whole model breaks: `config.yaml`, which holds the stacked
// rules the policy reads, and `decisions.yaml`, which holds the remembered
// "allow always" and "reject always" answers the decision store reads and
// writes. Both stand in the same two roots:
//
//   * user    — `$XDG_CONFIG_HOME/shell/`, or `~/.config/shell/`
//   * project — `{git_root}/.shell/`
//
// This type resolves both roots itself, and it takes no dependency on an
// external dotfolder stack. The two roots are an XDG lookup — one environment
// variable and a fallback — and a walk up to the git root. Each one is small
// enough to own here, thus this package needs no package whose real work is to
// compose several dotfolders, of which one only applies.
//
// To resolve both file names from the same two roots, one time and in one
// place, is what keeps a decision from ever going to a layer that the rules did
// not come from.

import Foundation

/// Resolves the user-layer and project-layer file paths of the `shell`
/// dotfolder.
///
/// A namespace, and not a value: each member is `static`, and each call
/// resolves again. Thus a process that changes its working directory sees the
/// layers of the place it now stands in.
enum ShellDotfolder {
    /// The name of the dotfolder: `~/.config/shell/` (or
    /// `$XDG_CONFIG_HOME/shell/`) for the user layer, and `{git_root}/.shell/`
    /// for the project layer.
    static let name = "shell"

    /// The file of stacked rules inside each layer root.
    static let configFileName = "config.yaml"

    /// The file of remembered decisions inside each layer root. It stands
    /// beside `configFileName`, thus the rules of a layer and the answers of
    /// that layer travel together.
    static let decisionsFileName = "decisions.yaml"

    /// The suffix that gives the name of the sidecar a writer locks with
    /// `flock` while it rewrites a file.
    ///
    /// A sidecar, and not the file itself, because the rewrite is an atomic
    /// replace: it renames a new file over the old one, thus a lock on the old
    /// inode would guard nothing after the rename.
    static let lockFileSuffix = ".lock"

    /// The permissions a lock sidecar takes when it is not already there:
    /// writable by the owner, readable by each user. This is the mode an editor
    /// or `touch` leaves beside the file it guards.
    ///
    /// Named here, and not written at the `open` call, because a test that
    /// stands in for a second process must take the lock on the same terms the
    /// store does, and two copies of the mode are free to drift apart.
    ///
    /// Nothing reads or writes the contents of the sidecar — a caller only
    /// locks it — thus the mode governs who may take the lock, which is already
    /// the set of users able to rewrite the file it guards.
    static let lockFileMode: mode_t = 0o644

    /// The user-layer path of `fileName`.
    ///
    /// - Parameters:
    ///   - fileName: The file to locate inside the user layer root.
    ///   - environment: The environment dictionary the resolution reads
    ///     `XDG_CONFIG_HOME` from. The default is the environment of the
    ///     process. A test gives a dictionary of its own, thus it shows that
    ///     the override works and it depends on no real state of the process.
    /// - Returns: `$XDG_CONFIG_HOME/shell/<fileName>` when that variable holds
    ///   an absolute path, and `~/.config/shell/<fileName>` in each other case.
    static func userURL(
        fileName: String, environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        userLayerRoot(environment: environment).appendingPathComponent(fileName)
    }

    /// The project-layer path of `fileName`.
    ///
    /// - Parameter fileName: The file to locate inside the project layer root.
    /// - Returns: `{git_root}/.shell/<fileName>`, or `nil` when the working
    ///   directory does not stand inside a git working tree.
    static func projectURL(fileName: String) -> URL? {
        guard let gitRoot = nearestGitRoot() else { return nil }
        return
            gitRoot
            .appendingPathComponent(".\(name)", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    /// The name of the environment variable the XDG Base Directory
    /// specification states for the user configuration root.
    private static let configHomeVariable = "XDG_CONFIG_HOME"

    /// The folder inside the home directory that the XDG specification names as
    /// the default user configuration root.
    private static let homeConfigFolder = ".config"

    /// The first character of an absolute path. The XDG specification asks for
    /// an absolute `XDG_CONFIG_HOME`, thus a value that does not open with this
    /// character is invalid and the default takes its place.
    private static let absolutePathPrefix = "/"

    /// The root directory of the user layer, as the XDG Base Directory
    /// specification states it: `<XDG_CONFIG_HOME>/shell/` when `environment`
    /// holds an absolute `XDG_CONFIG_HOME`, and `~/.config/shell/` in each
    /// other case.
    ///
    /// - Parameter environment: The environment dictionary the resolution reads
    ///   `XDG_CONFIG_HOME` from.
    /// - Returns: The root directory of the user layer.
    private static func userLayerRoot(environment: [String: String]) -> URL {
        if let configHome = environment[configHomeVariable],
            configHome.hasPrefix(absolutePathPrefix)
        {
            return URL(fileURLWithPath: configHome, isDirectory: true)
                .appendingPathComponent(name, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(homeConfigFolder, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
    }

    /// The working directory of the process, as a directory URL.
    ///
    /// - Returns: The working directory.
    private static func currentDirectory() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    }

    /// The root of the nearest git working tree, found by a walk up from the
    /// working directory.
    ///
    /// - Returns: The root of the nearest git working tree, or `nil` when the
    ///   process does not stand inside one.
    private static func nearestGitRoot() -> URL? {
        var directory = currentDirectory()
        while true {
            let gitPath = directory.appendingPathComponent(".git").path
            if FileManager.default.fileExists(atPath: gitPath) {
                return directory
            }
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path { return nil }
            directory = parent
        }
    }
}
