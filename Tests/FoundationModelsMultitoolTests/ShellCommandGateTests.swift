import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Tests of ``ShellCommandGate``: each release ends on the first of its
/// events, and never on a time.
///
/// The tests of ``ShellCommandGate/release(whileAlive:)`` start a real child
/// with `Process`. No test waits on a clock: the release ends when the child
/// opens the FIFO, or on the kqueue exit event of the child. The tests of
/// ``ShellCommandGate/release(commandIn:orEndOf:)`` drive a `ShellState` and a
/// ``CallEnd`` in a fixed order.
@Suite("ShellCommandGateTests")
struct ShellCommandGateTests {

    /// The shell each test child runs under.
    private static let shellPath = "/bin/sh"

    /// The program that reads its standard input until the end of the file.
    private static let catPath = "/bin/cat"

    /// A child that waits on the gate gets the line, and the release gives
    /// ``ShellCommandGate/Release/reached``.
    @Test("a release reaches a command that waits on the gate")
    func releaseReachesACommandThatWaitsOnTheGate() async throws {
        let gate = try ShellCommandGate()
        let child = Process()
        child.executableURL = URL(fileURLWithPath: Self.shellPath)
        child.arguments = ["-c", gate.waitCommand]
        try child.run()

        // The result of the release is the event: `.reached` comes only after
        // the child opened the FIFO and the write of the line succeeded. The
        // child then reads the line and exits, and `Process` reaps it.
        let release = try await gate.release(whileAlive: child.processIdentifier)

        #expect(release == .reached)
    }

    /// One gate releases one wait. A second release of one gate throws, and it
    /// writes no line.
    ///
    /// The cause: a release closes its write end only after its write. In
    /// that interval a command that waits two times on one gate can read the
    /// line and open the same FIFO for its second wait. That open ends at once
    /// on the write end of the first release, and the close of that write end
    /// gives the second `read` the end of the file. The second wait then ends
    /// with no release.
    ///
    /// The order is fixed. The first release reaches a first child. Only
    /// after that does a second child wait on the same gate, and the second
    /// release must throw. A release that does not throw reaches the second
    /// child and gives ``ShellCommandGate/Release/reached``: a failed check,
    /// and no wait for all time. The test then stops the second child, and it
    /// waits for the kqueue exit event of that child.
    @Test("a second release of one gate throws and writes no line")
    func aSecondReleaseOfOneGateThrows() async throws {
        let gate = try ShellCommandGate()
        let first = Process()
        first.executableURL = URL(fileURLWithPath: Self.shellPath)
        first.arguments = ["-c", gate.waitCommand]
        try first.run()
        #expect(try await gate.release(whileAlive: first.processIdentifier) == .reached)

        let second = Process()
        second.executableURL = URL(fileURLWithPath: Self.shellPath)
        second.arguments = ["-c", gate.waitCommand]
        try second.run()
        let secondPid = second.processIdentifier
        await #expect(throws: ShellCommandGate.Failure.self) {
            _ = try await gate.release(whileAlive: secondPid)
        }
        second.terminate()
        await ProcessExitWait.waitUntilGone(secondPid)
    }

    /// A child that exits and never opens the FIFO cannot make the release
    /// wait for all time: the release ends on the exit event of the child and
    /// gives ``ShellCommandGate/Release/commandExited``.
    ///
    /// The child is `cat` on a pipe. The test closes the write end of the
    /// pipe, thus `cat` reads the end of the file and exits. The release can
    /// start before or after that exit; both orders give the same result.
    @Test("a release ends when the command exits before it opens the gate")
    func releaseEndsWhenTheCommandExitsBeforeItOpensTheGate() async throws {
        let gate = try ShellCommandGate()
        let input = Pipe()
        let child = Process()
        child.executableURL = URL(fileURLWithPath: Self.catPath)
        child.standardInput = input
        try child.run()
        let pid = child.processIdentifier

        let release = Task { try await gate.release(whileAlive: pid) }
        try input.fileHandleForWriting.close()

        #expect(try await release.value == .commandExited)
    }

    /// What the call of ``releaseEndsWhenTheCallEndsBeforeTheCommandStarts()``
    /// returned. It never calls `execute`.
    private static let returnedWithNoExecute = "returned with no execute"

    /// The completion token of the command that starts after the call ended.
    private static let laterCommandID = "later-command"

    /// A call that ends and never starts the command cannot make the release
    /// wait for all time: the release ends on the end of the call, and gives
    /// ``ShellCommandGate/CommandRelease/callEndedFirst(returned:)``.
    ///
    /// The order is fixed. The call ends first, and only after that does a
    /// different command that holds the path of the FIFO start, and end with
    /// no process. ``CallEnd/record(_:)`` ends the race of the release in the
    /// record itself, or the release sees the end at once when it starts
    /// later. Thus the release gives the end of the call, before or after
    /// the later command. A release that does not see the end of the call
    /// waits for the later command, and gives
    /// ``ShellCommandGate/CommandRelease/released(_:commandID:)`` for it: a
    /// failed check, and no wait for all time.
    @Test("a release ends when the call that must start the command ends first")
    func releaseEndsWhenTheCallEndsBeforeTheCommandStarts() async throws {
        let gate = try ShellCommandGate()
        let state = try ShellState(
            preferredDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("multitool-gate-call-\(UUID().uuidString)"))
        let call = CallEnd()

        async let released = gate.release(commandIn: state, orEndOf: call)
        call.record(Self.returnedWithNoExecute)
        await state.startCommand(gate.waitCommand, commandID: Self.laterCommandID)
        await state.completeCommand(commandID: Self.laterCommandID)

        #expect(try await released == .callEndedFirst(returned: Self.returnedWithNoExecute))
    }

    /// When the command starts before the call ends, the release goes on to
    /// the process of that command. A record that is final with no process
    /// gives ``ShellCommandGate/Release/commandExited``, and the end of the
    /// call that comes later changes nothing.
    @Test("a release that sees the command start ignores a later end of the call")
    func releaseThatSeesTheCommandIgnoresALaterEndOfTheCall() async throws {
        let gate = try ShellCommandGate()
        let state = try ShellState(
            preferredDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("multitool-gate-call-\(UUID().uuidString)"))
        let call = CallEnd()
        await state.startCommand(gate.waitCommand, commandID: Self.laterCommandID)
        await state.completeCommand(commandID: Self.laterCommandID)

        let released = try await gate.release(commandIn: state, orEndOf: call)
        call.record(Self.returnedWithNoExecute)

        #expect(released == .released(.commandExited, commandID: Self.laterCommandID))
    }
}
