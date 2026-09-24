// `HTMLMarkdown` — converts an HTML page to markdown or to plain text.
//
// `fetch` gives a page to the model as markdown or as text (web.md § "HTML to
// markdown"). SwiftSoup parses the page into a DOM (web.md § "Decisions",
// item 1). The converter removes the page parts that are not content, selects
// the content root, and walks it in document order. To split text into lines,
// the converter uses `Hashline.splitLines(_:)`, the one line model of this
// package. Thus a carriage return and line feed ends a line, as a line feed does.

import Foundation
import SwiftSoup

/// The form of the text that ``HTMLMarkdown`` makes from a page.
enum WebTextFormat: Sendable {
    /// Markdown. Headings, lists, links, code, quotes, emphasis, and tables
    /// keep their markdown marks.
    case markdown

    /// Plain text. The walk is the same as for ``markdown``, but the output
    /// has no markdown marks. An ordered list keeps its numbers, and the cells
    /// of a table row are separated by a tab.
    case text
}

/// A page after ``HTMLMarkdown`` converts it.
struct ConvertedPage: Sendable, Equatable {
    /// The title of the page, or `nil` when the page has no title source.
    let title: String?

    /// The content of the page in the requested ``WebTextFormat``.
    ///
    /// Blocks are separated by one empty line. The text ends with one newline,
    /// or it is empty when the page has no content.
    let text: String
}

/// Converts an HTML page to markdown or to plain text.
///
/// A namespace, and not a value: each member is `static`.
enum HTMLMarkdown {
    /// The CSS selector of each element that the conversion removes before it
    /// walks the page. These elements hold navigation, scripts, forms, and
    /// advertisements, and not the content of the page.
    static let removedElementsSelector = [
        "script", "style", "nav", "aside", "header", "footer", "form",
        "noscript", "svg", "iframe", ".sidebar", ".ad", ".ads", ".advertisement",
    ].joined(separator: ", ")

    /// The tags that can be the content root, in order of preference. A tag
    /// is the root only when the page has exactly one element with that tag.
    static let contentRootTags = ["main", "article"]

    /// The CSS selector of the Open Graph title of a page.
    static let openGraphTitleSelector = "meta[property=og:title]"

    /// The text that separates two blocks: one empty line.
    static let blockSeparator = "\n\n"

    /// Converts an HTML page.
    ///
    /// The conversion removes each element that ``removedElementsSelector``
    /// selects. Then it uses the single `<main>` or the single `<article>` as
    /// the content root, else `<body>`. Links become absolute against
    /// `baseURL`, and a `<base href>` in the page changes that base.
    ///
    /// - Parameters:
    ///   - html: The HTML source of the page.
    ///   - baseURL: The URL of the page. Relative links resolve against it.
    ///   - format: The form of the text to make.
    /// - Returns: The title of the page and its content in `format`.
    /// - Throws: The error of the SwiftSoup parser when it cannot read `html`.
    static func convert(html: String, baseURL: URL, format: WebTextFormat) throws -> ConvertedPage {
        let document = try SwiftSoup.parse(html, baseURL.absoluteString)
        _ = try document.select(removedElementsSelector).remove()
        let blocks = try HTMLBlockRenderer(format: format).blocks(in: contentRoot(of: document))
        return try ConvertedPage(title: title(of: document), text: joined(blocks))
    }

