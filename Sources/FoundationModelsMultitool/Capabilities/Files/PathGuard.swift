// `PathGuard` — the path validation stack of the files capability.
//
// A behavioral port of `../FoundationModelsFileTool/Sources/FileTool/
// PathGuard.swift`. The sibling declares the stack `public` for its own
// module surface; this package keeps it internal, the same way the Shell
// capability keeps its own store types.
//
// eventplan.md § "Consolidation of the siblings": the files capability gets
// "`PathGuard` root bounds". Each file verb routes its raw path argument
// through this stack before it touches the disk, thus one design answers
// "may this path be used" for the whole capability.
//
// A rejected path stays IN BAND. Every entry point returns a `Result`:
// `.success` with the resolved absolute URL, or `.failure` with a
// `PathViolation` that carries a corrective message. Nothing here throws. The
// model reads the message and corrects the path inside the same turn; a
// thrown error would end the turn instead.
//
// The stack is itself a Swift port of the Rust `swissarmyhammer-tools`
// `shared_utils` validation stack (`FilePathValidator`, `validate_file_path`,
// `reject_filesystem_root`, `check_file_permissions`). It is
// security-sensitive code: it defends the file verbs against directory
// traversal, symlink escapes, workspace-boundary violations, and
// pathological search roots.

import Darwin
import Foundation

/// A rejected path validation, which carries the corrective message the
/// model reads.
///
/// The validation stack follows the *return-don't-throw* pattern: a
/// violation comes back as a `Result` failure, never raised, thus a language
/// model can read the message and correct the path within the same turn. The
/// type conforms to `Error` only so it can be a `Result` failure — no code
/// throws it.
struct PathViolation: Error, Equatable, Sendable, CustomStringConvertible {
    /// The corrective message that says why the stack rejected the path.
    let message: String

    /// Creates a violation that carries a corrective message.
    ///
    /// - Parameter message: the human-readable corrective message.
    init(_ message: String) {
        self.message = message
    }

    /// The violation's textual representation, which is its corrective ``message``.
    var description: String { message }
}

/// The kind of file access a path is validated for.
///
/// Selects which permission rule ``PathGuard/checkPermission(_:for:)``
/// applies. Mirrors the Rust `FileOperation` enum.
enum FileOperation: Sendable {
    /// Reading a file's contents.
    case read
    /// Writing or creating a file.
    case write
    /// Modifying an existing file.
    case edit
    /// Creating or traversing a directory.
    case directory
    /// Deleting an existing file.
    case delete
}

/// Validates and permission-checks filesystem paths for the file operations.
///
/// Every validation entry point returns a `Result`: `.success` with the
/// resolved absolute ``Foundation/URL`` to operate on, or `.failure` with a
/// ``PathViolation`` that carries a corrective message. Nothing here throws.
///
/// Relative paths resolve against ``root`` — the session working directory —
/// never against the process current directory, because the host can run
/// with an unrelated current directory while it serves multiple sessions.
struct PathGuard: Sendable {
    /// The session working directory relative paths resolve against.
    ///
    /// Never the process current directory: the host process can run with an
    /// unrelated current directory (for example `/`) while a single process
    /// serves multiple session roots.
    let root: URL

    /// The optional primary workspace boundary each validated path must stay within.
    ///
    /// When non-`nil`, a validated path (or, for a not-yet-created target,
    /// its deepest existing parent) must be within this directory, or within
    /// one of ``additionalWorkspaceRoots``, after canonicalization. When
    /// both this and ``additionalWorkspaceRoots`` are empty, the stack
    /// enforces no boundary.
    ///
    /// This root stays privileged and distinct from
    /// ``additionalWorkspaceRoots``: it is the sole boundary for callers
    /// that only know about a single root (for example, error messages and
    /// callers written before multi-root support existed), and its meaning
    /// does not change when additional roots stand beside it.
    let workspaceRoot: URL?

    /// Extra workspace boundaries a validated path may resolve within instead of ``workspaceRoot``.
    ///
    /// A path is valid if it resolves within `workspaceRoot` *or* within a
    /// root in this set — the boundary check is a logical OR across each
    /// configured root, thus overlapping or nested roots never produce
    /// double-validation or conflicting outcomes. Defaults to empty, thus
    /// single-root construction (``workspaceRoot`` alone, or neither)
    /// behaves exactly as it did before this property existed.
    ///
    /// This set never affects relative-path resolution: a relative `path`
    /// always resolves against ``root`` only, never against a member of
    /// this set, even when a member would also contain the resolved path.
    let additionalWorkspaceRoots: Set<URL>

    /// Whether symlinks resolve (`true`) or are rejected (`false`, the secure default).
    ///
    /// When `false`, the stack rejects a path that is itself a symlink
    /// before canonicalization, thus a link to a nonexistent or
    /// out-of-bounds target cannot slip through. When `true`, the symlink
    /// resolves to its real target, and the stack re-checks that target
    /// against the workspace boundary.
    let allowSymlinks: Bool

