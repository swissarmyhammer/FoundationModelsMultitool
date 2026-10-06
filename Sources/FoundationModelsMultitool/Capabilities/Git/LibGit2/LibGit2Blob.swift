// `LibGit2Blob` — the blob calls of the `LibGit2` layer: the bytes of one file
// at one ref.
//
// git.md § "Decisions", items 6 and 10: each verb that reads a file at a ref
// (`tools.git.show`, and `tools.git.diff` for `path@ref`) reads the blob
// through libgit2. The steps are the ones that the spike proved
// (git.md § "Spike result"): `git_revparse_single` and a peel to the commit
// (`LibGit2Commit.swift`), then `git_object_lookup_bypath` from that commit,
// then `git_blob_rawcontent` and `git_blob_rawsize`.
//
// libgit2 gives the same code, `GIT_ENOTFOUND`, for an unknown ref and for an
// unknown path. The verb must name the one that is wrong, thus this layer
// looks up the two in two steps and gives a lookup kind for each, not a
// thrown error.
//
// The bytes of `git_blob_rawcontent` belong to the blob. The layer copies them
// into a `Data` before it frees the blob.

import Foundation
import libgit2

/// The bytes of one file at one ref.
struct LibGit2Blob: Equatable, Sendable {

    /// The bytes of the file, as the commit holds them.
    let content: Data

    /// Whether git sees the bytes as binary (`git_blob_is_binary`: a NUL byte
    /// or too many bytes that are not printable, in the first 8000 bytes).
    let isBinary: Bool
}

/// The result of a blob lookup: the blob, or the step that found nothing.
enum LibGit2BlobLookup: Equatable, Sendable {

    /// The commit of the ref holds a file at the path.
    case found(LibGit2Blob)

    /// The ref names no object.
    case unknownRevision

    /// The commit of the ref holds nothing at the path.
    case unknownPath

    /// The commit of the ref holds a folder (a tree) or a submodule at the
    /// path, not a file.
    case notAFile
}

extension LibGit2Repository {

    /// The value of `git_blob_is_binary` for a binary blob.
    private static let binaryBlob: Int32 = 1

    /// Reads the file at `path` in the commit that `revision` names.
    ///
    /// - Parameters:
    ///   - path: The path of the file relative to the work folder, as libgit2
    ///     reads it (for example `src/a.txt`).
    ///   - revision: A ref, as `git_revparse_single` reads it.
    /// - Returns: The blob, or the step that found nothing.
    /// - Throws: ``LibGit2Error`` when the ref is not valid, when the object
    ///   that it names does not peel to a commit, or when a libgit2 call fails
    ///   for another reason.
    func blob(atPath path: String, revision: String) throws(LibGit2Error) -> LibGit2BlobLookup {
        guard let commit = try commit(forRevision: revision) else { return .unknownRevision }
        defer { git_commit_free(commit) }
        let entry: OpaquePointer
        do {
            entry = try LibGit2.makeHandle { entry in git_object_lookup_bypath(&entry, commit, path, GIT_OBJECT_ANY) }
        } catch where error.isNotFound {
            return .unknownPath
        }
        defer { git_object_free(entry) }
        guard git_object_type(entry) == GIT_OBJECT_BLOB else { return .notAFile }
        return .found(Self.copy(ofBlob: entry))
    }

    /// Copies the bytes of an open blob.
    ///
    /// - Parameter blob: The blob. The caller keeps it and frees it.
    /// - Returns: The bytes, and the binary flag of git.
    private static func copy(ofBlob blob: OpaquePointer) -> LibGit2Blob {
        let size = Int(git_blob_rawsize(blob))
        let content = git_blob_rawcontent(blob).map { Data(bytes: $0, count: size) } ?? Data()
        return LibGit2Blob(content: content, isBinary: git_blob_is_binary(blob) == binaryBlob)
    }
}
