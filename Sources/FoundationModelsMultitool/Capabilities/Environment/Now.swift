// `Now` — the `tools.environment.now` verb.
//
// The verb gives the date and the time now, in one time zone: the local time
// with its offset, the same instant in UTC, the date, the time, the day of the
// week, the time zone, the offset, and the seconds since 1970. The user decided
// (2026-10-08) that one `now` verb gives the date and the time, not two verbs
// `date` and `time`.
//
// The verb is a plain `FoundationModels.Tool` that holds the context of the
// environment capability, in the pattern of `Variables.swift`. The capability
// supplies the noun, thus this verb's `name` is the bare `now` and the surface
// path renders as `tools.environment.now`.
//
// The verb reads the clock through `EnvironmentContext.now` at each call, and
// uses `EnvironmentContext.timeZone` when the model gives no time zone. A test
// injects a fixed clock and a fixed time zone.
//
// **Each format uses the Gregorian calendar and the `en_US_POSIX` locale.**
// Thus the text does not change with the locale or the calendar of the user.
//
// An unknown time zone stays IN BAND, as a `correction` beside empty fields. It
// is never thrown: it is a mistake that the model can correct inside the turn,
// and a thrown error would end the turn instead.

import Foundation
import FoundationModels

/// The arguments of `tools.environment.now`: one time zone, or none.
@Generable(description: "The time zone to show the date and the time in, or none for the time zone of the session.")
struct NowArguments {

    /// The IANA identifier of a time zone, or `nil` for the time zone of the
    /// session.
    @Guide(
        description:
            "An IANA time zone identifier, for example Europe/Paris or America/New_York. Null to use the time "
            + "zone of the session.")
    var timeZone: String?
}

/// The result of `tools.environment.now`: the date and the time now, or the
/// correction that says why there is no date.
///
/// `correction` and the other fields are exclusive. A result that gives the
/// date carries no correction, and a correction carries empty text and zero in
/// each other field.
@Generable(description: "The date and the time now, or the correction that says why there is no date.")
struct NowResult {

    /// The local time with its offset, for example
    /// `2026-10-08T14:03:27-07:00`.
    @Guide(description: "The local time with its offset, for example 2026-10-08T14:03:27-07:00.")
    var iso8601: String

    /// The same instant in UTC, for example `2026-10-08T21:03:27Z`.
    @Guide(description: "The same instant in UTC, for example 2026-10-08T21:03:27Z.")
    var utc: String

    /// The local date, as `yyyy-MM-dd`.
    @Guide(description: "The local date, as yyyy-MM-dd.")
    var date: String

    /// The local time of the day, as `HH:mm:ss` on a 24-hour clock.
    @Guide(description: "The local time of the day, as HH:mm:ss on a 24-hour clock.")
    var time: String

    /// The English name of the local day of the week, for example
    /// `Thursday`.
    @Guide(description: "The English name of the local day of the week, for example Thursday.")
    var weekday: String

    /// The identifier of the time zone, for example `America/Los_Angeles`.
    @Guide(description: "The identifier of the time zone, for example America/Los_Angeles.")
    var timeZone: String

    /// The offset of the time zone from UTC at this instant, for example
    /// `-07:00`.
    @Guide(description: "The offset from UTC at this instant, for example -07:00.")
    var utcOffset: String

    /// The whole seconds since 1970-01-01T00:00:00Z.
    @Guide(description: "The whole seconds since 1970-01-01T00:00:00Z.")
    var epochSeconds: Int

    /// Why the verb gives no date, or `nil` when the date stands.
    @Guide(description: "Why the verb gives no date; null when the date stands.")
    var correction: String?
}

extension Now {

    // MARK: Formats

    /// The patterns of the text fields, in the syntax of `DateFormatter`.
    private enum Pattern {

        /// The local time with its offset.
        static let iso8601 = "yyyy-MM-dd'T'HH:mm:ssxxxxx"

        /// The instant in UTC, with the `Z` designator.
        static let utc = "yyyy-MM-dd'T'HH:mm:ss'Z'"

        /// The local date.
        static let date = "yyyy-MM-dd"

        /// The local time of the day, on a 24-hour clock.
        static let time = "HH:mm:ss"

        /// The full name of the day of the week.
        static let weekday = "EEEE"

        /// The offset from UTC, with a colon.
        static let utcOffset = "xxxxx"
    }

    /// The locale of each format. It does not change with the user.
    private static let posixLocale = Locale(identifier: "en_US_POSIX")

    // MARK: Corrective text