    /// The maximum accepted path length in UTF-8 bytes.
    ///
    /// Matches the Rust `MAX_PATH_LENGTH` (the Unix `PATH_MAX` standard).
    /// The measure is in bytes, as the Rust `str::len` is, thus the limit is
    /// identical across both ports.
    private static let maximumPathLength = 4096

    /// Literal substrings that reject a path when present anywhere in it.
    ///
    /// Ported from the Rust default blocked-pattern set: Unix (`../`) and
    /// Windows (`\..\`, `..\`) parent-directory traversal, plus the null
    /// byte in both raw (`\0`) and escaped (`\\0`) forms. A bare `..` is
    /// deliberately not blocked (it can be a legitimate filename), and `./`
    /// is allowed (it references the current directory, which is safe).
    private static let blockedPatterns = ["../", "\\..\\", "..\\", "\0", "\\0"]

    /// The corrective-message prefix reported when a parent directory is missing.
    ///
    /// ``parentDirectoryMissing(_:)`` reads this constant, thus the exact
    /// wording lives in a single place. The offending parent path goes after
    /// one space.
    private static let parentDirectoryMissingMessage = "Parent directory does not exist:"

    /// The corrective-message suffix that tells the model how to supply a valid search root.
    ///
    /// Both branches of ``rejectFilesystemRoot(_:)`` read this constant,
    /// thus the exact wording lives in a single place, appended after each
    /// branch-specific prefix.
    private static let provideSessionDirectoryMessage =
        "Provide a `path`, or run with a session working directory set."

    /// The POSIX mode bits that mean "any write permission" (owner, group, or other).
    ///
    /// Each write-permission check reads this constant —
    /// ``checkWritePermission(_:)`` (via ``isReadOnly(_:)``),
    /// ``isReadOnly(_:)`` itself, and ``checkDeletePermission(_:)`` (for the
    /// containing directory's write bit, because POSIX places unlink
    /// permission on the parent) — thus the literal lives in one place and
    /// not at each call site.
    private static let writePermissionBits: mode_t = 0o222

    /// The `st_mode` bits that mean "readable by owner, group, or other" (`0o444`).
    ///
    /// ``checkReadPermission(_:)`` checks these bits with a bitwise AND
    /// against a file's mode, thus the literal lives in one place, which
    /// matches ``writePermissionBits``.
    private static let readPermissionBits: mode_t = 0o444

    /// Creates a guard rooted at a session working directory.
    ///
    /// - Parameters:
    ///   - root: the session working directory relative paths resolve
    ///     against. Relative paths always resolve against this root alone,
    ///     never against ``workspaceRoot`` or `additionalWorkspaceRoots`.
    ///   - workspaceRoot: the optional primary boundary each validated path
    ///     must stay within; `nil` (the default) enforces no boundary unless
    ///     `additionalWorkspaceRoots` is non-empty.
    ///   - additionalWorkspaceRoots: extra boundaries a path may resolve
    ///     within instead of `workspaceRoot`; defaults to empty. A path is
    ///     valid if it resolves within `workspaceRoot` or within a root in
    ///     this set.
    ///   - allowSymlinks: whether to resolve symlinks (`true`) or reject
    ///     them (`false`, the default).
    init(
        root: URL,
        workspaceRoot: URL? = nil,
        additionalWorkspaceRoots: Set<URL> = [],
        allowSymlinks: Bool = false
    ) {
        self.root = root
        self.workspaceRoot = workspaceRoot
        self.additionalWorkspaceRoots = additionalWorkspaceRoots
        self.allowSymlinks = allowSymlinks
    }

    // MARK: Path validation

    /// Validate a path and, on success, check permissions for an operation.
    ///
    /// Runs ``validatePath(_:)`` then ``checkPermission(_:for:)``, and
    /// returns the first violation found or the resolved absolute URL.
    ///
    /// - Parameters:
    ///   - path: the raw path string (absolute or relative to ``root``).
    ///   - operation: the operation whose permission rule to apply.
    /// - Returns: `.success` with the resolved absolute URL, or `.failure`
    ///   with a corrective ``PathViolation``.
    func validate(_ path: String, for operation: FileOperation) -> Result<URL, PathViolation> {
        validatePath(path).flatMap { url in
            checkPermission(url, for: operation).map { url }
        }
    }

