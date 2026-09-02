// `Patch` — the `tools.files.patch` verb.
//
// A behavioral port of `../FoundationModelsFileTool/Sources/FileTool/
// Operations/PatchFiles.swift`. The sibling is an `@Operation` that takes a
// `FileContext` through its `execute(in:)`; this package has no operation
// machinery, thus the verb is a plain `FoundationModels.Tool` that holds
// the context it applies against, in the pattern of `Capabilities/Files/
// Edit.swift`. The sibling's `@OperationParam` alias (`input`) does not
// port: the plain `@Generable` arguments keep only the canonical `patch`
// name. The sibling's `PatchOutput` enum does not port either: the flat
// result carries a `correction` field in its place, and the per-file
// results ride as JSON text encoded from the `PatchFileResult` wire type,
// the same treatment `Edit` gives its per-pair outcomes.
//
// eventplan.md § "Registration of capabilities: noun/verb": the capability
// supplies the noun, thus this verb's `name` is the bare `patch` and the
// surface path renders as `tools.files.patch`.
//
// A patch the verb cannot apply stays IN BAND, as a `correction` beside
// empty envelope fields. It is never thrown: an envelope that cannot parse
// (surfaced with the offending line number), a path outside the root, an
// add onto an existing file, a delete of a missing file, a binary update
// target, a cross-file conflict, a read-only session, and a failed
// stage/commit/unlink are each a mistake the model corrects inside the
// turn, and a thrown error would end the turn instead. The structured
// retryable outcomes (`ambiguous`, `nearMiss`, `alreadyApplied`,
// `consumedTarget`) are not corrections: they ride in the result's
// `status` and `outcome`, and they leave every file byte-identical.

import Foundation
import FoundationModels
import FoundationModelsRouter

/// The arguments of `tools.files.patch`: the whole patch envelope.
@Generable
struct PatchArguments {

    /// The complete patch envelope: `*** Begin Patch` … `*** End Patch`
    /// with Add/Update/Delete/Move sections.
    @Guide(
        description:
            "The whole patch envelope, from *** Begin Patch to *** End Patch, holding one or "
            + "more Add/Update/Delete/Move file sections with absolute paths.")
    var patch: String
}

/// The result of `tools.files.patch`: the whole-patch status with its
/// per-file results, the unresolved fields of a retryable outcome, or the
/// correction that says why nothing was applied.
///
/// `correction` and the patch fields are exclusive. An applied patch
/// carries no correction, one `files` entry per touched file, and no
/// unresolved field. A structured retryable outcome (`ambiguous`,
/// `nearMiss`, `alreadyApplied`, `consumedTarget`) carries empty `files`
/// and the unresolved fields (`path`, `outcome`); it commits nothing and
/// leaves every file byte-identical. A correction carries an empty
/// `status`, empty `files`, and no unresolved field.
@Generable(
    description:
        "the patch's status with its per-file results, the unresolved fields of a retryable outcome, or the correction that says why nothing was applied."
)
struct PatchResult {

    /// The whole-patch status: `applied`, `ambiguous`, `nearMiss`,
    /// `alreadyApplied`, or `consumedTarget`. Empty on a correction.
    var status: String

    /// The per-file results as JSON text with sorted keys, one entry per
    /// touched file for an `applied` patch: each carries `path`, `action`,
    /// and `applied`, plus `movedTo` for a moved file and `bytesWritten` /
    /// `hash` for a committed one. Empty for an unresolved outcome and on a
    /// correction.
    var files: [String]

    /// The failing file's absolute path for an unresolved outcome; `nil`
    /// when applied and on a correction.
    var path: String?

    /// The single failing pair's outcome as JSON text with sorted keys for
    /// an unresolved outcome — the same `matchedBy` / `candidates` /
    /// `nearMisses` shape the `edit` verb reports; `nil` when applied and
    /// on a correction.
    var outcome: String?

    /// Why nothing was applied, or `nil` when the patch fields stand.
    var correction: String?
}

