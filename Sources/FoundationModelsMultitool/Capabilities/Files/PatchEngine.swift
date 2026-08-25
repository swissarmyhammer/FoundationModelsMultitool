// `PatchEngine` — two-phase, all-or-nothing applier that turns parsed
// `PatchParser.Hunk` values into multi-file mutations.
//
// A behavioral port of `../FoundationModelsFileTool/Sources/FileTool/
// PatchEngine.swift`. The sibling declares the types `public` for its own
// module surface; this package keeps them internal, the same way
// `PatchParser` and `EditEngine` beside it do.
//
// The engine keeps the corrective posture: a hunk that cannot apply comes
// back in-band as a `Result` failure, never thrown. Writes are atomic
// through `AtomicWriter`, and each path is bounded through `PathGuard`. The
// patch verb (`Patch`, card ^vb4dvzp) consumes the outcomes, beside the
// ported suite (`PatchEngineTests`).

import Foundation

/// Two-phase, all-or-nothing applier that turns parsed ``PatchParser/Hunk`` values into multi-file mutations.
///
/// The engine is the orchestration layer above the pure primitives: it composes
/// ``PathGuard`` (path validation), ``AtomicWriter`` (decode / encode / staged
/// write), and ``EditEngine`` (the find/replace resolution cascade) into a single
/// patch application, modeled on grok's `compute_all_changes` but stronger on
/// write atomicity. It performs file IO but stays free of the `@Operation` /
/// `Encodable` wire layer, returning engine-level ``FileOutcome`` values the way
/// ``EditEngine`` stays pure of `edit file`'s projection; the `patch files`
/// operation projects them.
///
/// **Phase 1 — compute (``computeChanges(_:using:capturingContent:)``).** Every
/// hunk's path is validated (`.write` for an Add, `.delete` for a Delete,
/// `.edit` for an Update with the move destination validated `.write`), and
/// each file's resulting bytes are computed *in memory* — Updates run the
/// ``EditEngine`` cascade against the decoded original — without touching the
/// filesystem. The first hunk that fails aborts the whole patch. Cross-file
/// conflicts are then detected: two hunks that produce the same final path, or
/// a produced path that is also a delete target, abort the patch (the
/// ``PatchParser`` deliberately leaves move-destination collisions to
/// apply-order semantics here, so a legal filename swap or rotation — distinct
/// final paths — is preserved while a genuine collision is rejected).
///
/// **Phase 2 — write (``writeChanges(_:)``).** Every add/update/move-destination
/// write is staged via ``AtomicWriter/stage(_:to:)`` first; a stage failure
/// discards every staged temporary and aborts with destinations untouched. Only
/// once all stages succeed are they committed, then move sources and delete
/// targets are unlinked — deletes last, and never a path that is also a write
/// destination, so a swap or rotation keeps the content another hunk wrote. An
/// unlink that fails after the commits is surfaced as a corrective rather than
/// swallowed, so the reported outcome never claims a removal that did not happen.
enum PatchEngine {
    // MARK: Result types

    /// The action a patched file underwent, as data.
    ///
    /// A `String`-raw-valued enum so the model-facing names live as data read via
    /// the non-optional `rawValue`, matching the ``AtomicWriter/LineEnding`` and
    /// ``AtomicWriter/TextEncoding`` idiom, rather than string literals repeated
    /// across the projection layer. `CaseIterable` so a projection that routes
    /// this vocabulary into another one through a table can be tested for
    /// totality, which the table gives up relative to an exhaustive `switch`.
    enum Action: String, CaseIterable, Equatable, Sendable {
        /// A new file was created (an Add).
        case added
        /// An existing file's contents were rewritten in place (an Update).
        case modified
        /// A file was removed (a Delete).
        case deleted
        /// A file was renamed to ``FileOutcome/movedTo`` (an Update with a Move).
        case moved
    }

    /// The per-file result of a committed patch: what happened to one file.
    ///
    /// The engine-level outcome the `patch files` operation projects into its wire
    /// output. The commit-only fields (``bytesWritten``, ``hash``) are `nil` for a
    /// ``Action/deleted`` file, which commits no bytes; ``movedTo`` is the
    /// destination path for a ``Action/moved`` file and `nil` otherwise.
    struct FileOutcome: Equatable, Sendable {
        /// The absolute path acted on (the source path for a move).
        let path: String

        /// The action the file underwent.
        let action: Action

        /// The absolute destination path for a ``Action/moved`` file; `nil` otherwise.
        let movedTo: String?

        /// The number of find/replace pairs applied (`0` for an Add, Delete, or pure rename).
        let appliedPairs: Int

        /// The number of bytes committed, or `nil` for a deleted file.
        let bytesWritten: Int?

        /// The whole-file freshness token over the committed bytes, or `nil` for a deleted file.
        let hash: String?

        /// The file's text before the patch, or `nil` for an added file (or one whose bytes are not text).
        ///
        /// The engine already holds this text — an Update decodes its source to
        /// resolve against — so reporting it costs nothing; a Delete's text is
        /// read best-effort, since the engine otherwise never reads a file it is
        /// only going to unlink. Carried so the operation layer can project the
        /// change set (and its patch) without re-reading files the patch has
        /// already overwritten.
        let oldContent: String?

        /// The file's text after the patch, or `nil` for a deleted file (or one whose bytes are not text).
        let newContent: String?

