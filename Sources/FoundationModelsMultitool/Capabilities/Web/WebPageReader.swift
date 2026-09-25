// `WebPageReader` — the conversion, the windows, and the page cache of the web
// capability (web.md § "Fetch / The pipeline", steps 6 and 7, and the page
// cache paragraph after them).
//
// The reader loads a page with `WebFetcher`, decodes the body, and converts an
// HTML page with `HTMLMarkdown`. Then it gives one window of the converted
// text. The reader keeps the converted pages of one session in a small cache.
// Thus a snippet that reads a long page window by window downloads it one
// time.
//
// Each offset, each window size, and each length counts `Character` values,
// the same unit as `String.count`. Thus a window never cuts a character in
// two.

import Foundation

/// The form of the content that the reader gives.
///
/// The raw value is the name of the form in the `format` argument of
/// `tools.web.fetch`.
enum WebPageFormat: String, Sendable, Hashable, CaseIterable {
    /// Markdown. An HTML page is converted. Other text is used as is.
    case markdown

    /// Plain text. An HTML page is converted with no markdown marks. Other
    /// text is used as is.
    case text

    /// The decoded body with no change, also for an HTML page.
    case raw

    /// The form that ``HTMLMarkdown`` makes of an HTML page for this format,
    /// or `nil` when the format does not convert HTML.
    var htmlTextFormat: WebTextFormat? {
        switch self {
        case .markdown: .markdown
        case .text: .text
        case .raw: nil
        }
    }
}

/// One window of a converted page.
struct PageWindow: Sendable, Equatable {
    /// The final URL, after each redirect.
    let url: URL

    /// The HTTP status of the final response.
    let status: Int

    /// The media type of the response, in lower case, for example `text/html`.
    let contentType: String

    /// The title of an HTML page in the markdown or the text format, else
    /// `nil`.
    let title: String?

    /// The characters of the window.
    let content: String

    /// The number of characters in the full converted page.
    let totalCharacters: Int

    /// The offset of the next window, or `nil` when this window goes to the
    /// end of the page.
    let nextOffset: Int?

    /// `true` when the body is longer than the byte limit and the page is not
    /// complete.
    let truncated: Bool
}

/// Loads pages, converts them, gives windows of them, and keeps the converted
/// pages of one session in a cache.
///
/// The cache keeps at most ``cacheCapacity`` pages. When it is full, the page
/// that the reader used least recently goes first. Each page is stored under
/// the requested URL and under the final URL, each with the format. Thus a
/// second window of a URL that redirects makes no new request.
actor WebPageReader {
    /// The maximum number of pages in the cache.
    static let cacheCapacity = 16

    /// The media types that the reader converts as HTML.
    static let htmlMediaTypes: Set<String> = ["text/html", "application/xhtml+xml"]

    /// The number of loads that went to the fetcher. A cache hit does not
    /// count. The live tests read it to prove that the cache works.
    private(set) var networkLoadCount = 0

    /// The fetcher that loads each page.
    private let fetcher: WebFetcher

    /// The converted pages of this session.
    private var cache = WebPageCache(capacity: cacheCapacity)

    /// Makes a reader with an empty cache.
    ///
    /// - Parameter fetcher: The fetcher that loads each page.
    init(fetcher: WebFetcher) {
        self.fetcher = fetcher
    }

    /// Gives one window of a page.
    ///
    /// The reader uses the cached page when the cache has one for `url` and
    /// `format`. Else it loads the page, converts it, and stores it in the
    /// cache. A failure goes into no cache entry, thus the next read tries
    /// again.
    ///
    /// - Parameters:
    ///   - url: The URL of the page.
    ///   - format: The form of the content.
    ///   - offset: The character offset of the window. It must not be
    ///     negative. An offset at or past the end gives empty content.
    ///   - maxCharacters: The maximum number of characters in the window. It
    ///     must be more than zero.
    ///   - timeout: The time limit of a load.
    /// - Returns: The window, or the failure of the load. A non-2xx status is
    ///   a window, not a failure.
    func read(
        url: URL, format: WebPageFormat, offset: Int, maxCharacters: Int, timeout: Duration
    ) async -> Result<PageWindow, WebFetchFailure> {
        precondition(offset >= 0, "the window offset must not be negative")
        precondition(maxCharacters > 0, "the window size must be more than zero")
        let key = WebPageCacheKey(url: url, format: format)
        if let page = cache.page(for: key) {
            return .success(page.window(offset: offset, maxCharacters: maxCharacters))
        }
        let loaded = await load(url, format: format, timeout: timeout)
        if case .success(let page) = loaded {
            cache.insert(page, keys: [key, WebPageCacheKey(url: page.url, format: format)])
        }
        return loaded.map { $0.window(offset: offset, maxCharacters: maxCharacters) }
    }

    /// Loads a page with the fetcher, decodes it, and converts it.
    ///
    /// - Parameters:
    ///   - url: The URL of the page.
    ///   - format: The form of the content.
    ///   - timeout: The time limit of the load.
    /// - Returns: The converted page, or the failure.
    private func load(
        _ url: URL, format: WebPageFormat, timeout: Duration
    ) async -> Result<ConvertedWebPage, WebFetchFailure> {
        networkLoadCount += 1
        let fetcher = fetcher
        return await fetcher.load(URLRequest(url: url), timeout: timeout).flatMap { body in
            fetcher.decodeText(body).flatMap { text in Self.convert(text, of: body, format: format) }
        }
    }

    /// Converts the decoded text of a body to `format`.
    ///
    /// - Parameters:
    ///   - text: The decoded body.
    ///   - body: The body and the facts of its response.
    ///   - format: The form of the content.
    /// - Returns: The converted page. An HTML page in the markdown or the text
    ///   format goes through ``HTMLMarkdown``. Other text is used as is. The
    ///   failure is ``WebFetchFailure/unconvertible(url:reason:)`` when the
    ///   converter cannot read the HTML.
    private static func convert(
        _ text: String, of body: FetchedBody, format: WebPageFormat
    ) -> Result<ConvertedWebPage, WebFetchFailure> {
        guard htmlMediaTypes.contains(body.contentType), let htmlFormat = format.htmlTextFormat else {
            return .success(ConvertedWebPage(body: body, title: nil, text: text))
        }
        do {
            let converted = try HTMLMarkdown.convert(html: text, baseURL: body.url, format: htmlFormat)
            return .success(ConvertedWebPage(body: body, title: converted.title, text: converted.text))
        } catch {
            return .failure(.unconvertible(url: body.url.absoluteString, reason: String(describing: error)))
        }
    }
}