/// The per-file wire result of a committed patch: what happened to one touched file.
///
/// The `Encodable` value one entry of ``PatchResult/files`` encodes. The
/// commit-only fields (``bytesWritten``, ``hash``) are `nil` — and omitted
/// from the JSON — for a `deleted` file, which commits no bytes;
/// ``movedTo`` is the absolute destination path for a `moved` file and
/// `nil` otherwise. There is deliberately no `taggedContent` here (unlike
/// ``EditResult`` / ``WriteResult``): echoing every touched file's
/// hashline-tagged content back into a small on-device context is too
/// expensive for a multi-file patch, so a chained edit re-anchors with the
/// `read` verb instead.
struct PatchFileResult: Encodable, Sendable {
    /// The absolute path acted on (the source path for a move).
    let path: String

    /// The action the file underwent: `added`, `modified`, `deleted`, or `moved`.
    let action: String

    /// The absolute destination path for a `moved` file; `nil` otherwise.
    let movedTo: String?

    /// The number of find/replace pairs applied (`0` for an Add, Delete, or pure rename).
    let applied: Int

    /// The number of bytes committed, or `nil` for a `deleted` file.
    let bytesWritten: Int?

    /// The whole-file freshness token over the committed bytes, or `nil` for a `deleted` file.
    let hash: String?
}

extension Patch {

    // MARK: Corrective messages

    /// The corrective message for a patch on a read-only session.
    private static let readOnlySessionMessage =
        "The session is read-only, so the `patch` verb cannot change files."

    /// A result carrying only a correction: empty status, no files, no
    /// unresolved field.
    ///
    /// - Parameter message: the correction the model reads and acts on.
    /// - Returns: the corrective ``PatchResult``.
    private static func corrective(_ message: String) -> PatchResult {
        PatchResult(status: "", files: [], path: nil, outcome: nil, correction: message)
    }

    // MARK: Execution

    /// Applies the patch envelope and answers the whole-patch status with
    /// its per-file results, a structured retryable outcome, or the
    /// correction that says why nothing was applied.
    ///
    /// Rejects a read-only session, then parses the `patch` scalar via
    /// ``PatchParser`` (a parse failure becomes a correction naming the
    /// offending line) and applies the parsed hunks via
    /// ``PatchEngine/apply(_:using:capturingContent:)`` against the
    /// context's ``PathGuard``. A fully resolved patch commits every hunk
    /// atomically and reports one per-file result per touched file; an
    /// unresolved Update pair answers a structured, byte-identical outcome;
    /// every recoverable failure comes back as the `correction` field of
    /// the result. Nothing here throws for a bad envelope, path, file, or
    /// commit.
    ///
    /// Content capture is asked for only when the session records changes,
    /// so a non-recording patch does exactly the IO it always did. A
    /// failure commits too: a patch that fails after some of its writes
    /// have committed carries those files on
    /// ``PatchEngine/Failure/committedOutcomes``, and they are committed
    /// before the correction is returned, so the change set never
    /// under-reports a mutation that landed. Every change of every outcome
    /// goes in ONE commit, thus a patch that touches four files delivers one
    /// event with four changes.
    ///
    /// **The ambient context is read one time, at the start.** eventplan.md
    /// § "The ambient context" makes that rule mandatory: work that inherits
    /// no task local sees none, so a second read of the ambient context
    /// after an `await` would find `nil`. The value captured here is what
    /// the commit posts through.
    ///
    /// - Parameter arguments: The patch envelope to apply.
    /// - Returns: The patch status with its per-file results, or the correction.
    func call(arguments: PatchArguments) async throws -> PatchResult {
        let toolContext = ToolContext.current
        if context.readOnly { return Self.corrective(Self.readOnlySessionMessage) }

        return await PatchParser.parse(arguments.patch)
            .resolveAsync(corrective: Self.corrective) { hunks in
                let capturingContent = context.changes.isRecording
                switch PatchEngine.apply(hunks, using: context.pathGuard, capturingContent: capturingContent) {
                case .success(let outcomes):
                    await Self.commit(outcomes, in: context, through: toolContext)
                    return Self.appliedResult(from: outcomes)
                case .failure(let failure):
                    await Self.commit(failure.committedOutcomes, in: context, through: toolContext)
                    return Self.result(for: failure)
                }
            }
    }

