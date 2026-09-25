@testable import FoundationModelsMultitool
import Testing

/// Tests for ``SearchFreshnessValues``: the table of the values of one
/// provider field for each age limit.
///
/// Each provider test checks the documented values of its own table. This
/// suite checks that the table gives the value of each age limit from the
/// field of that age limit.
@Suite("SearchFreshnessValues")
struct SearchFreshnessValuesTests {
    /// A table with a different value for each age limit.
    private static let table = SearchFreshnessValues(day: "d-value", week: "w-value", month: "m-value", year: "y-value")

    @Test(
        "the table gives the value of the field of each age limit",
        arguments: [(SearchFreshness.day, "d-value"), (.week, "w-value"), (.month, "m-value"), (.year, "y-value")])
    func valueOfEachAgeLimit(freshness: SearchFreshness, value: String) {
        #expect(Self.table.value(for: freshness) == value)
    }
}
