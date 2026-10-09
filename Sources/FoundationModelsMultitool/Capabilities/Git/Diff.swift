// `Diff` — the `tools.git.diff` verb.
//
// git.md § "The source", Layer 1, item 2: a port of the `get diff` operation
// of the sah MCP tool `git` (`diff/mod.rs` in
// `../swissarmyhammer/crates/swissarmyhammer-tools/src/mcp/tools/git/`, and
// the dispatch `execute_diff` in `changes/mod.rs`). The diff is at the entity
// level (function, class, and other entities), through the semantic engine
// (`Semantic/SemanticDiffer.swift`, git.md § "Decisions", item 6). Each mode
// also reports the changed lines that no entity holds
// (`Semantic/UncoveredLines.swift`, task `^8fd3kgk`), which the Rust source
// does not: there, a comment added at the end of a file gives no change.
//
// git.md § "Decisions", item 9: `diff` is one verb with three modes, the same
// as the source, and each argument and each result field is `camelCase`. The
// modes, in the order of the Rust dispatch:
//
// 1. Inline: `leftText`, `rightText`, and `language`. The text goes to the
//    plugin of a file named `inline<extension>`.
// 2. File: `left` and `right`, each a path or `path@ref`. A side with a ref
//    reads the commit (`GitBlobReader.swift`); a side with no ref reads the
//    work folder (`GitWorkTreeReader.swift`). The change path is the path of
//    the right side, as in Rust: two paths are a content compare, not a
//    rename.
// 3. Automatic: no argument. Each file of the status (`GitStatusReader.swift`)
//    is diffed against HEAD: the old side is the file at HEAD, and the new
//    side is the file in the work folder.
//
// The automatic mode differs from Rust in two points, because the card is
// the contract: it reads the new side from the work folder for a staged file
// too (Rust reads the index first), and a clean tree gives an empty result
// (Rust then diffs HEAD~1 against HEAD). As in Rust, a side that cannot be
// read is no side (`git_show_content` and `read_to_string(...).ok()` give
// `None`): a file that HEAD does not hold is new, and a file that the work
// folder does not hold is gone.
//
// A staged rename reads HEAD at its OLD path, and the changed file carries
// that path as `oldFilePath` (task `^wvmh7vf`). This is a deliberate fix of
// a gap that the Rust source also has: `populate_staged_contents` reads
// `HEAD:<new path>`, which HEAD does not hold, thus each entity of a renamed
// file is `added` there. Here the entities of the file are `moved` (or
// `modified`), not `added`. A rename from a path outside the root is the
// exception: the root rule (git.md § "Decisions", item 8) never reads a path
// outside the root, thus the status gives no old path, the file is new below
// the root, and each of its entities is `added`. A rename from below the root
// to a path outside the root is the opposite case (task `^pt6fyf0`): the
// status gives the old path as a staged removal, the work folder of the root
// does not hold that path, thus each entity of the old file is `deleted`. The
// new path is outside the root, thus no verb reads it.
//
// Each path in a result is relative to the root (git.md § "Decisions",
// item 8). The card names the field `structuralChange`; the field is
// `isStructuralChange`, because a Boolean member reads as an assertion
// (`swift/naming-clarity`). The engine already has a type `DiffResult`, thus
// the result of this verb is `GitDiffResult`.
//
// The content of each change has a cap (``Diff/contentCharacterCap``): the
// result renderer caps the whole return value of a snippet
// (`ResultRendererLimits.defaultReturnValueCharacterLimit`), and one content
// field is a quarter of that cap. A cut field sets `isContentCapped`.
//
// A diff the verb cannot make stays IN BAND, as a `correction` beside no
// change. It is never thrown: a missing argument, a path outside the root, an
// unknown ref, an unknown path, a file that is not text, and a root in no
// repository are each a mistake or a fact the model reads inside the turn.
//
// Each type here is `internal`, and the declaration says so. The host gets
// the verb only through `GitCapability.tools` (`[any Tool]`), the same as the
// other git verbs and the files verbs. No other module uses `Diff`, its
// arguments, or its result, thus no type here is `public`.

import Foundation
import FoundationModels

