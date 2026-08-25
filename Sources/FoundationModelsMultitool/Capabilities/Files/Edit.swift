// `Edit` — the `tools.files.edit` verb.
//
// A behavioral port of `../FoundationModelsFileTool/Sources/FileTool/
// Operations/EditFile.swift`. The sibling is an `@Operation` that takes a
// `FileContext` through its `execute(in:)`; this package has no operation
// machinery, thus the verb is a plain `FoundationModels.Tool` that holds
// the context it edits against, in the pattern of `Capabilities/Files/
// Write.swift`. The sibling's `@OperationParam` aliases (`path`,
// `absolute_path`, the find and replace dialects) do not port: plain
// `@Generable` arguments keep only the canonical names. The sibling's
// `EditOutput` enum does not port either: the flat result carries a
// `correction` field in its place, and the per-pair outcomes ride as JSON
// text encoded from the `EditOutcomeProjection` wire types. The sibling
// folded compiler diagnostics into its result through `DiagnosticsBridge`;
// decision 2026-08-11 in eventplan.md removes the bridge from this package,
// thus the result carries no diagnostics field and the edit folds nothing.
//
// eventplan.md § "Registration of capabilities: noun/verb": the capability
// supplies the noun, thus this verb's `name` is the bare `edit` and the
// surface path renders as `tools.files.edit`.
//
// An edit the verb cannot make stays IN BAND, as a `correction` beside
// empty envelope fields. It is never thrown: a payload that cannot
// normalize, a path outside the root, a missing or binary file, a
// read-only target, a read-only session, and a failed commit are each a
// mistake the model corrects inside the turn, and a thrown error would end
// the turn instead. The structured retryable outcomes (`ambiguous`,
// `nearMiss`, `alreadyApplied`, `consumedTarget`) are not corrections:
// they ride in the result's `status` and `outcomes`, and they leave the
// file byte-identical.

import Foundation
import FoundationModels

/// The arguments of `tools.files.edit`: the file to edit and the
/// find/replace batch to apply.
@Generable
struct EditArguments {

    /// The path of the file to edit.
    @Guide(description: "The path of the file to edit, absolute or relative to the session root.")
    var path: String

    /// The `find` values to locate: one for a scalar edit, several for a
    /// parallel-array batch. Each value is a literal text or a hashline
    /// anchor.
    @Guide(
        description:
            "The find values to locate: one for a single edit, several for a batch. Each value "
            + "is a literal text or an N:HH|text hashline anchor from a prior read or write.")
    var find: [String]?

    /// The `replace` values: one per `find`, or a single value broadcast
    /// across every `find`.
    @Guide(
        description:
            "The replace values: one per find, or a single value applied to every find.")
    var replace: [String]?

    /// Whether every occurrence of each `find` is rewritten rather than a
    /// single one, or `nil` for the default (`false`).
    @Guide(
        description:
            "Whether every occurrence of each find is rewritten. Omit it to rewrite a single "
            + "occurrence.")
    var replacesAll: Bool?

    /// The 1-based occurrence selector that disambiguates among literal
    /// candidates, or `nil` for none.
    @Guide(
        description:
            "The 1-based occurrence to select when a find matches several sites. Omit it when "
            + "the find is unique.")
    var occurrence: Int?
}

/// The result of `tools.files.edit`: the batch status with its per-pair
/// outcomes and — when applied — the commit envelope, or the correction
/// that says why nothing was resolved.
///
/// `correction` and the batch fields are exclusive. A resolved batch
/// carries no correction, and a correction carries an empty `path`, an
/// empty `status`, a zero `applied`, no outcome, and no commit field. The
/// commit-only fields (`bytesWritten`, `encoding`, `lineEndings`, `hash`,
/// `taggedContent`) are `nil` unless the `status` is `applied`: a
/// structured retryable outcome commits nothing and leaves the file
/// byte-identical.
@Generable(
    description:
        "the edit batch's status, per-pair outcomes, and commit envelope, or the correction that says why nothing was resolved."
)
struct EditResult {

    /// The absolute path edited, resolved through the session's path guard. Empty on a correction.
    var path: String

    /// The whole-batch status: `applied`, `ambiguous`, `nearMiss`,
    /// `alreadyApplied`, or `consumedTarget`. Empty on a correction.
    var status: String

