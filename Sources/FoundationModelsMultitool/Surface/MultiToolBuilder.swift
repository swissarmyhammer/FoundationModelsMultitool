import FoundationModels

/// A failure raised by `MultiTool.Builder.build()`.
///
/// Never raised by `addTool`/`addTools`/`addGroup`/`register`/
/// `withCapability`, which only ever record what was added — every
/// validation (group-name and noun legality, name collisions, and each
/// tool's own completeness contract via
/// `ToolAPIRenderer`) happens once, at `build()`. That's why plan.md's
/// fluent chain needs `try` only on the final call:
/// `try MultiTool.Builder().addTool(...)....addGroup(...).build()`.
public struct MultiToolBuilderError: Error, Sendable, Equatable, CustomStringConvertible {
    /// What kind of build-time failure this was.
    public enum Kind: Sendable, Equatable {
        /// Two tools would render at the same top-level snippet call
        /// path: two standalone tools sharing a `name`, two tools in the
        /// same group sharing a `name`, or a standalone tool's `name`
        /// matching a group's name outright. Namespacing per plan.md
        /// Resolved #5: duplicates *across different groups* are fine
        /// (their fully-qualified paths differ), so this is never raised
        /// for those.
        case duplicateName

        /// A group name passed to `addGroup(named:_:)` — or a noun passed
        /// to `register(noun:tool:)`, which is the same segment under the
        /// other name — isn't a legal TypeScript identifier.
        /// Schema/user-derived text is never
        /// spliced into a generated `tools.<group>.<name>` namespace
        /// without this check — the same posture `ToolAPIRenderer` takes
        /// toward a tool's own `name`.
        case illegalGroupName
    }

    /// What kind of failure this was.
    public let kind: Kind

    /// The offending tool or group name.
    public let name: String

    /// A human-readable description of the failure.
    public let message: String

    /// Creates a builder error.
    ///
    /// Explicit for the same reason as `ToolDescriptor.init` in
    /// `ToolDescriptor.swift`: a `public` struct's synthesized initializer
    /// is only `internal`-accessible, and `MultiToolBuilderError` is a
    /// public `Error` type thrown across the `FoundationModelsMultitool`
    /// library product's boundary, e.g. to build a fixture in a caller's
    /// own tests.
    ///
    /// - Parameters:
    ///   - kind: what kind of failure this was.
    ///   - name: the offending tool or group name.
    ///   - message: a human-readable description of the failure.
    public init(kind: Kind, name: String, message: String) {
        self.kind = kind
        self.name = name
        self.message = message
    }

    /// A human-readable description of the error, satisfying
    /// `CustomStringConvertible`. Identical to `message`.
    public var description: String { message }
}

extension MultiTool {
    /// Collects wrapped `Tool`s into a model-agnostic catalog and renders
    /// them, via `ToolAPIRenderer`, into an `APISurface` — plan.md §
    /// "Adding tools is the easy path" / Component 2: "The `Builder` is a
    /// pure catalog — no model wiring here."
    ///
    /// ```swift
    /// let surface = try MultiTool.Builder()
    ///     .addTool(WeatherTool())                 // any FoundationModels.Tool
    ///     .addTool(thirdPartyToolFromSomePackage)
    ///     .addTools(myToolArray)
    ///     .addGroup(named: "github", githubTools)  // many Tools under one namespace
    ///     .withCapability(FilesCapability())       // one noun, its own Tools
    ///     .build()                                 // rendered APISurface; still model-agnostic
    /// ```
    ///
    /// A `final class` (not a `struct`): every registration method
    /// mutates this builder's queued-tool list in place and returns `self`
    /// so the fluent chain above type-checks with no intermediate `var
    /// builder = ...` — a `struct`'s `mutating` methods can't be called
    /// directly on the un-named temporary `MultiTool.Builder()` returns,
    /// only a reference type's in-place mutation supports this chained
    /// style.
    public final class Builder {
        /// One tool queued for rendering — standalone (destined for a
        /// flat `tools.<name>` entry) or belonging to a named group
        /// (destined for `tools.<group>.<name>`) — recorded in the exact
        /// order the registration methods were called. A noun and a group
        /// are the same segment, so `register(noun:tool:)` and
        /// `addGroup(named:_:)` both queue `.grouped`.
        /// `ToolAPIRenderer` never runs until `build()`.
        private enum PendingTool {
            case standalone(any Tool)
            case grouped(group: String, tool: any Tool)
        }

