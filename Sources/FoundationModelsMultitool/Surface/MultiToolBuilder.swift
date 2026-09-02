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
/// `withShell(storeDirectory:sandbox:outputChunkStream:defaultWorkingDirectory:)`
/// and `withMCP(servers:)` are the two registration methods that throw, and
/// neither throws THIS error: the first prepares the store of the shell on
/// disk, and the second waits for each server to be ready, which is resource
/// acquisition rather than validation. The single leading `try` of the chain
/// covers both.
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
    /// mutates this builder's recorded registrations in place and returns
    /// `self` so the fluent chain above type-checks with no intermediate
    /// `var builder = ...` — a `struct`'s `mutating` methods can't be called
    /// directly on the un-named temporary `MultiTool.Builder()` returns,
    /// only a reference type's in-place mutation supports this chained
    /// style.
    ///
    /// The builder records; ``MultiTool/RegistrySource`` renders. Every
    /// registration method appends to ``registrySource``, and `build()` and
    /// `buildRegistry()` render that value. A host that must render again
    /// later — after a `tools/list_changed` re-list of an MCP server — keeps
    /// ``registrySource`` and calls its `rebuildRegistry()`, so the builder
    /// itself need not outlive the chain.
    public final class Builder {
        /// Every registration so far, in registration order — the value a
        /// session keeps after `build()`.
        private var source = MultiTool.RegistrySource()

        /// The servers ``withMCP(servers:)`` recorded, for the shutdown that
        /// follows the session sweep — see ``serverPool``.
        private let pool = MCPServerPool()

        /// Creates an empty builder.
        public init() {}

        /// The pool that holds every server ``withMCP(servers:)`` recorded.
        ///
        /// A host keeps this pool beside ``registrySource``, adds the
        /// `StdioServerProcess` of each server it spawned, and calls
        /// `MCPServerPool.shutdownAll()` after the session sweep at session
        /// end. A builder that never called ``withMCP(servers:)`` holds an
        /// empty pool, whose `shutdownAll()` does nothing.
        public var serverPool: MCPServerPool { pool }

        /// The recorded registrations of this builder, as the `Sendable`
        /// value a session keeps after `build()`.
        ///
        /// It holds the recorded items, and nothing else. Its
        /// `rebuildRegistry()` reads the catalog of each MCP server again
        /// and renders a new `Registry`, so a host keeps this value and not
        /// the builder.
        public var registrySource: MultiTool.RegistrySource { source }

        /// Queues `tool` as a standalone tool, destined to render flat at
        /// `tools.<tool.name>`.
        ///
        /// Generic over `T: Tool`, and not `any Tool`, to capture the
        /// concrete type. A concrete `T` and an already-erased `any Tool`
        /// both work at this call site — Swift's implicit existential
        /// opening (SE-0352) binds `T` to the underlying concrete type
        /// either way — and the `any Tool` recorded is what a later
        /// `ToolInvoker.invoke` opens again to make the native call.
        ///
        /// - Parameter tool: the tool to add.
        @discardableResult
        public func addTool<T: Tool>(_ tool: T) -> Self {
            source.registrations.append(.standalone(tool))
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
        /// `addGroup(named:_:)` comes through here, so both registrations
        /// make the same `tools.<noun>.<verb>` entry and obey the same
        /// validation at `buildRegistry()`. `withCapability(_:)` records the
        /// capability itself, so a rebuild can ask it for its current tools;
        /// its entries render under the same rule.
        ///
        /// - Parameters:
        ///   - noun: the namespace `tool` renders under. Must be a legal
        ///     TypeScript identifier; examined at `buildRegistry()`, and not
        ///     here — see ``MultiToolBuilderError`` for why no registration
        ///     method throws.
        ///   - tool: the tool to add under `noun`.
        @discardableResult
        public func register(noun: String, tool: any Tool) -> Self {
            source.registrations.append(.grouped(group: noun, tool: tool))
            return self
        }

        /// Queues every tool of `capability` under that capability's own
        /// noun, in order.
        ///
        /// A capability is only a noun plus its tools, so at render time this
        /// is only `register(noun:tool:)` applied one time for each tool.
        /// Built-in capabilities and user capabilities come through the same
        /// door.
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
            source.registrations.append(.capability(capability))
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
        ///   - defaultWorkingDirectory: the directory a `tools.shell.execute`
        ///     call runs in when it omits `workingDirectory`. Defaults to the
        ///     current directory of this process. A host with a session root
        ///     passes that root.
        /// - Throws: what
        ///   `ShellCapability.init(storeDirectory:sandbox:outputChunkStream:defaultWorkingDirectory:)`
        ///   throws when the store cannot prepare.
        @discardableResult
        public func withShell(
            storeDirectory: URL? = nil,
            sandbox: (any CommandSandbox)? = nil,
            outputChunkStream: ShellOutputChunkStream? = nil,
            defaultWorkingDirectory: URL? = nil
        ) throws -> Self {
            let capability = try ShellCapability(
                storeDirectory: storeDirectory,
                sandbox: sandbox,
                outputChunkStream: outputChunkStream,
                defaultWorkingDirectory: defaultWorkingDirectory
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
        ///     changed. When `true`, each `write`, `edit` and `patch` call
        ///     that lands delivers its changes to the session as one
        ///     `.progress` `OperationEvent` whose `detail` is the
        ///     `fileChanges` envelope; a host reads it with
        ///     `FileChangeSet.init(operationEventDetail:)`. A verb called
        ///     with no session keeps them in the change journal for a drain.
        ///     Defaults to recording nothing.
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

        /// Queues one MCP capability for each server of `servers`, in order —
        /// the verbs of each server under the noun that is the server's own
        /// name, `tools.<serverName>.<toolName>`. It is a short form of
        /// `withCapability(MCPCapability(server:))` called one time for each
        /// server, so the verbs render and each noun is owned as any other
        /// capability's are. No `tools.mcp` group exists: the model must not
        /// see the transport.
        ///
        /// **MCP is OFF by default.** A builder that never calls this renders
        /// no server group at all.
        ///
        /// The method awaits readiness, and it does not connect. eventplan.md:
        /// "Servers connect before `buildRegistry()`." The host connects each
        /// server first; this method waits for each one through
        /// `MCPServer.waitUntilReady()` and reads its catalog.
        ///
        /// A server whose name is a noun another registration owns — a server
        /// named `files` beside `withFiles(root:)` — is the `.duplicateNoun`
        /// failure of `buildRegistry()`, as for any other capability.
        ///
        /// Each server is also recorded into ``serverPool``, so the host's
        /// `MCPServerPool.shutdownAll()` after the session sweep reaches it.
        ///
        /// - Parameter servers: the servers the host connected, in the order
        ///   their groups render.
        /// - Throws: `MCPServerError.notReady(_:)` when a server is `.faulted`
        ///   or `.disconnected`, and so cannot reach `.ready` without a new
        ///   connect — see `MCPCapability.init(server:)`.
        @discardableResult
        public func withMCP(servers: [MCPServer]) async throws -> Self {
            for server in servers {
                withCapability(try await MCPCapability(server: server))
                await pool.add(server: server)
            }
            return self
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
        /// Delegates to ``MultiTool/RegistrySource/buildRegistry()`` on
        /// ``registrySource``, which holds every validation.
        ///
        /// - Returns: the rendered catalog paired with its live tool
        ///   instances, in `.directMode() == false` (both `runCode` and
        ///   `searchTools` surfaced).
        /// - Throws: what ``MultiTool/RegistrySource/buildRegistry()`` throws.
        public func buildRegistry() throws -> MultiTool.Registry {
            try source.buildRegistry()
        }

        /// Reads the current catalog of each MCP server again, and then
        /// renders a new `MultiTool.Registry` from the same registrations —
        /// the first half of rebuild-and-swap.
        ///
        /// Delegates to ``MultiTool/RegistrySource/rebuildRegistry()`` on
        /// ``registrySource``. A host that no longer holds the builder calls
        /// that method on the source it kept; the result is the same.
        ///
        /// - Returns: the registry rendered from the current catalogs.
        /// - Throws: what ``MultiTool/RegistrySource/rebuildRegistry()``
        ///   throws.
        public func rebuildRegistry() async throws -> MultiTool.Registry {
            try await source.rebuildRegistry()
        }
    }
}
