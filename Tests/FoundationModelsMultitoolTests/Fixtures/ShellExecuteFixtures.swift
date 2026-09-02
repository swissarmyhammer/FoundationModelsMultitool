import Foundation
import FoundationModelsExtras
import Testing

@testable import FoundationModelsMultitool

// MARK: - The execute verb of a configured capability, and its answer
//
// Two suites drive `tools.shell.execute` through a whole `ShellCapability`
// rather than through a bare `Execute`: the suite of the verb itself, and the
// seatbelt suite that proves a plain command runs where the capability says it
// runs. Both need the same two steps — take the configured verb out of the
// capability with a registry of its own, and read the JSON report back — so
// both steps stand here, and neither suite holds a copy of them.

/// The `execute` verb of a configured `ShellCapability`, and the report one
/// call of it answers with.
enum ShellExecuteVerb {

    /// The `execute` verb of `capability`, with the registry of its runner
    /// replaced by a private one.
    ///
    /// The capability takes `ProcessRegistry.global`, and an ordinary test must
    /// not touch the process-wide instance — see the doc comment of that
    /// property. Nothing else of the configured runner is touched, thus the
    /// store, the live view, the confinement and the default working directory
    /// stay the ones the capability built.
    ///
    /// - Parameter capability: The capability a test configured.
    /// - Returns: The verb of that capability.
    /// - Throws: When the capability holds no `execute` verb.
    static func configured(in capability: ShellCapability) throws -> Execute {
        let verb = try #require(capability.tools.compactMap { $0 as? Execute }.first)
        var runner = verb.runner
        runner.registry = ProcessRegistry()
        return Execute(runner: runner)
    }

    /// The report one rendered answer carries, read back as a JSON object.
    ///
    /// The verb answers `String`, because only a `String`-output tool reaches
    /// `BackgroundToolRunner` and thus the run plane. So a test reads the answer
    /// the way the model does: as the JSON object `ResultRenderer` serialized.
    ///
    /// - Parameter output: The rendered answer of one call.
    /// - Returns: The fields of the report.
    /// - Throws: When the answer is not a JSON object.
    static func report(of output: String) throws -> [String: Any] {
        let data = try #require(output.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
