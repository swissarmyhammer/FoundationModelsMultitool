import Foundation
import FoundationModels
import FoundationModelsRouter
import Testing

@testable import FoundationModelsMultitool

// MARK: - The run plane of a shell run
//
// A `tools.shell.execute` call reaches the run plane only through the shared
// elevation engine of Router: the engine parks the run, and the ambient
// `ToolContext` reports it. Thus a suite that examines a PARKED shell run takes
// two steps before it can assert anything — mount the verb on that engine, and
// wait for the run to reach the plane. Both steps stand here, thus each suite
// that takes them reads one copy and no copy can drift from another.

/// The two steps a test takes before it can read a parked shell run: the mount,
/// and the wait for the park.
enum ShellRunPlane {

    /// How many runs ``parkedRun(in:)`` waits for.
    private static let oneRun = 1

    /// Mounts `verb` on the shared elevation engine over one mailbox, the way
    /// `RunBinding` mounts every inner `tools.*` call.
    ///
    /// The configuration is `RunBinding.innerCallMount` on purpose: the verb's
    /// own `detachmentMount` must win over it, because that declaration is the
    /// only way a `wait: false` call can ever park.
    ///
    /// - Parameters:
    ///   - verb: The verb to mount.
    ///   - context: The session context the engine inherits.
    /// - Returns: The mounted engine.
    /// - Throws: When the decorator did not preserve the verb's own types.
    static func mounted(
        _ verb: Execute, inheriting context: ToolContext
    ) throws -> any Tool<ExecuteArguments, String> {
        try #require(
            ToolDetachment.wrapping(
                tool: verb,
                inheriting: context,
                sink: AmbientUpstreamSink(context: context),
                configuration: RunBinding.innerCallMount
            ) as? any Tool<ExecuteArguments, String>
        )
    }

    /// Waits until the run plane of `context` holds `count` runs, and answers
    /// them in park order.
    ///
    /// A ``TestPoll`` rather than one read: a `wait: false` call answers as the
    /// engine parks its run, and the answer and the park are not one hop.
    ///
    /// - Parameters:
    ///   - context: The session context whose run plane to read.
    ///   - count: How many runs must stand on the plane.
    /// - Returns: The parked runs, in park order.
    /// - Throws: When fewer than `count` runs reach the plane before the
    ///   deadline.
    static func parkedRuns(in context: ToolContext, count: Int) async throws -> [ParkedRun] {
        var going: [ParkedRun] = []
        let arrived = await TestPoll.holds {
            going = await context.parkedRuns()
            return going.count >= count
        }
        guard arrived else {
            Issue.record(
                "Only \(going.count) of \(count) runs reached the run plane before the deadline.")
            throw ParkedRunAbsent()
        }
        return going
    }

    /// Waits until the run plane of `context` holds a run, and answers it.
    ///
    /// - Parameter context: The session context whose run plane to read.
    /// - Returns: The parked run.
    /// - Throws: When no run reaches the run plane before the deadline.
    static func parkedRun(in context: ToolContext) async throws -> ParkedRun {
        let going = try await parkedRuns(in: context, count: oneRun)
        return try #require(going.first)
    }

    /// The failure ``parkedRuns(in:count:)`` throws when the run plane stays
    /// short of the count the caller asked for.
    private struct ParkedRunAbsent: Error {}
}