        /// The file a completed ``Action/moved`` outcome's destination genuinely destroyed, or `nil` when the destination was new, capture was not asked for, this outcome is not a move, or (see below) a peer hunk in the same patch actually accounts for that content.
        ///
        /// A `*** Move to:` onto an existing path silently overwrites that
        /// file, and phase 1 is the only moment its prior state can still be
        /// seen (see ``OverwrittenDestination``). A *stranded* move — a
        /// post-commit failure that leaves the source on disk — already
        /// reports that destruction by carrying the overwritten text as this
        /// outcome's own ``oldContent`` against a ``Action/modified`` action,
        /// so this field stays `nil` there; it exists only for a move that
        /// genuinely completed, where ``oldContent`` is already spoken for by
        /// the source's own before/after text and the destination's
        /// destruction would otherwise go unreported entirely.
        ///
        /// A swap (`a→b`, `b→a`) or a longer relocation chain makes every
        /// participating hunk's destination a path that already exists — that
        /// is what makes it a swap or chain — without anything actually being
        /// lost: the peer hunk whose own source is this destination carries
        /// that content forward to wherever *it* writes. ``outcomes(of:applied:)``
        /// recognizes this (via ``reportableOverwrittenDestination(for:moveSourcePaths:)``)
        /// and reports `nil` here in that case, so a swap or rotation reports
        /// none of its destinations as destroyed.
        let overwrittenDestination: OverwrittenDestination?

        /// Creates a per-file outcome.
        ///
        /// - Parameters:
        ///   - path: the absolute path acted on (the source path for a move).
        ///   - action: the action the file underwent.
        ///   - movedTo: the destination path for a moved file, or `nil`.
        ///   - appliedPairs: the number of find/replace pairs applied.
        ///   - bytesWritten: the number of bytes committed, or `nil`.
        ///   - hash: the whole-file freshness token over the committed bytes, or `nil`.
        ///   - oldContent: the file's text before the patch, or `nil`; defaults to `nil`.
        ///   - newContent: the file's text after the patch, or `nil`; defaults to `nil`.
        ///   - overwrittenDestination: the file a completed move's destination
        ///     overwrote, or `nil`; defaults to `nil`.
        init(
            path: String,
            action: Action,
            movedTo: String?,
            appliedPairs: Int,
            bytesWritten: Int?,
            hash: String?,
            oldContent: String? = nil,
            newContent: String? = nil,
            overwrittenDestination: OverwrittenDestination? = nil
        ) {
            self.path = path
            self.action = action
            self.movedTo = movedTo
            self.appliedPairs = appliedPairs
            self.bytesWritten = bytesWritten
            self.hash = hash
            self.oldContent = oldContent
            self.newContent = newContent
            self.overwrittenDestination = overwrittenDestination
        }
    }

    /// Why a patch was rejected, before or during application.
    ///
    /// Follows the upstream *return-don't-throw* convention (shared with
    /// ``PathViolation`` and ``ParseFailure``): a rejection is a `Result` failure,
    /// never raised. ``corrective(_:committed:)`` carries a message the model
    /// reads and acts on — a path violation, an add onto an existing file, a
    /// delete of a missing file, a binary update target, a cross-file conflict,
    /// a stage/commit failure, or a post-commit unlink failure that leaves a
    /// file on disk. ``unresolved(path:pair:resolution:)`` carries the failing
    /// file's path, the failing ``EditEngine/Pair``, and its non-definite
    /// ``EditEngine/Resolution`` so the operation can surface the same candidates
    /// and near-misses `edit file` does. The type conforms to `Error` only so it
    /// can be a `Result` failure — it is never thrown out of the engine.
    enum Failure: Error, Equatable, Sendable {
        /// A recoverable hard failure carrying a corrective message for the model, plus whatever had already committed.
        ///
        /// `committed` is empty for every rejection that leaves the filesystem
        /// untouched — which is all of them except the two post-commit paths
        /// (see ``committedOutcomes``) — so a caller that only projects the
        /// message can ignore it. Constructing the case does not require it,
        /// but *binding* the message does: match
        /// `case .corrective(let message, _)`, or read
        /// ``committedOutcomes`` and match bindingless.
        case corrective(String, committed: [FileOutcome] = [])

        /// An Update pair that did not resolve, carrying the file path and the engine resolution.
        case unresolved(path: String, pair: EditEngine.Pair, resolution: EditEngine.Resolution)

        /// The per-file outcomes that had already landed on disk when the patch failed.
        ///
        /// Phase 2 can fail after files have genuinely changed: a
        /// ``writeChanges(_:)`` commit that fails mid-sequence leaves the
        /// earlier renames in place, and a removal failure happens once every
        /// write has committed. Neither can be rolled back, so the failure
        /// reports what landed and the operation layer records it before
        /// returning the corrective — otherwise a host draining the change set
        /// would see nothing for files the patch really did rewrite.
        ///
        /// Empty for every other failure, all of which leave every file
        /// byte-identical.
        var committedOutcomes: [FileOutcome] {
            if case .corrective(_, let committed) = self { return committed }
            return []
        }
    }

    // MARK: Application

    /// Apply an ordered list of hunks as one all-or-nothing multi-file mutation.
    ///
    /// Runs phase 1 (``computeChanges(_:using:capturingContent:)``) to validate
    /// and compute every change in memory, then phase 2 (``writeChanges(_:)``)
    /// to stage, commit, and unlink. Any phase-1 failure leaves the filesystem
    /// untouched; a phase-2 stage failure discards every staged temporary,
    /// leaving destinations untouched.
    ///
    /// - Parameters:
    ///   - hunks: the parsed hunks to apply, in order.
    ///   - pathGuard: the guard that validates and resolves every path.
    ///   - capturingContent: whether each outcome carries the file's text on
    ///     both sides (see ``FileOutcome/oldContent``); defaults to `false`,
    ///     which also skips the one read the engine would not otherwise make —
    ///     a Delete's.
    /// - Returns: `.success` with the per-file outcomes, or `.failure` with a
    ///   ``Failure`` the operation layer projects.
    static func apply(
        _ hunks: [PatchParser.Hunk],
        using pathGuard: PathGuard,
        capturingContent: Bool = false
    ) -> Result<[FileOutcome], Failure> {
        computeChanges(hunks, using: pathGuard, capturingContent: capturingContent)
            .flatMap(writeChanges)
    }

