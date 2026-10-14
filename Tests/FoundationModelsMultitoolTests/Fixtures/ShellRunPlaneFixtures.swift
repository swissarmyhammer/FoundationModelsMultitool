import Foundation
import FoundationModels
import FoundationModelsRouter
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

// MARK: - The run plane of a shell run
//
// A `tools.shell.execute` call reaches the run plane only through the shared
// engine of Router: `BackgroundToolRunner` tracks the run in the session mailbox, and
// the ambient `ToolContext` reports it. Thus a suite that examines a background
// shell run takes two steps before it can assert anything — mount the verb on
// that engine, and read the run on the plane. Both steps stand here,
// thus each suite that takes them reads one copy and no copy can drift from
// another.

/// The two steps a test takes before it can read a background shell run: the
/// mount, and the read of the run on the plane.
enum ShellRunPlane {

    /// How many runs ``backgroundRun(in:)`` reads.
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
    ///   - sink: The upstream sink each run's events reach, or `nil` to let the
    ///     mount supply its own. A caller-supplied sink observes each run's OWN
    ///     `completionToken`.
    /// - Returns: The mounted engine.
    static func mounted(
        _ verb: Execute, inheriting context: ToolContext,
        postingTo sink: (any OperationEventSink)? = nil
    ) -> any Tool<ExecuteArguments, String> {
        guard let sink else { return context.mount(verb, as: RunBinding.innerCallMount) }
        return context.mount(verb, as: RunBinding.innerCallMount, postingTo: sink)
    }

    /// Reads the `count` runs on the run plane of `context`, in the order
    /// they were tracked.
    ///
    /// One read is enough, and it is not a race. The engine of a mounted call
    /// (`BackgroundToolRunner.start`) awaits `RunPlane.start`, and that call
    /// adds the run to the plane before it returns. The mounted call answers
    /// only after that. Thus each run of a mounted call that returned stands
    /// on the plane, until it settles or a test cancels it. A caller calls
    /// this only after its mounted calls returned, and only for runs that
    /// cannot end by themselves.
    ///
    /// - Parameters:
    ///   - context: The session context whose run plane to read.
    ///   - count: How many runs must stand on the plane.
    /// - Returns: The background runs, in the order they were tracked.
    /// - Throws: When fewer than `count` runs stand on the plane, after the
    ///   failure is recorded.
    static func backgroundRuns(in context: ToolContext, count: Int) async throws -> [BackgroundRun] {
        let going = await context.backgroundRuns()
        guard going.count >= count else {
            Issue.record("Only \(going.count) of \(count) runs stand on the run plane.")
            throw BackgroundRunAbsent()
        }
        return going
    }

    /// Reads the one run on the run plane of `context`, and answers it.
    ///
    /// - Parameter context: The session context whose run plane to read.
    /// - Returns: The background run.
    /// - Throws: When no run stands on the run plane.
    static func backgroundRun(in context: ToolContext) async throws -> BackgroundRun {
        let going = try await backgroundRuns(in: context, count: oneRun)
        return try #require(going.first)
    }

    /// The failure ``backgroundRuns(in:count:)`` throws when the run plane
    /// stays short of the count the caller asked for.
    private struct BackgroundRunAbsent: Error {}
}
