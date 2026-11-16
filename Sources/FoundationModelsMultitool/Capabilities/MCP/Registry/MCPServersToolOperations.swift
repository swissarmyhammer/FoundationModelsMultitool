// The operations of the `mcpServers` tool: `list mcp servers`,
// `show mcp server`, `add mcp server`, `edit mcp server`,
// `remove mcp server`, `enable mcp server` and `disable mcp server`.
//
// Each answer is plain text, and each refusal is a corrective text. A text
// names an env variable or a header, and never shows its value: a value can
// be a secret.

import Foundation
import FoundationModels
import Operations

// MARK: - Read

/// Lists the MCP servers (`list mcp servers`).
@Generable
@Operation(verb: "list", noun: "mcp servers", description: "List the MCP servers of this Mac, with their state.")
struct ListMCPServers {}

extension ListMCPServers {
    /// Lists the servers.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: One line for each server, or the text of no server.
    func execute(in context: MCPServersToolContext) async throws -> String {
        await context.answer {
            let servers = try await context.registry.list()
            guard !servers.isEmpty else {
                return "This Mac has no MCP server. Add one with addMcpServer."
            }
            return servers.map(MCPServersToolText.line).joined(separator: "\n")
        }
    }
}

/// Shows one MCP server (`show mcp server`).
@Generable
@Operation(verb: "show", noun: "mcp server", description: "Show one MCP server.")
struct ShowMCPServer {
    /// The name of the server.
    @Guide(description: "The name of the MCP server.")
    var name: String
}

extension ShowMCPServer {
    /// Shows the server.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: The server, or a corrective for an unknown name.
    func execute(in context: MCPServersToolContext) async throws -> String {
        await context.answer {
            guard let server = try await context.registry.server(named: name) else {
                throw MCPServerRegistryError.unknownServer(name)
            }
            return MCPServersToolText.line(server)
        }
    }
}

// MARK: - Add and edit

/// Adds one MCP server (`add mcp server`).
@Generable
@Operation(
    verb: "add", noun: "mcp server",
    description: """
        Add an MCP server: give a command (a program on this Mac) or a url (a remote server), not both. \
        The user approves it first.
        """)
struct AddMCPServer {
    /// The name of the new server.
    @Guide(description: "The name: lower-case letters, digits, - and _. It is the noun of the tools of the server.")
    var name: String

    /// The stdio command.
    @Guide(description: "Optional. The absolute path of the program, for example /opt/homebrew/bin/npx.")
    var command: String?

    /// The stdio arguments.
    @Guide(description: "Optional. The arguments of the program.")
    var args: [String]?

    /// The plain env values.
    @Guide(description: "Optional. Env variables that are not secret, each as NAME=value.")
    var env: [String]?

    /// The http url.
    @Guide(description: "Optional. The http or https url of a remote MCP server.")
    var url: String?

    /// The headers whose values are secrets.
    @Guide(description: "Optional. The names of the headers that need a secret, for example Authorization.")
    var secretHeaders: [String]?

    /// The env variables whose values are secrets.
    @Guide(description: "Optional. The names of the env variables that need a secret, for example API_TOKEN.")
    var secretEnv: [String]?
}

extension AddMCPServer {
    /// Checks the server, asks the user to approve it, asks the user for
    /// each secret, and adds it.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: The new server, or a corrective.
    func execute(in context: MCPServersToolContext) async throws -> String {
        await context.answer {
            let entry = try MCPServersToolText.entry(name: name, command: command, args: args, env: env, url: url)
            let keys = MCPServersToolText.secretKeys(headers: secretHeaders, env: secretEnv)
            try await context.registry.validate(try entry.setting(references: entry.schemeReferences(of: keys)))
            try await context.requireApproval(MCPServersToolText.approval(adding: entry))
            let references = try await context.registry.requestSecrets(keys, server: name)
            let added = try await context.registry.add(try entry.setting(references: references))
            return "Added MCP server \(MCPServersToolText.line(added))"
        }
    }
}

/// Changes one MCP server (`edit mcp server`).
@Generable
@Operation(
    verb: "edit", noun: "mcp server",
    description: """
        Change the given fields of one MCP server; the other fields stay. A new command, args or url needs the \
        approval of the user.
        """)
