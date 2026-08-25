// `AtomicWriter` — atomic file writes plus the encoding and line-ending
// conventions the file verbs preserve.
//
// A behavioral port of `../FoundationModelsFileTool/Sources/FileTool/
// AtomicWriter.swift`. The sibling declares the type `public` for its own
// module surface; this package keeps it internal, the same way `Hashline`,
// `PathGuard`, and `PathCorrective` beside it do.
//
// eventplan.md § "Consolidation of the siblings": the Files capability gets
// `AtomicWriter`, and capabilities keep their own serialization where order
// is important (atomic file writes). The write verb (task ^p238zzp) and the
// edit verb (task ^v5xap97, which commits `EditEngine`'s content) consume
// this primitive; until they land, the ported suite (`AtomicWriterTests`)
// is the one caller.

import Darwin
import Foundation

/// Writes file bytes atomically and owns the encoding and line-ending conventions the write and edit operations preserve.
///
/// The write path never mutates the target in place. It writes the new bytes
/// to a sibling temporary file — `{path}.tmp.{UUID}` in the *same directory*
/// as the target, thus the final ``Foundation/FileManager``-free `rename`
/// stays on one filesystem and is therefore atomic — and only then renames
/// the temporary file onto the target, which atomically replaces any existing
/// file. A single cleanup path removes the temporary file on *any* failure (a
/// failed write, a failed permission re-application, or a failed rename),
/// thus an interrupted write can never leave a partial file or a stray
/// temporary behind. When the target already exists, its permission bits are
/// re-applied to the replacement, thus overwriting, for example, a `0755`
/// script keeps it executable.
///
/// The type also owns the text conventions the operations must preserve
/// across a rewrite: byte-order-mark-aware ``TextEncoding`` detection with a
/// UTF-8 fallback (``decode(_:)``), symmetric re-encoding (``encode(_:as:)``),
/// and ``LineEnding`` detection (``detectLineEnding(in:)``). The `write file`
/// operation writes freshly supplied UTF-8 content, thus it uses only the
/// write path; the `edit file` operation reads an existing file, detects its
/// encoding and line ending, and re-encodes the edited text with the same
/// convention, thus it consumes the detection and re-encode hooks as well.
enum AtomicWriter {
    // MARK: Temporary-file naming

    /// The infix between the target path and the unique suffix of a temporary file name.
    ///
    /// A temporary file is named `{target path}\(temporaryFileInfix){UUID}`,
    /// thus it sits in the same directory as the target and a directory scan
    /// can recognize a leftover by this infix.
    private static let temporaryFileInfix = ".tmp."

    // MARK: Write path

    /// A write prepared on disk but not yet committed onto its destination.
    ///
    /// ``AtomicWriter/stage(_:to:)`` returns one of these after writing the
    /// new bytes to a sibling temporary file (permission bits already applied)
    /// but *before* renaming it onto the destination. This splits the
    /// single-shot ``AtomicWriter/write(_:to:)`` into two phases, thus a
    /// multi-file patch can stage every file first and only then ``commit()``
    /// them, shrinking the partial-write window to the sequence of renames. On
    /// any staging failure or an abandoned patch, ``discard()`` removes the
    /// temporary file, leaving the destination untouched.
    struct StagedWrite {
        /// The sibling temporary file holding the staged bytes.
        let temporaryURL: URL

        /// The destination the staged bytes commit onto.
        let destinationURL: URL

        /// The destination's permission bits when it already existed, else `nil`.
        ///
        /// Captured at stage time and already applied to ``temporaryURL``,
        /// thus the commit is a pure rename; retained for inspection and thus
        /// the staging contract is visible on the value.
        let permissionBits: mode_t?

        /// Rename the staged temporary file onto its destination, atomically.
        ///
        /// The commit phase of a staged write: a single POSIX `rename` that
        /// atomically replaces any existing destination on one filesystem.
        /// The caller removes the temporary file via ``discard()`` if a
        /// commit in a multi-file sequence fails.
        ///
        /// - Throws: an ``AtomicWriteError`` when the rename fails.
        func commit() throws {
            try AtomicWriter.rename(temporaryURL, onto: destinationURL)
        }