    /// Validate a path string, and return the resolved absolute URL to operate on.
    ///
    /// Performs, in order: empty check, length check, blocked-pattern check,
    /// relative resolution against ``root``, symlink rejection (before
    /// canonicalization unless ``allowSymlinks`` is set), canonicalization
    /// with parent-existence messaging for not-yet-created targets,
    /// control-character rejection, and workspace-boundary enforcement.
    ///
    /// For an existing path the result is the resolved canonical URL. For a
    /// not-yet-created target whose parent exists the result is the resolved
    /// (uncanonicalized) absolute URL, thus a write can create it.
    ///
    /// - Parameter path: the raw path string (absolute or relative to ``root``).
    /// - Returns: `.success` with the resolved absolute URL, or `.failure`
    ///   with a corrective ``PathViolation``.
    func validatePath(_ path: String) -> Result<URL, PathViolation> {
        if let violation = Self.emptyViolation(path) { return .failure(violation) }
        if let violation = Self.lengthViolation(path) { return .failure(violation) }
        if let violation = Self.blockedPatternViolation(path) { return .failure(violation) }

        let resolvedPath = path.hasPrefix("/") ? path : Self.join(root.path, path)

        // Re-check the length of the resolved path: a short relative input
        // can exceed the limit once joined to the session root. Mirrors the
        // Rust nested length check in `validate_file_path`.
        if let violation = Self.lengthViolation(resolvedPath) { return .failure(violation) }
        if let violation = symlinkBeforeCanonicalizationViolation(resolvedPath) { return .failure(violation) }

        return handleCanonicalizeResult(resolvedPath).flatMap { validatedPath in
            finishValidation(originalPath: resolvedPath, validatedPath: validatedPath)
        }
    }

    /// A `.success` with the canonical path, or the errno-mapped canonicalization violation.
    ///
    /// Splits the ``CanonicalizeOutcome`` of ``canonicalize(_:)`` into a
    /// `Result`: a resolved path succeeds; a failure goes by its POSIX
    /// `errno` through ``canonicalizeFailureViolation(_:resolvedPath:)``.
    /// The `ENOENT` case is not itself a violation — a not-yet-created
    /// target with an existing parent yields the uncanonicalized
    /// `resolvedPath`.
    ///
    /// - Parameter resolvedPath: the resolved absolute path to canonicalize.
    /// - Returns: `.success` with the path to operate on, or `.failure` with
    ///   a corrective ``PathViolation``.
    private func handleCanonicalizeResult(_ resolvedPath: String) -> Result<String, PathViolation> {
        switch Self.canonicalize(resolvedPath) {
        case .resolved(let canonical):
            return .success(canonical)
        case .failed(let errorNumber):
            return canonicalizeFailureViolation(errorNumber, resolvedPath: resolvedPath)
        }
    }

    /// Map a `realpath` `errno` to a canonicalization outcome for `resolvedPath`.
    ///
    /// The deliberately preserved errno-dispatch table: `ENOENT` (path does
    /// not exist) is acceptable for a not-yet-created write target as long
    /// as the parent directory exists, thus it yields the uncanonicalized
    /// `resolvedPath`; `EACCES`, `EINVAL`, and every other `errno` become
    /// corrective violations.
    ///
    /// - Parameters:
    ///   - errorNumber: the POSIX `errno` from the failed `realpath`.
    ///   - resolvedPath: the resolved absolute path that failed to canonicalize.
    /// - Returns: `.success` with `resolvedPath` for an acceptable `ENOENT`,
    ///   or `.failure` with a corrective ``PathViolation``.
    private func canonicalizeFailureViolation(
        _ errorNumber: Int32,
        resolvedPath: String
    ) -> Result<String, PathViolation> {
        switch errorNumber {
        case ENOENT:
            return parentDirectoryMissing(resolvedPath).map { resolvedPath }
        case EACCES:
            return .failure(PathViolation("Permission denied accessing path: \(resolvedPath)"))
        case EINVAL:
            return .failure(PathViolation("Invalid path format: \(resolvedPath)"))
        default:
            return .failure(
                PathViolation("Failed to resolve path '\(resolvedPath)': \(String(cString: strerror(errorNumber)))")
            )
        }
    }

    /// Run the post-canonicalization checks and produce the resolved URL.
    ///
    /// Applies, in order, control-character rejection on the canonical path
    /// and workspace-boundary enforcement, then re-resolves an opted-in
    /// symlink to its real target and re-checks the boundary. The boundary
    /// applies once here (after control-character validation) and, when
    /// symlinks are opted in, again on the symlink's real target inside
    /// ``resolveSymlinkIfAllowed(originalPath:validatedPath:)``. Thus both
    /// the requested path and its resolved target must stay within the
    /// boundary. Both stages route through ``enforceWorkspaceBoundary(_:)``.
    ///
    /// - Parameters:
    ///   - originalPath: the pre-canonicalization resolved path, tested for
    ///     being a symlink.
    ///   - validatedPath: the canonical path to check and resolve.
    /// - Returns: `.success` with the resolved absolute URL, or `.failure`
    ///   with a corrective ``PathViolation``.
    private func finishValidation(originalPath: String, validatedPath: String) -> Result<URL, PathViolation> {
        if let violation = Self.controlCharacterViolation(validatedPath) { return .failure(violation) }
        return enforceWorkspaceBoundary(validatedPath)
            .flatMap { resolveSymlinkIfAllowed(originalPath: originalPath, validatedPath: validatedPath) }
            .map { URL(fileURLWithPath: $0) }
    }

