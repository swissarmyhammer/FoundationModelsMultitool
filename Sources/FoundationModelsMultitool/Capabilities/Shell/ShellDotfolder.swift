// `ShellDotfolder` — where the files of each layer of the `shell` dotfolder
// stand.
//
// The dotfolder is where the configuration of the shell capability stands, and
// it stands in two roots:
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
// One type resolves both roots, thus each reader of the dotfolder sees the
// same two layers and the same working directory. `ShellState` roots its
// `<cwd>/.shell` store on the `currentDirectory()` of this type for that
// reason.

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

    /// The configuration file of the shell capability inside each layer root.
    ///
    /// **Nothing reads this file yet, and the name is kept on purpose.** The
    /// write confinement of `SeatbeltSandbox.Options` — `writableRoots` and
    /// `extraWritePaths` — is stated there as configuration the host supplies,
    /// and code is the only host that supplies it today. A file the two
    /// resolvers of this type find is where that configuration is meant to
    /// come from, and this constant is the one name they resolve. So the
    /// answer to "where do the write roots come from" is this file, and the
    /// name stands until a reader gives it a body.
    ///
    /// The `.yaml` extension states the intended format. It is not a format
    /// this package can read right now: no YAML parser is a dependency of it.
    /// The reader and the parser land together.
    ///
    /// This name and the two resolvers stand or fall together. No file of
    /// `Sources/` calls `userURL(fileName:environment:)` or
    /// `projectURL(fileName:)` either, and each of the three is kept for this
    /// one reason: the reader that gives this file a body is the caller of all
    /// three. A change that deletes one of the three must read the reason on
    /// the other two again.
    static let configFileName = "config.yaml"

    /// The user-layer path of `fileName`.
    ///
    /// **No file of `Sources/` calls this yet, and it is kept on purpose.** It
    /// is the user half of the pair that finds `configFileName`, thus the
    /// reason written on that constant is the reason this resolver stands: the
    /// reader of the shell configuration file is the caller that lands, and it
    /// has to find the file in each of the two layers. `ShellDotfolderTests`
    /// holds the XDG lookup correct until then.
    ///
    /// - Parameters:
    ///   - fileName: The file to locate inside the user layer root.
    ///   - environment: The environment dictionary the resolution reads
    ///     `XDG_CONFIG_HOME` from. The default is the environment of the
    ///     process. A test gives a dictionary of its own, thus it shows that
    ///     the override works and it depends on no real state of the process.
    /// - Returns: `$XDG_CONFIG_HOME/shell/<fileName>` when that variable holds
    ///   an absolute path, and `~/.config/shell/<fileName>` in each other case.
    ///   The user layer is always there, thus the answer is never absent.
    static func userURL(
        fileName: String, environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        userLayerRoot(environment: environment).appendingPathComponent(fileName)
    }

    /// The project-layer path of `fileName`.
    ///
    /// **No file of `Sources/` calls this yet, and it is kept on purpose.** It
    /// is the project half of that same pair, thus the reason written on
    /// `configFileName` carries it too. `ShellDotfolderTests` holds the walk to
    /// the git root correct until then.
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

    /// The working directory of the process, as a directory URL.
    ///
    /// The one home of that expression. The walk to the git root starts here,
    /// and `ShellState` roots its `<cwd>/.shell` store here, thus the two read
    /// the working directory the same way.
    ///
    /// - Returns: The working directory.
    static func currentDirectory() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
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
