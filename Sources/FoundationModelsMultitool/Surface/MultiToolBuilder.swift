import Foundation
import FoundationModels

/// A failure raised by `MultiTool.Builder.build()`.
///
/// Never raised by `addTool`/`addTools`/`addGroup`/`register`/
/// `withCapability`, which only record what was added. Every validation —
/// group-name and noun legality, name collisions, and each tool's own
/// completeness contract through `ToolAPIRenderer` — occurs one time, at
/// `build()`. That is why the fluent chain needs `try` only on its final
/// call.
///
/// `withShell(storeDirectory:sandbox:outputChunkStream:)` is the one
/// registration method that throws, and it never throws THIS error: it
/// prepares the store of the shell on disk, which is resource acquisition
/// rather than validation. The single leading `try` of the chain covers it.
public struct MultiToolBuilderError: Error, Sendable, Equatable, CustomStringConvertible {
    /// What kind of build-time failure this was.
    public enum Kind: Sendable, Equatable {
        /// Two tools would render at the same top-level snippet call
        /// path: two standalone tools sharing a `name`, two tools in the
        /// same group sharing a `name`, or a standalone tool's `name`
        /// matching a group's name outright. Duplicates *across different
        /// groups* are fine — their fully-qualified paths differ — so this
        /// is never raised for those.
        case duplicateName

        /// A group name passed to `addGroup(named:_:)` — or a noun passed
        /// to `register(noun:tool:)`, which is the same segment under the
        /// other name — isn't a legal TypeScript identifier.
        /// Schema/user-derived text is never
        /// spliced into a generated `tools.<group>.<name>` namespace
        /// without this check — the same posture `ToolAPIRenderer` takes
        /// toward a tool's own `name`.
        case illegalGroupName

        /// A noun a capability owns was registered a second time. Nouns are
        /// unique, and registration rejects a duplicate noun.
        ///
        /// `withCapability(_:)` claims the whole `tools.<noun>` namespace, so
        /// three shapes raise this: a second capability that claims the same
        /// noun, a tool that `addGroup(named:_:)` or `register(noun:tool:)`
        /// puts under that noun, and a standalone tool whose flat
        /// `tools.<name>` entry wears the noun.
        ///
        /// Distinct from `duplicateName`, which reports two tools that would
        /// render at one path. This case reports ownership, so it is raised
        /// even when every path differs: `tools.demo.first` and
        /// `tools.demo.second` collide nowhere, and a second owner of `demo`
        /// is the failure all the same.
        case duplicateNoun
    }

    /// What kind of failure this was.
    public let kind: Kind

    /// The offending tool or group name.
    public let name: String

    /// A human-readable description of the failure.
    public let message: String

    /// Creates a builder error.
    ///
    /// Explicit because a `public` struct's synthesized initializer is
    /// `internal` only, and this error crosses the
    /// `FoundationModelsMultitool` library product's boundary — a caller
    /// builds one to make a fixture in its own tests.
    public init(kind: Kind, name: String, message: String) {
        self.kind = kind
        self.name = name
        self.message = message
    }

    /// A human-readable description of the error, satisfying
    /// `CustomStringConvertible`.
    public var description: String { message }
}

extension MultiTool {
    /// Collects wrapped `Tool`s into a model-agnostic catalog and renders
    /// them, through `ToolAPIRenderer`, into an `APISurface`. It is a pure
    /// catalog, with no model wiring in it.
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
        private enum PendingTool {
            case standalone(any Tool)
            case grouped(group: String, tool: any Tool)
        }

        /// Every tool queued so far, in add order.
        private var pending: [PendingTool] = []

        /// One capability's claim on one noun, recorded by
        /// `withCapability(_:)` — the fact that tells an entry the capability
        /// itself queued from an entry another registration put under the
        /// same noun.
        ///
        /// `withCapability(_:)`, `addGroup(named:_:)` and
        /// `register(noun:tool:)` all queue the same `.grouped` item, so the
        /// queue alone cannot say who registered what. The claim answers that
        /// with the half-open range of queue positions the capability's own
        /// tools fill, and it names the claimant so the failure can too.
        private struct CapabilityClaim {
            /// The noun this capability owns.
            let noun: String

            /// The name of the capability's own type. A capability holds a
            /// noun and its tools and nothing else, so its type is the only
            /// identity an error message can give it.
            let claimant: String

            /// The half-open range of `pending` positions holding this
            /// capability's own tools. `withCapability(_:)` queues them
            /// together, so one range covers all of them.
            let toolPositions: Range<Int>
        }

        /// Every claim a capability has made so far, in claim order.
        private var capabilityClaims: [CapabilityClaim] = []

        /// Creates an empty builder.
        public init() {}