/// The arguments of `tools.git.diff`: the two texts of the inline mode, the
/// two files of the file mode, or none for the automatic mode.
@Generable
internal struct DiffArguments {

    /// The old side of the file mode: a path, or `path@ref`.
    @Guide(
        description:
            "The old side for file mode: a path, or path@ref to read the file at a ref (for example "
            + "'Sources/App/main.swift@HEAD~1'). Give it with right.")
    var left: String?

    /// The new side of the file mode: a path, or `path@ref`.
    @Guide(
        description:
            "The new side for file mode: a path, or path@ref. A path with no ref reads the work folder. "
            + "Give it with left.")
    var right: String?

    /// The old text of the inline mode.
    @Guide(description: "The old source text for inline mode. Give it with rightText and language.")
    var leftText: String?

    /// The new text of the inline mode.
    @Guide(description: "The new source text for inline mode. Give it with leftText and language.")
    var rightText: String?

    /// The language of the two texts of the inline mode.
    @Guide(
        description:
            "The language of the inline texts, for example 'swift', 'rust', 'typescript', or 'python'. "
            + "An unknown language compares chunks of lines.")
    var language: String?
}

/// The counts of the changes of `tools.git.diff`.
@Generable(description: "the counts of the changes of the diff.")
internal struct DiffSummary {

    /// The number of files with at least one change. The inline mode counts
    /// its one text pair, as in Rust.
    @Guide(description: "The number of files with at least one change.")
    var files: Int

    /// The number of `added` changes.
    @Guide(description: "The number of added entities.")
    var added: Int

    /// The number of `modified` changes.
    @Guide(description: "The number of modified entities.")
    var modified: Int

    /// The number of `deleted` changes.
    @Guide(description: "The number of deleted entities.")
    var deleted: Int

    /// The number of `moved` changes.
    @Guide(description: "The number of entities that moved to another file.")
    var moved: Int

    /// The number of `renamed` changes.
    @Guide(description: "The number of renamed entities.")
    var renamed: Int
}

/// One change to one entity of `tools.git.diff`.
///
/// The fields keep the order of the source: what changed, where, and how,
/// then the content.
@Generable(description: "one change to one entity: a function, a class, a key, or another entity.")
internal struct DiffChange {

    /// What happened: `added`, `modified`, `deleted`, `moved`, or `renamed`.
    @Guide(description: "What happened to the entity: added, modified, deleted, moved, or renamed.")
    var changeType: String

    /// The kind of the entity, for example `function`, or `lines` for
    /// changed lines that no entity holds.
    @Guide(
        description:
            "The kind of the entity, for example function, class, or property; lines for changed lines that no "
            + "entity holds.")
    var entityType: String

    /// The name of the entity.
    @Guide(description: "The name of the entity.")
    var entityName: String

    /// The path of the file that holds the entity, relative to the root.
    @Guide(description: "The path of the file that holds the entity, relative to the session root.")
    var filePath: String

    /// The path of the file that held the entity before a move, or `nil`.
    @Guide(description: "The path of the file that held the entity before a move; null otherwise.")
    var oldFilePath: String?

    /// Whether the structure of a modified entity changed (`true`) or only
    /// its comments or format (`false`), or `nil` when the engine cannot
    /// tell.
    @Guide(
        description:
            "For a modified entity: true when its structure changed, false when only comments or format "
            + "changed; null otherwise.")
    var isStructuralChange: Bool?

    /// The id of the entity.
    @Guide(description: "The id of the entity.")
    var entityId: String

    /// The source text of the entity before the change, cut to the cap, or
    /// `nil` for an added entity.
    @Guide(description: "The source text of the entity before the change; null for an added entity.")
    var beforeContent: String?

    /// The source text of the entity after the change, cut to the cap, or
    /// `nil` for a deleted entity.
    @Guide(description: "The source text of the entity after the change; null for a deleted entity.")
    var afterContent: String?

    /// Whether the cap cut `beforeContent` or `afterContent`.
    @Guide(description: "True when beforeContent or afterContent holds only the first characters of the text.")
    var isContentCapped: Bool
}

