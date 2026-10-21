// `OperationToolCapability` — one operation tool of the host, under a noun
// that the host gives.
//
// `MultiTool.Builder.withOperationTool(noun:tool:)` records this type. The
// host gives an `OperationDescribing` tool, and Multitool does not know its
// concrete type: FoundationModelsACPAgent depends on this package, so this
// package cannot import the `SettingsTool` of ACPAgent (MT-9, D100 (f)).
//
// The type adds no behavior. It is a `Capability` so that the noun is owned
// (a second registration under it fails at `buildRegistry()`), and so that the
// registry mounts the tool through the same path as the tools of Multitool:
// `RegistrySource` changes the tool into one `OperationVerbTool` for each
// operation. Thus a snippet calls each operation as `tools.<noun>.<verb>`,
// and a call goes through the same `runCode` path as a call of a built-in verb.

import FoundationModels
import FoundationModelsExtras

/// The capability that holds one operation tool of the host under the noun
/// that the host gives.
struct OperationToolCapability: Capability {
    /// The noun that the host gives. Each operation of ``tool`` renders under it.
    let noun: String

    /// The operation tool of the host.
    let tool: any OperationDescribing

    /// The one tool of this capability. The registry mounts one verb for
    /// each operation of it.
    ///
    /// The `Capability` default of `graphQLEndpoints` reads this list, so it
    /// gives the endpoints of ``tool`` itself when it is a
    /// `GraphQLEndpointTool`, as `SettingsTool` is. The registry reads them
    /// before it replaces ``tool`` with one `OperationVerbTool` for each
    /// operation, because no verb is a `GraphQLEndpointTool`.
    var tools: [any Tool] { [tool] }
}
