import Testing

import FoundationModels
import FoundationModelsMultitool
import FoundationModelsRouter
import JavaScriptCore

/// Scaffold-only checks for M0: the package skeleton compiles and links
/// against every dependency the plan requires. There is no behavior yet, so
/// successfully importing all four modules — the ability to compile this
/// file at all — is the assertion.
@Suite("Scaffold")
struct ScaffoldTests {
    @Test("package, system frameworks, and Router dependency all import")
    func modulesImport() {
        #expect(true)
    }
}
