// `EnvironmentContext` — the inputs that the verbs of the environment
// capability read.
//
// Each input is a closure, and each verb calls the closure at each call. Thus
// each call reads the live value, not a copy that `init` took. This is the
// same rule as `WebConfiguration`, which reads its environment "at the time of
// each call". A test injects each input, thus a test never reads the real
// process, the real clock, or the real time zone.

import Foundation

/// The inputs that the verbs of `tools.environment` read: the environment
/// variables, the clock, and the time zone.
///
/// The default of each input reads the real process. A test gives its own
/// input for each value that it controls.
struct EnvironmentContext: Sendable {

    /// Gives the environment variables, by name. A verb calls it at each
    /// call.
    let variables: @Sendable () -> [String: String]

    /// Gives the date and the time now. A verb calls it at each call.
    let now: @Sendable () -> Date

    /// The time zone that a verb uses to show a date.
    let timeZone: TimeZone

    /// Makes a context. Each input that the caller does not give reads the
    /// real process.
    ///
    /// - Parameters:
    ///   - variables: Gives the environment variables. Defaults to the
    ///     environment of this process, read at each call.
    ///   - now: Gives the date and the time now. Defaults to the system
    ///     clock, read at each call.
    ///   - timeZone: The time zone that a verb uses. Defaults to the current
    ///     time zone of the system.
    init(
        variables: @escaping @Sendable () -> [String: String] = { ProcessInfo.processInfo.environment },
        now: @escaping @Sendable () -> Date = { Date() },
        timeZone: TimeZone = .current
    ) {
        self.variables = variables
        self.now = now
        self.timeZone = timeZone
    }
}
