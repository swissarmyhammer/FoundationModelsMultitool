// `SessionDirectoryErrorCorrectiveTests` — the corrective text and the code
// that the `sessions` tool and graph give for each error of the session
// directory that the fork of a session brought (^xpaa2h9).

import Foundation
import FoundationModelsExtras
import Testing
import ULID

@testable import FoundationModelsMultitool

/// The corrective and the code of the archived-session and fork errors of the
/// session directory.
@Suite("SessionDirectoryErrorCorrectiveTests")
struct SessionDirectoryErrorCorrectiveTests {

    /// A fixed session id.
    private static let sessionID = ULID()

    /// An archived session names the session and says that it is archived.
    @Test func anArchivedSessionNamesTheSession() {
        let text = SessionsToolText.corrective(for: .archivedSession(Self.sessionID))

        #expect(text.contains(Self.sessionID.ulidString), "text was: \(text)")
        #expect(text.contains("archived"), "text was: \(text)")
    }

    /// A cut out of range says that the cut is not in the history.
    @Test func aForkCutOutOfRangeSaysTheCutIsNotInTheHistory() {
        let text = SessionsToolText.corrective(for: .forkCutOutOfRange(.historyPosition(99)))

        #expect(text.contains("history"), "text was: \(text)")
    }

    /// A directory that cannot fork says so.
    @Test func aForkUnsupportedSaysTheServerCannotFork() {
        let text = SessionsToolText.corrective(for: .forkUnsupported)

        #expect(text.contains("cannot fork"), "text was: \(text)")
    }

    /// Each new error has the code of its refusal.
    @Test func eachForkErrorHasItsCode() {
        #expect(SessionsGraphResolver.refusalKind(of: .archivedSession(Self.sessionID))?.rawValue == "ARCHIVED_SESSION")
        #expect(SessionsGraphResolver.refusalKind(of: .forkCutOutOfRange(.lastCompletedTurn))?.rawValue == "FORK_CUT_OUT_OF_RANGE")
        #expect(SessionsGraphResolver.refusalKind(of: .forkUnsupported)?.rawValue == "FORK_UNSUPPORTED")
    }
}