        /// Remove the staged temporary file, leaving the destination untouched.
        ///
        /// Idempotent and non-throwing: a `discard()` after a successful
        /// ``commit()`` (the temporary file is gone, renamed onto the
        /// destination) or a second `discard()` is a no-op, thus it is safe
        /// to call on every staged write when rolling back an abandoned
        /// patch.
        func discard() {
            try? FileManager.default.removeItem(at: temporaryURL)
        }
    }

    /// Stage `data` for `url`: write it to a sibling temp without committing.
    ///
    /// The preparation phase of an atomic write. Creates the target's parent
    /// directories if they do not exist, writes the bytes to a sibling
    /// temporary file in the destination's own directory, and re-applies the
    /// destination's existing permission bits when overwriting — but does
    /// *not* rename onto the destination, thus the destination is untouched
    /// until ``StagedWrite/commit()``. On any failure the temporary file is
    /// removed and the error is rethrown, leaving nothing behind.
    ///
    /// - Parameters:
    ///   - data: the bytes to stage.
    ///   - url: the destination file URL.
    /// - Returns: a ``StagedWrite`` ready to commit or discard.
    /// - Throws: the underlying error when creating a directory or writing the
    ///   bytes fails, or an ``AtomicWriteError`` when re-applying permissions fails.
    static func stage(_ data: Data, to url: URL) throws -> StagedWrite {
        let originalPermissions = existingPermissionBits(of: url)
        try createParentDirectory(of: url)
        let temporaryURL = makeTemporaryURL(for: url)
        do {
            try data.write(to: temporaryURL)
            if let originalPermissions {
                try applyPermissionBits(originalPermissions, to: temporaryURL)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
        return StagedWrite(temporaryURL: temporaryURL, destinationURL: url, permissionBits: originalPermissions)
    }

    /// Write `data` to `url` atomically, creating parents and preserving permissions.
    ///
    /// A single-shot ``stage(_:to:)`` immediately followed by
    /// ``StagedWrite/commit()``, thus one temp+rename implementation serves
    /// both the single-file write and the multi-file staged commit. Creates
    /// the target's parent directories if they do not exist, writes the bytes
    /// to a sibling temporary file, re-applies the original file's permission
    /// bits when overwriting, and renames the temporary file onto the target.
    /// On any failure the temporary file is removed and the error is
    /// rethrown, leaving the target untouched.
    ///
    /// - Parameters:
    ///   - data: the bytes to write.
    ///   - url: the destination file URL.
    /// - Throws: an ``AtomicWriteError`` when the rename fails, or the
    ///   underlying error when creating a directory or writing the bytes fails.
    static func write(_ data: Data, to url: URL) throws {
        let staged = try stage(data, to: url)
        do {
            try staged.commit()
        } catch {
            staged.discard()
            throw error
        }
    }

    /// The sibling temporary-file URL for a target, in the target's own directory.
    ///
    /// - Parameter url: the destination file URL.
    /// - Returns: a `{path}\(temporaryFileInfix){UUID}` URL in the same directory.
    private static func makeTemporaryURL(for url: URL) -> URL {
        URL(fileURLWithPath: url.path + temporaryFileInfix + UUID().uuidString)
    }

    /// Create the target's parent directory, including any missing intermediate directories.
    ///
    /// A no-op when the parent already exists. Extracted, thus the write path
    /// reads as a single sequence of steps.
    ///
    /// - Parameter url: the destination file URL whose parent to create.
    /// - Throws: the underlying error when the directory cannot be created.
    private static func createParentDirectory(of url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    /// Rename `source` onto `destination`, atomically replacing any existing file.
    ///
    /// Uses the POSIX `rename`, thus the replacement is atomic on a single
    /// filesystem; a failure (for example, when `destination` is an existing
    /// directory) is surfaced as an ``AtomicWriteError`` carrying the `errno`
    /// description.
    ///
    /// - Parameters:
    ///   - source: the temporary file to rename.
    ///   - destination: the target to replace.
    /// - Throws: an ``AtomicWriteError`` when the rename fails.
    private static func rename(_ source: URL, onto destination: URL) throws {
        let result = source.path.withCString { sourcePath in
            destination.path.withCString { destinationPath in
                Darwin.rename(sourcePath, destinationPath)
            }
        }
        guard result == 0 else {
            throw AtomicWriteError("could not replace \(destination.path): \(String(cString: strerror(errno)))")
        }
    }

    // MARK: Permission preservation

    /// The permission bits (`mode & 0o777`) of `url` when it already exists, else `nil`.
    ///
    /// - Parameter url: the file URL to inspect.
    /// - Returns: the permission bits when the file exists and can be stat-ed,
    ///   or `nil` when it does not exist (a fresh write, with nothing to preserve).
    private static func existingPermissionBits(of url: URL) -> mode_t? {
        var status = stat()
        guard stat(url.path, &status) == 0 else { return nil }
        return status.st_mode & permissionBitMask
    }

    /// Re-apply permission `bits` to `url`.
    ///
    /// - Parameters:
    ///   - bits: the permission bits to set.
    ///   - url: the file URL to change.
    /// - Throws: an ``AtomicWriteError`` when `chmod` fails.
    private static func applyPermissionBits(_ bits: mode_t, to url: URL) throws {
        let result = url.path.withCString { chmod($0, bits) }
        guard result == 0 else {
            throw AtomicWriteError("could not re-apply permissions to \(url.path): \(String(cString: strerror(errno)))")
        }
    }

    /// The mask selecting the user/group/other permission bits from a file mode.
    private static let permissionBitMask: mode_t = 0o777

    // MARK: Encoding detection and re-encode

    /// A text encoding the operations detect and preserve across a rewrite.
    ///
    /// Limited to the byte-order-mark-aware UTF-8 forms the file operations
    /// support; the raw name reads directly into an operation result's
    /// encoding field.
    enum TextEncoding: String, Sendable {
        /// UTF-8 with no byte-order mark.
        case utf8 = "utf-8"

        /// UTF-8 preceded by a byte-order mark.
        case utf8WithByteOrderMark = "utf-8 bom"
    }

    /// Decoded text paired with the encoding it was decoded from.
    ///
    /// Re-encoding ``text`` with ``encoding`` via ``AtomicWriter/encode(_:as:)``
    /// reproduces the original bytes, thus an edit can preserve the file's
    /// encoding without inspecting the raw bytes again.
    struct DecodedText: Sendable {
        /// The detected encoding of the source bytes.
        let encoding: TextEncoding

        /// The decoded text, with any byte-order mark stripped.
        let text: String
    }

    /// The first byte of the UTF-8 byte-order mark. Its value is `0xEF`.
    private static let utf8ByteOrderMarkFirstByte: UInt8 = 0xEF

    /// The second byte of the UTF-8 byte-order mark. Its value is `0xBB`.
    private static let utf8ByteOrderMarkSecondByte: UInt8 = 0xBB

    /// The third byte of the UTF-8 byte-order mark. Its value is `0xBF`.
    private static let utf8ByteOrderMarkThirdByte: UInt8 = 0xBF

    /// The UTF-8 byte-order mark bytes (`EF BB BF`).
    private static let utf8ByteOrderMark: [UInt8] = [
        utf8ByteOrderMarkFirstByte,
        utf8ByteOrderMarkSecondByte,
        utf8ByteOrderMarkThirdByte,
    ]

    /// Decode file bytes to text, detecting the encoding from a leading byte-order mark.
    ///
    /// Bytes beginning with the UTF-8 byte-order mark decode as
    /// ``TextEncoding/utf8WithByteOrderMark`` with the mark stripped from the
    /// returned text; all other bytes are decoded as plain
    /// ``TextEncoding/utf8``. Bytes that are not valid UTF-8 (a binary file)
    /// yield `nil` rather than a lossy decode.
    ///
    /// - Parameter data: the raw file bytes.
    /// - Returns: the decoded text and its encoding, or `nil` when the bytes
    ///   are not valid UTF-8.
    static func decode(_ data: Data) -> DecodedText? {
        if data.starts(with: utf8ByteOrderMark) {
            return decodeAsUTF8(from: data.dropFirst(utf8ByteOrderMark.count), encoding: .utf8WithByteOrderMark)
        }
        return decodeAsUTF8(from: data, encoding: .utf8)
    }

    /// The decoded text of the file at `url`, or `nil` when it is absent, unreadable, or not text.
    ///
    /// The best-effort read behind the change projection: the bytes a `write
    /// file` is about to clobber, or the bytes a patch's Delete is about to
    /// remove. It never throws and never fails a mutation — a missing,
    /// unreadable, or binary (undecodable) file yields `nil`, which the
    /// projection reports as text it could not capture rather than as an
    /// empty file.
    ///
    /// - Parameter url: the file to read.
    /// - Returns: the decoded text, or `nil`.
    static func decodedText(at url: URL) -> String? {
        (try? Data(contentsOf: url)).flatMap { decode($0)?.text }
    }

    /// Decode UTF-8 bytes, tagging the result with the encoding they came from.
    ///
    /// The guard-decode-return pattern shared by both branches of
    /// ``decode(_:)``: bytes that are not valid UTF-8 (a binary file) yield
    /// `nil` rather than a lossy decode.
    ///
    /// - Parameters:
    ///   - data: the UTF-8 bytes to decode, with any byte-order mark already stripped.
    ///   - encoding: the encoding to pair the decoded text with.
    /// - Returns: the decoded text paired with `encoding`, or `nil` when the
    ///   bytes are not valid UTF-8.
    private static func decodeAsUTF8(from data: Data, encoding: TextEncoding) -> DecodedText? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return DecodedText(encoding: encoding, text: text)
    }

    /// Encode `text` as `encoding`, re-applying a byte-order mark when required.
    ///
    /// The inverse of ``decode(_:)``: encoding decoded text with its detected
    /// encoding reproduces the original bytes.
    ///
    /// - Parameters:
    ///   - text: the text to encode.
    ///   - encoding: the encoding to produce.
    /// - Returns: the encoded bytes.
    static func encode(_ text: String, as encoding: TextEncoding) -> Data {
        var data = Data()
        if encoding == .utf8WithByteOrderMark {
            data.append(contentsOf: utf8ByteOrderMark)
        }
        data.append(Data(text.utf8))
        return data
    }

    // MARK: Line-ending detection

    /// The line-ending convention of a text.
    ///
    /// The raw name reads directly into an operation result's line-ending field.
    enum LineEnding: String, Sendable {
        /// Every line ends with a line feed (`\n`).
        case lineFeed = "lf"

        /// Every line ends with a carriage return then a line feed (`\r\n`).
        case carriageReturnLineFeed = "crlf"

        /// Every line ends with a bare carriage return (`\r`).
        case carriageReturn = "cr"

        /// Lines end with more than one distinct terminator.
        case mixed = "mixed"
    }

    /// The terminator strings that map to each single-convention ``LineEnding``.
    ///
    /// Detection is data, not control flow: the set of distinct terminators
    /// is looked up here, thus recognizing a convention and reporting `mixed`
    /// share one code path and cannot drift apart.
    private static let lineEndingByTerminator: [String: LineEnding] = [
        "\n": .lineFeed,
        "\r\n": .carriageReturnLineFeed,
        "\r": .carriageReturn,
    ]

    /// Detect the line-ending convention of `text`.
    ///
    /// Reuses ``Hashline/splitLines(_:)`` — the single line model the anchors
    /// are numbered against — to collect the distinct terminators present.
    /// Text with a single terminator kind reports that convention; text with
    /// more than one reports ``LineEnding/mixed``; text with no line breaks
    /// reports `nil`.
    ///
    /// - Parameter text: the text to inspect.
    /// - Returns: the detected line ending, or `nil` when `text` has no line breaks.
    static func detectLineEnding(in text: String) -> LineEnding? {
        var terminators: Set<String> = []
        for line in Hashline.splitLines(text) where !line.terminator.isEmpty {
            terminators.insert(line.terminator)
        }
        guard let onlyTerminator = terminators.first else { return nil }
        return terminators.count == 1 ? lineEndingByTerminator[onlyTerminator] : .mixed
    }
}

/// A failed atomic write, carrying a description of the underlying failure.
///
/// Thrown by ``AtomicWriter`` when a `rename` or `chmod` fails; the
/// operations layer catches it and returns a corrective message rather than
/// propagating a throw out of an operation's `execute(in:)`.
struct AtomicWriteError: Error, CustomStringConvertible {
    /// The description of what failed.
    let description: String

    /// Creates an atomic-write error.
    ///
    /// - Parameter description: the description of what failed.
    init(_ description: String) {
        self.description = description
    }
}
