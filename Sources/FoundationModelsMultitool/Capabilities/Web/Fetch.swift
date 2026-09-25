// `Fetch` — the `tools.web.fetch` verb (web.md § "The surface",
// § "Corrections, not throws", and § "Fetch / The pipeline").
//
// The verb is a plain `FoundationModels.Tool` that holds the `WebContext` of
// the web capability, in the pattern of `Capabilities/Files/Read.swift`. The
// capability supplies the noun, thus the verb's `name` is the bare `fetch`
// and the surface path renders as `tools.web.fetch`.
//
// The verb checks its arguments (pipeline step 1), then asks the page reader
// of the context for one window of the page. The reader does the guard, the
// request, the body, the conversion, the window, and the page cache. The verb
// is synchronous and does not conform to `BackgroundTool` (web.md
// § "Decisions", item 3).
//
// A non-2xx status is a normal result with the status and the content. A bad
// argument, a guard refusal, a timeout, a network failure, and a type that is
// not text each stay IN BAND, as a `correction`. The verb never throws for
// them.

import Foundation
import FoundationModels

/// The arguments of `tools.web.fetch`: the URL, the format, and the window.
@Generable
struct FetchArguments {
    /// The absolute `http` or `https` URL of the page.
    @Guide(description: "The absolute http or https URL of the page, for example a url from tools.web.search.")
    var url: String

    /// The format name, or `nil` for `markdown`.
    @Guide(
        description:
            "The format of the content: markdown (the default), text with no markdown marks, or raw with no change.")
    var format: String?

    /// The character offset of the window, or `nil` for 0.
    @Guide(description: "The character offset of the window. Omit it to start at 0. Use nextOffset to read on.")
    var offset: Int?

    /// The maximum number of characters in the window, or `nil` for 20000.
    @Guide(description: "The maximum number of characters in the window, 500 to 200000. Omit it for 20000.")
    var maxCharacters: Int?

    /// The time limit in seconds, or `nil` for the default of the policy.
    @Guide(description: "The time limit of the download in seconds, 1 to 120. Omit it for 30.")
    var timeout: Int?
}

/// The result of `tools.web.fetch`: one window of the page, or the
/// correction that says why there is none.
///
/// `correction` and the page are exclusive. A fetch that gives a page has no
/// correction. A correction has the requested URL, status 0, and no content.
@Generable(description: "one window of the fetched page, or the correction that says why there is none.")
struct FetchResult {
    /// The final URL, after the redirects. On a correction, the requested
    /// URL.
    var url: String

    /// The HTTP status. A non-2xx status is a result, not a correction. 0 on
    /// a correction.
    var status: Int

    /// The media type from the response, for example `text/html`. Empty on a
    /// correction.
    var contentType: String

    /// The title of an HTML page, or `nil`.
    var title: String?

    /// The characters of the window of the converted content.
    var content: String

    /// The number of characters in the full converted content.
    var totalCharacters: Int

    /// The `offset` of the next window, or `nil` at the end of the page.
    var nextOffset: Int?

    /// Facts about the page, for example that the download stopped at the
    /// byte limit, or `nil` when there are none.
    var notes: [String]?

    /// Why the fetch gave no page, or `nil` when the page stands.
    var correction: String?
}

extension Fetch {
    // MARK: Bounds

    /// The window size of a fetch that omits `maxCharacters`.
    private static let defaultMaxCharacters = 20_000

    /// The smallest accepted `maxCharacters`.
    private static let minimumMaxCharacters = 500

    /// The largest accepted `maxCharacters`.
    private static let maximumMaxCharacters = 200_000

    /// The largest accepted `timeout`, in seconds.
    private static let maximumTimeout = 120

    /// The bound on `offset`: a character offset of 0 or more.
    private static let offsetBound = BoundParameter(
        parameterName: "offset", typeDescription: "character offset", minimum: 0)

