// `CorrectiveResult` — the return-don't-throw resolution of a corrective
// failure.
//
// A behavioral port of `../FoundationModelsFileTool/Sources/FileTool/
// CorrectiveResult.swift`. The sibling also conforms its `ParseFailure` to
// `CorrectiveFailure`; that type belongs to the patch parser, which is not
// in this package yet, thus the patch-verb port brings that conformance
// with it. `PathCorrective.UnreadableFile` conforms in its own file.
//
// eventplan.md § "Consolidation of the siblings": a corrective result stays
// in band, never thrown.

import Foundation

/// A recoverable failure carrying the corrective message handed back to the model.
///
/// The engines and verbs follow the upstream *return-don't-throw*
/// convention: a recoverable condition is reported as a `Result` failure
/// whose payload reduces to one corrective string, which the caller then
/// hands back as its own outcome's `corrective` case. Conforming a failure
/// type here is what lets ``Swift/Result/resolve(corrective:then:)`` express
/// that hand-off in one place instead of one time per verb.
///
/// The conforming types are `Error`s only so they can be a `Result` failure;
/// none of them is ever thrown.
protocol CorrectiveFailure: Error {
    /// The corrective message the model reads and acts on.
    var correctiveMessage: String { get }
}

extension PathViolation: CorrectiveFailure {
    /// The corrective message that says why the path was rejected.
    var correctiveMessage: String { message }
}

extension Result where Failure: CorrectiveFailure {
    /// Continues with `body` on success, or short-circuits to a corrective outcome.
    ///
    /// Every verb that resolves an input through a `Result` — a validated
    /// path, a prepared search, a parsed patch envelope — faces the same
    /// two-branch shape ahead of its real work: bind the resolved value and
    /// carry on, or hand the failure's message back as the outcome's
    /// `corrective` case. This is that shape, written one time.
    ///
    /// - Parameters:
    ///   - corrective: builds the outcome carrying a corrective message,
    ///     normally the outcome enum's own `corrective` case.
    ///   - body: the work to do with the resolved value.
    /// - Returns: `body`'s outcome on success, or the corrective outcome
    ///   built from the failure's ``CorrectiveFailure/correctiveMessage``.
    func resolve<Output>(
        corrective: (String) -> Output,
        then body: (Success) -> Output
    ) -> Output {
        switch self {
        case .success(let value):
            return body(value)
        case .failure(let failure):
            return corrective(failure.correctiveMessage)
        }
    }

    /// The asynchronous twin of ``resolve(corrective:then:)``, for a verb
    /// whose work after the resolution awaits.
    ///
    /// A Swift function is not polymorphic over `async`, thus the twin
    /// cannot share the name: overloading on nothing but the closure's
    /// effect would leave every trailing-closure call site ambiguous.
    ///
    /// - Parameters:
    ///   - corrective: builds the outcome carrying a corrective message,
    ///     normally the outcome enum's own `corrective` case.
    ///   - body: the asynchronous work to do with the resolved value.
    /// - Returns: `body`'s outcome on success, or the corrective outcome
    ///   built from the failure's ``CorrectiveFailure/correctiveMessage``.
    func resolveAsync<Output>(
        corrective: (String) -> Output,
        then body: (Success) async -> Output
    ) async -> Output {
        switch self {
        case .success(let value):
            return await body(value)
        case .failure(let failure):
            return corrective(failure.correctiveMessage)
        }
    }
}
