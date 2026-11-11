// `FileWalker` — the shared search-root resolution and git-aware walk of
// the files capability.
//
// A behavioral port of `../FoundationModelsFileTool/Sources/FileTool/
// FileWalker.swift`, unchanged in behavior. The callers are `GlobEngine`
// (landed with the glob task, ^4cmvjqh), `FileChangeJournal` (through
// `canonicalDirectory`), and the `FileWalkerTests` suite; the sibling's
// `GrepEngine` consumer arrives with the grep task (^2j06zb7).
//
// eventplan.md § "Consolidation of the siblings": the glob and grep verbs
// resolve, bound, and enumerate a search root the same way, thus the steps
// they share live here one time rather than as copies.
//
// The git-aware listing reads the repository through the `LibGit2` layer in
// the process, and starts no `git` child process: in the App Sandbox the
// `/usr/bin/git` shim refuses to run, and a Mac with no developer tools has
// no git.

import Darwin
import Foundation
import Logging

/// The shared search-root resolution and git-aware walk behind the glob and grep engines.
///
/// Both engines resolve, bound, and enumerate a search root the same way,
/// thus the steps they share live here one time rather than as copies:
///
/// - **Root resolution** — ``resolveRequestedPath(_:in:validate:)`` turns a
///   requested `path` (or the session root, when absent) into a validated
///   URL, and ``boundDirectory(_:in:)`` refuses the filesystem root before
///   returning a canonical directory URL.
/// - **Enumeration** — when a repository is present and its ignore rules are
///   being honored, the git-aware listing is used: libgit2 reads the index
///   and the untracked files that the ignore rules do not exclude, in the
///   process (``LibGit2Repository/listedFiles()``). Thus ignored files — and,
///   crucially, whole ignored directories such as a `build/` tree — are
///   never descended into; otherwise a plain `FileManager` walk is used.
///   Each enumeration gives only regular files (see ``isRegularFile(_:)``).
/// - **Collect-filter-assemble** — ``walkAndFilter(walkRoot:sessionRoot:respectGitIgnore:excludePatterns:accept:build:)``
///   is the single loop that enumerates, computes relative paths, skips the
///   files that the host ``ExcludePatterns`` exclude, applies a
///   caller-supplied acceptance predicate, and builds a caller-supplied
///   result type, thus neither engine hand-rolls that loop.
///
/// Sharing all of this in one place keeps the two engines byte identical and
/// means the "unscoped grep never touches the ignored `build/` directory"
/// fix and the firmlink-aware ``canonicalDirectory(_:)`` resolution live in
/// exactly one implementation.
///
/// The type is a pure namespace of stateless static helpers; it holds no
/// state and is never instantiated.
enum FileWalker {
    // MARK: Filesystem walk

    /// Enumerates the candidate files under a search root as absolute paths.
    ///
    /// When `respectGitIgnore` is set and `walkRoot` is inside the work
    /// folder of a git repository, the git-aware listing is used: libgit2
    /// reads the tracked files and the untracked files that the ignore rules
    /// do not exclude, in the process. Thus ignored files are skipped without
    /// hand-rolled gitignore parsing. Otherwise, and whenever libgit2 cannot
    /// read the listing or the directory is not in a work folder, a plain
    /// `FileManager` walk is used. Each of the two gives only the regular
    /// files that the folder holds now.
    ///
    /// - Parameters:
    ///   - walkRoot: the canonical search root.
    ///   - respectGitIgnore: whether to prefer the git-aware listing.
    /// - Returns: the absolute paths of the candidate regular files.
    static func collectFiles(walkRoot: URL, respectGitIgnore: Bool) async -> [String] {
        if respectGitIgnore, let relativePaths = gitListedFiles(in: walkRoot) {
            return relativePaths.map { walkRoot.path + "/" + $0 }
        }
        return enumeratedRegularFiles(under: walkRoot)
    }