    /// The bound on `maxCharacters`.
    private static let maxCharactersBound = BoundParameter(
        parameterName: "maxCharacters", typeDescription: "character count",
        minimum: minimumMaxCharacters, maximum: maximumMaxCharacters)

    /// The bound on `timeout`: 1 to ``maximumTimeout`` seconds.
    private static let timeoutBound = BoundParameter(
        parameterName: "timeout", typeDescription: "number of seconds", minimum: 1, maximum: maximumTimeout)

    /// The URL schemes that the verb fetches.
    private static let fetchSchemes: Set<String> = ["http", "https"]

    // MARK: Corrective messages

    /// The correction for an unknown `format`, with the accepted names.
    private static let formatCorrection = EnumParameter.unknownValueMessage(
        validNames: WebPageFormat.allCases.map(\.rawValue), parameterName: "format")

    /// The correction for a `url` that is not an absolute `http` or `https`
    /// URL.
    ///
    /// - Parameter url: The rejected value.
    /// - Returns: The correction, with the value at the end.
    private static func urlCorrection(_ url: String) -> String {
        "The `url` parameter must be an absolute http or https URL: \(url)"
    }

    /// The note of a body that stopped at the byte limit.
    ///
    /// - Parameter byteLimit: The byte limit of the policy.
    /// - Returns: The note.
    private static func truncationNote(byteLimit: Int) -> String {
        "The download stopped at \(byteLimit) bytes. The page is not complete."
    }

    // MARK: Execution

    /// Checks the arguments, fetches the page, and gives one window of it, or
    /// the correction that says why there is none.
    ///
    /// - Parameter arguments: The URL, the format, and the window.
    /// - Returns: The window, or the correction. Nothing here throws for a bad
    ///   argument or a failed fetch.
    func call(arguments: FetchArguments) async throws -> FetchResult {
        let corrective: (String) -> FetchResult = { message in Self.corrective(message, url: arguments.url) }
        let policy = context.fetcher.policy
        return await Self.request(from: arguments, policy: policy).resolveAsync(corrective: corrective) { request in
            await context.reader.read(
                url: request.url, format: request.format, offset: request.offset,
                maxCharacters: request.maxCharacters, timeout: request.timeout
            )
            .resolve(corrective: corrective) { window in Self.result(of: window, byteLimit: policy.maxBytes) }
        }
    }

    /// Checks the arguments and makes the request of the reader.
    ///
    /// The checks run in the order of the arguments and stop at the first
    /// failure, because a correction is one message.
    ///
    /// - Parameters:
    ///   - arguments: The arguments of the call.
    ///   - policy: The fetch policy, which gives the default time limit.
    /// - Returns: The request, or the rejection with its correction.
    private static func request(
        from arguments: FetchArguments, policy: WebFetchPolicy
    ) -> Result<PageRequest, CorrectiveRejection> {
        guard let url = httpURL(arguments.url) else {
            return .failure(CorrectiveRejection(correctiveMessage: urlCorrection(arguments.url)))
        }
        guard let format = WebPageFormat(rawValue: (arguments.format ?? WebPageFormat.markdown.rawValue).lowercased())
        else {
            return .failure(CorrectiveRejection(correctiveMessage: formatCorrection))
        }
        let bounds = [
            offsetBound.violation(arguments.offset),
            maxCharactersBound.violation(arguments.maxCharacters),
            timeoutBound.violation(arguments.timeout)
        ]
        if let message = bounds.compactMap({ $0 }).first {
            return .failure(CorrectiveRejection(correctiveMessage: message))
        }
        let timeout = arguments.timeout.map { Duration.seconds($0) } ?? .seconds(policy.defaultFetchTimeout)
        return .success(
            PageRequest(
                url: url, format: format, offset: arguments.offset ?? 0,
                maxCharacters: arguments.maxCharacters ?? defaultMaxCharacters, timeout: timeout))
    }

