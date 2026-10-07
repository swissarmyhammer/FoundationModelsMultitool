// `TemporaryGitRepository` — one git repository with a work folder, for one
// test.
//
// git.md § "Proposed shape": the unit tests make a temporary repository for
// each test. The helper stands in the `MultitoolTestSupport` product, thus
// the unit test target and the nested `IntegrationTests` package take the
// same helper.
//
// The helper never starts the `git` binary. It calls libgit2 directly, in the
// pattern of `GitFixtureRepository` in FoundationModelsExtras
// `Tests/MarketplaceFixtures`, and it starts libgit2 and checks each call
// through the `LibGit2` layer of the library. That fixture makes a bare
// repository; this one makes a repository with a work folder, because the
// git verbs read the work folder of the root.

import Foundation
import libgit2

@testable import FoundationModelsMultitool

/// A git repository with a work folder that a test builds with libgit2 only.
///
/// The helper makes the repository in a new temporary folder, writes files
/// into the work folder, stages or commits them, and makes branches. HEAD names
/// ``defaultBranch`` whatever `init.defaultBranch` the host sets (git.md §
/// "Spike result", fact 2), thus a test that reads HEAD does not depend on
/// the host configuration. The folder is removed when the helper is released.
final class TemporaryGitRepository {

    /// The branch that HEAD names in a new repository.
    static let defaultBranch = "main"

    /// The prefix of the name of each temporary folder. Thus a leaked folder
    /// is traceable to this helper.
    private static let directoryNamePrefix = "TemporaryGitRepository"

    /// The `is_bare` flag value that makes `git_repository_init` write a
    /// repository with a work folder.
    private static let workFolderRepositoryFlag: UInt32 = 0

    /// The name that each commit records.
    private static let signatureName = "Test"

    /// The email that each commit records. The `.invalid` top-level domain
    /// can never be a real address.
    private static let signatureEmail = "test@example.invalid"

    /// The `force` flag value that makes `git_branch_create` fail on a branch
    /// that already exists.
    private static let keepExistingBranch: Int32 = 0

    /// The ref name that names the commit HEAD points at.
    private static let headReference = "HEAD"

    /// The prefix that makes a branch name into the full name of its ref.
    private static let branchReferencePrefix = "refs/heads/"

    /// The text of each blob that ``markConflicted(_:)`` records.
    private static let conflictText = "conflict\n"

    /// The work folder of the repository.
    ///
    /// The URL keeps the spelling of the process temporary folder (`/var/...`
    /// on macOS), and libgit2 gives the real path (`/private/var/...`). A
    /// test that compares the two resolves both with `resolvedPath(_:)`.
    let workDirectory: URL

    /// The open repository handle. This instance owns it.
    private let repository: OpaquePointer

