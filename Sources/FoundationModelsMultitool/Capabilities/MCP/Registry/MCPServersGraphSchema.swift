// The Graphiti schema of the `mcpServers` GraphQL endpoint.

import Foundation
import FoundationModelsExtras
import Graphiti
import GraphQL

/// The Graphiti engine of the `mcpServers` endpoint.
struct MCPServersGraphAPI: API {
    /// The schema, built once. The context of a call holds the registry.
    static let builtSchema = Result { try makeSchema() }

    /// The root resolver.
    let resolver = MCPServersGraphResolver()

    /// The schema.
    let schema: Schema<MCPServersGraphResolver, MCPServersGraphContext>

    /// One type of the schema.
    typealias SchemaType = TypeComponent<MCPServersGraphResolver, MCPServersGraphContext>

    /// One root field of the schema.
    typealias SchemaField = FieldComponent<MCPServersGraphResolver, MCPServersGraphContext>

    /// The text of the name argument of a server.
    private static let nameDescription = "The name of the MCP server."

    /// The text of the secret inputs.
    private static let secretDescription =
        "Secret values. Each goes to the Keychain of this Mac, and the server keeps only its keychain: reference."

    /// Builds the schema.
    ///
    /// - Returns: The schema.
    /// - Throws: An error of the schema builder.
    private static func makeSchema() throws -> Schema<MCPServersGraphResolver, MCPServersGraphContext> {
        try SchemaBuilder(MCPServersGraphResolver.self, MCPServersGraphContext.self)
            .addToolkitScalars()
            .addToolkitIDScalar()
            .add {
                transportEnum()
                changeKindEnum()
                settingType()
                serverType()
                changeType()
                settingInput()
                addInput()
                updateInput()
                removeInput()
                enableInput()
            }
            .addQuery {
                Field("mcpServers", at: MCPServersGraphResolver.mcpServers)
                    .description("The MCP servers of this Mac, in their stored order.")
                Field("mcpServer", at: MCPServersGraphResolver.mcpServer) {
                    Argument("name", at: \.name).description(nameDescription)
                }
                .description("One MCP server, or null when no server has the name.")
                Field("cursor", at: MCPServersGraphResolver.cursor)
                    .description(
                        "The cursor of the newest change. Read the servers, then subscribe to changes after it.")
            }
            .addMutation {
                Field("addMCPServer", at: MCPServersGraphResolver.addMCPServer) {
                    Argument("input", at: \.input).description("The new server.")
                }
                .description("Adds one MCP server after the others. Gives the server.")
                Field("updateMCPServer", at: MCPServersGraphResolver.updateMCPServer) {
                    Argument("input", at: \.input).description("The server and the fields to change.")
                }
                .description(
                    "Changes the given fields of one MCP server in its place: a rename, the command, the url, and "
                        + "the other fields. A field that is not given does not change. Gives the server.")
                Field("removeMCPServer", at: MCPServersGraphResolver.removeMCPServer) {
                    Argument("input", at: \.input).description("The server.")
                }
                .description("Removes one MCP server. Gives the server as it was.")
                Field("setMCPServerEnabled", at: MCPServersGraphResolver.setMCPServerEnabled) {
                    Argument("input", at: \.input).description("The server and its new switch.")
                }
                .description("Turns one MCP server on or off. Gives the server.")
            }
            .addSubscription {
                SubscriptionField(
                    "changes",
                    at: { (entry: ChangeLogEntry<MCPServerChange>) in
                        { (_: MCPServersGraphContext, _: MCPServersGraphChangesArguments) async throws
                            -> MCPServersGraphChange in
                            MCPServersGraphChange(entry)
                        }
                    },
                    atSub: MCPServersGraphResolver.changes
                ) {
                    Argument("after", at: \.after)
                        .description("The cursor to resume after, from the cursor query or a change. None: from now.")
                }
                .description(
                    "The changes of the MCP servers after a cursor, one server each. RESYNC_REQUIRED ends it when a "
                        + "change after the cursor is lost: read the servers and the cursor again, then subscribe.")
            }
            .build()
    }

    // MARK: Enums

    /// The `MCPServerTransport` enum.
    ///
    /// - Returns: The enum.
    private static func transportEnum() -> SchemaType {
        Enum(MCPServersGraphTransport.self, as: "MCPServerTransport") {
            Value(.stdio).description("A program on this Mac that speaks MCP on stdio.")
            Value(.http).description("A remote endpoint that speaks MCP over http or https.")
        }
        .description("How the host reaches an MCP server.")
    }

    /// The `MCPServerChangeKind` enum.
    ///
    /// - Returns: The enum.
    private static func changeKindEnum() -> SchemaType {
        Enum(MCPServersGraphChangeKind.self, as: "MCPServerChangeKind") {
            Value(.added).description("A new server.")
            Value(.updated).description("A changed server: a rename, a switch or another field.")
            Value(.removed).description("A removed server.")
        }
        .description("The kind of a change of an MCP server.")
    }

    // MARK: Object types

    /// The `MCPServerSetting` type.
    ///
    /// - Returns: The type.
    private static func settingType() -> SchemaType {
        Type(MCPServersGraphSetting.self, as: "MCPServerSetting") {
            Field("name", at: \.name).description("The name of the env variable or the header.")
            Field("value", at: \.value).description("The value. For a secret, its keychain: reference.")
            Field("secret", at: \.secret).description("True when the value is a keychain: reference.")
        }
        .description("One env variable or one header of an MCP server.")
    }