    /// The title of a page: the `<title>`, else the Open Graph title, else the
    /// first `<h1>`. The first source with text wins.
    ///
    /// - Parameter document: The page, after the removal step.
    /// - Returns: The title with its whitespace collapsed, or `nil` when no
    ///   source has text.
    private static func title(of document: Document) throws -> String? {
        let sources = [
            try document.title(),
            try document.select(openGraphTitleSelector).first()?.attr("content") ?? "",
            try document.select("h1").first()?.text() ?? "",
        ]
        return sources
            .map { HTMLBlockRenderer.collapsedWhitespace($0).trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }

    /// The element that holds the content of a page.
    ///
    /// - Parameter document: The page, after the removal step.
    /// - Returns: The only element with the first tag of ``contentRootTags``
    ///   that occurs exactly one time, else `<body>`.
    private static func contentRoot(of document: Document) throws -> Element {
        for tag in contentRootTags {
            let candidates = try document.select(tag)
            if candidates.size() == 1, let root = candidates.first() {
                return root
            }
        }
        return document.body() ?? document
    }

    /// Joins blocks into the final text.
    ///
    /// - Parameter blocks: The blocks of the page, in document order.
    /// - Returns: The blocks separated by one empty line, with each run of
    ///   empty lines made into one empty line, and one newline at the end.
    private static func joined(_ blocks: [String]) -> String {
        let text = blocks
            .joined(separator: blockSeparator)
            .replacing(/\n(?:[ \t]*\n){2,}/, with: blockSeparator)
            .trimmingCharacters(in: .newlines)
        return text.isEmpty ? text : text + "\n"
    }
}

/// Walks a DOM element and makes the blocks of text of its content.
///
/// A block is a paragraph, a heading, a list, a code block, a quote, a table,
/// or a rule. Inline content — text, links, emphasis, and inline code — goes
/// into the paragraph that holds it.
private struct HTMLBlockRenderer {
    /// The number of heading levels HTML has, `<h1>` to `<h6>`.
    static let headingLevelCount = 6

    /// The heading level of each heading tag.
    static let headingLevels = Dictionary(
        uniqueKeysWithValues: (1...headingLevelCount).map { ("h\($0)", $0) }
    )

    /// The tags that start a block. Each other element is inline content.
    static let blockTags: Set<String> = Set(headingLevels.keys).union([
        "address", "article", "aside", "blockquote", "body", "dd", "details",
        "div", "dl", "dt", "fieldset", "figcaption", "figure", "footer", "header",
        "hr", "html", "li", "main", "nav", "ol", "p", "pre", "section", "summary",
        "table", "tbody", "td", "tfoot", "th", "thead", "tr", "ul",
    ])

    /// The markdown mark of each emphasis tag.
    static let emphasisMarks = ["em": "*", "i": "*", "strong": "**", "b": "**"]

    /// The tags of a table cell.
    static let cellTags: Set<String> = ["td", "th"]

    /// The prefix of the class that names the language of a code block, for
    /// example `language-swift`.
    static let languageClassPrefix = "language-"

    /// The markdown marker of an item of an unordered list.
    static let bulletMarker = "- "

    /// The markdown fence that starts and ends a code block.
    static let codeFence = "```"

    /// The markdown mark of inline code.
    static let inlineCodeMark = "`"

    /// The markdown mark of a quoted line.
    static let quoteMark = ">"

    /// The markdown line of a horizontal rule.
    static let ruleLine = "---"

    /// The markdown cell of the row under a table header.
    static let headerSeparatorCell = "---"

    /// The text between two cells of a table row in ``WebTextFormat/text``.
    static let textCellSeparator = "\t"

    /// The form of the text to make.
    let format: WebTextFormat

    /// Whether the renderer writes markdown marks.
    private var writesMarks: Bool {
        format == .markdown
    }

    // MARK: Blocks

    /// The blocks of the content of an element, in document order.
    ///
    /// Inline content between two blocks becomes one paragraph.
    ///
    /// - Parameter element: The element whose children to walk.
    /// - Returns: The non-empty blocks.
    func blocks(in element: Element) throws -> [String] {
        var walked: [String] = []
        var inlineRun = ""
        for node in element.getChildNodes() {
            guard let child = node as? Element, Self.blockTags.contains(child.tagNameNormal()) else {
                inlineRun += try inline(node)
                continue
            }
            walked += Self.paragraph(inlineRun)
            inlineRun = ""
            walked += try blocks(of: child)
        }
        return walked + Self.paragraph(inlineRun)
    }

