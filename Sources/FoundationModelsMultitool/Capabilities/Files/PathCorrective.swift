// `PathCorrective` — the shared corrective vocabulary of a failed-path
// operation.
//
// A behavioral port of `../FoundationModelsFileTool/Sources/FileTool/
// PathCorrective.swift`. `UnreadableFile` conforms to the `CorrectiveFailure`
// protocol from `CorrectiveResult.swift` beside it, the same way the
// sibling's does, thus a read failure resolves through
// `Result.resolve(corrective:then:)` like every other corrective failure.
//
// eventplan.md § "Consolidation of the siblings": a corrective result stays
// in band, never thrown. The read and edit verbs both validate a path via
// `PathGuard`, then attempt to read its on-disk bytes, and both report a
// read failure with the identical leading description before the requested
// path. This type derives `unreadableDescription` and
// `pathErrorMessage(description:path:)` one time, thus the wording — and
// the `<description>: <path>` shape it renders in — cannot drift between
// the two operations.
//
// Each operation's binary-file description differs in wording (`read` vs.
// `edit`), and the commit-failure description exists only for the edit
// verb. Thus those stay local to their own operation, and they compose only
// through `pathErrorMessage(description:path:)` rather than living here.

import Foundation

/// The shared corrective vocabulary of a failed-path operation.
///
/// One template renders each failed-path corrective, thus the wording and
/// the `<description>: <path>` shape live in one place and cannot drift
/// between the operations that compose them.
enum PathCorrective {
    /// The description of a path that validated but whose bytes could not be read, before the `: path` suffix.
    static let unreadableDescription = "The file could not be read"

    /// A corrective message for a failed path, formatted as `<description>: <path>`.
    ///
    /// The single template behind every failed-path corrective — an
    /// unreadable file, a binary file, or a failed commit — which differ
    /// only by their leading description. Thus the shared
    /// `<description>: <path>` shape lives in one place and cannot drift
    /// between the operations that compose it.
    ///
    /// - Parameters:
    ///   - description: the leading description of what went wrong.
    ///   - path: the requested path.
    /// - Returns: the corrective message.
    static func pathErrorMessage(description: String, path: String) -> String {
        "\(description): \(path)"
    }

    /// A failure reading an already-validated path's on-disk bytes.
    ///
    /// Exists only so ``readData(at:path:)`` can return a `Result`
    /// (`Failure` must be an `Error`) while it still reduces to one
    /// corrective string via ``CorrectiveFailure``, the same way
    /// ``PathViolation`` does for its own `Result` failures.
    struct UnreadableFile: CorrectiveFailure, Equatable, Sendable, CustomStringConvertible {
        /// The originally requested path, echoed in the corrective message.
        let path: String

        /// The corrective message that says why the file could not be read.
        var correctiveMessage: String {
            PathCorrective.pathErrorMessage(description: PathCorrective.unreadableDescription, path: path)
        }

        /// The failure's textual representation, which is its ``correctiveMessage``.
        var description: String { correctiveMessage }
    }

    /// Reads the on-disk bytes at an already-validated path, or the unreadable-file corrective.
    ///
    /// The read and edit verbs both validate a path via ``PathGuard`` and
    /// then need its raw bytes before anything else, and both report the
    /// same ``unreadableDescription`` when the read itself fails. This is
    /// that read, written one time, thus neither operation carries its own
    /// `do`/`catch` around `Data(contentsOf:)`.
    ///
    /// - Parameters:
    ///   - url: the resolved, already-validated path to read.
    ///   - path: the originally requested path, echoed in the corrective message.
    /// - Returns: the file's bytes on success, or an ``UnreadableFile`` failure on failure.
    static func readData(at url: URL, path: String) -> Result<Data, UnreadableFile> {
        do {
            return .success(try Data(contentsOf: url))
        } catch {
            return .failure(UnreadableFile(path: path))
        }
    }
}
