// `EnvironmentNowTests` — the behavioral suite of the `tools.environment.now`
// verb.
//
// Each test injects a fixed clock and a fixed time zone through an
// `EnvironmentContext`. Thus each exact value is the same on each machine, at
// each time of the day, and in each time zone of the machine. No test reads the
// real clock.

import Foundation
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Behavioral tests for the `tools.environment.now` verb (task `^c73rk0s`).
@Suite("EnvironmentNowTests")
struct EnvironmentNowTests {

    /// The injected instant: 2026-10-08T21:03:27Z, a Thursday.
    private static let instant = Date(timeIntervalSince1970: 1_791_493_407)

    /// The injected time zone of the session. It has daylight saving time.
    private static let losAngeles = "America/Los_Angeles"

    /// A time zone that the model can give as an argument. It has no daylight
    /// saving time, and it is on a different date from Los Angeles at
    /// ``instant``.
    private static let tokyo = "Asia/Tokyo"

    /// An identifier that names no time zone.
    private static let unknownZone = "Not/AZone"

    /// The instant when Los Angeles changes from PDT to PST in 2026:
    /// 2026-11-01T09:00:00Z.
    private static let endOfDaylightSavingTime = Date(timeIntervalSince1970: 1_793_523_600)

    /// The snippet that calls the verb with no argument and returns its
    /// result.
    private static let nowSnippet = "return await tools.environment.now({});"

    /// The fields at ``instant`` in Los Angeles.
    private static let losAngelesFields = Fields(
        iso8601: "2026-10-08T14:03:27-07:00",
        utc: "2026-10-08T21:03:27Z",
        date: "2026-10-08",
        time: "14:03:27",
        weekday: "Thursday",
        timeZone: losAngeles,
        utcOffset: "-07:00",
        epochSeconds: 1_791_493_407,
        correction: nil)

    // MARK: - The injected clock and time zone

    /// With no argument, the verb uses the clock and the time zone of the
    /// context, and each field is exactly the expected text.
    @Test("with no argument, each field is exactly the expected text")
    func withNoArgumentEachFieldIsExactlyTheExpectedText() async throws {
        let result = try await Self.call(at: Self.instant, timeZone: nil)

        #expect(Fields(result) == Self.losAngelesFields)
    }

    /// A `timeZone` argument changes each local field, but not the instant.
    @Test("timeZone Asia/Tokyo changes each local field, but not utc or epochSeconds")
    func aTimeZoneArgumentChangesEachLocalFieldButNotTheInstant() async throws {
        let result = try await Self.call(at: Self.instant, timeZone: Self.tokyo)

        let expected = Fields(
            iso8601: "2026-10-09T06:03:27+09:00",
            utc: Self.losAngelesFields.utc,
            date: "2026-10-09",
            time: "06:03:27",
            weekday: "Friday",
            timeZone: Self.tokyo,
            utcOffset: "+09:00",
            epochSeconds: Self.losAngelesFields.epochSeconds,
            correction: nil)
        #expect(Fields(result) == expected)
    }

    /// In a time zone with daylight saving time, the offset is correct on
    /// each side of the change.
    @Test("the offset is correct on each side of a change of daylight saving time")
    func theOffsetIsCorrectOnEachSideOfAChangeOfDaylightSavingTime() async throws {
        let before = try await Self.call(at: Self.endOfDaylightSavingTime - 1, timeZone: nil)
        let after = try await Self.call(at: Self.endOfDaylightSavingTime, timeZone: nil)

        #expect(before.iso8601 == "2026-11-01T01:59:59-07:00")
        #expect(before.utcOffset == "-07:00")
        #expect(after.iso8601 == "2026-11-01T01:00:00-08:00")
        #expect(after.utcOffset == "-08:00")
    }

