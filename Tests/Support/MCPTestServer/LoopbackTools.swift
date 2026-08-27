// `LoopbackTools` — the three tools the MCP suites cite by name.
//
// This file has no source in `../FoundationModelsMCP`. The three names are
// coined here, and the later MCP tasks cite them: the elicitation host
// handler task drives `elicitEcho` and `elicitURL`, and the in-process HTTP
// loopback task serves all three over HTTP. Test support — see the header
// of `ScriptedServer.swift`.

import MCP

extension ScriptedServer {
    /// The name of the form-mode eliciting loopback tool: it elicits a form
    /// mid-call and reflects the answer in its result. Registered by
    /// ``addLoopbackTools()`` through
    /// ``addElicitingTool(named:message:requestedSchema:preElicitationDelay:postElicitationStall:)``.
    ///
    /// A name this package coins; the source had no fixed name for the tool.
    public static let elicitEchoToolName = "elicitEcho"

    /// The name of the URL-mode eliciting loopback tool: the three-message
    /// URL flow — `elicitation/create` in URL mode, the answer of the client,
    /// and ``sendElicitationComplete(elicitationId:)`` to end it. Registered
    /// by ``addLoopbackTools()`` through
    /// ``addURLElicitingTool(named:message:url:elicitationId:)``.
    ///
    /// A name this package coins; the source had no fixed name for the tool.
    public static let elicitURLToolName = "elicitURL"

    /// The prompt ``elicitEchoToolName`` shows the user.
    public static let elicitEchoMessage = "What is the answer?"

    /// The one field ``elicitEchoToolName`` requests, and the key under which
    /// its `structuredContent` reflects the answer.
    public static let elicitEchoAnswerField = "answer"

    /// The `requestedSchema` ``elicitEchoToolName`` sends: one required
    /// string field, ``elicitEchoAnswerField``.
    public static let elicitEchoRequestedSchema = Elicitation.RequestSchema(
        properties: [elicitEchoAnswerField: .object(["type": .string("string")])],
        required: [elicitEchoAnswerField]
    )

    /// The prompt ``elicitURLToolName`` shows the user.
    public static let elicitURLMessage = "Complete the sign-in in your browser."

    /// The link ``elicitURLToolName`` sends the user to. An `example.com`
    /// address: no test opens it.
    public static let elicitURLLink = "https://example.com/loopback/sign-in"

    /// The `elicitationId` ``elicitURLToolName`` carries, and the id
    /// ``sendElicitationComplete(elicitationId:)`` names to end the flow.
    public static let elicitURLElicitationId = "loopback-elicitation"

    /// The three loopback tool names, in registration order.
    public static let loopbackToolNames = [echoToolName, elicitEchoToolName, elicitURLToolName]

    /// Registers the three loopback tools at once: ``echoToolName``,
    /// ``elicitEchoToolName`` and ``elicitURLToolName``.
    ///
    /// The set a later MCP task reaches whether the server is scripted
    /// in-process, spawned as `mcp-test-server --mode loopback`, or served
    /// over the in-process HTTP loopback.
    public func addLoopbackTools() {
        addEchoTool()
        addElicitingTool(
            named: Self.elicitEchoToolName,
            message: Self.elicitEchoMessage,
            requestedSchema: Self.elicitEchoRequestedSchema
        )
        addURLElicitingTool(
            named: Self.elicitURLToolName,
            message: Self.elicitURLMessage,
            url: Self.elicitURLLink,
            elicitationId: Self.elicitURLElicitationId
        )
    }
}
