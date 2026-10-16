import Foundation
import FoundationModelsExtras
import ULID

// MARK: - The elicitation globals, from one declarative table
//
// Each sandbox global that asks the user a question is one row of
// ``MultiTool/elicitationGlobals``. The row is the single source of the
// global: the host function that it installs, its `docs(name)` block, its
// lines on the `docs("globals")` page, and the usage text of its argument
// errors are all made from the row. Thus the documentation and the installed
// global cannot drift apart.
//
// Each row goes the same path at call time: the session context, then the
// question of the row (``ElicitationGlobal/makeQuestion``), then
// `ToolContext.elicit`, then ``ElicitationQuestion/renderAnswer(_:)``. An
// argument error throws before the request goes to the user.
//
// A headless session installs no row and documents no row (see
// ``MultiTool/asksUser(_:)``).

/// One parameter of the declaration of an elicitation global.
struct ElicitationParameter: Sendable {
    /// The name of the parameter in the declaration.
    let name: String

    /// The TypeScript type of the parameter.
    let tsType: String

    /// Tells if a snippet can leave the parameter out.
    let isOptional: Bool

    /// The parameter as the declaration writes it, for example
    /// `options?: { min?: number }`.
    var declaration: String {
        "\(name)\(isOptional ? "?" : ""): \(tsType)"
    }
}

/// One call shape of an elicitation global.
struct ElicitationSignature: Sendable {
    /// The parameters, in call order.
    let parameters: [ElicitationParameter]

    /// The TypeScript type of the `content` of an accepted answer.
    let contentType: String
}

/// Why the arguments of one call to an elicitation global are not a
/// question that the global can ask.
///
/// The host function of the global changes it to a ``SandboxGlobalError``
/// that carries the usage text of the global.
enum ElicitationArgumentError: Error, Equatable {
    /// The arguments do not have the shape of a call to the global.
    case malformed

    /// The arguments have the shape of a call, but a value in them is not a
    /// request that the restricted MCP elicitation subset accepts.
    case undecodable(reason: String)
}

/// The question that one call to an elicitation global asks, and how the
/// content of an accepted answer goes back to the snippet.
struct ElicitationQuestion: Sendable {
    /// The request that goes to the user.
    let request: ElicitationRequest

    /// Converts the content of an accepted answer to the value that the
    /// snippet reads as `content`.
    let renderContent: @Sendable ([String: ElicitationValue]?) -> InterpreterValue

    /// Renders the answer of the user for the snippet.
    ///
    /// The object always has the three keys `action`, `content`, and
    /// `reason`. `content` is the rendered content of an accept, and `null`
    /// for a decline or a cancel. `reason` is the reason of a decline or a
    /// cancel, and `null` when the response has no reason. Thus `action`
    /// alone tells the three actions apart, and a read of `content` or
    /// `reason` never finds an undefined property.
    ///
    /// - Parameter response: the answer of the user.
    /// - Returns: the JS-visible answer object.
    func renderAnswer(_ response: ElicitationResponse) -> InterpreterValue {
        .object([
            "action": .string(response.action.rawValue),
            "content": response.action == .accept ? renderContent(response.content) : .null,
            "reason": response.reason.map { .string($0) } ?? .null,
        ])
    }

    /// Converts one elicitation content value to its JS-visible equivalent.
    ///
    /// - Parameter value: the answered value.
    /// - Returns: the equivalent interpreter value.
    static func renderValue(_ value: ElicitationValue) -> InterpreterValue {
        switch value {
        case .string(let text): .string(text)
        case .number(let number): .number(number)
        case .boolean(let flag): .bool(flag)
        case .stringArray(let items): .array(items.map { .string($0) })
        }
    }
}

/// One row of the table of elicitation globals.
struct ElicitationGlobal: Sendable {
    /// The name a snippet calls the global by.
    let name: String

    /// What the global does, as the lines of the JSDoc comment of its block.
    /// The lines are separated by `"\n"`.
    let summary: String

    /// The repair text of an argument error: the call shapes that the global
    /// takes.
    let usage: String

    /// One line of snippet code that calls the global.
    let example: String

    /// The call shapes of the global. Each one gives one declaration.
    let signatures: [ElicitationSignature]

    /// Makes the question of one call from the arguments of the call.
    ///
    /// A fresh `elicitationId` is minted for each question, never taken from
    /// the snippet: it is the key the run plane holds the continuation
    /// under, and a snippet-chosen id could collide with a pending one.
    let makeQuestion: @Sendable ([InterpreterValue]) throws(ElicitationArgumentError) -> ElicitationQuestion