    /// The `MCPServer` type.
    ///
    /// - Returns: The type.
    private static func serverType() -> SchemaType {
        Type(MCPServersGraphServer.self, as: "MCPServer") {
            Field("name", at: \.name).description("The name: the id of the server and the noun of its tools.")
            Field("enabled", at: \.enabled).description("True when the host connects the server.")
            Field("transport", at: \.transport).description("How the host reaches the server.")
            Field("command", at: \.command).description("The absolute path of the program (STDIO), or null.")
            Field("args", at: \.args).description("The arguments of the program (STDIO).")
            Field("env", at: \.env).description("The env variables of the program (STDIO), sorted by name.")
            Field("url", at: \.url).description("The url of the endpoint (HTTP), or null.")
            Field("headers", at: \.headers).description("The headers of each request (HTTP), sorted by name.")
        }
        .description("One MCP server of this Mac.")
    }

    /// The `MCPServerChange` type.
    ///
    /// - Returns: The type.
    private static func changeType() -> SchemaType {
        Type(MCPServersGraphChange.self, as: "MCPServerChange") {
            Field("cursor", at: \.cursor).description("The cursor that resumes the subscription after this change.")
            Field("at", at: \.at).description("The time of the change.")
            Field("kind", at: \.kind).description("The kind of the change.")
            Field("name", at: \.name).description("The name of the server after the change.")
            Field("previousName", at: \.previousName)
                .description("The name of the server before the change. It differs after a rename.")
            Field("server", at: \.server).description("The server after the change, or as it was before a remove.")
            Field("added", at: \.added).description("The name of the server that the change added, or none.")
            Field("changed", at: \.changed)
                .description("The name of the server that the change changed, after a rename too, or none.")
            Field("removed", at: \.removed).description("The name of the server that the change removed, or none.")
        }
        .description("One change of one MCP server, with the whole server, so a client updates one row.")
    }

    // MARK: Input objects

    /// The `MCPServerSettingInput` input object.
    ///
    /// - Returns: The input object.
    private static func settingInput() -> SchemaType {
        Input(MCPServersGraphSettingInput.self, as: "MCPServerSettingInput") {
            InputField("name", at: \.name).description("The name of the env variable or the header.")
            InputField("value", at: \.value).description("The value.")
        }
        .description("One env variable or one header.")
    }

    /// The `AddMCPServerInput` input object.
    ///
    /// - Returns: The input object.
    private static func addInput() -> SchemaType {
        Input(MCPServersGraphAddInput.self, as: "AddMCPServerInput") {
            InputField("name", at: \.name).description(MCPServerRegistry.nameRule)
            InputField("command", at: \.command).description("STDIO: the absolute path of the program.")
            InputField("args", at: \.args).description("STDIO: the arguments of the program.")
            InputField("env", at: \.env).description("STDIO: the plain env values. Give a secret in envSecrets.")
            InputField("url", at: \.url).description("HTTP: the http or https url.")
            InputField("headers", at: \.headers)
                .description(
                    "HTTP: the headers. Each value must be a keychain: reference. Give a token in headerSecrets.")
            InputField("headerSecrets", at: \.headerSecrets).description("HTTP: \(secretDescription)")
            InputField("envSecrets", at: \.envSecrets).description("STDIO: \(secretDescription)")
            InputField("enabled", at: \.enabled).defaultValue(true).description("True to connect the server.")
        }
        .description("A new MCP server: give a command (STDIO) or a url (HTTP), not both.")
    }

    /// The `UpdateMCPServerInput` input object.
    ///
    /// - Returns: The input object.
    private static func updateInput() -> SchemaType {
        Input(MCPServersGraphUpdateInput.self, as: "UpdateMCPServerInput") {
            InputField("name", at: \.name).description(nameDescription)
            InputField("newName", at: \.newName).description("The new name.")
            InputField("command", at: \.command)
                .description("The new program. On an HTTP server, it changes the server to STDIO.")
            InputField("args", at: \.args).description("The new arguments.")
            InputField("env", at: \.env).description("The new plain env values: they replace the whole env.")
            InputField("url", at: \.url).description("The new url. On a STDIO server, it changes the server to HTTP.")
            InputField("headers", at: \.headers).description("The new headers: they replace all headers.")
            InputField("headerSecrets", at: \.headerSecrets).description(secretDescription)
            InputField("envSecrets", at: \.envSecrets).description(secretDescription)
            InputField("enabled", at: \.enabled).description("The new switch.")
        }
        .description("The fields of one MCP server to change. A field that is not given does not change.")
    }

    /// The `RemoveMCPServerInput` input object.
    ///
    /// - Returns: The input object.
    private static func removeInput() -> SchemaType {
        Input(MCPServersGraphRemoveInput.self, as: "RemoveMCPServerInput") {
            InputField("name", at: \.name).description(nameDescription)
        }
        .description("The MCP server to remove.")
    }

    /// The `SetMCPServerEnabledInput` input object.
    ///
    /// - Returns: The input object.
    private static func enableInput() -> SchemaType {
        Input(MCPServersGraphEnableInput.self, as: "SetMCPServerEnabledInput") {
            InputField("name", at: \.name).description(nameDescription)
            InputField("enabled", at: \.enabled).description("True to turn the server on, false to turn it off.")
        }
        .description("One MCP server and its new switch.")
    }
}