    /// The number of pairs applied; `0` unless `status` is `applied`.
    var applied: Int

    /// The per-pair outcomes as JSON text with sorted keys, one entry per
    /// pair: each carries `matchedBy` and `find`, plus the resolved `line`
    /// for an anchor match, the `candidates` of an ambiguous outcome, the
    /// `nearMisses` diffs of a near-miss, or the `note` of a
    /// reclassification. One entry per applied pair for an `applied`
    /// result, or the single unresolved pair otherwise. Empty on a
    /// correction.
    var outcomes: [String]

    /// The number of bytes committed, or `nil` when nothing was committed.
    var bytesWritten: Int?

    /// The detected, preserved encoding (`utf-8`, `utf-8 bom`), or `nil` when nothing was committed.
    var encoding: String?

    /// The detected, preserved line-ending convention (`lf`, `crlf`, `cr`,
    /// `mixed`), or `nil` when nothing was committed or the file has no
    /// line break.
    var lineEndings: String?

    /// The whole-file freshness token over the committed bytes, exactly as
    /// a subsequent read computes it, or `nil` when nothing was committed.
    var hash: String?

    /// The committed content tagged with absolute `N:HH|text` hashline
    /// anchors, identical to a subsequent read's lines, or `nil` when
    /// nothing was committed.
    var taggedContent: [String]?

    /// Why nothing was resolved, or `nil` when the batch fields stand.
    var correction: String?
}

extension Edit {

    // MARK: Parameter defaults

    /// The `replacesAll` behavior used when the parameter is absent.
    private static let defaultReplacesAll = false

    // MARK: Corrective messages

    /// The corrective message for an edit on a read-only session.
    private static let readOnlySessionMessage =
        "The session is read-only, so the `edit` verb cannot change files."

    /// The description of a non-UTF-8 (binary) file, which is never decoded, before the `: path` suffix.
    ///
    /// Composed with ``PathCorrective/pathErrorMessage(description:path:)``
    /// at the call site; the unreadable-path description lives there too
    /// (``PathCorrective/unreadableDescription``), since it is
    /// byte-identical to the read verb's, while this wording is
    /// edit-specific.
    private static let binaryDescription =
        "The file is not valid UTF-8 text and appears to be binary, so it cannot be edited as text"

    /// The description of a resolved batch whose atomic commit failed, before the `: path` suffix.
    private static let commitFailureDescription = "The edit resolved but could not be committed"

    /// A result carrying only a correction: empty path, empty status, zero
    /// applied, no outcome, no commit field.
    ///
    /// - Parameter message: the correction the model reads and acts on.
    /// - Returns: the corrective ``EditResult``.
    private static func corrective(_ message: String) -> EditResult {
        EditResult(
            path: "",
            status: "",
            applied: 0,
            outcomes: [],
            bytesWritten: nil,
            encoding: nil,
            lineEndings: nil,
            hash: nil,
            taggedContent: nil,
            correction: message
        )
    }

    // MARK: Outcome encoding

    /// Encodes one wire outcome to its JSON text with sorted keys.
    ///
    /// ``EditOutcomeProjection`` maps each ``EditEngine/Resolution`` to its
    /// `Encodable` wire type, and
    /// ``EditOutcomeProjection/encodedText(_:)`` — the encoder this verb
    /// shares with the patch verb — turns that wire value into the result's
    /// text.
    ///
    /// - Parameter outcome: the wire outcome to encode.
    /// - Returns: the JSON text.
    private static func encodedOutcome(_ outcome: EditOutcome) -> String {
        EditOutcomeProjection.encodedText(outcome)
    }

    // MARK: Execution

