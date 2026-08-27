// `MultiTool.RegistrySource` — the recorded configuration of a
// `MultiTool.Builder`, and the value that gives a `Registry` from it as many
// times as a host asks.
//
// eventplan.md § "Consolidation of the siblings": "A late server, a
// reconnect, or an MCP `tools/list_changed` starts a full rebuild. MultiTool
// renders the new registry complete at the side." The builder records what
// the host registered; this value holds that record after `build()`, so a
// host keeps this value and not the builder. `buildRegistry()` renders the
// record as it stands. `rebuildRegistry()` reads the catalog of each MCP
// server again first, and then renders. Neither touches a `Registry` that
// exists: "The surface never changes in place."

import FoundationModels

extension MultiTool {
    /// The recorded registrations of a `MultiTool.Builder`, from which a
    /// `Registry` renders one time or many times.
    ///
    /// A value, and `Sendable`: a session keeps it after `build()` and calls
    /// ``rebuildRegistry()`` on it when a server's catalog moves. The builder
    /// itself is a reference type that the fluent chain consumes, so a host
    /// keeps this value instead.
    ///
    /// ```swift
    /// let builder = try await MultiTool.Builder()
    ///     .withShell()
    ///     .withMCP(servers: [github])
    /// let first = try builder.buildRegistry()
    /// let source = builder.registrySource
    ///
    /// // later, after a tools/list_changed re-list of `github`:
    /// let second = try await source.rebuildRegistry()   // `first` is unchanged
    /// ```
    public struct RegistrySource: Sendable {
        /// One registration a builder method recorded, in the exact order the
        /// registration methods were called.
        enum Registration: Sendable {
            /// A standalone tool, destined for a flat `tools.<name>` entry.
            case standalone(any Tool)

            /// A tool under a named group, destined for `tools.<group>.<name>`.
            /// A noun and a group are the same segment, so `register(noun:tool:)`
            /// and `addGroup(named:_:)` both record this case.
            case grouped(group: String, tool: any Tool)

            /// A capability, which claims its noun whole and gives every tool
            /// under it. Kept as the capability, and not as its tools, so a
            /// rebuild can ask an `MCPCapability` for its current tools.
            case capability(any Capability)
        }

        /// One tool queued for rendering, after the capabilities of
        /// ``registrations`` are expanded into their tools.
        private enum PendingTool {
            case standalone(any Tool)
            case grouped(group: String, tool: any Tool)
        }

        /// One capability's claim on one noun — the fact that tells an entry
        /// the capability itself queued from an entry another registration
        /// put under the same noun.
        ///
        /// A capability and `addGroup(named:_:)` both queue the same
        /// `.grouped` item, so the queue alone cannot say who registered what.
        /// The claim answers that with the half-open range of queue positions
        /// the capability's own tools fill, and it names the claimant so the
        /// failure can too.
        private struct CapabilityClaim {
            /// The noun this capability owns.
            let noun: String

            /// The name of the capability's own type. A capability holds a
            /// noun and its tools and nothing else, so its type is the only
            /// identity an error message can give it.
            let claimant: String

            /// The half-open range of queue positions holding this
            /// capability's own tools. Expansion queues them together, so one
            /// range covers all of them.
            let toolPositions: Range<Int>
        }

        /// The queue of tools and the claims of the capabilities, which
        /// ``expanded()`` derives from ``registrations``.
        private struct Expansion {
            /// Every tool to render, in registration order.
            let pending: [PendingTool]

            /// Every claim a capability made, in registration order.
            let claims: [CapabilityClaim]
        }

        /// Every registration so far, in registration order.
        var registrations: [Registration] = []

        /// Creates an empty source.
        init() {}

        // MARK: - Building