    /// Walks the files under a root, keeps those the predicate accepts, and builds a result for each.
    ///
    /// Enumerates the candidate files under `walkRoot` via
    /// ``collectFiles(walkRoot:respectGitIgnore:)``, computes each file's
    /// path relative to the walk root and to `sessionRoot` (skipping any
    /// that fall outside either), skips a file that `excludePatterns`
    /// excludes, offers the walk-relative pair to `accept`, and — for the
    /// accepted files — hands the session-relative pair to `build`,
    /// collecting the non-`nil` results in enumeration order. `build` may
    /// return `nil` to drop a file (for example when an attribute it needs
    /// cannot be read).
    ///
    /// This is the single collect-filter-assemble loop both engines share:
    /// the enumeration, the two relative-path computations, the host
    /// exclude patterns, and the skip-on-outside bookkeeping live here one
    /// time, while each engine supplies its own acceptance predicate and its
    /// own result type through the closures.
    ///
    /// The host patterns go through ``ExcludePatterns`` here and not through
    /// the ignore rules of the repository, because an ignore rule applies to
    /// untracked files only, and the plain walk does not read the repository.
    /// Thus one matcher applies the host patterns to each walk.
    ///
    /// - Parameters:
    ///   - walkRoot: the canonical directory to enumerate.
    ///   - sessionRoot: the canonical session root the built results are relative to.
    ///   - respectGitIgnore: whether a present repository's ignore rules are
    ///     honored. It does not turn off `excludePatterns`: the model sets
    ///     `respectGitIgnore` in a call, but the host patterns are the rule
    ///     of the host, and the model must not turn them off.
    ///   - excludePatterns: the host exclude patterns, matched against the
    ///     path relative to `sessionRoot`; they apply whatever
    ///     `respectGitIgnore` says.
    ///   - accept: whether to keep a file, given its absolute path and its walk-relative path.
    ///   - build: builds a result from a kept file's absolute path and its
    ///     session-relative path, or `nil` to drop it.
    /// - Returns: the built results, in enumeration order.
    static func walkAndFilter<Element>(
        walkRoot: URL,
        sessionRoot: URL,
        respectGitIgnore: Bool,
        excludePatterns: ExcludePatterns,
        accept: (_ absolutePath: String, _ walkRelativePath: String) -> Bool,
        build: (_ absolutePath: String, _ sessionRelativePath: String) -> Element?
    ) async -> [Element] {
        var results: [Element] = []
        for absolute in await collectFiles(walkRoot: walkRoot, respectGitIgnore: respectGitIgnore) {
            guard let relativeToWalk = relativePath(ofAbsolute: absolute, under: walkRoot.path) else { continue }
            guard let relativeToSession = relativePath(ofAbsolute: absolute, under: sessionRoot.path) else { continue }
            guard !excludePatterns.excludes(relativePath: relativeToSession) else { continue }
            guard accept(absolute, relativeToWalk) else { continue }
            guard let element = build(absolute, relativeToSession) else { continue }
            results.append(element)
        }
        return results
    }

    /// The repository-listed files under a directory, or `nil` when no
    /// work folder of a repository holds it.
    ///
    /// Reads the listing of the repository that contains the directory
    /// through libgit2 in the process (``LibGit2Repository/listedFiles()``),
    /// and starts no child process. The listing holds the tracked files and
    /// the untracked files that the ignore rules do not exclude: the same
    /// files that the file listing of the git command line gives with
    /// `--cached --others --exclude-standard`. This
    /// function keeps the files below the directory, and makes each path
    /// relative to it.
    ///
    /// The function also keeps only the paths that are regular files of the
    /// work folder now (``isRegularFile(_:)``), the same as the plain walk.
    /// Thus a tracked file that the work folder no longer holds, a gitlink
    /// (the folder of a submodule), and a tracked symbolic link are not in
    /// the result, and the result does not change with the presence of a
    /// repository.
    ///
    /// A folder outside a repository, a bare repository, a folder in the
    /// repository data (the `.git` folder), and a listing that libgit2 cannot
    /// read each give `nil`, thus the caller falls back to a plain walk.
    ///
    /// - Parameter directory: the canonical directory to list.
    /// - Returns: the paths relative to `directory`, or `nil` when the
    ///   caller must walk the directory.
    private static func gitListedFiles(in directory: URL) -> [String]? {
        guard let repository = openRepository(containing: directory),
            let prefix = workFolderPrefix(of: directory, in: repository),
            let listed = readListing(of: repository)
        else {
            return nil
        }
        return listed.compactMap { path in relativePath(ofAbsolute: path, under: prefix) }
            .filter { path in !path.isEmpty && isRegularFile(directory.appendingPathComponent(path)) }
    }

