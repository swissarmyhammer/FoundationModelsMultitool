// `Write` — the `tools.files.write` verb.
//
// A behavioral port of `../FoundationModelsFileTool/Sources/FileTool/
// Operations/WriteFile.swift`. The sibling is an `@Operation` that takes a
// `FileContext` through its `execute(in:)`; this package has no operation
// machinery, thus the verb is a plain `FoundationModels.Tool` that holds
// the context it writes against, in the pattern of `Capabilities/Files/
// Read.swift`. The sibling's `@OperationParam` aliases (`path`,
// `absolute_path`) do not port: plain `@Generable` arguments keep only the
// canonical names. The sibling's `WriteOutput` enum does not port either:
// the flat result carries a `correction` field in its place. The sibling
// folded compiler diagnostics into its result through `DiagnosticsBridge`;
// decision 2026-08-11 in eventplan.md removes the bridge from this package,
// thus the result carries no diagnostics field and the write folds nothing.
//
// eventplan.md § "Registration of capabilities: noun/verb": the capability
// supplies the noun, thus this verb's `name` is the bare `write` and the
// surface path renders as `tools.files.write`.
//
// A write the verb cannot make stays IN BAND, as a `correction` beside
// empty envelope fields. It is never thrown: an over-cap content, a path
// outside the root, a read-only target, a read-only session, and a failed
// write are each a mistake the model corrects inside the turn, and a
// thrown error would end the turn instead.

import Foundation
import FoundationModels

/// The arguments of `tools.files.write`: the file to write and the content
/// to put in it.
@Generable
struct WriteArguments {

    /// The path of the file to write.
    @Guide(description: "The path of the file to write, absolute or relative to the session root.")
    var path: String

    /// The content to write, replacing any existing file whole.
    @Guide(description: "The full content to write. The write replaces any existing file whole.")
    var content: String
}

/// The result of `tools.files.write`: the written file's envelope, or the
/// correction that says why nothing was written.
///
/// `correction` and the envelope are exclusive. A write that lands carries
/// no correction, and a correction carries an empty `path`, a zero
/// `bytesWritten`, an empty `hash`, and no tagged line.
@Generable(
    description: "the written file's envelope, or the correction that says why nothing was written.")
struct WriteResult {

    /// The absolute path written, resolved through the session's path guard. Empty on a correction.
    var path: String

    /// The number of UTF-8 bytes written. Zero on a correction.
    var bytesWritten: Int

    /// The whole-file freshness token: the lowercase-hex MD5 over the bytes
    /// just written, exactly as a subsequent read of the same path computes
    /// it. Empty on a correction.
    var hash: String

    /// The written content tagged with absolute `N:HH|text` hashline
    /// anchors, one entry per line, identical to a subsequent read's lines.
    var taggedContent: [String]

    /// Why nothing was written, or `nil` when the envelope stands.
    var correction: String?
}

extension Write {

    // MARK: Content-size cap

    /// The number of bytes in one mebibyte.
    private static let bytesPerMebibyte = 1024 * 1024

    /// The maximum accepted content size in mebibytes, matching the Rust `files` tool.
    private static let maximumContentMebibytes = 10

    /// The maximum accepted content size in UTF-8 bytes (the 10 MiB write cap).
    private static let maximumContentByteCount = maximumContentMebibytes * bytesPerMebibyte

    /// A corrective message when `content` exceeds the size cap, or `nil` when acceptable.
    ///
    /// The size is measured in UTF-8 bytes — the bytes actually written —
    /// thus a multi-byte scalar counts as its encoded length. Content
    /// exactly at the cap is accepted; only content strictly larger is
    /// rejected.
    ///
    /// - Parameter content: the content to check.
    /// - Returns: the ``overSizeMessage`` when `content` is over the cap, else `nil`.
    private static func contentSizeViolation(content: String) -> String? {
        content.utf8.count > maximumContentByteCount ? overSizeMessage : nil
    }

    /// The corrective message naming the content-size cap.
    private static var overSizeMessage: String {
        "The `content` parameter must be at most \(maximumContentMebibytes) MiB (\(maximumContentByteCount) bytes)."
    }

    // MARK: Corrective messages

    /// The corrective message for a write on a read-only session.
    private static let readOnlySessionMessage =
        "The session is read-only, so the `write` verb cannot change files."

    /// A corrective message for a path that validated but could not be written.
    ///
    /// - Parameter path: the requested path.
    /// - Returns: the corrective message.
    private static func writeFailureMessage(path: String) -> String {
        "The file could not be written: \(path)"
    }

    /// A result carrying only a correction: empty path, zero bytes, empty
    /// hash, no tagged line.
    ///
    /// - Parameter message: the correction the model reads and acts on.
    /// - Returns: the corrective ``WriteResult``.
    private static func corrective(_ message: String) -> WriteResult {
        WriteResult(path: "", bytesWritten: 0, hash: "", taggedContent: [], correction: message)
    }