        /// Renders every registration and assembles the result into a
        /// `MultiTool.Registry`, which pairs the rendered `APISurface` with
        /// the live `any Tool` instances a `MultiTool` dispatches `tools.*`
        /// calls to.
        ///
        /// Validates the namespacing rule: every standalone tool's name is
        /// unique among standalone tools; every tool's name is unique within
        /// its own group; and no standalone tool's name collides with a
        /// group's name, which would make `tools.<name>` ambiguous between a
        /// function and a namespace.
        ///
        /// Validates one rule more: a noun a capability claims is owned whole,
        /// so nothing else may register under it.
        ///
        /// - Returns: the rendered catalog paired with its live tool
        ///   instances, in `.directMode() == false` (both `runCode` and
        ///   `searchTools` surfaced).
        /// - Throws: `ToolAPIRendererError`, propagated unchanged and never
        ///   wrapped — the same posture `ToolInvoker` takes toward a tool's
        ///   own thrown error — when a queued tool cannot be fully rendered.
        ///   A tool that cannot be fully rendered fails loudly here rather
        ///   than emit a lossy stub. `MultiToolBuilderError` when a group
        ///   name isn't a legal TypeScript identifier, when two tools would
        ///   collide at the same top-level snippet call path, or when
        ///   anything other than the owning capability registers under a noun
        ///   a capability claimed.
        public func buildRegistry() throws -> MultiTool.Registry {
            let expansion = expanded()
            var entries: [APISurface.Entry] = []
            var toolsByPath: [String: any Tool] = [:]
            var standaloneNames: Set<String> = []
            var groupNames: Set<String> = []
            var namesByGroup: [String: Set<String>] = [:]

            for item in expansion.pending {
                switch item {
                case .standalone(let tool):
                    let descriptor = try ToolAPIRenderer.render(tool)
                    guard standaloneNames.insert(descriptor.name).inserted else {
                        throw MultiToolBuilderError(
                            kind: .duplicateName,
                            name: descriptor.name,
                            message: "Duplicate standalone tool name \"\(descriptor.name)\"; every "
                                + "standalone tool renders flat at tools.\(descriptor.name), so its "
                                + "name must be unique. Wrap one of them in a named group via "
                                + "addGroup(named:_:) to disambiguate."
                        )
                    }
                    entries.append(APISurface.Entry(path: descriptor.name, group: nil, descriptor: descriptor))
                    toolsByPath[descriptor.name] = tool

                case .grouped(let group, let tool):
                    guard ToolAPIRenderer.isLegalTSIdentifier(group) else {
                        throw MultiToolBuilderError(
                            kind: .illegalGroupName,
                            name: group,
                            message: "Group name \"\(group)\" is not a legal TypeScript identifier "
                                + "(must match ^[A-Za-z_$][A-Za-z0-9_$]*$); refusing to emit a "
                                + "tools.\(group).<name> namespace for it."
                        )
                    }
                    let descriptor = try ToolAPIRenderer.render(tool)
                    var namesInGroup = namesByGroup[group] ?? []
                    guard namesInGroup.insert(descriptor.name).inserted else {
                        throw MultiToolBuilderError(
                            kind: .duplicateName,
                            name: descriptor.name,
                            message: "Duplicate tool name \"\(descriptor.name)\" within group "
                                + "\"\(group)\"; every tool in a group renders at "
                                + "tools.\(group).\(descriptor.name), so its name must be unique "
                                + "within that group."
                        )
                    }
                    namesByGroup[group] = namesInGroup
                    groupNames.insert(group)
                    let path = "\(group).\(descriptor.name)"
                    entries.append(APISurface.Entry(path: path, group: group, descriptor: descriptor))
                    toolsByPath[path] = tool
                }
            }

            try Self.validateNounOwnership(of: expansion, standaloneNames: standaloneNames)

            if let collision = standaloneNames.intersection(groupNames).first {
                throw MultiToolBuilderError(
                    kind: .duplicateName,
                    name: collision,
                    message: "Tool name \"\(collision)\" collides with group \"\(collision)\"; a "
                        + "standalone tool and a group can't share the same top-level name — "
                        + "tools.\(collision) would be ambiguous between a function and a namespace."
                )
            }

            return MultiTool.Registry(surface: APISurface(entries: entries), tools: toolsByPath)
        }

        /// Reads the current catalog of each MCP server again, and then
        /// renders every registration into a new `MultiTool.Registry` — the
        /// first half of rebuild-and-swap.
        ///
        /// For each `MCPCapability`, the server's catalog is read again and
        /// new `MCPTool` verbs are made from it. Every other capability and
        /// every tool is the same instance the first build rendered, so the
        /// store of the shell and the context of the files capability hold
        /// across the rebuild. Then the same validation as
        /// ``buildRegistry()`` runs.
        ///
        /// A `Registry` that exists is never touched: the result is a new
        /// value, and a failure leaves the caller with the registry it holds.
        ///
        /// - Returns: the registry rendered from the current catalogs.
        /// - Throws: what `MCPCapability.init(server:)` throws when a server
        ///   cannot reach `.ready`, and what ``buildRegistry()`` throws when
        ///   the current catalogs no longer render — a verb that is not a
        ///   legal identifier, or two tools at one path.
        public func rebuildRegistry() async throws -> MultiTool.Registry {
            try await refreshed().buildRegistry()
        }

        /// A copy of this source in which each `MCPCapability` is replaced by
        /// one read from its server's current catalog.
        ///
        /// - Returns: the refreshed source.
        /// - Throws: what `MCPCapability.refreshed()` throws.
        private func refreshed() async throws -> RegistrySource {
            var refreshed = RegistrySource()
            for registration in registrations {
                guard case .capability(let capability) = registration,
                    let mcp = capability as? MCPCapability
                else {
                    refreshed.registrations.append(registration)
                    continue
                }
                refreshed.registrations.append(.capability(try await mcp.refreshed()))
            }
            return refreshed
        }

