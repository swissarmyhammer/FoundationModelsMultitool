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
// The first row is `elicit()`, the general question. The other rows are the
// helpers `elicit.confirm`, `elicit.choose`, `elicit.chooseMany`,
// `elicit.askText` and `elicit.askNumber`. Each helper, and the text short
// form `elicit("question")`, sends a form with one required field, `answer`,
// and an accept gives the plain value of that field as `content`. The host
// function of a helper installs under its dotted name. The preamble then
// moves it onto the `elicit` function as a property that a snippet cannot
// write, delete or configure, and removes the dotted global (see
// ``MultiTool/elicitationPreamble``). The preamble is made one time for
// each registry, thus the move has a gate in JS: it occurs only when the
// sandbox has the `elicit` function.
//
// A headless session installs no row and documents no row (see
// ``MultiTool/asksUser(_:)``). A call to a helper there gets the same
// `ReferenceError` on `elicit`, and thus the same hint, as a call to
// `elicit()`.

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

    /// The character between the namespace and the member in the name of a
    /// helper, as in `elicit.confirm`.
    static let memberSeparator: Character = "."

    /// The text that indents each member line of a `declare namespace` block.
    private static let memberIndent = "  "

    /// The namespace that holds the global, for example `elicit` for
    /// `elicit.confirm`, or `nil` for a global of its own, as `elicit` is.
    var namespace: String? {
        name.firstIndex(of: Self.memberSeparator).map { String(name[..<$0]) }
    }

    /// The name of the global in its namespace, for example `confirm` for
    /// `elicit.confirm`. For a global of its own, the whole name.
    var memberName: String {
        name.firstIndex(of: Self.memberSeparator).map { String(name[name.index(after: $0)...]) } ?? name
    }

    /// The `docs(name)` entry of the global.
    var doc: SandboxGlobalDoc {
        let summaryLines = summary.split(separator: "\n", omittingEmptySubsequences: false)
        let comment = ["/**"]
            + summaryLines.map { " * \($0)" }
            + [
                " * \(Self.returnsTag) \(answerType(of: signatures)) — \(Self.answerNote)",
                " * \(Self.exampleTag) \(example)",
                " */",
            ]
        return SandboxGlobalDoc(name: name, block: (["// \(name)"] + comment + declarations).joined(separator: "\n"))
    }

    /// The `function` line of each call shape, with no `declare`: the line
    /// that a `declare namespace` block holds, for example
    /// `function confirm(message: string): Promise<ElicitationAnswer<boolean>>;`.
    var memberDeclarations: [String] {
        signatures.map { signature in
            let parameters = signature.parameters.map(\.declaration).joined(separator: ", ")
            return "function \(memberName)(\(parameters)): \(answerType(of: [signature]));"
        }
    }

    /// The declaration lines of the block of the global: a `declare function`
    /// line for each call shape of a global of its own, or a
    /// `declare namespace` block for a helper.
    var declarations: [String] {
        guard let namespace else {
            return memberDeclarations.map { "declare \($0)" }
        }
        return Self.namespaceDeclaration(namespace, members: memberDeclarations)
    }

    /// The return type of the global for some of its call shapes, for example
    /// `Promise<ElicitationAnswer<boolean>>`.
    ///
    /// - Parameter shapes: the call shapes whose content types the type
    ///   joins.
    /// - Returns: the TypeScript return type.
    private func answerType(of shapes: [ElicitationSignature]) -> String {
        "Promise<\(Self.answerTypeName)<\(shapes.map(\.contentType).joined(separator: " | "))>>"
    }

    /// The `declare namespace` block that holds some member lines.
    ///
    /// - Parameters:
    ///   - namespace: the name of the namespace.
    ///   - members: the member lines, each one a ``memberDeclarations`` line.
    /// - Returns: the lines of the block.
    static func namespaceDeclaration(_ namespace: String, members: [String]) -> [String] {
        ["declare namespace \(namespace) {"] + members.map { "\(memberIndent)\($0)" } + ["}"]
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
    /// row, and the helpers follow it.
    static let elicitationGlobals: [ElicitationGlobal] = [
        elicitGlobal, confirmGlobal, chooseGlobal, chooseManyGlobal, askTextGlobal, askNumberGlobal,
    ]

    /// The `docs(name)` entries of the elicitation globals.
    static var elicitationGlobalDocs: [SandboxGlobalDoc] {
        elicitationGlobals.map(\.doc)
    }

    /// The sections that the elicitation globals add to the
    /// `docs("globals")` page, in page order: one section.
    ///
    /// The section gives one declaration line for each elicitation global: a
    /// `declare function` line for each global of its own, and a
    /// `declare namespace` block with one line for each helper. The return
    /// cap of `runCode` has no room for the whole blocks, thus each whole
    /// block is in its `docs(name)` entry only. One comment line opens the
    /// section: it tells how to read an answer, and where the whole blocks
    /// are.
    static var elicitationPageSections: [String] {
        let ownGlobals = elicitationGlobals.filter { $0.namespace == nil }
        let blockNames = ownGlobals.map(\.name)
            + elicitationNamespaces.map { "\($0)\(ElicitationGlobal.memberSeparator)<name>" }
        let comment = "// Read `action` first: `content` is null unless the user accepted. "
            + blockNames.map { "docs(\"\($0)\")" }.joined(separator: " and ") + " give the full text."
        let namespaceBlocks = elicitationNamespaces.flatMap { namespace in
            ElicitationGlobal.namespaceDeclaration(
                namespace, members: elicitationHelpers(in: namespace).flatMap(\.memberDeclarations))
        }
        return [([comment] + ownGlobals.flatMap(\.declarations) + namespaceBlocks).joined(separator: "\n")]
    }

    /// The namespaces that hold helpers, in table order, each one time.
    private static var elicitationNamespaces: [String] {
        let namespaces = elicitationGlobals.compactMap(\.namespace)
        return namespaces.enumerated()
            .filter { namespaces.firstIndex(of: $0.element) == $0.offset }
            .map(\.element)
    }

    /// The helpers of one namespace, in table order.
    ///
    /// - Parameter namespace: the name of the namespace.
    /// - Returns: the rows whose namespace is `namespace`.
    private static func elicitationHelpers(in namespace: String) -> [ElicitationGlobal] {
        elicitationGlobals.filter { $0.namespace == namespace }
    }

    /// The `declare type` line of the answer that each elicitation global
    /// resolves to. Its type parameter is the type of `content` on an accept:
    /// each declaration names it.
    static var elicitationAnswerDeclaration: String {
        "declare type \(ElicitationGlobal.answerTypeName)<T> = "
            + "{ action: \"accept\" | \"decline\" | \"cancel\"; content: T | null; reason: string | null };"
    }

    /// The preamble line that moves the host function of each helper onto its
    /// namespace function, or an empty string when the table has no helper.
    ///
    /// A host function installs as a global under its dotted name, for
    /// example `globalThis["elicit.confirm"]`. For each helper, the line
    /// defines the member on the namespace function with
    /// `Object.defineProperty`, which makes it not writable and not
    /// configurable, and then deletes the dotted global. Thus a snippet
    /// cannot replace or delete a helper, and `globalThis` has no dotted
    /// name. The preamble is made one time for each registry, and the
    /// sandbox of a headless session has no namespace function. Thus the
    /// line moves a helper only when both functions are in the sandbox.
    ///
    /// The names come from the table, and each one is a JS identifier, thus
    /// they are safe to put in the JS source.
    static var elicitationPreamble: String {
        elicitationNamespaces.map { namespace in
            let members = elicitationHelpers(in: namespace).map { "\"\($0.memberName)\"" }.joined(separator: ", ")
            return "(function (owner, members) { for (const member of members) { "
                + "const key = \"\(namespace)\(ElicitationGlobal.memberSeparator)\" + member; "
                + "if (typeof owner === \"function\" && typeof globalThis[key] === \"function\") { "
                + "Object.defineProperty(owner, member, { value: globalThis[key], enumerable: true }); } "
                + "delete globalThis[key]; } })(globalThis.\(namespace), [\(members)]);"
        }
        .joined(separator: " ")
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
        elicit("question") asks for a text: on an accept, content is the text. \
        elicit({ message, requestedSchema }) asks with a form: on an accept, \
        content is the object of the fields. elicit({ message, url }) starts a URL flow.
        """

    /// The TypeScript type of the `content` of an accepted `elicit()` answer:
    /// the text of the short form, or the object of a request object.
    private static let elicitContentType = "string | object"

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
    /// form-mode request with one required free-text field,
    /// ``elicitationAnswerField``, as `elicit.askText` sends. The content of
    /// its accept is the text. An object carries the full restricted MCP
    /// shape, decoded by the `ElicitationRequestedSchema` of
    /// FoundationModelsExtras so this boundary enforces exactly the subset
    /// every other elicitor does — a snippet cannot widen it. The content of
    /// its accept is the object of the filled fields, and `null` for a URL
    /// flow.
    ///
    /// - Parameter argument: the first argument of the call.
    /// - Returns: the question.
    /// - Throws: ``ElicitationArgumentError/malformed`` when the argument is
    ///   neither a question string nor an object with a `message`;
    ///   ``ElicitationArgumentError/undecodable(reason:)`` when its `url` is
    ///   not a string or not an absolute `http` or `https` URL, or its
    ///   `requestedSchema` is outside the subset.
    private static func makeElicitQuestion(
        from argument: InterpreterValue?
    ) throws(ElicitationArgumentError) -> ElicitationQuestion {
        if case .string(let question)? = argument {
            return makeHelperQuestion(message: question, field: .string(ElicitationStringSchema()))
        }
        return ElicitationQuestion(request: try makeElicitRequest(from: argument)) { content in
            content.map { .object($0.mapValues(ElicitationQuestion.renderValue)) } ?? .null
        }
    }

    /// Builds the typed request of one `elicit()` call with a request object.
    ///
    /// - Parameter argument: the first argument of the call.
    /// - Returns: the typed request.
    /// - Throws: see ``makeElicitQuestion(from:)``.
    private static func makeElicitRequest(
        from argument: InterpreterValue?
    ) throws(ElicitationArgumentError) -> ElicitationRequest {
        let elicitationId = ULID()
        guard case .object(let fields)? = argument, case .string(let message)? = fields["message"] else {
            throw .malformed
        }
        if let url = try decodeElicitURL(fields["url"]) {
            return ElicitationRequest(message: message, elicitationId: elicitationId, url: url)
        }
        return ElicitationRequest(
            message: message,
            elicitationId: elicitationId,
            requestedSchema: try decodeRequestedSchema(fields["requestedSchema"])
        )
    }

    /// The reason of a `url` that is not a string.
    private static let elicitURLNotAStringReason = "the url must be a string"

    /// Decodes the `url` field of an `elicit()` request object.
    ///
    /// The URL rule is ``Fetch/httpURL(_:)``: an absolute `http` or `https`
    /// URL with a host. Thus a relative text, such as `"foo"`, and another
    /// scheme, such as `"javascript:x"`, give an argument error before a
    /// request goes to the user.
    ///
    /// - Parameter value: the `url` field, or `nil`/`null` for a form request.
    /// - Returns: the URL, or `nil` when the request has no `url`.
    /// - Throws: ``ElicitationArgumentError/undecodable(reason:)`` when the
    ///   value is not a string, or not an absolute `http` or `https` URL.
    private static func decodeElicitURL(_ value: InterpreterValue?) throws(ElicitationArgumentError) -> URL? {
        guard let value, value != .null else {
            return nil
        }
        guard case .string(let urlText) = value else {
            throw .undecodable(reason: elicitURLNotAStringReason)
        }
        guard let url = Fetch.httpURL(urlText) else {
            throw .undecodable(reason: "\"\(urlText)\" is not an absolute http or https URL")
        }
        return url
    }

    /// Decodes a form request's `requestedSchema` through the `Codable`
    /// conformance of the `ElicitationRequestedSchema` of
    /// FoundationModelsExtras, so the restricted MCP subset is enforced by the
    /// one implementation that defines it.
    ///
    /// - Parameter value: the `requestedSchema` field, or `nil`/`null` for a
    ///   message-only form, which is a free answer.
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

// MARK: - The helpers: elicit.confirm, choose, chooseMany, askText, askNumber

extension MultiTool {
    /// The one field of the form that each helper and `elicit("question")`
    /// send. An accept gives the value of this field, and no more, as
    /// `content`.
    static let elicitationAnswerField = "answer"

    /// The `message` parameter, which each helper takes first.
    private static let messageParameter = ElicitationParameter(name: "message", tsType: "string", isOptional: false)

    /// The `options` parameter of `choose` and `chooseMany`.
    private static let optionsParameter = ElicitationParameter(name: "options", tsType: "string[]", isOptional: false)

    /// The settings of the options object of `chooseMany`.
    private static let chooseManySettings: [ElicitationHelperSetting] = [.min, .max]

    /// The settings of the options object of `askText`.
    private static let askTextSettings: [ElicitationHelperSetting] = [.format, .pattern]

    /// The settings of the options object of `askNumber`.
    private static let askNumberSettings: [ElicitationHelperSetting] = [.min, .max, .integer]

    /// The name of `elicit.confirm`.
    private static let confirmName = helperName("confirm")

    /// The name of `elicit.choose`.
    private static let chooseName = helperName("choose")

    /// The name of `elicit.chooseMany`.
    private static let chooseManyName = helperName("chooseMany")

    /// The name of `elicit.askText`.
    private static let askTextName = helperName("askText")

    /// The name of `elicit.askNumber`.
    private static let askNumberName = helperName("askNumber")

    /// The usage text of `elicit.confirm`.
    private static let confirmUsage = "\(confirmName)(message) asks a yes-or-no question. "
        + "On an accept, content is true or false."

    /// The usage text of `elicit.choose`.
    private static let chooseUsage = "\(chooseName)(message, options) asks the user to pick one of options, "
        + "an array of one or more different strings. On an accept, content is the picked string."

    /// The usage text of `elicit.chooseMany`.
    private static let chooseManyUsage =
        "\(chooseManyName)(message, options, \(settingsShape(chooseManySettings))) asks the user to pick "
        + "some of options, an array of one or more different strings. min and max are whole numbers that "
        + "limit the count of picks, and min is not more than the count of options. On an accept, content is "
        + "the array of picked strings."

    /// The usage text of `elicit.askText`.
    private static let askTextUsage = "\(askTextName)(message, \(settingsShape(askTextSettings))) asks for a text. "
        + "format is one of \(ElicitationHelperSetting.format.tsType). pattern is a regular expression "
        + "that the whole text must match. On an accept, content is the text."

    /// The usage text of `elicit.askNumber`.
    private static let askNumberUsage =
        "\(askNumberName)(message, \(settingsShape(askNumberSettings))) asks for a number. min and max "
        + "limit the number, and integer: true asks for a whole number. With integer: true, a whole number "
        + "must be between min and max. On an accept, content is the number."

    /// The row of `elicit.confirm()`: a yes-or-no question.
    static let confirmGlobal = ElicitationGlobal(
        name: confirmName,
        summary: "Asks the user a yes-or-no question, and resolves to their answer.\n\(confirmUsage)",
        usage: confirmUsage,
        example: "const answer = await \(confirmName)(\"Delete the branch?\");",
        signatures: [ElicitationSignature(parameters: [messageParameter], contentType: "boolean")],
        makeQuestion: { arguments throws(ElicitationArgumentError) in
            let call = ElicitationHelperArguments(arguments)
            return makeHelperQuestion(message: try call.message(), field: .boolean(ElicitationBooleanSchema()))
        })

    /// The row of `elicit.choose()`: a pick of one option.
    static let chooseGlobal = ElicitationGlobal(
        name: chooseName,
        summary: "Asks the user to pick one option, and resolves to their answer.\n\(chooseUsage)",
        usage: chooseUsage,
        example: "const answer = await \(chooseName)(\"Which region?\", [\"us\", \"eu\"]);",
        signatures: [ElicitationSignature(parameters: [messageParameter, optionsParameter], contentType: "string")],
        makeQuestion: { arguments throws(ElicitationArgumentError) in
            let call = ElicitationHelperArguments(arguments)
            let message = try call.message()
            let field = ElicitationSingleSelectSchema(values: try call.options())
            return makeHelperQuestion(message: message, field: .singleSelect(field))
        })

    /// The row of `elicit.chooseMany()`: a pick of some options.
    static let chooseManyGlobal = ElicitationGlobal(
        name: chooseManyName,
        summary: "Asks the user to pick some options, and resolves to their answer.\n\(chooseManyUsage)",
        usage: chooseManyUsage,
        example: "const answer = await \(chooseManyName)(\"Which checks?\", [\"lint\", \"test\"], { min: 1 });",
        signatures: [
            ElicitationSignature(
                parameters: [messageParameter, optionsParameter, settingsParameter("limits", chooseManySettings)],
                contentType: "string[]")
        ],
        makeQuestion: { arguments throws(ElicitationArgumentError) in
            let call = ElicitationHelperArguments(arguments)
            let message = try call.message()
            let options = try call.options()
            let limits = try call.settings(at: .afterOptions, allowing: chooseManySettings)
                .countRange(ofPicksFrom: options.count)
            let field = ElicitationMultiSelectSchema(values: options, minItems: limits.minimum, maxItems: limits.maximum)
            return makeHelperQuestion(message: message, field: .multiSelect(field))
        })

    /// The row of `elicit.askText()`: a question with a text answer.
    static let askTextGlobal = ElicitationGlobal(
        name: askTextName,
        summary: "Asks the user for a text, and resolves to their answer.\n\(askTextUsage)",
        usage: askTextUsage,
        example: "const answer = await \(askTextName)(\"Which email address?\", { format: \"email\" });",
        signatures: [
            ElicitationSignature(
                parameters: [messageParameter, settingsParameter("constraints", askTextSettings)],
                contentType: "string")
        ],
        makeQuestion: { arguments throws(ElicitationArgumentError) in
            let call = ElicitationHelperArguments(arguments)
            let message = try call.message()
            let constraints = try call.settings(at: .afterMessage, allowing: askTextSettings)
            let field = ElicitationStringSchema(format: try constraints.format(), pattern: try constraints.pattern())
            return makeHelperQuestion(message: message, field: .string(field))
        })

    /// The row of `elicit.askNumber()`: a question with a number answer.
    static let askNumberGlobal = ElicitationGlobal(
        name: askNumberName,
        summary: "Asks the user for a number, and resolves to their answer.\n\(askNumberUsage)",
        usage: askNumberUsage,
        example: "const answer = await \(askNumberName)(\"How many retries?\", { min: 0, max: 5, integer: true });",
        signatures: [
            ElicitationSignature(
                parameters: [messageParameter, settingsParameter("limits", askNumberSettings)],
                contentType: "number")
        ],
        makeQuestion: { arguments throws(ElicitationArgumentError) in
            let call = ElicitationHelperArguments(arguments)
            let message = try call.message()
            let field = try call.settings(at: .afterMessage, allowing: askNumberSettings).numberSchema()
            return makeHelperQuestion(message: message, field: .number(field))
        })

    /// The name of a helper in the `elicit` namespace.
    ///
    /// - Parameter member: the name of the helper in the namespace, for
    ///   example `confirm`.
    /// - Returns: the dotted name, for example `elicit.confirm`.
    private static func helperName(_ member: String) -> String {
        "\(elicitGlobalName)\(ElicitationGlobal.memberSeparator)\(member)"
    }

    /// The usage text of an options object, for example `{ min, max }?`.
    ///
    /// - Parameter settings: the settings of the object.
    /// - Returns: the text.
    private static func settingsShape(_ settings: [ElicitationHelperSetting]) -> String {
        "{ \(settings.map(\.rawValue).joined(separator: ", ")) }?"
    }

    /// The optional options-object parameter of a helper, for example
    /// `limits?: { min?: number; max?: number }`.
    ///
    /// - Parameters:
    ///   - name: the name of the parameter in the declaration.
    ///   - settings: the settings of the object.
    /// - Returns: the parameter.
    private static func settingsParameter(_ name: String, _ settings: [ElicitationHelperSetting]) -> ElicitationParameter {
        let fields = settings.map { "\($0.rawValue)?: \($0.tsType)" }.joined(separator: "; ")
        return ElicitationParameter(name: name, tsType: "{ \(fields) }", isOptional: true)
    }

    /// Makes the question of one helper call, or of one `elicit("question")`
    /// call: a form with the one required field ``elicitationAnswerField``.
    /// An accept gives the value of that field as `content`.
    ///
    /// `ToolContext.elicit` checks an accepted answer against the form, and
    /// changes an answer that is not valid to a decline. Thus an accept
    /// always holds the field.
    ///
    /// - Parameters:
    ///   - message: the question.
    ///   - field: the schema of the `answer` field.
    /// - Returns: the question.
    private static func makeHelperQuestion(message: String, field: ElicitationPrimitiveSchema) -> ElicitationQuestion {
        let schema = ElicitationRequestedSchema(
            properties: [elicitationAnswerField: field], required: [elicitationAnswerField])
        let request = ElicitationRequest(message: message, elicitationId: ULID(), requestedSchema: schema)
        return ElicitationQuestion(request: request) { content in
            content?[elicitationAnswerField].map(ElicitationQuestion.renderValue) ?? .null
        }
    }
}

/// One setting of the options object of an elicitation helper. The raw value
/// is the key that a snippet writes.
enum ElicitationHelperSetting: String, Sendable {
    /// The lower limit: a count of picks, or a number.
    case min

    /// The upper limit: a count of picks, or a number.
    case max

    /// Tells if `askNumber` asks for a whole number.
    case integer

    /// The string format of the answer of `askText`.
    case format

    /// The regular expression that the whole answer of `askText` must match.
    case pattern

    /// The string formats that ``format`` takes, in the order that the docs
    /// list them.
    static let textFormats: [ElicitationStringFormat] = [.email, .uri, .date, .dateTime]

    /// The TypeScript type of the setting.
    var tsType: String {
        switch self {
        case .min, .max: "number"
        case .integer: "boolean"
        case .format: Self.textFormats.map { "\"\($0.rawValue)\"" }.joined(separator: " | ")
        case .pattern: "string"
        }
    }
}

/// The arguments of one call to an elicitation helper.
///
/// Each read throws ``ElicitationArgumentError/malformed`` when an argument
/// does not have the shape that the helper takes, and
/// ``ElicitationArgumentError/undecodable(reason:)`` when a value has the
/// shape but cannot go in the form. A `null` or `undefined` argument is the
/// same as an argument that the call leaves out.
struct ElicitationHelperArguments {
    /// Where the options object of a helper is in its arguments.
    enum SettingsPosition: Int {
        /// Right after the message, as in `elicit.askText(message, { format })`.
        case afterMessage = 1

        /// After the message and the options, as in
        /// `elicit.chooseMany(message, options, { min })`.
        case afterOptions = 2
    }

    /// The position of the message in the arguments.
    private static let messagePosition = 0

    /// The position of the options of `choose` and `chooseMany`.
    private static let optionsPosition = 1

    /// The arguments of the call, in call order.
    private let values: [InterpreterValue]

    /// Makes a reader of the arguments of one call.
    ///
    /// - Parameter values: the arguments of the call, in call order.
    init(_ values: [InterpreterValue]) {
        self.values = values
    }

    /// The question: the first argument, a string.
    ///
    /// - Returns: the question.
    /// - Throws: ``ElicitationArgumentError/malformed`` when the first
    ///   argument is not a string.
    func message() throws(ElicitationArgumentError) -> String {
        guard case .string(let message)? = value(at: Self.messagePosition) else { throw .malformed }
        return message
    }

    /// The options: the second argument, an array of one or more different
    /// strings.
    ///
    /// The user cannot tell two options with the same text apart, and a pick
    /// of `chooseMany` holds each option one time only. Thus the options must
    /// be different strings.
    ///
    /// - Returns: the options, in call order.
    /// - Throws: ``ElicitationArgumentError/malformed`` when the argument is
    ///   not an array of strings; ``ElicitationArgumentError/undecodable(reason:)``
    ///   when the array is empty, or when it holds the same string two times.
    func options() throws(ElicitationArgumentError) -> [String] {
        guard case .array(let items)? = value(at: Self.optionsPosition) else { throw .malformed }
        let options = items.compactMap { item -> String? in
            guard case .string(let option) = item else { return nil }
            return option
        }
        guard options.count == items.count else { throw .malformed }
        guard !options.isEmpty else { throw .undecodable(reason: "options must hold one or more strings") }
        guard Set(options).count == options.count else {
            throw .undecodable(reason: "options must be different strings")
        }
        return options
    }

    /// The options object of the call. An absent object has no settings.
    ///
    /// - Parameters:
    ///   - position: where the object is in the arguments.
    ///   - allowed: the settings that the helper takes.
    /// - Returns: the settings that the object gives, without the `null` ones.
    /// - Throws: ``ElicitationArgumentError/malformed`` when the argument is
    ///   not an object; ``ElicitationArgumentError/undecodable(reason:)`` when
    ///   it has a key that is not in `allowed`.
    func settings(
        at position: SettingsPosition, allowing allowed: [ElicitationHelperSetting]
    ) throws(ElicitationArgumentError) -> ElicitationHelperSettings {
        guard let argument = value(at: position.rawValue) else { return ElicitationHelperSettings(values: [:]) }
        guard case .object(let fields) = argument else { throw .malformed }
        let allowedKeys = Set(allowed.map(\.rawValue))
        for key in fields.keys.sorted() where !allowedKeys.contains(key) {
            throw .undecodable(reason: "\"\(key)\" is not a setting of this call")
        }
        let given = fields.compactMap { key, value -> (ElicitationHelperSetting, InterpreterValue)? in
            guard let setting = ElicitationHelperSetting(rawValue: key), value != .null else { return nil }
            return (setting, value)
        }
        return ElicitationHelperSettings(values: Dictionary(uniqueKeysWithValues: given))
    }

    /// The argument at `position`.
    ///
    /// - Parameter position: the position in the arguments.
    /// - Returns: the argument, or `nil` when the call gives none there or
    ///   gives `null`.
    private func value(at position: Int) -> InterpreterValue? {
        guard values.indices.contains(position), values[position] != .null else { return nil }
        return values[position]
    }
}

/// The settings that the options object of one helper call gives.
struct ElicitationHelperSettings {
    /// The value of each setting that the object gives.
    let values: [ElicitationHelperSetting: InterpreterValue]

    /// The ``ElicitationHelperSetting/min`` and ``ElicitationHelperSetting/max``
    /// counts of a pick from some different options.
    ///
    /// - Parameter optionCount: the count of options that the user picks
    ///   from. No pick holds more options than this count.
    /// - Returns: each count, or `nil` for a count that the object does not
    ///   give.
    /// - Throws: ``ElicitationArgumentError/undecodable(reason:)`` when a
    ///   count is not a whole number, 0 or more, when `min` is more than
    ///   `max`, or when `min` is more than `optionCount`.
    func countRange(
        ofPicksFrom optionCount: Int
    ) throws(ElicitationArgumentError) -> (minimum: Int?, maximum: Int?) {
        let range = try range(count)
        try Self.checkPickable(minimum: range.minimum, from: optionCount)
        return range
    }

    /// The schema of a number: the ``ElicitationHelperSetting/min`` and
    /// ``ElicitationHelperSetting/max`` limits, and the
    /// ``ElicitationHelperSetting/integer`` flag.
    ///
    /// - Returns: the schema. A limit that the object does not give is `nil`
    ///   in the schema.
    /// - Throws: ``ElicitationArgumentError/undecodable(reason:)`` when a
    ///   limit is not a finite number, when `min` is more than `max`, when
    ///   `integer` is not `true` or `false`, or when `integer` is `true` and
    ///   no whole number is between `min` and `max`.
    func numberSchema() throws(ElicitationArgumentError) -> ElicitationNumberSchema {
        let range = try range(number)
        guard try flag(.integer) == true else {
            return ElicitationNumberSchema(type: .number, minimum: range.minimum, maximum: range.maximum)
        }
        try Self.checkHoldsWholeNumber(range.minimum, range.maximum)
        return ElicitationNumberSchema(type: .integer, minimum: range.minimum, maximum: range.maximum)
    }

    /// The value of a true-or-false setting.
    ///
    /// - Parameter setting: the setting.
    /// - Returns: the value, or `nil` when the object does not give it.
    /// - Throws: ``ElicitationArgumentError/undecodable(reason:)`` when the
    ///   value is not `true` or `false`.
    func flag(_ setting: ElicitationHelperSetting) throws(ElicitationArgumentError) -> Bool? {
        try value(of: setting, mustBe: "true or false", Self.boolPayload(of:))
    }

    /// The ``ElicitationHelperSetting/format`` setting.
    ///
    /// - Returns: the format, or `nil` when the object does not give one.
    /// - Throws: ``ElicitationArgumentError/undecodable(reason:)`` when the
    ///   value is not one of ``ElicitationHelperSetting/textFormats``.
    func format() throws(ElicitationArgumentError) -> ElicitationStringFormat? {
        guard let name = try text(.format) else { return nil }
        guard let format = ElicitationHelperSetting.textFormats.first(where: { $0.rawValue == name }) else {
            throw .undecodable(reason: "format \"\(name)\" is not one of \(ElicitationHelperSetting.format.tsType)")
        }
        return format
    }

    /// The ``ElicitationHelperSetting/pattern`` setting.
    ///
    /// - Returns: the regular expression, or `nil` when the object does not
    ///   give one.
    /// - Throws: ``ElicitationArgumentError/undecodable(reason:)`` when the
    ///   value is not a regular expression that compiles.
    func pattern() throws(ElicitationArgumentError) -> String? {
        guard let pattern = try text(.pattern) else { return nil }
        guard (try? NSRegularExpression(pattern: pattern)) != nil else {
            throw .undecodable(reason: "pattern \"\(pattern)\" is not a valid regular expression")
        }
        return pattern
    }

    /// The value of a count setting.
    ///
    /// - Parameter setting: the setting.
    /// - Returns: the count, or `nil` when the object does not give it.
    /// - Throws: ``ElicitationArgumentError/undecodable(reason:)`` when the
    ///   value is not a whole number, 0 or more.
    private func count(_ setting: ElicitationHelperSetting) throws(ElicitationArgumentError) -> Int? {
        let requirement = "a whole number, 0 or more"
        guard let number = try value(of: setting, mustBe: requirement, Self.numberPayload(of:)) else { return nil }
        guard let count = Int(exactly: number), count >= 0 else {
            throw Self.mismatch(of: setting, mustBe: requirement)
        }
        return count
    }

    /// The value of a number setting.
    ///
    /// - Parameter setting: the setting.
    /// - Returns: the number, or `nil` when the object does not give it.
    /// - Throws: ``ElicitationArgumentError/undecodable(reason:)`` when the
    ///   value is not a finite number.
    private func number(_ setting: ElicitationHelperSetting) throws(ElicitationArgumentError) -> Double? {
        let requirement = "a number"
        guard let number = try value(of: setting, mustBe: requirement, Self.numberPayload(of:)) else { return nil }
        guard number.isFinite else { throw Self.mismatch(of: setting, mustBe: requirement) }
        return number
    }

    /// The value of a string setting.
    ///
    /// - Parameter setting: the setting.
    /// - Returns: the string, or `nil` when the object does not give it.
    /// - Throws: ``ElicitationArgumentError/undecodable(reason:)`` when the
    ///   value is not a string.
    private func text(_ setting: ElicitationHelperSetting) throws(ElicitationArgumentError) -> String? {
        try value(of: setting, mustBe: "a string", Self.stringPayload(of:))
    }

    /// The ``ElicitationHelperSetting/min`` and ``ElicitationHelperSetting/max``
    /// limits, each read with `read`.
    ///
    /// - Parameter read: the typed reader of one limit, for example ``count(_:)``.
    /// - Returns: each limit, or `nil` for a limit that the object does not
    ///   give.
    /// - Throws: what `read` throws, or
    ///   ``ElicitationArgumentError/undecodable(reason:)`` when `min` is more
    ///   than `max`.
    private func range<Bound: Comparable>(
        _ read: (ElicitationHelperSetting) throws(ElicitationArgumentError) -> Bound?
    ) throws(ElicitationArgumentError) -> (minimum: Bound?, maximum: Bound?) {
        let range = (minimum: try read(.min), maximum: try read(.max))
        try Self.checkOrder(range.minimum, range.maximum)
        return range
    }

    /// The typed value of a setting.
    ///
    /// - Parameters:
    ///   - setting: the setting.
    ///   - requirement: what the value must be, for the error text, for
    ///     example `a string`.
    ///   - extract: gives the typed value of a raw value, or `nil` when the
    ///     raw value has a different type.
    /// - Returns: the typed value, or `nil` when the object does not give the
    ///   setting.
    /// - Throws: ``ElicitationArgumentError/undecodable(reason:)`` when
    ///   `extract` gives `nil`.
    private func value<Value>(
        of setting: ElicitationHelperSetting, mustBe requirement: String,
        _ extract: (InterpreterValue) -> Value?
    ) throws(ElicitationArgumentError) -> Value? {
        guard let raw = givenValue(of: setting) else { return nil }
        guard let value = extract(raw) else { throw Self.mismatch(of: setting, mustBe: requirement) }
        return value
    }

    /// The raw value of a setting.
    ///
    /// - Parameter setting: the setting.
    /// - Returns: the value, or `nil` when the object does not give it.
    private func givenValue(of setting: ElicitationHelperSetting) -> InterpreterValue? {
        values[setting]
    }

    /// The error for a setting whose value is not what it must be.
    ///
    /// - Parameters:
    ///   - setting: the setting.
    ///   - requirement: what the value must be, for example `a string`.
    /// - Returns: the error, with the text "`<setting>` must be `<requirement>`".
    private static func mismatch(
        of setting: ElicitationHelperSetting, mustBe requirement: String
    ) -> ElicitationArgumentError {
        .undecodable(reason: "\(setting.rawValue) must be \(requirement)")
    }

    /// The payload of a true-or-false value.
    ///
    /// - Parameter value: the raw value.
    /// - Returns: the payload, or `nil` when `value` is not `true` or `false`.
    private static func boolPayload(of value: InterpreterValue) -> Bool? {
        guard case .bool(let flag) = value else { return nil }
        return flag
    }

    /// The payload of a number value.
    ///
    /// - Parameter value: the raw value.
    /// - Returns: the payload, or `nil` when `value` is not a number.
    private static func numberPayload(of value: InterpreterValue) -> Double? {
        guard case .number(let number) = value else { return nil }
        return number
    }

    /// The payload of a string value.
    ///
    /// - Parameter value: the raw value.
    /// - Returns: the payload, or `nil` when `value` is not a string.
    private static func stringPayload(of value: InterpreterValue) -> String? {
        guard case .string(let text) = value else { return nil }
        return text
    }

    /// Checks that a lower limit is not more than an upper limit.
    ///
    /// - Parameters:
    ///   - minimum: the lower limit, or `nil`.
    ///   - maximum: the upper limit, or `nil`.
    /// - Throws: ``ElicitationArgumentError/undecodable(reason:)`` when both
    ///   limits are given and `minimum` is more than `maximum`.
    private static func checkOrder<Bound: Comparable>(
        _ minimum: Bound?, _ maximum: Bound?
    ) throws(ElicitationArgumentError) {
        guard let minimum, let maximum, minimum > maximum else { return }
        throw .undecodable(
            reason: "\(ElicitationHelperSetting.min.rawValue) is more than \(ElicitationHelperSetting.max.rawValue)")
    }

    /// Checks that a pick can hold the lower limit of its count.
    ///
    /// - Parameters:
    ///   - minimum: the lower limit of the count of picks, or `nil`.
    ///   - optionCount: the count of different options that the user picks
    ///     from.
    /// - Throws: ``ElicitationArgumentError/undecodable(reason:)`` when
    ///   `minimum` is given and is more than `optionCount`.
    private static func checkPickable(minimum: Int?, from optionCount: Int) throws(ElicitationArgumentError) {
        guard let minimum, minimum > optionCount else { return }
        throw .undecodable(reason: "\(ElicitationHelperSetting.min.rawValue) is more than the count of options")
    }

    /// Checks that a whole number is between a lower limit and an upper
    /// limit.
    ///
    /// - Parameters:
    ///   - minimum: the lower limit, or `nil`.
    ///   - maximum: the upper limit, or `nil`.
    /// - Throws: ``ElicitationArgumentError/undecodable(reason:)`` when both
    ///   limits are given and no whole number is between them.
    private static func checkHoldsWholeNumber(_ minimum: Double?, _ maximum: Double?) throws(ElicitationArgumentError) {
        guard let minimum, let maximum, minimum.rounded(.up) > maximum.rounded(.down) else { return }
        throw .undecodable(
            reason: "no whole number is between \(ElicitationHelperSetting.min.rawValue) "
                + "and \(ElicitationHelperSetting.max.rawValue)")
    }
}
