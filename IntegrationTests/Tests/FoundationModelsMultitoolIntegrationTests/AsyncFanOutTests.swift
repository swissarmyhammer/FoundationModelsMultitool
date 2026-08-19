import Testing

/// The gated async fan-out scenario — eventplan.md's phase-1 exit proof that
/// the "each call that goes into Swift effects returns a promise" contract
/// composes: two independent fixture tools have no ordering between them, so
/// the natural snippet awaits both at once (`Promise.all`) and combines the
/// results.
///
/// **Outcome over path.** Like every scenario in `SearchThenCallTests`, this
/// asserts the answer, never the route: whether the model actually reached for
/// `Promise.all`, two sequential `await`s, or two separate `runCode` calls is
/// deliberately unasserted — see `runNativeIntegrationScenario`'s
/// documentation for why route assertions were retired. What is asserted is
/// that the reply carries the two fixtures' *combined* total, which is only
/// reachable by genuinely reading both.
///
/// Serialized and time-limited exactly like `SearchThenCallTests`, and, like
/// every suite here, it lives in the nested `IntegrationTests` package: the
/// root `swift test` never sees it, because the root manifest declares no such
/// target, so the root suite stays green with zero downloads and zero live
/// inference. This suite runs under
/// `swift test --package-path IntegrationTests --no-parallel`.
@Suite(
    "Gated async fan-out scenario (phase-1 exit)",
    .serialized,
    .timeLimit(.minutes(30))
)
struct AsyncFanOutTests {
    /// The total the two stock fixtures combine to — derived from the fixtures
    /// themselves rather than restated, so the assertion cannot drift from the
    /// data it grades.
    private static let combinedUnits = integrationWarehouseStockUnits + integrationStoreStockUnits

    @Test("async fan-out scenario answers with the two stock fixtures' combined total")
    func fanOutOverTwoStockTools() async throws {
        try await runNativeIntegrationScenario(
            name: "fanOutOverTwoStockTools",
            tools: { log in integrationStockTools(log: log) },
            prompt: "How many units do we have in total, counting both the warehouse and the store floor?",
            // Only the sum is accepted — neither fixture's own count proves
            // both were read.
            answerContainsOneOf: integerAnswers(for: Self.combinedUnits),
            // Both counters, for the same reason the sum is the only accepted
            // answer: a total is knowable only once both of them handed a
            // count back.
            groundedIn: IntegrationScenarioGrounding.combinedStock
        )
    }
}
