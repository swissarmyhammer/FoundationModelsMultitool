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
// **The same envelope also rides `ToolContext.attach(_:)`, and that is the
// LIVE half.** A Router session keeps a `.progress` event off its live surface:
// the event is the model-facing preamble and the durable recording, so a host
// that must show a diff DURING the answer cannot wait for it. A record attached
// to a call makes ONE tool call report (`ToolCallReport`, FoundationModelsExtras)
// when that call closes, under the run's own correlation. The host gets that
// report live. It is the carrier that was built for exactly this
// (UPSTREAM_ASKS.md, ask 4). The record's `schemaName` is
// `FileChangeSet.operationEventDetailKey`, so a host matches it against the
// same public name it already reads a `detail` by.
//
// **Why each verb delivers its own changes, and no drain at the end of a
// `runCode` call does.** `FilesCapability.init` makes ONE `FileContext`, thus
// ONE journal, for the whole registry, and several `runCode` calls can run at
// once over that registry (no number limits them). A drain at the end of call A would take the changes call B
// recorded and post them under A's correlation. So each verb posts through
// the `ToolContext` the engine bound around its own inner call, and
// `ToolContext.post(_:)` re-stamps the event with the outer `runCode` run's
// `tool`, `op` and `completionToken` (see `RunBinding.invoke`).
//
// **The display diff.** The `fileChanges` envelope goes only to a recording
// session. A client must also show the diff of each change when the session
// does not record. Thus, under an ambient context, `commit` also posts one
// `ToolDisplayEvent` for each changed file: a `.contentChunk` that holds a
// `ToolDisplayContent.diff(path:oldText:newText:)`. It does this also when the
// journal does not record. The display event never goes into the model input,
// and the journal never keeps it.

import Foundation
import FoundationModelsExtras

/// The session-scoped record of what the mutating verbs changed: delivered to
/// the session as a `.progress` event and an attached record, or kept for a
/// host to drain.
///
/// The verbs report their results to the *model* as encoded JSON, which is
/// all a host driving them ever sees. A host that must also tell its
/// *client* what changed — an Agent Client Protocol agent rendering a
/// reviewable diff — needs the change set as values, not as prose to
/// re-parse. The journal is that side channel. Each mutating verb commits
/// the ``FileChange`` values of one call through ``commit(_:through:)``:
///
/// - Under a session, the changes leave at once as ONE `fileChanges` envelope
///   (``FileChangeSet/encodedOperationEventDetail()``), carried two ways
///   through the ambient `ToolContext` of the call: as the `detail` of a
///   `.progress` `OperationEvent`, which the session records, and as a
///   `ToolCallAttachment`, which reaches a host live in the tool call report
///   (`ToolCallReport`) of the call. A host reads the set back from either with
///   ``FileChangeSet/init(operationEventDetail:)``. One verb call makes one
///   event and one record, whatever the number of files it touched.
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

    /// Whether a verb must capture the text of its change before it writes.
    ///
    /// The capture is necessary when the journal records, and also when the
    /// call has an ambient context, because ``commit(_:through:)`` then posts
    /// the display diff of each change. `nonisolated`, thus a verb can
    /// consult it before the write, with no wait.
    ///
    /// - Parameter context: the ambient `ToolContext` the verb read at the
    ///   start of its call, or `nil` on a bare session.
    /// - Returns: `true` when the verb must capture the text of its change.
    nonisolated func capturesChanges(through context: ToolContext?) -> Bool {
        isRecording || context != nil
    }

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
    /// Returns at once when `changes` is empty. When `context` is not `nil`,
    /// posts one display diff for each change first (see
    /// ``displayDiff(of:)``), also when the journal is disabled. Then returns
    /// when the journal is disabled.
    /// When `context` is not `nil`, delivers the changes both ways and keeps
    /// nothing: ONE `.progress` event whose `detail` is the `fileChanges`
    /// envelope of a ``FileChangeSet`` rooted at ``root``, and ONE
    /// `ToolCallAttachment` carrying that same envelope. When `context` is
    /// `nil`, keeps the changes for ``drain()``. A change is delivered or kept,
    /// never both.
    ///
    /// The two deliveries carry the same text and reach different readers, so
    /// neither replaces the other. The order they are made in decides nothing:
    /// the host posts a run's report after that run's close record, whatever
    /// order the tool wrote the two calls in.
    ///
    /// - Parameters:
    ///   - changes: the committed changes of one verb call.
    ///   - context: the ambient `ToolContext` the verb read at the start of
    ///     its call, or `nil` on a bare session.
    func commit(_ changes: [FileChange], through context: ToolContext?) async {
        guard !changes.isEmpty else { return }
        if let context {
            for diff in changes.compactMap(Self.displayDiff(of:)) {
                await context.emit(chunk: diff)
            }
        }
        guard isRecording else { return }
        guard let context else {
            for change in changes { record(change) }
            return
        }
        // Encoded one time and read two ways. The envelope renders the whole
        // git patch of the set, so a second encoding would render it again.
        let envelope = FileChangeSet(root: root, changes: changes).encodedOperationEventDetail()
        await context.post(
            OperationEvent(
                tool: context.tool,
                op: context.op,
                correlationID: context.completionToken,
                kind: .progress,
                detail: envelope
            )
        )
        context.attach(
            ToolCallAttachment(
                schemaName: FileChangeSet.operationEventDetailKey, contentJSON: envelope))
    }

    // MARK: Display diff

    /// The display diff of one change, for the client of the host.
    ///
    /// - An add or a copy gives the destination path, no old text, and the
    ///   new text.
    /// - A modify gives the path, the old text and the new text.
    /// - A move gives the destination path, the old text of the source and
    ///   the new text.
    /// - A delete gives the path, the old text and an empty new text.
    ///
    /// A change gives no diff when a side that exists has no text: the file
    /// is binary, or the verb could not read it. A diff with a `nil` old text
    /// tells the client that the file is new, thus a missing old text of a
    /// file that existed must not become a diff.
    ///
    /// - Parameter change: the committed change.
    /// - Returns: the diff content, or `nil` when the change has no text diff.
    static func displayDiff(of change: FileChange) -> ToolDisplayContent? {
        switch change.kind {
        case .add, .copy:
            guard let newText = change.newContent else { return nil }
            return .diff(path: change.destinationPath ?? change.path, oldText: nil, newText: newText)
        case .modify:
            guard let oldText = change.oldContent, let newText = change.newContent else { return nil }
            return .diff(path: change.path, oldText: oldText, newText: newText)
        case .move:
            guard let oldText = change.oldContent, let newText = change.newContent else { return nil }
            return .diff(path: change.destinationPath ?? change.path, oldText: oldText, newText: newText)
        case .delete:
            guard let oldText = change.oldContent else { return nil }
            return .diff(path: change.path, oldText: oldText, newText: "")
        }
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
