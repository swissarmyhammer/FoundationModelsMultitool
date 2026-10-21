// `Sequence.mappedInOrder(by:)` — the one way a test maps a sequence with an
// asynchronous transform, one element at a time.
//
// The unit test target and the suites of `IntegrationTests/` both map with
// it, thus it stands in the `MultitoolTestSupport` product and not in one test
// target. Each of them held a copy of it before.

extension Sequence {
    /// Maps every element with an asynchronous transform, one element at a
    /// time and in the order the sequence lists them.
    ///
    /// `map` takes no asynchronous transform, and a task group would run the
    /// elements together. Each call here waits for the call before it, so the
    /// side effects of `transform` happen in sequence order: one model call
    /// over one shared searcher, or one change to one shared directory. This
    /// walks the head and then the tail and joins the two answers. It builds
    /// the array from those answers, and never by mutating an empty one.
    ///
    /// - Parameter transform: what to make of one element.
    /// - Returns: what `transform` answered for each element, in sequence
    ///   order.
    /// - Throws: whatever `transform` throws, unchanged; no element after it
    ///   runs.
    public func mappedInOrder<Transformed>(
        by transform: (Element) async throws -> Transformed
    ) async rethrows -> [Transformed] {
        let elements = Array(self)
        guard let head = elements.first else { return [] }
        let tail = elements.dropFirst()
        return try await [transform(head)] + tail.mappedInOrder(by: transform)
    }
}