/// The result of `tools.git.diff`: the counts and the changes, or the
/// correction that says why there are none.
///
/// `correction` and the changes are exclusive. A diff that answers changes
/// carries no correction, and a correction carries no change and zero counts.
@Generable(description: "the counts and the changes of the diff, or the correction that says why there are none.")
internal struct GitDiffResult {

    /// The counts of the changes.
    @Guide(description: "The counts of the changes.")
    var summary: DiffSummary

    /// The changes, file by file.
    @Guide(description: "The changes, file by file.")
    var changes: [DiffChange]

    /// Why the diff answered no change, or `nil` when the changes stand.
    @Guide(description: "Why the diff answered no change; null when the changes stand.")
    var correction: String?
}

/// One side of the file mode: a path, and the ref to read it at.
internal struct DiffFileSpec: Equatable, Sendable {

    /// The path of the file, absolute or relative to the root.
    let path: String

    /// The ref to read the file at, or `nil` to read the work folder.
    let ref: String?
}

extension DiffFileSpec {

    /// The character between the path and the ref.
    private static let refSeparator: Character = "@"

    /// Parses a `path` or `path@ref` spec: `parse_file_ref` in `diff/mod.rs`.
    ///
    /// The last `@` splits the spec. An `@` at the start of the spec, and an
    /// `@` with no text after it, are part of the path, thus such a spec has
    /// no ref.
    ///
    /// - Parameter spec: The spec, for example `src/main.rs@HEAD~1`.
    init(parsing spec: String) {
        guard let separator = spec.lastIndex(of: Self.refSeparator), separator != spec.startIndex else {
            self.init(path: spec, ref: nil)
            return
        }
        let ref = spec[spec.index(after: separator)...]
        guard !ref.isEmpty else {
            self.init(path: spec, ref: nil)
            return
        }
        self.init(path: String(spec[..<separator]), ref: String(ref))
    }
}

extension Diff {

    // MARK: Bounds

    /// The part of the return-value cap that one content field can use: one
    /// change with both sides then uses at most half of it.
    private static let contentShareDivisor = 4

    /// The largest number of characters in `beforeContent` or
    /// `afterContent`. A longer text gives its first characters and sets
    /// `isContentCapped`.
    static let contentCharacterCap = ResultRendererLimits.defaultReturnValueCharacterLimit / contentShareDivisor

    /// The number of files that the inline mode counts, as in Rust.
    private static let inlineFileCount = 1

    // MARK: Languages

    /// The file name, before the extension, of the two texts of the inline
    /// mode: `inline` in Rust.
    private static let inlineFileName = "inline"

    /// The extension of a language that ``languageExtensions`` does not hold.
    private static let unknownLanguageExtension = ".txt"

    /// The extension of each language name: the table of
    /// `language_to_extension` in `diff/mod.rs`. A key is in lowercase.
    private static let languageExtensions: [String: String] = [
        "rust": ".rs", "rs": ".rs",
        "typescript": ".ts", "ts": ".ts",
        "tsx": ".tsx",
        "javascript": ".js", "js": ".js",
        "jsx": ".jsx",
        "python": ".py", "py": ".py",
        "go": ".go",
        "java": ".java",
        "c": ".c",
        "cpp": ".cpp", "c++": ".cpp", "cxx": ".cpp",
        "ruby": ".rb", "rb": ".rb",
        "csharp": ".cs", "c#": ".cs", "cs": ".cs",
        "php": ".php",
        "fortran": ".f90", "f90": ".f90",
        "swift": ".swift",
        "elixir": ".ex", "ex": ".ex",
        "bash": ".sh", "sh": ".sh",
        "json": ".json",
        "yaml": ".yaml", "yml": ".yaml",
        "toml": ".toml",
        "csv": ".csv",
        "markdown": ".md", "md": ".md",
        "vue": ".vue",
    ]

    /// The extension of a language name: `language_to_extension` in
    /// `diff/mod.rs`.
    ///
    /// The name is case-insensitive. An unknown name gives `.txt`, which the
    /// fallback plugin reads.
    ///
    /// - Parameter language: The language name, for example `rust`.
    /// - Returns: The extension with its leading dot.
    static func fileExtension(forLanguage language: String) -> String {
        languageExtensions[language.lowercased()] ?? unknownLanguageExtension
    }

