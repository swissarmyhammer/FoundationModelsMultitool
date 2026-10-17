import Testing

// MARK: - The temporary folders of a suite with static helpers
//
// `TestSupport.makeTemporaryDirectory(named:)` is a static function, and many
// suites call it from their own static helpers. A static helper cannot reach
// a `TestScratch` that the suite holds as a stored property. Thus the trait
// in this file gives each test one `TestScratch` through a task-local value,
// and removes the folders of that test when the test ends.

/// A suite trait that gives each test of the suite one `TestScratch`, and
/// removes each path of that scratch when the test ends.
///
/// Put the trait on the suite:
///
/// ```swift
/// @Suite(.ownsTemporaryDirectories) struct SomeTests {
///     private static func makeRoot() -> URL {
///         TestSupport.makeTemporaryDirectory(named: "SomeTests")
///     }
/// }
/// ```
///
/// The scope removes the paths in a `defer`. Thus the folders go away when
/// the test body returns, and also when it throws or a `#require` fails.
/// The removal is synchronous, thus no work of the cleanup runs after the
/// test ended.
///
/// The trait is recursive: a nested suite and each test case of a
/// parameterized test gets the same scope.
struct TemporaryDirectoryScope: SuiteTrait, TestTrait, TestScoping {

    /// Each test and each nested suite of the suite gets the trait.
    var isRecursive: Bool { true }

    /// The scope of one test case. A suite gets no scope of its own, because
    /// the folders belong to the tests and not to the suite.
    ///
    /// - Parameters:
    ///   - test: The test or the suite that is about to run.
    ///   - testCase: The test case that is about to run, or `nil` for a
    ///     suite.
    /// - Returns: This trait for a test case, and `nil` for a suite.
    func scopeProvider(for test: Test, testCase: Test.Case?) -> Self? {
        testCase == nil ? nil : self
    }

    /// Runs one test case with its own `TestScratch` as
    /// `TestScratch.current`, and removes each path of that scratch after
    /// the test case, on each path.
    ///
    /// - Parameters:
    ///   - test: The test that runs.
    ///   - testCase: The test case that runs.
    ///   - function: The body of the test case.
    /// - Throws: What the body of the test case threw.
    func provideScope(
        for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void
    ) async throws {
        let scratch = TestScratch()
        defer { scratch.removeAll() }
        try await TestScratch.current.withValue(scratch) {
            try await function()
        }
    }
}

extension Trait where Self == TemporaryDirectoryScope {

    /// Each temporary folder that a test of the suite makes through
    /// `TestSupport.makeTemporaryDirectory(named:)` is removed when the test
    /// ends, also when the test throws.
    static var ownsTemporaryDirectories: Self { Self() }
}
