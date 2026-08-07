import FoundationModels
import FoundationModelsRouter

// MARK: - Fork composition (eventplan.md § "MultiTool is a host and an emitter")
//
// A host derives each child session's tool instance by conformance cast —
// `((tool as? any ForkableTool)?.forked() ?? tool)` — before wrapping the
// result in that session's own layers. Declaring the conformance here is how
// `runCode` answers that question deliberately rather than by omission.

/// `runCode` forks by identity.
///
/// It inherits `ForkableTool`'s blanket `forked()`, which returns `self`, and
/// declares no `forked()` of its own. The protocol documents that default as
/// the correct one for a value-semantics tool, and `MultiTool` is a `struct`.
/// What makes it correct here in substance, rather than only in form, is where
/// this tool keeps its state:
///
/// - **Nothing derived at `init` can drift.** `registry`, and the
///   `hostFunctions`, `liveTools`, and `preamble` precomputed from it, are
///   `let`s that depend only on the registry, which never changes. A fork has
///   nothing to re-derive, and two sessions reading the same catalog is the
///   point of sharing a registry, not a leak.
/// - **Per-run state never lives on the tool.** Everything one invocation's
///   inner `tools.*` calls need is captured into a `RunBinding` at the top of
///   `call(arguments:)`, from the ambient `ToolContext` that invocation's own
///   host bound around it. So a single shared instance already serves any
///   number of sessions concurrently without cross-routing (see
///   `RunBinding`), which is exactly the property a fork would otherwise have
///   to buy by copying.
/// - **The two reference-typed members are shared on purpose.** A fork keeps
///   the one `interpreter`, and `liveContexts` counts the live contexts of
///   *that* interpreter. Handing a fork a fresh counter would let every fork
///   open a full `configuration.liveContextLimit` worth of suspended contexts
///   on the same sandbox, which is the pile-up the cap exists to prevent.
///
/// A real `forked()` would therefore have to reconstruct immutable state that
/// cannot go stale, and split a counter whose whole job is to be shared.
extension MultiTool: ForkableTool {}
