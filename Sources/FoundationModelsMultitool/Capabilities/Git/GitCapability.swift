// `GitCapability` — the `git` noun, and the verbs that render under it.
//
// git.md § "Proposed shape": a new capability with `noun = "git"`, built the
// same way as `FilesCapability` beside it. The type holds no logic of its
// own. It names the noun one time, it makes the one `GitContext` of the
// session, and it composes the verbs over that context.
//
// **Each verb task adds its verb.** Each verb task of git.md § "Proposed order
// of the tasks" (`status`, `branches`, `changes`, `show`, `log`, `blame`,
// `diff`) adds its verb to ``GitCapability/tools``, over ``context``. The
// verbs so far are `blame` (`Blame.swift`), `show` (`Show.swift`), `log`
// (`Log.swift`), `status` (`Status.swift`), and `branches` (`Branches.swift`).
//
// **The capability is off by default**, and nothing here makes it otherwise.
// eventplan.md § "The capability contract": "The modules are opt-in ... They
// are off by default." A host that never calls
// `MultiTool.Builder.withGit(root:)` renders no `tools.git` namespace at all.
//
// **The capability is read-only** (git.md § "Decisions", item 2). No verb
// changes the repository. The model changes files with `tools.files.*` and
// runs other git commands with `tools.shell.*`, when the host mounts those
// capabilities.

import Foundation
import FoundationModels

/// The git capability: one noun, and the read verbs of the repository that
/// contains the root.
///
/// ```swift
/// let surface = try MultiTool.Builder()
///     .withGit(root: workspaceURL)        // tools.git.*
///     .build()
/// ```
///
/// `MultiTool.Builder.withGit(root:)` is the short form of
/// `withCapability(GitCapability(root:))`. Register this type directly where a
/// host builds the capability one time and hands it on.
public struct GitCapability: Capability {

    /// The one namespace each verb of this capability renders under — the
    /// first segment of `tools.git.<verb>`.
    ///
    /// The capability OWNS this noun: `MultiTool.Builder.withCapability(_:)`
    /// claims the whole `tools.git` namespace, so a second registration
    /// under it fails loudly at `buildRegistry()` rather than quietly at
    /// dispatch. The claim holds with no verb, too.
    public let noun = "git"

    /// The verbs of the git session, in the order they render. Each verb task
    /// adds its verb here.
    ///
    /// Each one supplies its own second segment through `Tool.name`, so this
    /// array and the noun above are the whole of what the surface needs.
    public let tools: [any Tool]

    /// The one context of the session: the root, the path guard, and the
    /// repository that contains the root. Each verb gets this context.
    let context: GitContext

    /// Makes the git capability over one session root.
    ///
    /// The initializer builds one `GitContext` and hands it to each verb. It
    /// never throws: a root in no repository is not an error here, and each
    /// verb answers it as a correction in its own result.
    ///
    /// - Parameter root: The session working directory: the boundary every
    ///   path is confined to, and the base a relative path resolves against.
    ///   The root can be a subfolder of the repository.
    public init(root: URL) {
        context = GitContext(root: root)
        tools = [
            Blame(context: context), Show(context: context), Log(context: context), Status(context: context),
            Branches(context: context),
        ]
    }
}