    // MARK: Change recording

    /// The data-driven engine-action-to-change-kind correspondence.
    ///
    /// The one mapping from the engine's ``PatchEngine/Action`` vocabulary
    /// (`added` / `modified` / `deleted` / `moved`, the names the
    /// model-facing ``PatchFileResult/action`` carries) to the change-set
    /// vocabulary a host projects into. The two are deliberately separate
    /// spellings — the change-set names are the Agent Client Protocol's —
    /// so the routing between them lives here as a table rather than as
    /// parallel switch arms a human must keep in lockstep, covering all
    /// four fixed ``PatchEngine/Action`` cases. An action absent from the
    /// table (which the fixed engine enum cannot produce) falls back to
    /// ``FileChangeKind/modify`` in ``changeKind(for:)``.
    ///
    /// Internal rather than private so a test can assert the table is total
    /// over ``PatchEngine/Action/allCases`` — the `FileChangeSet` suite
    /// port (card ^7r99xf5) reads it — standing in for the exhaustiveness
    /// the compiler checked when this was a `switch`.
    static let changeKinds: [PatchEngine.Action: FileChangeKind] = [
        .added: .add,
        .modified: .modify,
        .deleted: .delete,
        .moved: .move,
    ]

    /// The ``FileChangeKind`` of an engine action.
    ///
    /// - Parameter action: the engine action to name.
    /// - Returns: the corresponding change kind, defaulting to
    ///   ``FileChangeKind/modify`` — the reading that claims neither a
    ///   creation, a removal, nor a rename, only that the file changed.
    private static func changeKind(for action: PatchEngine.Action) -> FileChangeKind {
        changeKinds[action] ?? .modify
    }

    /// Project one committed ``PatchEngine/FileOutcome`` into the ``FileChange``(s) to record for it.
    ///
    /// When capture was asked for, the engine carries the text on both
    /// sides of every touched file, so the change set is a pure projection
    /// here — no file the patch has already rewritten is read again.
    ///
    /// A completed move whose destination overwrote an existing file
    /// (``PatchEngine/FileOutcome/overwrittenDestination``) fans out to two
    /// entries rather than one: the rename itself, carrying the source's
    /// own before/after text, plus a ``FileChangeKind/delete`` of the
    /// destination path carrying its prior text — the file the move
    /// silently destroyed. Reporting that as a delete keeps the rename's
    /// hunk legible (a diff of the source's edit, not of two unrelated
    /// files) while still surfacing the destruction a host would otherwise
    /// never see. Every other outcome — a move onto a new destination
    /// included, and a swap or rotation whose pre-existing destination the
    /// engine already recognized as another hunk's own source (so
    /// ``PatchEngine/FileOutcome/overwrittenDestination`` reads `nil`
    /// there, suppressed by ``PatchEngine`` itself) — projects to exactly
    /// one entry.
    ///
    /// - Parameter outcome: the committed per-file outcome.
    /// - Returns: the change(s) to record, in the order a host should apply them.
    private static func changes(for outcome: PatchEngine.FileOutcome) -> [FileChange] {
        let rename = FileChange(
            kind: changeKind(for: outcome.action),
            path: outcome.path,
            destinationPath: outcome.movedTo,
            oldContent: outcome.oldContent,
            newContent: outcome.newContent
        )
        guard let destination = outcome.movedTo, let overwritten = outcome.overwrittenDestination else {
            return [rename]
        }
        let destroyed = FileChange(
            kind: .delete,
            path: destination,
            oldContent: overwritten.content
        )
        return [rename, destroyed]
    }

