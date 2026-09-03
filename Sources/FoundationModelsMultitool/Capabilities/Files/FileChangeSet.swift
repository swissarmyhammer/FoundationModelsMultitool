// `FileChangeSet` — the change-record value layer of the files capability:
// what happened to each file, and the git-format patch of the whole run.
//
// A behavioral port of `../FoundationModelsFileTool/Sources/FileTool/
// FileChangeSet.swift`. The sibling declares the types `public` for its own
// module surface, and this package does too (UPSTREAM_ASKS.md, ask 4): a host
// such as FoundationModelsACPAgent reads the change record as values, thus
// the three types here are the public, `Codable` half of that record. The
// journal that collects them (`FileChangeJournal`) stays internal, the same
// way `PathGuard` and `Hashline` beside it do.
//
// eventplan.md § "Consolidation of the siblings": the file-change journal
// collects one `FileChange` per mutating file verb into a `FileChangeSet`,
// and a host renders that set as a reviewable diff. The host reads the set
// off an `OperationEvent.detail` through the envelope at the end of this
// file, never off the journal.

import Foundation

/// What happened to one file in a change set: created, removed, rewritten, renamed, or duplicated.
///
/// The vocabulary a host projects a mutating operation into — the Agent
/// Client Protocol's diff-content `changes` vocabulary, whose entries name an
/// operation on an absolute path. A `String`-raw-valued enum, thus the names
/// live as data read via the non-optional `rawValue`, and the `Codable`
/// conformance is the synthesized one over that raw value.
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
public enum FileChangeKind: String, Equatable, Sendable, Codable {
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
///
/// The `Codable` conformance is the synthesized one: each stored property is
/// one key of the same name, and a `nil` side is omitted.
public struct FileChange: Equatable, Sendable, Codable {
    /// What happened to the file.
    public let kind: FileChangeKind

    /// The absolute path acted on; the source path for a ``FileChangeKind/move`` or ``FileChangeKind/copy``.
    public let path: String

    /// The absolute destination path of a ``FileChangeKind/move`` or ``FileChangeKind/copy``; `nil` otherwise.
    public let destinationPath: String?

    /// The whole-file text before the change; `nil` for an add, or when the text could not be captured.
    public let oldContent: String?

    /// The whole-file text after the change; `nil` for a delete, or when the text could not be captured.
    public let newContent: String?

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
    public init(
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
public struct FileChangeSet: Equatable, Sendable {
    /// The session root the ``patch``'s paths are relative to.
    public let root: URL

    /// The changes, one per affected file, in the order they were made.
    public let changes: [FileChange]

    /// Creates a change set.
    ///
    /// - Parameters:
    ///   - root: the session root the ``patch``'s paths are relative to.
    ///   - changes: the changes, one per affected file, in the order they
    ///     were made.
    public init(root: URL, changes: [FileChange]) {
        self.root = root
        self.changes = changes
    }

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
    public var patch: String { GitPatch.render(changes, relativeTo: root) }
}

// MARK: - Codable

extension FileChangeSet: Codable {
    /// The keys of the encoded object.
    ///
    /// `patch` is written and never read: it is a computed property rendered
    /// from ``changes``, thus a decode takes ``root`` and ``changes`` and
    /// renders the patch again.
    private enum CodingKeys: String, CodingKey {
        case root
        case changes
        case patch
    }

    /// Creates a change set from its encoded object, ignoring the `patch` key.
    ///
    /// `root` is read as an absolute path and rebuilt with
    /// `URL(fileURLWithPath:isDirectory:)`, `isDirectory: true`. That is the
    /// initializer `FileWalker.canonicalDirectory(_:)` builds a session root
    /// with, thus a set the journal drained and a set decoded from its
    /// encoding compare equal: the two-argument `URL(fileURLWithPath:)` gives
    /// a URL without the trailing separator, and `==` on `URL` tells the two
    /// spellings apart.
    ///
    /// - Parameter decoder: the decoder to read the object from.
    /// - Throws: `DecodingError` when the object lacks `root` or `changes`, or
    ///   when either has the wrong shape.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let path = try container.decode(String.self, forKey: .root)
        root = URL(fileURLWithPath: path, isDirectory: true)
        changes = try container.decode([FileChange].self, forKey: .changes)
    }

    /// Encodes the change set as an object with `root`, `changes` and `patch`.
    ///
    /// `root` is written as its absolute path (`root.path`, no trailing
    /// separator); `patch` is the rendered ``patch`` text, carried so a host
    /// that only shows a diff need not render one.
    ///
    /// - Parameter encoder: the encoder to write the object to.
    /// - Throws: `EncodingError` when the underlying container fails to encode
    ///   a value.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(root.path, forKey: .root)
        try container.encode(changes, forKey: .changes)
        try container.encode(patch, forKey: .patch)
    }
}

// MARK: - The OperationEvent detail envelope

extension FileChangeSet {
    /// The one top-level key of the envelope ``encodedOperationEventDetail()`` writes.
    ///
    /// A host reads an `OperationEvent.detail` and asks whether it is a change
    /// set or a plain notice; the presence of this key, over an object of this
    /// type, is the answer. ``init(operationEventDetail:)`` makes that test.
    ///
    /// It is the `schemaName` of the `ToolCallAttachment` a mutating verb call
    /// attaches as well, so one public name answers both carriers of the
    /// envelope and a host matches on it rather than on a literal of its own.
    public static let operationEventDetailKey = "fileChanges"

    /// The JSON text of the envelope `{"fileChanges": <encoded change set>}`.
    ///
    /// The text a tool posts as an `OperationEvent.detail` at the end of a
    /// call, and the text ``init(operationEventDetail:)`` reads back. The keys
    /// are sorted, thus the same set always encodes to the same text.
    ///
    /// - Returns: the envelope's JSON text.
    public func encodedOperationEventDetail() -> String {
        EditOutcomeProjection.encodedText([Self.operationEventDetailKey: self])
    }

    /// Creates a change set from the envelope ``encodedOperationEventDetail()`` wrote.
    ///
    /// Returns `nil` for any text that is not that envelope: a plain
    /// `notify()` detail such as `starting the sweep`, an object without the
    /// key (`{}`), or an object whose value under the key is not an encoded
    /// change set (`{"fileChanges": 1}`). Never throws, thus a host can try
    /// every detail it receives.
    ///
    /// - Parameter operationEventDetail: the `OperationEvent.detail` text.
    public init?(operationEventDetail: String) {
        let data = Data(operationEventDetail.utf8)
        guard
            let envelope = try? JSONDecoder().decode([String: FileChangeSet].self, from: data),
            let set = envelope[Self.operationEventDetailKey]
        else { return nil }
        self = set
    }
}
