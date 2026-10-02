@testable import FoundationModelsMultitool
import Testing

/// Tests for ``BoundParameter``: the shared bound check and corrective message
/// of a bounded integer verb parameter.
@Suite("BoundParameter")
struct BoundParameterTests {
    /// The inclusive range of the bound under test.
    private static let range = 1...20

    /// The bound that the range initializer makes from ``range``.
    private static let bound = BoundParameter(parameterName: "count", typeDescription: "result count", range: range)

    /// The corrective message that names ``range``.
    private static let correction = "The `count` parameter must be a result count between 1 and 20."

    /// The range initializer takes its minimum from the lower end and its
    /// maximum from the upper end of the range.
    @Test func rangeInitializerReadsBothEnds() {
        #expect(Self.bound.minimum == Self.range.lowerBound)
        #expect(Self.bound.maximum == Self.range.upperBound)
        #expect(Self.bound.correctiveMessage == Self.correction)
    }

    /// A bound made from a range accepts each end of the range and refuses
    /// each value that is one step outside it.
    @Test func rangeInitializerChecksBothEnds() {
        #expect(Self.bound.violation(Self.range.lowerBound) == nil)
        #expect(Self.bound.violation(Self.range.upperBound) == nil)
        #expect(Self.bound.violation(Self.range.lowerBound - 1) == Self.correction)
        #expect(Self.bound.violation(Self.range.upperBound + 1) == Self.correction)
    }
}