    // MARK: Change recording

    /// The change this write makes, as it must be captured *before* the write.
    ///
    /// A path with nothing at it is a ``FileChangeKind/add``; an existing
    /// file is a ``FileChangeKind/modify`` carrying the text about to be
    /// overwritten, which is unrecoverable once the clobbering write lands.
    /// That old text is `nil` when the file's bytes cannot be read or are
    /// not decodable text (a binary file), thus the rendered patch reports
    /// the file as binary rather than inventing a diff against nothing.
    ///
    /// - Parameters:
    ///   - content: the content about to be written.
    ///   - url: the resolved target URL.
    /// - Returns: the change the write will make.
    private static func change(writing content: String, to url: URL) -> FileChange {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return FileChange(kind: .add, path: url.path, newContent: content)
        }
        return FileChange(
            kind: .modify,
            path: url.path,
            oldContent: AtomicWriter.decodedText(at: url),
            newContent: content
        )
    }

    // MARK: Execution

    /// Writes the content and answers the envelope, or the correction that
    /// says why nothing was written.
    ///
    /// Rejects a read-only session, then over-cap content, then validates
    /// the path via the context's ``PathGuard`` for a write, then writes
    /// the UTF-8 content through ``AtomicWriter``. When the session's
    /// ``FileChangeJournal`` records, the change is captured before the
    /// write (the overwritten text is gone afterward) and recorded once the
    /// write commits. Each recoverable failure comes back as the
    /// `correction` field of the result; nothing here throws for an
    /// over-cap content, a bad path, or a failed write.
    ///
    /// - Parameter arguments: What to write and where.
    /// - Returns: The written envelope, or the correction.
    func call(arguments: WriteArguments) async throws -> WriteResult {
        if context.readOnly { return Self.corrective(Self.readOnlySessionMessage) }
        if let message = Self.contentSizeViolation(content: arguments.content) {
            return Self.corrective(message)
        }

        return await context.pathGuard.validate(arguments.path, for: .write)
            .resolveAsync(corrective: Self.corrective) { url in
                // Captured before the write: afterward the overwritten text is gone.
                let change = context.changes.isRecording ? Self.change(writing: arguments.content, to: url) : nil
                let data = Data(arguments.content.utf8)
                do {
                    try AtomicWriter.write(data, to: url)
                } catch {
                    return Self.corrective(Self.writeFailureMessage(path: arguments.path))
                }
                if let change { await context.changes.record(change) }

                return WriteResult(
                    path: url.path,
                    bytesWritten: data.count,
                    hash: Hashline.wholeFileHash(bytes: data),
                    taggedContent: Hashline.taggedLines(of: arguments.content),
                    correction: nil
                )
            }
    }
}

/// Writes content to a file atomically, returning its freshness token and
/// hashline-tagged content.
///
/// ```swift
/// // In a snippet the model writes:
/// //   const saved = await tools.files.write({ path: "notes/draft.md", content: "# Draft\n" });
/// ```
///
/// The contract: the write goes through ``AtomicWriter`` — the new bytes
/// land in a sibling temporary file and an atomic rename replaces the
/// target, thus an interrupted write never leaves a partial file or a
/// stray temporary behind, and overwriting preserves the target's
/// permission bits. The write is an unconditional clobber — there is no
/// freshness precondition, matching the upstream `files` tool, where
/// lost-update protection lives in anchored edits rather than in the
/// write. The result's `hash` is the whole-file freshness token over the
/// written bytes and `taggedContent` is those bytes tagged with absolute
/// `N:HH|text` anchors, both exactly as a subsequent read of the same path
/// computes them, thus a chained edit resolves anchors without an
/// intervening read. The path is bounded through the session's
/// ``PathGuard``, and the session's ``FileChangeJournal`` records the
/// change when it is recording. Content over the 10 MiB cap, a path
/// outside the root, a read-only target, a read-only session, and a
/// failed write each come back as a `correction` rather than as an error.
///
/// The context it writes against is the context the files capability owns,
/// thus each verb of one capability answers for the same session.
struct Write: Tool {

    /// The verb this tool renders as, which the files noun stands in front
    /// of: `tools.files.write`.
    let name = "write"

    /// The usage instructions, as the model reads them.
    let description = """
        write writes content to a file atomically, replacing any existing file whole. The \
        result carries bytesWritten, the whole-file freshness hash over the written bytes, \
        and taggedContent — the written lines tagged as N:HH|text, identical to what a \
        subsequent read returns, thus a chained edit resolves anchors without an intervening \
        read. Content over 10 MiB, a path outside the session root, a read-only target, a \
        read-only session, and a failed write each come back as a correction rather than as \
        an error — read it, correct the call, and ask again.
        """

    /// The session context this verb writes against, which the files capability owns.
    ///
    /// The compiler-synthesized memberwise initializer takes this one
    /// property, thus the capability makes the verb as `Write(context:)`.
    let context: FileContext
}
