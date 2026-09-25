// `WebCapability` — the `web` noun, and the two verbs that render under it
// (web.md § "Mount in code mode").
//
// This type has the same shape as `FilesCapability`. It holds no logic of its
// own. It names the noun one time, and it composes the two verbs `search` and
// `fetch`, which are plain `FoundationModels.Tool` conformers.
//
// **The capability makes the two verbs one session.** The initializer makes
// one `WebContext` and gives it to each verb. Thus the two verbs send each
// request through one session and one address guard, and they share one page
// cache.
//
// **The capability is off by default.** A host that never calls
// `MultiTool.Builder.withWeb(configuration:sessionConfiguration:)` renders no
// `tools.web` namespace.
//
// **The initializer sends no request.** It makes the session, the page reader
// and the search chain only. Each network question is answered per call, as a
// correction in the result of the verb.

import Foundation
import FoundationModels

/// The web capability: one noun, and the two verbs that search the web and
/// read a page.
///
/// ```swift
/// let surface = try MultiTool.Builder()
///     .withWeb()          // tools.web.search, tools.web.fetch
///     .build()
/// ```
///
/// `MultiTool.Builder.withWeb(configuration:sessionConfiguration:)` is the
/// short form of `withCapability(WebCapability(...))`, and it takes the same
/// two arguments. Register this type directly where a host makes the
/// capability one time and gives it on.
///
/// The two verbs render in the order they are listed:
///
/// | Path | What it does |
/// |---|---|
/// | `tools.web.search` | Finds pages on the web, and gives ranked hits. |
/// | `tools.web.fetch` | Downloads one page, and gives one window of its content. |
public struct WebCapability: Capability {

    /// The one namespace that each verb of this capability renders under: the
    /// first segment of `tools.web.<verb>`.
    ///
    /// The capability OWNS this noun. `MultiTool.Builder.withCapability(_:)`
    /// claims the whole `tools.web` namespace, thus a second owner of the noun
    /// fails at `buildRegistry()` and not at dispatch.
    public let noun = "web"

    /// The two verbs of the web session, in the order they render.
    ///
    /// Each verb gives its own second segment through `Tool.name`.
    public let tools: [any Tool]

    /// Makes the web capability over one session context.
    ///
    /// The initializer makes one `WebContext` from its two arguments, and it
    /// gives that context to each verb. It never throws and it sends no
    /// request.
    ///
    /// - Parameters:
    ///   - configuration: The search providers in the order to try, the fetch
    ///     policy, and the environment that the API keys come from. The
    ///     default, `.fromEnvironment()`, uses each keyed provider whose
    ///     variable is set, then the keyless providers.
    ///   - sessionConfiguration: The configuration of the one `URLSession` of
    ///     the capability. The default is `.ephemeral`. A test gives a
    ///     configuration whose `protocolClasses` holds a stub.
    public init(
        configuration: WebConfiguration = .fromEnvironment(),
        sessionConfiguration: URLSessionConfiguration = .ephemeral
    ) {
        // The one context of the session. Each verb holds it, thus the two
        // verbs share one session, one guard and one page cache.
        let context = WebContext(configuration: configuration, sessionConfiguration: sessionConfiguration)

        self.tools = [Search(context: context), Fetch(context: context)]
    }
}
