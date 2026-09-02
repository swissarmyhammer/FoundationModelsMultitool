// `FileChangeJournal` — the session-scoped record of what the mutating file
// verbs changed.
//
// A behavioral port of `../FoundationModelsFileTool/Sources/FileTool/
// FileChangeJournal.swift`, unchanged in behavior. The sibling declares the
// type `public`; this package keeps it internal, the same way `PathGuard`
// beside it is. The values it collects — `FileChange` and `FileChangeSet` —
// are public (UPSTREAM_ASKS.md, ask 4), because a host reads the change set
// off an `OperationEvent.detail`, never off the journal. The callers of
// `record` are the mutating verbs `Write`, `Edit` and `Patch`.
//
// eventplan.md § "Consolidation of the siblings": the journal collects one
// `FileChange` per mutating file verb into a `FileChangeSet`, and a host
// renders that set as a reviewable diff.

import Foundation

/// The session-scoped record of what the mutating verbs changed, for a host to drain.
///
/// The verbs report their results to the *model* as encoded JSON, which is
/// all a host driving them ever sees. A host that must also tell its
/// *client* what changed — an Agent Client Protocol agent rendering a
/// reviewable diff — needs the change set as values, not as prose to
/// re-parse. The journal is that side channel: the mutating verbs record one
/// ``FileChange`` per affected file as they commit, and the host drains
/// them.
///
/// Recording is **opt in** (``Mode/disabled`` by default, via
/// ``FileContext/init(root:additionalRoots:readOnly:allowSymlinks:recordsChanges:)``).
/// A change carries the whole-file text on both sides, thus the patch can be
/// rendered, which costs memory until it is drained, and capturing the
/// *old* text costs a write verb a read it would not otherwise make; a
/// session that does not consume change sets pays neither.
///
/// The natural drain point is the end of a tool call: what one call changed
/// is exactly what has accumulated since the last drain.
actor FileChangeJournal {
    // MARK: Mode

    /// Whether the journal records anything.
    enum Mode: Sendable, Equatable {
        /// The journal records every change until it is drained.
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

    /// The session root the drained ``FileChangeSet`` carries, canonicalized.
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

    /// The changes recorded since the last drain, in the order they were made.
    private var recorded: [FileChange] = []

    // MARK: Recording

    /// Records one file's change, or drops it when the journal is disabled.
    ///
    /// Called by a mutating verb once its mutation has committed, thus the
    /// journal never reports a change that did not land: an unresolved edit
    /// or patch (which leaves every file byte-identical) records nothing.
    ///
    /// The converse holds too. A patch envelope that fails *after* some of
    /// its staged writes have already been committed still records those
    /// files before returning its corrective, thus a partially applied patch
    /// is reported as what it changed rather than as nothing at all.
    ///
    /// - Parameter change: the committed change to record.
    func record(_ change: FileChange) {
        guard isRecording else { return }
        recorded.append(change)
    }

    // MARK: Draining

    /// Takes every change recorded since the last drain, clearing the journal.
    ///
    /// - Returns: the accumulated change set, rooted at ``root``; empty when
    ///   nothing was recorded or the journal is disabled.
    func drain() -> FileChangeSet {
        defer { recorded.removeAll() }
        return FileChangeSet(root: root, changes: recorded)
    }
}
