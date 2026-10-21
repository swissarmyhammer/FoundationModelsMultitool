// The file changes of the `snapshots` GraphQL endpoint (MT-13, HOOKS-2): the
// `Checkpoint.changes` field, which gives the unified diff of each file that a
// checkpoint changed.
//
// The field is resolved lazily: a query that does not select `changes` reads
// no diff, so a `checkpoints` list stays as cheap as the timeline read. The
// diff comes from the diff provider of the endpoint, which the context of the
// call carries, and which is `SnapshotStore.diff(sessionKey:index:path:)`
// unless a test injects another one.

import FoundationModelsExtras
import FoundationModelsHooks
import Graphiti

/// Reads the unified diff of one file of one checkpoint: the session key, the
/// index of the checkpoint (from 1) and the path of the file, relative to the
/// work tree. It throws a ``SnapshotError`` for an error of the store.
typealias SnapshotsGraphDiffProvider =
    @Sendable (_ sessionKey: String, _ index: Int, _ path: String) async throws -> String

/// The `FileChange` object: one file that a checkpoint changed, with its diff.
struct SnapshotsGraphFileChange: Codable, Sendable {
    /// The path of the file, relative to the work tree.
    let path: String

    /// The unified diff of the file, from the tree before the checkpoint to
    /// the tree after it.
    let diff: String
}

extension SnapshotsGraphCheckpoint {
    /// Resolves `Checkpoint.changes`: the diff of each file of ``files``, in
    /// the same order. It reads the diffs only when a query selects the field.
    ///
    /// - Parameters:
    ///   - context: The context of the call, which gives the diff provider.
    ///   - arguments: No argument.
    /// - Returns: One change for each file that the checkpoint changed.
    /// - Throws: A ``SnapshotsGraphError`` for each store error. Each other
    ///   error, for example a libgit2 failure, stays as it is and gives the
    ///   `INTERNAL` code of the toolkit.
    func changes(context: SnapshotsGraphContext, arguments _: NoArguments) async throws
        -> [SnapshotsGraphFileChange]
    {
        do {
            var changes: [SnapshotsGraphFileChange] = []
            for path in files {
                let diff = try await context.diff(sessionKey, index, path)
                changes.append(SnapshotsGraphFileChange(path: path, diff: diff))
            }
            return changes
        } catch let error as SnapshotError {
            throw SnapshotsGraphError.coded(error, sessionId: sessionId)
        }
    }
}

extension SnapshotsGraphAPI {
    /// The `FileChange` type.
    ///
    /// - Returns: The type.
    static func fileChangeType() -> SchemaType {
        Type(SnapshotsGraphFileChange.self, as: "FileChange") {
            Field("path", at: \.path).description("The path of the file, relative to the working folder.")
            Field("diff", at: \.diff)
                .description(
                    "The unified diff of the file, as git diff gives it. An added file diffs from /dev/null, a "
                        + "deleted file to /dev/null, and a binary file gives a 'Binary files ... differ' line.")
        }
        .description("One file that a checkpoint changed, with its diff.")
    }
}
