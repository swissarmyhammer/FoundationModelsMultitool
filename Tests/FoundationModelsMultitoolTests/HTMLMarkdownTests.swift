import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Golden tests for ``HTMLMarkdown``.
///
/// Each page in `WebGoldens/` is a small hand-written HTML file. Beside it,
/// `<page>.md` holds the markdown and `<page>.txt` holds the text that
/// ``HTMLMarkdown/convert(html:baseURL:format:)`` must make from it. The test
/// compares the whole output with the whole golden file, thus a change in any
/// character is a failure.
///
/// The conversion reads a string and makes a string. It uses no network and
/// no file other than the goldens, thus this suite is a unit test.
@Suite struct HTMLMarkdownTests {
    /// The name of the resource directory that holds the goldens.
    private static let goldenDirectory = "WebGoldens"

    /// The URL each golden page has. Relative links resolve against it.
    private static let baseURL = URL(string: "https://example.com/docs/page.html")

    /// The name of each golden page, with no extension.
    private static let goldenPages = [
        "headings-and-lists",
        "code-fences",
        "table",
        "relative-links",
        "main-element",
        "clutter",
        "title-tag",
        "title-og",
        "title-h1",
    ]

    /// The golden pages whose title comes from each of the three title sources,
    /// and the title that each page must give.
    private static let expectedTitles = [
        "title-tag": "Tag Title",
        "title-og": "OG Title",
        "title-h1": "Heading Title",
    ]

    /// The text of each element that the removal step must remove from
    /// `clutter.html`.
    private static let removedTexts = [
        "Header text",
        "Home link",
        "Blog link",
        "Aside text",
        "Sidebar text",
        "Ad text",
        "Ads text",
        "Advertisement text",
        "script text",
        "Noscript text",
        "Svg text",
        "Iframe text",
        "Form text",
        "Footer text",
        "color: red",
    ]

    // MARK: Golden loading

    /// The extension of the golden file that holds the output in `format`.
    private static func goldenExtension(for format: WebTextFormat) -> String {
        switch format {
        case .markdown: "md"
        case .text: "txt"
        }
    }

    /// Converts one golden page in `format`.
    private static func convert(_ page: String, format: WebTextFormat) throws -> ConvertedPage {
        try HTMLMarkdown.convert(
            html: TestResource.bundledText(named: page, withExtension: "html", in: goldenDirectory),
            baseURL: #require(baseURL),
            format: format
        )
    }

    // MARK: Goldens

    @Test(arguments: goldenPages, [WebTextFormat.markdown, .text])
    func pageConvertsToItsGolden(page: String, format: WebTextFormat) throws {
        let expected = try TestResource.bundledText(
            named: page,
            withExtension: Self.goldenExtension(for: format),
            in: Self.goldenDirectory
        )

        let converted = try Self.convert(page, format: format)

        #expect(converted.text == expected)
    }

    // MARK: Titles

    @Test(arguments: expectedTitles.keys.sorted())
    func titleComesFromTheFirstSourceThePageHas(page: String) throws {
        let converted = try Self.convert(page, format: .markdown)

        #expect(converted.title == Self.expectedTitles[page])
    }

    @Test func pageWithNoTitleSourceHasNoTitle() throws {
        let converted = try HTMLMarkdown.convert(
            html: "<html><body><p>No title here.</p></body></html>",
            baseURL: #require(Self.baseURL),
            format: .markdown
        )

        #expect(converted.title == nil)
        #expect(converted.text == "No title here.\n")
    }

    // MARK: Links

    @Test func everyLinkTargetIsAbsolute() throws {
        let markdown = try Self.convert("relative-links", format: .markdown).text
        let targets = markdown.matches(of: /\]\(([^)]*)\)/).map { String($0.output.1) }

        #expect(targets.count == 5)
        for target in targets {
            let url = try #require(URL(string: target), "\(target) must parse as a URL")
            #expect(url.scheme == "https", "\(target) must be an absolute https URL")
        }
    }

    // MARK: Removal

    @Test(arguments: [WebTextFormat.markdown, .text])
    func removedElementsDoNotAppear(format: WebTextFormat) throws {
        let text = try Self.convert("clutter", format: format).text

        #expect(text.contains("Story one."), "the content beside the removed elements must stay")
        for removed in Self.removedTexts {
            #expect(!text.contains(removed), "\(removed) must not appear in the output")
        }
    }

    // MARK: Empty lines

    @Test func runOfEmptyLinesBecomesOneEmptyLine() throws {
        let html = "<html><body><p>Before</p><pre>first\n\n\n\nlast</pre></body></html>"

        let converted = try HTMLMarkdown.convert(
            html: html,
            baseURL: #require(Self.baseURL),
            format: .text
        )

        #expect(converted.text == "Before\n\nfirst\n\nlast\n")
    }

    // MARK: Line terminators

    /// A carriage return and line feed in a code block ends a line, as a line
    /// feed does. Each line of the code in a list item gets the indent of the
    /// item, and each line in a quote gets the quote mark.
    @Test(arguments: [
        ("<ul><li>Item<pre>first\r\nlast</pre></li></ul>", "- Item\n  ```\n  first\n  last\n  ```\n"),
        ("<blockquote><pre>first\r\nlast</pre></blockquote>", "> ```\n> first\n> last\n> ```\n"),
    ])
    func carriageReturnLineFeedInNestedCodeEndsALine(body: String, expected: String) throws {
        let converted = try HTMLMarkdown.convert(
            html: "<html><body>\(body)</body></html>",
            baseURL: #require(Self.baseURL),
            format: .markdown
        )

        #expect(converted.text == expected)
    }

    // MARK: Content root

    @Test func exactlyOneArticleIsTheContentRoot() throws {
        let html = """
            <html><body>
            <div>Text outside of the article.</div>
            <article><p>Text of the article.</p></article>
            </body></html>
            """

        let converted = try HTMLMarkdown.convert(
            html: html,
            baseURL: #require(Self.baseURL),
            format: .text
        )

        #expect(converted.text == "Text of the article.\n")
    }
}
