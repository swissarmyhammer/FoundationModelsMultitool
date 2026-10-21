// `SessionsToolContext` — the shared context of the operations of the
// `sessions` tool.
//
// session.md section 8: `SessionsToolContext` holds `any SessionDirectory`.
// Each operation reads the directory through it, and reads the caller
// session from `ToolContext.current` at the start of its call.

import FoundationModelsExtras
import ULID

/// The shared context of the operations of ``SessionsTool``.
struct SessionsToolContext: Sendable {
    /// The session directory that each operation reads.
    let directory: any SessionDirectory

    /// The session of the current call, or `nil` for a call with no
    /// `ToolContext` (outside a Router session). A call with no caller can
    /// only read the directory (session.md section 8.2).
    var callerID: ULID? {
        ToolContext.current?.sessionID
    }
}
