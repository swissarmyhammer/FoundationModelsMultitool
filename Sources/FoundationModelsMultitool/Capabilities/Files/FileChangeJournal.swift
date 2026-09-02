// `FileChangeJournal` — the session-scoped record of what the mutating file
// verbs changed, and the seam that delivers it to the session.
//
// A behavioral port of `../FoundationModelsFileTool/Sources/FileTool/
// FileChangeJournal.swift`, extended for UPSTREAM_ASKS.md, ask 4. The
// sibling declares the type `public`; this package keeps it internal, the
// same way `PathGuard` beside it is. The values it collects — `FileChange`
// and `FileChangeSet` — are public, because a host reads the change set off
// an `OperationEvent.detail`, never off the journal. The callers of `commit`
// are the mutating verbs `Write`, `Edit` and `Patch`.
//
// eventplan.md § "Consolidation of the siblings": the journal collects one
// `FileChange` per mutating file verb into a `FileChangeSet`, and a host
// renders that set as a reviewable diff. The set reaches the host as a
// `.progress` `OperationEvent` whose `detail` is the `fileChanges` envelope
// (`FileChangeSet.encodedOperationEventDetail()`), one event for each
// mutating verb call, and `FileChangeSet.init(operationEventDetail:)` is how
// the host reads it back.
//
// **Why each verb delivers its own changes, and no drain at the end of a
// `runCode` call does.** `FilesCapability.init` makes ONE `FileContext`, thus
// ONE journal, for the whole registry, and `MultiToolConfiguration.
// liveContextLimit` lets several `runCode` calls run at once over that
// registry. A drain at the end of call A would take the changes call B
// recorded and post them under A's correlation. So each verb posts through
// the `ToolContext` the engine bound around its own inner call, and
// `ToolContext.post(_:)` re-stamps the event with the outer `runCode` run's
// `tool`, `op` and `completionToken` (see `RunBinding.invoke`).

import Foundation
import FoundationModelsRouter

/// The session-scoped record of what the mutating verbs changed: delivered to
/// the session as a `.progress` event, or kept for a host to drain.
///
/// The verbs report their results to the *model* as encoded JSON, which is
/// all a host driving them ever sees. A host that must also tell its
/// *client* what changed — an Agent Client Protocol agent rendering a
/// reviewable diff — needs the change set as values, not as prose to
/// re-parse. The journal is that side channel. Each mutating verb commits
/// the ``FileChange`` values of one call through ``commit(_:through:)``:
///
/// - Under a session, the changes leave at once as ONE `.progress`
///   `OperationEvent` whose `detail` is the `fileChanges` envelope
///   (``FileChangeSet/encodedOperationEventDetail()``), posted through the
///   ambient `ToolContext` of the call. A host reads the set back with
///   ``FileChangeSet/init(operationEventDetail:)``. One verb call makes one
///   event, whatever the number of files it touched.
/// - With no ambient context (a verb on a bare `LanguageModelSession`, or a
///   direct call in a test), the changes are kept, and ``drain()`` takes them.
///
/// **A change is delivered or kept, never both.** A delivered change is not
/// retained, thus a long session does not grow the journal, and a drain
/// after a delivery is empty.
///
/// Recording is **opt in** (``Mode/disabled`` by default, via
/// ``FileContext/init(root:additionalRoots:readOnly:allowSymlinks:recordsChanges:)``).
/// A change carries the whole-file text on both sides, thus the patch can be
/// rendered, and capturing the *old* text costs a write verb a read it would
/// not otherwise make; a session that does not consume change sets pays
/// neither.
actor FileChangeJournal {
    // MARK: Mode

    /// Whether the journal records anything.
    enum Mode: Sendable, Equatable {
        /// The journal records every change: delivered to the session, or kept until drained.
        case recording

        /// The journal records nothing, and the verbs skip the capture work.
        case disabled
    }

    /// Whether this journal records changes.
    ///
    /// `nonisolated`, thus a verb can consult it synchronously, before doing
    /// the extra work — a pre-write read, a patch's content capture — that
    /// only a recording session needs.
    nonisolated var isRecording: Bool { mode == .recording }

    // MARK: State

    /// Whether the journal records changes.
    nonisolated let mode: Mode

    /// The session root every ``FileChangeSet`` this journal makes carries, canonicalized.
    ///
    /// Canonicalized with `realpath` at creation, the way ``PathGuard``
    /// canonicalizes every path it resolves. Both ends must agree: a session
    /// rooted at a symlinked path (a macOS temporary directory's `/var/…`,
    /// say) records changes at canonical `/private/var/…` paths, and a patch
    /// can only render those relative to the root if the root is canonical
    /// too.
    nonisolated let root: URL

    /// Creates a journal for a session root.
    ///
    /// - Parameters:
    ///   - root: the session root; canonicalized into ``root``.
    ///   - mode: whether the journal records changes.
    init(root: URL, mode: Mode) {
        self.root = FileWalker.canonicalDirectory(root)
        self.mode = mode
    }

    /// The changes kept since the last drain, in the order they were made.
    private var recorded: [FileChange] = []

    // MARK: Committing

    /// Delivers the changes of one verb call to the session, or keeps them for a drain.
    ///
    /// Called by a mutating verb once its mutation has committed, with every
    /// change that call made, thus the journal never reports a change that
    /// did not land: an unresolved edit or patch (which leaves every file
    /// byte-identical) commits nothing. A patch envelope that fails *after*
    /// some of its staged writes have committed still commits those files
    /// before the verb returns its correction, thus a partially applied
    /// patch is reported as what it changed rather than as nothing at all.
    ///
    /// Returns at once when the journal is disabled or `changes` is empty.
    /// When `context` is not `nil`, posts ONE `.progress` event whose
    /// `detail` is the `fileChanges` envelope of a ``FileChangeSet`` rooted
    /// at ``root``, and keeps nothing. When `context` is `nil`, keeps the
    /// changes for ``drain()``. A change is delivered or kept, never both.
    ///
    /// - Parameters:
    ///   - changes: the committed changes of one verb call.
    ///   - context: the ambient `ToolContext` the verb read at the start of
    ///     its call, or `nil` on a bare session.
    func commit(_ changes: [FileChange], through context: ToolContext?) async {
        guard isRecording, !changes.isEmpty else { return }
        guard let context else {
            for change in changes { record(change) }
            return
        }
        await context.post(
            OperationEvent(
                tool: context.tool,
                op: context.op,
                correlationID: context.completionToken,
                kind: .progress,
                detail: FileChangeSet(root: root, changes: changes).encodedOperationEventDetail()
            )
        )
    }

    // MARK: Recording

    /// Keeps one file's change for ``drain()``, or drops it when the journal is disabled.
    ///
    /// The retention path of ``commit(_:through:)``: a change committed with
    /// no ambient context lands here, one call for each change, in the order
    /// the verb made them.
    ///
    /// - Parameter change: the committed change to keep.
    func record(_ change: FileChange) {
        guard isRecording else { return }
        recorded.append(change)
    }

    // MARK: Draining

    /// Takes every change kept since the last drain, clearing the journal.
    ///
    /// A change delivered to the session is never here: only a change
    /// committed with no ambient context is kept.
    ///
    /// - Returns: the accumulated change set, rooted at ``root``; empty when
    ///   nothing was kept or the journal is disabled.
    func drain() -> FileChangeSet {
        defer { recorded.removeAll() }
        return FileChangeSet(root: root, changes: recorded)
    }
}
