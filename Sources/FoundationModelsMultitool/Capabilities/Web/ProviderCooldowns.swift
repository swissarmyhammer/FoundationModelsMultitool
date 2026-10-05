// `ProviderCooldowns` — the cooldown of a search provider after HTTP 429
// (web.md § "Fallback").
//
// A provider that sends HTTP 429 gets a cooldown. During the cooldown, the
// chain sends no request to that provider, thus the chain does not make the
// block of the provider longer. The time of the cooldown comes from the
// `Retry-After` header of the response, else it is ``defaultCooldown``. It is
// never longer than ``maximumCooldown``.
//
// The store lives as long as its `WebSearchChain`, thus as long as the
// `WebContext` that holds the chain. The store reads the time from an
// injected clock, thus a test moves the time with no real wait.

import Foundation
import Synchronization

/// The cooldowns of the search providers, by the name of the provider.
///
/// A reference type guarded by a `Mutex`, not an actor: each operation is a
/// short read and write of one dictionary, with no suspension point, and each
/// copy of the `Sendable` chain struct must share one store.
final class ProviderCooldowns: Sendable {
    /// The time of a cooldown when the response gives no `Retry-After` time
    /// that the store can read.
    static let defaultCooldown = Duration.seconds(60)

    /// The longest cooldown: 10 minutes. A longer `Retry-After` time gives
    /// this time.
    static let maximumCooldown = Duration.seconds(600)

    /// The time since the store was made, read from the clock of the store.
    private let elapsed: @Sendable () -> Duration

    /// The end of each cooldown, as the time since the store was made, by
    /// the name of the provider.
    private let ends = Mutex<[String: Duration]>([:])

    /// Makes a store with no cooldown.
    ///
    /// - Parameter clock: The clock that gives the time of each cooldown.
    init(clock: some Clock<Duration>) {
        let start = clock.now
        elapsed = { start.duration(to: clock.now) }
    }

    /// The time that is left in the cooldown of a provider.
    ///
    /// - Parameter name: The name of the provider.
    /// - Returns: The time that is left, or `nil` when the provider has no
    ///   cooldown or its cooldown ended.
    func remainingCooldown(of name: String) -> Duration? {
        let now = elapsed()
        return ends.withLock { ends in
            guard let end = ends[name] else { return nil }
            guard end > now else {
                ends[name] = nil
                return nil
            }
            return end - now
        }
    }

    /// Starts the cooldown of a provider that sent HTTP 429. A new cooldown
    /// replaces the cooldown that the provider had.
    ///
    /// - Parameters:
    ///   - name: The name of the provider.
    ///   - retryAfter: The `Retry-After` header of the response, or `nil`
    ///     when the response has none.
    func startCooldown(of name: String, retryAfter: String?) {
        let end = elapsed() + Self.cooldown(forRetryAfter: retryAfter, at: .now)
        ends.withLock { $0[name] = end }
    }

    /// The time of a cooldown for a `Retry-After` header.
    ///
    /// The header is a number of seconds (`120`) or an HTTP date in the
    /// IMF-fixdate form (`Wed, 21 Oct 2015 07:28:00 GMT`), RFC 9110,
    /// section 10.2.3. The obsolete date forms of RFC 9110 give the default.
    ///
    /// - Parameters:
    ///   - retryAfter: The header, or `nil` when the response has none.
    ///   - now: The time of the response, which an HTTP date is compared to.
    /// - Returns: The time of the header, at most ``maximumCooldown``. A date
    ///   in the past gives zero. No header, and a header that is not a number
    ///   and not an HTTP date, give ``defaultCooldown``.
    static func cooldown(forRetryAfter retryAfter: String?, at now: Date) -> Duration {
        guard let text = retryAfter?.trimmingCharacters(in: .whitespaces) else { return defaultCooldown }
        let delay = seconds(in: text) ?? dateDelay(in: text, after: now) ?? defaultCooldown
        return min(delay, maximumCooldown)
    }

    /// Reads a `Retry-After` value that is a number of seconds.
    ///
    /// - Parameter text: The value, with no whitespace at the start or the
    ///   end.
    /// - Returns: The time, or `nil` when the value is not a whole number of
    ///   zero or more.
    private static func seconds(in text: String) -> Duration? {
        guard !text.isEmpty, text.allSatisfy(\.isASCIIDigit), let seconds = Int64(text) else { return nil }
        return .seconds(seconds)
    }

    /// Reads a `Retry-After` value that is an HTTP date.
    ///
    /// - Parameters:
    ///   - text: The value, with no whitespace at the start or the end.
    ///   - now: The time that the date is compared to.
    /// - Returns: The time from `now` to the date, zero for a date in the
    ///   past, or `nil` when the value is not an HTTP date.
    private static func dateDelay(in text: String, after now: Date) -> Duration? {
        guard let date = try? Date(text, strategy: .http) else { return nil }
        return .seconds(max(date.timeIntervalSince(now), 0))
    }
}

private extension Character {
    /// `true` for the ASCII digits `0` to `9`.
    var isASCIIDigit: Bool {
        isASCII && isWholeNumber
    }
}