    /// The blocks of one block element.
    ///
    /// - Parameter element: An element whose tag is in ``blockTags``.
    /// - Returns: The blocks the element makes.
    private func blocks(of element: Element) throws -> [String] {
        let tag = element.tagNameNormal()
        if let level = Self.headingLevels[tag] {
            return try heading(element, level: level)
        }
        switch tag {
        case "ul": return try list(element, isOrdered: false)
        case "ol": return try list(element, isOrdered: true)
        case "pre": return try codeBlock(element)
        case "blockquote": return try quote(element)
        case "table": return try table(element)
        case "hr": return writesMarks ? [Self.ruleLine] : []
        default: return try blocks(in: element)
        }
    }

    /// A paragraph from a run of inline content.
    ///
    /// - Parameter inlineRun: The inline content. A newline in it comes from a
    ///   `<br>`.
    /// - Returns: One block with the whitespace of each line collapsed, or no
    ///   block when the run has no text.
    private static func paragraph(_ inlineRun: String) -> [String] {
        let text = paragraphText(inlineRun)
        return text.isEmpty ? [] : [text]
    }

    /// The text of a run of inline content: each line with its spaces
    /// collapsed and trimmed, and with no empty line.
    private static func paragraphText(_ inlineRun: String) -> String {
        Hashline.splitLines(inlineRun)
            .map { $0.text.replacing(/\ {2,}/, with: " ").trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    /// The block of a heading.
    ///
    /// - Parameters:
    ///   - element: The `<h1>` to `<h6>` element.
    ///   - level: The heading level, from 1 to ``headingLevelCount``.
    /// - Returns: The heading text on one line, with `level` number signs in
    ///   markdown.
    private func heading(_ element: Element, level: Int) throws -> [String] {
        let text = try Self.paragraphText(inlineContent(of: element)).replacing("\n", with: " ")
        guard !text.isEmpty else { return [] }
        return writesMarks ? [String(repeating: "#", count: level) + " " + text] : [text]
    }

    // MARK: Lists

    /// The block of a list. An item that holds a nested list holds it as
    /// indented lines.
    ///
    /// - Parameters:
    ///   - element: The `<ul>` or `<ol>` element.
    ///   - isOrdered: Whether the list is an `<ol>`, whose items have numbers
    ///     that start at its `start` attribute.
    /// - Returns: One block with one line for each item, or no block when the
    ///   list has no text.
    private func list(_ element: Element, isOrdered: Bool) throws -> [String] {
        let firstNumber = try Int(element.attr("start")) ?? 1
        let items = element.children().array().filter { $0.tagNameNormal() == "li" }
        let lines = try items.enumerated().compactMap { offset, item in
            try listItem(item, marker: marker(isOrdered: isOrdered, number: firstNumber + offset))
        }
        return lines.isEmpty ? [] : [lines.joined(separator: "\n")]
    }

    /// The marker at the start of a list item.
    ///
    /// - Parameters:
    ///   - isOrdered: Whether the list is ordered.
    ///   - number: The number of the item in an ordered list.
    /// - Returns: `"<number>. "` for an ordered list. For an unordered list,
    ///   ``bulletMarker`` in markdown, and nothing in text.
    private func marker(isOrdered: Bool, number: Int) -> ListItemMarker {
        guard !isOrdered else { return ListItemMarker(text: "\(number). ") }
        let indent = String(repeating: " ", count: Self.bulletMarker.count)
        return ListItemMarker(text: writesMarks ? Self.bulletMarker : "", indent: indent)
    }

    /// The lines of one list item.
    ///
    /// - Parameters:
    ///   - item: The `<li>` element.
    ///   - marker: The marker of the item.
    /// - Returns: The marker and the first line, then each other line under the
    ///   indent of the marker, or `nil` when the item has no text.
    private func listItem(_ item: Element, marker: ListItemMarker) throws -> String? {
        let lines = try Hashline.splitLines(blocks(in: item).joined(separator: "\n")).map(\.text)
        guard let first = lines.first, !first.isEmpty else { return nil }
        let rest = lines.dropFirst().map { $0.isEmpty ? "" : marker.indent + $0 }
        return ([marker.text + first] + rest).joined(separator: "\n")
    }

    // MARK: Code

    /// The block of a `<pre>` element.
    ///
    /// - Parameter element: The `<pre>` element.
    /// - Returns: The code with its whitespace kept. In markdown, the code is
    ///   in a fence that names the language of the code block. No block when
    ///   the element has no text.
    private func codeBlock(_ element: Element) throws -> [String] {
        let code = try element.text(trimAndNormaliseWhitespace: false).trimmingCharacters(in: .newlines)
        guard !code.isEmpty else { return [] }
        guard writesMarks else { return [code] }
        let language = try codeLanguage(of: element)
        return [Self.codeFence + language + "\n" + code + "\n" + Self.codeFence]
    }

    /// The language of a code block, from a `language-<name>` class on the
    /// `<pre>` element or on a `<code>` element in it.
    ///
    /// - Parameter element: The `<pre>` element.
    /// - Returns: The name of the language, or an empty string when no class
    ///   names one.
    private func codeLanguage(of element: Element) throws -> String {
        let classNames = try ([element] + element.select("code").array())
            .flatMap { try $0.className().split(separator: " ") }
        let languageClass = classNames.first { $0.hasPrefix(Self.languageClassPrefix) }
        return languageClass.map { String($0.dropFirst(Self.languageClassPrefix.count)) } ?? ""
    }

    // MARK: Quotes and tables

    /// The block of a `<blockquote>` element.
    ///
    /// - Parameter element: The `<blockquote>` element.
    /// - Returns: In markdown, one block with each line of the quoted blocks
    ///   after the quote mark. In text, the quoted blocks.
    private func quote(_ element: Element) throws -> [String] {
        let quoted = try blocks(in: element)
        guard writesMarks, !quoted.isEmpty else { return quoted }
        let lines = Hashline.splitLines(quoted.joined(separator: HTMLMarkdown.blockSeparator))
            .map { $0.text.isEmpty ? Self.quoteMark : Self.quoteMark + " " + $0.text }
        return [lines.joined(separator: "\n")]
    }

    /// The block of a `<table>` element.
    ///
    /// - Parameter element: The `<table>` element.
    /// - Returns: In markdown, a table whose first row is the header. In text,
    ///   one line for each row. No block when the table has no cells.
    private func table(_ element: Element) throws -> [String] {
        let rows = try element.select("tr").array().map(cells).filter { !$0.isEmpty }
        guard !rows.isEmpty else { return [] }
        guard writesMarks else {
            return [rows.map { $0.joined(separator: Self.textCellSeparator) }.joined(separator: "\n")]
        }
        return [Self.markdownTable(rows)]
    }

    /// The text of each cell of one table row.
    ///
    /// - Parameter row: The `<tr>` element.
    /// - Returns: The text of each `<td>` and `<th>` child, in order.
    private func cells(of row: Element) throws -> [String] {
        try row.children().array().filter { Self.cellTags.contains($0.tagNameNormal()) }.map(cellText)
    }

    /// The text of one table cell, on one line. In markdown, a pipe in the
    /// text is escaped.
    private func cellText(_ cell: Element) throws -> String {
        let text = try Self.paragraphText(inlineContent(of: cell)).replacing("\n", with: " ")
        return writesMarks ? text.replacing("|", with: "\\|") : text
    }

    /// A markdown table.
    ///
    /// - Parameter rows: The text of the cells of each row. The first row is
    ///   the header.
    /// - Returns: The table, with each short row filled with empty cells.
    private static func markdownTable(_ rows: [[String]]) -> String {
        let columnCount = rows.map(\.count).max() ?? 0
        let filledRows = rows.map { $0 + Array(repeating: "", count: columnCount - $0.count) }
        let separatorRow = Array(repeating: headerSeparatorCell, count: columnCount)
        return (filledRows.prefix(1) + [separatorRow] + filledRows.dropFirst())
            .map { "| " + $0.joined(separator: " | ") + " |" }
            .joined(separator: "\n")
    }

    // MARK: Inline content

    /// The inline content of a node.
    ///
    /// - Parameter node: A text node or an element that is not a block.
    /// - Returns: The text of the node with its whitespace collapsed, and the
    ///   markdown marks of links, emphasis, and inline code. A `<br>` gives a
    ///   newline. A comment gives nothing.
    private func inline(_ node: Node) throws -> String {
        if let textNode = node as? TextNode {
            return Self.collapsedWhitespace(textNode.getWholeText())
        }
        guard let element = node as? Element else { return "" }
        switch element.tagNameNormal() {
        case "br": return "\n"
        case "a": return try link(element)
        case "code": return try inlineCode(element)
        case let tag: return try marked(inlineContent(of: element), with: Self.emphasisMarks[tag])
        }
    }

    /// The inline content of a `<code>` element that is not in a `<pre>`.
    ///
    /// - Parameter element: The `<code>` element.
    /// - Returns: The text of the code with its whitespace collapsed, between
    ///   two inline code marks in markdown.
    private func inlineCode(_ element: Element) throws -> String {
        let code = try Self.collapsedWhitespace(element.text(trimAndNormaliseWhitespace: false))
        return marked(code, with: Self.inlineCodeMark)
    }

    /// The inline content of each child of an element, joined.
    private func inlineContent(of element: Element) throws -> String {
        try element.getChildNodes().map(inline).joined()
    }

    /// The inline content of a link.
    ///
    /// - Parameter element: The `<a>` element.
    /// - Returns: In markdown, `[text](absolute-url)`. The text only when the
    ///   format is text or the link has no target, and nothing when the link
    ///   has no text.
    private func link(_ element: Element) throws -> String {
        let content = try inlineContent(of: element)
        let label = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = try element.absUrl("href")
        guard writesMarks, !label.isEmpty, !target.isEmpty else { return content }
        return Self.keepingOuterSpace(of: content, around: "[\(label)](\(target))")
    }

    /// Inline content between two marks.
    ///
    /// - Parameters:
    ///   - content: The inline content.
    ///   - mark: The markdown mark, or `nil` when the element has no mark.
    /// - Returns: In markdown, the trimmed content between two marks, with the
    ///   outer spaces of `content` kept outside the marks. Else `content`.
    private func marked(_ content: String, with mark: String?) -> String {
        let core = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard writesMarks, let mark, !core.isEmpty else { return content }
        return Self.keepingOuterSpace(of: content, around: mark + core + mark)
    }

    /// Puts one space before and after `core` where `content` starts or ends
    /// with whitespace. Thus a mark never stands next to a space inside it.
    private static func keepingOuterSpace(of content: String, around core: String) -> String {
        let leading = content.first?.isWhitespace == true ? " " : ""
        let trailing = content.last?.isWhitespace == true ? " " : ""
        return leading + core + trailing
    }

    /// Makes each run of whitespace in `text` into one space.
    static func collapsedWhitespace(_ text: String) -> String {
        text.replacing(/\s+/, with: " ")
    }
}

/// The marker at the start of a list item, and the indent of the other lines
/// of the item.
private struct ListItemMarker {
    /// The text before the first line of the item.
    let text: String

    /// The text before each other line of the item.
    let indent: String
}

extension ListItemMarker {
    /// A marker whose indent has the width of `text`.
    init(text: String) {
        self.init(text: text, indent: String(repeating: " ", count: text.count))
    }
}
