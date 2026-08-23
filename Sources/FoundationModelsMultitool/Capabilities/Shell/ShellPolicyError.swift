// `ShellPolicyError` — the refusals of the shell policy layer.
//
// The layer refuses to write a remembered answer in some conditions. Each one
// of those conditions is a case here. The store throws them, and the policy
// that stands in front of the store adds its own cases as that policy arrives.
//
// The type stands in a file of its own, and not inside `ShellDecisionStore`,
// because the store and the policy both throw it.

import Foundation

/// A refusal of the shell policy layer.
public enum ShellPolicyError: Error, Equatable, CustomStringConvertible, Sendable {
    /// The scope that the caller named has no file in the layering of this
    /// store. A `.project` answer outside a git working tree is one example.
    case noStorageForScope(ShellDecisionStore.Scope)

    /// The `decisions.yaml` of the layer is there, but it does not parse. To
    /// write to it means to write over text that the user typed.
    ///
    /// To record an answer is a read-modify-write. To read a file that does not
    /// parse as an empty file replaces each entry in it — a `reject_always`
    /// included — with one new entry. It also stops the warning that reported
    /// the problem.
    case unreadableDecisionsFile(URL)

    /// Text that tells a person why the layer refused.
    public var description: String {
        switch self {
        case .noStorageForScope(let scope):
            return "No \(scope) layer is configured to store a decision in"
        case .unreadableDecisionsFile(let url):
            return """
                Refusing to overwrite the remembered decisions at \(url.path): \
                the file could not be parsed. Fix or remove it first.
                """
        }
    }
}
