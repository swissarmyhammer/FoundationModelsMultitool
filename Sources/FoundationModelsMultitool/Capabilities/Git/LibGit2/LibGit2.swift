// `LibGit2` — the start call and the error check of the libgit2 C API.
//
// git.md § "Decisions", item 10: one internal Swift layer in
// `Capabilities/Git/LibGit2/` holds all the C calls of the git capability. It
// calls `git_libgit2_init` one time, it owns each C pointer, and it changes
// each negative return code into a Swift error with the text of
// `git_error_last`. No verb calls the C API directly.
//
// `Marketplace/Git/LibGit2Transport.swift` in FoundationModelsExtras is the
// model for the start call and for the error text. Both packages link the same
// `swift-libgit2` package, thus both read one libgit2 in one process.
//
// The verb tasks add their own functions to this layer, beside
// `LibGit2Repository`.

import libgit2

/// The start call and the error check that each call of the `LibGit2` layer
/// uses.
///
/// A namespace, not a value: libgit2 keeps its own state for the process, and
/// this type only starts it and reads its errors.
enum LibGit2 {

    /// Starts libgit2 one time for the process. The value is the start count,
    /// or a negative libgit2 error code.
    ///
    /// A `static let` is initialized one time, and the runtime makes the
    /// initialization safe across threads. Thus `git_libgit2_init` runs one
    /// time, however many calls reach ``start()`` first.
    private static let libraryStartCount: Int32 = git_libgit2_init()

    /// The text of a ``LibGit2Error`` when libgit2 recorded no error text.
    ///
    /// The header of libgit2 1.9 says that `git_error_last()` is never NULL.
    /// The guard stays, thus a later libgit2 that breaks that promise gives
    /// this text and not a crash.
    private static let missingErrorText = "libgit2 gave no error text"

    /// The value that a libgit2 test function returns for true, for example
    /// `git_oid_is_zero`, `git_repository_head_unborn`, and
    /// `git_reference_is_branch`.
    static let trueValue: Int32 = 1

    /// Starts libgit2, or throws when it cannot start.
    ///
    /// Each entry point of the layer calls this before its first libgit2 call.
    ///
    /// - Throws: ``LibGit2Error`` when `git_libgit2_init` failed.
    static func start() throws(LibGit2Error) {
        try check(libraryStartCount)
    }

    /// Throws a ``LibGit2Error`` when `status` is a libgit2 error code.
    ///
    /// Read the error text on the same thread, directly after the failed
    /// call: libgit2 keeps the last error for each thread.
    ///
    /// - Parameter status: The code that the libgit2 call returned. A value
    ///   below `GIT_OK` is an error.
    /// - Throws: ``LibGit2Error`` with `status` and the text of the last
    ///   libgit2 error.
    static func check(_ status: Int32) throws(LibGit2Error) {
        guard status < GIT_OK.rawValue else { return }
        throw LibGit2Error(code: status, message: lastErrorMessage())
    }

    /// Runs one libgit2 call that makes an object, and gives the object.
    ///
    /// - Parameter call: The libgit2 call. It writes the object into its
    ///   argument, and returns the libgit2 status.
    /// - Returns: The object. The caller owns it and frees it.
    /// - Throws: ``LibGit2Error`` when the call fails, or when it gives no
    ///   object.
    static func makeHandle(_ call: (_ handle: inout OpaquePointer?) -> Int32) throws(LibGit2Error) -> OpaquePointer {
        var handle: OpaquePointer?
        try check(call(&handle))
        guard let handle else {
            throw LibGit2Error(code: GIT_ERROR.rawValue, message: lastErrorMessage())
        }
        return handle
    }

    /// The text of the last libgit2 error on this thread.
    private static func lastErrorMessage() -> String {
        guard let error = git_error_last(), let message = error.pointee.message else {
            return missingErrorText
        }
        return String(cString: message)
    }
}
