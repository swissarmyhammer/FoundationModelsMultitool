import Foundation
import os

/// What every `tools.*` call of one `runCode` invocation returned, and the one
/// judgement that record supports: whether the snippet's own return value
/// carries any of it.
///
/// **The gap this closes.** `runCode` grades the shape of a snippet's result
/// and nothing else. A snippet that fires `tools.*`, throws the return away and
/// answers with a sentence about it succeeds exactly as a snippet that reports
/// the value does — both hand back a string, and only that string reaches the
/// model. Two models, given the same prompt and the same surface, both took
/// that first step, and neither had anything in band to contradict it: one
/// wrote the same narrating snippet four more times, the other went looking
/// through the ambient-globals documentation and the run plane (task
/// `wnfzwxg`). The loop shape is a model behaviour; the silence is this
/// package's, and this is where it ends.
///
/// **Only this package can say it.** Nothing upstream sees both halves. Router
/// sees a tool call that returned a string; the interpreter sees a snippet that
/// ran to completion. The `tools.*` bindings and the snippet's return value meet
/// in one place — a `runCode` invocation — so the comparison is made here and
/// reported through the same rendered text every other `runCode` answer uses.
///
/// **What it never does is guess.** The notice states one checkable fact: no
/// text any recorded call returned appears anywhere in the value the snippet
/// handed back. Where the comparison cannot be made — nothing recorded, or more
/// values than ``maximumRecordedValues`` on either side — the ledger says
/// nothing rather than reporting on a comparison it did not make, because a
/// notice on a snippet that did report would be a false claim and would send a
/// model that answered correctly around for another turn.
///
/// A reference type guarded by `OSAllocatedUnfairLock`, rather than an `actor`,
/// for `MultiTool.LiveContextCounter`'s reason: every operation is a
/// synchronous decision on a small value, and the recording side runs inside
/// `AsyncHostFunction` bodies the interpreter's promise pump starts on whatever
/// thread it likes.
final class ToolReturnLedger: Sendable {
    /// The most scalar values the ledger compares on either side.
    ///
    /// Two facts set it. The comparison below is quadratic in the worst case —
    /// every value on one side read against every value on the other — so an
    /// unbounded pair of large results could cost a turn's time. And a snippet
    /// that read thousands of distinct values is summarizing rather than
    /// reporting, which is the case this notice is least able to judge. Past
    /// the bound the ledger therefore reports nothing at all, which is the one
    /// direction that cannot make a false claim.
    static let maximumRecordedValues = 512

    /// The notice a snippet gets back when it called `tools.*` and returned a
    /// value carrying nothing those calls returned.
    ///
    /// Written as `MultiTool+Detachment.swift`'s `liveContextCapError` is: the
    /// fact first, then the consequence the model cannot otherwise see, then
    /// the action. The last of the three is what `RepairDirective.closingLine`
    /// puts last for the same reason — it is what the model reads immediately
    /// before deciding what to do next.
    ///
    /// This is the only place the text is written, on `RepairDirective
    /// .closingLine`'s terms: `FoundationModelsMultitoolTests` reads it here
    /// through `@testable import` rather than restating it, so a reword reaches
    /// every assertion that expects it — and, more importantly, every
    /// assertion that expects it to be *absent*, which a copy in a test would
    /// go on satisfying after the reword.
    static let uncarriedReturnNotice = """
        This snippet called tools.* and returned a value carrying nothing those calls returned. \
        Only the returned value reaches you, and a sentence about a result is not the result. \
        Call runCode again and return the values those calls gave you.
        """

    /// Every scalar value the `tools.*` calls of this invocation returned.
    private let recorded = OSAllocatedUnfairLock(initialState: ScalarValues())

    /// Runs one `tools.*` call and records the value it handed back.
    ///
    /// A call that throws records nothing, and that is right rather than a
    /// simplification: a snippet whose calls all failed received no value it
    /// could have carried, so there is nothing for the notice to be about.
    ///
    /// - Parameter call: the `tools.*` binding to run.
    /// - Returns: what `call` returned, unchanged.
    /// - Throws: whatever `call` throws, unchanged.
    func recording(_ call: () async throws -> InterpreterValue) async rethrows -> InterpreterValue {
        let value = try await call()
        recorded.withLock { $0.collect(from: value) }
        return value
    }