    /// Opens the repository that contains a directory, or gives `nil` when
    /// libgit2 cannot open one.
    ///
    /// A directory that no repository contains (``LibGit2Error/isNotFound``)
    /// is the usual case, and gives `nil` with no log record. Each other
    /// failure gives `nil` and an `error` log record, thus the caller uses
    /// the plain walk and a developer can see why.
    ///
    /// - Parameter directory: the canonical directory to start the search at.
    /// - Returns: the open repository, or `nil` when the caller must walk the
    ///   directory.
    private static func openRepository(containing directory: URL) -> LibGit2Repository? {
        do {
            return try LibGit2Repository(discoveringFrom: directory)
        } catch {
            if !error.isNotFound { logListingFailure(error) }
            return nil
        }
    }

    /// The listing of a repository, or `nil` when libgit2 cannot read it.
    ///
    /// libgit2 opened the repository, thus a failure to read the index or
    /// the status is unexpected. It gives `nil` and an `error` log record,
    /// thus the caller uses the plain walk and a developer can see why.
    ///
    /// - Parameter repository: the open repository.
    /// - Returns: the paths relative to the work folder, or `nil` when the
    ///   caller must walk the directory.
    private static func readListing(of repository: LibGit2Repository) -> [String]? {
        do {
            return try repository.listedFiles()
        } catch {
            logListingFailure(error)
            return nil
        }
    }

    /// Writes the `error` log record of a git-aware listing that libgit2
    /// could not give.
    ///
    /// The record holds the type and the code of the error, and not its
    /// text, because the text can name a path of the user.
    ///
    /// - Parameter error: the libgit2 failure.
    private static func logListingFailure(_ error: LibGit2Error) {
        MultitoolTelemetry.logger.log(
            .fileListingReadFailed, level: .error, metadata: MultitoolTelemetry.errorMetadata(of: error))
    }

    /// The path of a directory relative to the work folder of a repository,
    /// or `nil` when the repository has no work folder or the work folder
    /// does not hold the directory.
    ///
    /// libgit2 gives real paths (`/private/var/...` on macOS), thus each
    /// side of the comparison goes through ``resolvedPath(_:)``. A directory
    /// in the repository data is in no work folder, also when the repository
    /// data is below the work folder.
    ///
    /// - Parameters:
    ///   - directory: the directory to find in the work folder.
    ///   - repository: the open repository.
    /// - Returns: the relative path (empty for the work folder itself), or
    ///   `nil` when no work folder of `repository` holds `directory`.
    private static func workFolderPrefix(of directory: URL, in repository: LibGit2Repository) -> String? {
        guard let workDirectory = repository.workDirectory else { return nil }
        let resolvedDirectory = resolvedPath(directory.path)
        let repositoryData = resolvedPath(repository.repositoryDirectory.path)
        guard relativePath(ofAbsolute: resolvedDirectory, under: repositoryData) == nil else { return nil }
        return relativePath(ofAbsolute: resolvedDirectory, under: resolvedPath(workDirectory.path))
    }