    /// A "symlinks not allowed" violation when a path is a rejected symlink, else `nil`.
    ///
    /// Rejects a path that is itself a symlink before canonicalization when
    /// ``allowSymlinks`` is `false`, thus a link to a nonexistent or
    /// out-of-bounds target cannot slip through. Returns `nil` when the path
    /// is not a symlink or symlinks are opted in.
    ///
    /// - Parameter path: the resolved path to test for being a rejected symlink.
    /// - Returns: a corrective ``PathViolation``, or `nil` when acceptable.
    private func symlinkBeforeCanonicalizationViolation(_ path: String) -> PathViolation? {
        guard isSymlink(path) && !allowSymlinks else { return nil }
        return PathViolation("Symlinks are not allowed: \(path)")
    }

    /// Each configured workspace boundary: ``workspaceRoot`` (if set)
    /// followed by ``additionalWorkspaceRoots`` in a stable order.
    ///
    /// The primary root goes first — it is the privileged root a
    /// single-root caller (and each error message) names first — followed by
    /// the additional roots sorted by path. Thus error messages and
    /// iteration order never depend on `Set`'s unspecified enumeration
    /// order.
    private var allWorkspaceRoots: [URL] {
        var roots: [URL] = []
        if let workspaceRoot { roots.append(workspaceRoot) }
        roots.append(contentsOf: additionalWorkspaceRoots.sorted { $0.path < $1.path })
        return roots
    }

    /// Enforce the workspace boundary on a path when at least one root is configured.
    ///
    /// A no-op that returns `.success` when ``allWorkspaceRoots`` is empty
    /// (no boundary configured at all); otherwise delegates to
    /// ``ensureWorkspaceBoundary(_:workspaceRoots:)``. Extracted, thus the
    /// boundary check applied both after control-character validation and
    /// after symlink re-resolution stays a single expression at each stage.
    ///
    /// - Parameter path: the resolved path to bound-check.
    /// - Returns: `.success` when within the boundary (or unbounded), or
    ///   `.failure` with a corrective ``PathViolation``.
    private func enforceWorkspaceBoundary(_ path: String) -> Result<Void, PathViolation> {
        let roots = allWorkspaceRoots
        guard !roots.isEmpty else { return .success(()) }
        return ensureWorkspaceBoundary(path, workspaceRoots: roots)
    }

    /// Re-resolve an opted-in symlink to its real target and re-check the boundary.
    ///
    /// When ``allowSymlinks`` is set and `originalPath` is itself a symlink,
    /// the already validated path re-canonicalizes to its real target, and
    /// the workspace boundary applies again against that target. Thus an
    /// opted-in symlink can never point outside the workspace — a dangling
    /// link fails to canonicalize and is rejected. Otherwise
    /// `validatedPath` comes back unchanged. Mirrors the Rust
    /// `resolve_symlink_securely`.
    ///
    /// - Parameters:
    ///   - originalPath: the pre-canonicalization resolved path, tested for
    ///     being a symlink.
    ///   - validatedPath: the validated path to re-resolve and bound-check.
    /// - Returns: `.success` with the path to operate on, or `.failure` with
    ///   a corrective ``PathViolation``.
    private func resolveSymlinkIfAllowed(
        originalPath: String,
        validatedPath: String
    ) -> Result<String, PathViolation> {
        guard allowSymlinks && isSymlink(originalPath) else {
            return .success(validatedPath)
        }
        return Self.canonicalizeOrFail(validatedPath, failureMessage: "Failed to resolve symlink: \(originalPath)")
            .flatMap { resolvedTarget in
                enforceWorkspaceBoundary(resolvedTarget).map { resolvedTarget }
            }
    }

    /// A `.failure` when `path`'s parent directory does not exist, else `.success`.
    ///
    /// Shared by ``validatePath(_:)`` (for a not-yet-created
    /// canonicalization target) and ``checkPermission(_:for:)`` (for a
    /// `write` to a nonexistent target), thus the parent-existence rule and
    /// its corrective message live in one place.
    ///
    /// - Parameter path: the path whose parent directory to check.
    /// - Returns: `.success` when the parent exists (or there is no parent),
    ///   or `.failure` with a corrective ``PathViolation``.
    private func parentDirectoryMissing(_ path: String) -> Result<Void, PathViolation> {
        if let parent = Self.parentPath(path), !fileExists(parent) {
            return .failure(PathViolation("\(Self.parentDirectoryMissingMessage) \(parent)"))
        }
        return .success(())
    }

    /// Refuse a search root that would walk the whole filesystem or the process directory.
    ///
    /// A relative search directory (a bare `.`, the empty string, or a path
    /// not anchored at an absolute root) means the session working directory
    /// could not resolve; a walk of it would root the search at the process
    /// current directory. An absolute root with no path components is the
    /// filesystem root (`/`); a walk of it visits every file on the machine.
    /// The stack refuses either case. Mirrors the Rust
    /// `reject_filesystem_root`.
    ///
    /// - Parameter searchDirectory: the resolved search root to check.
    /// - Returns: `.success` when the root is a normal absolute directory,
    ///   or `.failure` with a corrective ``PathViolation``.
    func rejectFilesystemRoot(_ searchDirectory: String) -> Result<Void, PathViolation> {
        if !searchDirectory.hasPrefix("/") {
            return .failure(
                PathViolation(
                    "Refusing to search '\(searchDirectory)': the session working directory could not be "
                        + "resolved to an absolute path. " + Self.provideSessionDirectoryMessage
                )
            )
        }
        if searchDirectory.split(separator: "/", omittingEmptySubsequences: true).isEmpty {
            return .failure(
                PathViolation(
                    "Refusing to search the filesystem root: \(searchDirectory). "
                        + Self.provideSessionDirectoryMessage
                )
            )
        }
        return .success(())
    }

