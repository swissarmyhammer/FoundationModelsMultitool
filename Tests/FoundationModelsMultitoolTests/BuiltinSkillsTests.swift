// `BuiltinSkillsTests` — the unit suite of the skills folder that the library
// ships as a resource: the folder is in the bundle, it holds the `sessions`
// skill, and the frontmatter of that skill names the skill and describes it.

import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Unit tests for ``BuiltinSkills``.
@Suite struct BuiltinSkillsTests {

    /// The line that opens and closes the frontmatter of a skill file.
    private static let frontmatterFence = "---"

    /// The start of the frontmatter line that describes a skill.
    private static let descriptionKey = "description: "

    /// The file of the `sessions` skill, below ``BuiltinSkills/directory``.
    /// `SessionsSkillTests` reads the text of the skill from this file too.
    static var sessionsSkillFile: URL {
        BuiltinSkills.directory
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("SKILL.md", isDirectory: false)
    }

    /// Reads the frontmatter lines of the `sessions` skill: the lines between
    /// the first fence and the second fence.
    ///
    /// - Returns: The frontmatter lines, with no fence.
    private static func sessionsFrontmatter() throws -> [String] {
        let lines = try String(contentsOf: sessionsSkillFile, encoding: .utf8)
            .components(separatedBy: "\n")
        guard lines.first == frontmatterFence,
            let end = lines.dropFirst().firstIndex(of: frontmatterFence)
        else {
            return []
        }
        return Array(lines[1..<end])
    }

    @Test("the skills folder is in the bundle")
    func theSkillsFolderIsInTheBundle() {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: BuiltinSkills.directory.path, isDirectory: &isDirectory)

        #expect(exists && isDirectory.boolValue)
    }

    @Test("the skills folder holds sessions/SKILL.md")
    func theSkillsFolderHoldsTheSessionsSkill() {
        #expect(FileManager.default.fileExists(atPath: Self.sessionsSkillFile.path))
    }

    @Test("the frontmatter of the sessions skill names the skill sessions")
    func theFrontmatterNamesTheSkill() throws {
        #expect(try Self.sessionsFrontmatter().contains("name: sessions"))
    }

    @Test("the frontmatter of the sessions skill has a description")
    func theFrontmatterHasADescription() throws {
        let description = try Self.sessionsFrontmatter().first { $0.hasPrefix(Self.descriptionKey) }

        #expect(description.map { $0.dropFirst(Self.descriptionKey.count).isEmpty } == false)
    }
}
