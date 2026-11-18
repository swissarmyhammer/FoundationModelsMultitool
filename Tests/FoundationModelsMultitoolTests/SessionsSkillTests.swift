// `SessionsSkillTests` — the unit suite that checks the text of the built-in
// `sessions` skill against the `sessions` tool (D200): each `{"op": ...}`
// example names an operation of the tool and only its parameters, each
// operation of the tool has an example, the skill names each parameter of
// `export session`, each code-mode verb of the skill is a verb of the tool,
// and the skill names each form of a session reference and each receipt word
// of the tool.
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
        let object = try? JSONSerialization.jsonObject(with: Data(example.utf8))
        guard let fields = object as? [String: Any] else {
            return "\(example): not a JSON object"
        }
        guard let op = fields[opKey] as? String,
            let descriptor = descriptors.first(where: { $0.opString == op })
        else {
            return "\(example): names no operation of the tool"
        }
        let known = Set(descriptor.parameters.flatMap { [$0.name] + $0.aliases })
        let unknown = fields.keys.filter { $0 != opKey && !known.contains($0) }.sorted()
        return unknown.isEmpty ? nil : "\(example): \(unknown) is not a parameter of \(op)"
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

    @Test("the skill names each parameter of export session")
    func theSkillNamesEachExportParameter() throws {
        let text = try Self.skillText()
        let descriptor = try #require(try Self.descriptors().first { $0.opString == ExportSession.opString })

        let names = descriptor.parameters.map(\.name)
        try #require(!names.isEmpty)

        let missing = names.filter { !text.contains("`\($0)`") }

        #expect(missing == [])
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

    @Test("the skill names each receipt word of the tool", arguments: SessionsGraphOutcome.allCases)
    func theSkillNamesTheReceiptWord(_ outcome: SessionsGraphOutcome) throws {
        #expect(try Self.skillText().contains("`\(outcome.rawValue.lowercased())`"))
    }
}