    // MARK: Phase 1 — compute

    /// A computed, not-yet-written change for one hunk.
    ///
    /// The uniform in-memory representation phase 1 produces and phase 2 consumes:
    /// an optional ``Write`` (the staged bytes; `nil` for a pure Delete) and an
    /// optional ``Removal`` (a path to unlink after commits), plus the reported
    /// outcome fields. Modeling every hunk as one struct — rather than a parallel
    /// enum the write phase must re-switch on — keeps the two phases from drifting.
    private struct Change {
        /// The absolute path reported in the outcome (the source path for a move).
        let reportedPath: String

        /// The action the file underwent.
        let action: Action

        /// The absolute destination path for a move; `nil` otherwise.
        let movedTo: String?

        /// The number of find/replace pairs applied.
        let appliedPairs: Int

        /// The staged write to perform, or `nil` for a pure Delete.
        let write: Write?

        /// A path to unlink after all writes commit, or `nil`.
        let removal: Removal?

        /// The file a move's destination overwrites, or `nil` when the destination is new or this is not a move.
        let overwrittenDestination: OverwrittenDestination?

        /// The file's text before the patch, reported on the outcome; `nil` for an Add.
        let oldContent: String?

        /// The file's text after the patch, reported on the outcome; `nil` for a Delete.
        let newContent: String?
    }

    /// A file write to stage and commit: the destination and its final bytes.
    private struct Write {
        /// The resolved destination URL.
        let url: URL

        /// The bytes to commit, already re-encoded with the file's detected encoding.
        let data: Data
    }

    /// A path to unlink after all writes commit, tagged so deletes run last.
    private struct Removal {
        /// Whether the removal is a move's abandoned source or an explicit delete target.
        enum Kind {
            /// The source path of an Update-with-Move, removed after the destination commits.
            case moveSource
            /// The target of a Delete.
            case deleteTarget
        }

        /// Which kind of removal this is, controlling unlink ordering.
        let kind: Kind

        /// The resolved path to unlink.
        let url: URL
    }

    /// The file a move's destination already held, observed in phase 1 before anything is written.
    ///
    /// A `*** Move to:` onto an existing path overwrites that file. Phase 1 is
    /// the only moment that prior state can still be seen, and a post-commit
    /// failure that strands the rename — destination written, source still on
    /// disk — has to report the destination as a *modification* of that file
    /// rather than as a creation. Its presence is the "already existed"
    /// answer; ``content`` is the text, which a non-recording session does not
    /// pay to read.
    ///
    /// Not `private`, so a *completed* move can carry it too, on
    /// ``FileOutcome/overwrittenDestination`` — the stranded case folds it
    /// into ``FileOutcome/oldContent`` instead (see that property), but a
    /// completed rename has no other slot for the destination's destroyed
    /// text, since ``FileOutcome/oldContent`` there already reports the
    /// source's own prior text.
    struct OverwrittenDestination: Equatable, Sendable {
        /// The destination's text before the patch, or `nil` when content is not captured or the bytes are not text.
        let content: String?
    }

    /// Compute every hunk's change in memory, then detect cross-file conflicts.
    ///
    /// Validates and resolves each hunk in order (aborting on the first failure),
    /// then rejects a patch whose changes collide on a final path. Nothing on disk
    /// is touched.
    ///
    /// - Parameters:
    ///   - hunks: the hunks to compute changes for.
    ///   - pathGuard: the guard that validates and resolves every path.
    ///   - capturingContent: whether to carry each file's text on both sides.
    /// - Returns: `.success` with the computed changes, or `.failure`.
    private static func computeChanges(
        _ hunks: [PatchParser.Hunk],
        using pathGuard: PathGuard,
        capturingContent: Bool
    ) -> Result<[Change], Failure> {
        do {
            var changes: [Change] = []
            for hunk in hunks {
                changes.append(
                    try computeChange(hunk, using: pathGuard, capturingContent: capturingContent).get()
                )
            }
            if let conflict = conflictViolation(in: changes) {
                return .failure(.corrective(conflict))
            }
            return .success(changes)
        } catch {
            return .failure(error)
        }
    }

    /// Compute the change for one hunk, validating its path and resolving its bytes.
    ///
    /// - Parameters:
    ///   - hunk: the hunk to compute.
    ///   - pathGuard: the guard that validates and resolves the path.
    ///   - capturingContent: whether to carry the file's text on both sides.
    /// - Returns: `.success` with the computed change, or `.failure`.
    private static func computeChange(
        _ hunk: PatchParser.Hunk,
        using pathGuard: PathGuard,
        capturingContent: Bool
    ) -> Result<Change, Failure> {
        switch hunk {
        case .addFile(let path, let contents):
            return computeAdd(
                path: path, contents: contents, using: pathGuard, capturingContent: capturingContent)
        case .deleteFile(let path):
            return computeDelete(path: path, using: pathGuard, capturingContent: capturingContent)
        case .updateFile(let path, let movePath, let pairs):
            return computeUpdate(
                path: path,
                movePath: movePath,
                pairs: pairs,
                using: pathGuard,
                capturingContent: capturingContent
            )
        }
    }

    /// Compute an Add: validate `.write`, reject an existing target, and stage the new bytes.
    ///
    /// An Add means a *new* file (overwriting an existing file is `write file`'s
    /// job), so a target that already exists is a corrective. The contents are
    /// encoded as plain UTF-8 — a freshly created file has no prior encoding to
    /// preserve.
    ///
    /// - Parameters:
    ///   - path: the file to create.
    ///   - contents: the new file's contents.
    ///   - pathGuard: the guard that validates and resolves the path.
    ///   - capturingContent: whether to carry the created text on the outcome.
    /// - Returns: `.success` with the add change, or `.failure`.
    private static func computeAdd(
        path: String,
        contents: String,
        using pathGuard: PathGuard,
        capturingContent: Bool
    ) -> Result<Change, Failure> {
        validate(path, for: .write, using: pathGuard).flatMap { url in
            guard !fileExists(url) else {
                return .failure(.corrective(Messages.addExists(path: url.path)))
            }
            let data = AtomicWriter.encode(contents, as: .utf8)
            return .success(
                Change(
                    reportedPath: url.path,
                    action: .added,
                    movedTo: nil,
                    appliedPairs: 0,
                    write: Write(url: url, data: data),
                    removal: nil,
                    overwrittenDestination: nil,
                    oldContent: nil,
                    newContent: capturingContent ? contents : nil
                )
            )
        }
    }