    /// Reads an absolute `http` or `https` URL with a host.
    ///
    /// URL schemes are not case-sensitive, thus `HTTPS://` is also correct.
    ///
    /// - Parameter text: The value of `url`.
    /// - Returns: The URL, or `nil` when the text is not an absolute `http` or
    ///   `https` URL with a host.
    private static func httpURL(_ text: String) -> URL? {
        guard let url = URL(string: text),
            let scheme = url.scheme?.lowercased(),
            fetchSchemes.contains(scheme),
            url.host()?.isEmpty == false
        else { return nil }
        return url
    }

    /// Makes the result of one window.
    ///
    /// - Parameters:
    ///   - window: The window of the page.
    ///   - byteLimit: The byte limit of the policy, which the truncation note
    ///     names.
    /// - Returns: The result, with the truncation note when the body stopped
    ///   at the byte limit.
    private static func result(of window: PageWindow, byteLimit: Int) -> FetchResult {
        FetchResult(
            url: window.url.absoluteString, status: window.status, contentType: window.contentType,
            title: window.title, content: window.content, totalCharacters: window.totalCharacters,
            nextOffset: window.nextOffset, notes: window.truncated ? [truncationNote(byteLimit: byteLimit)] : nil,
            correction: nil)
    }

    /// A result that holds only a correction: the requested URL, status 0,
    /// and no content.
    ///
    /// - Parameters:
    ///   - message: The correction that the model reads and acts on.
    ///   - url: The requested URL text.
    /// - Returns: The corrective result.
    private static func corrective(_ message: String, url: String) -> FetchResult {
        FetchResult(
            url: url, status: 0, contentType: "", title: nil, content: "", totalCharacters: 0, nextOffset: nil,
            notes: nil, correction: message)
    }
}

/// One checked request of the page reader.
private struct PageRequest {
    /// The absolute `http` or `https` URL of the page.
    let url: URL

    /// The form of the content.
    let format: WebPageFormat

    /// The character offset of the window.
    let offset: Int

    /// The maximum number of characters in the window.
    let maxCharacters: Int

    /// The time limit of the download.
    let timeout: Duration
}

/// Fetches one URL, and gives the page as markdown, text, or raw content, in
/// windows.
///
/// ```swift
/// // In a snippet the model writes:
/// //   const page = await tools.web.fetch({ url: "https://www.swift.org/", maxCharacters: 5000 });
/// ```
///
/// The guard refuses a private, loopback, or local address. A non-2xx page is
/// a result with its status. A bad argument and a failed fetch each come back
/// as a `correction`, not as an error. The context is the context that the
/// web capability owns, thus a second window of one page comes from the page
/// cache and makes no new download.
struct Fetch: Tool {
    /// The verb that this tool renders as, after the web noun:
    /// `tools.web.fetch`.
    let name = "fetch"

    /// The usage instructions, as the model reads them.
    let description = """
        fetch downloads one web page and gives its content. Use it to read a page whose URL you \
        have, for example a url from tools.web.search. The normal pattern is tools.web.search then \
        tools.web.fetch in one snippet. Promise.all fetches pages in parallel, for example await \
        Promise.all(urls.map(url => tools.web.fetch({ url, maxCharacters: 5000 }))). url must be an \
        absolute http or https URL. format is markdown (the default), text, or raw. The content \
        comes in windows: maxCharacters is 500 to 200000 (default 20000), and nextOffset is the \
        offset of the next window, or null at the end. timeout is 1 to 120 seconds (default 30). A \
        page with a status that is not 2xx is still a result: read status and content. notes tell \
        when the download stopped at the byte limit. A bad argument, a refused address, a timeout, \
        or a type that is not text comes back as a correction rather than as an error — read it, \
        correct the call, and ask again.
        """

    /// The web context that this verb fetches with, which the web capability
    /// owns.
    ///
    /// The compiler-synthesized memberwise initializer takes this one
    /// property, thus the capability makes the verb as `Fetch(context:)`.
    let context: WebContext
}
