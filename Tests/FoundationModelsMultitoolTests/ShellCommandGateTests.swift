import Foundation
import Testing

/// Tests of ``ShellCommandGate/release(whileAlive:)``: the release ends on the
/// first of two events, and never on a time.
///
/// Each test starts a real child with `Process`. No test waits on a clock: the
/// release ends when the child opens the FIFO, or on the kqueue exit event of
/// the child.
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
}
