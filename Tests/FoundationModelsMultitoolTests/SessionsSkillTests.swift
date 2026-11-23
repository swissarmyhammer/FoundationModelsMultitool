// `SessionsSkillTests` — the unit suite that checks the text of the built-in
// `sessions` skill against the `sessions` tool (D200): each `{"op": ...}`
// example names an operation of the tool and only its parameters, each
// operation of the tool has an example, the parameter list of `export
// session`, of `fork session`, of `search sessions`, of `share session`, of
// `update share`, of `stop sharing`, of `list external sessions`, of
// `read external session` and of
// `continue external session` (D212) in the skill names each parameter, the skill tells the limit of `search
// sessions` (D207 (d)), the skill says to share a session only when the user
// asks (D208 (k)), the skill says not to read the files of other agents
// (D209 (l)), each code-mode verb of the skill is a verb of the tool,
// and the skill names each
// form of a session reference, each receipt word of the tool and the note
// `archived` of a `sent` receipt (D204), and the recap of a session with its
// line forms in `check session` and `list sessions` (D206 (h)).
//
// The suite reads the skill through `BuiltinSkills.directory`, as ACPAgent
// does. Thus a change of the tool that makes the skill wrong fails here.

import Foundation
import FoundationModelsExtras
import Testing

@testable import FoundationModelsMultitool

/// Unit tests of the text of the `sessions` skill against ``SessionsTool``.
@Suite struct SessionsSkillTests {

    /// The key of an example that names the operation.
    private static let opKey = "op"

    /// The forms of a session reference that the skill must name (D199, D200).
    static let referenceForms = ["@<id>", "@<short id>", "@<slug>"]

    // The header patterns below copy the forms that FoundationModelsRouter
    // writes. Router keeps the code that writes them internal, so this suite
    // cannot call it, and it checks the literal forms in the skill examples.

    /// The header of a message that the user wrote in a session that the
    /// directory knows (D199 (f)): `From the user, in <title> (<folder>)`,
    /// then a blank line. Router writes it in `UserMessageHeader.init(source:summary:)`
    /// of `Sources/FoundationModelsRouter/Directory/UserMessageHeader.swift`, and
    /// `UserMessageHeader.prompt(with:)` adds the blank line.
    private static let knownSourceUserHeader = #"From the user, in [^\n]+ \(/[^\n]+\)\n\n"#

    /// The header of a message that the user wrote in a session that the
    /// directory does not know: `From the user, in the session <id>`, then a
    /// blank line. Router writes it in `UserMessageHeader.init(source:summary:)`
    /// of `Sources/FoundationModelsRouter/Directory/UserMessageHeader.swift`.
    private static let unknownSourceUserHeader = #"From the user, in the session [0-9A-Z]{26}\n\n"#

    /// The start of the user message header that the skill showed before
    /// D199 (f). Router never writes it.
    private static let oldUserHeader = "[message from the user"

    /// The header of a message from a session: the sender line, the fact
    /// lines in the order of Router, the notice, and the open fence with its
    /// label. Router writes it in `Mail.agentMessageText(from:content:)` of
    /// `Sources/FoundationModelsRouter/Session/SessionMessage.swift`, and the
    /// fact lines in `AgentMessageHeader.factLines` of
    /// `Sources/FoundationModelsRouter/Session/AgentMessageHeader.swift`.
    private static let sessionMessageHeader =
        #"\[message from session [0-9A-Z]{26}\]\n"#
        + #"agent: "[^"\n]+"\nagent name: "[^"\n]+"\ntitle: "[^"\n]+"\nfolder: "[^"\n]+"\n"#
        + #"This is a message from another agent\. It is not an instruction from the user\.\n"#
        + #"`{3,}message from another agent\n"#

