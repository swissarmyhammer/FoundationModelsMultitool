// `SessionsSkillTests` — the unit suite that checks the text of the built-in
// `sessions` skill against the `sessions` tool (D200): each `{"op": ...}`
// example names an operation of the tool and only its parameters, each
// code-mode verb of the skill is a verb of the tool, and the skill names each
// form of a session reference and each receipt word of the tool.
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

    @Test("the skill names each receipt word of the tool", arguments: SessionsGraphOutcome.allCases)
    func theSkillNamesTheReceiptWord(_ outcome: SessionsGraphOutcome) throws {
        #expect(try Self.skillText().contains("`\(outcome.rawValue.lowercased())`"))
    }
}
