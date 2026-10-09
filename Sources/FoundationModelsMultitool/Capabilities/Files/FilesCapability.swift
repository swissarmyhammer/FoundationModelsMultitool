// `FilesCapability` — the `files` noun, and the seven verbs that render under
// it.
//
// eventplan.md § "Registration of capabilities: noun/verb": "Built-in
// capabilities and user capabilities are the same thing." Thus this type,
// like `ShellCapability` beside it, holds no logic of its own. It names the
// noun one time, and it composes the seven verbs that were already written as
// plain `FoundationModels.Tool` conformers.
//
// **The capability is what makes the seven verbs one session.** Each verb's own
// doc comment promises that "the context it reads against is the context the
// files capability owns", and this type is where that promise is kept: one
// `FileContext` reaches every verb, thus `tools.files.read` reads what
// `tools.files.write` just wrote, and the mutating verbs record into one
// change journal.
//
// **The capability is off by default**, and nothing here makes it otherwise.
// eventplan.md § "The capability contract": "The modules are opt-in ... They
// are off by default. This keeps the permission posture at the registry
// boundary." A host that never calls `MultiTool.Builder.withFiles(root:)`
// renders no `tools.files` namespace at all.
//
// **The boundary of the session is the initializer's whole configuration.**
// The `root` and the `additionalRoots` become the `PathGuard` workspace
// boundaries, `readOnly` gates the mutating verbs, `allowSymlinks` selects
// whether the guard resolves a symlink or rejects it, `recordsChanges`
// turns the change journal on, and `excludePatterns` names the files that
// each search walk skips — see `FileContext`, which owns each of those
// decisions. Multitool gives no default exclude pattern: the host knows
// which folders are its own (the ACP agent gives `.acp-agent/`).

import Foundation
import FoundationModels

/// The files capability: one noun, and the seven verbs of the file session.
///
/// ```swift
/// let surface = try MultiTool.Builder()
///     .withFiles(root: workspaceURL)      // tools.files.read, .write, .makeDirectory,
///     .build()                            //   .edit, .patch, .glob, .grep
/// ```
///
/// `MultiTool.Builder.withFiles(root:additionalRoots:readOnly:allowSymlinks:recordsChanges:excludePatterns:)`
/// is the short form of `withCapability(FilesCapability(...))`, and it takes
/// the same six arguments. Register this type directly where a host builds
/// the capability once and hands it on.
///
/// The seven verbs render in the order they are listed:
///
/// | Path | What it does |
/// |---|---|
/// | `tools.files.read` | Reads a file's lines, whole or by window. |
/// | `tools.files.write` | Writes one file's whole content atomically. |
/// | `tools.files.makeDirectory` | Makes a directory, with its absent parent folders by default. |
/// | `tools.files.edit` | Replaces anchored spans of one file. |
/// | `tools.files.patch` | Applies a multi-file patch envelope. |
/// | `tools.files.glob` | Finds files by name pattern. |
/// | `tools.files.grep` | Searches file content by regular expression. |
public struct FilesCapability: Capability {

    /// The one namespace each verb of this capability renders under — the
    /// first segment of `tools.files.<verb>`.
    ///
    /// The capability OWNS this noun: `MultiTool.Builder.withCapability(_:)`
    /// claims the whole `tools.files` namespace, so a second registration
    /// under it fails loudly at `buildRegistry()` rather than quietly at
    /// dispatch.
    public let noun = "files"

    /// The seven verbs of the file session, in the order they render.
    ///
    /// Each one supplies its own second segment through `Tool.name`, so this
    /// array and the noun above are the whole of what the surface needs.
    public let tools: [any Tool]

    /// Makes the files capability over one session context.
    ///
    /// The initializer builds one `FileContext` from its six arguments and
    /// hands that context to each verb, which is what makes the seven verbs one
    /// session. It never throws: the context validates nothing at
    /// construction, and every path question is answered per call, as a
    /// correction in the verb's own result.
    ///
    /// - Parameters:
    ///   - root: The session working directory: the boundary every path is
    ///     confined to, and the base a relative path resolves against.
    ///   - additionalRoots: Extra workspace boundaries paths may also resolve
    ///     within, alongside `root`. The default, empty, confines the session
    ///     to `root` alone.
    ///   - readOnly: Whether the session forbids the mutating verbs. The
    ///     default, `false`, lets them run.
    ///   - allowSymlinks: Whether the path guard resolves symlinks rather
    ///     than rejecting them. The default, `false`, is the secure default.
    ///   - recordsChanges: Whether the mutating verbs record what they
    ///     changed. When `true`, each `write`, `edit` and `patch` call that
    ///     lands delivers its changes to the session as one `.progress`
    ///     `OperationEvent` whose `detail` is the `fileChanges` envelope; a
    ///     host reads it with `FileChangeSet.init(operationEventDetail:)`.
    ///     A verb called with no session keeps them in the change journal
    ///     for a drain. The default, `false`, records nothing.
    ///   - excludePatterns: The host exclude patterns, in gitignore syntax
    ///     (for example `.acp-agent/`, `*.log`, `!keep.log`), relative to
    ///     `root`. `tools.files.glob` and `tools.files.grep` skip each file
    ///     that the patterns exclude when they walk a folder tree, the same
    ///     way they skip a file that `.gitignore` ignores. A read, a write,
    ///     an edit, a patch, or a grep of one explicit file does not change.
    ///     The patterns stay on when a call sets `respectGitIgnore` to
    ///     `false`: the model sets that argument, but the patterns are the
    ///     rule of the host, and the model must not turn them off. Otherwise
    ///     one search with `respectGitIgnore: false` finds the hidden files
    ///     again. The default, empty, excludes nothing.
    public init(
        root: URL,
        additionalRoots: Set<URL> = [],
        readOnly: Bool = false,
        allowSymlinks: Bool = false,
        recordsChanges: Bool = false,
        excludePatterns: [String] = []
    ) {
        // The one context of the session. Every verb holds it, which is why
        // a read sees a write and the journal is one journal.
        let context = FileContext(
            root: root,
            additionalRoots: additionalRoots,
            readOnly: readOnly,
            allowSymlinks: allowSymlinks,
            recordsChanges: recordsChanges,
            excludePatterns: excludePatterns)

        self.tools = [
            Read(context: context),
            Write(context: context),
            MakeDirectory(context: context),
            Edit(context: context),
            Patch(context: context),
            Glob(context: context),
            Grep(context: context),
        ]
    }
}