    // MARK: Execution

    /// Runs the mode that the arguments select, or answers the correction
    /// that says why there is no diff.
    ///
    /// The inline texts select the inline mode, else the file sides select
    /// the file mode, else the automatic mode runs, in the order of
    /// `execute_diff` in `changes/mod.rs`. Each recoverable failure comes
    /// back as the `correction` field of the result; nothing here throws.
    ///
    /// - Parameter arguments: The texts, the files, or none.
    /// - Returns: The counts and the changes, or the correction.
    internal func call(arguments: DiffArguments) async throws -> GitDiffResult {
        switch DiffMode(arguments) {
        case .inline:
            Self.inlineDiff(arguments)
        case .file:
            fileDiff(arguments)
        case .automatic:
            automaticDiff()
        }
    }

    // MARK: Modes

    /// The inline mode: `execute_inline_diff` in `diff/mod.rs`.
    ///
    /// - Parameter arguments: The arguments, with at least one inline text.
    /// - Returns: The diff of the two texts, or the correction that names the
    ///   missing argument.
    private static func inlineDiff(_ arguments: DiffArguments) -> GitDiffResult {
        guard let leftText = arguments.leftText else { return corrective(missingInlineArgumentMessage("leftText")) }
        guard let rightText = arguments.rightText else { return corrective(missingInlineArgumentMessage("rightText")) }
        guard let language = arguments.language else { return corrective(missingInlineArgumentMessage("language")) }
        let change = SemanticFileChange(
            filePath: inlineFileName + fileExtension(forLanguage: language), status: .modified, oldFilePath: nil,
            beforeContent: leftText, afterContent: rightText)
        return result(of: semanticDiff(of: [change]), fileCount: inlineFileCount)
    }

    /// The file mode: `execute_file_diff` in `diff/mod.rs`.
    ///
    /// - Parameter arguments: The arguments, with at least one file side.
    /// - Returns: The diff of the two files, or the correction.
    private func fileDiff(_ arguments: DiffArguments) -> GitDiffResult {
        guard let left = arguments.left else { return Self.corrective(Self.missingFileArgumentMessage("left")) }
        guard let right = arguments.right else { return Self.corrective(Self.missingFileArgumentMessage("right")) }
        return file(DiffFileSpec(parsing: left)).resolve(corrective: Self.corrective) { before in
            file(DiffFileSpec(parsing: right)).resolve(corrective: Self.corrective) { after in
                let change = SemanticFileChange(
                    filePath: after.path, status: .modified, oldFilePath: nil, beforeContent: before.text,
                    afterContent: after.text)
                let diff = Self.semanticDiff(of: [change])
                return Self.result(of: diff, fileCount: diff.fileCount)
            }
        }
    }

    /// The automatic mode: each file of the status, against HEAD.
    ///
    /// - Returns: The diff of the files of the status, or the correction for
    ///   a root in no repository and for a status that cannot be read.
    private func automaticDiff() -> GitDiffResult {
        context.status().resolve(corrective: Self.corrective) { status in
            let files = status.allFiles.map { path in
                automaticChange(ofFile: path, renamedFrom: status.oldPathsOfRenamedFiles[path])
            }
            let diff = Self.semanticDiff(of: files)
            return Self.result(of: diff, fileCount: diff.fileCount)
        }
    }

    // MARK: Steps

    /// Reads one side of the file mode.
    ///
    /// - Parameter spec: The side.
    /// - Returns: The file at the ref of the side, or in the work folder when
    ///   the side has no ref; or the correction.
    private func file(_ spec: DiffFileSpec) -> Result<GitBlob, CorrectiveRejection> {
        guard let ref = spec.ref else { return context.workTreeFile(path: spec.path) }
        return context.blob(path: spec.path, ref: ref)
    }

