extension Array {
    /// The result of `transform` on each element, in order. Each call waits
    /// for the call before it, so the side effects of `transform` happen in
    /// the order of the array.
    ///
    /// - Parameter transform: The work on one element.
    /// - Returns: The results, in the order of the elements.
    /// - Throws: The first error of `transform`; no element after it runs.
    func asyncMap<Mapped>(_ transform: (Element) async throws -> Mapped) async rethrows -> [Mapped] {
        guard let head = first else {
            return []
        }
        let mappedHead = try await transform(head)
        return try await [mappedHead] + Array(dropFirst()).asyncMap(transform)
    }
}