    /// The text that opens the JSDoc line of the return value of each block.
    private static let returnsTag = "@returns"

    /// The text that opens the JSDoc line of the example of each block.
    private static let exampleTag = "@example"

    /// The name of the TypeScript type that each elicitation global resolves
    /// to.
    static let answerTypeName = "ElicitationAnswer"

    /// What each block says about the answer, after its return type.
    private static let answerNote = """
        `content` is null when the user declined or cancelled, so read `action` first. \
        `reason` is the reason of a decline or a cancel, for example \
        "\(RunPlane.runCancelledReason)", the decline text of a client, or \
        "\(ElicitationRequestedSchema.invalidAnswerReasonPrefix)…"; else it is null.
        """

    /// The `docs(name)` entry of the global.
    var doc: SandboxGlobalDoc {
        let summaryLines = summary.split(separator: "\n", omittingEmptySubsequences: false)
        let comment = ["/**"]
            + summaryLines.map { " * \($0)" }
            + [
                " * \(Self.returnsTag) Promise<\(Self.answerTypeName)> — \(Self.answerNote)",
                " * \(Self.exampleTag) \(example)",
                " */",
            ]
        return SandboxGlobalDoc(name: name, block: (["// \(name)"] + comment + declarations).joined(separator: "\n"))
    }

    /// The `declare function` line of each call shape.
    private var declarations: [String] {
        signatures.map { signature in
            let parameters = signature.parameters.map(\.declaration).joined(separator: ", ")
            return "declare function \(name)(\(parameters)): Promise<\(Self.answerTypeName)>;"
        }
    }

    /// Builds the host function of the global for one `runCode` invocation.
    ///
    /// The one path of each elicitation global: the session context, then
    /// the question, then `ToolContext.elicit`, then the rendered answer. An
    /// argument error throws before the request goes to the user.
    ///
    /// - Parameter binding: the captured session binding of the invocation,
    ///   or `nil` when it has none — then the call rejects with
    ///   ``SandboxGlobalError/noSession``.
    /// - Returns: the async host function, named ``name``.
    func makeHostFunction(binding: RunBinding?) -> AsyncHostFunction {
        AsyncHostFunction(name: name) { [self] arguments in
            let context = try MultiTool.sessionContext(from: binding)
            let asked = try question(for: arguments)
            return asked.renderAnswer(try await context.elicit(asked.request))
        }
    }

    /// Makes the question of one call, and gives an argument error the usage
    /// text of this global.
    ///
    /// - Parameter arguments: the arguments of the call.
    /// - Returns: the question.
    /// - Throws: ``SandboxGlobalError/malformedElicitationRequest(usage:)`` or
    ///   ``SandboxGlobalError/undecodableElicitationRequest(reason:usage:)``.
    private func question(for arguments: [InterpreterValue]) throws -> ElicitationQuestion {
        do throws(ElicitationArgumentError) {
            return try makeQuestion(arguments)
        } catch {
            switch error {
            case .malformed:
                throw SandboxGlobalError.malformedElicitationRequest(usage: usage)
            case .undecodable(let reason):
                throw SandboxGlobalError.undecodableElicitationRequest(reason: reason, usage: usage)
            }
        }
    }
}

extension MultiTool {
    /// The table of elicitation globals, in page order. `elicit` is the first
    /// row.
    static let elicitationGlobals: [ElicitationGlobal] = [elicitGlobal]

    /// The `docs(name)` entries of the elicitation globals.
    static var elicitationGlobalDocs: [SandboxGlobalDoc] {
        elicitationGlobals.map(\.doc)
    }

    /// The sections that the elicitation globals add to the
    /// `docs("globals")` page, in page order.
    static var elicitationPageSections: [String] {
        elicitationGlobalDocs.map(\.block)
    }

    /// The `declare type` line of the answer that each elicitation global
    /// resolves to. The type of `content` is the content type of `elicit`.
    static var elicitationAnswerDeclaration: String {
        let contentType = elicitGlobal.signatures.map(\.contentType).joined(separator: " | ")
        return "declare type \(ElicitationGlobal.answerTypeName) = "
            + "{ action: \"accept\" | \"decline\" | \"cancel\"; content: \(contentType) | null; reason: string | null };"
    }

    /// Builds the host function of each elicitation global for one `runCode`
    /// invocation.
    ///
    /// - Parameter binding: the captured session binding of the invocation.
    /// - Returns: one async host function for each row of
    ///   ``elicitationGlobals``.
    static func makeElicitationHostFunctions(binding: RunBinding?) -> [AsyncHostFunction] {
        elicitationGlobals.map { $0.makeHostFunction(binding: binding) }
    }