    // MARK: Permission checks

    /// Check that an operation is permitted on a resolved path.
    ///
    /// Ported from the Rust `check_file_permissions`. Uses pure mode-bit
    /// checks (readable = any of ``readPermissionBits``; not read-only = any
    /// of ``writePermissionBits``), thus the result is independent of the
    /// running user:
    ///
    /// - `read`: an existing path must be a regular file and readable.
    /// - `write`: an existing file must not be read-only; a nonexistent
    ///   target's parent directory must exist.
    /// - `edit`: the file must exist and must not be read-only.
    /// - `directory`: an existing path must be a directory.
    /// - `delete`: the path must be an existing regular file whose parent
    ///   directory is writable (POSIX deletion permission lives on the
    ///   parent).
    ///
    /// - Parameters:
    ///   - url: the resolved absolute URL (from ``validatePath(_:)``).
    ///   - operation: the operation whose permission rule to apply.
    /// - Returns: `.success` when permitted, or `.failure` with a corrective
    ///   ``PathViolation``.
    func checkPermission(_ url: URL, for operation: FileOperation) -> Result<Void, PathViolation> {
        let path = url.path
        switch operation {
        case .read:
            return checkReadPermission(path)
        case .write:
            return checkWritePermission(path)
        case .edit:
            return checkEditPermission(path)
        case .directory:
            return checkDirectoryPermission(path)
        case .delete:
            return checkDeletePermission(path)
        }
    }

    /// Check that a path may be read: an existing path must be a readable regular file.
    ///
    /// A nonexistent path succeeds (there is nothing to protect). An
    /// existing path must be a regular file with at least one read bit
    /// (``readPermissionBits``).
    ///
    /// - Parameter path: the resolved path to check.
    /// - Returns: `.success` when readable (or nonexistent), or `.failure`
    ///   with a corrective ``PathViolation``.
    private func checkReadPermission(_ path: String) -> Result<Void, PathViolation> {
        guard fileExists(path) else { return .success(()) }
        guard let mode = Self.fileMode(path) else {
            return .failure(PathViolation("Failed to get file metadata: \(path)"))
        }
        if (mode & S_IFMT) != S_IFREG {
            return .failure(PathViolation("Path is not a regular file: \(path)"))
        }
        if (mode & Self.readPermissionBits) == 0 {
            return .failure(PathViolation("File is not readable (no read permissions): \(path)"))
        }
        return .success(())
    }

    /// Check that a path may be written: an existing file must not be read-only.
    ///
    /// An existing file must have at least one write bit. A nonexistent
    /// target is acceptable only when its parent directory exists.
    ///
    /// - Parameter path: the resolved path to check.
    /// - Returns: `.success` when writable, or `.failure` with a corrective
    ///   ``PathViolation``.
    private func checkWritePermission(_ path: String) -> Result<Void, PathViolation> {
        guard fileExists(path) else { return parentDirectoryMissing(path) }
        if Self.isReadOnly(path) {
            return .failure(PathViolation("File is read-only: \(path)"))
        }
        return .success(())
    }

    /// Check that a path may be edited: the file must exist and not be read-only.
    ///
    /// Unlike `write`, an edit requires the file to already exist.
    ///
    /// - Parameter path: the resolved path to check.
    /// - Returns: `.success` when editable, or `.failure` with a corrective
    ///   ``PathViolation``.
    private func checkEditPermission(_ path: String) -> Result<Void, PathViolation> {
        if !fileExists(path) {
            return .failure(Self.nonexistentFileViolation(operation: "edit", path: path))
        }
        if Self.isReadOnly(path) {
            return .failure(PathViolation("File is read-only and cannot be edited: \(path)"))
        }
        return .success(())
    }

    /// Check that a path may be used as a directory: if it exists, it must be one.
    ///
    /// A nonexistent path succeeds. An existing path that is not a directory
    /// (or cannot be stat-ed) is rejected.
    ///
    /// - Parameter path: the resolved path to check.
    /// - Returns: `.success` when a directory (or nonexistent), or
    ///   `.failure` with a corrective ``PathViolation``.
    private func checkDirectoryPermission(_ path: String) -> Result<Void, PathViolation> {
        if fileExists(path), (Self.fileMode(path).map { ($0 & S_IFMT) != S_IFDIR }) ?? true {
            return .failure(PathViolation("Path exists but is not a directory: \(path)"))
        }
        return .success(())
    }

