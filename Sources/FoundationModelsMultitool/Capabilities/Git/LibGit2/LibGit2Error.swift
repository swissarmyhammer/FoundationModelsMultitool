// `LibGit2Error` — a failed libgit2 call, as a Swift error.
//
// git.md § "Decisions", item 10: the `LibGit2` layer changes each negative
// return code into a Swift error with the text of `git_error_last`. A verb
// changes that error into a `correction` in its result when the model can
// correct it (an unknown ref, an unknown path), and throws only for a fault
// that the model cannot correct. Thus the error keeps the code, and the verb
// can tell the two apart.

import libgit2

/// A libgit2 call that returned an error code.
struct LibGit2Error: Error, Equatable, Sendable, CustomStringConvertible {

    /// The negative code that the libgit2 call returned, for example
    /// `GIT_ENOTFOUND`.
    let code: Int32

    /// The text of the last libgit2 error, read on the thread of the failed
    /// call.
    ///
    /// For an unknown path, the text names only the first path part that is
    /// missing (git.md § "Spike result", "Error text"). Thus a verb that
    /// shows this text for an unknown path also names the whole path itself.
    let message: String

    /// Whether libgit2 did not find what the call asked for
    /// (`GIT_ENOTFOUND`): no repository above a folder, an unknown ref, or an
    /// unknown path.
    var isNotFound: Bool {
        code == GIT_ENOTFOUND.rawValue
    }

    /// The libgit2 text, with the code after it.
    var description: String {
        "\(message) (libgit2 code \(code))"
    }
}