    /// Compute a Delete: validate `.delete`, capture the removed text, and record the target for unlinking.
    ///
    /// The original bytes are read *best-effort* only — via
    /// ``AtomicWriter/decodedText(at:)``, which never throws — so the removed
    /// text can be reported on the outcome (a deletion's patch hunk is the text
    /// it removed) while an unreadable file still deletes. Requiring readability
    /// would wrongly reject a deletable-but-unreadable file, since the `.delete`
    /// permission (unlink permission lives on the parent directory) does not
    /// require read access; such a file simply reports no old text.
    ///
    /// - Parameters:
    ///   - path: the file to delete.
    ///   - pathGuard: the guard that validates and resolves the path.
    ///   - capturingContent: whether to read the removed text; when `false` the
    ///     engine reads nothing at all, as it did before change sets existed.
    /// - Returns: `.success` with the delete change, or `.failure`.
    private static func computeDelete(
        path: String,
        using pathGuard: PathGuard,
        capturingContent: Bool
    ) -> Result<Change, Failure> {
        validate(path, for: .delete, using: pathGuard).map { url in
            Change(
                reportedPath: url.path,
                action: .deleted,
                movedTo: nil,
                appliedPairs: 0,
                write: nil,
                removal: Removal(kind: .deleteTarget, url: url),
                overwrittenDestination: nil,
                oldContent: capturingContent ? AtomicWriter.decodedText(at: url) : nil,
                newContent: nil
            )
        }
    }

    /// Compute an Update: validate, decode, resolve the pairs, and stage the rewritten bytes.
    ///
    /// Validates the source `.edit` and, for a Move, the destination `.write`,
    /// reads and decodes the source (a binary file is a corrective), runs the
    /// ``EditEngine`` cascade over the decoded text (an unresolved pair aborts the
    /// patch, carrying the path and resolution), and re-encodes the result with the
    /// source's detected encoding — so a CRLF/BOM file keeps its convention through
    /// the decode/encode round-trip. A pure rename (a Move with no pairs) re-encodes
    /// the original content unchanged for the destination.
    ///
    /// - Parameters:
    ///   - path: the file to update.
    ///   - movePath: the rename destination, or `nil`.
    ///   - pairs: the find/replace pairs to apply, in order.
    ///   - pathGuard: the guard that validates and resolves the paths.
    ///   - capturingContent: whether to carry the text on both sides.
    /// - Returns: `.success` with the update change, or `.failure`.
    private static func computeUpdate(
        path: String,
        movePath: String?,
        pairs: [PatchParser.Pair],
        using pathGuard: PathGuard,
        capturingContent: Bool
    ) -> Result<Change, Failure> {
        do {
            let sourceURL = try validate(path, for: .edit, using: pathGuard).get()
            let destinationURL = try resolveDestination(movePath, using: pathGuard).get()
            let decoded = try decodeSource(sourceURL).get()
            let resolved = try resolveContent(pairs, in: decoded.text, path: sourceURL.path).get()
            return .success(
                makeUpdateChange(
                    sourceURL: sourceURL,
                    destinationURL: destinationURL,
                    decoded: decoded,
                    resolved: resolved,
                    capturingContent: capturingContent
                )
            )
        } catch {
            return .failure(error)
        }
    }

    /// Resolve an optional move destination, validating it for `.write`.
    ///
    /// - Parameters:
    ///   - movePath: the rename destination, or `nil` for an in-place update.
    ///   - pathGuard: the guard that validates and resolves the path.
    /// - Returns: `.success` with the resolved destination URL, `.success(nil)`
    ///   for an in-place update, or `.failure`.
    private static func resolveDestination(
        _ movePath: String?,
        using pathGuard: PathGuard
    ) -> Result<URL?, Failure> {
        guard let movePath else { return .success(nil) }
        return validate(movePath, for: .write, using: pathGuard).map { $0 }
    }

    /// Read and decode a source file, rejecting an unreadable or binary file.
    ///
    /// The unreadable-path read goes through ``PathCorrective/readData(at:path:)``,
    /// the same helper `read file` and `edit file` use, so the corrective wording
    /// cannot drift between the three operations.
    ///
    /// - Parameter url: the resolved source URL.
    /// - Returns: `.success` with the decoded text and encoding, or `.failure`.
    private static func decodeSource(_ url: URL) -> Result<AtomicWriter.DecodedText, Failure> {
        PathCorrective.readData(at: url, path: url.path)
            .mapError { Failure.corrective($0.correctiveMessage) }
            .flatMap { data in
                guard let decoded = AtomicWriter.decode(data) else {
                    return .failure(.corrective(Messages.binary(path: url.path)))
                }
                return .success(decoded)
            }
    }

    /// The resolved content of an Update and the number of pairs applied.
    private struct ResolvedContent {
        /// The rewritten (or, for a pure rename, unchanged) content.
        let content: String

        /// The number of find/replace pairs applied.
        let appliedPairs: Int
    }

