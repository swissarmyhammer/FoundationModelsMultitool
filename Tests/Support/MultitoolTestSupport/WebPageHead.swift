// `WebPageHead` — the value that the search-then-fetch snippet of web.md
// § "Goal" returns for each page.
//
// The snippet returns `pages.map(p => ({ url: p.url, title: p.title, head:
// p.content.slice(0, 400) }))`. The unit suite `WebRunCodeTests` runs it over a
// stub session, and the live suite `WebRunCodeLiveTests` of
// `IntegrationTests/` runs it over the real web. Both decode its output
// with `RunOutput.decoded(_:from:)` into this one type.

/// The value that the goal snippet of web.md returns for each page.
struct WebPageHead: Decodable, Equatable {
    /// The final URL of the page.
    let url: String

    /// The title of the page, or `nil` when the page has no title.
    let title: String?

    /// The first characters of the content of the page.
    let head: String
}
