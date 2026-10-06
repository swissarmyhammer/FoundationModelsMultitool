// `GitContext` — the shared per-session state of the git verbs.
//
// git.md § "Decisions", item 8: `MultiTool.Builder.withGit(root:)` takes its
// own root, and does not need the `files` capability. `GitContext` holds that
// root and one `PathGuard` with the same rules as `files`. Each path argument
// goes through the guard. The repository is the one that contains the root,
// and the root can be a subfolder of the repository.
//
// git.md § "Decisions", item 10: the libgit2 objects are not `Sendable`, thus
// the context holds the location of the repository and not an open handle.
// Each verb opens, uses, and frees the handle inside one call.
//
// A root that is in no repository does not throw at construction. The
// context holds the correction, and each verb answers it in band, the same
// as a path that `PathGuard` refuses.

import Foundation

/// The shared per-session state the git verbs dispatch against.
///
/// A value: every stored property is immutable and `Sendable`, and the
/// context holds no libgit2 handle. Thus each verb holds its own copy of the
/// same context, and the copies cannot differ.
struct GitContext: Sendable {

    /// The correction that each verb answers when no repository contains the
    /// root.
    private static let notInRepositoryCorrection = "the root is not in a git repository"

    /// The correction that each verb answers when the repository of the root
    /// has no work folder (a bare repository).
    private static let bareRepositoryCorrection = "the git repository of the root has no work folder"

    /// The start of the correction that each verb answers when the repository
    /// of the root cannot be opened. The libgit2 error goes after one space.
    private static let unopenableRepositoryCorrection = "the git repository of the root cannot be opened:"

    /// The session working directory: the boundary and the relative-path base.
    let root: URL

    /// The validator every path argument passes through before a verb runs.
    ///
    /// Built from ``root`` as both the relative-path base and the workspace
    /// boundary, with symlinks refused: the same rules as `FileContext`.
    let pathGuard: PathGuard

    /// The repository that contains ``root``, or the correction that each
    /// verb answers in its place.
    ///
    /// A verb reads it with `Result.resolve(corrective:then:)`, thus a root in
    /// no repository becomes the `correction` of the verb result and not a
    /// thrown error.
    let repository: Result<GitRepositoryLocation, CorrectiveRejection>

    /// Creates a session context rooted at a working directory.
    ///
    /// The initializer finds the repository that contains `root` one time,
    /// with libgit2 (`git_repository_open_ext`, which reads only the folders
    /// from `root` up to the repository). It never throws: a root in no
    /// repository gives a ``repository`` failure.
    ///
    /// - Parameter root: the session working directory; also the
    ///   ``pathGuard`` workspace boundary and relative-path base.
    init(root: URL) {
        self.root = root
        self.pathGuard = PathGuard(root: root, workspaceRoot: root)
        self.repository = Self.locateRepository(containing: root)
    }

    /// Finds the repository that contains `root`.
    ///
    /// - Parameter root: The session working directory.
    /// - Returns: The location of the repository, or the correction for a
    ///   root in no repository, for a bare repository, and for a repository
    ///   that libgit2 cannot open.
    private static func locateRepository(
        containing root: URL
    ) -> Result<GitRepositoryLocation, CorrectiveRejection> {
        let workDirectory: URL?
        do {
            workDirectory = try LibGit2Repository(discoveringFrom: root).workDirectory
        } catch where error.isNotFound {
            return .failure(CorrectiveRejection(correctiveMessage: notInRepositoryCorrection))
        } catch {
            return .failure(CorrectiveRejection(correctiveMessage: "\(unopenableRepositoryCorrection) \(error)"))
        }
        guard let workDirectory else {
            return .failure(CorrectiveRejection(correctiveMessage: bareRepositoryCorrection))
        }
        guard let location = GitRepositoryLocation(workDirectory: workDirectory, root: root) else {
            return .failure(CorrectiveRejection(correctiveMessage: notInRepositoryCorrection))
        }
        return .success(location)
    }
}