    /// Resolve an Update's find/replace pairs against the decoded source text.
    ///
    /// An empty pair list is a pure rename and yields the text unchanged. Otherwise
    /// the batch runs through ``EditEngine/apply(_:to:)`` with exactly `edit file`'s
    /// semantics; the first unresolved pair aborts the patch.
    ///
    /// - Parameters:
    ///   - pairs: the find/replace pairs, in order.
    ///   - text: the decoded source text to resolve against.
    ///   - path: the source path, carried on an unresolved failure.
    /// - Returns: `.success` with the resolved content, or `.failure` naming the
    ///   unresolved pair and its resolution.
    private static func resolveContent(
        _ pairs: [PatchParser.Pair],
        in text: String,
        path: String
    ) -> Result<ResolvedContent, Failure> {
        guard !pairs.isEmpty else {
            return .success(ResolvedContent(content: text, appliedPairs: 0))
        }
        let enginePairs = pairs.map { EditEngine.Pair(find: $0.find, replace: $0.replace) }
        switch EditEngine.apply(enginePairs, to: text) {
        case .applied(let content, let edits):
            return .success(ResolvedContent(content: content, appliedPairs: edits.count))
        case .failed(_, let pair, let resolution):
            return .failure(.unresolved(path: path, pair: pair, resolution: resolution))
        }
    }

    /// Assemble the ``Change`` for a resolved Update, choosing the write target and removal.
    ///
    /// An in-place update writes back to the source; a Move writes the destination
    /// and records the source for removal after the commit.
    ///
    /// - Parameters:
    ///   - sourceURL: the resolved source URL.
    ///   - destinationURL: the resolved move destination, or `nil` for in place.
    ///   - decoded: the decoded source, supplying the encoding to re-apply.
    ///   - resolved: the resolved content and applied-pair count.
    ///   - capturingContent: whether to carry the text on both sides.
    /// - Returns: the assembled change.
    private static func makeUpdateChange(
        sourceURL: URL,
        destinationURL: URL?,
        decoded: AtomicWriter.DecodedText,
        resolved: ResolvedContent,
        capturingContent: Bool
    ) -> Change {
        let writeURL = destinationURL ?? sourceURL
        let data = AtomicWriter.encode(resolved.content, as: decoded.encoding)
        return Change(
            reportedPath: sourceURL.path,
            action: destinationURL == nil ? .modified : .moved,
            movedTo: destinationURL?.path,
            appliedPairs: resolved.appliedPairs,
            write: Write(url: writeURL, data: data),
            removal: destinationURL.map { _ in Removal(kind: .moveSource, url: sourceURL) },
            overwrittenDestination: overwrittenDestination(
                at: destinationURL, capturingContent: capturingContent),
            oldContent: capturingContent ? decoded.text : nil,
            newContent: capturingContent ? resolved.content : nil
        )
    }

    /// The file a move destination already holds, or `nil` when the destination is new or there is none.
    ///
    /// The existence check is a `stat` the engine always makes for a move —
    /// cheap, and the only chance to learn whether the rename creates or
    /// overwrites. The prior text costs a read, so it is taken only when the
    /// session captures content, exactly as a Delete's is.
    ///
    /// - Parameters:
    ///   - url: the resolved move destination, or `nil` for an in-place update.
    ///   - capturingContent: whether to read the overwritten text.
    /// - Returns: the overwritten destination, or `nil` when nothing is overwritten.
    private static func overwrittenDestination(
        at url: URL?,
        capturingContent: Bool
    ) -> OverwrittenDestination? {
        guard let url, fileExists(url) else { return nil }
        return OverwrittenDestination(
            content: capturingContent ? AtomicWriter.decodedText(at: url) : nil)
    }

    // MARK: Cross-file conflict detection

    /// The conflict message when two changes collide on a final path, or `nil` when they do not.
    ///
    /// A patch is rejected when two hunks *produce* the same final path (two writes
    /// to one destination — the move-destination collision the ``PatchParser``
    /// leaves to apply-order semantics), or when a produced path is also a delete
    /// target (a file both written and deleted). Distinct final paths — a swap or
    /// rotation — pass.
    ///
    /// - Parameter changes: the computed changes to check.
    /// - Returns: a corrective message naming the colliding path, or `nil`.
    private static func conflictViolation(in changes: [Change]) -> String? {
        var produced: Set<String> = []
        for change in changes {
            guard let write = change.write else { continue }
            if !produced.insert(write.url.path).inserted {
                return Messages.conflict(path: write.url.path)
            }
        }
        for change in changes {
            if let removal = change.removal, removal.kind == .deleteTarget, produced.contains(removal.url.path) {
                return Messages.conflict(path: removal.url.path)
            }
        }
        return nil
    }

    // MARK: Phase 2 — write

    /// What phase 2 actually applied to the filesystem, accumulated as it goes.
    ///
    /// Phase 2 is the only part of the engine that can stop with the workspace
    /// changed, so it keeps a running ledger of what has landed rather than
    /// inferring it after the fact. The success report and both post-commit
    /// failure reports are projected from this one value
    /// (``outcomes(of:applied:)``), so a partially applied patch is described
    /// by the same code that describes a complete one.
    ///
    /// The ledger identifies changes by their index rather than by path: two
    /// sections can name one file (the ``PatchParser`` de-duplicates on the
    /// declared path string, which `realpath` may collapse), and crediting one
    /// section's removal to another would report a file as both renamed and
    /// deleted.
    private struct Applied {
        /// The number of staged writes that have committed, in staging order.
        var committedWrites = 0

        /// The indices of the changes whose removal is settled: unlinked, or deliberately skipped because a peer hunk writes that path.
        var settledRemovals: Set<Int> = []
    }

