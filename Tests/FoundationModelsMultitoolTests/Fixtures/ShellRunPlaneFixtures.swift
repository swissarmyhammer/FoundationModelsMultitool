import Foundation
import FoundationModels
import FoundationModelsRouter
import Testing

@testable import FoundationModelsMultitool

// MARK: - The run plane of a shell run
//
// A `tools.shell.execute` call reaches the run plane only through the shared
// engine of Router: `BackgroundToolRunner` tracks the run in the session mailbox, and
// the ambient `ToolContext` reports it. Thus a suite that examines a background
// shell run takes two steps before it can assert anything — mount the verb on
// that engine, and wait for the run to reach the plane. Both steps stand here,
// thus each suite that takes them reads one copy and no copy can drift from
// another.

/// The two steps a test takes before it can read a background shell run: the
/// mount, and the wait for the run to reach the plane.
enum ShellRunPlane {

    /// How many runs ``backgroundRun(in:)`` waits for.
    private static let oneRun = 1

    /// Mounts `verb` on the shared engine over one mailbox, the way
    /// `RunBinding` mounts every inner `tools.*` call.
    ///
    /// The configuration is `RunBinding.innerCallMount` on purpose: the verb's
    /// own `mount` must win over it, because that declaration is the
    /// only way a call of this verb reaches the background.
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
            ToolMounting.makeWrapped(
                tool: verb,
                inheriting: context,
                sink: AmbientUpstreamSink(context: context),
                configuration: RunBinding.innerCallMount
            ) as? any Tool<ExecuteArguments, String>
        )
    }

    /// Waits until the run plane of `context` holds `count` runs, and answers
    /// them in the order they were tracked.
    ///
    /// A ``TestPoll`` rather than one read: a mounted call answers as the
    /// engine tracks its run, and the answer and the tracking are not one hop.
    ///
    /// - Parameters:
    ///   - context: The session context whose run plane to read.
    ///   - count: How many runs must stand on the plane.
    /// - Returns: The background runs, in the order they were tracked.
    /// - Throws: When fewer than `count` runs reach the plane before the
    ///   deadline.
    static func backgroundRuns(in context: ToolContext, count: Int) async throws -> [BackgroundRun] {
        var going: [BackgroundRun] = []
        let arrived = await TestPoll.holds {
            going = await context.backgroundRuns()
            return going.count >= count
        }
        guard arrived else {
            Issue.record(
                "Only \(going.count) of \(count) runs reached the run plane before the deadline.")
            throw BackgroundRunAbsent()
        }
        return going
    }

    /// Waits until the run plane of `context` holds a run, and answers it.
    ///
    /// - Parameter context: The session context whose run plane to read.
    /// - Returns: The background run.
    /// - Throws: When no run reaches the run plane before the deadline.
    static func backgroundRun(in context: ToolContext) async throws -> BackgroundRun {
        let going = try await backgroundRuns(in: context, count: oneRun)
        return try #require(going.first)
    }

    /// The failure ``backgroundRuns(in:count:)`` throws when the run plane
    /// stays short of the count the caller asked for.
    private struct BackgroundRunAbsent: Error {}
}
