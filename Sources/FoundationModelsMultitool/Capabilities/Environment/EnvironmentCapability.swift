// `EnvironmentCapability` — the `environment` noun, and the verbs that render
// under it.
//
// The capability is built the same way as `GitCapability`. The type holds no
// logic of its own. It names the noun one time, it holds the one
// `EnvironmentContext` of the session, and it composes the verbs over that
// context.
//
// **Each verb task adds its verb.** The verbs so far are `variables`
// (`Variables.swift`).
//
// **The capability is off by default**, and nothing here makes it otherwise.
// eventplan.md § "The capability contract": "The modules are opt-in ... They
// are off by default." A host that never calls
// `MultiTool.Builder.withEnvironment()` renders no `tools.environment`
// namespace at all.
//
// **The capability is read-only.** No verb changes the environment of the
// process.

import Foundation
import FoundationModels

/// The environment capability: one noun, and the read verbs of the process
/// that runs the session.
///
/// ```swift
/// let surface = try MultiTool.Builder()
///     .withEnvironment()        // tools.environment.*
///     .build()
/// ```
///
/// `MultiTool.Builder.withEnvironment()` is the short form of
/// `withCapability(EnvironmentCapability())`. Register this type directly
/// where a host builds the capability one time and hands it on.
public struct EnvironmentCapability: Capability {

    /// The one namespace each verb of this capability renders under — the
    /// first segment of `tools.environment.<verb>`.
    ///
    /// The capability OWNS this noun: `MultiTool.Builder.withCapability(_:)`
    /// claims the whole `tools.environment` namespace, so a second
    /// registration under it fails loudly at `buildRegistry()` rather than
    /// quietly at dispatch.
    public let noun = "environment"

    /// The verbs of the environment capability, in the order they render.
    /// Each verb task adds its verb here.
    ///
    /// Each one supplies its own second segment through `Tool.name`, so this
    /// array and the noun above are the whole of what the surface needs.
    public let tools: [any Tool]

    /// The one context of the session: the inputs that each verb reads.
    let context: EnvironmentContext

    /// Makes the environment capability over the real process: its
    /// environment variables, its clock, and its time zone.
    public init() {
        self.init(context: EnvironmentContext())
    }

    /// Makes the environment capability over a context that the caller
    /// gives. A test uses this initializer to inject each input.
    ///
    /// - Parameter context: The inputs that each verb reads.
    init(context: EnvironmentContext) {
        self.context = context
        tools = [Variables(context: context)]
    }
}