    /// Stage, commit, and unlink every computed change as one atomic multi-file write.
    ///
    /// Stages every write first; a stage failure discards all staged temporaries
    /// and aborts with destinations untouched. Once every stage succeeds, the
    /// writes are committed and then move sources and delete targets are unlinked
    /// (deletes last, and never a path that is also a write destination). The
    /// per-file outcomes are computed from the committed bytes.
    ///
    /// Both post-commit failures — a commit that fails mid-sequence, and an
    /// unlink that fails once every write has landed — carry the outcomes for
    /// the part of the patch that *did* land, so the operation layer can record
    /// those files before returning the corrective.
    ///
    /// - Parameter changes: the computed changes to write.
    /// - Returns: `.success` with the per-file outcomes, or `.failure`.
    private static func writeChanges(_ changes: [Change]) -> Result<[FileOutcome], Failure> {
        var staged: [AtomicWriter.StagedWrite] = []
        for write in changes.compactMap(\.write) {
            do {
                staged.append(try AtomicWriter.stage(write.data, to: write.url))
            } catch {
                for stagedWrite in staged {
                    stagedWrite.discard()
                }
                return .failure(.corrective(Messages.stageFailure(path: write.url.path)))
            }
        }
        // `??` sequences the two write steps: removals are attempted only when
        // every commit succeeded, and the first failing step's message wins.
        var applied = Applied()
        let failed =
            commit(staged, recordingInto: &applied)
            ?? performRemovals(changes, recordingInto: &applied)
        guard let message = failed else {
            return .success(outcomes(of: changes, applied: applied))
        }
        return .failure(.corrective(message, committed: outcomes(of: changes, applied: applied)))
    }

    /// Commit every staged write, discarding the uncommitted remainder on a failure.
    ///
    /// The partial-write window the staged design shrinks to the sequence of
    /// renames: an interrupted commit leaves the already-committed writes in place
    /// and discards the temporaries not yet committed.
    ///
    /// - Parameters:
    ///   - staged: the staged writes to commit, in order.
    ///   - applied: the ledger each successful commit is counted into.
    /// - Returns: the corrective message when a commit fails, or `nil` when all commit.
    private static func commit(
        _ staged: [AtomicWriter.StagedWrite],
        recordingInto applied: inout Applied
    ) -> String? {
        for (index, write) in staged.enumerated() {
            do {
                try write.commit()
                applied.committedWrites += 1
            } catch {
                for uncommitted in staged[index...] {
                    uncommitted.discard()
                }
                return Messages.commitFailure(path: write.destinationURL.path)
            }
        }
        return nil
    }

    /// Unlink move sources and delete targets, deletes last, skipping any write destination.
    ///
    /// The removal order is data — ``Removal/Kind/moveSource`` before
    /// ``Removal/Kind/deleteTarget`` — so "deletes last" is expressed once rather
    /// than as duplicated passes. Which paths are actually unlinked, and what a
    /// skipped one means, is ``settle(_:at:skipping:recordingInto:)``'s to say.
    ///
    /// An unlink that fails aborts with a corrective rather than being swallowed:
    /// removals run *after* every write has committed, so a failed unlink cannot
    /// be rolled back, but reporting `.success` here would emit a ``FileOutcome``
    /// claiming a `.deleted`/`.moved` file that in fact still exists on disk. The
    /// corrective keeps the reported outcome truthful — a removal failure is
    /// surfaced the same way ``commit(_:recordingInto:)`` surfaces a
    /// post-commit failure — while the committed writes (which cannot be
    /// undone) stay in place and are reported as such.
    ///
    /// - Parameters:
    ///   - changes: the committed changes whose removals to perform.
    ///   - applied: the ledger each settled removal is recorded into.
    /// - Returns: the corrective message when an unlink fails, or `nil` when all succeed.
    private static func performRemovals(
        _ changes: [Change],
        recordingInto applied: inout Applied
    ) -> String? {
        let writeDestinations = Set(changes.compactMap { $0.write?.url.path })
        for kind in removalOrder {
            for (index, change) in changes.enumerated() {
                guard let removal = change.removal, removal.kind == kind else { continue }
                if let message = settle(removal, at: index, skipping: writeDestinations, recordingInto: &applied) {
                    return message
                }
            }
        }
        return nil
    }

    /// Settle one change's removal: unlink the path, or leave it to the peer hunk that writes it.
    ///
    /// The whole per-change removal, so ``performRemovals(_:recordingInto:)``
    /// stays a pair of loops over *which* removals run in *what* order and this
    /// carries *how* one runs. A removal path that is also a write destination
    /// is settled without unlinking — the peer hunk's content is what belongs
    /// there, so a swap (`a→b`, `b→a`) or rotation keeps it — and either way
    /// the change is recorded in the ledger only once nothing more will happen
    /// to it, never on a failed unlink.
    ///
    /// What the ledger then means for the report is
    /// ``outcomes(of:applied:)``'s: a Delete left unsettled contributes no
    /// outcome at all, while an unsettled *move* — whose write did commit — is
    /// still reported, at its destination as a stranded move rather than as a
    /// rename that did not happen.
    ///
    /// - Parameters:
    ///   - removal: the removal to settle.
    ///   - index: the owning change's index, recorded in the ledger once settled.
    ///   - writeDestinations: the paths this patch writes, which are never unlinked.
    ///   - applied: the ledger the settled removal is recorded into.
    /// - Returns: the corrective message when the unlink fails, or `nil` once settled.
    private static func settle(
        _ removal: Removal,
        at index: Int,
        skipping writeDestinations: Set<String>,
        recordingInto applied: inout Applied
    ) -> String? {
        if !writeDestinations.contains(removal.url.path) {
            do {
                try FileManager.default.removeItem(at: removal.url)
            } catch {
                return Messages.removalFailure(path: removal.url.path)
            }
        }
        applied.settledRemovals.insert(index)
        return nil
    }

    /// The order removals run in: move sources first, delete targets last.
    ///
    /// So an interrupted patch errs on the side of leaving extra files rather than
    /// losing content.
    private static let removalOrder: [Removal.Kind] = [.moveSource, .deleteTarget]