    /// Edits the file and answers the batch status with its envelope, or
    /// the correction that says why nothing was resolved.
    ///
    /// Rejects a read-only session, then validates the path via the
    /// context's ``PathGuard`` for an edit (the file must exist and must
    /// not be read-only), reads and decodes the on-disk bytes (rejecting a
    /// binary file), records the detected line ending, normalizes the
    /// arguments through ``EditEngine/normalize(_:)``, and resolves the
    /// whole batch in memory through ``EditEngine/apply(_:to:)``. A fully
    /// resolved batch is committed atomically with the detected encoding;
    /// an unresolved batch answers a structured outcome and leaves the
    /// file byte-identical. Each recoverable failure comes back as the
    /// `correction` field of the result; nothing here throws for a bad
    /// payload, path, file, or commit.
    ///
    /// - Parameter arguments: What to edit and the find/replace batch.
    /// - Returns: The batch status with its envelope, or the correction.
    func call(arguments: EditArguments) async throws -> EditResult {
        if context.readOnly { return Self.corrective(Self.readOnlySessionMessage) }

        return await context.pathGuard.validate(arguments.path, for: .edit)
            .resolveAsync(corrective: Self.corrective) { url in
                await PathCorrective.readData(at: url, path: arguments.path)
                    .resolveAsync(corrective: Self.corrective) { data in
                        guard let decoded = AtomicWriter.decode(data) else {
                            return Self.corrective(
                                PathCorrective.pathErrorMessage(
                                    description: Self.binaryDescription, path: arguments.path))
                        }
                        let lineEnding = AtomicWriter.detectLineEnding(in: decoded.text)

                        let pairs: [EditEngine.Pair]
                        switch EditEngine.normalize(Self.engineArguments(for: arguments)) {
                        case .pairs(let shaped):
                            pairs = shaped
                        case .corrective(let message):
                            return Self.corrective(message)
                        }

                        switch EditEngine.apply(pairs, to: decoded.text) {
                        case .applied(let content, let edits):
                            return await Self.commit(
                                content: content, edits: edits, to: url, decoded: decoded,
                                lineEnding: lineEnding, path: arguments.path, context: context)
                        case .failed(_, let pair, let resolution):
                            return Self.unresolvedResult(path: url.path, pair: pair, resolution: resolution)
                        }
                    }
            }
    }

    /// Builds the ``EditEngine/EditArguments`` for the verb's parameters.
    ///
    /// An absent array is treated as empty and an absent `replacesAll` as
    /// the default, thus ``EditEngine/normalize(_:)`` sees one canonical
    /// shape. The engine's `edits` object-array form is not a model-facing
    /// parameter of this verb, the same as in the ported sibling, thus it
    /// stays empty.
    ///
    /// - Parameter arguments: the verb's arguments.
    /// - Returns: the engine's normalized argument value.
    private static func engineArguments(for arguments: EditArguments) -> EditEngine.EditArguments {
        EditEngine.EditArguments(
            finds: arguments.find ?? [],
            replaces: arguments.replace ?? [],
            replaceAll: arguments.replacesAll ?? defaultReplacesAll,
            occurrence: arguments.occurrence
        )
    }

    // MARK: Commit

    /// Commits a fully resolved batch in a single atomic write, or answers
    /// a correction on failure.
    ///
    /// Re-encodes the committed content with the file's detected encoding
    /// (``AtomicWriter/encode(_:as:)``, the inverse of the decode that
    /// read it) and writes it through ``AtomicWriter/write(_:to:)``, which
    /// preserves the existing permission bits and removes its temporary
    /// file on any failure. A landed commit is recorded on the context's
    /// ``FileContext/changes`` journal as a ``FileChangeKind/modify``
    /// carrying the text on both sides — only here, after the write, thus
    /// an unresolved batch (which commits nothing) records nothing. The
    /// journal itself drops the record when the session is not recording.
    ///
    /// - Parameters:
    ///   - content: the fully rewritten content to commit.
    ///   - edits: the per-pair applied-edit records.
    ///   - url: the resolved target URL.
    ///   - decoded: the decoded original, supplying the encoding to re-apply.
    ///   - lineEnding: the detected line-ending convention to report, or `nil`.
    ///   - path: the requested path, for a corrective message.
    ///   - context: the session context whose journal records the change.
    /// - Returns: the applied ``EditResult``, or the corrective one when
    ///   the atomic write fails.
    private static func commit(
        content: String,
        edits: [EditEngine.AppliedEdit],
        to url: URL,
        decoded: AtomicWriter.DecodedText,
        lineEnding: AtomicWriter.LineEnding?,
        path: String,
        context: FileContext
    ) async -> EditResult {
        let data = AtomicWriter.encode(content, as: decoded.encoding)
        do {
            try AtomicWriter.write(data, to: url)
        } catch {
            return corrective(
                PathCorrective.pathErrorMessage(description: commitFailureDescription, path: path))
        }
        await context.changes.record(
            FileChange(kind: .modify, path: url.path, oldContent: decoded.text, newContent: content)
        )
        return EditResult(
            path: url.path,
            status: EditOutcomeProjection.appliedStatus,
            applied: edits.count,
            outcomes: edits.map {
                encodedOutcome(EditOutcomeProjection.outcome(for: $0.resolution, find: $0.pair.find))
            },
            bytesWritten: data.count,
            encoding: decoded.encoding.rawValue,
            lineEndings: lineEnding?.rawValue,
            hash: Hashline.wholeFileHash(bytes: data),
            taggedContent: Hashline.taggedLines(of: content),
            correction: nil
        )
    }