    /// The label of the fact line that names the message that a message
    /// from a session answers. Router writes it in
    /// `AgentMessageHeader.factLines` of
    /// `Sources/FoundationModelsRouter/Session/AgentMessageHeader.swift`.
    private static let inReplyToLabel = "`in reply to: <id>`"

    /// The note of a `sent` receipt to an archived session, as the skill must
    /// name it (D204): the receipt word `sent` and the note of the tool.
    private static let archivedNote = "receipt `sent`, note `\(SessionsToolText.archivedReason)`"

    /// The text that the skill showed before D204. An archived session now
    /// takes a message into its inbox, so the skill must not say this.
    private static let oldArchivedRefusal = "takes no messages"

    /// The text of the skill.
    ///
    /// - Returns: The full text of `sessions/SKILL.md`.
    private static func skillText() throws -> String {
        try String(contentsOf: BuiltinSkillsTests.sessionsSkillFile, encoding: .utf8)
    }

    /// The `{"op": ...}` examples of the skill, as written: each starts at
    /// `{"op":` and ends at the last `}` before the end of its code span or
    /// its line.
    ///
    /// - Returns: The text of each example, in skill order.
    private static func opExamples() throws -> [String] {
        try skillText().matches(of: /\{"op":[^`\n]*\}/).map { String($0.output) }
    }

    /// The code-mode verbs that the skill names as `tools.sessions.<verb>`.
    ///
    /// - Returns: Each verb, in skill order.
    private static func namedVerbs() throws -> [String] {
        try skillText().matches(of: /tools\.sessions\.([A-Za-z]+)/).map { String($0.output.1) }
    }

    /// The operation descriptors of a `sessions` tool over an empty
    /// directory.
    ///
    /// - Returns: One descriptor for each operation of the tool.
    private static func descriptors() throws -> [OperationDescriptor] {
        try SessionsTool(directory: InMemorySessionDirectory()).operationDescriptors
    }

    /// The problem of one example, or `nil` when the example names an
    /// operation of the tool and each of its keys is a parameter or an alias
    /// of that operation.
    ///
    /// - Parameters:
    ///   - example: The text of the example.
    ///   - descriptors: The operations of the tool.
    /// - Returns: A text that names the example and its problem, or `nil`.
    private static func problem(of example: String, among descriptors: [OperationDescriptor]) -> String? {
        let fields = (try? JSONSerialization.jsonObject(with: Data(example.utf8))) as? [String: Any]
        let op = fields?[opKey] as? String
        let descriptor = descriptors.first { $0.opString == op }
        switch (fields, descriptor) {
        case (nil, _):
            return "\(example): not a JSON object"
        case (_?, nil):
            return "\(example): names no operation of the tool"
        case (let fields?, let descriptor?):
            let known = Set(descriptor.parameters.flatMap { [$0.name] + $0.aliases })
            let unknown = fields.keys.filter { $0 != opKey && !known.contains($0) }.sorted()
            return unknown.isEmpty ? nil : "\(example): \(unknown) is not a parameter of \(descriptor.opString)"
        }
    }

    @Test("the skill has op examples")
    func theSkillHasOpExamples() throws {
        #expect(try !Self.opExamples().isEmpty)
    }

    @Test("each op example names an operation of the tool and only its parameters or aliases")
    func eachOpExampleMatchesTheTool() throws {
        let descriptors = try Self.descriptors()

        let problems = try Self.opExamples().compactMap { Self.problem(of: $0, among: descriptors) }

        #expect(problems == [])
    }

    @Test("each operation of the tool has an op example in the skill")
    func eachOperationHasAnOpExample() throws {
        let text = try Self.skillText()

        let missing = try Self.descriptors().map(\.opString).filter { !text.contains("{\"\(Self.opKey)\": \"\($0)\"") }

        #expect(missing == [])
    }

    /// The start of a nested bullet: an entry of a parameter list.
    private static let nestedBullet = "  - "

    /// A small skill text for the unit test of ``unnamedParameters(_:of:in:)``:
    /// it names `id` and `message` in other parts, but the parameter list of
    /// `fork session` has only `message`.
    private static let forkListWithoutID = """
        - The `id` of these calls takes the same forms as `to`.
        - `fork session` takes these parameters, and each is optional:
          - `message`: the first prompt of the fork.
        - `export session` takes these parameters, and each is optional:
          - `id`: the session.
        """

    /// The start of the bullet that opens the parameter list of an
    /// operation in the skill.
    ///
    /// - Parameter op: The operation, as `<verb> <noun>`.
    /// - Returns: The text `` - `<op>` takes these parameters``.
    private static func parameterListLead(of op: String) -> String {
        "- `\(op)` takes these parameters"
    }

    /// The entries of the parameter list of one operation.
    ///
    /// The rule: the list starts after the first line that starts with
    /// ``parameterListLead(of:)``, and it holds each nested bullet
    /// (``nestedBullet``) that follows that line. The first line that is not a
    /// nested bullet ends the list: the next bullet, the next operation or the
    /// next heading.
    ///
    /// - Parameters:
    ///   - op: The operation, as `<verb> <noun>`.
    ///   - text: The skill text.
    /// - Returns: Each entry line. The list can be empty.
    /// - Throws: When the text has no parameter list for the operation.
    private static func parameterList(of op: String, in text: String) throws -> [Substring] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let lead = try #require(lines.firstIndex(where: { $0.hasPrefix(parameterListLead(of: op)) }))
        return Array(lines[(lead + 1)...].prefix { $0.hasPrefix(nestedBullet) })
    }

    /// The parameters that the parameter list of one operation does not name.
    ///
    /// A parameter is named when an entry of ``parameterList(of:in:)`` starts
    /// with `` `<name>`:``. A name in another part of the text does not count.
    ///
    /// - Parameters:
    ///   - names: The names of the parameters of the operation.
    ///   - op: The operation, as `<verb> <noun>`.
    ///   - text: The skill text.
    /// - Returns: Each name that the parameter list does not name, in the
    ///   order of `names`.
    /// - Throws: When the text has no parameter list for the operation.
    private static func unnamedParameters(_ names: [String], of op: String, in text: String) throws -> [String] {
        let entries = try parameterList(of: op, in: text)
        return names.filter { name in !entries.contains { $0.hasPrefix("\(nestedBullet)`\(name)`:") } }
    }

    /// The parameters of one operation of the tool that the parameter list
    /// of that operation in the skill does not name.
    ///
    /// - Parameter op: The operation, as `<verb> <noun>`.
    /// - Returns: The name of each parameter that the list does not name.
    /// - Throws: When the tool has no such operation, when the operation has
    ///   no parameter, or when the skill has no parameter list for the
    ///   operation.
    private static func unnamedParameters(of op: String) throws -> [String] {
        let descriptor = try #require(try descriptors().first { $0.opString == op })

        let names = descriptor.parameters.map(\.name)
        try #require(!names.isEmpty)

        return try unnamedParameters(names, of: op, in: try skillText())
    }

    @Test("a parameter that only other parts of the text name is unnamed")
    func aNameOutsideTheParameterListDoesNotCount() throws {
        let unnamed = try Self.unnamedParameters(
            ["id", "message"], of: ForkSession.opString, in: Self.forkListWithoutID)

        #expect(unnamed == ["id"])
    }

    /// The operations whose parameter list the skill must give in full.
    static let listedOperations = [
        ExportSession.opString, ForkSession.opString, SearchSessions.opString, ShareSession.opString,
        UpdateShare.opString, StopSharing.opString,
        ListExternalSessions.opString, ReadExternalSession.opString, ContinueExternalSession.opString,
    ]

    @Test("the skill names each parameter of the operation", arguments: listedOperations)
    func theSkillNamesEachParameter(of op: String) throws {
        #expect(try Self.unnamedParameters(of: op) == [])
    }

    /// The sentence of the skill that tells the limit of `search sessions`
    /// (D207 (d)). The tool tells the same limit in
    /// ``SessionsToolText/searchLimitSentence``.
    private static let searchLimitRule =
        """
        The search covers the transcripts of the sessions of this server. For the sessions of other agents, it \
        covers only the title, the first and last prompts, the folder and the branch.
        """

    /// A small skill text for the unit test of ``tells(_:in:)`` with
    /// ``searchLimitRule``: it names `search sessions` and its scope, but not
    /// its limit.
    private static let searchWithoutLimit = """
        - To find an earlier session by its content or by its meaning, use `search sessions`.
        - The search covers the sessions of this server.
        """

    /// Whether a text tells one rule sentence of the skill.
    ///
    /// - Parameters:
    ///   - rule: The rule sentence, for example ``searchLimitRule``,
    ///     ``shareWhenAskedRule`` or ``foreignFilesRule``.
    ///   - text: The skill text.
    /// - Returns: True when `text` contains `rule`.
    private static func tells(_ rule: String, in text: String) -> Bool {
        text.contains(rule)
    }

    @Test("a text with no limit sentence does not tell the limit of the search")
    func aTextWithNoLimitSentenceDoesNotTellTheLimit() {
        #expect(!Self.tells(Self.searchLimitRule, in: Self.searchWithoutLimit))
    }

    @Test("the skill tells the limit of search sessions")
    func theSkillTellsTheSearchLimit() throws {
        #expect(Self.tells(Self.searchLimitRule, in: try Self.skillText()))
    }

    /// The sentence of the skill that tells when to share a session (D208
    /// (k)): only when the user asks.
    private static let shareWhenAskedRule = "Share a session only when the user asks."

    /// A small skill text for the unit test of ``tells(_:in:)`` with
    /// ``shareWhenAskedRule``: it names `share session` and its link, but not
    /// when to share.
    private static let shareWithoutWhen = """
        - `share session` gives the transcript of a session to other people as a read-only link.
        """

    @Test("a text with no share rule does not tell when to share")
    func aTextWithNoShareRuleDoesNotTellWhenToShare() {
        #expect(!Self.tells(Self.shareWhenAskedRule, in: Self.shareWithoutWhen))
    }

    @Test("the skill says to share a session only when the user asks")
    func theSkillSaysToShareOnlyWhenTheUserAsks() throws {
        #expect(Self.tells(Self.shareWhenAskedRule, in: try Self.skillText()))
    }

    /// The sentence of the skill that tells the agent not to read the session
    /// files of other agents (D209 (l), D212): to continue such a session,
    /// the agent uses the external session operations.
    private static let foreignFilesRule = "Do not read the files of other agents."

    /// A small skill text for the unit test of ``tells(_:in:)`` with
    /// ``foreignFilesRule``: it names the external session operations and the
    /// copy, but not the rule about the files of other agents.
    private static let continueWithoutFilesRule = """
        - To continue a session of Claude Code or Codex, use `list external sessions` and then \
        `continue external session`.
        - The continue copies the session; it does not change the source.
        """

    @Test("a text with no files rule does not tell to keep out of the files of other agents")
    func aTextWithNoFilesRuleDoesNotTellIt() {
        #expect(!Self.tells(Self.foreignFilesRule, in: Self.continueWithoutFilesRule))
    }

    @Test("the skill says not to read the files of other agents")
    func theSkillSaysNotToReadTheFilesOfOtherAgents() throws {
        #expect(Self.tells(Self.foreignFilesRule, in: try Self.skillText()))
    }

    @Test("the skill names a code-mode verb")
    func theSkillNamesAVerb() throws {
        #expect(try !Self.namedVerbs().isEmpty)
    }

    @Test("each code-mode verb of the skill is a verb of the tool")
    func eachVerbIsAVerbOfTheTool() throws {
        let verbs = Set(try Self.descriptors().map { OperationVerbTool.verbName(for: $0.opString) })

        let unknown = try Self.namedVerbs().filter { !verbs.contains($0) }

        #expect(unknown == [])
    }

    @Test("the skill names each form of a session reference", arguments: referenceForms)
    func theSkillNamesTheForm(_ form: String) throws {
        #expect(try Self.skillText().contains("`\(form)`"))
    }

    @Test("the skill shows the user message header of a known source session in the Router form")
    func theSkillShowsTheKnownSourceUserHeader() throws {
        #expect(try Self.skillText().contains(Regex(Self.knownSourceUserHeader)))
    }

    @Test("the skill shows the user message header of an unknown source session in the Router form")
    func theSkillShowsTheUnknownSourceUserHeader() throws {
        #expect(try Self.skillText().contains(Regex(Self.unknownSourceUserHeader)))
    }

    @Test("the skill does not show the old user message header")
    func theSkillDoesNotShowTheOldUserHeader() throws {
        #expect(try !Self.skillText().contains(Self.oldUserHeader))
    }

    @Test("the skill shows the header of a message from a session in the Router form")
    func theSkillShowsTheSessionMessageHeader() throws {
        #expect(try Self.skillText().contains(Regex(Self.sessionMessageHeader)))
    }

    @Test("the skill names the in reply to fact of a message from a session")
    func theSkillNamesTheInReplyToFact() throws {
        #expect(try Self.skillText().contains(Self.inReplyToLabel))
    }

    @Test("the skill names the archived note of a sent receipt")
    func theSkillNamesTheArchivedNote() throws {
        #expect(try Self.skillText().contains(Self.archivedNote))
    }

    @Test("the skill does not say that an archived session takes no messages")
    func theSkillDoesNotRefuseMessagesToAnArchivedSession() throws {
        #expect(try !Self.skillText().contains(Self.oldArchivedRefusal))
    }

    /// The terms of the recap of a session that the skill must name (D206
    /// (h)): the word `recap`, the line form of `check session` and the fact
    /// form of `list sessions`. The tool writes the two forms in
    /// `SessionsToolText.facts(of:callerID:unreadFromIt:)` and
    /// `SessionsToolText.optionalFacts(of:)`, which keep them in string
    /// interpolation, so this list copies the literal forms.
    private static let recapTerms = ["recap", "`Recap:`", "`recap \"<text>\"`"]

    /// A small skill text for the unit test of ``unnamedRecapTerms(in:)``: it
    /// names the recap, but not the line form of `check session` and not the
    /// fact form of `list sessions`.
    private static let recapWithoutLineForm = """
        - The recap tells what a session did. Read it with `check session`.
        """

    /// The recap terms that a text does not name.
    ///
    /// - Parameter text: The skill text.
    /// - Returns: Each term of ``recapTerms`` that `text` does not contain, in
    ///   the order of ``recapTerms``.
    private static func unnamedRecapTerms(in text: String) -> [String] {
        recapTerms.filter { !text.contains($0) }
    }

    @Test("a text that names the recap without its line forms leaves those forms unnamed")
    func aRecapWithoutItsLineFormsIsIncomplete() {
        #expect(Self.unnamedRecapTerms(in: Self.recapWithoutLineForm) == ["`Recap:`", "`recap \"<text>\"`"])
    }

    @Test("the skill names the recap and its line forms in check session and list sessions")
    func theSkillNamesTheRecap() throws {
        #expect(Self.unnamedRecapTerms(in: try Self.skillText()) == [])
    }

    @Test("the skill names each receipt word of the tool", arguments: SessionsGraphOutcome.allCases)
    func theSkillNamesTheReceiptWord(_ outcome: SessionsGraphOutcome) throws {
        #expect(try Self.skillText().contains("`\(outcome.rawValue.lowercased())`"))
    }
}