        /// Every tool queued so far, in add order.
        private var pending: [PendingTool] = []

        /// Creates an empty builder.
        public init() {}

        /// Queues `tool` as a standalone tool, destined to render flat at
        /// `tools.<tool.name>`.
        ///
        /// Generic over `T: Tool` (rather than accepting `any Tool`
        /// directly) per plan.md: "`addTool` is generic over `T: Tool`,
        /// capturing the concrete type so `ToolInvoker` can open it
        /// later." Passing a concrete `T` or an already-erased `any Tool`
        /// value both work identically at this call site — Swift's
        /// implicit existential opening (SE-0352) binds `T` to the
        /// value's underlying concrete type either way — and the `any
        /// Tool` stored in `pending` is exactly what a later
        /// `ToolInvoker.invoke` (M3b) opens again to make the native
        /// call.
        ///
        /// - Parameter tool: the tool to add.
        /// - Returns: `self`, for fluent chaining.
        @discardableResult
        public func addTool<T: Tool>(_ tool: T) -> Self {
            pending.append(.standalone(tool))
            return self
        }

        /// Queues every tool in `tools` as a standalone tool, in order —
        /// equivalent to calling `addTool(_:)` once per element.
        ///
        /// - Parameter tools: the tools to add.
        /// - Returns: `self`, for fluent chaining.
        @discardableResult
        public func addTools(_ tools: [any Tool]) -> Self {
            enqueue(tools) { addTool($0) }
        }

        /// Queues `tool` under the namespace `noun`, destined to render at
        /// `tools.<noun>.<tool.name>` — the registration primitive of
        /// eventplan.md § "Registration of capabilities: noun/verb".
        ///
        /// The method supplies the noun, and nothing else. The tool supplies
        /// the verb, because `Tool.name` is the verb. Thus a `Tool` conformer
        /// that exists needs no change to register: the two segments of the
        /// path come from the two sides of this one call.
        ///
        /// `addGroup(named:_:)` and `withCapability(_:)` both come through
        /// here, so all three registrations make the same
        /// `tools.<noun>.<verb>` entry and obey the same validation at
        /// `buildRegistry()`.
        ///
        /// - Parameters:
        ///   - noun: the namespace `tool` renders under. Must be a legal
        ///     TypeScript identifier; examined at `buildRegistry()`, and not
        ///     here — see this type's documentation for why no registration
        ///     method throws.
        ///   - tool: the tool to add under `noun`.
        /// - Returns: `self`, for fluent chaining.
        @discardableResult
        public func register(noun: String, tool: any Tool) -> Self {
            pending.append(.grouped(group: noun, tool: tool))
            return self
        }

        /// Queues every tool of `capability` under that capability's own
        /// noun, in order — eventplan.md's "`Builder.withCapability(_:)`
        /// fills in the noun one time".
        ///
        /// A capability is only a noun plus its tools, so this method is only
        /// `register(noun:tool:)` called one time for each tool. Built-in
        /// capabilities and user capabilities come through the same door.
        ///
        /// A second capability with the same noun and the same verb is a
        /// failure at `buildRegistry()`. Two capabilities with the same noun
        /// and different verbs merge into that one namespace, exactly as two
        /// `addGroup(named:_:)` calls with the same group do.
        ///
        /// - Parameter capability: the capability to register.
        /// - Returns: `self`, for fluent chaining.
        @discardableResult
        public func withCapability(_ capability: any Capability) -> Self {
            enqueue(capability.tools) { register(noun: capability.noun, tool: $0) }
        }