    /// The fraction of a second does not show, and `epochSeconds` counts
    /// whole seconds down to the start of the second.
    @Test("epochSeconds and time ignore the fraction of a second")
    func epochSecondsAndTimeIgnoreTheFractionOfASecond() async throws {
        let result = try await Self.call(at: Self.instant + 0.9, timeZone: nil)

        #expect(result.time == Self.losAngelesFields.time)
        #expect(result.epochSeconds == Self.losAngelesFields.epochSeconds)
    }

    /// Before 1970, `epochSeconds` is the second that holds the instant, and
    /// it agrees with the time that the verb shows.
    @Test("before 1970, epochSeconds is the second that holds the instant")
    func before1970EpochSecondsIsTheSecondThatHoldsTheInstant() async throws {
        let result = try await Self.call(at: Date(timeIntervalSince1970: -0.5), timeZone: "UTC")

        #expect(result.utc == "1969-12-31T23:59:59Z")
        #expect(result.epochSeconds == -1)
    }

    // MARK: - An unknown time zone

    /// An unknown identifier gives a correction that names it, and each
    /// other field is empty or zero. The verb does not throw.
    @Test("an unknown timeZone gives a correction that names it, and no other value")
    func anUnknownTimeZoneGivesACorrectionThatNamesIt() async throws {
        let result = try await Self.call(at: Self.instant, timeZone: Self.unknownZone)

        let correction = try #require(result.correction)
        #expect(correction.contains(Self.unknownZone))
        #expect(Fields(result) == Fields(correction: correction))
    }

    // MARK: - The snippet

    /// `tools.environment.now({})` renders in a snippet and gives each field.
    @Test("tools.environment.now({}) renders and gives each field")
    func theSnippetRendersAndGivesEachField() async throws {
        let registry = try MultiTool.Builder()
            .withEnvironment(context: Self.context(at: Self.instant))
            .buildRegistry()

        let output = try await MultiTool(registry: registry).call(arguments: RunCodeArguments(code: Self.nowSnippet))

        let fields = try RunOutput.decoded(Fields.self, from: output)
        #expect(fields == Self.losAngelesFields, "the output was \(output)")
    }

    // MARK: - Helpers

    /// A context with a fixed clock and the Los Angeles time zone.
    ///
    /// - Parameter date: The instant that the clock gives at each call.
    /// - Returns: The context.
    private static func context(at date: Date) throws -> EnvironmentContext {
        let zone = try #require(TimeZone(identifier: losAngeles))
        return EnvironmentContext(now: { date }, timeZone: zone)
    }

    /// Calls the verb over a fixed clock and the Los Angeles time zone.
    ///
    /// - Parameters:
    ///   - date: The instant that the clock gives.
    ///   - timeZone: The `timeZone` argument, or `nil` for none.
    /// - Returns: The result of the verb.
    private static func call(at date: Date, timeZone: String?) async throws -> NowResult {
        try await Now(context: context(at: date)).call(arguments: NowArguments(timeZone: timeZone))
    }
}

/// The fields of one result, in a form that `#expect` compares and that a
/// snippet output decodes into.
private struct Fields: Decodable, Equatable {

    /// The local time with its offset.
    var iso8601 = ""

    /// The same instant in UTC.
    var utc = ""

    /// The local date.
    var date = ""

    /// The local time of the day.
    var time = ""

    /// The English name of the local day of the week.
    var weekday = ""

    /// The identifier of the time zone.
    var timeZone = ""

    /// The offset from UTC.
    var utcOffset = ""

    /// The whole seconds since 1970-01-01T00:00:00Z.
    var epochSeconds = 0

    /// The correction, or `nil`.
    var correction: String?
}

extension Fields {

    /// Copies the fields of one result.
    ///
    /// - Parameter result: The result of the verb.
    init(_ result: NowResult) {
        self.init(
            iso8601: result.iso8601,
            utc: result.utc,
            date: result.date,
            time: result.time,
            weekday: result.weekday,
            timeZone: result.timeZone,
            utcOffset: result.utcOffset,
            epochSeconds: result.epochSeconds,
            correction: result.correction)
    }
}
