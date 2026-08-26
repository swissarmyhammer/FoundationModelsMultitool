// `FilesCapability` — the `files` noun, and the six verbs that render under
// it.
//
// eventplan.md § "Registration of capabilities: noun/verb": "Built-in
// capabilities and user capabilities are the same thing." Thus this type,
// like `ShellCapability` beside it, holds no logic of its own. It names the
// noun one time, and it composes the six verbs that were already written as
// plain `FoundationModels.Tool` conformers.
//
// **The capability is what makes the six verbs one session.** Each verb's own
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
// whether the guard resolves a symlink or rejects it, and `recordsChanges`
// turns the change journal on — see `FileContext`, which owns each of those
// decisions.

import Foundation
import FoundationModels

/// The files capability: one noun, and the six verbs of the file session.
///
/// ```swift
/// let surface = try MultiTool.Builder()
///     .withFiles(root: workspaceURL)      // tools.files.read, .write, .edit,
///     .build()                            //   .patch, .glob, .grep
/// ```
///
/// `MultiTool.Builder.withFiles(root:additionalRoots:readOnly:allowSymlinks:recordsChanges:)`
/// is the short form of `withCapability(FilesCapability(...))`, and it takes
/// the same five arguments. Register this type directly where a host builds
/// the capability once and hands it on.
///
/// The six verbs render in the order they are listed:
///
/// | Path | What it does |
/// |---|---|
/// | `tools.files.read` | Reads a file's lines, whole or by window. |
/// | `tools.files.write` | Writes one file's whole content atomically. |
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

    /// The six verbs of the file session, in the order they render.
    ///
    /// Each one supplies its own second segment through `Tool.name`, so this
    /// array and the noun above are the whole of what the surface needs.
    public let tools: [any Tool]

    /// Makes the files capability over one session context.
    ///
    /// The initializer builds one `FileContext` from its five arguments and
    /// hands that context to each verb, which is what makes the six verbs one
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
    ///     changed into the session's change journal. The default, `false`,
    ///     records nothing.
    public init(
        root: URL,
        additionalRoots: Set<URL> = [],
        readOnly: Bool = false,
        allowSymlinks: Bool = false,
        recordsChanges: Bool = false
    ) {
        // The one context of the session. Every verb holds it, which is why
        // a read sees a write and the journal is one journal.
        let context = FileContext(
            root: root,
            additionalRoots: additionalRoots,
            readOnly: readOnly,
            allowSymlinks: allowSymlinks,
            recordsChanges: recordsChanges)

        self.tools = [
            Read(context: context),
            Write(context: context),
            Edit(context: context),
            Patch(context: context),
            Glob(context: context),
            Grep(context: context),
        ]
    }
}
