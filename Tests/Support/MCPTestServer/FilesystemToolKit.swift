// `FilesystemToolKit` — a three-tool filesystem mode over an in-memory store.
//
// A behavioral port of
// `../FoundationModelsMCP/Sources/MCPTestServer/FilesystemToolKit.swift`.
// Test support — see the header of `ScriptedServer.swift`.

import MCP

/// A minimal in-memory file store behind the filesystem-style multi-tool
/// mode of ``ScriptedServer``.
///
/// Not the real filesystem, on purpose: a scripted scenario needs
/// deterministic, disposable state per test, not sandboxing or real I/O.
public actor VirtualFilesystem {
    /// The stored files, path to content.
    private var files: [String: String]

    /// Creates a virtual filesystem seeded with `initialFiles`.
    ///
    /// - Parameter initialFiles: The starting path-to-content map. Defaults
    ///   to empty.
    public init(initialFiles: [String: String] = [:]) {
        self.files = initialFiles
    }

    /// Every stored path, sorted for a deterministic listing.
    ///
    /// - Returns: The stored paths, sorted.
    public func listPaths() -> [String] {
        files.keys.sorted()
    }

    /// Reads the content of one file.
    ///
    /// - Parameter path: The path to read.
    /// - Returns: The content, or `nil` when `path` does not exist.
    public func read(path: String) -> String? {
        files[path]
    }

    /// Writes (creates or overwrites) the content of one file.
    ///
    /// - Parameters:
    ///   - path: The path to write.
    ///   - content: The new content.
    public func write(path: String, content: String) {
        files[path] = content
    }
}

extension ScriptedServer {
    /// The name of the tool that lists every path.
    public static let listFilesToolName = "list_files"

    /// The name of the tool that reads one file.
    public static let readFileToolName = "read_file"

    /// The name of the tool that writes one file.
    public static let writeFileToolName = "write_file"

    /// The three filesystem tool names, in registration order.
    public static let filesystemToolNames = [listFilesToolName, readFileToolName, writeFileToolName]

    /// The `path` argument of the read and write tools.
    private static let pathArgument = "path"

    /// The `content` argument of the write tool.
    private static let contentArgument = "content"

    /// Registers the filesystem-style multi-tool mode over a fresh
    /// ``VirtualFilesystem``: ``listFilesToolName``, ``readFileToolName``
    /// and ``writeFileToolName``.
    ///
    /// - Parameter initialFiles: The starting path-to-content map of the
    ///   backing ``VirtualFilesystem``. Defaults to empty.
    /// - Returns: The backing ``VirtualFilesystem``, so a test can seed or
    ///   inspect it directly beside driving it through `tools/call`.
    @discardableResult
    public func addFilesystemTools(initialFiles: [String: String] = [:]) -> VirtualFilesystem {
        let filesystem = VirtualFilesystem(initialFiles: initialFiles)
        addListFilesTool(filesystem: filesystem)
        addReadFileTool(filesystem: filesystem)
        addWriteFileTool(filesystem: filesystem)
        return filesystem
    }

    /// Registers ``listFilesToolName``, which lists every path in
    /// `filesystem`.
    ///
    /// - Parameter filesystem: The backing virtual filesystem.
    private func addListFilesTool(filesystem: VirtualFilesystem) {
        addScriptedTool(
            name: Self.listFilesToolName,
            description: "Lists every path in the virtual filesystem.",
            inputSchema: JSONSchemaBuilder.emptySchema
        ) { _ in
            let paths = await filesystem.listPaths()
            return CallTool.Result(
                content: [
                    .text(text: paths.joined(separator: "\n"), annotations: nil, _meta: nil)
                ]
            )
        }
    }

    /// Registers ``readFileToolName``, which reads one file of `filesystem`.
    ///
    /// - Parameter filesystem: The backing virtual filesystem.
    private func addReadFileTool(filesystem: VirtualFilesystem) {
        addScriptedTool(
            name: Self.readFileToolName,
            description: "Reads one file's content from the virtual filesystem.",
            inputSchema: JSONSchemaBuilder.object(
                properties: [Self.pathArgument: JSONSchemaBuilder.string()], required: [Self.pathArgument])
        ) { params in
            guard let path = params.arguments?[Self.pathArgument]?.stringValue else {
                throw MCPError.invalidParams("\(Self.readFileToolName) requires a \"\(Self.pathArgument)\" argument")
            }
            guard let content = await filesystem.read(path: path) else {
                return CallTool.Result(
                    content: [
                        .text(text: "No such file: \(path)", annotations: nil, _meta: nil)
                    ],
                    isError: true
                )
            }
            return CallTool.Result(
                content: [.text(text: content, annotations: nil, _meta: nil)])
        }
    }

    /// Registers ``writeFileToolName``, which writes (creates or overwrites)
    /// one file of `filesystem`.
    ///
    /// - Parameter filesystem: The backing virtual filesystem.
    private func addWriteFileTool(filesystem: VirtualFilesystem) {
        addScriptedTool(
            name: Self.writeFileToolName,
            description: "Writes (creating or overwriting) one file in the virtual filesystem.",
            inputSchema: JSONSchemaBuilder.object(
                properties: [
                    Self.pathArgument: JSONSchemaBuilder.string(),
                    Self.contentArgument: JSONSchemaBuilder.string(),
                ],
                required: [Self.pathArgument, Self.contentArgument]
            )
        ) { params in
            guard let path = params.arguments?[Self.pathArgument]?.stringValue,
                let content = params.arguments?[Self.contentArgument]?.stringValue
            else {
                throw MCPError.invalidParams(
                    "\(Self.writeFileToolName) requires \"\(Self.pathArgument)\" and \"\(Self.contentArgument)\" arguments")
            }
            await filesystem.write(path: path, content: content)
            return CallTool.Result(
                content: [.text(text: "wrote \(path)", annotations: nil, _meta: nil)])
        }
    }
}