    /// The changed file of one file of the status: the file at HEAD against
    /// the file in the work folder.
    ///
    /// A staged rename reads HEAD at its old path, and the engine reads the
    /// old entities at that path. A side that cannot be read is no side, as
    /// in Rust: the file is new, gone, or (for a binary file) has no entity.
    ///
    /// - Parameters:
    ///   - path: The path of the file, relative to the root.
    ///   - oldPath: The path of the file at HEAD for a staged rename,
    ///     relative to the root, or `nil` when the file has no rename below
    ///     the root.
    /// - Returns: The changed file.
    private func automaticChange(ofFile path: String, renamedFrom oldPath: String?) -> SemanticFileChange {
        let before = try? context.blob(path: oldPath ?? path, ref: GitContext.defaultRef).get().text
        let after = try? context.workTreeFile(path: path).get().text
        return SemanticFileChange(
            filePath: path, status: Self.fileStatus(before: before, after: after, isRenamed: oldPath != nil),
            oldFilePath: oldPath, beforeContent: before, afterContent: after)
    }

    /// What happened to a file, from the sides that it has.
    ///
    /// - Parameters:
    ///   - before: The old text, or `nil`.
    ///   - after: The new text, or `nil`.
    ///   - isRenamed: Whether the old text comes from another path.
    /// - Returns: `added` with no old text, `deleted` with no new text, else
    ///   `renamed` for a rename and `modified` for a file at one path.
    private static func fileStatus(before: String?, after: String?, isRenamed: Bool) -> FileStatus {
        switch (before, after) {
        case (.none, _):
            .added
        case (.some, .none):
            .deleted
        case (.some, .some):
            isRenamed ? .renamed : .modified
        }
    }

    /// The entity-level diff of some changed files, with the default
    /// plugins, and no commit sha and no author, as in Rust.
    ///
    /// Each mode also reports the changed lines that no entity holds (task
    /// `^8fd3kgk`): a comment, an import, or another line at the top level
    /// is in no entity, and a diff that drops its change hides an edit.
    ///
    /// - Parameter files: The changed files.
    /// - Returns: The diff of the engine.
    private static func semanticDiff(of files: [SemanticFileChange]) -> DiffResult {
        SemanticDiffer.computeSemanticDiff(
            fileChanges: files, registry: ParserRegistry.makeDefault(), commitSHA: nil, author: nil,
            reportsUncoveredLines: true)
    }

    /// The result of a diff: `diff_result_to_response` in `diff/mod.rs`.
    ///
    /// - Parameters:
    ///   - diff: The diff of the engine.
    ///   - fileCount: The number of files that the summary names.
    /// - Returns: The result with its counts and its changes.
    private static func result(of diff: DiffResult, fileCount: Int) -> GitDiffResult {
        GitDiffResult(
            summary: DiffSummary(
                files: fileCount, added: diff.addedCount, modified: diff.modifiedCount, deleted: diff.deletedCount,
                moved: diff.movedCount, renamed: diff.renamedCount),
            changes: diff.changes.map(Self.change(of:)),
            correction: nil)
    }

    /// The row of one change, with each content cut to the cap:
    /// `to_change_entry` in `diff/mod.rs`.
    ///
    /// - Parameter change: The change of the engine.
    /// - Returns: The row.
    private static func change(of change: SemanticChange) -> DiffChange {
        let before = cappedContent(change.beforeContent)
        let after = cappedContent(change.afterContent)
        return DiffChange(
            changeType: change.changeType.rawValue, entityType: change.entityType, entityName: change.entityName,
            filePath: change.filePath, oldFilePath: change.oldFilePath, isStructuralChange: change.isStructuralChange,
            entityId: change.entityID, beforeContent: before.text, afterContent: after.text,
            isContentCapped: before.isCapped || after.isCapped)
    }

    /// A content cut to ``contentCharacterCap`` characters.
    ///
    /// The cut counts `Character`s, the same as the result renderer, thus it
    /// never splits a grapheme cluster.
    ///
    /// - Parameter content: The content, or `nil`.
    /// - Returns: The content, cut when it is longer than the cap, and
    ///   whether the cap cut it.
    private static func cappedContent(_ content: String?) -> (text: String?, isCapped: Bool) {
        guard let content, content.count > contentCharacterCap else { return (content, false) }
        return (String(content.prefix(contentCharacterCap)), true)
    }

    // MARK: Corrective results