/// A page after the reader converts it, as the cache keeps it.
private struct ConvertedWebPage: Sendable {
    /// The final URL, after each redirect.
    let url: URL

    /// The HTTP status of the final response.
    let status: Int

    /// The media type of the response, in lower case.
    let contentType: String

    /// The title of an HTML page in the markdown or the text format, else
    /// `nil`.
    let title: String?

    /// The full converted text.
    let text: String

    /// The number of characters in ``text``.
    let totalCharacters: Int

    /// `true` when the body stopped at the byte limit.
    let truncated: Bool

    /// Makes a converted page from a body and its converted text.
    ///
    /// - Parameters:
    ///   - body: The body and the facts of its response.
    ///   - title: The title of the page, or `nil`.
    ///   - text: The full converted text.
    init(body: FetchedBody, title: String?, text: String) {
        url = body.url
        status = body.status
        contentType = body.contentType
        self.title = title
        self.text = text
        totalCharacters = text.count
        truncated = body.truncated
    }

    /// One window of the page.
    ///
    /// - Parameters:
    ///   - offset: The character offset of the window, zero or more.
    ///   - maxCharacters: The maximum number of characters in the window.
    /// - Returns: The window. An offset at or past the end gives empty
    ///   content and no next offset.
    func window(offset: Int, maxCharacters: Int) -> PageWindow {
        let start = min(offset, totalCharacters)
        let length = min(maxCharacters, totalCharacters - start)
        let lower = text.index(text.startIndex, offsetBy: start)
        let upper = text.index(lower, offsetBy: length)
        let end = start + length
        return PageWindow(
            url: url, status: status, contentType: contentType, title: title, content: String(text[lower..<upper]),
            totalCharacters: totalCharacters, nextOffset: end < totalCharacters ? end : nil, truncated: truncated
        )
    }
}

/// The key of one cache entry: a URL and a format.
private struct WebPageCacheKey: Hashable, Sendable {
    // The synthesized `Hashable` conformance reads it; periphery sees no caller.
    // periphery:ignore
    /// The absolute text of the URL.
    let url: String

    // The synthesized `Hashable` conformance reads it; periphery sees no caller.
    // periphery:ignore
    /// The form of the content.
    let format: WebPageFormat

    /// Makes a key.
    ///
    /// - Parameters:
    ///   - url: The URL of the page.
    ///   - format: The form of the content.
    init(url: URL, format: WebPageFormat) {
        self.url = url.absoluteString
        self.format = format
    }
}

/// The converted pages of one session, with the least recently used page
/// first.
private struct WebPageCache {
    /// One page and each key that finds it.
    private struct Entry {
        /// The keys that find the page: the requested URL and the final URL,
        /// each with the format.
        let keys: Set<WebPageCacheKey>

        /// The converted page.
        let page: ConvertedWebPage
    }

    /// The maximum number of pages.
    let capacity: Int

    /// The pages, from the least recently used to the most recently used.
    private var entries: [Entry] = []

    /// Makes an empty cache.
    ///
    /// - Parameter capacity: The maximum number of pages.
    init(capacity: Int) {
        self.capacity = capacity
    }

    /// Finds the page of a key, and makes it the most recently used page.
    ///
    /// - Parameter key: The key.
    /// - Returns: The page, or `nil` when no entry has the key.
    mutating func page(for key: WebPageCacheKey) -> ConvertedWebPage? {
        guard let index = entries.firstIndex(where: { $0.keys.contains(key) }) else { return nil }
        let entry = entries.remove(at: index)
        entries.append(entry)
        return entry.page
    }

    /// Stores a page as the most recently used page, and removes the least
    /// recently used pages past the capacity.
    ///
    /// An old entry that has one of `keys` is replaced. The new entry keeps
    /// the keys of that old entry, because each of them finds the same page.
    ///
    /// - Parameters:
    ///   - page: The page.
    ///   - keys: The keys that find the page.
    mutating func insert(_ page: ConvertedWebPage, keys: Set<WebPageCacheKey>) {
        let replaced = entries.filter { !$0.keys.isDisjoint(with: keys) }
        entries.removeAll { !$0.keys.isDisjoint(with: keys) }
        let allKeys = replaced.reduce(keys) { $0.union($1.keys) }
        entries.append(Entry(keys: allKeys, page: page))
        entries.removeFirst(max(entries.count - capacity, 0))
    }
}