        /// Queues every tool in `tools` under the named `group`, destined
        /// to render at `tools.<group>.<name>` — plan.md's namespacing for
        /// "many `Tool`s under one namespace" (Resolved #5). Calling
        /// `addGroup(named:_:)` more than once with the same `group`
        /// merges every call's tools into that one namespace, in the order
        /// added.
        ///
        /// The group is the noun, so this method registers through
        /// `register(noun:tool:)`. A group and a capability make the same
        /// entry, and one queue holds both.
        ///
        /// - Parameters:
        ///   - group: the namespace every tool in `tools` renders under.
        ///     Must be a legal TypeScript identifier; validated at
        ///     `build()`, not here — see this type's documentation for why
        ///     no `add*` method throws.
        ///   - tools: the tools to add under `group`.
        /// - Returns: `self`, for fluent chaining.
        @discardableResult
        public func addGroup(named group: String, _ tools: [any Tool]) -> Self {
            enqueue(tools) { register(noun: group, tool: $0) }
        }

        /// Queues every tool in `tools`, in order, through the single-tool
        /// registration method `add` names — the shared iterate-and-queue
        /// loop that `addTools(_:)`, `addGroup(named:_:)` and
        /// `withCapability(_:)` all need.
        ///
        /// Each caller passes its own primitive: `addTool(_:)` for a flat
        /// entry, `register(noun:tool:)` for a `tools.<noun>.<verb>` entry.
        /// Thus one method queues one tool, and this loop holds the only
        /// copy of the fluent tail.
        ///
        /// - Parameters:
        ///   - tools: the tools to add.
        ///   - add: queues one tool.
        /// - Returns: `self`, for fluent chaining.
        @discardableResult
        private func enqueue(_ tools: [any Tool], by add: (any Tool) -> Void) -> Self {
            for tool in tools {
                add(tool)
            }
            return self
        }

        /// Renders every queued tool and assembles the result into an
        /// `APISurface` — the rendered catalog alone, with no live tool
        /// instances attached. Equivalent to `try buildRegistry().surface`;
        /// kept as its own entry point for a caller that only wants the
        /// model-agnostic catalog (the registry-backed selection tier's
        /// instruction prefix, `help()`/`docs()`, or a host UI listing), not
        /// an executable `MultiTool`.
        ///
        /// - Returns: the rendered, model-agnostic catalog.
        /// - Throws: see `buildRegistry()` — this delegates to it entirely.
        public func build() throws -> APISurface {
            try buildRegistry().surface
        }

        /// Renders every queued tool and assembles the result into a
        /// `MultiTool.Registry` — plan.md's "registry," pairing the same
        /// rendered `APISurface` `build()` returns with the live `any Tool`
        /// instances a `MultiTool` (M4a) dispatches `tools.*` calls to. This
        /// is the primary entry point; `build()` above is the thin,
        /// surface-only convenience wrapper over it.
        ///
        /// Validates, per plan.md Resolved #5's namespacing rule: every
        /// standalone tool's name is unique among standalone tools; every
        /// tool's name is unique within its own group; and no standalone
        /// tool's name collides with a group's name (which would make
        /// `tools.<name>` ambiguous between a function and a namespace).
        /// Duplicate names *across different groups* are explicitly fine —
        /// their fully-qualified paths (`tools.<groupA>.<name>` vs.
        /// `tools.<groupB>.<name>`) never collide.
        ///
        /// - Returns: the rendered catalog paired with its live tool
        ///   instances, in `.directMode() == false` (both `runCode` and
        ///   `searchTools` surfaced).
        /// - Throws: `ToolAPIRendererError`, propagated unchanged (never
        ///   wrapped — the same posture `ToolInvoker` takes toward a
        ///   tool's own thrown error), if any queued tool can't be fully
        ///   rendered — plan.md's completeness contract: "`Builder.build()`
        ///   fails loudly if a tool can't be fully rendered rather than
        ///   emit a lossy stub." `MultiToolBuilderError` if a group name
        ///   isn't a legal TypeScript identifier, or if two tools would
        ///   collide at the same top-level snippet call path.
        public func buildRegistry() throws -> MultiTool.Registry {
            var entries: [APISurface.Entry] = []
            var toolsByPath: [String: any Tool] = [:]
            var standaloneNames: Set<String> = []
            var groupNames: Set<String> = []
            var namesByGroup: [String: Set<String>] = [:]

            for item in pending {
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
    }
}