    /// The correction for an identifier that names no time zone.
    ///
    /// - Parameter identifier: The identifier that the model gave.
    /// - Returns: The correction the model reads.
    private static func unknownTimeZoneCorrection(for identifier: String) -> String {
        "the time zone \(identifier) is not known; give an IANA time zone identifier, for example "
            + "Europe/Paris, or give no timeZone to use the time zone of the session"
    }

    // MARK: Execution

    /// Gives the date and the time now, or the correction that says why there
    /// is no date.
    ///
    /// Reads the clock through the context at each call. An unknown time zone
    /// comes back as the `correction` field of the result; nothing here
    /// throws.
    ///
    /// - Parameter arguments: The time zone, or none.
    /// - Returns: The date and the time, or the correction.
    func call(arguments: NowArguments) async throws -> NowResult {
        guard let identifier = arguments.timeZone else {
            return Self.result(at: context.now(), in: context.timeZone)
        }
        guard let zone = TimeZone(identifier: identifier) else {
            return Self.corrective(Self.unknownTimeZoneCorrection(for: identifier))
        }
        return Self.result(at: context.now(), in: zone)
    }

    // MARK: Steps

    /// The result for one instant in one time zone.
    ///
    /// - Parameters:
    ///   - instant: The date and the time to show.
    ///   - zone: The time zone of each local field.
    /// - Returns: Each field of the date and the time.
    private static func result(at instant: Date, in zone: TimeZone) -> NowResult {
        NowResult(
            iso8601: text(of: instant, as: Pattern.iso8601, in: zone),
            utc: text(of: instant, as: Pattern.utc, in: .gmt),
            date: text(of: instant, as: Pattern.date, in: zone),
            time: text(of: instant, as: Pattern.time, in: zone),
            weekday: text(of: instant, as: Pattern.weekday, in: zone),
            timeZone: zone.identifier,
            utcOffset: text(of: instant, as: Pattern.utcOffset, in: zone),
            epochSeconds: Int(instant.timeIntervalSince1970.rounded(.down)),
            correction: nil)
    }

    /// The text of one instant in one pattern and one time zone.
    ///
    /// Each call makes a new formatter, because `DateFormatter` is not
    /// `Sendable` and a verb call can run on each thread.
    ///
    /// - Parameters:
    ///   - instant: The date and the time to show.
    ///   - pattern: The pattern, in the syntax of `DateFormatter`.
    ///   - zone: The time zone of the text.
    /// - Returns: The text.
    private static func text(of instant: Date, as pattern: String, in zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = posixLocale
        formatter.timeZone = zone
        formatter.dateFormat = pattern
        return formatter.string(from: instant)
    }

    // MARK: Corrective results

    /// A result that carries only a correction: empty text and zero in each
    /// other field.
    ///
    /// - Parameter message: The correction the model reads and acts on.
    /// - Returns: The corrective ``NowResult``.
    private static func corrective(_ message: String) -> NowResult {
        NowResult(
            iso8601: "", utc: "", date: "", time: "", weekday: "", timeZone: "", utcOffset: "", epochSeconds: 0,
            correction: message)
    }
}

/// Gives the date and the time now.
///
/// ```swift
/// // In a snippet the model writes:
/// //   const { date, time, weekday } = await tools.environment.now({ timeZone: "Europe/Paris" });
/// ```
///
/// The contract: with no argument, the date and the time in the time zone of
/// the session; with `timeZone`, the date and the time in that time zone. An
/// unknown time zone comes back as a `correction`, not as an error.
struct Now: Tool {

    /// The verb this tool renders as, which the environment noun stands in
    /// front of: `tools.environment.now`.
    let name = "now"

    /// The usage instructions, as the model reads them.
    let description = """
        now gives the date and the time now. With no argument it uses the time zone of the session; \
        timeZone gives an IANA time zone identifier to use instead, for example Europe/Paris. iso8601 is \
        the local time with its offset, for example 2026-10-08T14:03:27-07:00. utc is the same instant in \
        UTC, for example 2026-10-08T21:03:27Z. date is yyyy-MM-dd, and time is HH:mm:ss on a 24-hour \
        clock. weekday is the English name of the day, for example Thursday. timeZone is the identifier \
        of the time zone, and utcOffset is its offset from UTC, for example -07:00. epochSeconds is the \
        whole seconds since 1970-01-01T00:00:00Z. An unknown time zone comes back as a correction rather \
        than as an error — read it and act on it.
        """

    /// The session context this verb reads against, which the environment
    /// capability owns.
    ///
    /// The compiler-synthesized memberwise initializer takes this one
    /// property, thus the capability makes the verb as `Now(context:)`.
    let context: EnvironmentContext
}