    /// The correction for a missing argument of the inline mode.
    ///
    /// - Parameter name: The name of the missing argument.
    /// - Returns: The correction, which names the argument and the three
    ///   arguments of the mode.
    private static func missingInlineArgumentMessage(_ name: String) -> String {
        "Inline mode needs the argument `\(name)`: give `leftText`, `rightText`, and `language` together."
    }

    /// The correction for a missing argument of the file mode.
    ///
    /// - Parameter name: The name of the missing argument.
    /// - Returns: The correction, which names the argument and the two
    ///   arguments of the mode.
    private static func missingFileArgumentMessage(_ name: String) -> String {
        "File mode needs the argument `\(name)`: give `left` and `right` together, each a path or path@ref."
    }

    /// A result that carries only a correction: no change and zero counts.
    ///
    /// - Parameter message: The correction the model reads and acts on.
    /// - Returns: The corrective ``GitDiffResult``.
    private static func corrective(_ message: String) -> GitDiffResult {
        GitDiffResult(
            summary: DiffSummary(files: 0, added: 0, modified: 0, deleted: 0, moved: 0, renamed: 0), changes: [],
            correction: message)
    }
}

/// The mode of one call of `tools.git.diff`, from its arguments.
private enum DiffMode {

    /// Two texts and a language.
    case inline

    /// Two files, each a path or `path@ref`.
    case file

    /// Each changed file of the status, against HEAD.
    case automatic

    /// The mode that the arguments select, in the order of `execute_diff`
    /// in `changes/mod.rs`: an inline text selects the inline mode, else a
    /// file side selects the file mode, else the automatic mode runs.
    ///
    /// - Parameter arguments: The arguments of the call.
    init(_ arguments: DiffArguments) {
        if arguments.leftText != nil || arguments.rightText != nil {
            self = .inline
        } else if arguments.left != nil || arguments.right != nil {
            self = .file
        } else {
            self = .automatic
        }
    }
}

/// Gives the entity-level diff of two texts, of two files, or of the changed
/// files of the work folder.
///
/// ```swift
/// // In a snippet the model writes:
/// //   const diff = await tools.git.diff({ left: "Sources/App/main.swift@HEAD~1", right: "Sources/App/main.swift" });
/// ```
///
/// The contract: the counts of the changes and one row for each changed
/// entity (function, class, key, or other entity) and for each run of
/// changed lines that no entity holds (``UncoveredLines``), with its kind,
/// its name, its file, and its text before and after, each text cut to
/// ``contentCharacterCap`` characters with an honest `isContentCapped` flag.
/// Each path is relative to the root and bounded through the session's
/// ``PathGuard``. A missing argument, a path outside the root, an unknown
/// ref, an unknown path, a file that is not text, and a root in no
/// repository each come back as a `correction`, not as an error.
internal struct Diff: Tool {

    /// The verb this tool renders as, which the git noun stands in front of:
    /// `tools.git.diff`.
    let name = "diff"

    /// The usage instructions, as the model reads them.
    let description = """
        diff gives a semantic diff at the entity level (functions, classes, keys, and other \
        entities), not a line diff, in one of three modes. A changed line that no entity holds \
        (a comment, an import, or other text at the top level) is a change of the entityType \
        \(UncoveredLines.entityType), named by its line numbers. Inline: give leftText, rightText, and \
        language to compare two texts. File: give left and right, each a path or path@ref (for \
        example 'a.swift@HEAD~1'); a path with no ref reads the work folder. Automatic: give no \
        argument to diff each changed file of the work folder against HEAD. summary counts the \
        changes; each change names the changeType, the entity, its file, and its text before and \
        after. A text holds at most \(Diff.contentCharacterCap) characters; when isContentCapped \
        is true, the text holds only its first characters. A missing argument, a path outside the \
        session root, an unknown ref, an unknown path, a binary file, and a root in no git \
        repository each come back as a correction rather than as an error — read it, correct the \
        call, and ask again.
        """

    /// The session context this verb reads against, which the git capability
    /// owns.
    ///
    /// The compiler-synthesized memberwise initializer takes this one
    /// property, thus the capability makes the verb as `Diff(context:)`.
    let context: GitContext
}
