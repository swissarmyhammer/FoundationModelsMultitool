// `JSCInterpreter.makeWithHeldWatchdog` — a plain `JSCInterpreter`.
//
// The sandbox has no clock now, thus only the snippet, an error or a
// cancellation can end a run. This helper stays only so that its callers
// compile. Task `^tt2rg2x` removes it.

import Foundation

@testable import FoundationModelsMultitool

extension JSCInterpreter {
    /// Makes a plain interpreter.
    ///
    /// - Returns: An interpreter that only a cancellation can stop.
    static func makeWithHeldWatchdog() -> JSCInterpreter {
        JSCInterpreter()
    }
}