struct EditMCPServer {
    /// The name of the server.
    @Guide(description: "The name of the MCP server.")
    var name: String

    /// The new name.
    @Guide(description: "Optional. The new name.")
    var newName: String?

    /// The new stdio command.
    @Guide(description: "Optional. The new absolute path of the program.")
    var command: String?

    /// The new stdio arguments.
    @Guide(description: "Optional. The new arguments: they replace all arguments.")
    var args: [String]?

    /// The new plain env values.
    @Guide(description: "Optional. The new env variables that are not secret, each as NAME=value: they replace all.")
    var env: [String]?

    /// The new http url.
    @Guide(description: "Optional. The new http or https url.")
    var url: String?

    /// The headers that need a new secret.
    @Guide(description: "Optional. The names of the headers that need a new secret.")
    var secretHeaders: [String]?

    /// The env variables that need a new secret.
    @Guide(description: "Optional. The names of the env variables that need a new secret.")
    var secretEnv: [String]?
}

extension EditMCPServer {
    /// Checks the change, asks the user to approve a change of what runs,
    /// asks the user for each secret, and saves.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: The server after the change, or a corrective.
    func execute(in context: MCPServersToolContext) async throws -> String {
        await context.answer {
            let update = MCPServerUpdate(
                name: newName, command: command, args: args, env: try env.map(MCPServersToolText.envMap), url: url)
            let keys = MCPServersToolText.secretKeys(headers: secretHeaders, env: secretEnv)
            let changed = try await context.registry.changed(named: name, with: update)
            _ = try changed.setting(references: changed.schemeReferences(of: keys))
            if update.changesWhatRuns {
                try await context.requireApproval(MCPServersToolText.approval(changing: name, to: changed))
            }
            let references = try await context.registry.requestSecrets(keys, server: changed.name)
            let saved = try await context.registry.update(named: name, with: update, references: references)
            return "Changed MCP server \(MCPServersToolText.line(saved))"
        }
    }
}

// MARK: - Remove and switch

/// Removes one MCP server (`remove mcp server`).
@Generable
@Operation(verb: "remove", noun: "mcp server", description: "Remove one MCP server from this Mac.")
struct RemoveMCPServer {
    /// The name of the server.
    @Guide(description: "The name of the MCP server.")
    var name: String
}

extension RemoveMCPServer {
    /// Removes the server.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: The text of the remove, or a corrective.
    func execute(in context: MCPServersToolContext) async throws -> String {
        await context.answer {
            let removed = try await context.registry.remove(named: name)
            return "Removed MCP server \(removed.name). Its tools go away when the session starts again."
        }
    }
}

/// Turns one MCP server on (`enable mcp server`).
@Generable
@Operation(verb: "enable", noun: "mcp server", description: "Turn on one MCP server: the host connects it.")
struct EnableMCPServer {
    /// The name of the server.
    @Guide(description: "The name of the MCP server.")
    var name: String
}

extension EnableMCPServer {
    /// Turns the server on.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: The server, or a corrective.
    func execute(in context: MCPServersToolContext) async throws -> String {
        await context.answer {
            let server = try await context.registry.setEnabled(true, named: name)
            return "Turned on MCP server \(MCPServersToolText.line(server))"
        }
    }
}

/// Turns one MCP server off (`disable mcp server`).
@Generable
@Operation(verb: "disable", noun: "mcp server", description: "Turn off one MCP server: the host does not connect it.")
struct DisableMCPServer {
    /// The name of the server.
    @Guide(description: "The name of the MCP server.")
    var name: String
}

extension DisableMCPServer {
    /// Turns the server off.
    ///
    /// - Parameter context: The shared context of the tool.
    /// - Returns: The server, or a corrective.
    func execute(in context: MCPServersToolContext) async throws -> String {
        await context.answer {
            let server = try await context.registry.setEnabled(false, named: name)
            return "Turned off MCP server \(MCPServersToolText.line(server))"
        }
    }
}

// MARK: - Text