    /// Builds the byte-identical (uncommitted) result for a batch that
    /// short-circuited on an unresolved pair.
    ///
    /// The commit-only fields (`bytesWritten`, `encoding`, `lineEndings`,
    /// `hash`, `taggedContent`) are all `nil`: nothing was written and the
    /// file is byte-identical.
    ///
    /// - Parameters:
    ///   - path: the resolved absolute path.
    ///   - pair: the pair that failed to resolve.
    ///   - resolution: the non-definite resolution that short-circuited the batch.
    /// - Returns: the structured, retryable ``EditResult``.
    private static func unresolvedResult(
        path: String,
        pair: EditEngine.Pair,
        resolution: EditEngine.Resolution
    ) -> EditResult {
        EditResult(
            path: path,
            status: EditOutcomeProjection.statusName(for: resolution),
            applied: 0,
            outcomes: [encodedOutcome(EditOutcomeProjection.outcome(for: resolution, find: pair.find))],
            bytesWritten: nil,
            encoding: nil,
            lineEndings: nil,
            hash: nil,
            taggedContent: nil,
            correction: nil
        )
    }
}

/// Edits a file's contents by a batch of find/replace pairs, committed
/// atomically with encoding and line-ending preservation.
///
/// ```swift
/// // In a snippet the model writes:
/// //   const edited = await tools.files.edit({ path: "notes/draft.md", find: ["old"], replace: ["new"] });
/// ```
///
/// The contract: each `find` resolves through the shape-inferred
/// ``EditEngine`` cascade — a hashline anchor from a prior read or write,
/// then a literal substring, then the recovery ladder — and the whole
/// batch resolves in memory before anything touches the disk. Only a fully
/// resolved batch is committed, in a single atomic write through
/// ``AtomicWriter`` that preserves the file's detected encoding, its line
/// endings, and its permission bits; the result's `hash` and
/// `taggedContent` are exactly what a subsequent read computes, thus a
/// chained edit resolves anchors without an intervening read. An
/// unresolved pair short-circuits before any mutation: the file stays
/// byte-identical and the `status` (`ambiguous`, `nearMiss`,
/// `alreadyApplied`, `consumedTarget`) with its JSON `outcomes` says how
/// to retry. The path is bounded through the session's ``PathGuard``, and
/// the session's ``FileChangeJournal`` records a landed commit when it is
/// recording. A payload that cannot normalize, a path outside the root, a
/// missing or binary file, a read-only target, a read-only session, and a
/// failed commit each come back as a `correction` rather than as an error.
///
/// The context it edits against is the context the files capability owns,
/// thus each verb of one capability answers for the same session.
struct Edit: Tool {

    /// The verb this tool renders as, which the files noun stands in front
    /// of: `tools.files.edit`.
    let name = "edit"

    /// The usage instructions, as the model reads them.
    let description = """
        edit rewrites a file by a batch of find/replace pairs, committed in one atomic write \
        that preserves the file's encoding, line endings, and permission bits. Each find is a \
        literal text or an N:HH|text hashline anchor from a prior read or write, thus a chained \
        edit needs no intervening read. replacesAll rewrites every occurrence and occurrence \
        selects one site among several matches. An unresolved find commits nothing: the status \
        (ambiguous, nearMiss, alreadyApplied, consumedTarget) and the JSON outcomes say how to \
        retry, and the file stays byte-identical. A payload that cannot resolve, a path outside \
        the session root, a missing or binary file, a read-only target, a read-only session, \
        and a failed commit each come back as a correction rather than as an error — read it, \
        correct the call, and ask again.
        """

    /// The session context this verb edits against, which the files capability owns.
    ///
    /// The compiler-synthesized memberwise initializer takes this one
    /// property, thus the capability makes the verb as `Edit(context:)`.
    let context: FileContext
}