    /// Commit every per-file outcome that landed on disk to the session's journal, in one call.
    ///
    /// Shared by the applied path and the partially-applied one, so a file
    /// the patch rewrote is reported the same way whether or not the patch
    /// as a whole succeeded. The changes of every outcome are collected into
    /// one array and committed one time, thus the session receives ONE
    /// `fileChanges` event for the whole patch. A non-recording session
    /// drops them.
    ///
    /// - Parameters:
    ///   - outcomes: the per-file outcomes whose mutations committed.
    ///   - context: the session context whose journal to commit to.
    ///   - toolContext: the ambient context the verb read at the start of
    ///     its call, or `nil` on a bare session.
    private static func commit(
        _ outcomes: [PatchEngine.FileOutcome],
        in context: FileContext,
        through toolContext: ToolContext?
    ) async {
        await context.changes.commit(outcomes.flatMap(changes(for:)), through: toolContext)
    }

    // MARK: Result projection

    /// Build the applied ``PatchResult`` projecting every committed file outcome.
    ///
    /// - Parameter outcomes: the engine's per-file outcomes for the committed patch.
    /// - Returns: the applied result, with the unresolved fields left `nil`.
    private static func appliedResult(from outcomes: [PatchEngine.FileOutcome]) -> PatchResult {
        PatchResult(
            status: EditOutcomeProjection.appliedStatus,
            files: outcomes.map { EditOutcomeProjection.encodedText(fileResult($0)) },
            path: nil,
            outcome: nil,
            correction: nil
        )
    }

    /// Project one ``PatchEngine/FileOutcome`` to its `Encodable` ``PatchFileResult``.
    ///
    /// The ``PatchEngine/Action`` wire name is read straight from the
    /// engine enum's ``PatchEngine/Action`` raw value, so the action
    /// vocabulary (`added` / `modified` / `deleted` / `moved`) is
    /// single-sourced there rather than restated as a mapping table here.
    ///
    /// - Parameter outcome: the engine file outcome to project.
    /// - Returns: the `Encodable` per-file result.
    private static func fileResult(_ outcome: PatchEngine.FileOutcome) -> PatchFileResult {
        PatchFileResult(
            path: outcome.path,
            action: outcome.action.rawValue,
            movedTo: outcome.movedTo,
            applied: outcome.appliedPairs,
            bytesWritten: outcome.bytesWritten,
            hash: outcome.hash
        )
    }

    /// Map an engine ``PatchEngine/Failure`` to its ``PatchResult``.
    ///
    /// A ``PatchEngine/Failure/corrective(_:committed:)`` rides straight
    /// through as a correction — its committed outcomes are committed by
    /// ``call(arguments:)`` and deliberately absent from the model-facing
    /// result, which reports a rejected patch as a message and nothing
    /// else; a ``PatchEngine/Failure/unresolved(path:pair:resolution:)``
    /// becomes a structured, byte-identical result carrying the failing
    /// file's path and the same ``EditOutcome`` the `edit` verb produces.
    ///
    /// - Parameter failure: the engine failure to project.
    /// - Returns: the corresponding result.
    private static func result(for failure: PatchEngine.Failure) -> PatchResult {
        switch failure {
        case .corrective(let message, _):
            return corrective(message)
        case .unresolved(let path, let pair, let resolution):
            return unresolvedResult(path: path, pair: pair, resolution: resolution)
        }
    }

    /// Build the byte-identical (uncommitted) result for a patch that
    /// short-circuited on an unresolved Update pair.
    ///
    /// The `status` and the JSON `outcome` come from
    /// ``EditOutcomeProjection`` — the same mapping the `edit` verb uses —
    /// so the wire status and candidates/near-misses are identical to a
    /// single-file edit's. `files` is empty: nothing was committed and
    /// every file is byte-identical (asserted by the engine).
    ///
    /// - Parameters:
    ///   - path: the failing file's absolute path.
    ///   - pair: the pair that failed to resolve.
    ///   - resolution: the non-definite resolution that short-circuited the patch.
    /// - Returns: the structured, retryable result.
    private static func unresolvedResult(
        path: String,
        pair: EditEngine.Pair,
        resolution: EditEngine.Resolution
    ) -> PatchResult {
        PatchResult(
            status: EditOutcomeProjection.statusName(for: resolution),
            files: [],
            path: path,
            outcome: EditOutcomeProjection.encodedText(
                EditOutcomeProjection.outcome(for: resolution, find: pair.find)),
            correction: nil
        )
    }
}

