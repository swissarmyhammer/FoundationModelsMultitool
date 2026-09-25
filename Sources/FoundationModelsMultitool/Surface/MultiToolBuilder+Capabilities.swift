import Foundation

/// The short forms of `MultiTool.Builder` for the built-in capabilities.
///
/// Each method here makes one capability and records it through
/// `withCapability(_:)` or `withCapability(_:replacing:)`. No method here
/// writes the recorded registrations directly, so the storage of the builder
/// stays `private` in `MultiToolBuilder.swift`.
extension MultiTool.Builder {
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

    /// Queues the two verbs of the web capability — `tools.web.search`
    /// and `tools.web.fetch` — under the noun `web`, through
    /// `withCapability(_:)`.
    ///
    /// **Web is OFF by default.** A builder that never calls this renders
    /// no `tools.web` namespace.
    ///
    /// Like `withFiles(...)`, this method does not throw. The web
    /// capability gets no resource at construction: it sends no request,
    /// and each network question is answered per call, as a correction in
    /// the verb's own result.
    ///
    /// **The last call wins.** The builder holds at most one web
    /// capability. A second call replaces the earlier web capability at
    /// its position, and gives no error. A different owner of the noun
    /// `web` — `register(noun:tool:)`, `addGroup(named:_:)`, or an MCP
    /// server named `web` — is still `.duplicateNoun` at
    /// `buildRegistry()`.
    ///
    /// - Parameters:
    ///   - configuration: the search providers in the order to try, the
    ///     fetch policy, and the environment that the API keys come from.
    ///     Defaults to `.fromEnvironment()`: each keyed provider whose
    ///     variable is set, then the keyless providers. A host that wants
    ///     no environment read gives `.keyless` or its own list.
    ///   - sessionConfiguration: the configuration of the one
    ///     `URLSession` of the capability. Defaults to `.ephemeral`.
    @discardableResult
    public func withWeb(
        configuration: WebConfiguration = .fromEnvironment(),
        sessionConfiguration: URLSessionConfiguration = .ephemeral
    ) -> Self {
        withWeb(
            configuration: configuration, sessionConfiguration: sessionConfiguration,
            resolver: SystemHostResolver())
    }

    /// Queues the web capability, with the resolver of its address guard.
    /// The rules of `withWeb(configuration:sessionConfiguration:)` apply.
    ///
    /// - Parameters:
    ///   - configuration: the search providers, the fetch policy, and the
    ///     environment that the API keys come from.
    ///   - sessionConfiguration: the configuration of the one `URLSession`
    ///     of the capability.
    ///   - resolver: the resolver of the address guard. A test gives a
    ///     stub, thus no lookup goes to the network.
    @discardableResult
    func withWeb(
        configuration: WebConfiguration,
        sessionConfiguration: URLSessionConfiguration,
        resolver: any HostResolver
    ) -> Self {
        let capability = WebCapability(
            configuration: configuration, sessionConfiguration: sessionConfiguration, resolver: resolver)
        return withCapability(capability, replacing: { $0 is WebCapability })
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
            await serverPool.add(server: server)
        }
        return self
    }
}