    // MARK: - elicit()

    /// The usage text of each malformed `elicit()` call.
    static let elicitUsage = """
        elicit("question") takes a question string, or a request object — \
        elicit({ message, requestedSchema }) for a form, \
        elicit({ message, url }) for a URL flow.
        """

    /// The TypeScript type of the `content` of an accepted `elicit()` answer.
    private static let elicitContentType = "object"

    /// The row of `elicit()`, the general question.
    static let elicitGlobal = ElicitationGlobal(
        name: elicitGlobalName,
        summary: """
            Asks the user a question in the middle of a snippet, and resolves to their
            answer. \(elicitUsage)
            """,
        usage: elicitUsage,
        example: "const answer = await elicit(\"Which repository should I target?\");",
        signatures: [
            ElicitationSignature(
                parameters: [
                    ElicitationParameter(
                        name: "request",
                        tsType: "string | { message: string; requestedSchema?: object; url?: string }",
                        isOptional: false)
                ],
                contentType: elicitContentType)
        ],
        makeQuestion: { arguments throws(ElicitationArgumentError) in
            try makeElicitQuestion(from: arguments.first)
        })

    /// Makes the question of one `elicit()` call.
    ///
    /// A bare string is the shorthand eventplan.md § "The sandbox globals"
    /// shows (`await elicit("Which repository should I target?")`): a
    /// form-mode request with a message and no fields to fill in. An object
    /// carries the full restricted MCP shape, decoded by the
    /// `ElicitationRequestedSchema` of FoundationModelsExtras so this boundary
    /// enforces exactly the subset every other elicitor does — a snippet
    /// cannot widen it. The content of an accept is the object of the filled
    /// fields, and `null` for a URL flow.
    ///
    /// - Parameter argument: the first argument of the call.
    /// - Returns: the question.
    /// - Throws: ``ElicitationArgumentError/malformed`` when the argument is
    ///   neither a question string nor an object with a `message`;
    ///   ``ElicitationArgumentError/undecodable(reason:)`` when its `url` is
    ///   not a URL or its `requestedSchema` is outside the subset.
    private static func makeElicitQuestion(
        from argument: InterpreterValue?
    ) throws(ElicitationArgumentError) -> ElicitationQuestion {
        ElicitationQuestion(request: try makeElicitRequest(from: argument)) { content in
            content.map { .object($0.mapValues(ElicitationQuestion.renderValue)) } ?? .null
        }
    }

    /// Builds the typed request of one `elicit()` call.
    ///
    /// - Parameter argument: the first argument of the call.
    /// - Returns: the typed request.
    /// - Throws: see ``makeElicitQuestion(from:)``.
    private static func makeElicitRequest(
        from argument: InterpreterValue?
    ) throws(ElicitationArgumentError) -> ElicitationRequest {
        let elicitationId = ULID()
        if case .string(let question)? = argument {
            return ElicitationRequest(
                message: question,
                elicitationId: elicitationId,
                requestedSchema: ElicitationRequestedSchema(properties: [:])
            )
        }
        guard case .object(let fields)? = argument, case .string(let message)? = fields["message"] else {
            throw .malformed
        }
        if case .string(let urlText)? = fields["url"] {
            guard let url = URL(string: urlText) else {
                throw .undecodable(reason: "\"\(urlText)\" is not a URL")
            }
            return ElicitationRequest(message: message, elicitationId: elicitationId, url: url)
        }
        return ElicitationRequest(
            message: message,
            elicitationId: elicitationId,
            requestedSchema: try decodeRequestedSchema(fields["requestedSchema"])
        )
    }

    /// Decodes a form request's `requestedSchema` through the `Codable`
    /// conformance of the `ElicitationRequestedSchema` of
    /// FoundationModelsExtras, so the restricted MCP subset is enforced by the
    /// one implementation that defines it.
    ///
    /// - Parameter value: the `requestedSchema` field, or `nil`/`null` for a
    ///   message-only form — the same request the string shorthand produces.
    /// - Returns: the decoded schema.
    /// - Throws: ``ElicitationArgumentError/undecodable(reason:)`` when the
    ///   value is outside the subset.
    private static func decodeRequestedSchema(
        _ value: InterpreterValue?
    ) throws(ElicitationArgumentError) -> ElicitationRequestedSchema {
        guard let value, value != .null else {
            return ElicitationRequestedSchema(properties: [:])
        }
        do {
            return try JSONDecoder().decode(
                ElicitationRequestedSchema.self,
                from: try JSONEncoder().encode(value)
            )
        } catch {
            throw .undecodable(reason: "\(error)")
        }
    }
}
