import Foundation
import Testing

@testable import FoundationModelsMultitool

// MARK: - The injected environment of a session
//
// Two suites mount the environment capability through a whole `MultiTool`:
// the goal snippet suite and the search suite. Each one must not read the
// real process, the real host, the real clock, or the real time zone. Thus
// both suites read the one injected context here, and neither suite holds a
// copy of it.

/// The fixed inputs of the environment capability, and the context that
/// gives them.
enum InjectedEnvironment {

    /// The prefix of the variables that the application owns.
    static let applicationPrefix = "APP_"

    /// The name of the first application variable.
    static let modeName = applicationPrefix + "MODE"

    /// The name of the second application variable.
    static let titleName = applicationPrefix + "TITLE"

    /// The value of ``modeName``.
    static let modeValue = "test"

    /// The value of ``titleName``.
    static let titleValue = "Multitool"

    /// The home folder of the injected user.
    static let homeDirectory = "/Users/tester"

    /// The environment variables, by name. `HOME` does not start with
    /// ``applicationPrefix``, thus a prefix search must not give it.
    static let variables = [
        modeName: modeValue,
        titleName: titleValue,
        "HOME": homeDirectory,
    ]

    /// The number of processors of the injected host.
    static let processorCount = 6

    /// The bytes of physical memory of the injected host.
    static let physicalMemoryBytes = 1_234_567_890

    /// The facts of the operating system. Each value is different from the
    /// real value of a host, thus a test sees if a verb reads the host
    /// instead of the context.
    static let operatingSystem = OperatingSystemResult(
        name: "TestOS",
        version: "9.8.7",
        build: "Version 9.8.7 (Build 1A2b3)",
        architecture: "test64",
        hostName: "test-host.example",
        userName: "tester",
        homeDirectory: homeDirectory,
        processorCount: processorCount,
        physicalMemoryBytes: physicalMemoryBytes,
        locale: "de_CH")

    /// The whole seconds since 1970 of ``instant``: 2026-10-08T21:03:27Z, a
    /// Thursday in UTC.
    static let epochSeconds = 1_791_493_407

    /// The instant that the clock gives at each call.
    static let instant = Date(timeIntervalSince1970: TimeInterval(epochSeconds))

    /// The time zone of the session. At ``instant`` it is on 2026-10-09, a
    /// Friday, thus a verb that ignores a `timeZone` argument gives a
    /// different date.
    static let sessionTimeZone = "Asia/Tokyo"

    /// A context that gives each fixed input above.
    ///
    /// - Returns: The context.
    /// - Throws: When ``sessionTimeZone`` names no time zone.
    static func context() throws -> EnvironmentContext {
        let zone = try #require(TimeZone(identifier: sessionTimeZone))
        return EnvironmentContext(
            variables: { variables },
            operatingSystem: { operatingSystem },
            now: { instant },
            timeZone: zone)
    }
}
