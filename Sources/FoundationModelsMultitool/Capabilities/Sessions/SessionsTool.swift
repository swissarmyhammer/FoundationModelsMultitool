// `SessionsTool` — the `sessions` tool: the operations that find, check,
// read, message, start, tag, rename and archive the sessions of the server
// through a `SessionDirectory` (session.md sections 8 and 14, MT-2 and MT-9).
//
// The tool has the shape of the `agents` tool of FoundationModelsAgents: a
// public struct that holds an `OperationTool` of its operations. A host gives
// the same instance as a top-level tool of the session and to
// `MultiTool.Builder.withSessions(_:)`, which mounts each operation as
// `tools.sessions.<verb>` (D76).

import Foundation
import FoundationModels
import FoundationModelsExtras
import Operations

/// The `sessions` tool: find the sessions of the server, check one of them,
/// read the messages that other sessions sent to the caller session, send a
/// message and reply to one, start a new session, tag, untag and rename a
/// session, and archive a session.
///
/// The operations are `list sessions`, `check session`, `read inbox`,
/// `send message`, `reply message`, `start session`, `tag session`,
/// `untag session`, `rename session` and `archive session`. In code mode each
/// one is a verb of `tools.sessions`: `listSessions`, `checkSession`,
/// `readInbox`, `sendMessage`, `replyMessage`, `startSession`, `tagSession`,
/// `untagSession`, `renameSession` and `archiveSession`. Each answer is plain
/// text, and each error is a corrective text the model reads in the same
/// turn, never a thrown error.
///
/// The caller session is `ToolContext.current?.sessionID`. A call with no
/// `ToolContext` reads the directory, but each operation that acts for the
/// caller — `read inbox`, each message and each change — then gives a
/// corrective.
///
/// **The tool is a value type, and a host copies it** (EXTRAS-9 rule 1): to
/// the top-level tools of a session, to the registry of `runCode`, and to a
/// forked session. Each copy shares the directory that ``init(directory:)``
/// gets, and the record of the messages that `read inbox` gave, which
/// ``init(directory:)`` makes one time and `reply message` reads. A later
/// part that must be shared — the `sessions` GraphQL endpoint and its change
/// log — is made one time for each directory, never for each copy, so
/// ``init(directory:)`` keeps its shape.
public struct SessionsTool: Tool, OperationDescribing {
    /// The raw payload: an `op` and the fields of one operation.
    public typealias Arguments = GeneratedContent

    /// The answer of the operation, or a corrective text.
    public typealias Output = String

    /// The model-facing name of the tool, and the noun of its verbs in code
    /// mode.
    static let toolName = "sessions"

    /// The tool that resolves and dispatches each call.
    let operationTool: OperationTool<SessionsToolContext>

    /// Makes the `sessions` tool over `directory`.
    ///
    /// - Parameter directory: The session directory that each operation
    ///   reads. The Router gives the real one; a test gives an
    ///   `InMemorySessionDirectory`.
    /// - Throws: The error of `OperationTool.init` when the schema of the
    ///   operations cannot be fused.
    public init(directory: any SessionDirectory) throws {
        operationTool = try OperationTool(
            name: Self.toolName,
            description: SessionsToolText.toolDescription,
            context: SessionsToolContext(directory: directory),
            operations: [
                AnyOperation(ListSessions.self),
                AnyOperation(CheckSession.self),
                AnyOperation(ReadInbox.self),
                AnyOperation(SendMessage.self),
                AnyOperation(ReplyMessage.self),
                AnyOperation(StartSession.self),
                AnyOperation(TagSession.self),
                AnyOperation(UntagSession.self),
                AnyOperation(RenameSession.self),
                AnyOperation(ArchiveSession.self),
            ],
            resolver: OperationResolver(verbAliases: Self.verbAliases))
    }

    /// The verb aliases of the tool over the default aliases of the
    /// resolver: `read` stays `read`. The default table makes `read` the
    /// verb `get`, and then `read inbox` names no operation.
    static let verbAliases: [String: String] = [
        ReadInbox.verb: ReadInbox.verb
    ]

    /// The model-facing name of the tool: `sessions`.
    public var name: String {
        operationTool.name
    }

    /// The description that the model reads.
    public var description: String {
        operationTool.description
    }

    /// The fused schema of the operations.
    public var parameters: GenerationSchema {
        operationTool.parameters
    }

    /// Whether FoundationModels puts ``parameters`` into the prompt. The same
    /// value as the operation tool.
    public var includesSchemaInInstructions: Bool {
        operationTool.includesSchemaInInstructions
    }

    /// One descriptor for each operation, in tool order. The registry of
    /// `runCode` mounts one verb for each.
    public var operationDescriptors: [OperationDescriptor] {
        operationTool.operationDescriptors
    }

    /// Resolves `arguments` to one operation and dispatches it.
    ///
    /// - Parameter arguments: The payload of the model.
    /// - Returns: The plain-text answer of the operation, or a corrective
    ///   text.
    /// - Throws: The error of `OperationTool.call(arguments:)`.
    public func call(arguments: GeneratedContent) async throws -> String {
        Self.plainText(of: try await operationTool.call(arguments: arguments))
    }

    /// Dispatches one operation for a host, as a `runCode` verb does.
    ///
    /// - Parameter arguments: The payload with the `op` key and the fields of
    ///   one operation.
    /// - Returns: The plain-text answer of the operation, or a corrective
    ///   text.
    /// - Throws: The refusal of `OperationTool.perform(_:)` for a payload
    ///   that names no operation or lacks a required field.
    public func perform(_ arguments: GeneratedContent) async throws -> String {
        Self.plainText(of: try await operationTool.perform(arguments))
    }

    /// The plain text of an answer of the operation tool.
    ///
    /// The operation tool encodes the text of each operation as a JSON
    /// string. A refusal of its resolver is plain text already, and stays as
    /// it is.
    ///
    /// - Parameter answer: The answer of the operation tool.
    /// - Returns: The plain text.
    private static func plainText(of answer: String) -> String {
        (try? JSONDecoder().decode(String.self, from: Data(answer.utf8))) ?? answer
    }
}
