import Foundation
import Testing

/// Guards the documents of the git capability against a gap (task
/// `^xd2dbd1`).
///
/// The `## Capabilities` section of `README.md` must name the builder short
/// form, each verb, the read-only rule, and each language of the semantic
/// diff, thus a host that reads the README can mount the capability and knows
/// what it reads. Fortran is not in the language set (git.md § "Decisions",
/// item 13), thus the section must not name it.
///
/// The `## Status of this document` section of `git.md` must say that the code
/// shipped, and that the code and `README.md` are correct when they are
/// different from the plan, with the same text as `web.md`.
///
/// Each test reads only its own section. The same text in a different section
/// does not make a test pass.
@Suite("GitDocumentation")
struct GitDocumentationTests {
    /// The README, from the repository root.
    private static let readmePath = "README.md"

    /// The heading of the README section that must document the capability.
    private static let capabilitiesHeading = "## Capabilities"

    /// The texts that the README section must hold: the builder short form,
    /// each verb, and the read-only rule.
    static let readmeTexts = [
        "withGit(root:)",
        "tools.git.status",
        "tools.git.branches",
        "tools.git.changes",
        "tools.git.show",
        "tools.git.log",
        "tools.git.blame",
        "tools.git.diff",
        "read-only",
        "absentFolders",
    ]

    /// Each language and each data format of the semantic diff (git.md §
    /// "Decisions", items 7, 13, and 14), and the fallback for all other
    /// files.
    ///
    /// The README names the languages in one list with commas. Thus the entry
    /// for C is `C,`: the text `C` alone is also in `C++` and `C#`, and would
    /// pass with no C in the list.
    static let diffLanguages = [
        "Rust", "TypeScript", "TSX", "JavaScript", "JSX", "Python", "Go", "Java", "C,", "C++", "Ruby", "C#",
        "PHP", "Swift", "Elixir", "Bash", "JSON", "YAML", "TOML", "CSV", "Markdown", "Vue", "fallback",
    ]

    /// The language that git.md § "Decisions", item 13, removed.
    private static let droppedLanguage = "Fortran"

    /// The plan of the capability, from the repository root.
    private static let planPath = "git.md"

    /// The plan of the web capability, whose status text the git plan copies.
    private static let webPlanPath = "web.md"

    /// The heading of the status section of each plan.
    private static let statusHeading = "## Status of this document"

    @Test("the README Capabilities section names each text a host needs to mount the git capability",
          arguments: readmeTexts)
    func readmeCapabilitiesSectionNames(_ text: String) throws {
        let section = try RepositoryFile.section(headed: Self.capabilitiesHeading, inRelativeFile: Self.readmePath)
        #expect(section.contains(text), "\(Self.readmePath) \(Self.capabilitiesHeading) does not contain \"\(text)\".")
    }

    @Test("the README Capabilities section names each language of the semantic diff", arguments: diffLanguages)
    func readmeCapabilitiesSectionNamesTheLanguage(_ language: String) throws {
        let section = try RepositoryFile.section(headed: Self.capabilitiesHeading, inRelativeFile: Self.readmePath)
        #expect(
            section.contains(language),
            "\(Self.readmePath) \(Self.capabilitiesHeading) does not contain \"\(language)\".")
    }

    @Test("the README Capabilities section does not name the dropped language")
    func readmeCapabilitiesSectionDoesNotNameTheDroppedLanguage() throws {
        let section = try RepositoryFile.section(headed: Self.capabilitiesHeading, inRelativeFile: Self.readmePath)
        #expect(
            !section.contains(Self.droppedLanguage),
            "\(Self.readmePath) \(Self.capabilitiesHeading) names \"\(Self.droppedLanguage)\".")
    }

    @Test("the status of git.md says that the code shipped, with the same text as web.md")
    func planStatusSaysThatTheCodeShipped() throws {
        let gitStatus = try RepositoryFile.section(headed: Self.statusHeading, inRelativeFile: Self.planPath)
        let webStatus = try RepositoryFile.section(headed: Self.statusHeading, inRelativeFile: Self.webPlanPath)
        #expect(
            gitStatus.trimmingCharacters(in: .whitespacesAndNewlines)
                == webStatus.trimmingCharacters(in: .whitespacesAndNewlines),
            "\(Self.planPath) \(Self.statusHeading) is \"\(gitStatus)\".")
    }
}
