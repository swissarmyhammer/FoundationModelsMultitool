import Foundation
import Testing

/// Guards the documents of the web capability against a gap.
///
/// The `## Capabilities` section of `README.md` must name the builder short
/// form, the two verbs, and each environment variable of a keyed provider,
/// thus a host that reads the README can mount the capability and give it
/// keys. The `## The web capability` section of `docs/SECURITY.md` must hold
/// each fixed phrase of web.md § "Security", thus each security property of
/// the capability has a sentence that states it.
///
/// Each test reads only its own section. The same text in a different section
/// does not make a test pass.
@Suite("WebDocumentation")
struct WebDocumentationTests {
    /// The README, from the repository root.
    private static let readmePath = "README.md"

    /// The heading of the README section that must document the capability.
    private static let capabilitiesHeading = "## Capabilities"

    /// The texts that the README section must hold: the builder short form,
    /// the two verbs, and the environment variable of each keyed provider.
    static let readmeTexts = [
        "withWeb",
        "tools.web.search",
        "tools.web.fetch",
        "BRAVE_SEARCH_API_KEY",
        "TAVILY_API_KEY",
        "EXA_API_KEY",
        "SERPER_API_KEY",
        "KAGI_API_KEY",
        "SEARXNG_URL",
    ]

    /// The security document, from the repository root.
    private static let securityPath = "docs/SECURITY.md"

    /// The heading of the security section of the capability.
    private static let securityHeading = "## The web capability"

    /// The fixed phrases that the security section must hold, one for each
    /// property that web.md § "Security" names.
    static let securityPhrases = [
        "off by default",
        "withWeb",
        "each redirect hop",
        "WebAddressGuard",
        "DNS rebinding",
        "Keys stay in Swift",
        "can contain instructions",
        "SearXNG",
        "only from a mounted tool",
    ]

    @Test("the README Capabilities section names each text a host needs to mount the web capability",
          arguments: readmeTexts)
    func readmeCapabilitiesSectionNames(_ text: String) throws {
        let section = try RepositoryFile.section(headed: Self.capabilitiesHeading, inRelativeFile: Self.readmePath)
        #expect(section.contains(text), "\(Self.readmePath) \(Self.capabilitiesHeading) does not contain \"\(text)\".")
    }

    @Test("the security section of the web capability holds each fixed phrase", arguments: securityPhrases)
    func securitySectionHolds(_ phrase: String) throws {
        let section = try RepositoryFile.section(headed: Self.securityHeading, inRelativeFile: Self.securityPath)
        #expect(section.contains(phrase), "\(Self.securityPath) \(Self.securityHeading) does not contain \"\(phrase)\".")
    }
}