/// The texts and the argument readers of the `mcpServers` tool.
enum MCPServersToolText {
    /// One line for a server: its name, transport, switch, and what runs.
    /// It names each env variable and header, and shows no value.
    ///
    /// - Parameter server: The server.
    /// - Returns: The line.
    static func line(_ server: MCPServerEntry) -> String {
        let state = server.enabled ? "on" : "off"
        switch server.transport {
        case .stdio(let command, let args, let env):
            let program = ([command] + args).joined(separator: " ")
            return "- \(server.name) (stdio, \(state)): \(program)\(names(" env", env))"
        case .http(let url, let headers):
            return "- \(server.name) (http, \(state)): \(url)\(names(" headers", headers))"
        }
    }

    /// The names of the keys of a map, after a label, or no text.
    ///
    /// - Parameters:
    ///   - label: The label.
    ///   - map: The map.
    /// - Returns: The text.
    private static func names(_ label: String, _ map: [String: String]) -> String {
        map.isEmpty ? "" : ";\(label) \(map.keys.sorted().joined(separator: ", "))"
    }

    /// The approval text of a new server.
    ///
    /// - Parameter entry: The server.
    /// - Returns: The text.
    static func approval(adding entry: MCPServerEntry) -> String {
        "The agent wants to add the MCP server \"\(entry.name)\": \(what(entry)). Approve it?"
    }

    /// The approval text of a change of what a server runs.
    ///
    /// - Parameters:
    ///   - name: The name of the server before the change.
    ///   - entry: The server after the change.
    /// - Returns: The text.
    static func approval(changing name: String, to entry: MCPServerEntry) -> String {
        "The agent wants to change the MCP server \"\(name)\" to: \(what(entry)). Approve it?"
    }

    /// What a server runs or reaches, in words.
    ///
    /// - Parameter entry: The server.
    /// - Returns: The words.
    private static func what(_ entry: MCPServerEntry) -> String {
        switch entry.transport {
        case .stdio(let command, let args, _):
            "it runs the program \(([command] + args).joined(separator: " ")) on this Mac"
        case .http(let url, _):
            "it connects to \(url)"
        }
    }

    /// The entry of the arguments of an add.
    ///
    /// - Parameters:
    ///   - name: The name.
    ///   - command: The stdio command.
    ///   - args: The stdio arguments.
    ///   - env: The plain env values, each as `NAME=value`.
    ///   - url: The http url.
    /// - Returns: The entry.
    /// - Throws: ``MCPServerRegistryError/conflictingTransport(server:)``
    ///   for both or neither of a command and a url, and
    ///   ``MCPServersToolRefusal`` for an env value with no `=`.
    static func entry(
        name: String, command: String?, args: [String]?, env: [String]?, url: String?
    ) throws -> MCPServerEntry {
        switch (command, url) {
        case (let command?, nil):
            return MCPServerEntry(
                name: name, transport: .stdio(command: command, args: args ?? [], env: try envMap(env ?? [])))
        case (nil, let url?) where args == nil && env == nil:
            return MCPServerEntry(name: name, transport: .http(url: url, headers: [:]))
        default:
            throw MCPServerRegistryError.conflictingTransport(server: name)
        }
    }

    /// The map of env values written as `NAME=value`.
    ///
    /// - Parameter pairs: The values.
    /// - Returns: The map.
    /// - Throws: ``MCPServersToolRefusal`` for a value with no `=` or no
    ///   name.
    static func envMap(_ pairs: [String]) throws -> [String: String] {
        var map: [String: String] = [:]
        for pair in pairs {
            guard let separator = pair.firstIndex(of: "="), separator != pair.startIndex else {
                throw MCPServersToolRefusal(text: "Write each env variable as NAME=value. Nothing changed.")
            }
            map[String(pair[..<separator])] = String(pair[pair.index(after: separator)...])
        }
        return map
    }

    /// The secret keys of the names that the model gave.
    ///
    /// - Parameters:
    ///   - headers: The header names.
    ///   - env: The env names.
    /// - Returns: The keys, the headers first.
    static func secretKeys(headers: [String]?, env: [String]?) -> [MCPSecretKey] {
        (headers ?? []).map(MCPSecretKey.header) + (env ?? []).map(MCPSecretKey.env)
    }
}
