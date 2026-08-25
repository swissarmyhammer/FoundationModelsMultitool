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

import Darwin
import Foundation

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
///   being honored, the git-aware listing (`git ls-files --cached --others
///   --exclude-standard`) is used, thus ignored files — and, crucially,
///   whole ignored directories such as a `build/` tree — are never descended
///   into; otherwise a plain `FileManager` walk is used.
/// - **Collect-filter-assemble** — ``walkAndFilter(walkRoot:sessionRoot:respectGitIgnore:accept:build:)``
///   is the single loop that enumerates, computes relative paths, applies a
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
    /// When `respectGitIgnore` is set and `walkRoot` is inside a git
    /// repository, the git-aware listing (`git ls-files --cached --others
    /// --exclude-standard`) is used, thus ignored files are skipped without
    /// hand-rolled gitignore parsing; otherwise, and whenever git is
    /// unavailable or the directory is not a repository, a plain
    /// `FileManager` walk is used.
    ///
    /// - Parameters:
    ///   - walkRoot: the canonical search root.
    ///   - respectGitIgnore: whether to prefer the git-aware listing.
    /// - Returns: the absolute paths of the candidate regular files.
    static func collectFiles(walkRoot: URL, respectGitIgnore: Bool) -> [String] {
        if respectGitIgnore, let relativePaths = gitListedFiles(in: walkRoot) {
            return relativePaths.map { walkRoot.path + "/" + $0 }
        }
        return enumeratedRegularFiles(under: walkRoot)
    }

    /// Walks the files under a root, keeps those the predicate accepts, and builds a result for each.
    ///
    /// Enumerates the candidate files under `walkRoot` via
    /// ``collectFiles(walkRoot:respectGitIgnore:)``, computes each file's
    /// path relative to the walk root (skipping any that fall outside it),
    /// offers that pair to `accept`, and — for the accepted files — computes
    /// the path relative to `sessionRoot` and hands both to `build`,
    /// collecting the non-`nil` results in enumeration order. `build` may
    /// return `nil` to drop a file (for example when an attribute it needs
    /// cannot be read).
    ///
    /// This is the single collect-filter-assemble loop both engines share:
    /// the enumeration, the two relative-path computations, and the
    /// skip-on-outside bookkeeping live here one time, while each engine
    /// supplies its own acceptance predicate and its own result type through
    /// the closures.
    ///
    /// - Parameters:
    ///   - walkRoot: the canonical directory to enumerate.
    ///   - sessionRoot: the canonical session root the built results are relative to.
    ///   - respectGitIgnore: whether a present repository's ignore rules are honored.
    ///   - accept: whether to keep a file, given its absolute path and its walk-relative path.
    ///   - build: builds a result from a kept file's absolute path and its
    ///     session-relative path, or `nil` to drop it.
    /// - Returns: the built results, in enumeration order.
    static func walkAndFilter<Element>(
        walkRoot: URL,
        sessionRoot: URL,
        respectGitIgnore: Bool,
        accept: (_ absolutePath: String, _ walkRelativePath: String) -> Bool,
        build: (_ absolutePath: String, _ sessionRelativePath: String) -> Element?
    ) -> [Element] {
        var results: [Element] = []
        for absolute in collectFiles(walkRoot: walkRoot, respectGitIgnore: respectGitIgnore) {
            guard let relativeToWalk = relativePath(ofAbsolute: absolute, under: walkRoot.path) else { continue }
            guard accept(absolute, relativeToWalk) else { continue }
            guard let relativeToSession = relativePath(ofAbsolute: absolute, under: sessionRoot.path) else { continue }
            guard let element = build(absolute, relativeToSession) else { continue }
            results.append(element)
        }
        return results
    }

    /// The git-listed files under a directory, or `nil` when it is not a repository.
    ///
    /// Runs `git ls-files --cached --others --exclude-standard -z` with the
    /// given directory as the working directory, thus the output is the
    /// repository's tracked and untracked-but-not-ignored files under that
    /// directory, one NUL-separated relative path each. A nonzero exit (most
    /// commonly "not a git repository") or a launch failure yields `nil`,
    /// signaling the caller to fall back to a plain walk.
    ///
    /// - Parameter directory: the directory to list, used as git's working directory.
    /// - Returns: the NUL-separated relative paths, or `nil` when git is
    ///   unavailable or the directory is not a repository.
    private static func gitListedFiles(in directory: URL) -> [String]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"]
        process.currentDirectoryURL = directory
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError

        do {
            try process.run()
        } catch {
            return nil
        }
        let data = standardOutput.fileHandleForReading.readDataToEndOfFile()
        _ = try? standardError.fileHandleForReading.readToEnd()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        let text = String(decoding: data, as: UTF8.self)
        return text.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
    }

    /// The absolute paths of the regular files under a directory, walked recursively.
    ///
    /// Directories are traversed but only regular files are returned, thus
    /// the result is directly comparable to the git-aware listing.
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
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == true { paths.append(url.path) }
        }
        return paths
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
