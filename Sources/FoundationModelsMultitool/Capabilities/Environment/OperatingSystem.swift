// `OperatingSystem` — the `tools.environment.os` verb.
//
// The verb gives the facts of the operating system and of the host: the
// platform, the version, the processor, the host name, the user, and the
// locale. It takes no argument.
//
// The verb is a plain `FoundationModels.Tool` that holds the context of the
// environment capability, in the pattern of `Variables.swift`. The capability
// supplies the noun, thus this verb's `name` is the bare `os` and the surface
// path renders as `tools.environment.os`.
//
// The verb reads the facts through `EnvironmentContext.operatingSystem` at
// each call. The default of that input is `OperatingSystemResult.readFromHost()`,
// which reads the real host. A test injects fixed facts.
//
// **The host name comes from `gethostname()`**, not from
// `ProcessInfo.hostName`. On macOS, `ProcessInfo.hostName` can do a
// name-service lookup that blocks for some seconds, and a verb that the model
// calls must not block.

import Foundation
import FoundationModels

/// The arguments of `tools.environment.os`: none. The verb reads the whole
/// host.
@Generable
struct OperatingSystemArguments {}

/// The result of `tools.environment.os`: the facts of the operating system
/// and of the host.
@Generable(description: "The facts of the operating system and of the host.")
struct OperatingSystemResult {

    /// The name of the platform, for example `macOS`.
    @Guide(description: "The name of the platform, for example macOS.")
    var name: String

    /// The version of the operating system, as `major.minor.patch`.
    @Guide(description: "The version of the operating system, as major.minor.patch, for example 27.0.1.")
    var version: String

    /// The text of the version and of the build, as the system gives it.
    @Guide(description: "The text of the version and of the build, as the system gives it.")
    var build: String

    /// The processor architecture of the build, for example `arm64`.
    @Guide(description: "The processor architecture, for example arm64 or x86_64.")
    var architecture: String

    /// The name of the host.
    @Guide(description: "The name of the host. It is empty when the system cannot give it.")
    var hostName: String

    /// The name of the user that runs the process.
    @Guide(description: "The login name of the user that runs the process.")
    var userName: String

    /// The home folder of that user.
    @Guide(description: "The absolute path of the home folder of the user.")
    var homeDirectory: String

    /// The number of the processors that the system can use now.
    @Guide(description: "The number of the processors that the system can use now.")
    var processorCount: Int

    /// The size of the physical memory, in bytes.
    @Guide(description: "The size of the physical memory, in bytes.")
    var physicalMemoryBytes: Int

    /// The identifier of the current locale, for example `en_US`.
    @Guide(description: "The identifier of the current locale, for example en_US.")
    var locale: String
}

extension OperatingSystemResult {

    // MARK: Reading the host

    /// Reads the facts of the real host now.
    ///
    /// Each call reads the system again. Nothing here blocks on the network.
    ///
    /// - Returns: The facts of the host that runs the process.
    static func readFromHost() -> OperatingSystemResult {
        let process = ProcessInfo.processInfo
        return OperatingSystemResult(
            name: platformName,
            version: versionText(of: process.operatingSystemVersion),
            build: process.operatingSystemVersionString,
            architecture: architectureName,
            hostName: readHostName(),
            userName: NSUserName(),
            homeDirectory: NSHomeDirectory(),
            processorCount: process.activeProcessorCount,
            physicalMemoryBytes: Int(clamping: process.physicalMemory),
            locale: Locale.current.identifier)
    }

    // MARK: Steps

    /// The name of the platform that the code was built for.
    private static var platformName: String {
        #if os(macOS)
            "macOS"
        #elseif os(iOS)
            "iOS"
        #elseif os(visionOS)
            "visionOS"
        #elseif os(Linux)
            "Linux"
        #else
            "unknown"
        #endif
    }

    /// The processor architecture that the code was built for.
    private static var architectureName: String {
        #if arch(arm64)
            "arm64"
        #elseif arch(x86_64)
            "x86_64"
        #else
            "unknown"
        #endif
    }

    /// The text of a version, as `major.minor.patch`.
    ///
    /// - Parameter version: The version of the operating system.
    /// - Returns: The three numbers, with a dot between each two.
    private static func versionText(of version: OperatingSystemVersion) -> String {
        "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    /// Reads the name of the host with `gethostname()`.
    ///
    /// The buffer holds the longest name that the system permits, and one
    /// more byte for the terminating zero. Thus a failure here is unexpected.
    /// The failure stops a debug build, and an `error` log record tells of it
    /// in a release build. The result then gives an empty host name, and the
    /// `hostName` Guide tells the model that it can be empty.
    ///
    /// - Returns: The name of the host, or an empty text when the system
    ///   cannot give it.
    private static func readHostName() -> String {
        var characters = [CChar](repeating: 0, count: Int(MAXHOSTNAMELEN) + 1)
        guard gethostname(&characters, characters.count) == 0 else {
            let code = errno
            assertionFailure("gethostname failed with errno \(code)")
            MultitoolTelemetry.logger.log(
                .hostNameReadFailed, level: .error,
                metadata: [MultitoolTelemetry.LogMetadataKey.errorCode.rawValue: "\(code)"])
            return ""
        }
        let utf8 = characters.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: utf8, as: UTF8.self)
    }
}

extension OperatingSystem {

    // MARK: Execution

    /// Gives the facts of the operating system and of the host.
    ///
    /// Reads the facts through the context at each call. Nothing here
    /// throws.
    ///
    /// - Parameter arguments: No argument.
    /// - Returns: The facts.
    func call(arguments: OperatingSystemArguments) async throws -> OperatingSystemResult {
        context.operatingSystem()
    }
}

/// Gives the facts of the operating system and of the host.
///
/// ```swift
/// // In a snippet the model writes:
/// //   const { name, version, architecture } = await tools.environment.os({});
/// ```
///
/// The contract: with no argument, one result that holds each fact of
/// ``OperatingSystemResult``, read at the time of the call.
struct OperatingSystem: Tool {

    /// The verb this tool renders as, which the environment noun stands in
    /// front of: `tools.environment.os`.
    let name = "os"

    /// The usage instructions, as the model reads them.
    let description = """
        os gives the facts of the operating system and of the host. It takes no argument. name is \
        the platform, for example macOS. version is major.minor.patch, for example 27.0.1. build is \
        the text of the version and of the build, as the system gives it. architecture is the \
        processor architecture, for example arm64 or x86_64. hostName is the name of the host. \
        userName is the login name of the user, and homeDirectory is the absolute path of the home \
        folder of that user. processorCount is the number of the processors that the system can \
        use now. physicalMemoryBytes is the size of the physical memory, in bytes. locale is the \
        identifier of the current locale, for example en_US.
        """

    /// The session context this verb reads against, which the environment
    /// capability owns.
    ///
    /// The compiler-synthesized memberwise initializer takes this one
    /// property, thus the capability makes the verb as
    /// `OperatingSystem(context:)`.
    let context: EnvironmentContext
}
