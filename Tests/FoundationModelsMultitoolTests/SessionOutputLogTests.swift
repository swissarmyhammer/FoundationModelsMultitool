import FoundationModelsRouter
import ScenarioGrading
import Testing

/// The waits of ``SessionOutputLog`` tell the caller when their event did not
/// come.
///
/// A wait of the log ends also when the event stream of the session
/// finishes. The caller must then know that the event did not come, and not
/// read a partial log as if the event came.
@Suite("a wait of SessionOutputLog tells when its event did not come", .ownsTemporaryDirectories)
struct SessionOutputLogTests {
    /// The session closes before the test waits. A close finishes each event
    /// stream of the session, thus the log gets the end of its stream, and
    /// no terminal event of the mail can come after it.
    @Test("waitForTerminal(of:) gives false when the event stream finished before the terminal event came")
    func terminalWaitGivesFalseWhenTheStreamFinished() async throws {
        let session = try await makeMailProbeSession(mounting: [], prompts: MailProbePrompts()) { _, _ in
            "answered"
        }
        let log = await SessionOutputLog.reading(session)
        await session.close()

        let came = await log.waitForTerminal(of: MailID())

        #expect(!came)
    }
}
