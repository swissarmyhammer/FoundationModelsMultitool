import Testing

import FoundationModelsRouter

/// Every profile constant a session suite of this target resolves.
///
/// `multitoolTinyProfile` is what the answer-grading suites resolve.
/// `plumbingProbeProfile` is what the plumbing probes resolve.
/// `agentDiscoveryProfile` is what the agent discovery suites resolve. A new
/// profile constant that a suite resolves goes in this list too.
let sessionSuiteProfiles = [multitoolTinyProfile, plumbingProbeProfile, agentDiscoveryProfile]

/// The model-free guard over the profiles a session suite resolves.
///
/// No profile is held to two different models in `standard` and `flash` any
/// more. The work-queue Router refused the nested selection generation of
/// `searchTools` on the model of the outer answer, and this suite once held
/// the two slots apart for that reason. Since Router `505a03f3` the lock is
/// held over the call into the model only, never over a tool call, and
/// `NestedGenerationProbeTests` holds that a nested call on the same model
/// completes.
///
/// Model-free on purpose: it reads the profile constants and loads nothing, so
/// it gives its answer in milliseconds on any machine that builds this
/// package, before a live suite pays for a model load to find the same fault.
@Suite("Session profiles")
struct SessionProfileTests {
    @Test("the list of session profiles holds each profile once")
    func eachSessionProfileIsListedOnce() {
        let names = sessionSuiteProfiles.map(\.name)
        #expect(Set(names).count == names.count)
    }

    @Test("multitoolTinyProfile names generationModel in standard, flashModel in flash, and embeddingModel in embedding")
    func tinyProfileSlotsNameTheirPins() {
        #expect(multitoolTinyProfile.standard == [generationModel])
        #expect(multitoolTinyProfile.flash == [flashModel])
        #expect(multitoolTinyProfile.embedding == [embeddingModel])
    }
}
