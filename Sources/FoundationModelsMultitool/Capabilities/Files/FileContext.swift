// `FileContext` — the shared per-session state of the file verbs.
//
// A behavioral port of `../FoundationModelsFileTool/Sources/FileTool/
// FileContext.swift`. The sibling also holds a diagnostics-bridge handle,
// an `eagerWarmup` flag, and a `stop()` teardown that forwards to the
// bridge. Decision 2026-08-11 in eventplan.md: this package does not get
// the diagnostics bridge or the diagnostics engine, and it does not add
// the code-context dependency. Thus the port drops the bridge, the flag,
// and `stop()` — the one remaining dependency,
// `FileChangeJournal`, is an actor with plain state and needs no teardown,
// and the sibling's convenience/designated initializer split collapses into
// one initializer. The sibling declares the type `public`; this package
// keeps it internal, the same way `PathGuard` and `FileChangeSet` beside it
// do.
//
// eventplan.md § "We remove OperationTool": typed per-capability contexts
// (`ShellContext`, `FileContext`) stay as usual constructor dependencies.

import Foundation

/// The shared per-session state the file verbs dispatch against.
///
/// A `FileContext` bundles everything one agent session's file tools need:
/// the session ``root`` directory, the ``pathGuard`` that validates every
/// path against it, a ``readOnly`` flag, and the ``changes`` journal. It is
/// a reference type, thus the verbs share one instance — one change journal
/// — for the life of the session.
///
/// The ``pathGuard`` enforces ``root`` as its workspace boundary, thus every
/// verb is confined to the session root by default.
///
/// - Note: Every stored property is immutable and `Sendable` (``root``,
///   ``pathGuard``, ``readOnly``, and the ``changes`` journal — whose own
///   mutable state is isolated to that actor), thus the type is a checked
///   `Sendable`.
final class FileContext: Sendable {
    /// The session working directory: the boundary and relative-path base.
    let root: URL

    /// The validator every path passes through before a verb runs.
    ///
    /// Built from ``root`` as both the relative-path base and the workspace
    /// boundary, thus verbs are confined to the session root.
    let pathGuard: PathGuard

    /// Whether the session forbids the mutating verbs (`write` / `edit`).
    ///
    /// The verbs consult this to reject mutations up front; path validation
    /// itself is unaffected.
    let readOnly: Bool

    /// The session's change journal: what the mutating verbs changed, for a host to drain.
    ///
    /// Disabled unless the session asked for recording, thus a session that
    /// never consumes a ``FileChangeSet`` pays neither the capture work nor
    /// the retained content.
    let changes: FileChangeJournal

    /// Creates a session context rooted at a working directory.
    ///
    /// - Parameters:
    ///   - root: the session working directory; also the ``pathGuard``
    ///     workspace boundary and relative-path base.
    ///   - additionalRoots: extra workspace boundaries the ``pathGuard``
    ///     also confines paths to, alongside ``root``; defaults to empty. A
    ///     path is valid if it resolves within `root` or within any of
    ///     these. Relative paths still resolve against `root` alone (see
    ///     ``PathGuard``).
    ///   - readOnly: whether to forbid the mutating verbs; defaults to `false`.
    ///   - allowSymlinks: whether the guard resolves symlinks rather than
    ///     rejecting them; defaults to `false` (the secure default).
    ///   - recordsChanges: whether the mutating verbs record what they
    ///     changed into ``changes``; defaults to `false`.
    init(
        root: URL,
        additionalRoots: Set<URL> = [],
        readOnly: Bool = false,
        allowSymlinks: Bool = false,
        recordsChanges: Bool = false
    ) {
        self.root = root
        self.readOnly = readOnly
        self.pathGuard = PathGuard(
            root: root, workspaceRoot: root, additionalWorkspaceRoots: additionalRoots, allowSymlinks: allowSymlinks
        )
        self.changes = FileChangeJournal(root: root, mode: recordsChanges ? .recording : .disabled)
    }
}
