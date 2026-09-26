import FoundationModelsRouter
import Testing

@testable import MultitoolCLI

/// Coverage for the model profile the sample CLI resolves (`CLIRunner.demoProfile`).
///
/// `searchTools` is synchronous. Its selection session runs on `flash`, inside
/// the open submission of the session on `standard`. Router refuses a wait on
/// the model of that open submission, so the two slots must not share a model.
@Suite("DemoProfile")
struct DemoProfileTests {
    @Test("the flash slot and the standard slot of demoProfile have no model in common")
    func flashAndStandardHaveNoModelInCommon() {
        let profile = CLIRunner.demoProfile

        #expect(Set(profile.standard).isDisjoint(with: profile.flash))
    }

    @Test("the flash slot of demoProfile names flashModel, and the standard slot names generationModel")
    func slotsNameTheirOwnConstants() {
        let profile = CLIRunner.demoProfile

        #expect(profile.flash == [CLIRunner.flashModel])
        #expect(profile.standard == [CLIRunner.generationModel])
    }
}