    /// Check that a path may be deleted: an existing regular file in a writable parent.
    ///
    /// A deletion needs no new access kind for a move/rename — the caller
    /// validates the source with `delete` and the destination with `write`.
    /// The path must exist and be a regular file, and its parent directory
    /// must be writable, because POSIX places the permission to unlink a
    /// directory entry on the containing directory
    /// (``writePermissionBits``), not on the file itself.
    ///
    /// - Parameter path: the resolved path to check.
    /// - Returns: `.success` when deletable, or `.failure` with a corrective
    ///   ``PathViolation``.
    private func checkDeletePermission(_ path: String) -> Result<Void, PathViolation> {
        guard fileExists(path) else {
            return .failure(Self.nonexistentFileViolation(operation: "delete", path: path))
        }
        guard let mode = Self.fileMode(path), (mode & S_IFMT) == S_IFREG else {
            return .failure(PathViolation("Cannot delete non-regular file: \(path)"))
        }
        guard let parent = Self.parentPath(path),
            let parentMode = Self.fileMode(parent), (parentMode & Self.writePermissionBits) != 0
        else {
            return .failure(PathViolation("Parent directory is not writable: \(Self.parentPath(path) ?? path)"))
        }
        return .success(())
    }

    // MARK: Workspace boundary

    /// Ensure a path stays within at least one of several workspace boundaries.
    ///
    /// Each root and the path itself canonicalize before a component-wise
    /// prefix comparison, thus `/foo/bar` is inside `/foo` but `/foobar` is
    /// not. A not-yet-created target reconstructs from its deepest existing
    /// parent's canonical path, thus nonexistent write targets stay bounded.
    /// Mirrors the Rust `ensure_workspace_boundary`, generalized from a
    /// single root to a logical OR across `workspaceRoots`: a path succeeds
    /// as soon as it matches one root, thus overlapping or nested roots
    /// never produce double-validation or conflicting outcomes. A rejection
    /// names each root that was in scope, thus it stays actionable with more
    /// than one configured.
    ///
    /// - Parameters:
    ///   - path: the resolved path to bound-check.
    ///   - workspaceRoots: each configured root, in the order violations
    ///     name them (see ``allWorkspaceRoots``); never empty when this is
    ///     called.
    /// - Returns: `.success` when `path` is within a root, or `.failure`
    ///   with a corrective ``PathViolation`` that names each root.
    private func ensureWorkspaceBoundary(
        _ path: String,
        workspaceRoots: [URL]
    ) -> Result<Void, PathViolation> {
        canonicalize(workspaceRoots: workspaceRoots).flatMap { canonicalRoots in
            resolvedPathToCheck(path).flatMap { pathToCheck in
                canonicalRoots.contains(where: { Self.pathStartsWith(pathToCheck, prefix: $0) })
                    ? .success(())
                    : .failure(
                        PathViolation(
                            "Path is outside workspace boundaries: \(pathToCheck) "
                                + "(workspace roots: \(canonicalRoots.joined(separator: ", ")))"
                        )
                    )
            }
        }
    }

    /// Canonicalize each workspace root, and skip a root that cannot resolve.
    ///
    /// A root that fails to canonicalize (for example, one that was deleted
    /// or never existed after configuration) does not poison the whole
    /// boundary check: the check drops it, thus a path within another,
    /// still-valid root stays valid. Only when *every* configured root fails
    /// does this return `.failure`, and the failure names each one — which
    /// also keeps single-root behavior unchanged, because a lone invalid
    /// `workspaceRoot` has nothing else to fall back on and still fails
    /// outright.
    ///
    /// - Parameter workspaceRoots: the roots to canonicalize, in order.
    /// - Returns: `.success` with the real absolute path of each root that
    ///   canonicalized (same relative order, invalid ones dropped), or
    ///   `.failure` with a corrective ``PathViolation`` that names each root
    ///   when none canonicalized.
    private func canonicalize(workspaceRoots: [URL]) -> Result<[String], PathViolation> {
        var canonicalRoots: [String] = []
        var invalidRoots: [String] = []
        for root in workspaceRoots {
            switch Self.canonicalize(root.path) {
            case .resolved(let canonical):
                canonicalRoots.append(canonical)
            case .failed:
                invalidRoots.append(root.path)
            }
        }
        guard canonicalRoots.isEmpty else { return .success(canonicalRoots) }
        return .failure(PathViolation("Invalid workspace root(s): \(invalidRoots.joined(separator: ", "))"))
    }

    /// The real absolute path to bound-check for a path that may not yet exist.
    ///
    /// Canonicalizes an existing path directly. For a not-yet-created
    /// target, defers to ``reconstructViaExistingParent(_:)``, thus the
    /// boundary check still operates on a real absolute path.
    ///
    /// - Parameter path: the path to resolve for bounding.
    /// - Returns: `.success` with the resolved absolute path, or `.failure`
    ///   with a corrective ``PathViolation``.
    private func resolvedPathToCheck(_ path: String) -> Result<String, PathViolation> {
        fileExists(path)
            ? Self.canonicalizeOrFail(path, failureMessage: "Failed to canonicalize path: \(path)")
            : reconstructViaExistingParent(path)
    }