    /// The absolute paths of the regular files under a directory, walked recursively.
    ///
    /// Directories are traversed but only regular files are returned
    /// (``isRegularFile(_:)``), thus the result is directly comparable to the
    /// git-aware listing, which applies the same test.
    ///
    /// - Parameter root: the canonical search root to walk.
    /// - Returns: the absolute paths of the regular files found.
    private static func enumeratedRegularFiles(under root: URL) -> [String] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [],
                errorHandler: nil
            )
        else {
            return []
        }
        var paths: [String] = []
        for case let url as URL in enumerator where isRegularFile(url) {
            paths.append(url.path)
        }
        return paths
    }

    /// Whether a path names a regular file now.
    ///
    /// The test does not follow a symbolic link: a link is not a regular
    /// file, also when it points at one. A path with no entry, and a path
    /// whose attributes cannot be read, are not regular files. The plain walk
    /// and the git-aware listing both apply this test, thus the two give the
    /// same kind of entry.
    ///
    /// - Parameter url: the file URL to test.
    /// - Returns: `true` when the path names a regular file.
    private static func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
    }

    // MARK: Filesystem probes

    /// The canonical directory URL for a path, with symlinks fully resolved.
    ///
    /// Uses `realpath`, which resolves the firmlinks (`/var`, `/tmp`) that
    /// `URL.resolvingSymlinksInPath()` leaves untouched, thus the returned
    /// prefix matches the paths a `FileManager` enumerator yields. Falls
    /// back to the input URL when the path cannot be resolved (for example a
    /// nonexistent directory, which the caller rejects separately).
    ///
    /// - Parameter url: the directory URL to canonicalize.
    /// - Returns: the canonical directory URL, or `url` when `realpath` fails.
    static func canonicalDirectory(_ url: URL) -> URL {
        guard let resolved = realpath(url.path, nil) else { return url }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
    }

    /// Whether a path names an existing directory.
    ///
    /// - Parameter path: the path to test.
    /// - Returns: `true` when the path exists and is a directory.
    static func isDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    // MARK: Relative paths

    /// The path of `absolute` relative to `root`, or `nil` when it is not under `root`.
    ///
    /// Compares the two paths component-wise (not as string prefixes), thus
    /// `/foobar` is not considered inside `/foo`, and rejoins the remaining
    /// components with `/`.
    ///
    /// - Parameters:
    ///   - absolute: the absolute path to relativize.
    ///   - root: the absolute root the path should be under.
    /// - Returns: the relative path, or `nil` when `absolute` is not under `root`.
    static func relativePath(ofAbsolute absolute: String, under root: String) -> String? {
        let rootComponents = pathComponents(root)
        let absoluteComponents = pathComponents(absolute)
        guard absoluteComponents.count >= rootComponents.count else { return nil }
        guard Array(absoluteComponents.prefix(rootComponents.count)) == rootComponents else { return nil }
        return absoluteComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }

    /// The non-empty path components of a path (leading, trailing, and repeated slashes dropped).
    ///
    /// - Parameter path: the path to split.
    /// - Returns: the path's non-empty components.
    private static func pathComponents(_ path: String) -> [String] {
        path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    // MARK: Search-root resolution

    /// Resolves a requested path (or the session root) to a validated URL.
    ///
    /// A given `path` is validated through `validate` — each engine supplies
    /// its own validation (`PathGuard.validate(_:for:)` scoped to a
    /// directory for the glob engine, `PathGuard.validatePath(_:)` for the
    /// grep engine) — while an absent `path` resolves to the session root
    /// without validation. This is the
    /// optional-path-resolution-with-session-root-fallback step both engines
    /// share before their per-engine directory-versus-file handling
    /// diverges.
    ///
    /// - Parameters:
    ///   - path: the requested path, or `nil` for the session root.
    ///   - context: the shared session context supplying the session root.
    ///   - validate: validates a non-`nil` path to a resolved URL, or a violation.
    /// - Returns: `.success` with the resolved URL, or `.failure` with a
    ///   corrective ``PathViolation``.
    static func resolveRequestedPath(
        _ path: String?,
        in context: FileContext,
        validate: (String) -> Result<URL, PathViolation>
    ) -> Result<URL, PathViolation> {
        guard let path else { return .success(context.root) }
        return validate(path)
    }

    /// Refuses the filesystem root, then returns the resolved path's canonical directory URL.
    ///
    /// The shared tail of both engines' directory handling: the filesystem
    /// root is refused through the context's ``PathGuard`` (a
    /// whole-filesystem walk is never allowed), and the surviving path is
    /// canonicalized as a directory, thus the walk and the session-relative
    /// paths share one prefix model.
    ///
    /// - Parameters:
    ///   - resolved: the resolved directory URL to bound and canonicalize.
    ///   - context: the shared session context supplying the path guard.
    /// - Returns: `.success` with the canonical directory URL, or `.failure`
    ///   with a corrective ``PathViolation``.
    static func boundDirectory(_ resolved: URL, in context: FileContext) -> Result<URL, PathViolation> {
        if case .failure(let violation) = context.pathGuard.rejectFilesystemRoot(resolved.path) {
            return .failure(violation)
        }
        return .success(canonicalDirectory(resolved))
    }
}
