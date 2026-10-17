// `endingShellRun` — the one teardown of a shell run that a test started on a
// task of its own.
//
// Test rule T1: fixtures close also when the test body throws. A test that
// starts `ShellRunner.run` on a task and stops it only at the end of its body
// leaves a live child behind when a step of the body throws. A `defer` that
// only cancels the task does not wait for the end of the run, thus the child
// can still be alive and unreaped after the test. This teardown runs on each
// path, and it returns only after the run ended.

import Foundation

@testable import FoundationModelsMultitool

/// Runs `body`, and then ends `run` on each path: when `body` returns, and
/// when `body` throws.
///
/// First the write end `gate` of a FIFO closes, when the test gives one. Thus
/// a process of the group that reads the FIFO gets the end of the file, also
/// when the test replaced the kill of the group. A second close of a handle
/// that the test closed before does nothing. Then the task of the run is
/// cancelled, and this call waits for its end (``EventRace/endWait(_:)``). A
/// cancel of `ShellRunner.run` stops its child, and the teardown of the run
/// kills the process group of the child. The run returns only after
/// `Subprocess.run` reaped the child. Thus no child of the test stays alive
/// and unreaped after this call. When the run ended before, the cancel does
/// nothing, and the wait returns at once.
///
/// - Parameters:
///   - run: The task of the run.
///   - gate: The write end of the FIFO that holds the command, or `nil` — the
///     default — for none.
///   - body: The work of the test while the run goes.
/// - Returns: What `body` returned.
/// - Throws: What `body` threw, after the run ended.
func endingShellRun<Result>(
    _ run: Task<ShellRunner.Outcome, any Error>, closing gate: FileHandle? = nil,
    after body: () async throws -> Result
) async throws -> Result {
    try await ensuring(
        {
            try? gate?.close()
            await EventRace.endWait(run)
        }, after: body)
}