    /// The per-file outcomes for everything phase 2 actually applied.
    ///
    /// One outcome per change whose effect reached disk, in hunk order. A
    /// complete patch reports every change; a patch stopped by a post-commit
    /// failure reports only the part that landed — a change whose write never
    /// committed, or a Delete whose unlink never ran, contributes nothing.
    ///
    /// Both halves of the ledger are matched by change index, so a patch whose
    /// sections happen to name one file cannot have one section's progress
    /// credited to another.
    ///
    /// - Parameters:
    ///   - changes: the computed changes, in hunk order.
    ///   - applied: what phase 2 landed.
    /// - Returns: the per-file outcomes, in hunk order.
    private static func outcomes(of changes: [Change], applied: Applied) -> [FileOutcome] {
        let committedWrites = Set(
            changes.indices.filter { changes[$0].write != nil }.prefix(applied.committedWrites))
        let moveSourcePaths = Set(changes.map(\.reportedPath))
        return changes.indices.compactMap { index -> FileOutcome? in
            let change = changes[index]
            if change.write != nil {
                guard committedWrites.contains(index) else { return nil }
                return committedOutcome(
                    for: change, at: index, applied: applied, moveSourcePaths: moveSourcePaths)
            }
            guard change.removal != nil, applied.settledRemovals.contains(index) else { return nil }
            return outcome(for: change, moveSourcePaths: moveSourcePaths)
        }
    }

    /// The outcome for a change whose write committed, allowing for a rename left half-done.
    ///
    /// A move is complete only once its source is gone: unlinked, or left in
    /// place because a peer hunk writes that path (a swap or rotation). Until
    /// then the destination holds the new bytes while the source still exists,
    /// which is not a rename — so the outcome is reported at the destination
    /// instead of as a move.
    ///
    /// - Parameters:
    ///   - change: the change whose write committed.
    ///   - index: the change's index, identifying its removal in the ledger.
    ///   - applied: what phase 2 landed.
    ///   - moveSourcePaths: every hunk's own reported (source) path in this patch.
    /// - Returns: the per-file outcome.
    private static func committedOutcome(
        for change: Change,
        at index: Int,
        applied: Applied,
        moveSourcePaths: Set<String>
    ) -> FileOutcome {
        guard change.action == .moved, let movedTo = change.movedTo,
            !applied.settledRemovals.contains(index)
        else {
            return outcome(for: change, moveSourcePaths: moveSourcePaths)
        }
        return strandedMoveOutcome(for: change, movedTo: movedTo)
    }

    /// The outcome for a rename stranded by a post-commit failure: destination written, source still on disk.
    ///
    /// Reporting ``Action/moved`` here would claim a rename that did not
    /// happen, so the outcome describes the only thing that did: the
    /// destination now holds the new bytes, as a creation or — when the move
    /// overwrote a file that was already there — a modification of it.
    ///
    /// - Parameters:
    ///   - change: the move change whose write committed but whose source remains.
    ///   - movedTo: the destination path the bytes landed on.
    /// - Returns: the per-file outcome, reported at the destination.
    private static func strandedMoveOutcome(for change: Change, movedTo: String) -> FileOutcome {
        let overwritten = change.overwrittenDestination
        return outcome(
            for: change,
            reportedAt: movedTo,
            action: overwritten == nil ? .added : .modified,
            movedTo: nil,
            oldContent: overwritten?.content
        )
    }

    /// Project an applied change into its per-file outcome.
    ///
    /// - Parameters:
    ///   - change: the change whose write committed, or a Delete whose unlink ran.
    ///   - moveSourcePaths: every hunk's own reported (source) path in this patch.
    /// - Returns: the per-file outcome, reported the way phase 1 computed it.
    private static func outcome(for change: Change, moveSourcePaths: Set<String>) -> FileOutcome {
        outcome(
            for: change,
            reportedAt: change.reportedPath,
            action: change.action,
            movedTo: change.movedTo,
            oldContent: change.oldContent,
            overwrittenDestination: reportableOverwrittenDestination(
                for: change, moveSourcePaths: moveSourcePaths)
        )
    }

    /// The ``FileOutcome/overwrittenDestination`` to report for a completed change, suppressing a false "destroyed" claim a peer hunk actually accounts for.
    ///
    /// A swap (`a→b`, `b→a`) or a longer relocation chain makes every
    /// participating hunk's destination a path that already exists — that is
    /// what makes it a swap or chain — so phase 1's
    /// ``overwrittenDestination(at:capturingContent:)`` sees an occupant
    /// there regardless of whether anything is actually lost. But when that
    /// destination path is also declared as *another* hunk's own source in
    /// this same atomic patch, its prior content is not destroyed: the peer
    /// hunk's own outcome accounts for it, relocating it (edited or not) to
    /// wherever that hunk writes. A conflicting combination — a peer hunk
    /// that instead deletes or rewrites this same destination in place —
    /// is already rejected in phase 1 by ``conflictViolation(in:)``, so the
    /// only way a peer can legally share this destination as its own source
    /// is by moving it elsewhere, which is exactly the case this suppresses.
    ///
    /// - Parameters:
    ///   - change: the change whose write committed and whose removal settled.
    ///   - moveSourcePaths: every hunk's own reported (source) path in this patch.
    /// - Returns: the change's own overwritten destination, or `nil` when a
    ///   peer hunk accounts for it instead.
    private static func reportableOverwrittenDestination(
        for change: Change,
        moveSourcePaths: Set<String>
    ) -> OverwrittenDestination? {
        guard let movedTo = change.movedTo, !moveSourcePaths.contains(movedTo) else { return nil }
        return change.overwrittenDestination
    }

