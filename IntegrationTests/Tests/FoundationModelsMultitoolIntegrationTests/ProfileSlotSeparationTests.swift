import Testing

import FoundationModelsRouter

/// Every profile constant a session suite of this target resolves.
///
/// `multitoolTinyProfile` is what the answer-grading suites resolve.
/// `plumbingProbeProfile` is what the plumbing probes resolve.
/// `agentDiscoveryProfile` is what the agent discovery suites resolve. A new
/// profile constant that a suite resolves goes in this list too.
let sessionSuiteProfiles = [multitoolTinyProfile, plumbingProbeProfile, agentDiscoveryProfile]

/// The model-free guard over the slot layout of every profile a session suite
/// resolves.
///
/// **Why.** `searchTools` is synchronous: it runs the selection tier on
/// `flash` from inside a tool call of the session on `standard`. When one model
/// serves both slots, that nested generation needs the model that the outer
/// submission holds open, and the work-queue Router refuses it at once with
/// `GenerationQueueError.waitInsideOpenSubmission(model:)`. A later Router may
/// refuse such a profile at `Router.resolve`. So no profile of this target may
/// name one model in both `standard` and `flash`.
///
/// Model-free on purpose: it reads the profile constants and loads nothing, so
/// it gives its answer in milliseconds on any machine that builds this
/// package, before a live suite pays for a model load to find the same fault.
@Suite("Session profiles keep standard and flash on different models")
struct ProfileSlotSeparationTests {
    @Test("no profile a session suite resolves names one model in both standard and flash",
          arguments: sessionSuiteProfiles)
    func standardAndFlashDoNotOverlap(profile: ProfileDefinition) {
        let shared = Set(profile.standard).intersection(profile.flash)
        #expect(
            shared.isEmpty,
            """
            profile \(profile.name) names \(shared.map(\.stringValue).sorted()) in both standard and flash; \
            a synchronous searchTools inside a session then gets waitInsideOpenSubmission
            """
        )
    }

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
