// `SessionsGraphOriginTests` — the `SessionOrigin` enum value of the
// `sessions` endpoint for each origin of the session directory.

import FoundationModelsExtras
import Testing

@testable import FoundationModelsMultitool

/// The enum value of the origins of the session directory.
@Suite("SessionsGraphOriginTests")
struct SessionsGraphOriginTests {

    /// A session that an import made has the origin `IMPORT`.
    @Test func anImportedSessionHasTheOriginImport() {
        #expect(SessionsGraphOrigin(.import).rawValue == "IMPORT")
    }
}