        /// Queues `tool` as a standalone tool, destined to render flat at
        /// `tools.<tool.name>`.
        ///
        /// Generic over `T: Tool`, and not `any Tool`, to capture the
        /// concrete type. A concrete `T` and an already-erased `any Tool`
        /// both work at this call site — Swift's implicit existential
        /// opening (SE-0352) binds `T` to the underlying concrete type
        /// either way — and the `any Tool` stored in `pending` is what a
        /// later `ToolInvoker.invoke` opens again to make the native call.
        ///
        /// - Parameter tool: the tool to add.
        @discardableResult
        public func addTool<T: Tool>(_ tool: T) -> Self {
            pending.append(.standalone(tool))
            return self
        }

        /// Queues every tool in `tools` as a standalone tool, in order —
        /// equivalent to calling `addTool(_:)` once per element.
        @discardableResult
        public func addTools(_ tools: [any Tool]) -> Self {
            enqueue(tools) { addTool($0) }
        }

        /// Queues `tool` under the namespace `noun`, destined to render at
        /// `tools.<noun>.<tool.name>` — the registration primitive.
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
        ///     here — see ``MultiToolBuilderError`` for why no registration
        ///     method throws.
        ///   - tool: the tool to add under `noun`.
        @discardableResult
        public func register(noun: String, tool: any Tool) -> Self {
            pending.append(.grouped(group: noun, tool: tool))
            return self
        }

        /// Queues every tool of `capability` under that capability's own
        /// noun, in order.
        ///
        /// A capability is only a noun plus its tools, so this method is only
        /// `register(noun:tool:)` called one time for each tool. Built-in
        /// capabilities and user capabilities come through the same door.
        ///
        /// The method also CLAIMS the noun for that capability, which is
        /// where it parts from `addGroup(named:_:)`. A group name is a merge:
        /// two calls with one name put their tools in one namespace. A noun
        /// is owned: the capability holds the whole `tools.<noun>` namespace,
        /// and a second registration under it — another capability, an
        /// `addGroup(named:_:)` call, a `register(noun:tool:)` call, or a
        /// standalone tool of that name — is a `.duplicateNoun` failure at
        /// `buildRegistry()`, however the verbs fall.
        ///
        /// - Parameter capability: the capability to register.
        @discardableResult
        public func withCapability(_ capability: any Capability) -> Self {
            let firstPosition = pending.count
            enqueue(capability.tools) { register(noun: capability.noun, tool: $0) }
            capabilityClaims.append(
                CapabilityClaim(
                    noun: capability.noun,
                    claimant: String(describing: type(of: capability)),
                    toolPositions: firstPosition..<pending.count
                )
            )
            return self
        }

        /// Queues the three verbs of the shell capability —
        /// `tools.shell.execute`, `tools.shell.getLines` and
        /// `tools.shell.grepHistory` — under the noun `shell`. It is a short
        /// form of `withCapability(ShellCapability(...))`, so the verbs render
        /// and the noun is owned as any other capability's are.
        ///
        /// **The shell is OFF by default.** A builder that never calls this
        /// renders no `tools.shell` namespace at all.
        ///
        /// - Parameters:
        ///   - storeDirectory: the directory each run's history and captured
        ///     output are written into. Defaults to `<cwd>/.shell`.
        ///   - sandbox: the confinement each command spawns under. Defaults to
        ///     no confinement at all.
        ///   - outputChunkStream: the live view of the output a subscribed host
        ///     reads. Defaults to teeing nothing.
        /// - Throws: what
        ///   `ShellCapability.init(storeDirectory:sandbox:outputChunkStream:)`
        ///   throws when the store cannot prepare.
        @discardableResult
        public func withShell(
            storeDirectory: URL? = nil,
            sandbox: (any CommandSandbox)? = nil,
            outputChunkStream: ShellOutputChunkStream? = nil
        ) throws -> Self {
            let capability = try ShellCapability(
                storeDirectory: storeDirectory,
                sandbox: sandbox,
                outputChunkStream: outputChunkStream
            )
            return withCapability(capability)
        }

        /// Queues the six verbs of the files capability — `tools.files.read`,
        /// `tools.files.write`, `tools.files.edit`, `tools.files.patch`,
        /// `tools.files.glob` and `tools.files.grep` — under the noun `files`,
        /// through `withCapability(_:)`.
        ///
        /// **Files is OFF by default.** A builder that never calls this
        /// renders no `tools.files` namespace at all.
        ///
        /// Unlike `withShell(...)`, this method does not throw. The files
        /// capability acquires no resource at construction: the session
        /// context validates nothing up front, and every path question is
        /// answered per call, as a correction in the verb's own result.
        ///
        /// - Parameters:
        ///   - root: the session working directory: the boundary every path
        ///     is confined to, and the base a relative path resolves against.
        ///   - additionalRoots: extra workspace boundaries paths may also
        ///     resolve within, alongside `root`. Defaults to none.
        ///   - readOnly: whether the session forbids the mutating verbs.
        ///     Defaults to letting them run.
        ///   - allowSymlinks: whether the path guard resolves symlinks rather
        ///     than rejecting them. Defaults to rejecting them.
        ///   - recordsChanges: whether the mutating verbs record what they
        ///     changed into the session's change journal. Defaults to
        ///     recording nothing.
        @discardableResult
        public func withFiles(
            root: URL,
            additionalRoots: Set<URL> = [],
            readOnly: Bool = false,
            allowSymlinks: Bool = false,
            recordsChanges: Bool = false
        ) -> Self {
            withCapability(
                FilesCapability(
                    root: root,
                    additionalRoots: additionalRoots,
                    readOnly: readOnly,
                    allowSymlinks: allowSymlinks,
                    recordsChanges: recordsChanges
                )
            )
        }