    /// Project an applied change into an outcome reported at a caller-chosen path, action, and prior text.
    ///
    /// The single place a ``FileOutcome`` is built from a ``Change``, split so
    /// its two halves cannot drift. What the write *produced* —
    /// ``FileOutcome/appliedPairs``, ``FileOutcome/bytesWritten``,
    /// ``FileOutcome/hash``, ``FileOutcome/newContent`` — is a property of the
    /// change itself, identical however the change is reported, so it is
    /// derived here rather than at each report site. Everything that depends
    /// on *where* the change is reported — ``FileOutcome/path``,
    /// ``FileOutcome/action``, ``FileOutcome/movedTo`` and
    /// ``FileOutcome/oldContent`` — is the caller's to supply.
    ///
    /// ``FileOutcome/oldContent`` is in that second group for a reason worth
    /// stating: it is the prior text of the *reported* path, not of the
    /// change's source. A rename stranded at its destination therefore reports
    /// the text of the file it overwrote (``Change/overwrittenDestination``),
    /// never ``Change/oldContent``.
    ///
    /// The byte-derived fields come from the staged bytes, which are exactly
    /// the committed bytes (the temporary holding them was renamed onto the
    /// destination), so the reported ``FileOutcome/hash`` matches a subsequent
    /// `read file` over the same file.
    ///
    /// ``FileOutcome/overwrittenDestination`` defaults to `nil`: only a
    /// *completed* move (the ``outcome(for:moveSourcePaths:)`` overload above)
    /// passes it through, since a stranded move already folds the same fact
    /// into ``FileOutcome/oldContent`` at the caller's choice of `action` and
    /// would otherwise report the destruction twice.
    ///
    /// - Parameters:
    ///   - change: the change whose write committed, or a Delete whose unlink ran.
    ///   - path: the absolute path to report the change at.
    ///   - action: the action to report.
    ///   - movedTo: the destination path to report for a completed move, or `nil`.
    ///   - oldContent: the text the reported path held before the patch, or `nil`.
    ///   - overwrittenDestination: the file a completed move's destination
    ///     overwrote, or `nil`; defaults to `nil`.
    /// - Returns: the per-file outcome.
    private static func outcome(
        for change: Change,
        reportedAt path: String,
        action: Action,
        movedTo: String?,
        oldContent: String?,
        overwrittenDestination: OverwrittenDestination? = nil
    ) -> FileOutcome {
        FileOutcome(
            path: path,
            action: action,
            movedTo: movedTo,
            appliedPairs: change.appliedPairs,
            bytesWritten: change.write?.data.count,
            hash: change.write.map { Hashline.wholeFileHash(bytes: $0.data) },
            oldContent: oldContent,
            newContent: change.newContent,
            overwrittenDestination: overwrittenDestination
        )
    }

    // MARK: Path validation

    /// Validate a path for an operation, mapping a violation to a corrective failure.
    ///
    /// - Parameters:
    ///   - path: the raw path to validate.
    ///   - operation: the access kind whose rule to apply.
    ///   - pathGuard: the guard to validate against.
    /// - Returns: `.success` with the resolved URL, or `.failure` carrying the
    ///   violation message as a corrective.
    private static func validate(
        _ path: String,
        for operation: FileOperation,
        using pathGuard: PathGuard
    ) -> Result<URL, Failure> {
        pathGuard.validate(path, for: operation).mapError { .corrective($0.correctiveMessage) }
    }

    /// Whether a file exists on disk at a URL, following symlinks.
    ///
    /// - Parameter url: the URL to test.
    /// - Returns: `true` when a file exists at the URL.
    private static func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: Corrective messages

    /// The corrective messages for every patch rejection, defined in one place.
    private enum Messages {
        /// The corrective for an Add whose target already exists.
        ///
        /// - Parameter path: the existing target path.
        /// - Returns: the corrective message.
        static func addExists(path: String) -> String {
            "Cannot add a file that already exists: \(path). "
                + "Use an `*** Update File:` section to change an existing file."
        }

        /// The description of a non-UTF-8 (binary) Update source, before the `: path` suffix.
        ///
        /// Composed with ``PathCorrective/pathErrorMessage(description:path:)`` at
        /// the call site; the unreadable-path description lives there too
        /// (``PathCorrective/unreadableDescription``), since it is byte-identical
        /// to `read file`/`edit file`'s. This wording is patch-specific (`patched`
        /// rather than `read`/`edited`), so it stays local rather than joining
        /// ``PathCorrective`` outright.
        private static let binaryDescription =
            "The file is not valid UTF-8 text and appears to be binary, so it cannot be patched as text"

        /// The corrective for a binary (non-UTF-8) Update source.
        ///
        /// - Parameter path: the source path.
        /// - Returns: the corrective message.
        static func binary(path: String) -> String {
            PathCorrective.pathErrorMessage(description: binaryDescription, path: path)
        }

        /// The corrective for two patch sections resolving to the same final path.
        ///
        /// - Parameter path: the colliding final path.
        /// - Returns: the corrective message.
        static func conflict(path: String) -> String {
            "Two patch sections target the same path `\(path)`; a patch must resolve each file exactly once."
        }

        /// The corrective for a write that could not be staged (nothing was changed).
        ///
        /// - Parameter path: the destination that failed to stage.
        /// - Returns: the corrective message.
        static func stageFailure(path: String) -> String {
            "A file in the patch could not be staged for writing, so no files were changed: \(path)"
        }

        /// The corrective for a staged write that could not be committed.
        ///
        /// - Parameter path: the destination that failed to commit.
        /// - Returns: the corrective message.
        static func commitFailure(path: String) -> String {
            "The patch resolved but a file could not be committed: \(path)"
        }

        /// The corrective for a move source or delete target that could not be unlinked.
        ///
        /// Removals run after every write commits, so this reports a file that
        /// could not be removed even though the patch's writes landed — the file
        /// remains on disk, and the outcome does not claim it was deleted or moved.
        ///
        /// - Parameter path: the path that could not be unlinked.
        /// - Returns: the corrective message.
        static func removalFailure(path: String) -> String {
            "The patch's writes committed but a file could not be removed, so it remains on disk: \(path)"
        }
    }
}