    /// The notice this run's rendered result closes with, or `nil` when it
    /// closes with the value alone.
    ///
    /// - Parameter returnValue: the value the snippet returned.
    /// - Returns: ``uncarriedReturnNotice`` when this run called `tools.*`,
    ///   returned text, and that text carries nothing any of those calls
    ///   returned; `nil` in every other case, including every case the ledger
    ///   cannot judge.
    func notice(forReturnValue returnValue: InterpreterValue) -> String? {
        let calls = recorded.withLock { $0 }
        guard calls.canBeCompared else { return nil }

        var returned = ScalarValues()
        returned.collect(from: returnValue)
        // Only a returned *sentence* is the failure this reports. A snippet
        // that computed a number or a flag out of what it read produced no
        // narration to mistake for one, and saying otherwise would be a
        // finding about arithmetic.
        guard returned.canBeCompared, returned.holdsText else { return nil }
        guard !returned.shareAnyText(with: calls) else { return nil }
        return Self.uncarriedReturnNotice
    }
}

/// The scalar values reachable inside one JSON-shaped value, as the text a
/// reader would see, bounded by ``ToolReturnLedger/maximumRecordedValues``.
///
/// Both sides of the comparison are collected the same way, by the same type,
/// so the tool returns and the snippet's own return value can never be read by
/// two different rules.
private struct ScalarValues {
    /// Every scalar's text, lower-cased.
    ///
    /// Lower-cased because a snippet that upper-cased a name it read still
    /// carries that name, and reporting otherwise would be a false claim.
    private(set) var values: Set<String> = []

    /// Whether any collected scalar was a non-empty string.
    ///
    /// The recording side never reads this; the returned side needs it,
    /// because a value holding no text holds no sentence.
    private(set) var holdsText = false

    /// Whether more scalars were reached than the bound admits.
    private(set) var isOverBound = false

    /// Whether this side can take part in a comparison at all: something was
    /// collected, and the bound was not crossed.
    var canBeCompared: Bool { !isOverBound && !values.isEmpty }

    /// Collects every scalar inside `value`, walking arrays and object values.
    ///
    /// Object *keys* are deliberately not collected. A key is the shape of a
    /// result rather than a value a call produced, so a snippet that echoed a
    /// field name back would otherwise read as carrying the result.
    ///
    /// - Parameter value: the JSON-shaped value to walk.
    mutating func collect(from value: InterpreterValue) {
        guard !isOverBound else { return }
        switch value {
        case .null:
            // A null carries nothing, so it is neither recorded nor counted
            // as text.
            break
        case .bool, .number:
            insert(ResultRenderer.serialize(value))
        case .string(let text):
            if !text.isEmpty { holdsText = true }
            insert(text)
        case .array(let elements):
            for element in elements { collect(from: element) }
        case .object(let fields):
            for field in fields.values { collect(from: field) }
        }
    }

    /// Whether any text on this side appears in any text on `other`, in either
    /// direction.
    ///
    /// Containment rather than equality, and no minimum length. A snippet that
    /// formatted a value it read into a sentence carries it, and so does one
    /// that returned a slice of a string it read; asking for a shared run of
    /// some minimum length would make the notice fire on a short value the
    /// snippet really did deliver, and a notice that says a value carries
    /// nothing when it carries something is the one outcome no reword can
    /// repair.
    ///
    /// - Parameter other: the values to read against.
    /// - Returns: `true` when the two sides share text.
    func shareAnyText(with other: ScalarValues) -> Bool {
        // The equal-value case is the common one and answers by hashing, so it
        // is asked first and the scan below runs only when it does not.
        guard values.isDisjoint(with: other.values) else { return true }
        for text in values where other.values.contains(where: { text.contains($0) || $0.contains(text) }) {
            return true
        }
        return false
    }

    /// Records one scalar's text, or marks the bound crossed.
    ///
    /// - Parameter text: the scalar's text.
    private mutating func insert(_ text: String) {
        // An empty string is inside every other string, so admitting one would
        // silence the notice for every run that reached one.
        guard !text.isEmpty else { return }
        guard values.count < ToolReturnLedger.maximumRecordedValues else {
            isOverBound = true
            return
        }
        values.insert(text.lowercased())
    }
}
