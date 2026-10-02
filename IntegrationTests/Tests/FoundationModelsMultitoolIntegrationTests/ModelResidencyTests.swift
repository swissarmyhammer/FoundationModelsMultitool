import Foundation
import FoundationModelsExtras
import FoundationModelsRouter
import Testing

/// The label the skip note of the residency test carries.
private let residencyScenarioName = "modelResidency"

/// The gated test that holds the models of a resolved profile resident for
/// the next test of the same process.
///
/// **Why it exists.** Each scenario resolves its profile through a new
/// `Router`, which gives each scenario its own recordings directory. Router
/// takes the models from `ModelPool.shared`, and the pool loads a model one
/// time and gives a hold of it to each later user (`Router.resolve` goes to
/// `ready` with no load when the pool holds the model). When the last hold
/// goes, the pool evicts the model, and the next scenario loads it again. In
/// CI run `36951032341` that cost approximately 9 s for each of 20
/// resolutions, and a slow first generation call after each load.
/// `LiveModelResidency` keeps one hold of each model for the whole test
/// process, thus each model loads one time.
///
/// **What it reads.** The footprint of the pool, read in an admission job of
/// the pool. The pool puts the eviction of a model in the same admission
/// queue when its last hold goes, thus an admission job that runs after the
/// teardown sees the eviction when one occurred.
///
/// Packaged like every gated suite: in the nested `IntegrationTests` package,
/// out of reach of the root `swift test`, run under
/// `swift test --package-path IntegrationTests --no-parallel`, and skipping
/// cleanly when the live Router path throws
/// `GenerationError.notWiredForLiveInference`.
@Suite(
    "Model residency across the tests of one process",
    .serialized,
    .timeLimit(IntegrationHangGuard.timeLimit)
)
struct ModelResidencyTests {
    @Test("each model of a resolved profile stays resident after its fixture tears down")
    func eachModelStaysResidentAfterTearDown() async throws {
        var keys: [ModelPoolKey] = []
        try await withLiveRouterFixture(name: residencyScenarioName, profile: plumbingProbeProfile) { fixture in
            keys = LiveModelResidency.poolKeys(of: fixture.profile)
        }

        let footprint = try await ModelPool.shared.admit { admission in admission.footprint }
        for key in keys {
            #expect(
                footprint.resident[key] != nil,
                "\(key.ref.stringValue) was evicted when its fixture tore down, so the next test loads it again"
            )
        }
    }
}
