import Foundation
import ULID

@testable import FoundationModelsMultitool

/// A fake ``SessionTranscriptSearcher``: it gives the same page for each
/// search, and it records each request, so a case can read what the
/// operation asked for.
actor RecordingTranscriptSearcher: SessionTranscriptSearcher {
    /// The page of each search.
    let page: SessionSearchPage

    /// Each request, the oldest first.
    private(set) var requests: [SessionSearchRequest] = []

    /// Makes the searcher.
    ///
    /// - Parameter page: The page of each search. The default is a page with
    ///   no session.
    init(page: SessionSearchPage = SessionSearchPage(sessions: [], nextCursor: nil, unavailableFolders: [])) {
        self.page = page
    }

    /// Records the request, and gives ``page``.
    ///
    /// - Parameter request: The request of the search.
    /// - Returns: ``page``.
    func search(_ request: SessionSearchRequest) async throws -> SessionSearchPage {
        requests.append(request)
        return page
    }
}
