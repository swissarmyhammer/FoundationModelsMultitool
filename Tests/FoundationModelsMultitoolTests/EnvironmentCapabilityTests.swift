import Foundation
import FoundationModels
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Coverage for `EnvironmentCapability` and for
/// `MultiTool.Builder.withEnvironment()` (task `^9p3e1nh`).
///
/// Three properties carry this suite, and each one is a sentence of
/// eventplan.md § "The capability contract":
///
/// 1. The capability owns ONE noun, `environment`. Each verb task adds its
///    verb to `EnvironmentCapability.tools` and to ``verbNames``.
/// 2. The capability is OFF by default: a builder that never calls
///    `withEnvironment()` renders no entry under that noun, and a second
///    registration of the noun fails loudly at `buildRegistry()`.
/// 3. The default context reads the real process at each call.
@Suite("EnvironmentCapabilityTests")
struct EnvironmentCapabilityTests {

    /// The one noun this capability owns.
    private static let environmentNoun = "environment"

    /// The first segment of every path the capability claims, with its
    /// separator.
    private static let environmentPathPrefix = "\(environmentNoun)."

    /// The verbs of the capability, in render order.
    private static let verbNames = ["variables", "os", "now"]

    /// The rendered call path of the one tool the off-by-default test
    /// registers instead, which proves that test reads a surface that was
    /// really built.
    private static let unrelatedToolPath = "getWeather"

    // MARK: - The noun

    /// The capability owns the `environment` noun, and holds each verb that a
    /// verb task added, in render order.
    @Test("the capability owns the environment noun and holds its verbs")
    func theCapabilityOwnsTheEnvironmentNounAndHoldsItsVerbs() {
        let capability = EnvironmentCapability()

        #expect(capability.noun == Self.environmentNoun)
        #expect(capability.tools.map(\.name) == Self.verbNames)
    }

    /// `withEnvironment()` renders each verb under the `environment` noun.
    @Test("withEnvironment renders each verb under the environment noun")
    func withEnvironmentRendersEachVerbUnderTheEnvironmentNoun() throws {
        let surface = try MultiTool.Builder().withEnvironment().build()

        #expect(surface.entries.map(\.path) == Self.verbNames.map { Self.environmentPathPrefix + $0 })
    }

    /// The capability holds the context it was made with, thus each verb
    /// reads the inputs that a test injects.
    @Test("the capability holds the context it was made with")
    func theCapabilityHoldsTheContextItWasMadeWith() {
        let injected = ["ONLY": "value"]
        let capability = EnvironmentCapability(context: EnvironmentContext(variables: { injected }))

        #expect(capability.context.variables() == injected)
    }

    // MARK: - The default context

    /// The default context reads the variables of this process.
    @Test("the default context reads the variables of this process")
    func theDefaultContextReadsTheVariablesOfThisProcess() {
        let context = EnvironmentContext()

        #expect(context.variables() == ProcessInfo.processInfo.environment)
    }

    /// The default context reads the clock at each call, thus its date falls
    /// between two reads of the clock that stand around the call.
    @Test("the default context reads the clock at each call")
    func theDefaultContextReadsTheClockAtEachCall() {
        let context = EnvironmentContext()

        let before = Date()
        let now = context.now()
        let after = Date()

        #expect(before <= now)
        #expect(now <= after)
    }

    /// The default context uses the current time zone.
    @Test("the default context uses the current time zone")
    func theDefaultContextUsesTheCurrentTimeZone() {
        let context = EnvironmentContext()

        #expect(context.timeZone == TimeZone.current)
    }

    // MARK: - The builder short form

    /// `withEnvironment()` claims the whole `tools.environment` namespace: a
    /// tool that another registration puts under the noun fails at
    /// `buildRegistry()`.
    @Test("withEnvironment claims the environment noun, and a second registration under it makes buildRegistry() throw")
    func withEnvironmentClaimsTheEnvironmentNoun() {
        #expect {
            try MultiTool.Builder()
                .withEnvironment()
                .register(noun: Self.environmentNoun, tool: WeatherTool())
                .buildRegistry()
        } throws: { error in
            Self.isBuilderError(error, of: .duplicateNoun, naming: Self.environmentNoun)
        }
    }

    /// A second `withEnvironment()` is a second claim on the same noun. Its
    /// verbs collide path by path, so `buildRegistry()` reports the first
    /// path collision, the same as a second `withGit(root:)` — loudly, and
    /// never a quiet merge.
    @Test("a second withEnvironment registration makes buildRegistry() throw")
    func aSecondWithEnvironmentRegistrationThrows() {
        #expect {
            try MultiTool.Builder()
                .withEnvironment()
                .withEnvironment()
                .buildRegistry()
        } throws: { error in
            Self.isBuilderError(error, of: .duplicateName, naming: Self.verbNames.first)
        }
    }

    /// The internal short form registers the capability over the context that
    /// a test gives, under the same noun.
    @Test("withEnvironment(context:) renders each verb under the environment noun")
    func withEnvironmentContextRendersEachVerbUnderTheEnvironmentNoun() throws {
        let surface = try MultiTool.Builder()
            .withEnvironment(context: EnvironmentContext(variables: { [:] }))
            .build()

        #expect(surface.entries.map(\.path) == Self.verbNames.map { Self.environmentPathPrefix + $0 })
    }

    /// eventplan.md § "The capability contract": "The modules are opt-in ...
    /// They are off by default." A builder that never asked for the
    /// environment capability renders nothing under its noun.
    @Test("a builder with no withEnvironment renders no entry under the environment noun")
    func aBuilderWithNoWithEnvironmentRendersNoEnvironmentEntry() throws {
        let surface = try MultiTool.Builder().addTool(WeatherTool()).build()

        // The unrelated tool proves the surface was really built, thus the two
        // expectations below read an answer rather than an empty catalog.
        #expect(surface.entries.map(\.path) == [Self.unrelatedToolPath])
        #expect(!surface.entries.contains { $0.path.hasPrefix(Self.environmentPathPrefix) })
        #expect(!surface.entries.contains { $0.path == Self.environmentNoun })
    }

    // MARK: - Helpers

    /// Whether `error` is the builder failure of one kind, for one name.
    ///
    /// - Parameters:
    ///   - error: The error that `buildRegistry()` threw.
    ///   - kind: The kind of failure that the test expects.
    ///   - name: The noun or the verb that the failure must name.
    /// - Returns: `true` for that failure.
    private static func isBuilderError(
        _ error: any Error, of kind: MultiToolBuilderError.Kind, naming name: String?
    ) -> Bool {
        let builderError = error as? MultiToolBuilderError
        return builderError?.kind == kind && builderError?.name == name
    }
}