    /// Makes an empty repository with a work folder in a new temporary
    /// folder, and points HEAD at ``defaultBranch``.
    ///
    /// - Throws: ``LibGit2Error`` when libgit2 cannot make the repository, or
    ///   the error of `FileManager` when the folder cannot be made.
    init() throws {
        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(Self.directoryNamePrefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        do {
            repository = try Self.makeRepository(at: workDirectory)
        } catch {
            try? FileManager.default.removeItem(at: workDirectory)
            throw error
        }
        self.workDirectory = workDirectory
    }

    deinit {
        git_repository_free(repository)
        try? FileManager.default.removeItem(at: workDirectory)
    }

    /// Writes `contents` to the file at `path` in the work folder, and makes
    /// each parent folder that is missing.
    ///
    /// - Parameters:
    ///   - contents: The text of the file.
    ///   - path: The path of the file, relative to the work folder. It can
    ///     hold `/` separators.
    /// - Throws: The error of `FileManager` or of the write.
    func write(_ contents: String, to path: String) throws {
        let url = workDirectory.appendingPathComponent(path, isDirectory: false)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Stages each change of the work folder, and commits the index on the
    /// branch that HEAD names.
    ///
    /// A new file, a changed file, and a removed file each go into the
    /// commit. The commit that HEAD names becomes the parent; the first
    /// commit has no parent.
    ///
    /// - Parameter message: The commit message.
    /// - Returns: The 40-hex SHA of the new commit.
    /// - Throws: ``LibGit2Error`` when a libgit2 call fails.
    @discardableResult
    func commit(message: String) throws -> String {
        let tree = try stageWorkFolder()
        defer { git_tree_free(tree) }
        let parent = try headCommit()
        defer { git_commit_free(parent) }
        var commitID = try createCommit(
            of: tree, parents: parent.map { [$0] } ?? [], updating: Self.headReference, message: message)
        return String(cString: git_oid_tostr_s(&commitID))
    }

    /// Stages the file at `path`, and writes the index. No commit is made.
    ///
    /// A file in the work folder goes into the index, thus a new file is
    /// tracked but is in no commit. A file that the work folder no longer
    /// holds goes out of the index, thus its removal is staged.
    ///
    /// - Parameter path: The path of the file, relative to the work folder.
    /// - Throws: ``LibGit2Error`` when a libgit2 call fails.
    func stage(_ path: String) throws {
        let isInWorkFolder = FileManager.default.fileExists(
            atPath: workDirectory.appendingPathComponent(path, isDirectory: false).path)
        try withIndex { index in
            try LibGit2.check(isInWorkFolder ? git_index_add_bypath(index, path) : git_index_remove_bypath(index, path))
            try LibGit2.check(git_index_write(index))
        }
    }

    /// Moves the file at `oldPath` to `newPath` in the work folder, and
    /// stages the two paths. Thus the index holds a rename. No commit is
    /// made.
    ///
    /// Each parent folder of `newPath` that is missing is made first.
    ///
    /// - Parameters:
    ///   - oldPath: The path of the file before the move, relative to the
    ///     work folder.
    ///   - newPath: The path of the file after the move, relative to the
    ///     work folder.
    /// - Throws: The error of `FileManager`, or ``LibGit2Error`` when a
    ///   libgit2 call fails.
    func stageRename(from oldPath: String, to newPath: String) throws {
        let newURL = workDirectory.appendingPathComponent(newPath, isDirectory: false)
        try FileManager.default.createDirectory(
            at: newURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(
            at: workDirectory.appendingPathComponent(oldPath, isDirectory: false), to: newURL)
        try stage(oldPath)
        try stage(newPath)
    }

    /// Records a merge conflict on the file at `path` in the index, and
    /// writes the index. The work folder does not change.
    ///
    /// The index gets the three conflict stages (ancestor, ours, theirs) for
    /// the path, each with the blob of ``conflictText``, and loses the normal
    /// entry of the path. Thus git reads the file as conflicted.
    ///
    /// - Parameter path: The path of the file, relative to the work folder.
    /// - Throws: ``LibGit2Error`` when a libgit2 call fails.
    func markConflicted(_ path: String) throws {
        var blobID = git_oid()
        try LibGit2.check(
            Self.conflictText.withCString { text in
                git_blob_create_from_buffer(&blobID, repository, text, strlen(text))
            })
        try withIndex { index in
            try LibGit2.check(
                path.withCString { cPath in
                    var entry = git_index_entry()
                    entry.path = cPath
                    entry.mode = GIT_FILEMODE_BLOB.rawValue
                    entry.id = blobID
                    return withUnsafePointer(to: entry) { stage in git_index_conflict_add(index, stage, stage, stage) }
                })
            try LibGit2.check(git_index_write(index))
        }
    }

    /// Makes the branch `name` at the commit that HEAD names. HEAD does not
    /// move.
    ///
    /// - Parameter name: The branch name, without `refs/heads/`.
    /// - Throws: ``LibGit2Error`` when HEAD names no commit, when the branch
    ///   exists, or when a libgit2 call fails.
    func createBranch(named name: String) throws {
        let commit = try LibGit2.makeHandle { commit in
            git_revparse_single(&commit, repository, Self.headReference)
        }
        defer { git_object_free(commit) }
        try makeBranch(named: name, at: commit)
    }

    /// Commits each change of the work folder as a commit with no parent,
    /// and makes the branch `name` at that commit. HEAD does not move.
    ///
    /// The new branch has no history in common with the other branches (an
    /// orphan branch).
    ///
    /// - Parameters:
    ///   - name: The branch name, without `refs/heads/`.
    ///   - message: The commit message.
    /// - Throws: ``LibGit2Error`` when the branch exists, or when a libgit2
    ///   call fails.
    func createOrphanBranch(named name: String, message: String) throws {
        let tree = try stageWorkFolder()
        defer { git_tree_free(tree) }
        var commitID = try createCommit(of: tree, parents: [], updating: nil, message: message)
        let commit = try LibGit2.makeHandle { commit in git_commit_lookup(&commit, repository, &commitID) }
        defer { git_commit_free(commit) }
        try makeBranch(named: name, at: commit)
    }

    /// Points HEAD at the branch `name`. The work folder and the index do not
    /// change.
    ///
    /// - Parameter name: The branch name, without `refs/heads/`.
    /// - Throws: ``LibGit2Error`` when a libgit2 call fails.
    func pointHead(atBranch name: String) throws {
        try LibGit2.check(git_repository_set_head(repository, "\(Self.branchReferencePrefix)\(name)"))
    }

    /// Points HEAD directly at the commit that it names now, thus HEAD names
    /// no branch (a detached HEAD).
    ///
    /// - Throws: ``LibGit2Error`` when HEAD names no commit, or when a
    ///   libgit2 call fails.
    func detachHead() throws {
        try LibGit2.check(git_repository_detach_head(repository))
    }

    /// Deletes the local branch `name`. The commits stay.
    ///
    /// - Parameter name: The branch name, without `refs/heads/`. HEAD must
    ///   not name it.
    /// - Throws: ``LibGit2Error`` when the branch does not exist, when HEAD
    ///   names it, or when a libgit2 call fails.
    func deleteBranch(named name: String) throws {
        let branch = try LibGit2.makeHandle { branch in
            git_branch_lookup(&branch, repository, name, GIT_BRANCH_LOCAL)
        }
        defer { git_reference_free(branch) }
        try LibGit2.check(git_branch_delete(branch))
    }

    // MARK: - Steps

    /// Starts libgit2, makes the repository at `directory`, and points HEAD
    /// at ``defaultBranch``.
    ///
    /// - Returns: The repository. The caller owns it and frees it.
    private static func makeRepository(at directory: URL) throws -> OpaquePointer {
        try LibGit2.start()
        let repository = try LibGit2.makeHandle { repository in
            git_repository_init(&repository, directory.path, workFolderRepositoryFlag)
        }
        do {
            try LibGit2.check(git_repository_set_head(repository, "\(branchReferencePrefix)\(defaultBranch)"))
        } catch {
            git_repository_free(repository)
            throw error
        }
        return repository
    }

    /// Adds each new and changed file of the work folder to the index,
    /// removes each file that the work folder no longer holds, writes the
    /// index, and gives its tree.
    ///
    /// - Returns: The tree of the index. The caller frees it.
    private func stageWorkFolder() throws -> OpaquePointer {
        try withIndex { index in
            try LibGit2.check(git_index_add_all(index, nil, GIT_INDEX_ADD_DEFAULT.rawValue, nil, nil))
            try LibGit2.check(git_index_update_all(index, nil, nil, nil))
            try LibGit2.check(git_index_write(index))
            var treeID = git_oid()
            try LibGit2.check(git_index_write_tree(&treeID, index))
            return try LibGit2.makeHandle { tree in git_tree_lookup(&tree, repository, &treeID) }
        }
    }

    /// Makes the branch `name` at `commit`.
    ///
    /// - Parameters:
    ///   - name: The branch name, without `refs/heads/`.
    ///   - commit: The commit, or an object that peels to a commit. The
    ///     caller keeps it and frees it.
    /// - Throws: ``LibGit2Error`` when the branch exists, or when a libgit2
    ///   call fails.
    private func makeBranch(named name: String, at commit: OpaquePointer) throws {
        let branch = try LibGit2.makeHandle { branch in
            git_branch_create(&branch, repository, name, commit, Self.keepExistingBranch)
        }
        git_reference_free(branch)
    }

    /// Writes one commit with the signature of this helper.
    ///
    /// - Parameters:
    ///   - tree: The tree of the commit.
    ///   - parents: The parent commits, oldest first. Empty for a commit
    ///     with no parent.
    ///   - reference: The ref that moves to the new commit, or `nil` to move
    ///     no ref.
    ///   - message: The commit message.
    /// - Returns: The id of the new commit.
    /// - Throws: ``LibGit2Error`` when a libgit2 call fails.
    private func createCommit(
        of tree: OpaquePointer,
        parents: [OpaquePointer?],
        updating reference: String?,
        message: String
    ) throws -> git_oid {
        var parents = parents
        var signature: UnsafeMutablePointer<git_signature>?
        try LibGit2.check(git_signature_now(&signature, Self.signatureName, Self.signatureEmail))
        defer { git_signature_free(signature) }
        var commitID = git_oid()
        try LibGit2.check(
            git_commit_create(
                &commitID, repository, reference, signature, signature, nil, message, tree, parents.count,
                &parents))
        return commitID
    }

    /// Opens the index of the repository, runs `body` with it, and frees it.
    ///
    /// - Parameter body: The work to do with the index.
    /// - Returns: The value of `body`.
    /// - Throws: ``LibGit2Error`` when the index cannot be opened, or the
    ///   error of `body`.
    private func withIndex<Value>(_ body: (OpaquePointer) throws -> Value) throws -> Value {
        let index = try LibGit2.makeHandle { index in git_repository_index(&index, repository) }
        defer { git_index_free(index) }
        return try body(index)
    }

    /// The commit that HEAD names, or `nil` when the branch of HEAD has no
    /// commit yet.
    ///
    /// - Returns: The commit. The caller frees it.
    private func headCommit() throws -> OpaquePointer? {
        var headID = git_oid()
        guard git_reference_name_to_id(&headID, repository, Self.headReference) == GIT_OK.rawValue else {
            return nil
        }
        return try LibGit2.makeHandle { commit in git_commit_lookup(&commit, repository, &headID) }
    }
}