        // MARK: - Expansion

        /// Expands every registration into the queue of tools to render and
        /// the claims of the capabilities.
        ///
        /// A capability's tools are queued together under its noun, and the
        /// claim records the positions they fill, so a later validation can
        /// tell the capability's own entries from an entry another
        /// registration put under the same noun.
        ///
        /// - Returns: the queue and the claims.
        private func expanded() -> Expansion {
            var pending: [PendingTool] = []
            var claims: [CapabilityClaim] = []
            for registration in registrations {
                switch registration {
                case .standalone(let tool):
                    pending.append(.standalone(tool))
                case .grouped(let group, let tool):
                    pending.append(.grouped(group: group, tool: tool))
                case .capability(let capability):
                    let firstPosition = pending.count
                    for tool in capability.tools {
                        pending.append(.grouped(group: capability.noun, tool: tool))
                    }
                    claims.append(
                        CapabilityClaim(
                            noun: capability.noun,
                            claimant: String(describing: type(of: capability)),
                            toolPositions: firstPosition..<pending.count
                        )
                    )
                }
            }
            return Expansion(pending: pending, claims: claims)
        }

        // MARK: - Validation

        /// Answers which capability owns each claimed noun.
        ///
        /// - Parameter claims: every claim a capability made, in order.
        /// - Returns: the owning claim of each noun.
        /// - Throws: `MultiToolBuilderError` of kind `.duplicateNoun`, naming
        ///   the noun and both capabilities, when one noun holds two claims.
        private static func capabilityOwnersByNoun(
            of claims: [CapabilityClaim]
        ) throws -> [String: CapabilityClaim] {
            var owners: [String: CapabilityClaim] = [:]
            for claim in claims {
                guard let standing = owners[claim.noun] else {
                    owners[claim.noun] = claim
                    continue
                }
                throw MultiToolBuilderError(
                    kind: .duplicateNoun,
                    name: claim.noun,
                    message: "Noun \"\(claim.noun)\" is claimed by two capabilities, "
                        + "\(standing.claimant) and \(claim.claimant); a capability owns its "
                        + "whole tools.\(claim.noun) namespace, so a second capability can't "
                        + "claim it. Give one of the two a noun of its own."
                )
            }
            return owners
        }

        /// Holds each capability to the whole noun it claims.
        ///
        /// Runs after the render loop of ``buildRegistry()``, so two tools
        /// that would render at one path are still reported as the
        /// `.duplicateName` collision they are. What is left for this method
        /// is the ownership rule, which holds even where every path differs.
        ///
        /// - Parameters:
        ///   - expansion: the queue and the claims the render loop rendered.
        ///   - standaloneNames: the rendered name of every standalone tool,
        ///     which the render loop collected.
        /// - Throws: `MultiToolBuilderError` of kind `.duplicateNoun` when two
        ///   capabilities claim one noun, when a registration no capability
        ///   made lands under a claimed noun, or when a standalone tool wears
        ///   a claimed noun as its own flat name.
        private static func validateNounOwnership(
            of expansion: Expansion, standaloneNames: Set<String>
        ) throws {
            let owners = try capabilityOwnersByNoun(of: expansion.claims)

            for (position, item) in expansion.pending.enumerated() {
                guard case .grouped(let noun, let tool) = item,
                    let owner = owners[noun],
                    !owner.toolPositions.contains(position)
                else { continue }
                throw MultiToolBuilderError(
                    kind: .duplicateNoun,
                    name: noun,
                    message: "Noun \"\(noun)\" is owned by the capability \(owner.claimant), and "
                        + "the tool \"\(tool.name)\" was registered under it by "
                        + "addGroup(named:_:) or register(noun:tool:); a capability owns its "
                        + "whole tools.\(noun) namespace. Register that tool under a noun of "
                        + "its own, or put it in the capability's own tools."
                )
            }

            for claim in expansion.claims where standaloneNames.contains(claim.noun) {
                throw MultiToolBuilderError(
                    kind: .duplicateNoun,
                    name: claim.noun,
                    message: "Noun \"\(claim.noun)\" is owned by the capability "
                        + "\(claim.claimant), and a standalone tool of that name renders flat at "
                        + "tools.\(claim.noun); the one path would be ambiguous between a "
                        + "function and the namespace of the capability. Rename the standalone "
                        + "tool, or give the capability a noun of its own."
                )
            }
        }
    }
}