    /// Reconstruct a nonexistent path against its deepest existing parent's canonical path.
    ///
    /// Walks up the ancestors of `path` to the first that exists,
    /// canonicalizes it, and rejoins the remaining components. Thus the
    /// boundary check operates on a real absolute path even for a target
    /// that does not exist yet.
    private func reconstructViaExistingParent(_ path: String) -> Result<String, PathViolation> {
        var current = path
        while let parent = Self.parentPath(current) {
            if fileExists(parent) {
                return Self.canonicalizeOrFail(
                    parent, failureMessage: "Failed to canonicalize parent directory: \(parent)"
                )
                .map { Self.rejoinRemainder(of: path, below: parent, onto: $0) }
            }
            current = parent
        }
        return .failure(PathViolation("Path has no existing parent directory: \(path)"))
    }

    /// Rejoin the path components below `originalParent` onto its canonical form.
    ///
    /// `path` and `originalParent` share each component up to
    /// `originalParent`. This appends the remaining components of `path`
    /// onto `canonicalParent`, thus the result is `canonicalParent` itself
    /// when `path` and `originalParent` are the same directory.
    ///
    /// - Parameters:
    ///   - path: the original (possibly nonexistent) path in resolution.
    ///   - originalParent: the ancestor of `path` that was canonicalized.
    ///   - canonicalParent: the real absolute path of `originalParent`.
    /// - Returns: `canonicalParent` with the remaining components of `path` appended.
    private static func rejoinRemainder(of path: String, below originalParent: String, onto canonicalParent: String)
        -> String
    {
        let remainder = components(path).dropFirst(components(originalParent).count)
        return remainder.isEmpty ? canonicalParent : join(canonicalParent, remainder.joined(separator: "/"))
    }

    // MARK: Filesystem probes

    /// Whether a path exists, following symlinks (matching the Rust `Path::exists`).
    private func fileExists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    /// Whether a path is itself a symlink, without following it (via `lstat`).
    private func isSymlink(_ path: String) -> Bool {
        var status = stat()
        return lstat(path, &status) == 0 && (status.st_mode & S_IFMT) == S_IFLNK
    }

    // MARK: Static helpers

    /// The `st_mode` of a path, following symlinks, or `nil` if it cannot be stat-ed.
    private static func fileMode(_ path: String) -> mode_t? {
        var status = stat()
        guard stat(path, &status) == 0 else { return nil }
        return status.st_mode
    }

    /// Whether a path has no write bits set (`mode & writePermissionBits == 0`), matching Rust's `readonly()`.
    private static func isReadOnly(_ path: String) -> Bool {
        guard let mode = fileMode(path) else { return false }
        return (mode & writePermissionBits) == 0
    }

    /// The outcome of canonicalizing a path via `realpath`.
    ///
    /// Distinct from `Result` because the failure payload is a POSIX
    /// `errno` (an `Int32`), which does not conform to `Error`.
    private enum CanonicalizeOutcome {
        /// The real absolute path, with symlinks resolved.
        case resolved(String)
        /// The POSIX `errno` from the failed `realpath` (for example `ENOENT`).
        case failed(Int32)
    }

    /// Canonicalize a path via `realpath`, which resolves symlinks and requires existence.
    ///
    /// Mirrors the Rust `Path::canonicalize`:
    /// ``CanonicalizeOutcome/resolved(_:)`` with the real absolute path, or
    /// ``CanonicalizeOutcome/failed(_:)`` with the POSIX `errno` (for
    /// example `ENOENT` when the path does not exist).
    private static func canonicalize(_ path: String) -> CanonicalizeOutcome {
        guard let resolved = realpath(path, nil) else {
            return .failed(errno)
        }
        defer { free(resolved) }
        return .resolved(String(cString: resolved))
    }

    /// Canonicalize a path, and map a `realpath` failure to a corrective violation.
    ///
    /// Wraps the ``CanonicalizeOutcome`` guard repeated at every
    /// workspace-boundary and symlink-resolution site: on
    /// ``CanonicalizeOutcome/resolved(_:)`` it yields the real absolute
    /// path; on ``CanonicalizeOutcome/failed(_:)`` it discards the `errno`
    /// — as each call site already did — and returns a `.failure` that
    /// carries `failureMessage`.
    ///
    /// - Parameters:
    ///   - path: the path to canonicalize via `realpath`.
    ///   - failureMessage: the corrective message when canonicalization fails.
    /// - Returns: `.success` with the real absolute path, or `.failure` with
    ///   a ``PathViolation`` that carries `failureMessage`.
    private static func canonicalizeOrFail(
        _ path: String,
        failureMessage: @autoclosure () -> String
    ) -> Result<String, PathViolation> {
        switch canonicalize(path) {
        case .resolved(let canonical):
            return .success(canonical)
        case .failed:
            return .failure(PathViolation(failureMessage()))
        }
    }