        /// Queues every tool in `tools` under the named `group`, destined
        /// to render at `tools.<group>.<name>`. Calling `addGroup(named:_:)`
        /// more than once with the same `group` merges every call's tools
        /// into that one namespace, in the order added.
        ///
        /// The group is the noun, so this method registers through
        /// `register(noun:tool:)`.
        ///
        /// - Parameters:
        ///   - group: the namespace every tool in `tools` renders under.
        ///     Must be a legal TypeScript identifier; examined at
        ///     `buildRegistry()`, and not here — see ``MultiToolBuilderError``
        ///     for why no registration method throws.
        ///   - tools: the tools to add under `group`.
        @discardableResult
        public func addGroup(named group: String, _ tools: [any Tool]) -> Self {
            enqueue(tools) { register(noun: group, tool: $0) }
        }

        /// Queues every tool in `tools`, in order, through the single-tool
        /// registration method `add` names.
        ///
        /// Each caller passes its own primitive: `addTool(_:)` for a flat
        /// entry, `register(noun:tool:)` for a `tools.<noun>.<verb>` entry.
        /// Thus one method queues one tool, and this loop holds the only
        /// copy of the fluent tail.
        @discardableResult
        private func enqueue(_ tools: [any Tool], by add: (any Tool) -> Void) -> Self {
            for tool in tools {
                add(tool)
            }
            return self
        }

        /// Renders every queued tool into an `APISurface` — the rendered
        /// catalog alone, with no live tool instances attached.
        ///
        /// Its own entry point for a caller that only wants the
        /// model-agnostic catalog — the registry-backed selection tier's
        /// instruction prefix, `help()`/`docs()`, or a host UI listing — and
        /// not an executable `MultiTool`.
        ///
        /// - Throws: see `buildRegistry()` — this delegates to it entirely.
        public func build() throws -> APISurface {
            try buildRegistry().surface
        }

        /// Renders every queued tool and assembles the result into a
        /// `MultiTool.Registry`, which pairs the same rendered `APISurface`
        /// `build()` returns with the live `any Tool` instances a `MultiTool`
        /// dispatches `tools.*` calls to. This is the primary entry point;
        /// `build()` above is the thin, surface-only wrapper over it.
        ///
        /// Validates the namespacing rule: every standalone tool's name is
        /// unique among standalone tools; every tool's name is unique within
        /// its own group; and no standalone tool's name collides with a
        /// group's name, which would make `tools.<name>` ambiguous between a
        /// function and a namespace.
        ///
        /// Validates one rule more: a noun `withCapability(_:)` claims is
        /// owned whole, so nothing else may register under it.
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
        ///   `withCapability(_:)` claimed.
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

            try validateNounOwnership(standaloneNames: standaloneNames)

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

        /// Answers which capability owns each claimed noun.
        ///
        /// - Throws: `MultiToolBuilderError` of kind `.duplicateNoun`, naming
        ///   the noun and both capabilities, when one noun holds two claims.
        private func capabilityOwnersByNoun() throws -> [String: CapabilityClaim] {
            var owners: [String: CapabilityClaim] = [:]
            for claim in capabilityClaims {
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
        /// Runs after the render loop above, so two tools that would render at
        /// one path are still reported as the `.duplicateName` collision they
        /// are. What is left for this method is the ownership rule, which
        /// holds even where every path differs.
        ///
        /// - Parameter standaloneNames: the rendered name of every standalone
        ///   tool of this builder, which the render loop above collected.
        /// - Throws: `MultiToolBuilderError` of kind `.duplicateNoun` when two
        ///   capabilities claim one noun, when a registration no capability
        ///   made lands under a claimed noun, or when a standalone tool wears
        ///   a claimed noun as its own flat name.
        private func validateNounOwnership(standaloneNames: Set<String>) throws {
            let owners = try capabilityOwnersByNoun()

            for (position, item) in pending.enumerated() {
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

            for claim in capabilityClaims where standaloneNames.contains(claim.noun) {
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
