// `JSCInterpreter.makeWithHeldWatchdog` — an interpreter whose watchdog no
// machine load can fire.
//
// The watchdog of a stock `JSCInterpreter` ends a run at a real deadline. A
// test that is not about the watchdog then races that deadline: a busy machine
// can end a snippet that is correct. The watchdog of this interpreter sleeps
// on a `GatedClock` that no test opens, thus only the snippet, an error or a
// cancellation can end the run (card `^3np5yzj`: no test checks the speed of
// the machine). A test of the watchdog makes its own `GatedClock` and opens it.

import Foundation

@testable import FoundationModelsMultitool

extension JSCInterpreter {
    /// The limit, in seconds, of an interpreter from ``makeWithHeldWatchdog(timeLimit:)``
    /// when the test names none. The clock never reaches it. The value is
    /// only the limit that the interpreter states.
    static let heldWatchdogTimeLimit: TimeInterval = 5

    /// Makes an interpreter whose watchdog sleeps on a gated clock that
    /// nothing opens.
    ///
    /// `withTimeLimit(_:)` keeps the clock, thus the watchdog stays held
    /// under a `MultiTool` too.
    ///
    /// - Parameter timeLimit: The limit that the watchdog arms. The clock
    ///   never reaches it.
    /// - Returns: An interpreter that the watchdog cannot stop.
    static func makeWithHeldWatchdog(timeLimit: TimeInterval = heldWatchdogTimeLimit) -> JSCInterpreter {
        JSCInterpreter(timeLimit: timeLimit, watchdogClock: GatedClock())
    }
}