    /// The corrective violation that rejects an operation on a nonexistent file.
    ///
    /// Both ``checkEditPermission(_:)`` and ``checkDeletePermission(_:)``
    /// reject a missing file with the same wording except for the operation
    /// verb, thus the exact phrasing lives in one place. The offending path
    /// goes after the colon.
    ///
    /// - Parameters:
    ///   - operation: the verb that names the attempted operation ("edit", "delete").
    ///   - path: the offending path.
    /// - Returns: the corrective ``PathViolation``.
    private static func nonexistentFileViolation(operation: String, path: String) -> PathViolation {
        PathViolation("Cannot \(operation) non-existent file: \(path)")
    }

    /// An "empty path" violation when a path is blank after trimming, else `nil`.
    ///
    /// Trims Unicode whitespace and newlines (matching the Rust `str::trim`)
    /// before the emptiness test, thus a path of only spaces or newlines is
    /// rejected.
    ///
    /// - Parameter path: the raw path string to check.
    /// - Returns: a corrective ``PathViolation``, or `nil` when non-empty.
    private static func emptyViolation(_ path: String) -> PathViolation? {
        guard path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return PathViolation("File path cannot be empty")
    }

    /// A "blocked pattern" violation when a path contains a blocked substring, else `nil`.
    ///
    /// Reports the first ``blockedPatterns`` substring found anywhere in the
    /// path, thus directory-traversal and null-byte sequences stop before
    /// any filesystem access.
    ///
    /// - Parameter path: the raw path string to scan.
    /// - Returns: a corrective ``PathViolation`` that names the matched
    ///   pattern, or `nil` when no blocked pattern is present.
    private static func blockedPatternViolation(_ path: String) -> PathViolation? {
        for pattern in blockedPatterns where path.contains(pattern) {
            return PathViolation("Path contains blocked pattern '\(pattern)': \(path)")
        }
        return nil
    }

    /// A "path too long" violation when a path exceeds ``maximumPathLength``, else `nil`.
    ///
    /// The length is in UTF-8 bytes, matching the Rust `str::len`.
    private static func lengthViolation(_ path: String) -> PathViolation? {
        guard path.utf8.count > maximumPathLength else { return nil }
        return PathViolation(
            "Path too long (\(path.utf8.count) characters, maximum \(maximumPathLength)): \(path)"
        )
    }

    /// Join a relative path onto an absolute base directory.
    private static func join(_ base: String, _ relative: String) -> String {
        base.hasSuffix("/") ? base + relative : base + "/" + relative
    }

    /// The parent of an absolute path, or `nil` for the filesystem root.
    ///
    /// Trailing slashes trim first (the root stays). Mirrors the Rust
    /// `Path::parent` for the absolute paths this stack operates on.
    private static func parentPath(_ path: String) -> String? {
        var trimmed = path
        while trimmed.count > 1 && trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard trimmed != "/" else { return nil }
        guard let lastSlash = trimmed.lastIndex(of: "/") else { return nil }
        if lastSlash == trimmed.startIndex { return "/" }
        return String(trimmed[trimmed.startIndex..<lastSlash])
    }

    /// The non-empty path components of a path (leading/trailing slashes dropped).
    private static func components(_ path: String) -> [String] {
        path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    /// Whether `path` is at or below `prefix`, compared component-wise.
    ///
    /// Component-wise comparison (not string prefix), thus `/foobar` is not
    /// considered inside `/foo`.
    private static func pathStartsWith(_ path: String, prefix: String) -> Bool {
        let pathComponents = components(path)
        let prefixComponents = components(prefix)
        guard prefixComponents.count <= pathComponents.count else { return false }
        return Array(pathComponents.prefix(prefixComponents.count)) == prefixComponents
    }

    /// A "control characters" violation when a path holds a disallowed control character, else `nil`.
    ///
    /// Wraps ``containsInvalidControlCharacter(_:)``, thus the
    /// post-canonicalization check composes uniformly with the other
    /// violation helpers.
    ///
    /// - Parameter path: the canonical path to scan.
    /// - Returns: a corrective ``PathViolation``, or `nil` when no
    ///   disallowed control character is present.
    private static func controlCharacterViolation(_ path: String) -> PathViolation? {
        guard containsInvalidControlCharacter(path) else { return nil }
        return PathViolation("Path contains invalid control characters")
    }

    /// Whether a path contains a disallowed control character.
    ///
    /// Rejects Unicode control characters (C0 `U+0000`–`U+001F`, `DEL`, and
    /// C1 `U+0080`–`U+009F`) except tab, newline, and carriage return,
    /// matching the Rust normalization check. The null byte stops earlier
    /// as a blocked pattern but is also covered here.
    private static func containsInvalidControlCharacter(_ path: String) -> Bool {
        path.unicodeScalars.contains { scalar in
            let value = scalar.value
            let isControl = value <= 0x1F || (value >= 0x7F && value <= 0x9F)
            return isControl && scalar != "\n" && scalar != "\r" && scalar != "\t"
        }
    }
}
