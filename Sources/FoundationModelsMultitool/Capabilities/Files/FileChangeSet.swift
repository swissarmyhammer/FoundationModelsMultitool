// `FileChangeSet` — the change-record value layer of the files capability:
// what happened to each file, and the git-format patch of the whole run.
//
// A behavioral port of `../FoundationModelsFileTool/Sources/FileTool/
// FileChangeSet.swift`. The sibling declares the types `public` for its own
// module surface; this package keeps them internal, the same way `PathGuard`
// and `Hashline` beside them do.
//
// eventplan.md § "Consolidation of the siblings": the file-change journal
// (task ^zcr6qz8) collects one `FileChange` per mutating file verb into a
// `FileChangeSet`, and a host renders that set as a reviewable diff. Until
// the journal lands, `GitPatchTests` is the one caller; the ported
// change-set suite arrives on task ^7r99xf5.

import Foundation

/// What happened to one file in a change set: created, removed, rewritten, renamed, or duplicated.
///
/// The vocabulary a host projects a mutating operation into — the Agent
/// Client Protocol's diff-content `changes` vocabulary, whose entries name an
/// operation on an absolute path. A `String`-raw-valued enum, thus the names
/// live as data read via the non-optional `rawValue`.
///
/// ``move`` and ``copy`` are deliberately distinct from an ``add`` plus a
/// ``delete``: a rename carries both endpoints on one entry
/// (``FileChange/path`` and ``FileChange/destinationPath``), thus a client
/// renders it as a rename rather than as an unrelated creation and removal.
///
/// - Note: No file operation in this package produces ``copy`` today — the
///   patch dialect has no copy section and there is no `copy file` operation.
///   The case exists because the vocabulary a host projects into includes it,
///   thus a ``FileChange`` a host assembles for a copy it made by other means
///   (its own shell tool, say) has a name here rather than a false report as
///   an add.
enum FileChangeKind: String, Equatable, Sendable {
    /// A file that did not exist was created.
    case add

    /// An existing file was removed.
    case delete

    /// An existing file's contents were rewritten in place.
    case modify

    /// A file was renamed to ``FileChange/destinationPath``, optionally with an edit.
    case move

    /// A file was duplicated to ``FileChange/destinationPath``, and the source stays in place.
    case copy
}

/// One file's change: what happened to it, where it is, and the text on each side of the change.
///
/// The unit of the ACP change-set projection. ``path`` (and, for a rename or
/// a copy, ``destinationPath``) is always **absolute** — the operations take
/// paths relative to the session root, thus their resolution is the
/// projection's job, not the host's.
///
/// ``oldContent`` and ``newContent`` are the whole-file text on each side,
/// the material ``FileChangeSet/patch`` renders its hunks from. Each is `nil`
/// where the side does not exist (an ``FileChangeKind/add`` has no old
/// content, a ``FileChangeKind/delete`` no new content) and also where the
/// text could not be captured — an unreadable or binary (undecodable) file —
/// in which case the rendered patch reports the file as binary rather than
/// an invented diff.
struct FileChange: Equatable, Sendable {
    /// What happened to the file.
    let kind: FileChangeKind

    /// The absolute path acted on; the source path for a ``FileChangeKind/move`` or ``FileChangeKind/copy``.
    let path: String

    /// The absolute destination path of a ``FileChangeKind/move`` or ``FileChangeKind/copy``; `nil` otherwise.
    let destinationPath: String?

    /// The whole-file text before the change; `nil` for an add, or when the text could not be captured.
    let oldContent: String?

    /// The whole-file text after the change; `nil` for a delete, or when the text could not be captured.
    let newContent: String?

    /// Creates a file change.
    ///
    /// - Parameters:
    ///   - kind: what happened to the file.
    ///   - path: the absolute path acted on (the source path for a move or copy).
    ///   - destinationPath: the absolute destination path of a move or copy, or
    ///     `nil`; defaults to `nil`.
    ///   - oldContent: the whole-file text before the change, or `nil`;
    ///     defaults to `nil`.
    ///   - newContent: the whole-file text after the change, or `nil`;
    ///     defaults to `nil`.
    init(
        kind: FileChangeKind,
        path: String,
        destinationPath: String? = nil,
        oldContent: String? = nil,
        newContent: String? = nil
    ) {
        self.kind = kind
        self.path = path
        self.destinationPath = destinationPath
        self.oldContent = oldContent
        self.newContent = newContent
    }
}

/// Everything a run of mutating operations changed: one entry per affected file, plus its git-format patch.
///
/// The projection a host renders as a reviewable diff. A multi-file operation
/// — a patch envelope that touches four files, or a sequence of `edit file`
/// calls — projects one ``FileChange`` per affected file, in the order the
/// changes were made, never a single merged blob.
///
/// ``root`` is the session root the patch's paths are rendered relative to,
/// the way a git patch's paths are relative to the repository it applies in;
/// the ``FileChange/path`` values themselves stay absolute.
// The file-change journal (task ^zcr6qz8) is the production caller; until it
// lands, `GitPatchTests` and the ported change-set suite (task ^7r99xf5) are
// the callers.
// periphery:ignore
struct FileChangeSet: Equatable, Sendable {
    /// The session root the ``patch``'s paths are relative to.
    let root: URL

    /// The changes, one per affected file, in the order they were made.
    let changes: [FileChange]

    /// The change set as a patch in git's format, one section per change.
    ///
    /// The patch a host hands its client alongside the structured
    /// ``changes``. It is a real unified diff — `diff --git` headers, `@@`
    /// hunks with three lines of context, `/dev/null` for a creation or
    /// deletion, `rename from` / `rename to` for a move — with paths relative
    /// to ``root``, thus it applies with `git apply -p1` from there.
    ///
    /// A change with nothing to show renders nothing: a rewrite that produced
    /// identical text contributes no section, and an empty change set renders
    /// the empty string.
    ///
    /// - Important: A change whose text could not be captured (an unreadable
    ///   or binary file) renders git's `Binary files … differ` placeholder
    ///   instead of a diff, and such a patch cannot be applied at all: `git
    ///   apply` refuses the whole thing, every other section included. Check
    ///   for a change whose ``FileChange/oldContent`` or
    ///   ``FileChange/newContent`` is unexpectedly `nil` before you treat the
    ///   patch as appliable — the structured ``changes`` still describe every
    ///   affected file faithfully, thus nothing is lost when the diff renders
    ///   from those instead.
    var patch: String { GitPatch.render(changes, relativeTo: root) }
}
