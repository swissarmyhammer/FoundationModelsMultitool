import FoundationModels

/// Namespace for the MultiTool feature area — plan.md's central idea, "a
/// single `Tool` — the **MultiTool** — that wraps other, in-process
/// `Tool`s and exposes them to the model as a callable code API"
/// (Component 1).
///
/// The `runCode` `Tool` conformance itself lands in a later milestone
/// (M4a: "MultiTool runCode execution"); this bare namespace exists purely
/// so `MultiTool.Builder` — the model-agnostic tool catalog this file
/// builds (M2.5) — has the home plan.md's "Adding tools is the easy path"
/// usage expects: `MultiTool.Builder().addTool(...).build()`.
public enum MultiTool {}

/// A failure raised by `MultiTool.Builder.build()`.
///
/// Never raised by `addTool`/`addTools`/`addGroup`, which only ever record
/// what was added — every validation (group-name legality, name
/// collisions, and each tool's own completeness contract via
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

        /// A group name passed to `addGroup(named:_:)` isn't a legal
        /// TypeScript identifier. Schema/user-derived text is never
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
    /// Explicit (rather than relying on the compiler-synthesized memberwise
    /// initializer) for the same reason as `ToolDescriptor.init` in
    /// `ToolDescriptor.swift`: a `public` struct's synthesized initializer
    /// is only `internal`-accessible, and `MultiToolBuilderError` is a
    /// public `Error` type thrown across the `FoundationModelsMultitool`
    /// library product's boundary — without this, no module outside
    /// `FoundationModelsMultitool` could construct one, e.g. to build a
    /// fixture in a caller's own tests.
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
    ///     .build()                                 // rendered APISurface; still model-agnostic
    /// ```
    ///
    /// A `final class` (not a `struct`): `addTool`/`addTools`/`addGroup`
    /// mutate this builder's queued-tool list in place and return `self`
    /// so the fluent chain above type-checks with no intermediate `var
    /// builder = ...` — a `struct`'s `mutating` methods can't be called
    /// directly on the un-named temporary `MultiTool.Builder()` returns,
    /// only a reference type's in-place mutation supports this chained
    /// style.
    public final class Builder {
        /// One tool queued for rendering — standalone (destined for a
        /// flat `tools.<name>` entry) or belonging to a named group
        /// (destined for `tools.<group>.<name>`) — recorded in the exact
        /// order `addTool`/`addTools`/`addGroup` was called.
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
            for tool in tools {
                pending.append(.standalone(tool))
            }
            return self
        }

        /// Queues every tool in `tools` under the named `group`, destined
        /// to render at `tools.<group>.<name>` — plan.md's namespacing for
        /// "many `Tool`s under one namespace" (Resolved #5). Calling
        /// `addGroup(named:_:)` more than once with the same `group`
        /// merges every call's tools into that one namespace, in the order
        /// added.
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
            for tool in tools {
                pending.append(.grouped(group: group, tool: tool))
            }
            return self
        }

        /// Renders every queued tool and assembles the result into an
        /// `APISurface`, in the exact order tools were added.
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
        /// - Returns: the rendered, model-agnostic catalog.
        /// - Throws: `ToolAPIRendererError`, propagated unchanged (never
        ///   wrapped — the same posture `ToolInvoker` takes toward a
        ///   tool's own thrown error), if any queued tool can't be fully
        ///   rendered — plan.md's completeness contract: "`Builder.build()`
        ///   fails loudly if a tool can't be fully rendered rather than
        ///   emit a lossy stub." `MultiToolBuilderError` if a group name
        ///   isn't a legal TypeScript identifier, or if two tools would
        ///   collide at the same top-level snippet call path.
        public func build() throws -> APISurface {
            var entries: [APISurface.Entry] = []
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
                    entries.append(
                        APISurface.Entry(path: "\(group).\(descriptor.name)", group: group, descriptor: descriptor)
                    )
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

            return APISurface(entries: entries)
        }
    }
}