/// Applies a multi-file patch envelope — Add / Update / Delete / Move
/// sections with Find/Replace bodies — as one all-or-nothing mutation.
///
/// ```swift
/// // In a snippet the model writes:
/// //   const patched = await tools.files.patch({
/// //     patch: "*** Begin Patch\n*** Add File: /repo/notes.txt\n+first note\n*** End Patch\n"
/// //   });
/// ```
///
/// The contract: the whole envelope rides in the one `patch` scalar and
/// parses through ``PatchParser`` (a parse failure comes back as a
/// `correction` naming the offending line); the parsed hunks then run
/// through the two-phase ``PatchEngine`` against the session's
/// ``PathGuard``, thus every path is bounded to the session root. Every
/// hunk resolves in memory before anything touches the disk: only a fully
/// resolved patch is committed, each write atomic through ``AtomicWriter``
/// with encoding and permission preservation, and the result reports one
/// per-file JSON entry per touched file whose `hash` is exactly what a
/// subsequent read computes. An unresolved Update pair short-circuits
/// before any mutation: every file stays byte-identical and the `status`
/// (`ambiguous`, `nearMiss`, `alreadyApplied`, `consumedTarget`) with the
/// failing file's `path` and its JSON `outcome` — the same candidates and
/// near-miss diffs the `edit` verb reports — says how to retry. The
/// session's ``FileChangeJournal`` delivers every committed mutation to the
/// session as one event when it is recording, a partially-committed
/// failure's landed writes included. An envelope that cannot parse, a path outside the root, an
/// add onto an existing file, a delete of a missing file, a binary update
/// target, a cross-file conflict, a read-only session, and a failed
/// stage/commit/unlink each come back as a `correction` rather than as an
/// error.
///
/// The context it applies against is the context the files capability
/// owns, thus each verb of one capability answers for the same session.
struct Patch: Tool {

    /// The verb this tool renders as, which the files noun stands in front
    /// of: `tools.files.patch`.
    let name = "patch"

    /// The usage instructions, as the model reads them.
    ///
    /// This description carries the entire envelope syntax — the sibling
    /// operation's format teaching, kept whole — because FoundationModels
    /// have no `apply_patch` training exposure: the markers, the section
    /// forms, and one worked multi-file example are what let the model
    /// write a valid envelope at all.
    let description = """
        patch applies a multi-file patch in ONE call. The whole patch is a single text envelope \
        passed as `patch`.

        Envelope shape (every marker starts with `*** ` at the start of the line):

        *** Begin Patch
        <one or more file sections>
        *** End Patch

        File sections:

        1. Add a new file (fails if it already exists):
        *** Add File: /abs/path/new.txt
        +every content line is prefixed with a single `+`
        +the `+` is stripped and the joined lines become the file

        2. Update an existing file with one or more find/replace pairs:
        *** Update File: /abs/path/existing.txt
        *** Find:
        <the exact lines to locate — either verbatim text, or lines copied from a read WITH their N:HH| hashline tags left on>
        *** Replace:
        <the replacement lines (may be empty to delete the found lines)>
        You may repeat `*** Find:` / `*** Replace:` to send several edits for the same file.

        3. Delete a file:
        *** Delete File: /abs/path/gone.txt

        4. Rename (optionally while editing): put `*** Move to:` immediately after the Update header:
        *** Update File: /abs/path/old.txt
        *** Move to: /abs/path/new.txt
        *** Find:
        old text
        *** Replace:
        new text

        Worked example creating one file and editing another:

        *** Begin Patch
        *** Add File: /repo/notes.txt
        +first note
        +second note
        *** Update File: /repo/main.swift
        *** Find:
        let version = 1
        *** Replace:
        let version = 2
        *** End Patch

        Use absolute paths. All sections apply together atomically: if any section fails (bad \
        path, a Find that does not match, an Add onto an existing file), NOTHING is written and \
        a correction explains what to fix.
        """

    /// The session context this verb applies against, which the files capability owns.
    ///
    /// The compiler-synthesized memberwise initializer takes this one
    /// property, thus the capability makes the verb as `Patch(context:)`.
    let context: FileContext
}
