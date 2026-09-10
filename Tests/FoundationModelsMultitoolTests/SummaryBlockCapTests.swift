import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Holds the two rules `APISurface.Entry.summaryBlock` applies to the text a
/// third party writes: a long description is cut, and an empty description is
/// replaced.
///
/// **Why this suite exists.** The selection prompt holds the description of
/// each tool and nothing else. An MCP tool takes its description from the
/// server word for word (`MCPTool.description`), thus a server sets the size
/// of the prompt, the number of model calls and the time of one `searchTools`
/// call. A server that gives no description leaves the banner alone under the
/// heading, and the selection model must then pick from a path and nothing
/// more.
///
/// The rules live where the surface is rendered, and not in the MCP
/// capability, thus a native tool with a long description obeys the same cap.
@Suite("SummaryBlockCapTests")
struct SummaryBlockCapTests {

    /// The name of the tool each entry of this suite renders.
    private static let toolName = "sample"

    /// The word a long description repeats, so a cut that lands inside a word
    /// is visible in the assertion.
    private static let repeatedWord = "alpha"

    /// The names the argument object of the empty-description entry declares.
    private static let parameterNames = ["path", "count"]

    /// The text every placeholder field of the descriptor holds, because this
    /// suite reads the summary block alone.
    private static let placeholderText = "placeholder"

    /// How many words the long description holds over the count that fills
    /// the cap, so the description is longer than the cap and the marker has
    /// something to report.
    private static let wordsOverTheCap = 2

    /// A description of `repeatedWord` words that is longer than the cap.
    ///
    /// - Returns: The long description.
    private static func longDescription() -> String {
        let word = "\(repeatedWord) "
        let wordCount =
            APISurface.Entry.summaryDescriptionCharacterLimit / word.count + wordsOverTheCap
        return String(repeating: word, count: wordCount)
            .trimmingCharacters(in: .whitespaces)
    }

    /// One catalog entry over a hand-written descriptor.
    ///
    /// The descriptor is written here, and not rendered from a tool, because
    /// the rules under test read the description and the argument names alone.
    ///
    /// - Parameters:
    ///   - description: The description the entry carries.
    ///   - parameterNames: The names the argument object declares.
    /// - Returns: The entry.
    private static func entry(
        description: String, parameterNames: [String] = []
    ) -> APISurface.Entry {
        let properties = parameterNames.map {
            ToolObjectShape.Property(name: $0, shape: .string(choices: []), isRequired: true)
        }
        let descriptor = ToolDescriptor(
            name: toolName,
            description: description,
            declaration: placeholderText,
            doc: placeholderText,
            example: placeholderText,
            source: placeholderText,
            signature: ToolSignature(
                arguments: ToolObjectShape(properties: properties), result: .string(choices: []))
        )
        return APISurface.Entry(path: toolName, group: nil, descriptor: descriptor)
    }

    /// The description half of a summary block — everything under the banner.
    ///
    /// - Parameter entry: The entry to read.
    /// - Returns: The text under the banner line.
    private static func summaryDescription(of entry: APISurface.Entry) -> String {
        let lines = entry.summaryBlock.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        return lines.count == 2 ? String(lines[1]) : ""
    }

    /// The text a cut description shows, with the cut marker taken off.
    ///
    /// The marker opens a line of its own, and the descriptions of this suite
    /// hold no other line, so the first line break names where it starts.
    ///
    /// - Parameter described: The cut description to read.
    /// - Returns: The head the description keeps.
    /// - Throws: When `described` holds no cut marker.
    private static func keptHead(of described: String) throws -> String {
        let marker = try #require(described.range(of: "\n[cut "))
        return String(described[described.startIndex..<marker.lowerBound])
    }

    @Test("a description over the cap is cut to the cap")
    func aDescriptionOverTheCapIsCutToTheCap() {
        let entry = Self.entry(description: Self.longDescription())

        let described = Self.summaryDescription(of: entry)

        #expect(described.count <= APISurface.Entry.summaryDescriptionCharacterLimit)
    }

    @Test("a cut description names how many characters it does not show")
    func aCutDescriptionNamesHowManyCharactersItDoesNotShow() throws {
        let description = Self.longDescription()
        let entry = Self.entry(description: description)

        let described = Self.summaryDescription(of: entry)

        let kept = try Self.keptHead(of: described)
        #expect(description.hasPrefix(kept))
        #expect(
            described
                == kept + APISurface.Entry.summaryCutMarker(
                    cutCount: description.count - kept.count))
    }

    @Test("a cut lands on a word boundary")
    func aCutLandsOnAWordBoundary() throws {
        let entry = Self.entry(description: Self.longDescription())

        let described = Self.summaryDescription(of: entry)

        let kept = try Self.keptHead(of: described)
        #expect(kept.hasSuffix(Self.repeatedWord))
    }

    @Test("a description under the cap is carried word for word")
    func aDescriptionUnderTheCapIsCarriedWordForWord() {
        let description = "reads one file from disk"
        let entry = Self.entry(description: description)

        #expect(Self.summaryDescription(of: entry) == description)
    }

    @Test("an entry with no description names its verb and its argument names")
    func anEntryWithNoDescriptionNamesItsVerbAndItsArgumentNames() {
        let entry = Self.entry(description: "", parameterNames: Self.parameterNames)

        let described = Self.summaryDescription(of: entry)

        #expect(!described.isEmpty)
        #expect(described.contains(Self.toolName))
        for name in Self.parameterNames {
            #expect(described.contains(name), "the summary of an empty description drops \(name)")
        }
    }

    @Test("an entry with no description and no argument still says what it takes")
    func anEntryWithNoDescriptionAndNoArgumentStillSaysWhatItTakes() {
        let entry = Self.entry(description: "")

        let described = Self.summaryDescription(of: entry)

        #expect(!described.isEmpty)
        #expect(described.contains(Self.toolName))
    }

    @Test("a description of spaces alone counts as no description")
    func aDescriptionOfSpacesAloneCountsAsNoDescription() {
        let entry = Self.entry(description: "   \n  ", parameterNames: Self.parameterNames)

        let described = Self.summaryDescription(of: entry)

        #expect(described.contains(Self.parameterNames[0]))
    }
}
